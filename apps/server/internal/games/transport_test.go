package games

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
	// 桩中间件:发布作者固定为 u_test;审核裁决放行(模拟管理员)。
	stub := func(c *gin.Context) { c.Set("user_id", "u_test") }
	RegisterRoutes(r, newSvc(), stub, stub)
	return r
}

func do(t *testing.T, r *gin.Engine, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var rd *bytes.Reader = bytes.NewReader(nil)
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

// 发布 → 审核通过 → 出现在列表。
func TestHTTP_PublishApproveList(t *testing.T) {
	r := newRouter()

	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{
		"mod_id": "mod_1", "title": "电光狂奔", "ai_generated": true,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("发布状态码 %d, body=%s", w.Code, w.Body.String())
	}
	var g Game
	json.Unmarshal(w.Body.Bytes(), &g)
	if g.Status != StatusReviewing {
		t.Fatalf("发布后应 reviewing, got %s", g.Status)
	}

	// 列表此时应为空(还没过审)
	w = do(t, r, http.MethodGet, "/api/v1/games", nil)
	var listResp struct{ Items []Game }
	json.Unmarshal(w.Body.Bytes(), &listResp)
	if len(listResp.Items) != 0 {
		t.Errorf("未过审不应出现在列表, got %d", len(listResp.Items))
	}

	// 审核通过
	w = do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	if w.Code != http.StatusOK {
		t.Fatalf("审核状态码 %d", w.Code)
	}

	// 现在出现在已发布列表
	w = do(t, r, http.MethodGet, "/api/v1/games", nil)
	json.Unmarshal(w.Body.Bytes(), &listResp)
	if len(listResp.Items) != 1 || listResp.Items[0].Status != StatusPublished {
		t.Errorf("过审后应出现在列表且 published, got %+v", listResp.Items)
	}
}

// GET /games/:id 对非已发布态(reviewing/rejected/delisted)只对作者本人可见,匿名/第三方 404。回归守卫 C5。
func TestHTTP_GetGameHidesNonPublishedFromNonOwner(t *testing.T) {
	svc := newSvc()
	g, _ := svc.Publish(PublishRequest{ModID: "m", AuthorID: "owner", Title: "reviewing game"})
	build := func(viewer string) *gin.Engine {
		r := gin.New()
		mw := func(c *gin.Context) {
			if viewer != "" {
				c.Set("user_id", viewer)
			}
		}
		RegisterRoutes(r, svc, mw, mw, mw)
		return r
	}
	if w := do(t, build("outsider"), http.MethodGet, "/api/v1/games/"+g.ID, nil); w.Code != http.StatusNotFound {
		t.Fatalf("第三方不应看到未发布游戏, got %d %s", w.Code, w.Body.String())
	}
	if w := do(t, build(""), http.MethodGet, "/api/v1/games/"+g.ID, nil); w.Code != http.StatusNotFound {
		t.Fatalf("匿名不应看到未发布游戏, got %d", w.Code)
	}
	if w := do(t, build("owner"), http.MethodGet, "/api/v1/games/"+g.ID, nil); w.Code != http.StatusOK {
		t.Fatalf("作者应能看到自己的未发布游戏, got %d %s", w.Code, w.Body.String())
	}
}

func TestHTTP_DecideInvalidState(t *testing.T) {
	r := newRouter()
	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m", "title": "x"})
	var g Game
	json.Unmarshal(w.Body.Bytes(), &g)
	do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	// 再次裁决 → 409 INVALID_STATE
	w = do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	if w.Code != http.StatusConflict {
		t.Errorf("重复裁决状态码 %d, 期望 409", w.Code)
	}
}

func TestHTTP_AuthorDelistAndResubmit(t *testing.T) {
	r := newRouter()
	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m", "title": "x"})
	var g Game
	_ = json.Unmarshal(w.Body.Bytes(), &g)
	do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	w = do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/delist", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("delist %d %s", w.Code, w.Body.String())
	}
	w = do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "r", "title": "r"})
	_ = json.Unmarshal(w.Body.Bytes(), &g)
	do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": false})
	w = do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/resubmit", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("resubmit %d %s", w.Code, w.Body.String())
	}
}

