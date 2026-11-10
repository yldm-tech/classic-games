package ai

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/internal/quota"
	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

func init() { gin.SetMode(gin.TestMode) }

// 用真 SchemaValidator + 可配置 StubProvider 起一个内存路由,httptest 打 /ai/mod。
func newRouter(t *testing.T, ops string) *gin.Engine {
	t.Helper()
	prov := StubProvider{}
	if ops != "" {
		prov.Ops = parseOps(t, ops)
	}
	svc := NewService(prov, newValidator(t), nil, 2)
	r := gin.New()
	RegisterRoutes(r, svc)
	return r
}

func postJSON(t *testing.T, r *gin.Engine, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestHTTP_AiMod_Success(t *testing.T) {
	r := newRouter(t, forkPatchJSON)
	baseline := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))

	w := postJSON(t, r, "/api/v1/ai/mod", map[string]any{
		"runtime":     "shooter@1.0.0",
		"current_dsl": baseline,
		"prompt":      "把飞机换成猫",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("状态码 %d, 期望 200;body=%s", w.Code, w.Body.String())
	}
	var resp ModResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	// new_dsl 必须等于共享 golden(端到端:HTTP → Service → apply → schema 校验)
	golden := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", filepath.FromSlash("testdata/fork_expected.dsl.json")))
	got, _ := json.Marshal(resp.NewDSL)
	want, _ := json.Marshal(golden)
	if string(got) != string(want) {
		t.Errorf("new_dsl 与 golden 不一致\n got=%s\nwant=%s", got, want)
	}
}

func TestHTTP_AiMod_DSLInvalid(t *testing.T) {
	// provider 一直返回会让校验失败的补丁(删 player)→ 重试耗尽 → 422 DSL_INVALID
	r := newRouter(t, `[{"op":"remove","path":"/player"}]`)
	baseline := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))

	w := postJSON(t, r, "/api/v1/ai/mod", map[string]any{
		"runtime":     "shooter@1.0.0",
		"current_dsl": baseline,
		"prompt":      "x",
	})
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("状态码 %d, 期望 422;body=%s", w.Code, w.Body.String())
	}
	var env httpx.Envelope
	json.Unmarshal(w.Body.Bytes(), &env)
	if env.Error.Code != "DSL_INVALID" {
		t.Errorf("错误码 %q, 期望 DSL_INVALID", env.Error.Code)
	}
}

func TestHTTP_AiMod_BadJSON(t *testing.T) {
	r := newRouter(t, "")
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ai/mod", bytes.NewReader([]byte("{not json")))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("状态码 %d, 期望 400", w.Code)
	}
}

func TestHTTP_AiValidate(t *testing.T) {
	r := newRouter(t, "")
	baseline := loadDSL(t, repoFile(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))

	// 合法 DSL → 200 valid
	w := postJSON(t, r, "/api/v1/ai/validate", map[string]any{"runtime": "shooter@1.0.0", "dsl": baseline})
	if w.Code != http.StatusOK {
		t.Fatalf("合法 DSL 状态码 %d, 期望 200;body=%s", w.Code, w.Body.String())
	}
	// 非法 DSL(hp 越界)→ 422
	bad := mutate(t, baseline, func(d map[string]any) { d["player"].(map[string]any)["hp"] = 9999 })
	w2 := postJSON(t, r, "/api/v1/ai/validate", map[string]any{"runtime": "shooter@1.0.0", "dsl": bad})
	if w2.Code != http.StatusUnprocessableEntity {
		t.Errorf("非法 DSL 状态码 %d, 期望 422", w2.Code)
	}
}

