package mods

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func newRouter(t *testing.T) *gin.Engine {
	svc := newSvc(t)
	r := gin.New()
	RegisterRoutes(r, svc)
	return r
}

func do(t *testing.T, r *gin.Engine, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var rd *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	} else {
		rd = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, rd)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// 端到端走一遍 Fork 流:建根 → 取生效 DSL → Fork → 在 Fork 上建子 → 验证补丁链。
func TestHTTP_ModFlow(t *testing.T) {
	r := newRouter(t)

	// 1. 建根 mod:换皮 cat
	w := do(t, r, http.MethodPost, "/api/v1/mods", map[string]any{
		"runtime": "shooter@1.0.0",
		"patch":   []map[string]any{{"op": "replace", "path": "/player/sprite", "value": "cat"}},
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("建根 mod 状态码 %d, body=%s", w.Code, w.Body.String())
	}
	var root Mod
	json.Unmarshal(w.Body.Bytes(), &root)

	// 2. 取生效 DSL → sprite=cat
	w = do(t, r, http.MethodGet, "/api/v1/mods/"+root.ID+"/dsl", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("取生效 DSL 状态码 %d", w.Code)
	}
	var eff map[string]any
	json.Unmarshal(w.Body.Bytes(), &eff)
	if eff["player"].(map[string]any)["sprite"] != "cat" {
		t.Error("生效 DSL sprite 应为 cat")
	}

	// 3. Fork 根
	w = do(t, r, http.MethodPost, "/api/v1/mods/"+root.ID+"/fork", nil)
	if w.Code != http.StatusCreated {
		t.Fatalf("Fork 状态码 %d", w.Code)
	}
	var forked Mod
	json.Unmarshal(w.Body.Bytes(), &forked)
	if forked.ParentID != root.ID {
		t.Errorf("Fork parent=%s 期望 %s", forked.ParentID, root.ID)
	}

	// 4. 在 Fork 上建子:加鸟
	w = do(t, r, http.MethodPost, "/api/v1/mods", map[string]any{
		"parent_id": forked.ID,
		"patch":     []map[string]any{{"op": "add", "path": "/enemies/bird_1", "value": map[string]any{"type": "bird", "behavior": "sine", "count": 10, "hp": 15, "speed": 12}}},
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("建子 mod 状态码 %d, body=%s", w.Code, w.Body.String())
	}
	var child Mod
	json.Unmarshal(w.Body.Bytes(), &child)

	// 5. 子的生效 DSL:cat(继承)+ bird(本级)
	w = do(t, r, http.MethodGet, "/api/v1/mods/"+child.ID+"/dsl", nil)
	json.Unmarshal(w.Body.Bytes(), &eff)
	if eff["player"].(map[string]any)["sprite"] != "cat" {
		t.Error("子 mod 应继承 cat")
	}
	if _, has := eff["enemies"].(map[string]any)["bird_1"]; !has {
		t.Error("子 mod 应含 bird_1")
	}
}

func TestMineAndForkUseAuthenticatedOwner(t *testing.T) {
	svc := newSvc(t)
	r := gin.New()
	RegisterRoutes(r, svc, func(c *gin.Context) { c.Set("user_id", "user_a"); c.Next() })
	w := do(t, r, http.MethodPost, "/api/v1/mods", map[string]any{"runtime": "shooter@1.0.0", "draft": true})
	if w.Code != 201 {
		t.Fatalf("create=%d %s", w.Code, w.Body.String())
	}
	var root Mod
	_ = json.Unmarshal(w.Body.Bytes(), &root)
	if root.AuthorID != "user_a" || !root.Draft {
		t.Fatalf("root=%+v", root)
	}
	w = do(t, r, http.MethodPost, "/api/v1/mods/"+root.ID+"/fork", nil)
	var fork Mod
	_ = json.Unmarshal(w.Body.Bytes(), &fork)
	if fork.AuthorID != "user_a" || !fork.Draft {
		t.Fatalf("fork=%+v", fork)
	}
	w = do(t, r, http.MethodGet, "/api/v1/mods/mine", nil)
	if w.Code != 200 || !bytes.Contains(w.Body.Bytes(), []byte(root.ID)) || !bytes.Contains(w.Body.Bytes(), []byte(fork.ID)) {
		t.Fatalf("mine=%d %s", w.Code, w.Body.String())
	}
}

func TestDraftCompatibilityRoutesAndOwnership(t *testing.T) {
	svc := newSvc(t)
	owner := "user_a"
	r := gin.New()
	RegisterRoutes(r, svc, func(c *gin.Context) { c.Set("user_id", owner); c.Next() })
	w := do(t, r, http.MethodPost, "/api/v1/mods", map[string]any{"runtime": "shooter@1.0.0", "draft": true})
	var first Mod
	_ = json.Unmarshal(w.Body.Bytes(), &first)
	w = do(t, r, http.MethodGet, "/api/v1/drafts", nil)
	if w.Code != 200 || !bytes.Contains(w.Body.Bytes(), []byte(first.ID)) {
		t.Fatalf("draft list=%d %s", w.Code, w.Body.String())
	}
	w = do(t, r, http.MethodPut, "/api/v1/drafts/"+first.ID, map[string]any{"patch": []map[string]any{{"op": "replace", "path": "/player/sprite", "value": "cat"}}})
	var saved Mod
	_ = json.Unmarshal(w.Body.Bytes(), &saved)
	if w.Code != 201 || saved.ParentID != first.ID || !saved.Draft || saved.AuthorID != owner {
		t.Fatalf("draft save=%d %+v", w.Code, saved)
	}

	owner = "attacker"
	w = do(t, r, http.MethodPut, "/api/v1/drafts/"+first.ID, map[string]any{"patch": []any{}})
	if w.Code != http.StatusForbidden {
		t.Fatalf("他人草稿应 403, got %d %s", w.Code, w.Body.String())
	}
}

func TestHTTP_Mod_NotFound(t *testing.T) {
	r := newRouter(t)
	w := do(t, r, http.MethodGet, "/api/v1/mods/mod_nope/dsl", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("状态码 %d, 期望 404", w.Code)
	}
}

// requireTestUser 是最小鉴权中间件桩:无 X-Test-User 头则 401,有则注入 user_id。
// 用于把「写接口必须登录」钉成可执行契约,而不依赖真实 auth 包。
func requireTestUser() gin.HandlerFunc {
	return func(c *gin.Context) {
		uid := c.GetHeader("X-Test-User")
		if uid == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "AUTH_REQUIRED"})
			return
		}
		c.Set("user_id", uid)
		c.Next()
	}
}

