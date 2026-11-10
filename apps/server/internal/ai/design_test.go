package ai

import (
	"context"
	"reflect"
	"testing"
	"time"
)

func runtimeBaseline(t *testing.T, name string) map[string]any {
	t.Helper()
	return loadDSL(t, repoFile(t, "apps", "client", "runtime", name, "baseline.dsl.json"))
}

func TestAutoBalanceTunesEveryRuntimeAndKeepsSchemaValid(t *testing.T) {
	svc := NewService(StubProvider{}, newValidator(t), nil, 0)
	for _, runtime := range []string{"shooter", "survivor", "tower_defense"} {
		t.Run(runtime, func(t *testing.T) {
			before := runtimeBaseline(t, runtime)
			response, err := svc.AutoBalance(BalanceRequest{
				Runtime: runtime + "@1.0.0", CurrentDSL: before, TargetDifficulty: 5,
			})
			if err != nil {
				t.Fatal(err)
			}
			if len(response.DSLPatch) < 3 || reflect.DeepEqual(response.NewDSL, before) {
				t.Fatalf("%s did not tune multiple parameters: %+v", runtime, response.DSLPatch)
			}
			if response.Metrics.Before <= 0 || response.Metrics.After <= response.Metrics.Before {
				t.Fatalf("%s metrics = %+v", runtime, response.Metrics)
			}
			if err := svc.Validate(runtime+"@1.0.0", response.NewDSL); err != nil {
				t.Fatalf("balanced DSL invalid: %v", err)
			}
		})
	}
}

type stubSigner struct{}

func (stubSigner) Mint(now time.Time, ttl time.Duration) string { return "signed.token" }

// AutoBalance 是确定性、无鉴权、不调用 LLM 的路径,即便配置了签发器也不应签发溯源令牌。回归守卫 C3。
func TestAutoBalanceNeverMintsProvenance(t *testing.T) {
	svc := NewService(StubProvider{}, newValidator(t), nil, 0)
	svc.SetProvenanceSigner(stubSigner{})
	resp, err := svc.AutoBalance(BalanceRequest{
		Runtime: "shooter@1.0.0", CurrentDSL: runtimeBaseline(t, "shooter"), TargetDifficulty: 3,
	})
	if err != nil {
		t.Fatal(err)
	}
	if resp.Provenance != "" {
		t.Fatalf("确定性 AutoBalance 不应签发 AI 溯源令牌, got %q", resp.Provenance)
	}
}

func TestAutoBalanceRejectsInvalidDifficultyAndIsDeterministic(t *testing.T) {
	svc := NewService(StubProvider{}, newValidator(t), nil, 0)
	request := BalanceRequest{Runtime: "survivor@1.0.0", CurrentDSL: runtimeBaseline(t, "survivor"), TargetDifficulty: 3}
	first, err := svc.AutoBalance(request)
	if err != nil {
		t.Fatal(err)
	}
	second, err := svc.AutoBalance(request)
	if err != nil || !reflect.DeepEqual(first.NewDSL, second.NewDSL) {
		t.Fatalf("non-deterministic balance: %v", err)
	}
	request.TargetDifficulty = 0
	if _, err = svc.AutoBalance(request); err != ErrInvalidDifficulty {
		t.Fatalf("difficulty error = %v", err)
	}
}

func TestGenerateStructureAddsSeededValidWavesForEveryRuntime(t *testing.T) {
	svc := NewService(StubProvider{}, newValidator(t), nil, 0)
	for _, runtime := range []string{"shooter", "survivor", "tower_defense"} {
		t.Run(runtime, func(t *testing.T) {
			before := runtimeBaseline(t, runtime)
			response, err := svc.GenerateStructure(context.Background(), StructureRequest{
				Runtime: runtime + "@1.0.0", CurrentDSL: before, Prompt: "冰霜夜袭", Count: 3, Difficulty: 4,
			})
			if err != nil {
				t.Fatal(err)
			}
			if len(response.GeneratedKeys) != 3 || len(response.DSLPatch) != 3 {
				t.Fatalf("generated = %+v patch = %+v", response.GeneratedKeys, response.DSLPatch)
			}
			if err := svc.Validate(runtime+"@1.0.0", response.NewDSL); err != nil {
				t.Fatalf("generated DSL invalid: %v", err)
			}
			repeated, err := svc.GenerateStructure(context.Background(), StructureRequest{
				Runtime: runtime + "@1.0.0", CurrentDSL: before, Prompt: "冰霜夜袭", Count: 3, Difficulty: 4,
			})
			if err != nil || !reflect.DeepEqual(response.NewDSL, repeated.NewDSL) {
				t.Fatalf("seeded generation is not deterministic: %v", err)
			}
		})
	}
}

