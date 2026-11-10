package prefs

import (
	"bytes"
	"encoding/json"
	"errors"
	"forgeplay/server/internal/storage"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func newSvc(t *testing.T) *Service {
	t.Helper()
	s, err := NewService()
	if err != nil {
		t.Fatalf("NewService 失败: %v", err)
	}
	return s
}

func TestPreferencesSurviveRestart(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	store, _ := NewGormStateStore(db)
	s, _ := NewServiceWithStore(store)
	_ = s.SetNotification("u", "push_master", false)
	_ = s.SetPrivacy("u", "who_sees_games", 1)
	_ = s.SetTeen("u", true, "1234")
	again, e := NewServiceWithStore(store)
	if e != nil {
		t.Fatal(e)
	}
	if again.NotificationsFor("u", "zh").MasterDefault {
		t.Fatal("notification lost")
	}
	if again.PrivacyFor("u", "zh").Items[0].DefaultIndex != 1 {
		t.Fatalf("privacy=%+v", again.PrivacyFor("u", "zh"))
	}
	if !again.TeenFor("u", "zh").DefaultEnabled {
		t.Fatal("teen lost")
	}
}

func TestPreferenceWritesAreUserScopedAndTeenPINProtected(t *testing.T) {
	s := newSvc(t)
	if err := s.SetNotification("u1", "push_master", false); err != nil {
		t.Fatal(err)
	}
	if s.NotificationsFor("u1", "zh").MasterDefault || !s.NotificationsFor("u2", "zh").MasterDefault {
		t.Fatal("notification state leaked")
	}
	if err := s.SetPrivacy("u1", "show_online_status", false); err != nil {
		t.Fatal(err)
	}
	if err := s.SetTeen("u1", true, "1234"); err != nil {
		t.Fatal(err)
	}
	if !s.TeenFor("u1", "zh").DefaultEnabled {
		t.Fatal("teen not enabled")
	}
	if err := s.SetTeen("u1", false, "9999"); err != ErrInvalidPIN {
		t.Fatalf("wrong pin=%v", err)
	}
	if err := s.SetTeen("u1", false, "1234"); err != nil {
		t.Fatal(err)
	}
}

func TestGuardPlayEnforcesCurfewAndDailyLimit(t *testing.T) {
	s := newSvc(t)
	day := time.Date(2026, 8, 24, 15, 0, 0, 0, time.UTC)
	if err := s.GuardPlay("kid", 10, day); err != nil {
		t.Fatalf("teen off should allow: %v", err)
	}
	if err := s.SetTeen("kid", true, "1234"); err != nil {
		t.Fatal(err)
	}
	if err := s.GuardPlay("kid", 0, time.Date(2026, 8, 24, 22, 0, 0, 0, time.UTC)); !errors.Is(err, ErrTeenCurfew) {
		t.Fatalf("curfew=%v", err)
	}
	if err := s.GuardPlay("kid", TeenDailyLimitSecs, day); err != nil {
		t.Fatalf("first fill=%v", err)
	}
	if err := s.GuardPlay("kid", 1, day); !errors.Is(err, ErrTeenLimit) {
		t.Fatalf("limit=%v", err)
	}
}

// 已启用青少年模式后,不能用"重新启用+设新 PIN"覆盖家长 PIN(否则再用新 PIN 关闭即绕过)。回归守卫 C12。
func TestSetTeen_CannotResetPINWhileEnabled(t *testing.T) {
	s := newSvc(t)
	if err := s.SetTeen("kid", true, "1234"); err != nil {
		t.Fatal(err)
	}
	// 用错误 PIN 试图重新启用并改 PIN → 必须被拒。
	if err := s.SetTeen("kid", true, "0000"); err != ErrInvalidPIN {
		t.Fatalf("已启用后用错误 PIN 改 PIN 应 ErrInvalidPIN, got %v", err)
	}
	// PIN 未被覆盖:原 PIN 仍能且必须用于关闭;新 PIN 关不掉。
	if err := s.SetTeen("kid", false, "0000"); err != ErrInvalidPIN {
		t.Fatalf("伪 PIN 不应能关闭青少年模式, got %v", err)
	}
	if err := s.SetTeen("kid", false, "1234"); err != nil {
		t.Fatalf("原 PIN 应能关闭: %v", err)
	}
}

func newRouter(t *testing.T) *gin.Engine {
	t.Helper()
	r := gin.New()
	RegisterRoutes(r, newSvc(t))
	return r
}

func get(r *gin.Engine, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// 种子非空:四类设置都应解析出内容。
func TestSeeds_NonEmpty(t *testing.T) {
	s := newSvc(t)

	n := s.Notifications(LangZh)
	if n.MasterKey == "" || len(n.Groups) != 2 {
		t.Fatalf("通知种子异常: master=%q groups=%d", n.MasterKey, len(n.Groups))
	}
	total := 0
	for _, g := range n.Groups {
		if g.Key == "" || len(g.Items) == 0 {
			t.Errorf("分组异常: %+v", g)
		}
		total += len(g.Items)
	}
	if total != 7 {
		t.Errorf("通知项总数=%d, 期望 7", total)
	}

	p := s.Privacy(LangZh)
	if len(p.Items) != 5 {
		t.Errorf("隐私项=%d, 期望 5", len(p.Items))
	}

	tn := s.Teen(LangZh)
	if tn.Title == "" || len(tn.Rules) != 3 {
		t.Errorf("青少年种子异常: title=%q rules=%d", tn.Title, len(tn.Rules))
	}
	if tn.DefaultEnabled {
		t.Error("青少年模式默认应为关闭")
	}

	b := s.Blocks(LangZh)
	if len(b) != 2 {
		t.Errorf("黑名单=%d, 期望 2", len(b))
	}
}

// 本地化:zh / en / ja 各取到对应语种文本;未知语言回落 zh。
func TestLocalization_Resolves(t *testing.T) {
	s := newSvc(t)

	cases := []struct {
		lang string
		want string // master label
	}{
		{LangZh, "接收推送通知"},
		{LangEn, "Push notifications"},
		{LangJa, "プッシュ通知を受け取る"},
		{"fr", "接收推送通知"}, // 未知 → 回落 zh
		{"", "接收推送通知"},   // 缺省 → zh
	}
	for _, c := range cases {
		got := s.Notifications(c.lang).MasterLabel
		if got != c.want {
			t.Errorf("lang=%q master label=%q, 期望 %q", c.lang, got, c.want)
		}
	}

	// 段控选项随语言切换。
	pEn := s.Privacy(LangEn)
	if len(pEn.Items) == 0 || pEn.Items[0].Kind != "segment" {
		t.Fatalf("首个隐私项应为 segment, got %+v", pEn.Items)
	}
	if len(pEn.Items[0].Options) != 3 || pEn.Items[0].Options[0] != "Everyone" {
		t.Errorf("en 段控选项异常: %+v", pEn.Items[0].Options)
	}

	// 默认值不随语言变。
	if s.Teen(LangZh).PinLength != s.Teen(LangJa).PinLength {
		t.Error("pin_length 不应随语言变化")
	}
}

// 隐私项区分 segment / toggle:segment 带 options + default_index,toggle 带 default。
func TestPrivacy_ItemKinds(t *testing.T) {
	p := newSvc(t).Privacy(LangZh)
	var segs, toggles int
	for _, it := range p.Items {
		switch it.Kind {
		case "segment":
			segs++
			if len(it.Options) == 0 {
				t.Errorf("segment %q 缺 options", it.Key)
			}
		case "toggle":
			toggles++
			if len(it.Options) != 0 {
				t.Errorf("toggle %q 不应有 options", it.Key)
			}
		default:
			t.Errorf("未知 kind: %q", it.Kind)
		}
	}
	if segs != 2 || toggles != 3 {
		t.Errorf("隐私项 segment=%d toggle=%d, 期望 2/3", segs, toggles)
	}
}

// 端点 200,且返回体可反序列化为对应结构。
func TestHTTP_Endpoints200(t *testing.T) {
	r := newRouter(t)

	for _, path := range []string{
		"/api/v1/prefs/notifications",
		"/api/v1/prefs/notifications?lang=en",
		"/api/v1/prefs/privacy?lang=ja",
		"/api/v1/prefs/teen",
	} {
		w := get(r, path)
		if w.Code != http.StatusOK {
			t.Errorf("GET %s 状态码 %d, 期望 200; body=%s", path, w.Code, w.Body)
		}
	}

	// /blocks 已迁到 moderation 域(返回真实黑名单),prefs 不再提供,故此处不测。

	// notifications 端点形态。
	w := get(r, "/api/v1/prefs/notifications?lang=en")
	var n NotifPrefs
	if err := json.Unmarshal(w.Body.Bytes(), &n); err != nil {
		t.Fatalf("notifications 返回体非法 JSON: %v", err)
	}
	if n.MasterLabel != "Push notifications" {
		t.Errorf("en master label=%q", n.MasterLabel)
	}
}

func TestHTTP_PreferenceWrites(t *testing.T) {
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "u1") }
	RegisterRoutes(r, newSvc(t), user, user)
	cases := map[string]string{"/api/v1/prefs/notifications/push_master": `{"value":false}`, "/api/v1/prefs/privacy/show_online_status": `{"value":false}`, "/api/v1/prefs/teen": `{"enabled":true,"pin":"1234"}`}
	for path, body := range cases {
		req := httptest.NewRequest(http.MethodPost, path, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != 200 {
			t.Fatalf("%s=%d %s", path, w.Code, w.Body.String())
		}
	}
}
