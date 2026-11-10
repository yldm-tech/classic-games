package dsl

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/santhosh-tekuri/jsonschema/v6"
)

// packages/dsl is two levels below the repository root; the schemas and the client baselines are read from their real locations so both sides test the same files.
func repoFile(t *testing.T, parts ...string) []byte {
	t.Helper()
	p := filepath.Join(append([]string{"..", ".."}, parts...)...)
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("读 %s 失败: %v", p, err)
	}
	return b
}

func loadDSL(t *testing.T, b []byte) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("解析 DSL 失败: %v", err)
	}
	return m
}

func newValidator(t *testing.T) *SchemaValidator {
	t.Helper()
	return NewSchemaValidator(filepath.Join("..", "..", "packages", "schemas"))
}

func mutate(t *testing.T, base map[string]any, fn func(map[string]any)) map[string]any {
	t.Helper()
	b, _ := json.Marshal(base)
	var c map[string]any
	if err := json.Unmarshal(b, &c); err != nil {
		t.Fatal(err)
	}
	fn(c)
	return c
}

func TestSchemaValidator_AcceptsBaselineAndGolden(t *testing.T) {
	v := newValidator(t)
	for _, f := range []string{"baseline.dsl.json", "testdata/fork_expected.dsl.json"} {
		dsl := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", filepath.FromSlash(f)))
		if err := v.Validate("shooter@1.0.0", dsl); err != nil {
			t.Errorf("%s 应通过 schema 校验, 实际 %v", f, err)
		}
	}
}

func TestSchemaValidator_AcceptsSurvivorBaseline(t *testing.T) {
	v := newValidator(t)
	dsl := loadDSL(t, repoFile(t, "apps", "client", "runtime", "survivor", "baseline.dsl.json"))
	if err := v.Validate("survivor@1.0.0", dsl); err != nil {
		t.Fatalf("survivor baseline 应通过 schema 校验: %v", err)
	}
	bad := mutate(t, dsl, func(d map[string]any) { d["weapon"].(map[string]any)["cooldown"] = 0 })
	if err := v.Validate("survivor@1.0.0", bad); err == nil {
		t.Fatal("cooldown=0 应被 survivor schema 拒绝")
	}
}

func TestSchemaValidator_AcceptsTowerDefenseBaseline(t *testing.T) {
	v := newValidator(t)
	dsl := loadDSL(t, repoFile(t, "apps", "client", "runtime", "tower_defense", "baseline.dsl.json"))
	if err := v.Validate("tower_defense@1.0.0", dsl); err != nil {
		t.Fatalf("tower defense baseline 应通过 schema 校验: %v", err)
	}
	bad := mutate(t, dsl, func(d map[string]any) { d["path"].(map[string]any)["points"] = []any{[]any{0, 0}} })
	if err := v.Validate("tower_defense@1.0.0", bad); err == nil {
		t.Fatal("单点路径应被 tower defense schema 拒绝")
	}
}

func TestSchemaValidator_RejectsInvalid(t *testing.T) {
	v := newValidator(t)
	base := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))

	cases := map[string]func(map[string]any){
		"hp 越界": func(d map[string]any) {
			d["player"].(map[string]any)["hp"] = 9999
		},
		"未知 sprite": func(d map[string]any) {
			d["player"].(map[string]any)["sprite"] = "pikachu"
		},
		"laser 缺 width": func(d map[string]any) {
			d["player"].(map[string]any)["weapon"] = map[string]any{"type": "laser", "damage": 20}
		},
		"boss enabled 缺 skill": func(d map[string]any) {
			d["boss"] = map[string]any{"enabled": true, "sprite": "mecha", "hp": 2000}
		},
		"enemies 写成数组": func(d map[string]any) {
			d["enemies"] = []any{map[string]any{"type": "dog", "behavior": "chase", "count": 5, "hp": 10}}
		},
		"未知顶层字段": func(d map[string]any) {
			d["cheats"] = true
		},
	}
	for name, fn := range cases {
		bad := mutate(t, base, fn)
		if err := v.Validate("shooter@1.0.0", bad); err == nil {
			t.Errorf("反例「%s」应被 schema 拒绝, 却通过了", name)
		}
	}
}

// name/version 会拼进 schema 文件路径;带 .. 或路径分隔符的入参必须被边界净化挡掉,
// 而不是去读文件,且错误信息不得回显解析后的路径(/ai/validate 无鉴权,attacker 可控 runtime)。
func TestSchemaValidator_RejectsPathTraversal(t *testing.T) {
	v := newValidator(t)
	base := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	for _, ref := range []string{
		"shooter@../../../../etc/passwd",
		"shooter@..%2f..%2f",
		"../../secret@1.0.0",
		"shooter@1.0.0/../../x",
		"shooter@a/b",
	} {
		err := v.Validate(ref, base)
		if err == nil {
			t.Errorf("穿越/非法 ref %q 应被拒绝", ref)
			continue
		}
		if strings.Contains(err.Error(), v.schemaDir) || strings.Contains(err.Error(), "schemas") {
			t.Errorf("ref %q 的错误信息泄露了路径: %v", ref, err)
		}
	}
}

func TestSchemaValidator_UnknownVersion(t *testing.T) {
	v := newValidator(t)
	base := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	if err := v.Validate("shooter@9.9.9", base); err == nil {
		t.Error("不存在的版本应报错(找不到 schema 文件)")
	}
}

