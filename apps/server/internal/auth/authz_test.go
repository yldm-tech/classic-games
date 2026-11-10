package auth

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func TestGuestLogin_IssuesUniqueTokens(t *testing.T) {
	svc, _ := newSvc()
	t1, u1, err := svc.GuestLogin()
	if err != nil {
		t.Fatal(err)
	}
	t2, u2, err := svc.GuestLogin()
	if err != nil {
		t.Fatal(err)
	}
	if t1 == "" || t2 == "" || t1 == t2 {
		t.Error("游客 token 应非空且各不相同")
	}
	if u1.ID == u2.ID {
		t.Error("两个游客应是不同用户(合成手机号不冲突)")
	}
	if id, ok := svc.UserIDForToken(t1); !ok || id != u1.ID {
		t.Error("游客 token 应解析回其用户")
	}
}

func TestSetAdmins_AndIsAdmin(t *testing.T) {
	svc, _ := newSvc()
	if svc.IsAdmin("u1") {
		t.Error("默认无人是管理员")
	}
	svc.SetAdmins("u1", "", "u2")
	if !svc.IsAdmin("u1") || !svc.IsAdmin("u2") {
		t.Error("白名单用户应是管理员")
	}
	if svc.IsAdmin("") {
		t.Error("空 ID 不应被当作管理员")
	}
	svc.SetAdmins() // 覆盖式清空
	if svc.IsAdmin("u1") {
		t.Error("重设白名单应清掉旧管理员")
	}
}

// RequireAdmin:无 token→401,非管理员→403,管理员→放行。
func TestRequireAdmin_Gating(t *testing.T) {
	svc, sender := newSvc()
	svc.SendCode("13800000001")
	adminTok, adminUser, _ := svc.Login("13800000001", sender.Last["13800000001"])
	svc.SetAdmins(adminUser.ID)

	svc.SendCode("13800000002")
	userTok, _, _ := svc.Login("13800000002", sender.Last["13800000002"])

	r := gin.New()
	r.POST("/admin", RequireAdmin(svc), func(c *gin.Context) { c.Status(http.StatusOK) })

	do := func(tok string) int {
		req := httptest.NewRequest(http.MethodPost, "/admin", nil)
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w.Code
	}

	if got := do(""); got != http.StatusUnauthorized {
		t.Errorf("无 token 应 401, got %d", got)
	}
	if got := do(userTok); got != http.StatusForbidden {
		t.Errorf("非管理员应 403, got %d", got)
	}
	if got := do(adminTok); got != http.StatusOK {
		t.Errorf("管理员应放行 200, got %d", got)
	}
}

// Optional:有效 token 注入 user_id;无 token 不报错且不注入。
func TestOptional_InjectsWhenPresent(t *testing.T) {
	svc, sender := newSvc()
	svc.SendCode("13800000003")
	tok, u, _ := svc.Login("13800000003", sender.Last["13800000003"])

	r := gin.New()
	r.GET("/who", Optional(svc), func(c *gin.Context) { c.String(http.StatusOK, c.GetString("user_id")) })

	req := httptest.NewRequest(http.MethodGet, "/who", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Body.String() != u.ID {
		t.Errorf("有 token 应注入 user_id=%s, got %q", u.ID, w.Body.String())
	}

	req2 := httptest.NewRequest(http.MethodGet, "/who", nil) // 无 token
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK || w2.Body.String() != "" {
		t.Errorf("无 token 应放行且不注入身份, code=%d body=%q", w2.Code, w2.Body.String())
	}
}
