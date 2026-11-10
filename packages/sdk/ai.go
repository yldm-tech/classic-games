package sdk

import (
	"context"
	"encoding/json"
	"net/http"
)

// TokenUsage is the model token consumption of one generation.
type TokenUsage struct {
	Prompt     int `json:"prompt"`
	Completion int `json:"completion"`
}

// GenerateModRequest is the body of POST /api/v1/ai/mod.
type GenerateModRequest struct {
	// Runtime is the runtime ref the DSL belongs to, such as "shooter@1.0.0".
	Runtime string `json:"runtime"`
	// CurrentDSL is the complete effective DSL to modify. It is required; a missing value fails with 400 BAD_REQUEST.
	CurrentDSL map[string]any `json:"current_dsl"`
	// Prompt is the natural-language change request.
	Prompt string `json:"prompt"`
}

// GenerateModResponse is the result of POST /api/v1/ai/mod.
type GenerateModResponse struct {
	// DSLPatch is the RFC 6902 patch the model produced, relative to the CurrentDSL of the request.
	DSLPatch []PatchOp `json:"dsl_patch"`
	// NewDSL is CurrentDSL with DSLPatch applied. The backend has already validated it against the runtime schema.
	NewDSL map[string]any `json:"new_dsl"`
	// BalanceHint is an optional, non-blocking remark from the model about balance or alternatives.
	BalanceHint string     `json:"balance_hint,omitempty"`
	Model       string     `json:"model"`
	Tokens      TokenUsage `json:"tokens"`
	// Retries is how many extra model calls were needed before a valid result (0 to 2).
	Retries int `json:"retries"`
	// Provenance is a signed, short-lived token proving the patch came from the AI endpoint. Pass it as CreateModRequest.AIProvenance so the stored mod is marked AI-generated. It is empty when the backend has no FORGEPLAY_SECRET.
	Provenance string `json:"provenance,omitempty"`
}