func TestGenerateStructureRejectsUnsupportedBounds(t *testing.T) {
	svc := NewService(StubProvider{}, newValidator(t), nil, 0)
	_, err := svc.GenerateStructure(context.Background(), StructureRequest{
		Runtime: "survivor@1.0.0", CurrentDSL: runtimeBaseline(t, "survivor"), Prompt: "x", Count: 0, Difficulty: 3,
	})
	if err != ErrInvalidStructure {
		t.Fatalf("structure error = %v", err)
	}
}

func TestGenerateStructureRepeatedPromptAppendsInsteadOfOverwriting(t *testing.T) {
	svc := NewService(StubProvider{}, newValidator(t), nil, 0)
	base := runtimeBaseline(t, "survivor")
	first, err := svc.GenerateStructure(context.Background(), StructureRequest{Runtime: "survivor@1.0.0", CurrentDSL: base, Prompt: "冰霜夜袭", Count: 3, Difficulty: 4})
	if err != nil {
		t.Fatal(err)
	}
	second, err := svc.GenerateStructure(context.Background(), StructureRequest{Runtime: "survivor@1.0.0", CurrentDSL: first.NewDSL, Prompt: "冰霜夜袭", Count: 3, Difficulty: 4})
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range second.GeneratedKeys {
		for _, old := range first.GeneratedKeys {
			if key == old {
				t.Fatalf("reused structural key %s", key)
			}
		}
	}
	if len(object(second.NewDSL["waves"])) != len(object(base["waves"]))+6 {
		t.Fatalf("repeated generation overwrote waves: %d", len(object(second.NewDSL["waves"])))
	}
}

func TestGenerateStructureUsesProviderAndEnforcesStructuralResult(t *testing.T) {
	provider := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{Model: "llm-test", BalanceHint: "semantic wave", Ops: parseOps(t, `[{"op":"add","path":"/waves/llm_wave","value":{"enemy":"ghost","start":12,"interval":0.8,"count":20,"hp":30,"speed":90,"xp":4}}]`)}, nil
	}}
	svc := NewService(provider, newValidator(t), nil, 1)
	response, err := svc.GenerateStructure(context.Background(), StructureRequest{Runtime: "survivor@1.0.0", CurrentDSL: runtimeBaseline(t, "survivor"), Prompt: "幽灵在中段包围玩家", Count: 1, Difficulty: 3})
	if err != nil {
		t.Fatal(err)
	}
	if provider.calls != 1 || response.Model != "llm-test" || len(response.GeneratedKeys) != 1 || response.GeneratedKeys[0] != "llm_wave" {
		t.Fatalf("provider structure not used: calls=%d response=%+v", provider.calls, response)
	}
}

func TestGenerateStructureRejectsProviderThatMutatesExistingContent(t *testing.T) {
	provider := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{Model: "llm-test", Ops: parseOps(t, `[
			{"op":"replace","path":"/hero/hp","value":999},
			{"op":"add","path":"/waves/llm_wave","value":{"enemy":"ghost","start":12,"interval":0.8,"count":20,"hp":30,"speed":90,"xp":4}}
		]`)}, nil
	}}
	svc := NewService(provider, newValidator(t), nil, 0)
	_, err := svc.GenerateStructure(context.Background(), StructureRequest{Runtime: "survivor@1.0.0", CurrentDSL: runtimeBaseline(t, "survivor"), Prompt: "偷偷增强玩家", Count: 1, Difficulty: 3})
	if err == nil {
		t.Fatal("provider changed existing content while adding the requested structure")
	}
}
