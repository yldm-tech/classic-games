package ai

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"time"

	"github.com/yldm-tech/classic-games/packages/dsl"
)

// provenanceTTL 是 AI 溯源令牌有效期(从 /ai/mod 生成到 POST /mods 建 mod 的窗口)。
// 取 24h:一次创作会话从生成到发布可能跨数小时,太短会让 AI 作品因令牌过期被漏标。
const provenanceTTL = 24 * time.Hour

// ErrDSLInvalid 表示重试耗尽后仍无法产出合法 DSL。上层映射为 API 错误码 DSL_INVALID
// (docs/09-api-design.md)。发生它时 provider 已被调用(含重试),有真实成本。
var ErrDSLInvalid = errors.New("ai: 无法产出合法 DSL(重试耗尽)")

// ErrNoCurrentDSL 表示入参 current_dsl 为空——属于调 provider 之前的前置校验失败,
// 无 LLM 成本。上层映射为 400 BAD_REQUEST(而非 provider 错误),且配额可回补。
var ErrNoCurrentDSL = errors.New("ai: current_dsl 为空")

// ModRequest 对应 POST /ai/mod 的入参(docs/09-api-design.md)。
type ModRequest struct {
	Runtime    string         `json:"runtime"`     // "shooter@1.0.0"
	CurrentDSL map[string]any `json:"current_dsl"` // 当前生效 DSL
	Prompt     string         `json:"prompt"`      // 自然语言意图
}

// ModResponse 对应 POST /ai/mod 的出参。
//
// 注意:DSLPatch 相对 CurrentDSL(本轮全量),与入库的 mods.patch(相对父 mod 生效 DSL)不是
// 同一个;publish 时才由 NewDSL 与父 mod 生效 DSL 做 diff 得入库 patch(docs/10-data-model.md)。
type ModResponse struct {
	DSLPatch    []dsl.Op       `json:"dsl_patch"`
	NewDSL      map[string]any `json:"new_dsl"`
	BalanceHint string         `json:"balance_hint,omitempty"`
	Model       string         `json:"model"`
	Tokens      TokenUsage     `json:"tokens"`
	Retries     int            `json:"retries"`
	// Provenance 是「AI 生成」溯源令牌(服务端 HMAC 签名)。客户端在 POST /mods 时回带,
	// 服务端校验通过即把该 mod 标记为 AI 生成,且发布时不可被改成非 AI(防漏标)。未配置密钥时为空。
	Provenance string `json:"provenance,omitempty"`
}

// ProvenanceSigner 签发「AI 生成」溯源令牌(由 pkg/provenance 实现)。
type ProvenanceSigner interface {
	Mint(now time.Time, ttl time.Duration) string
}

// Service 编排一次 AI 改 DSL。框架无关,可单测。
type Service struct {
	provider   LLMProvider
	validator  Validator
	recorder   Recorder
	maxRetries int
	signer     ProvenanceSigner // 可空;非空则成功响应里带 AI 溯源令牌
}

// SetProvenanceSigner 注入 AI 溯源令牌签发器。
func (s *Service) SetProvenanceSigner(p ProvenanceSigner) { s.signer = p }

func (s *Service) mintProvenance() string {
	if s.signer == nil {
		return ""
	}
	return s.signer.Mint(time.Now(), provenanceTTL)
}

// NewService 组装编排器。maxRetries<0 时取默认 2(docs/12-ai-prompt.md「有限次重试」)。
func NewService(p LLMProvider, v Validator, r Recorder, maxRetries int) *Service {
	if v == nil {
		v = MinimalValidator{}
	}
	if r == nil {
		r = NoopRecorder{}
	}
	if maxRetries < 0 {
		maxRetries = 2
	}
	return &Service{provider: p, validator: v, recorder: r, maxRetries: maxRetries}
}

// GenerateMod 执行 docs/12-ai-prompt.md 的生成流程:
//
//	调 provider(structured output 产 6902 patch)
//	  → apply 到 current_dsl 得 new_dsl
//	  → 用 Validator 校验 new_dsl 语义合法性
//	      通过 → 返回 ModResponse
//	      失败 → 把错误回灌给 provider 重试(有限次)→ 仍失败返回 ErrDSLInvalid
//	全程记录 ai_calls。
//
// 关键:provider 只保证 patch「格式」合法;「apply 后语义合法」必须由本函数 apply+校验保证
// (评审 M1:两者不能捆在一起)。
func (s *Service) GenerateMod(ctx context.Context, req ModRequest) (ModResponse, error) {
	if req.CurrentDSL == nil {
		return ModResponse{}, ErrNoCurrentDSL
	}
	hint := ""
	var lastSug PatchSuggestion
	for attempt := 0; attempt <= s.maxRetries; attempt++ {
		sug, err := s.provider.GenerateModPatch(ctx, req.Runtime, req.CurrentDSL, req.Prompt, hint)
		if err != nil {
			// provider 自身错误(网络/限流等)不重试,直接上抛由上层处理。
			s.record(ctx, req.Runtime, sug, attempt, false, "PROVIDER_ERROR")
			return ModResponse{}, err
		}
		lastSug = sug
		if len(sug.Ops) == 0 {
			hint = "上一轮返回空补丁,必须产生至少一项实际修改"
			s.record(ctx, req.Runtime, sug, attempt, false, "EMPTY_PATCH")
			continue
		}

		newDSL, applyErr := dsl.Apply(req.CurrentDSL, sug.Ops)
		if applyErr != nil {
			hint = "上一轮补丁 apply 失败,请修正:" + applyErr.Error()
			s.record(ctx, req.Runtime, sug, attempt, false, "PATCH_APPLY_FAILED")
			continue
		}
		if reflect.DeepEqual(newDSL, req.CurrentDSL) {
			hint = "上一轮补丁没有改变 DSL,必须产生实际修改"
			s.record(ctx, req.Runtime, sug, attempt, false, "NO_CHANGE")
			continue
		}

		if vErr := s.validator.Validate(req.Runtime, newDSL); vErr != nil {
			hint = "上一轮结果未通过校验,请修正:" + vErr.Error()
			s.record(ctx, req.Runtime, sug, attempt, false, "DSL_INVALID")
			continue
		}

		s.record(ctx, req.Runtime, sug, attempt, true, "")
		return ModResponse{
			DSLPatch:    sug.Ops,
			NewDSL:      newDSL,
			BalanceHint: sug.BalanceHint,
			Model:       sug.Model,
			Tokens:      sug.Tokens,
			Retries:     attempt,
			Provenance:  s.mintProvenance(),
		}, nil
	}
	_ = lastSug
	return ModResponse{}, ErrDSLInvalid
}

// Validate 只校验一份 DSL 是否合法,供 POST /ai/validate 客户端预检用(docs/09-api-design.md)。
func (s *Service) Validate(runtime string, dsl map[string]any) error {
	return s.validator.Validate(runtime, dsl)
}

func (s *Service) record(ctx context.Context, runtime string, sug PatchSuggestion, attempt int, valid bool, code string) {
	s.recorder.Record(ctx, CallRecord{
		Runtime: runtime,
		Model:   sug.Model,
		Tokens:  sug.Tokens,
		Retries: attempt,
		Valid:   valid,
		ErrCode: code,
	})
}

// runtimeName 取 "shooter@1.0.0" 的 name 部分。
func runtimeName(ref string) string {
	if i := strings.IndexByte(ref, '@'); i >= 0 {
		return ref[:i]
	}
	return ref
}
