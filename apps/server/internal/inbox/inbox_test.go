package inbox

import (
	"bytes"
	"encoding/json"
	"forgeplay/server/internal/storage"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func TestInboxWritesSurviveRestart(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	store, _ := NewGormStateStore(db)
	s, _ := NewServiceWithStore(store)
	_, _ = s.SendMessage("u", 0, "hello")
	_ = s.SetFollowing("u", "@alice", true)
	_ = s.AddFriend("u", "@bob")
	again, e := NewServiceWithStore(store)
	if e != nil {
		t.Fatal(e)
	}
	msgs, ok := again.MessagesFor("u", 0, "en")
	if !ok || msgs[len(msgs)-1].Text != "hello" {
		t.Fatalf("messages=%+v", msgs)
	}
	if !again.IsFollowing("u", "@alice") || !again.IsFriend("u", "@bob") {
		t.Fatal("relations lost")
	}
}

func TestAuthenticatedMessagesContainOnlyPersistedMessages(t *testing.T) {
	s := NewService()
	before, ok := s.MessagesFor("real-user", 0, "zh")
	if !ok || len(before) != 0 {
		t.Fatalf("new user received demo messages: %+v", before)
	}
	after, err := s.SendMessage("real-user", 0, "实际发送")
	if err != nil || len(after) != 1 || !after[0].Mine || after[0].Text != "实际发送" {
		t.Fatalf("persisted messages=%+v err=%v", after, err)
	}
}

func TestRealConversationsComeFromFriendsAndPersistByHandle(t *testing.T) {
	s := NewService()
	if got := s.ChatsFor("u", "zh"); len(got) != 0 {
		t.Fatalf("new user demo chats=%+v", got)
	}
	if err := s.AddFriend("u", "@bob"); err != nil {
		t.Fatal(err)
	}
	if got := s.ChatsFor("u", "zh"); len(got) != 1 || got[0].Handle != "@bob" {
		t.Fatalf("friend chats=%+v", got)
	}
	if _, err := s.SendMessageTo("u", "@stranger", "no"); err == nil {
		t.Fatal("must reject non-friend conversation")
	}
	items, err := s.SendMessageTo("u", "@bob", "hello")
	if err != nil || len(items) != 1 || items[0].Text != "hello" || !items[0].Mine {
		t.Fatalf("messages=%+v err=%v", items, err)
	}
	chats := s.ChatsFor("u", "zh")
	if chats[0].LastMessage != "hello" {
		t.Fatalf("last message=%+v", chats)
	}
}

func newRouter() *gin.Engine {
	r := gin.New()
	RegisterRoutes(r, NewService())
	return r
}

func get(t *testing.T, r *gin.Engine, path string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// 种子非空:每个资源都应解码出内容。
func TestService_SeedsNonEmpty(t *testing.T) {
	s := NewService()
	if len(s.Activity("zh")) == 0 {
		t.Error("activity 种子为空")
	}
	if len(s.Chats("zh")) == 0 {
		t.Error("chats 种子为空")
	}
	if s.ChatCount() == 0 {
		t.Error("ChatCount 为 0")
	}
	if len(s.autoReplies) == 0 {
		t.Error("auto_replies 种子为空")
	}
	following, ok := s.Follow("following", "zh")
	if !ok || len(following) == 0 {
		t.Error("following 种子为空")
	}
	followers, ok := s.Follow("followers", "zh")
	if !ok || len(followers) == 0 {
		t.Error("followers 种子为空")
	}
	sugs, code := s.Suggestions("zh")
	if len(sugs) == 0 {
		t.Error("suggestions 种子为空")
	}
	if code == "" {
		t.Error("invite_code 为空")
	}
}

// 本地化:同一条记录在 zh/en/ja 下解析出不同文案,缺省与非法 lang 回落 zh。
func TestService_Localization(t *testing.T) {
	s := NewService()
	zh := s.Activity("zh")[0].Title
	en := s.Activity("en")[0].Title
	ja := s.Activity("ja")[0].Title
	if zh == en || zh == ja || en == ja {
		t.Errorf("三语应不同: zh=%q en=%q ja=%q", zh, en, ja)
	}
	// 缺省 lang 回落 zh
	if s.Activity("")[0].Title != zh {
		t.Errorf("空 lang 应回落 zh, got %q", s.Activity("")[0].Title)
	}
	// 非法 lang 回落 zh
	if s.Activity("fr")[0].Title != zh {
		t.Errorf("非法 lang 应回落 zh, got %q", s.Activity("fr")[0].Title)
	}
}

func TestService_MessagesBounds(t *testing.T) {
	s := NewService()
	// 有效索引:对方种子消息 + 自动回复,首条为对方发出。
	msgs, ok := s.Messages(0, "zh")
	if !ok || len(msgs) == 0 {
		t.Fatalf("会话 0 应有消息, ok=%v len=%d", ok, len(msgs))
	}
	if msgs[0].Mine {
		t.Error("首条应为对方消息 (Mine=false)")
	}
	// 越界
	if _, ok := s.Messages(-1, "zh"); ok {
		t.Error("负索引应返回 ok=false")
	}
	if _, ok := s.Messages(s.ChatCount(), "zh"); ok {
		t.Error("越界索引应返回 ok=false")
	}
}

func TestService_FollowKinds(t *testing.T) {
	s := NewService()
	if _, ok := s.Follow("bogus", "zh"); ok {
		t.Error("非法 kind 应返回 ok=false")
	}
}

func TestDocumentedFollowRoutes(t *testing.T) {
	r := gin.New()
	auth := func(c *gin.Context) { c.Set("user_id", "alice"); c.Next() }
	RegisterRoutes(r, NewService(), nil, auth)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/users/bob/follow", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("follow=%d %s", w.Code, w.Body.String())
	}
	w = get(t, r, "/api/v1/users/alice/following")
	if w.Code != http.StatusOK || !bytes.Contains(w.Body.Bytes(), []byte(`"handle":"bob"`)) {
		t.Fatalf("following=%d %s", w.Code, w.Body.String())
	}
	w = get(t, r, "/api/v1/users/bob/followers")
	if w.Code != http.StatusOK || !bytes.Contains(w.Body.Bytes(), []byte(`"handle":"alice"`)) {
		t.Fatalf("followers=%d %s", w.Code, w.Body.String())
	}
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/users/bob/follow", nil)
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("unfollow=%d", w.Code)
	}
}

