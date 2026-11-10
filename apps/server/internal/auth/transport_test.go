package auth

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func newRouter(t *testing.T) (*gin.Engine, *LogSender) {
	sender := NewLogSender()
	svc := NewService(sender, NewMemUserRepo())
	r := gin.New()
	RegisterRoutes(r, svc)
	return r, sender
}

func post(t *testing.T, r *gin.Engine, path string, body any, token string) *httptest.ResponseRecorder {
	t.Helper()
	var rd *bytes.Reader = bytes.NewReader(nil)
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req := httptest.NewRequest(http.MethodPost, path, rd)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// 完整登录链路 + 鉴权中间件:发码 → 验码拿 token → /users/me 带 token → 200。
func TestHTTP_LoginAndMe(t *testing.T) {
	r, sender := newRouter(t)

	post(t, r, "/api/v1/auth/sms/send", map[string]any{"phone": "13800001234"}, "")
	code := sender.Last["13800001234"]

	w := post(t, r, "/api/v1/auth/sms/verify", map[string]any{"phone": "13800001234", "code": code}, "")
	if w.Code != http.StatusOK {
		t.Fatalf("登录状态码 %d, body=%s", w.Code, w.Body.String())
	}
	var resp struct {
		Token string `json:"token"`
		User  User   `json:"user"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp.Token == "" {
		t.Fatal("应返回 token")
	}

	// 带 token 取 /users/me → 200,且是同一用户
	req := httptest.NewRequest(http.MethodGet, "/api/v1/users/me", nil)
	req.Header.Set("Authorization", "Bearer "+resp.Token)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req)
	if w2.Code != http.StatusOK {
		t.Fatalf("/users/me 状态码 %d", w2.Code)
	}
	var me User
	json.Unmarshal(w2.Body.Bytes(), &me)
	if me.ID != resp.User.ID {
		t.Errorf("/users/me 返回的不是当前用户: %+v", me)
	}
	// 手机号是 PII,不应出现在响应 JSON 里(已 json:"-" 脱敏)。
	if strings.Contains(w2.Body.String(), "13800001234") {
		t.Errorf("/users/me 响应泄露了手机号: %s", w2.Body.String())
	}
}

func TestHTTP_MeRequiresAuth(t *testing.T) {
	r, _ := newRouter(t)
	// 无 token → 401
	req := httptest.NewRequest(http.MethodGet, "/api/v1/users/me", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("无 token 应 401, got %d", w.Code)
	}
	// 错 token → 401
	req2 := httptest.NewRequest(http.MethodGet, "/api/v1/users/me", nil)
	req2.Header.Set("Authorization", "Bearer bogus")
	w3 := httptest.NewRecorder()
	r.ServeHTTP(w3, req2)
	if w3.Code != http.StatusUnauthorized {
		t.Errorf("错 token 应 401, got %d", w3.Code)
	}
}

func TestDocumentedOAuthProviderRoute(t *testing.T) {
	svc := NewService(NewLogSender(), NewMemUserRepo())
	svc.SetOAuthVerifier(&fakeOAuthVerifier{identities: map[string]OAuthIdentity{"apple:code": {Subject: "subject"}}})
	r := gin.New()
	RegisterRoutes(r, svc)
	w := post(t, r, "/api/v1/auth/oauth/apple", map[string]any{"code": "code"}, "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"token"`) {
		t.Fatalf("oauth alias=%d %s", w.Code, w.Body.String())
	}
}

func TestHTTP_DeleteMeRevokesToken(t *testing.T) {
	r, sender := newRouter(t)
	phone := "13800008888"
	post(t, r, "/api/v1/auth/sms/send", map[string]any{"phone": phone}, "")
	w := post(t, r, "/api/v1/auth/sms/verify", map[string]any{"phone": phone, "code": sender.Last[phone]}, "")
	var login struct {
		Token string `json:"token"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &login)
	req := httptest.NewRequest(http.MethodDelete, "/api/v1/users/me", nil)
	req.Header.Set("Authorization", "Bearer "+login.Token)
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("delete=%d %s", w.Code, w.Body.String())
	}
	req = httptest.NewRequest(http.MethodGet, "/api/v1/users/me", nil)
	req.Header.Set("Authorization", "Bearer "+login.Token)
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("old token=%d", w.Code)
	}
}
