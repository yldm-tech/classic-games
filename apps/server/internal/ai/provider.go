// Package ai 编排「自然语言 → DSL 补丁」的生成流程(见 docs/12-ai-prompt.md)。
//
// 分层:本包只做框架无关的编排逻辑(调 provider → apply 6902 → 校验 → 重试 → 返回)。
// HTTP 装配(gin handler、限流、配额、ai_calls 落库)在上层 cmd/server 接入,
// 调用本包的 Service.GenerateMod。这样核心逻辑可单测,不绑 gin。
//
// 安全边界(docs/14-security-compliance.md):provider 的产物只进 DSL 补丁管线,绝不 eval。
package ai

import (
	"context"

	"github.com/yldm-tech/classic-games/packages/dsl"
)

// TokenUsage 记录一次模型调用的 token 消耗,用于成本核算。
type TokenUsage struct {
	Prompt     int `json:"prompt"`
	Completion int `json:"completion"`
}

// PatchSuggestion 是 provider 对一次意图给出的 6902 补丁建议。
type PatchSuggestion struct {
	Ops         []dsl.Op   `json:"ops"`          // RFC 6902 补丁(相对 current_dsl)
	BalanceHint string     `json:"balance_hint"` // 非阻断的平衡性/替代提示
	Model       string     `json:"model"`
	Tokens      TokenUsage `json:"tokens"`
}

// LLMProvider 抽象具体模型供应商(Claude / GPT / Gemini / 本地),见 ADR-008。
// 实现负责:喂入 runtime 的 schema/枚举约束,用 structured output / tool input_schema
// 强制产出「格式合法的 6902 补丁」。语义合法性由本包 apply + 校验保证,不依赖 provider。
type LLMProvider interface {
	// GenerateModPatch 针对 prompt 在 currentDSL 上给出补丁建议。
	// retryHint 携带上一轮的校验错误,用于失败重试时回灌给模型(首次为空)。
	GenerateModPatch(
		ctx context.Context,
		runtime string,
		currentDSL map[string]any,
		prompt string,
		retryHint string,
	) (PatchSuggestion, error)
}

// Validator 校验 apply 后的生效 DSL 是否符合 runtime 的契约(权威校验,见 docs/12-ai-prompt.md)。
// 权威实现是 github.com/yldm-tech/classic-games/packages/dsl 的 SchemaValidator(packages/dsl/schema_validator.go),用 JSON Schema 校验
// packages/schemas/<name>-<version>.schema.json;MinimalValidator 是零配置兜底(测试/未配置 schema 目录时)。
type Validator interface {
	Validate(runtime string, effectiveDSL map[string]any) error
}

// CallRecord 是一次 AI 调用的审计记录,用于成本核算与质量回归(docs/10-data-model.md ai_calls)。
type CallRecord struct {
	Runtime string
	Model   string
	Tokens  TokenUsage
	Retries int
	Valid   bool
	ErrCode string
}

// Recorder 落盘 ai_calls。上层可注入真实实现;默认 NoopRecorder。
type Recorder interface {
	Record(ctx context.Context, rec CallRecord)
}

// NoopRecorder 不记录,用于测试或未接入审计时。
type NoopRecorder struct{}

func (NoopRecorder) Record(context.Context, CallRecord) {}
