package ai

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// canned Messages API 响应:模型调用 emit_dsl_patch,返回「换皮 cat」补丁。
const cannedToolResponse = `{
  "id": "msg_test",
  "type": "message",
  "role": "assistant",
  "model": "claude-opus-4-8",
  "content": [
    {
      "type": "tool_use",
      "id": "toolu_1",
      "name": "emit_dsl_patch",
      "input": {
        "ops": [{"op": "replace", "path": "/player/sprite", "value": "cat"}],
        "balance_hint": "换皮不影响平衡"
      }
    }
  ],
  "stop_reason": "tool_use",
  "stop_sequence": null,
  "usage": {"input_tokens": 120, "output_tokens": 30}
}`

func mockClaude(t *testing.T, body string) (*ClaudeProvider, func()) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, body)
	}))
	return NewClaudeProvider("test-key", srv.URL), srv.Close
}

// 验证:请求能发出、tool_use 响应被正确解析成 PatchSuggestion。
func TestClaudeProvider_ParsesToolPatch(t *testing.T) {
	p, closeFn := mockClaude(t, cannedToolResponse)
	defer closeFn()

	base := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	sug, err := p.GenerateModPatch(context.Background(), "shooter@1.0.0", base, "把飞机换成猫", "")
	if err != nil {
		t.Fatalf("GenerateModPatch 失败: %v", err)
	}
	if len(sug.Ops) != 1 || sug.Ops[0].Op != "replace" || sug.Ops[0].Path != "/player/sprite" {
		t.Errorf("ops 解析不对: %+v", sug.Ops)
	}
	if sug.BalanceHint == "" {
		t.Error("balance_hint 应被解析")
	}
	if sug.Tokens.Prompt != 120 || sug.Tokens.Completion != 30 {
		t.Errorf("token 用量不对: %+v", sug.Tokens)
	}
}

// 端到端:ClaudeProvider(mock)→ Service 编排 → apply → SchemaValidator 校验 → new_dsl。
func TestClaudeProvider_WiresIntoService(t *testing.T) {
	p, closeFn := mockClaude(t, cannedToolResponse)
	defer closeFn()

	svc := NewService(p, newValidator(t), nil, 2)
	resp, err := svc.GenerateMod(context.Background(), baseReq(t))
	if err != nil {
		t.Fatalf("端到端编排失败: %v", err)
	}
	if resp.NewDSL["player"].(map[string]any)["sprite"] != "cat" {
		t.Error("new_dsl 应换皮为 cat")
	}
}

// 模型不调用工具(异常响应)→ 报错,由 Service 转重试/失败。
func TestClaudeProvider_NoToolCall(t *testing.T) {
	body := `{"id":"m","type":"message","role":"assistant","model":"claude-opus-4-8",
		"content":[{"type":"text","text":"我不知道"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}`
	p, closeFn := mockClaude(t, body)
	defer closeFn()
	if _, err := p.GenerateModPatch(context.Background(), "shooter@1.0.0", map[string]any{}, "x", ""); err == nil {
		t.Error("模型未调用工具应报错")
	}
}
