package users

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func userRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	auth := func(c *gin.Context) { c.Set("user_id", "user_http"); c.Next() }
	RegisterRoutes(r, newSvc(t), auth)
	return r
}

func TestProfileAndVerificationHTTP(t *testing.T) {
	r := userRouter(t)
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/users/me/profile", strings.NewReader(`{"name":"Alice","bio":"hello","gender":1,"tone":"ocean","region":"Tokyo"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"id":"@user_http"`) {
		t.Fatalf("profile: %d %s", w.Code, w.Body.String())
	}

	w = httptest.NewRecorder()
	raw := "11010519491231002X"
	req = httptest.NewRequest(http.MethodPost, "/api/v1/users/me/verification", strings.NewReader(`{"name":"张三","id_number":"`+raw+`"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusAccepted || strings.Contains(w.Body.String(), raw) {
		t.Fatalf("verification leaked/failure: %d %s", w.Code, w.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil || body["status"] != "pending" {
		t.Fatalf("unexpected verification: %v %v", body, err)
	}
}

func TestDocumentedUserRouteAliases(t *testing.T) {
	r := userRouter(t)
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/users/me", strings.NewReader(`{"name":"Patched"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), "Patched") {
		t.Fatalf("PATCH /users/me=%d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/v1/users/@user_http", nil)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"id":"@user_http"`) {
		t.Fatalf("GET /users/:id=%d %s", w.Code, w.Body.String())
	}
}

func TestDocumentedRealnameAlias(t *testing.T) {
	r := userRouter(t)
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/realname", strings.NewReader(`{"name":"张三","id_number":"11010519491231002X"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusAccepted || !strings.Contains(w.Body.String(), `"status":"pending"`) {
		t.Fatalf("realname=%d %s", w.Code, w.Body.String())
	}
}