func TestHTTP_ListPagination(t *testing.T) {
	r := newRouter()
	// 发布并过审 3 个
	for i := 0; i < 3; i++ {
		w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m", "title": "g"})
		var g Game
		json.Unmarshal(w.Body.Bytes(), &g)
		do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	}

	type pageResp struct {
		Items      []Game `json:"items"`
		NextCursor string `json:"next_cursor"`
	}
	// 第一页 limit=2
	w := do(t, r, http.MethodGet, "/api/v1/games?limit=2", nil)
	var p1 pageResp
	json.Unmarshal(w.Body.Bytes(), &p1)
	if len(p1.Items) != 2 || p1.NextCursor == "" {
		t.Fatalf("第一页应 2 项 + 游标, got %d cursor=%q", len(p1.Items), p1.NextCursor)
	}
	// 第二页
	w = do(t, r, http.MethodGet, "/api/v1/games?limit=2&cursor="+p1.NextCursor, nil)
	var p2 pageResp
	json.Unmarshal(w.Body.Bytes(), &p2)
	if len(p2.Items) != 1 || p2.NextCursor != "" {
		t.Fatalf("第二页应 1 项 + 空游标, got %d cursor=%q", len(p2.Items), p2.NextCursor)
	}
}

func TestHTTP_ListFiltersRuntimeAndCategory(t *testing.T) {
	svc := newSvc()
	svc.SetModRuntime(func(id string) (string, bool) {
		return map[string]string{"s": "survivor@1.0.0", "t": "tower_defense@1.0.0"}[id], true
	})
	r := gin.New()
	stub := func(c *gin.Context) { c.Set("user_id", "u") }
	RegisterRoutes(r, svc, stub, stub)
	for _, body := range []map[string]any{{"mod_id": "s", "title": "S", "category": "survival"}, {"mod_id": "t", "title": "T", "category": "strategy"}} {
		w := do(t, r, http.MethodPost, "/api/v1/games", body)
		var g Game
		_ = json.Unmarshal(w.Body.Bytes(), &g)
		do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	}
	w := do(t, r, http.MethodGet, "/api/v1/games?runtime=survivor&category=survival", nil)
	var got struct {
		Items []Game `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &got)
	if len(got.Items) != 1 || got.Items[0].Title != "S" {
		t.Fatalf("filter=%d %s", w.Code, w.Body.String())
	}
}

func TestHTTP_ListMineUsesAuthenticatedAuthorAndPrecedesIDRoute(t *testing.T) {
	svc := newSvc()
	owned, _ := svc.Publish(PublishRequest{ModID: "mine", AuthorID: "u", Title: "Mine"})
	_, _ = svc.Publish(PublishRequest{ModID: "foreign", AuthorID: "other", Title: "Foreign"})
	r := gin.New()
	auth := func(c *gin.Context) { c.Set("user_id", "u") }
	RegisterRoutes(r, svc, auth, auth)
	w := do(t, r, http.MethodGet, "/api/v1/games/mine?lang=zh", nil)
	var got struct {
		Items []Game `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &got)
	if w.Code != http.StatusOK || len(got.Items) != 1 || got.Items[0].ID != owned.ID {
		t.Fatalf("mine=%d %s", w.Code, w.Body.String())
	}
}