func TestSchemaValidator_MigratesLegacyV0BeforeValidation(t *testing.T) {
	v := newValidator(t)
	legacy := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	legacy["meta"].(map[string]any)["runtime_version"] = "0.9.0"
	legacy["player"].(map[string]any)["weapon"] = "spread"
	enemyMap := legacy["enemies"].(map[string]any)
	legacy["enemies"] = []any{map[string]any{"id": "dog_1", "type": "dog", "behavior": "chase", "count": 20, "hp": 30, "speed": 8}}
	_ = enemyMap
	legacy["drops"] = []any{map[string]any{"id": "heal_1", "type": "heal", "rate": 0.1}}
	if err := v.Validate("shooter@0.9.0", legacy); err != nil {
		t.Fatalf("legacy 应迁移后通过: %v", err)
	}
}

// A schema is data from disk: a "$ref" must never make the validator open another local file or fetch a URL.
func TestSchemaValidator_RefusesExternalRefs(t *testing.T) {
	secret := filepath.Join(t.TempDir(), "secret.json")
	if err := os.WriteFile(secret, []byte(`{"type":"object","required":["leaked_marker"]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	for name, ref := range map[string]string{
		"file":     "file://" + filepath.ToSlash(secret),
		"relative": "other.schema.json",
		"http":     "http://127.0.0.1:1/schema.json",
		"https":    "https://example.invalid/schema.json",
	} {
		dir := t.TempDir()
		schema := `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"x":{"$ref":"` + ref + `"}}}`
		if err := os.WriteFile(filepath.Join(dir, "evil-1.0.0.schema.json"), []byte(schema), 0o600); err != nil {
			t.Fatal(err)
		}
		err := NewSchemaValidator(dir).Validate("evil@1.0.0", map[string]any{"x": map[string]any{}})
		if err == nil {
			t.Errorf("%s ref: got nil, want a compile error", name)
			continue
		}
		// LoadURLError does not unwrap, so its cause is checked directly.
		var loadErr *jsonschema.LoadURLError
		if !errors.As(err, &loadErr) {
			t.Errorf("%s ref: got %v, want a load error", name, err)
		} else if _, refused := loadErr.Err.(*jsonschema.UnsupportedURLSchemeError); !refused {
			t.Errorf("%s ref: got cause %v, want an unsupported URL scheme error", name, loadErr.Err)
		}
		if strings.Contains(err.Error(), "leaked_marker") || strings.Contains(err.Error(), "missing property") {
			t.Errorf("%s ref: the referenced file was read: %v", name, err)
		}
	}
}

func TestSchemaValidator_ClassifiesRefErrors(t *testing.T) {
	v := newValidator(t)
	base := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	if err := v.Validate("racing@1.0.0", base); !errors.Is(err, ErrUnknownRuntime) || err.Error() != "找不到 racing@1.0.0 的 schema" {
		t.Errorf("unknown runtime: got %v", err)
	}
	if err := v.Validate("shooter@../x", base); !errors.Is(err, ErrInvalidRuntimeRef) || err.Error() != `非法 runtime ref: "shooter@../x"` {
		t.Errorf("invalid ref: got %v", err)
	}
}

// ValidateResolved names the schema that was really used, which is not the requested ref for a migrated legacy document.
func TestSchemaValidator_ValidateResolvedReportsTheSchemaUsed(t *testing.T) {
	v := newValidator(t)
	base := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	if ref, err := v.ValidateResolved("shooter@1.0.0", base); err != nil || ref != "shooter@1.0.0" {
		t.Errorf("current ref: got %q, %v", ref, err)
	}
	if ref, err := v.ValidateResolved("shooter@0.9.0", base); err != nil || ref != "shooter@1.0.0" {
		t.Errorf("legacy ref: got %q, %v; want shooter@1.0.0", ref, err)
	}
	broken := mutate(t, base, func(m map[string]any) { delete(m, "player") })
	if ref, err := v.ValidateResolved("shooter@0.1.0", broken); err == nil || ref != "shooter@1.0.0" {
		t.Errorf("invalid legacy document: got %q, %v; want violations against shooter@1.0.0", ref, err)
	}
	if ref, err := v.ValidateResolved("racing@1.0.0", base); err == nil || ref != "" {
		t.Errorf("unknown runtime: got %q, %v", ref, err)
	}
}

// A registered-only validator enforces the bytes it was given and never looks at the disk.
func TestSchemaValidator_RegisteredOnly(t *testing.T) {
	v := NewRegisteredSchemaValidator()
	base := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	if err := v.Validate("shooter@1.0.0", base); !errors.Is(err, ErrUnknownRuntime) {
		t.Fatalf("before Register: got %v, want ErrUnknownRuntime", err)
	}
	if err := v.Register("shooter@1.0.0", repoFile(t, "packages", "schemas", "shooter-1.0.0.schema.json")); err != nil {
		t.Fatalf("Register: %v", err)
	}
	if err := v.Validate("shooter@1.0.0", base); err != nil {
		t.Errorf("after Register: %v", err)
	}
	if err := v.Validate("shooter@1.0.0", mutate(t, base, func(m map[string]any) { delete(m, "player") })); err == nil {
		t.Error("after Register: a document without player must be rejected")
	}
	if err := v.Validate("survivor@1.0.0", base); !errors.Is(err, ErrUnknownRuntime) {
		t.Errorf("unregistered runtime: got %v, want ErrUnknownRuntime", err)
	}
	if err := v.Register("shooter@2.0.0", []byte(`{"type":"no-such-type"}`)); err == nil {
		t.Error("Register: a schema that does not compile must be rejected")
	}
	if err := v.Register("../x@1.0.0", []byte(`{}`)); !errors.Is(err, ErrInvalidRuntimeRef) {
		t.Errorf("Register with a bad ref: got %v", err)
	}
}