// GenerateMod calls POST /api/v1/ai/mod: the model turns Prompt into a JSON Patch against CurrentDSL, the backend applies and schema-validates it, and both the patch and the new DSL come back in one JSON response (the endpoint does not stream). Nothing is stored; persist the result with CreateMod or SaveDraft.
//
// Authentication is optional, but the call is metered: 20 calls per day shared between GenerateMod and GenerateStructure, counted per account for signed-in users and per client IP for guests and anonymous callers. When the quota is used up the call fails with 429 QUOTA_EXCEEDED. A request rejected before the model is called (400 BAD_REQUEST) is refunded; 422 DSL_INVALID (the model produced no valid result after its retries) and 502 PROVIDER_ERROR still consume one call. Read the current state with AIQuota.
func (c *Client) GenerateMod(ctx context.Context, request GenerateModRequest) (*GenerateModResponse, error) {
	var out GenerateModResponse
	if err := c.do(ctx, http.MethodPost, api("ai", "mod"), nil, request, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// GenerateStructureRequest is the body of POST /api/v1/ai/structure.
type GenerateStructureRequest struct {
	Runtime    string         `json:"runtime"`
	CurrentDSL map[string]any `json:"current_dsl"`
	// Prompt describes the enemies or waves to add. Required.
	Prompt string `json:"prompt"`
	// Count is the number of structure nodes to add, 1 to 8.
	Count int `json:"count"`
	// Difficulty is the target difficulty, 1 to 5.
	Difficulty int `json:"difficulty"`
}

// GenerateStructureResponse is the result of POST /api/v1/ai/structure.
type GenerateStructureResponse struct {
	DSLPatch []PatchOp      `json:"dsl_patch"`
	NewDSL   map[string]any `json:"new_dsl"`
	// GeneratedKeys are the map keys of the nodes that were added.
	GeneratedKeys []string `json:"generated_keys"`
	Model         string   `json:"model"`
	BalanceHint   string   `json:"balance_hint"`
	Provenance    string   `json:"provenance,omitempty"`
}

// GenerateStructure calls POST /api/v1/ai/structure and appends new enemy or wave nodes to the DSL without overwriting existing ones. It shares the daily quota and its billing rules with GenerateMod. A missing prompt or DSL, a count outside 1..8 or a difficulty outside 1..5 fails with 400 BAD_REQUEST.
func (c *Client) GenerateStructure(ctx context.Context, request GenerateStructureRequest) (*GenerateStructureResponse, error) {
	var out GenerateStructureResponse
	if err := c.do(ctx, http.MethodPost, api("ai", "structure"), nil, request, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// AutoBalanceRequest is the body of POST /api/v1/ai/balance.
type AutoBalanceRequest struct {
	Runtime    string         `json:"runtime"`
	CurrentDSL map[string]any `json:"current_dsl"`
	// TargetDifficulty is the difficulty to tune towards, 1 to 5.
	TargetDifficulty int `json:"target_difficulty"`
}

// BalanceMetrics is the pressure metric of a DSL before and after balancing.
type BalanceMetrics struct {
	Before float64 `json:"before"`
	After  float64 `json:"after"`
}

// AutoBalanceResponse is the result of POST /api/v1/ai/balance.
type AutoBalanceResponse struct {
	DSLPatch    []PatchOp      `json:"dsl_patch"`
	NewDSL      map[string]any `json:"new_dsl"`
	Metrics     BalanceMetrics `json:"metrics"`
	Model       string         `json:"model"`
	BalanceHint string         `json:"balance_hint"`
	Provenance  string         `json:"provenance,omitempty"`
}

// AutoBalance calls POST /api/v1/ai/balance and tunes player, enemy and wave parameters towards a target difficulty. It is computed by the backend without a model call, needs no authentication and does not consume AI quota. An invalid request fails with 400 BAD_REQUEST, a result that fails schema validation with 422 DSL_INVALID.
func (c *Client) AutoBalance(ctx context.Context, request AutoBalanceRequest) (*AutoBalanceResponse, error) {
	var out AutoBalanceResponse
	if err := c.do(ctx, http.MethodPost, api("ai", "balance"), nil, request, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// ValidateDSL calls POST /api/v1/ai/validate and returns nil when dsl is valid for the runtime ref (such as "shooter@1.0.0"). An invalid document fails with 422 DSL_INVALID; the response does not say which field is wrong, so use forgeplay/dsl with the schema from GetRuntimeSchema for field-level messages. No authentication, no quota.
func (c *Client) ValidateDSL(ctx context.Context, runtime string, dsl map[string]any) error {
	body := struct {
		Runtime string         `json:"runtime"`
		DSL     map[string]any `json:"dsl"`
	}{Runtime: runtime, DSL: dsl}
	return c.do(ctx, http.MethodPost, api("ai", "validate"), nil, body, nil)
}

// AIQuota is today's AI generation allowance for the caller.
type AIQuota struct {
	Used      int `json:"used"`
	Remaining int `json:"remaining"`
	Limit     int `json:"limit"`
}

// AIQuota calls GET /api/v1/ai/quota. Reading the quota never consumes it. The bucket is the caller's account when signed in with a real account, and the client IP for guests and anonymous callers. The counter resets at the backend's local midnight.
func (c *Client) AIQuota(ctx context.Context) (*AIQuota, error) {
	var out AIQuota
	if err := c.do(ctx, http.MethodGet, api("ai", "quota"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// GetRuntimeSchema calls GET /api/v1/runtimes/{name}/{version}/schema and returns the JSON Schema (draft 2020-12) of a runtime's DSL as raw JSON, for example name "shooter" and version "1.0.0". No authentication. An unknown runtime fails with 404 NOT_FOUND.
func (c *Client) GetRuntimeSchema(ctx context.Context, name, version string) (json.RawMessage, error) {
	var out json.RawMessage
	if err := c.do(ctx, http.MethodGet, api("runtimes", segment(name), segment(version), "schema"), nil, nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// GetRuntimeBaseline calls GET /api/v1/runtimes/{name}/{version}/baseline and returns the baseline DSL every root mod of that runtime starts from. No authentication. An unknown runtime or a version that differs from the baseline's own version fails with 404 NOT_FOUND.
func (c *Client) GetRuntimeBaseline(ctx context.Context, name, version string) (map[string]any, error) {
	var out map[string]any
	if err := c.do(ctx, http.MethodGet, api("runtimes", segment(name), segment(version), "baseline"), nil, nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}
