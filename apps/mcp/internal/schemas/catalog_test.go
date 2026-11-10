package schemas

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// repoPath joins parts onto the repository root, four levels above this package (apps/mcp/internal/schemas).
func repoPath(parts ...string) string {
	return filepath.Join(append([]string{"..", "..", "..", ".."}, parts...)...)
}

func openRepoCatalog(t *testing.T) *Catalog {
	t.Helper()
	catalog, err := Open(repoPath("packages", "schemas"))
	if err != nil {
		t.Fatalf("open repository schemas: %v", err)
	}
	return catalog
}

func loadBaseline(t *testing.T, name string) map[string]any {
	t.Helper()
	content, err := os.ReadFile(repoPath("apps", "client", "runtime", name, "baseline.dsl.json"))
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(content, &document); err != nil {
		t.Fatal(err)
	}
	return document
}

func TestOpenRepositorySchemas(t *testing.T) {
	catalog := openRepoCatalog(t)
	if want := []string{"shooter@1.0.0", "survivor@1.0.0", "tower_defense@1.0.0"}; !slices.Equal(catalog.Refs(), want) {
		t.Fatalf("refs = %v, want %v", catalog.Refs(), want)
	}
	runtime, ok := catalog.Lookup("tower_defense@1.0.0")
	if !ok || runtime.Name != "tower_defense" || runtime.Version != "1.0.0" || runtime.Title == "" || !json.Valid(runtime.Schema) {
		t.Errorf("tower_defense@1.0.0 = %+v (found %v)", runtime, ok)
	}
	if !slices.IsSorted(runtime.Sections) || !slices.Contains(runtime.Sections, "towers") || !slices.Contains(runtime.Required, "waves") {
		t.Errorf("sections = %v, required = %v", runtime.Sections, runtime.Required)
	}
	if _, ok := catalog.Lookup("tower_defense"); ok {
		t.Error("Lookup accepted a bare runtime name")
	}
}

