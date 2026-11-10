package ai

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"

	"forgeplay/dsl"
)

// ClaudeProvider 是 LLMProvider 的真实实现,用官方 anthropic-sdk-go 调 Claude(见 ADR-008)。
// 用 tool use 强制结构化输出:模型必须调用 emit_dsl_patch,以 RFC 6902 ops 形式返回补丁,
// 因此「格式」由 tool input_schema 约束;「语义」仍由后端 apply + SchemaValidator 校验(评审 M1)。
//
// 默认模型 claude-opus-4-8(claude-api 规范)。baseURL 可指向测试 mock,便于无 key 验证。
type ClaudeProvider struct {
	client    anthropic.Client
	model     anthropic.Model
	maxTokens int64
}

// NewClaudeProvider 用 API key 构造;baseURL 为空走官方端点,非空(如 httptest)便于测试。
func NewClaudeProvider(apiKey, baseURL string) *ClaudeProvider {
	opts := []option.RequestOption{option.WithAPIKey(apiKey)}
	if baseURL != "" {
		opts = append(opts, option.WithBaseURL(baseURL))
	}
	return &ClaudeProvider{
		client:    anthropic.NewClient(opts...),
		model:     anthropic.ModelClaudeOpus4_8,
		maxTokens: 4096,
	}
}

const patchToolName = "emit_dsl_patch"

func (p *ClaudeProvider) GenerateModPatch(
	ctx context.Context,
	runtime string,
	currentDSL map[string]any,
	prompt string,
	retryHint string,
) (PatchSuggestion, error) {
	curJSON, _ := json.Marshal(currentDSL)

	system := "你是 ForgePlay 的游戏改造助手。只能输出对游戏配置(DSL)的修改,以 RFC 6902 JSON Patch 形式。" +
		"只能使用 runtime 已有的枚举值,数值需在范围内;绝不输出代码或自然语言解释(解释放 balance_hint)。" +
		"你必须调用 " + patchToolName + " 工具返回结果。"

	userText := fmt.Sprintf("runtime: %s\n当前 DSL:\n%s\n\n用户意图: %s", runtime, string(curJSON), prompt)
	if retryHint != "" {
		userText += "\n\n注意:" + retryHint
	}

	// tool 的 input_schema:{ ops: [6902 op...], balance_hint?: string }。
	// ops 顶层是对象(JSON Schema 要求),内部 ops 字段是 6902 数组。
	patchTool := anthropic.ToolParam{
		Name:        patchToolName,
		Description: anthropic.String("返回对当前 DSL 的 RFC 6902 补丁"),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"ops": map[string]any{
					"type": "array",
					"items": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"op":    map[string]any{"type": "string", "enum": []string{"add", "remove", "replace", "test"}},
							"path":  map[string]any{"type": "string"},
							"value": map[string]any{},
						},
						"required": []string{"op", "path"},
					},
				},
				"balance_hint": map[string]any{"type": "string"},
			},
		},
	}

	resp, err := p.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     p.model,
		MaxTokens: p.maxTokens,
		System:    []anthropic.TextBlockParam{{Text: system}},
		Tools:     []anthropic.ToolUnionParam{{OfTool: &patchTool}},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock(userText)),
		},
	})
	if err != nil {
		return PatchSuggestion{}, fmt.Errorf("claude 调用失败: %w", err)
	}

	for _, block := range resp.Content {
		if tu, ok := block.AsAny().(anthropic.ToolUseBlock); ok && tu.Name == patchToolName {
			var parsed struct {
				Ops         []dsl.Op `json:"ops"`
				BalanceHint string   `json:"balance_hint"`
			}
			if err := json.Unmarshal([]byte(tu.JSON.Input.Raw()), &parsed); err != nil {
				return PatchSuggestion{}, fmt.Errorf("解析 tool 输入失败: %w", err)
			}
			return PatchSuggestion{
				Ops:         parsed.Ops,
				BalanceHint: parsed.BalanceHint,
				Model:       string(resp.Model),
				Tokens: TokenUsage{
					Prompt:     int(resp.Usage.InputTokens),
					Completion: int(resp.Usage.OutputTokens),
				},
			}, nil
		}
	}
	return PatchSuggestion{}, fmt.Errorf("模型未调用 %s 工具(stop_reason=%s)", patchToolName, resp.StopReason)
}
