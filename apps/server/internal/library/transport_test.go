package library

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"forgeplay/server/internal/games"
	"github.com/gin-gonic/gin"
)

func TestTransportMutatesAuthenticatedLibrary(t *testing.T) {
	gin.SetMode(gin.TestMode)
	svc := NewService(games.NewService(games.NewMemRepo()))
	// 手动注入下载关系模拟真实用户已下载的游戏(新用户默认空列表,见 downloadsForLocked)。
	svc.mu.Lock()
	svc.userDownloads["u1"] = append([]downloadRel(nil), svc.downloads...)
	svc.mu.Unlock()
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "u1") }
	RegisterRoutes(r, svc, user, user)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v1/downloads?lang=en", nil))
	var list struct {
		Items []DownloadItem `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &list)
	if len(list.Items) != 3 {
		t.Fatalf("items=%d", len(list.Items))
	}
	id := list.Items[0].Game.ID
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, "/api/v1/downloads/"+id, nil))
	if w.Code != http.StatusNoContent {
		t.Fatalf("delete=%d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v1/downloads?lang=en", nil))
	_ = json.Unmarshal(w.Body.Bytes(), &list)
	if len(list.Items) != 2 {
		t.Fatalf("after delete=%d", len(list.Items))
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, "/api/v1/history", nil))
	if w.Code != http.StatusNoContent {
		t.Fatalf("clear=%d", w.Code)
	}
}

func TestTransportRecordsPlay(t *testing.T) {
	gs := games.NewService(games.NewMemRepo())
	g, _ := gs.Publish(games.PublishRequest{ModID: "m", Title: "x"})
	g, _ = gs.Decide(g.ID, true)
	svc := NewService(gs)
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "u") }
	RegisterRoutes(r, svc, user, user)
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/games/"+g.ID+"/played", strings.NewReader(`{"duration_ms":65000}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("played=%d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v1/history?lang=en", nil))
	if !strings.Contains(w.Body.String(), "User Game") && !strings.Contains(w.Body.String(), `"id":"`+g.ID+`"`) {
		t.Fatalf("history=%s", w.Body.String())
	}
}