func TestHTTP_ListSortHot(t *testing.T) {
	svc := newSvc()
	var ids []string
	for _, title := range []string{"low", "high"} {
		g, _ := svc.Publish(PublishRequest{ModID: title, Title: title})
		g, _ = svc.Decide(g.ID, true)
		ids = append(ids, g.ID)
	}
	svc.SetLikeCounter(stubLikes{ids[0]: 9, ids[1]: 1})
	r := gin.New()
	RegisterRoutes(r, svc, nil, nil)
	w := do(t, r, http.MethodGet, "/api/v1/games?sort=hot", nil)
	var got struct {
		Items []Game `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &got)
	if len(got.Items) != 2 || got.Items[0].ID != ids[0] {
		t.Fatalf("hot sort=%s", w.Body.String())
	}
}

func TestHTTP_SearchAndAIFilter(t *testing.T) {
	svc := newSvc()
	r := gin.New()
	stub := func(c *gin.Context) { c.Set("user_id", "u") }
	RegisterRoutes(r, svc, stub, stub)
	for _, body := range []map[string]any{{"mod_id": "m1", "title": "Dragon Arena", "summary": "fire", "category": "action", "ai_generated": true}, {"mod_id": "m2", "title": "Quiet Farm", "summary": "dragon fruit", "category": "sim", "ai_generated": false}} {
		w := do(t, r, http.MethodPost, "/api/v1/games", body)
		var g Game
		_ = json.Unmarshal(w.Body.Bytes(), &g)
		do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	}
	w := do(t, r, http.MethodGet, "/api/v1/games?q=dragon&cat=sim&ai=false", nil)
	var got struct {
		Items []Game `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &got)
	if w.Code != 200 || len(got.Items) != 1 || got.Items[0].Title != "Quiet Farm" {
		t.Fatalf("search=%d %s", w.Code, w.Body.String())
	}
	w = do(t, r, http.MethodGet, "/api/v1/games?ai=invalid", nil)
	if w.Code != 400 {
		t.Fatalf("非法 ai 应 400, got %d", w.Code)
	}
}

func TestHTTP_PublishMissingTitle(t *testing.T) {
	r := newRouter()
	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m"})
	if w.Code != http.StatusBadRequest {
		t.Errorf("缺标题状态码 %d, 期望 400", w.Code)
	}
}

// 作者取自鉴权注入的 user_id,body 里伪造的 author_id 被忽略(防冒名)。
func TestHTTP_PublishAuthorFromToken(t *testing.T) {
	r := newRouter() // 桩中间件把 user_id 固定为 u_test
	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{
		"mod_id": "m", "title": "x", "author_id": "attacker", // 试图伪造
	})
	var g Game
	json.Unmarshal(w.Body.Bytes(), &g)
	if g.AuthorID != "u_test" {
		t.Errorf("作者应来自 token(u_test),body 伪造应被忽略, got %q", g.AuthorID)
	}
}

// 审核裁决套 adminMW:中间件拒绝时返回 403,不进入业务逻辑。
func TestHTTP_DecisionAdminGated(t *testing.T) {
	r := gin.New()
	stubAuth := func(c *gin.Context) { c.Set("user_id", "u_test") }
	denyAdmin := func(c *gin.Context) { c.AbortWithStatus(http.StatusForbidden) }
	RegisterRoutes(r, newSvc(), stubAuth, denyAdmin)

	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m", "title": "x"})
	var g Game
	json.Unmarshal(w.Body.Bytes(), &g)

	w = do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/decision", map[string]any{"approve": true})
	if w.Code != http.StatusForbidden {
		t.Errorf("非管理员裁决应 403, got %d", w.Code)
	}
}

