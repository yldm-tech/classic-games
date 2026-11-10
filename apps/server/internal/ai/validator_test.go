package ai

import (
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/yldm-tech/classic-games/packages/dsl"
)

func newValidator(t *testing.T) *dsl.SchemaValidator {
	t.Helper()
	// apps/server/internal/ai → 仓库根是 4 层 → packages/schemas
	return dsl.NewSchemaValidator(filepath.Join("..", "..", "..", "..", "packages", "schemas"))
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

func TestMinimalValidator_AcceptsEveryBuiltInRuntime(t *testing.T) {
	for _, name := range []string{"shooter", "survivor", "tower_defense"} {
		dsl := loadDSL(t, repoFile(t, "apps", "client", "runtime", name, "baseline.dsl.json"))
		if err := (MinimalValidator{}).Validate(name+"@1.0.0", dsl); err != nil {
			t.Errorf("MinimalValidator 应支持 %s: %v", name, err)
		}
	}
}

// SchemaValidator 满足 Validator 接口,可直接喂给 Service。
func TestSchemaValidator_WiresIntoService(t *testing.T) {
	v := newValidator(t)
	ops := parseOps(t, forkPatchJSON)
	prov := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{Ops: ops, Model: "fake"}, nil
	}}
	svc := NewService(prov, v, nil, 2)
	resp, err := svc.GenerateMod(t.Context(), baseReq(t))
	if err != nil {
		t.Fatalf("用真 schema 校验器编排应成功, 实际 %v", err)
	}
	if resp.NewDSL["player"].(map[string]any)["sprite"] != "cat" {
		t.Error("new_dsl 未生效")
	}
}
