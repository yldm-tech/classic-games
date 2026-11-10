package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"forgeplay/dsl"
)

// StubProvider 是开发/测试用的确定性 provider —— 不接入任何真实模型,
// 只返回预置的补丁。用于在没有 API key 时把 /ai/mod 的 HTTP 链路跑通、做集成测试。
// 生产可切换到 ClaudeProvider(调模型 + tool input_schema，见 ADR-008)。
type StubProvider struct {
	Ops         []dsl.Op
	Model       string
	BalanceHint string
}

func (p StubProvider) GenerateModPatch(_ context.Context, runtime string, _ map[string]any, _ string, _ string) (PatchSuggestion, error) {
	model := p.Model
	if model == "" {
		model = "stub"
	}
	hint := p.BalanceHint
	if hint == "" {
		hint = "stub provider:未接入真实模型,返回预置补丁"
	}
	ops := p.Ops
	if ops == nil {
		value := func(v string) json.RawMessage { b, _ := json.Marshal(v); return b }
		switch strings.SplitN(runtime, "@", 2)[0] {
		case "shooter":
			ops = []dsl.Op{{Op: "replace", Path: "/player/sprite", Value: value("cat")}}
		case "survivor":
			ops = []dsl.Op{{Op: "replace", Path: "/hero/sprite", Value: value("mage")}}
		case "tower_defense":
			ops = []dsl.Op{{Op: "replace", Path: "/stage/background", Value: value("desert")}}
		default:
			return PatchSuggestion{}, fmt.Errorf("stub provider:不支持 runtime %s", runtime)
		}
	}
	return PatchSuggestion{Ops: ops, Model: model, BalanceHint: hint}, nil
}