func TestHTTP_ModerationQueueOnlyReturnsReviewing(t *testing.T) {
	r := newRouter()
	var reviewing, published Game
	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m1", "title": "review me"})
	_ = json.Unmarshal(w.Body.Bytes(), &reviewing)
	w = do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m2", "title": "publish me"})
	_ = json.Unmarshal(w.Body.Bytes(), &published)
	do(t, r, http.MethodPost, "/api/v1/games/"+published.ID+"/decision", map[string]any{"approve": true})

	w = do(t, r, http.MethodGet, "/api/v1/moderation/queue", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("queue status=%d body=%s", w.Code, w.Body.String())
	}
	var got struct {
		Items []Game `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &got)
	if len(got.Items) != 1 || got.Items[0].ID != reviewing.ID || got.Items[0].Status != StatusReviewing {
		t.Fatalf("队列应只含待审作品: %+v", got.Items)
	}
}

func TestHTTP_ModerationQueueAdminGated(t *testing.T) {
	r := gin.New()
	deny := func(c *gin.Context) { c.AbortWithStatus(http.StatusForbidden) }
	RegisterRoutes(r, newSvc(), func(c *gin.Context) {}, deny)
	w := do(t, r, http.MethodGet, "/api/v1/moderation/queue", nil)
	if w.Code != http.StatusForbidden {
		t.Fatalf("非管理员读取队列应 403, got %d", w.Code)
	}
}

// stubLikes 是 LikeCounter 桩:返回固定的实时点赞数。
type stubLikes map[string]int

func (s stubLikes) LikeCount(id string) (int, error) { return s[id], nil }
func (s stubLikes) LikeCounts(ids []string) (map[string]int, error) {
	out := map[string]int{}
	for _, id := range ids {
		out[id] = s[id]
	}
	return out, nil
}

// 注入 LikeCounter 后,/games 与 /games/:id 的 likes 以 social 为准覆盖库里的静态值。
func TestHTTP_LikesOverlay(t *testing.T) {
	svc := newSvc()
	g, err := svc.Publish(PublishRequest{ModID: "m", Title: "T"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Decide(g.ID, true); err != nil {
		t.Fatal(err)
	}
	svc.SetLikeCounter(stubLikes{g.ID: 9301})

	r := gin.New()
	RegisterRoutes(r, svc, func(c *gin.Context) { c.Set("user_id", "u") }, func(c *gin.Context) { c.Set("user_id", "u") })

	w := do(t, r, http.MethodGet, "/api/v1/games/"+g.ID, nil)
	var got Game
	json.Unmarshal(w.Body.Bytes(), &got)
	if got.Likes != 9301 {
		t.Errorf("详情 likes 应被 social 覆盖为 9301, got %d", got.Likes)
	}

	w = do(t, r, http.MethodGet, "/api/v1/games", nil)
	var list struct{ Items []Game }
	json.Unmarshal(w.Body.Bytes(), &list)
	if len(list.Items) != 1 || list.Items[0].Likes != 9301 {
		t.Errorf("列表 likes 应被 social 覆盖为 9301, got %+v", list.Items)
	}
}

// The seeded catalogue stores capitalised categories ("Arcade") while the explore screen sends its chip label
// lowercased, and nothing normalises either side. An exact comparison therefore made every category chip return an
// empty list. The filter matches case-insensitively, like the free-text query alongside it.
func TestHTTP_CategoryFilterIgnoresCase(t *testing.T) {
	svc := newSvc()
	svc.SetModRuntime(func(id string) (string, bool) { return "shooter@1.0.0", true })
	r := gin.New()
	stub := func(c *gin.Context) { c.Set("user_id", "u") }
	RegisterRoutes(r, svc, stub, stub)
	w := do(t, r, http.MethodPost, "/api/v1/games", map[string]any{"mod_id": "m", "title": "Neon Drift", "category": "Racing"})
	var published Game
	if err := json.Unmarshal(w.Body.Bytes(), &published); err != nil {
		t.Fatal(err)
	}
	do(t, r, http.MethodPost, "/api/v1/games/"+published.ID+"/decision", map[string]any{"approve": true})

	for _, sent := range []string{"Racing", "racing", "RACING"} {
		listed := do(t, r, http.MethodGet, "/api/v1/games?category="+sent, nil)
		var got struct {
			Items []Game `json:"items"`
		}
		if err := json.Unmarshal(listed.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if len(got.Items) != 1 || got.Items[0].Title != "Neon Drift" {
			t.Fatalf("category=%q returned %d items (%s), want the one published game", sent, len(got.Items), listed.Body.String())
		}
	}
}