func TestDocumentedConversationRoutes(t *testing.T) {
	r := newRouter()
	w := get(t, r, "/api/v1/messages/conversations")
	if w.Code != 200 || !bytes.Contains(w.Body.Bytes(), []byte(`"items"`)) {
		t.Fatalf("conversations=%d %s", w.Code, w.Body.String())
	}
	w = get(t, r, "/api/v1/messages/0")
	if w.Code != 200 || !bytes.Contains(w.Body.Bytes(), []byte(`"items"`)) {
		t.Fatalf("messages=%d %s", w.Code, w.Body.String())
	}
}

// 所有读端点 200；用户关系允许真实空列表，其余目录种子非空。
func TestHTTP_EndpointsOK(t *testing.T) {
	r := newRouter()
	cases := []string{
		"/api/v1/activity",
		"/api/v1/activity?lang=en",
		"/api/v1/chats",
		"/api/v1/chats?lang=ja",
		"/api/v1/chats/0/messages",
		"/api/v1/chats/0/messages?lang=en",
		"/api/v1/follow",
		"/api/v1/follow?type=followers",
		"/api/v1/friends/suggestions?lang=ja",
	}
	for _, path := range cases {
		w := get(t, r, path)
		if w.Code != http.StatusOK {
			t.Errorf("%s 状态码 %d, body=%s", path, w.Code, w.Body.String())
			continue
		}
		var resp struct {
			Items []json.RawMessage `json:"items"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Errorf("%s 响应不是合法 JSON: %v", path, err)
			continue
		}
		isRelation := strings.HasPrefix(path, "/api/v1/follow")
		if len(resp.Items) == 0 && !isRelation {
			t.Errorf("%s items 为空", path)
		}
	}
}

func TestHTTP_SuggestionsInviteCode(t *testing.T) {
	r := newRouter()
	w := get(t, r, "/api/v1/friends/suggestions")
	var resp struct {
		InviteCode string `json:"invite_code"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp.InviteCode == "" {
		t.Error("suggestions 应返回 invite_code")
	}
}

func TestHTTP_MessagesNotFound(t *testing.T) {
	r := newRouter()
	w := get(t, r, "/api/v1/chats/999/messages")
	if w.Code != http.StatusNotFound {
		t.Errorf("越界会话应 404, got %d", w.Code)
	}
}

func TestHTTP_MessagesBadIdx(t *testing.T) {
	r := newRouter()
	w := get(t, r, "/api/v1/chats/abc/messages")
	if w.Code != http.StatusBadRequest {
		t.Errorf("非整数 idx 应 400, got %d", w.Code)
	}
}

func TestHTTP_FollowBadType(t *testing.T) {
	r := newRouter()
	w := get(t, r, "/api/v1/follow?type=bogus")
	if w.Code != http.StatusBadRequest {
		t.Errorf("非法 type 应 400, got %d", w.Code)
	}
}

func TestWritesAreUserScoped(t *testing.T) {
	s := NewService()
	if _, err := s.SendMessage("u1", 0, "hello"); err != nil {
		t.Fatal(err)
	}
	u1, _ := s.MessagesFor("u1", 0, "en")
	u2, _ := s.MessagesFor("u2", 0, "en")
	if len(u1) != len(u2)+1 || !u1[len(u1)-1].Mine {
		t.Fatalf("u1=%v u2=%v", u1, u2)
	}
	s.SetFollowing("u1", "@nova", true)
	if !s.IsFollowing("u1", "@nova") || s.IsFollowing("u2", "@nova") {
		t.Fatal("follow state leaked")
	}
	s.AddFriend("u1", "@rex")
	if !s.IsFriend("u1", "@rex") || s.IsFriend("u2", "@rex") {
		t.Fatal("friend state leaked")
	}
}

func TestHTTP_SendMessageFollowAndFriend(t *testing.T) {
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "u1") }
	RegisterRoutes(r, NewService(), user, user)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/chats/0/messages?lang=en", bytes.NewBufferString(`{"text":"hello"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("message=%d %s", w.Code, w.Body.String())
	}
	for _, path := range []string{"/api/v1/follow/%40nova", "/api/v1/friends/%40rex"} {
		req = httptest.NewRequest(http.MethodPost, path, nil)
		w = httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code < 200 || w.Code >= 300 {
			t.Fatalf("%s=%d", path, w.Code)
		}
	}
}