func TestOpenErrors(t *testing.T) {
	if _, err := Open(filepath.Join(t.TempDir(), "missing")); err == nil {
		t.Error("Open of a missing directory succeeded")
	}

	empty := t.TempDir()
	if err := os.WriteFile(filepath.Join(empty, "notes.json"), []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(empty); err == nil || !strings.Contains(err.Error(), "holds no") {
		t.Errorf("Open of a directory without schemas: %v", err)
	}

	broken := t.TempDir()
	if err := os.WriteFile(filepath.Join(broken, "shooter-1.0.0.schema.json"), []byte("not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(broken); err == nil || !strings.Contains(err.Error(), "shooter-1.0.0.schema.json") {
		t.Errorf("Open of a directory with a broken schema: %v", err)
	}
}

func TestSplitFileName(t *testing.T) {
	cases := map[string]struct {
		name, version string
		ok            bool
	}{
		"shooter-1.0.0.schema.json":       {"shooter", "1.0.0", true},
		"tower_defense-1.0.0.schema.json": {"tower_defense", "1.0.0", true},
		"tower-defense-2.1.0.schema.json": {"tower-defense", "2.1.0", true},
		"shooter-1.0.0-rc.1.schema.json":  {"shooter", "1.0.0-rc.1", true},
		"shooter.schema.json":             {"", "", false},
		"-1.0.0.schema.json":              {"", "", false},
		"shooter-1.0.0.json":              {"", "", false},
		"README.md":                       {"", "", false},
	}
	for file, want := range cases {
		name, version, ok := splitFileName(file)
		if name != want.name || version != want.version || ok != want.ok {
			t.Errorf("splitFileName(%q) = %q, %q, %v; want %q, %q, %v", file, name, version, ok, want.name, want.version, want.ok)
		}
	}
}

func TestRefOf(t *testing.T) {
	if ref, ok := RefOf(loadBaseline(t, "survivor")); !ok || ref != "survivor@1.0.0" {
		t.Errorf("RefOf(survivor baseline) = %q, %v", ref, ok)
	}
	for name, document := range map[string]map[string]any{
		"no meta":       {},
		"meta not map":  {"meta": "shooter"},
		"no version":    {"meta": map[string]any{"runtime": "shooter"}},
		"number as ref": {"meta": map[string]any{"runtime": 1, "runtime_version": "1.0.0"}},
	} {
		if ref, ok := RefOf(document); ok {
			t.Errorf("%s: RefOf = %q, want not ok", name, ref)
		}
	}
}

func TestValidate(t *testing.T) {
	catalog := openRepoCatalog(t)
	for _, name := range []string{"shooter", "survivor", "tower_defense"} {
		used, violations, err := catalog.Validate(name+"@1.0.0", loadBaseline(t, name))
		if err != nil || violations != nil || used != name+"@1.0.0" {
			t.Errorf("%s baseline: checked against %q, violations %v, error %v; want a valid document", name, used, violations, err)
		}
	}

	document := loadBaseline(t, "shooter")
	document["player"].(map[string]any)["weapon"] = map[string]any{"type": "laser", "damage": 9000, "width": 1}
	document["enemies"].(map[string]any)["Bad Key!"] = map[string]any{"type": "dog", "behavior": "chase", "count": 1, "hp": 1}
	_, violations, err := catalog.Validate("shooter@1.0.0", document)
	if err != nil {
		t.Fatalf("Validate: %v", err)
	}
	// The weapon is a union tagged by its type. Only the laser alternative is reported, at the field that is out of range, instead of one group of violations per weapon type.
	want := []Violation{
		{Path: "", Message: `object key "Bad Key!" is not allowed: 'Bad Key!' does not match pattern '^[a-z0-9_]{1,32}$' (the validator does not report which object holds the key)`},
		{Path: "/player/weapon/damage", Message: "maximum: got 9,000, want 200"},
	}
	if !slices.Equal(violations, want) {
		t.Errorf("violations = %+v\nwant %+v", violations, want)
	}

	// An unknown tag matches no alternative; the report stays on the tag instead of listing every field of every weapon.
	document = loadBaseline(t, "shooter")
	document["player"].(map[string]any)["weapon"] = map[string]any{"type": "plasma", "damage": 20, "fire_rate": 5}
	_, violations, err = catalog.Validate("shooter@1.0.0", document)
	if err != nil {
		t.Fatalf("Validate: %v", err)
	}
	if len(violations) == 0 {
		t.Fatal("an unknown weapon type produced no violations")
	}
	for _, violation := range violations {
		if violation.Path != "/player/weapon/type" {
			t.Errorf("unknown weapon type: unexpected violation %+v", violation)
		}
	}

	if _, _, err := catalog.Validate("racing@1.0.0", document); err == nil || !strings.Contains(err.Error(), `no schema for runtime "racing@1.0.0"`) || !strings.Contains(err.Error(), "shooter@1.0.0, survivor@1.0.0, tower_defense@1.0.0") {
		t.Errorf("unknown runtime: %v, want an error listing the available schemas", err)
	}
	if _, _, err := catalog.Validate("../etc@1.0.0", document); err == nil || !strings.Contains(err.Error(), "not a valid runtime ref") {
		t.Errorf("a runtime ref with a path traversal: %v, want it refused as an invalid ref", err)
	}
}

// The schema a client is shown and the schema validation enforces are the bytes read by Open, whatever happens to the files afterwards.
func TestSchemasAreReadOnceAtOpen(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"shooter", "survivor"} {
		content, err := os.ReadFile(repoPath("packages", "schemas", name+"-1.0.0.schema.json"))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, name+"-1.0.0.schema.json"), content, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	catalog, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	// The files change before the first validation of either runtime: one is replaced, one is removed, one is new.
	if err := os.WriteFile(filepath.Join(dir, "survivor-1.0.0.schema.json"), []byte(`{"type":"object","required":["only_in_new_file"]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(dir, "shooter-1.0.0.schema.json")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "racing-1.0.0.schema.json"), []byte(`{"type":"object"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"shooter", "survivor"} {
		if _, violations, err := catalog.Validate(name+"@1.0.0", loadBaseline(t, name)); err != nil || violations != nil {
			t.Errorf("%s baseline after the files changed: violations %v, error %v; want the schema read at Open", name, violations, err)
		}
	}
	if _, _, err := catalog.Validate("racing@1.0.0", map[string]any{}); err == nil {
		t.Error("a schema file added after Open was used for validation although the catalog does not list it")
	}
}

func TestOpenRejectsASchemaThatDoesNotCompile(t *testing.T) {
	for name, content := range map[string]string{
		"unknown type":  `{"type":"no-such-type"}`,
		"external ref":  `{"type":"object","properties":{"x":{"$ref":"file:///etc/hosts"}}}`,
		"dangling ref":  `{"type":"object","properties":{"x":{"$ref":"#/$defs/missing"}}}`,
		"bad file name": `{"type":"object"}`,
	} {
		dir := t.TempDir()
		file := "shooter-1.0.0.schema.json"
		if name == "bad file name" {
			file = "my runtime-1.0.0.schema.json"
		}
		if err := os.WriteFile(filepath.Join(dir, file), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := Open(dir); err == nil || !strings.Contains(err.Error(), file) {
			t.Errorf("%s: Open = %v, want an error naming %s", name, err, file)
		}
	}
}

func TestIsSchemaFile(t *testing.T) {
	for file, want := range map[string]bool{"shooter-1.0.0.schema.json": true, "user.schema.json": false, "shooter-1.0.0.json": false, "README.md": false} {
		if got := IsSchemaFile(file); got != want {
			t.Errorf("IsSchemaFile(%q) = %v, want %v", file, got, want)
		}
	}
}

func TestValidateLegacyShooter(t *testing.T) {
	// shooter@0.x documents are migrated by github.com/yldm-tech/classic-games/packages/dsl before validation, so the catalog accepts them without a 0.x schema file.
	legacy := map[string]any{
		"meta":    map[string]any{"runtime": "shooter", "runtime_version": "0.9.0"},
		"player":  map[string]any{"sprite": "plane", "hp": 100, "speed": 10, "weapon": "straight"},
		"enemies": []any{map[string]any{"id": "dog_1", "type": "dog", "behavior": "chase", "count": 3, "hp": 10, "speed": 5}},
		"stage":   map[string]any{"background": "space", "difficulty": 1, "duration": 60},
	}
	used, violations, err := openRepoCatalog(t).Validate("shooter@0.9.0", legacy)
	if err != nil {
		t.Fatalf("Validate legacy shooter: %v", err)
	}
	// The schema that was really used is the one the document was migrated to.
	if used != "shooter@1.0.0" {
		t.Errorf("legacy shooter was reported as checked against %q, want shooter@1.0.0", used)
	}
	for _, violation := range violations {
		t.Errorf("legacy shooter violation at %q: %s", violation.Path, violation.Message)
	}
}

func TestPointer(t *testing.T) {
	if got := pointer([]string{"enemies", "a/b", "c~d"}); got != "/enemies/a~1b/c~0d" {
		t.Errorf("pointer = %q, want /enemies/a~1b/c~0d", got)
	}
	if got := pointer(nil); got != "" {
		t.Errorf("pointer(nil) = %q, want the empty root pointer", got)
	}
}