func TestHTTP_AiBalanceAndStructure(t *testing.T) {
	r := newRouter(t, "")
	for _, runtime := range []string{"shooter", "survivor", "tower_defense"} {
		baseline := runtimeBaseline(t, runtime)
		balanced := postJSON(t, r, "/api/v1/ai/balance", map[string]any{
			"runtime": runtime + "@1.0.0", "current_dsl": baseline, "target_difficulty": 5,
		})
		if balanced.Code != http.StatusOK {
			t.Fatalf("%s balance: %d %s", runtime, balanced.Code, balanced.Body.String())
		}
		var balanceResponse BalanceResponse
		if err := json.Unmarshal(balanced.Body.Bytes(), &balanceResponse); err != nil || balanceResponse.Metrics.After <= balanceResponse.Metrics.Before {
			t.Fatalf("%s balance response: %+v %v", runtime, balanceResponse, err)
		}

		structured := postJSON(t, r, "/api/v1/ai/structure", map[string]any{
			"runtime": runtime + "@1.0.0", "current_dsl": baseline, "prompt": "熔岩突袭", "count": 3, "difficulty": 4,
		})
		if structured.Code != http.StatusOK {
			t.Fatalf("%s structure: %d %s", runtime, structured.Code, structured.Body.String())
		}
		var structureResponse StructureResponse
		if err := json.Unmarshal(structured.Body.Bytes(), &structureResponse); err != nil || len(structureResponse.GeneratedKeys) != 3 {
			t.Fatalf("%s structure response: %+v %v", runtime, structureResponse, err)
		}
	}
}

func TestHTTP_AiBalanceAndStructureRejectBadRequests(t *testing.T) {
	r := newRouter(t, "")
	baseline := runtimeBaseline(t, "survivor")
	if w := postJSON(t, r, "/api/v1/ai/balance", map[string]any{"runtime": "survivor@1.0.0", "current_dsl": baseline, "target_difficulty": 9}); w.Code != http.StatusBadRequest {
		t.Fatalf("bad balance = %d %s", w.Code, w.Body.String())
	}
	if w := postJSON(t, r, "/api/v1/ai/structure", map[string]any{"runtime": "survivor@1.0.0", "current_dsl": baseline, "prompt": "", "count": 0, "difficulty": 3}); w.Code != http.StatusBadRequest {
		t.Fatalf("bad structure = %d %s", w.Code, w.Body.String())
	}
}

func TestHTTP_AiStructureProviderFailureConsumesQuota(t *testing.T) {
	provider := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{}, errors.New("provider response parse failed")
	}}
	svc := NewService(provider, newValidator(t), nil, 0)
	quotaSvc := quota.NewService(2)
	r := gin.New()
	RegisterRoutes(r, svc, quota.Middleware(quotaSvc, func(*gin.Context) string { return "user" }))
	w := postJSON(t, r, "/api/v1/ai/structure", map[string]any{
		"runtime": "survivor@1.0.0", "current_dsl": runtimeBaseline(t, "survivor"), "prompt": "幽灵包围", "count": 1, "difficulty": 3,
	})
	if w.Code != http.StatusBadGateway {
		t.Fatalf("provider failure=%d %s", w.Code, w.Body.String())
	}
	if remaining := quotaSvc.Remaining("user"); remaining != 1 {
		t.Fatalf("provider cost refunded, remaining=%d", remaining)
	}
}

func TestHTTP_AiQuotaIsReadOnly(t *testing.T) {
	// The quota key comes from quota.UserOrIP, which falls back to gin's ClientIP for an anonymous caller. Seeding the
	// service under one address while the request arrives from another would report a different client's snapshot, so
	// the request has to originate from the address being primed — httptest otherwise defaults RemoteAddr to 192.0.2.1.
	const caller = "127.0.0.1"
	quotaSvc := quota.NewService(5)
	quotaSvc.Allow(caller)
	r := gin.New()
	RegisterQuotaRoute(r, quotaSvc)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/ai/quota", nil)
	req.RemoteAddr = caller + ":54321"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("quota=%d %s", w.Code, w.Body.String())
	}
	var body quota.Snapshot
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Used != 1 || body.Remaining != 4 || body.Limit != 5 {
		t.Fatalf("quota snapshot = %#v", body)
	}
	if quotaSvc.Remaining(caller) != 4 {
		t.Fatal("GET /ai/quota consumed a slot")
	}
}