// 写接口(建 mod / Fork)套了 authMW 时,匿名请求必须 401;读接口仍公开。
func TestHTTP_Mod_WriteRequiresAuth(t *testing.T) {
	svc := newSvc(t)
	r := gin.New()
	RegisterRoutes(r, svc, requireTestUser())

	// 匿名建 mod → 401
	w := do(t, r, http.MethodPost, "/api/v1/mods", map[string]any{"runtime": "shooter@1.0.0"})
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("匿名建 mod 应 401, 实际 %d body=%s", w.Code, w.Body.String())
	}
	// 匿名 Fork → 401(鉴权先于业务,故不会因 mod 不存在而 404)
	w = do(t, r, http.MethodPost, "/api/v1/mods/whatever/fork", nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("匿名 Fork 应 401, 实际 %d", w.Code)
	}
	// 读接口公开:无 token 取 DSL 不应被鉴权拦截(mod 不存在 → 404,而非 401)
	w = do(t, r, http.MethodGet, "/api/v1/mods/whatever/dsl", nil)
	if w.Code == http.StatusUnauthorized {
		t.Fatalf("读接口不应要求鉴权, 实际 %d", w.Code)
	}

	// 带 token 建 mod → 放行(201)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/mods", bytes.NewReader(mustJSON(map[string]any{"runtime": "shooter@1.0.0"})))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Test-User", "u_1")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("已登录建 mod 应 201, 实际 %d body=%s", rec.Code, rec.Body.String())
	}
}

func mustJSON(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}
