package social

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func newRouter() *gin.Engine {
	r := gin.New()
	// 写接口身份来自鉴权中间件注入的 user_id;测试用桩中间件固定为 u1。读接口软鉴权传 nil(匿名)。
	stubAuth := func(c *gin.Context) { c.Set("user_id", "u1") }
	RegisterRoutes(r, newSvc(), stubAuth, nil)
	return r
}

func do(t *testing.T, r *gin.Engine, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	rd := bytes.NewReader(nil)
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, rd)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestHTTP_CommentAndLike(t *testing.T) {
	r := newRouter()

	// 发评论
	w := do(t, r, http.MethodPost, "/api/v1/games/game_1/comments", map[string]any{"author_id": "u1", "content": "好玩"})
	if w.Code != http.StatusCreated {
		t.Fatalf("发评论 %d, body=%s", w.Code, w.Body.String())
	}
	// 列评论
	w = do(t, r, http.MethodGet, "/api/v1/games/game_1/comments", nil)
	var list struct{ Items []Comment }
	json.Unmarshal(w.Body.Bytes(), &list)
	if len(list.Items) != 1 {
		t.Errorf("应有 1 条评论, got %d", len(list.Items))
	}

	// 点赞
	w = do(t, r, http.MethodPost, "/api/v1/games/game_1/like?user_id=u1", nil)
	var ls struct {
		Count int  `json:"count"`
		Liked bool `json:"liked"`
	}
	json.Unmarshal(w.Body.Bytes(), &ls)
	if ls.Count != 1 || !ls.Liked {
		t.Errorf("点赞后应 count=1 liked=true, got %+v", ls)
	}
	// 取消赞
	w = do(t, r, http.MethodDelete, "/api/v1/games/game_1/like?user_id=u1", nil)
	json.Unmarshal(w.Body.Bytes(), &ls)
	if ls.Count != 0 || ls.Liked {
		t.Errorf("取消后应 count=0 liked=false, got %+v", ls)
	}
}

func TestHTTP_EmptyComment(t *testing.T) {
	r := newRouter()
	w := do(t, r, http.MethodPost, "/api/v1/games/g/comments", map[string]any{"author_id": "u", "content": ""})
	if w.Code != http.StatusBadRequest {
		t.Errorf("空评论应 400, got %d", w.Code)
	}
}

func TestHTTP_FavoriteAndList(t *testing.T) {
	r := newRouter()
	w := do(t, r, http.MethodPost, "/api/v1/games/game_1/favorite", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("favorite=%d %s", w.Code, w.Body.String())
	}
	w = do(t, r, http.MethodGet, "/api/v1/favorites", nil)
	var got struct {
		Items []string `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &got)
	if w.Code != http.StatusOK || len(got.Items) != 1 || got.Items[0] != "game_1" {
		t.Fatalf("favorites=%d %+v", w.Code, got.Items)
	}
	w = do(t, r, http.MethodDelete, "/api/v1/games/game_1/favorite", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("unfavorite=%d", w.Code)
	}
}
