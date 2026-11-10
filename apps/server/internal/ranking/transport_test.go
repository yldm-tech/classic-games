package ranking

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/internal/games"
	"github.com/yldm-tech/classic-games/apps/server/internal/social"
)

func init() { gin.SetMode(gin.TestMode) }

func TestHTTP_Ranking(t *testing.T) {
	gsvc := games.NewService(games.NewMemRepo())
	ssvc := social.NewService(social.NewMemRepo())
	a := publishApprove(t, gsvc, "A")
	b := publishApprove(t, gsvc, "B")
	ssvc.Like(b.ID, "u1")
	ssvc.Like(b.ID, "u2")

	r := gin.New()
	RegisterRoutes(r, NewService(gsvc, ssvc))

	// 热门:b(2赞)应排第一
	req := httptest.NewRequest(http.MethodGet, "/api/v1/ranking?type=hot", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("状态码 %d", w.Code)
	}
	var resp struct {
		Type  string   `json:"type"`
		Items []Ranked `json:"items"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if len(resp.Items) != 2 || resp.Items[0].ID != b.ID || resp.Items[0].Rank != 1 {
		t.Errorf("热门榜第一应是 B, got %+v", resp.Items)
	}
	_ = a

	// 未知类型 → 400
	req2 := httptest.NewRequest(http.MethodGet, "/api/v1/ranking?type=bogus", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusBadRequest {
		t.Errorf("未知类型应 400, got %d", w2.Code)
	}
}