func TestHTTP_FollowListUsesAuthenticatedRelationsWithoutSeedPeople(t *testing.T) {
	r := gin.New()
	s := NewService()
	user := func(c *gin.Context) { c.Set("user_id", "u-real") }
	RegisterRoutes(r, s, user, user)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/follow/%40real_target", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("follow=%d", w.Code)
	}
	w = get(t, r, "/api/v1/follow?type=following")
	var body struct {
		Items []Person `json:"items"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Items) != 1 || body.Items[0].Handle != "@real_target" {
		t.Fatalf("authoritative following=%s", w.Body.String())
	}
}

func TestHTTP_AuthenticatedActivityDoesNotReturnDemoNotifications(t *testing.T) {
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "new-user") }
	RegisterRoutes(r, NewService(), user, user)
	w := get(t, r, "/api/v1/activity")
	var body struct {
		Items []Activity `json:"items"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if w.Code != http.StatusOK || len(body.Items) != 0 {
		t.Fatalf("new user must not receive demo activity: %s", w.Body.String())
	}
}

func TestHTTP_AuthenticatedSuggestionsDoNotReturnDemoPeopleOrInviteCode(t *testing.T) {
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "new-user") }
	RegisterRoutes(r, NewService(), user, user)
	w := get(t, r, "/api/v1/friends/suggestions")
	var body struct {
		Items      []Suggestion `json:"items"`
		InviteCode string       `json:"invite_code"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Items) != 0 || body.InviteCode != "" {
		t.Fatalf("demo suggestions=%s", w.Body.String())
	}
}

func TestHTTP_RealConversationRoutesUseFriendHandle(t *testing.T) {
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "u") }
	RegisterRoutes(r, NewService(), user, user)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/friends/%40bob", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	w = get(t, r, "/api/v1/messages/conversations")
	var chats struct {
		Items []Chat `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &chats)
	if len(chats.Items) != 1 || chats.Items[0].Handle != "@bob" {
		t.Fatalf("chats=%s", w.Body.String())
	}
	req = httptest.NewRequest(http.MethodPost, "/api/v1/conversations/%40bob/messages", bytes.NewBufferString(`{"text":"hello"}`))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusCreated || !bytes.Contains(w.Body.Bytes(), []byte("hello")) {
		t.Fatalf("send=%d %s", w.Code, w.Body.String())
	}
	w = get(t, r, "/api/v1/conversations/%40bob/messages")
	if w.Code != http.StatusOK || !bytes.Contains(w.Body.Bytes(), []byte("hello")) {
		t.Fatalf("read=%d %s", w.Code, w.Body.String())
	}
}
