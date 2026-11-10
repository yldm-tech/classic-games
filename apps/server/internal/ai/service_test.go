package ai

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"forgeplay/dsl"
)

// ai 包在 apps/server/internal/ai/,到仓库根是 4 层。
func repoFile(t *testing.T, parts ...string) []byte {
	t.Helper()
	p := filepath.Join(append([]string{"..", "..", "..", ".."}, parts...)...)
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

func parseOps(t *testing.T, raw string) []dsl.Op {
	t.Helper()
	var o []dsl.Op
	if err := json.Unmarshal([]byte(raw), &o); err != nil {
		t.Fatalf("解析 ops 失败: %v", err)
	}
	return o
}

const forkPatchJSON = `[
	{"op":"replace","path":"/player/sprite","value":"cat"},
	{"op":"add","path":"/enemies/bird_1","value":{"type":"bird","behavior":"sine","count":10,"hp":15,"speed":12}},
	{"op":"replace","path":"/enemies/dog_1/count","value":30},
	{"op":"remove","path":"/enemies/turret_1"}
]`

// funcProvider 用一个函数模拟 LLMProvider,按 attempt 序号返回不同建议。
type funcProvider struct {
	fn    func(attempt int, hint string) (PatchSuggestion, error)
	calls int
}

func (p *funcProvider) GenerateModPatch(_ context.Context, _ string, _ map[string]any, _ string, hint string) (PatchSuggestion, error) {
	n := p.calls
	p.calls++
	return p.fn(n, hint)
}

// countRecorder 统计审计记录次数。
type countRecorder struct{ n int }

func (c *countRecorder) Record(context.Context, CallRecord) { c.n++ }

func baseReq(t *testing.T) ModRequest {
	return ModRequest{
		Runtime:    "shooter@1.0.0",
		CurrentDSL: loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json")),
		Prompt:     "把飞机换成猫,加只鸟,删掉炮台",
	}
}

func TestGenerateMod_SuccessFirstTry_MatchesGolden(t *testing.T) {
	ops := parseOps(t, forkPatchJSON)
	prov := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{Ops: ops, Model: "fake-1", Tokens: TokenUsage{Prompt: 100, Completion: 20}}, nil
	}}
	rec := &countRecorder{}
	svc := NewService(prov, MinimalValidator{}, rec, 2)

	resp, err := svc.GenerateMod(context.Background(), baseReq(t))
	if err != nil {
		t.Fatalf("GenerateMod 失败: %v", err)
	}
	if resp.Retries != 0 {
		t.Errorf("Retries=%d, 期望 0", resp.Retries)
	}
	if resp.Model != "fake-1" {
		t.Errorf("Model=%s", resp.Model)
	}
	// new_dsl 必须等于 golden(复用客户端共享 golden,确保编排产物正确)。
	golden := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "testdata", "fork_expected.dsl.json"))
	got, _ := json.Marshal(resp.NewDSL)
	want, _ := json.Marshal(golden)
	if string(got) != string(want) {
		t.Errorf("new_dsl 与 golden 不一致\n got=%s\nwant=%s", got, want)
	}
	if rec.n != 1 {
		t.Errorf("审计记录 %d 次, 期望 1", rec.n)
	}
}

func TestGenerateMod_RetryThenSuccess(t *testing.T) {
	good := parseOps(t, forkPatchJSON)
	// 第一次:删掉 player → apply 成功但校验失败(缺必需字段),触发重试。
	bad := parseOps(t, `[{"op":"remove","path":"/player"}]`)
	prov := &funcProvider{fn: func(attempt int, hint string) (PatchSuggestion, error) {
		if attempt == 0 {
			if hint != "" {
				t.Errorf("首次 hint 应为空, 实际 %q", hint)
			}
			return PatchSuggestion{Ops: bad, Model: "fake"}, nil
		}
		if hint == "" {
			t.Error("重试时 hint 应携带上一轮错误")
		}
		return PatchSuggestion{Ops: good, Model: "fake"}, nil
	}}
	rec := &countRecorder{}
	svc := NewService(prov, MinimalValidator{}, rec, 2)

	resp, err := svc.GenerateMod(context.Background(), baseReq(t))
	if err != nil {
		t.Fatalf("应在重试后成功, 实际 %v", err)
	}
	if resp.Retries != 1 {
		t.Errorf("Retries=%d, 期望 1", resp.Retries)
	}
	if rec.n != 2 {
		t.Errorf("审计记录 %d 次(1 失败 + 1 成功), 期望 2", rec.n)
	}
}

func TestGenerateMod_ExhaustRetries_DSLInvalid(t *testing.T) {
	bad := parseOps(t, `[{"op":"remove","path":"/player"}]`)
	prov := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{Ops: bad, Model: "fake"}, nil
	}}
	svc := NewService(prov, MinimalValidator{}, nil, 2)

	_, err := svc.GenerateMod(context.Background(), baseReq(t))
	if !errors.Is(err, ErrDSLInvalid) {
		t.Fatalf("期望 ErrDSLInvalid, 实际 %v", err)
	}
	if prov.calls != 3 {
		t.Errorf("provider 调用 %d 次(1 + 2 重试), 期望 3", prov.calls)
	}
}

func TestGenerateMod_EmptyPatchIsNotSuccess(t *testing.T) {
	prov := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) { return PatchSuggestion{Model: "empty"}, nil }}
	svc := NewService(prov, MinimalValidator{}, nil, 1)
	if _, err := svc.GenerateMod(context.Background(), baseReq(t)); !errors.Is(err, ErrDSLInvalid) {
		t.Fatalf("空补丁不得成功: %v", err)
	}
	if prov.calls != 2 {
		t.Fatalf("空补丁应重试, calls=%d", prov.calls)
	}
}

func TestGenerateMod_ProviderError_NoRetry(t *testing.T) {
	boom := errors.New("rate limited")
	prov := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{}, boom
	}}
	svc := NewService(prov, MinimalValidator{}, nil, 2)

	_, err := svc.GenerateMod(context.Background(), baseReq(t))
	if !errors.Is(err, boom) {
		t.Fatalf("provider 错误应原样上抛, 实际 %v", err)
	}
	if prov.calls != 1 {
		t.Errorf("provider 错误不应重试, 调用了 %d 次", prov.calls)
	}
}

func TestGenerateMod_BadPatchApply_RetryHint(t *testing.T) {
	// replace 不存在的路径 → apply 失败 → 应带 hint 重试,然后成功。
	badApply := parseOps(t, `[{"op":"replace","path":"/player/nope","value":1}]`)
	good := parseOps(t, forkPatchJSON)
	prov := &funcProvider{fn: func(attempt int, _ string) (PatchSuggestion, error) {
		if attempt == 0 {
			return PatchSuggestion{Ops: badApply, Model: "fake"}, nil
		}
		return PatchSuggestion{Ops: good, Model: "fake"}, nil
	}}
	svc := NewService(prov, MinimalValidator{}, nil, 2)

	resp, err := svc.GenerateMod(context.Background(), baseReq(t))
	if err != nil {
		t.Fatalf("应重试后成功, 实际 %v", err)
	}
	if resp.Retries != 1 {
		t.Errorf("Retries=%d, 期望 1", resp.Retries)
	}
}
