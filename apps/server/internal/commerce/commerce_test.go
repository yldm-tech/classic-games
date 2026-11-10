package commerce

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func newSvc(t *testing.T) *Service {
	t.Helper()
	s, err := NewService()
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}
	return s
}

func TestAuthenticatedPointsLedgerContainsOnlyRealMutations(t *testing.T) {
	s := newSvc(t)
	welfare := s.WelfareFor("new-user", LocaleZH)
	if welfare.Checkin.Streak != 0 || welfare.Checkin.Checked || welfare.Invite.Code == "" || welfare.Invite.Code == "KORU-2380" {
		t.Fatalf("new user welfare=%+v", welfare)
	}
	for _, quest := range welfare.Quests {
		if quest.Progress != 0 {
			t.Fatalf("demo quest progress=%+v", quest)
		}
	}
	if got := s.PointsFor("new-user", LocaleZH); got.Balance != 0 || len(got.Ledger) != 0 || got.Earnings.Total != 0 || len(got.Earnings.Ledger) != 0 {
		t.Fatalf("new user received demo wallet: %+v", got)
	}
	_, reward, err := s.Checkin("new-user")
	if err != nil {
		t.Fatal(err)
	}
	got := s.PointsFor("new-user", LocaleZH)
	if len(got.Ledger) != 1 || got.Ledger[0].Amount != reward {
		t.Fatalf("ledger=%+v reward=%d", got.Ledger, reward)
	}
	if err := s.CreditPoints("new-user", 50); err != nil {
		t.Fatal(err)
	}
	got = s.PointsFor("new-user", LocaleZH)
	if got.Earnings.Total != 50 || len(got.Earnings.Ledger) != 1 || got.Earnings.Ledger[0].Amount != 50 {
		t.Fatalf("earnings=%+v", got.Earnings)
	}
}

func TestConfirmedActionsAdvanceQuestAndAchievementProgress(t *testing.T) {
	s := newSvc(t)
	for _, gameID := range []string{"g1", "g2", "g2", "g3"} {
		if err := s.RecordAction("u", "play", gameID, 0); err != nil {
			t.Fatal(err)
		}
	}
	_ = s.RecordAction("u", "comment", "", 0)
	_ = s.RecordAction("u", "remix", "", 0)
	_ = s.RecordAction("u", "publish", "", 0)
	_ = s.RecordAction("u", "score", "", 60000)
	w := s.WelfareFor("u", LocaleZH)
	got := map[string]int{}
	for _, q := range w.Quests {
		got[q.ID] = q.Progress
	}
	if got["quest_play_3"] != 3 || got["quest_comment_1"] != 1 || got["quest_remix_1"] != 1 {
		t.Fatalf("quest progress=%v", got)
	}
	a := s.AchievementsFor("u", LocaleZH)
	ach := map[string]int{}
	for _, item := range a {
		ach[item.ID] = item.Progress
	}
	if ach["ach_first_launch"] != 1 || ach["ach_remix_pro"] != 1 || ach["ach_touch_master"] != 60000 {
		t.Fatalf("achievement progress=%v", ach)
	}
	if _, _, err := s.ClaimQuest("u", "quest_play_3"); err != nil {
		t.Fatal(err)
	}
}

func TestDailyQuestProgressAndClaimsResetOnNewUTCDate(t *testing.T) {
	s := newSvc(t)
	_ = s.RecordAction("u", "comment", "", 0)
	st := s.users["u"]
	st.Quests["quest_comment_1"] = true
	st.QuestDay = "2000-01-01"
	w := s.WelfareFor("u", LocaleZH)
	for _, q := range w.Quests {
		if q.ID == "quest_comment_1" && (q.Progress != 0 || q.Claimed) {
			t.Fatalf("stale daily state not reset: %+v", q)
		}
	}
}

func TestSendLiveGiftDebitsUserBalance(t *testing.T) {
	s, err := NewService()
	if err != nil {
		t.Fatal(err)
	}
	before := s.PointsFor("gift_user", "zh").Balance
	if before != 0 {
		t.Fatalf("new wallet should start empty, got %d", before)
	}
	if err := s.ApplyPayment("gift-setup", "gift_user", "points", 100); err != nil {
		t.Fatal(err)
	}
	before = s.PointsFor("gift_user", "zh").Balance
	after, err := s.SendLiveGift("gift_user", 10)
	if err != nil || after != before-10 {
		t.Fatalf("gift balance=%d err=%v before=%d", after, err, before)
	}
}

// flakyCommerceStore 可切换 Save 失败,模拟瞬时持久化故障。
type flakyCommerceStore struct {
	rows map[string]*userState
	fail bool
}

func (s *flakyCommerceStore) Load(userID string) (*userState, error) { return s.rows[userID], nil }
func (s *flakyCommerceStore) Save(userID string, st *userState) error {
	if s.fail {
		return errors.New("store down")
	}
	s.rows[userID] = st
	return nil
}

// 支付到账持久化失败时,必须回滚内存(含幂等标记),否则重试被 AppliedPayments 短路、真金到账丢失。回归守卫 C9。
func TestApplyPayment_RollsBackOnPersistFailure(t *testing.T) {
	store := &flakyCommerceStore{rows: map[string]*userState{}, fail: true}
	s, err := NewServiceWithStore(store)
	if err != nil {
		t.Fatal(err)
	}
	before := s.PointsFor("buyer", "zh").Balance
	// 持久化失败:应返回错误,且不留下到账余额或已应用标记。
	if err := s.ApplyPayment("pay_x", "buyer", "points", 300); err == nil {
		t.Fatal("持久化失败时 ApplyPayment 应返回错误")
	}
	if got := s.PointsFor("buyer", "zh").Balance; got != before {
		t.Fatalf("失败后余额应回滚, want %d got %d", before, got)
	}
	// 恢复存储后重试:幂等标记已回滚,应真正入账恰好一次。
	store.fail = false
	if err := s.ApplyPayment("pay_x", "buyer", "points", 300); err != nil {
		t.Fatalf("重试应成功: %v", err)
	}
	if got := s.PointsFor("buyer", "zh").Balance; got != before+300 {
		t.Fatalf("重试应入账 300, want %d got %d", before+300, got)
	}
}

func TestApplyPaymentIsIdempotentByOrder(t *testing.T) {
	s, err := NewService()
	if err != nil {
		t.Fatal(err)
	}
	before := s.PointsFor("pay_user", "zh").Balance
	if err = s.ApplyPayment("order_1", "pay_user", "points", 300); err != nil {
		t.Fatal(err)
	}
	if err = s.ApplyPayment("order_1", "pay_user", "points", 300); err != nil {
		t.Fatal(err)
	}
	if got := s.PointsFor("pay_user", "zh").Balance; got != before+300 {
		t.Fatalf("duplicate order credited twice: %d", got)
	}
	if err = s.ApplyPayment("order_2", "pay_user", "points", 60); err != nil {
		t.Fatal(err)
	}
	if got := s.PointsFor("pay_user", "zh").Balance; got != before+360 {
		t.Fatalf("second order missing: %d", got)
	}
}

// 种子非空:每个资源解析后至少有内容,确保内嵌 JSON 真的被装载了。
func TestSeed_NonEmpty(t *testing.T) {
	s := newSvc(t)
	cases := []struct {
		name string
		got  int
	}{
		{"points.ledger", len(s.Points(LocaleZH).Ledger)},
		{"points.earnings.ledger", len(s.Points(LocaleZH).Earnings.Ledger)},
		{"shop.skins", len(s.Shop(LocaleZH).Skins)},
		{"shop.items", len(s.Shop(LocaleZH).Items)},
		{"shop.recharge", len(s.Shop(LocaleZH).Recharge)},
		{"membership.perks", len(s.Membership(LocaleZH).Perks)},
		{"membership.plans", len(s.Membership(LocaleZH).Plans)},
		{"welfare.quests", len(s.Welfare(LocaleZH).Quests)},
		{"welfare.checkin.rewards", len(s.Welfare(LocaleZH).Checkin.Rewards)},
		{"events", len(s.Events(LocaleZH))},
		{"achievements", len(s.Achievements(LocaleZH))},
		{"avatar.categories", len(s.Avatar(LocaleZH))},
	}
	for _, c := range cases {
		if c.got == 0 {
			t.Errorf("%s 种子为空", c.name)
		}
	}
}

// 关键数值忠实复刻原型:余额 1280、签到 7 天、连签 3、成就 6 项。
func TestSeed_Values(t *testing.T) {
	s := newSvc(t)
	if bal := s.Points(LocaleZH).Balance; bal != 1280 {
		t.Errorf("余额 %d, 期望 1280", bal)
	}
	if w := s.Welfare(LocaleZH); len(w.Checkin.Rewards) != 7 || w.Checkin.Streak != 3 {
		t.Errorf("签到 rewards=%d streak=%d, 期望 7/3", len(w.Checkin.Rewards), w.Checkin.Streak)
	}
	if n := len(s.Achievements(LocaleZH)); n != 6 {
		t.Errorf("成就 %d 项, 期望 6", n)
	}
	for _, perk := range s.Membership(LocaleZH).Perks {
		if strings.Contains(perk, "水印") {
			t.Fatalf("membership must not sell hiding AI labels: %q", perk)
		}
	}
	for _, perk := range s.Membership(LocaleEN).Perks {
		if strings.Contains(strings.ToLower(perk), "watermark") {
			t.Fatalf("membership must not sell hiding AI labels: %q", perk)
		}
	}
}

// 本地化生效:同一活动标题 en 与 zh 不同,且各语言均非空。
func TestLocalize_EventTitleDiffersByLang(t *testing.T) {
	s := newSvc(t)
	zh := s.Events(LocaleZH)
	en := s.Events(LocaleEN)
	ja := s.Events(LocaleJA)
	if len(zh) == 0 {
		t.Fatal("无活动种子")
	}
	if zh[0].Title == en[0].Title {
		t.Errorf("zh/en 活动标题应不同: zh=%q en=%q", zh[0].Title, en[0].Title)
	}
	for _, v := range []EventView{zh[0], en[0], ja[0]} {
		if v.Title == "" {
			t.Error("活动标题不应为空")
		}
	}
}

// 未知 lang 回落默认(zh),不返回空串(系统边界容错)。
func TestLocalize_UnknownLangFallsBack(t *testing.T) {
	s := newSvc(t)
	got := s.Events("fr")
	want := s.Events(LocaleZH)
	if got[0].Title != want[0].Title {
		t.Errorf("未知 lang 应回落 zh: got=%q want=%q", got[0].Title, want[0].Title)
	}
}

// 数值/价格不随语言变(只本地化文本)。
func TestLocalize_NumericNotLocalized(t *testing.T) {
	s := newSvc(t)
	if s.Shop(LocaleZH).Skins[0].Price != s.Shop(LocaleEN).Skins[0].Price {
		t.Error("皮肤价格(创作点)不应随语言改变")
	}
}

func newRouter(t *testing.T) *gin.Engine {
	t.Helper()
	r := gin.New()
	RegisterRoutes(r, newSvc(t))
	return r
}

func get(t *testing.T, r *gin.Engine, path string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// 列表型端点:200 且 items 非空。
func TestHTTP_ListEndpoints(t *testing.T) {
	r := newRouter(t)
	for _, path := range []string{"/api/v1/events", "/api/v1/achievements", "/api/v1/avatar"} {
		w := get(t, r, path+"?lang=en")
		if w.Code != http.StatusOK {
			t.Fatalf("%s 状态码 %d", path, w.Code)
		}
		var resp struct {
			Items []json.RawMessage `json:"items"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("%s 解析失败: %v", path, err)
		}
		if len(resp.Items) == 0 {
			t.Errorf("%s items 为空", path)
		}
	}
}

// 对象型端点:200 且能解析。
func TestHTTP_ObjectEndpoints(t *testing.T) {
	r := newRouter(t)
	for _, path := range []string{"/api/v1/points", "/api/v1/shop", "/api/v1/membership", "/api/v1/welfare"} {
		w := get(t, r, path)
		if w.Code != http.StatusOK {
			t.Fatalf("%s 状态码 %d", path, w.Code)
		}
		var obj map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &obj); err != nil {
			t.Fatalf("%s 解析失败: %v", path, err)
		}
		if len(obj) == 0 {
			t.Errorf("%s 响应为空对象", path)
		}
	}
}

// HTTP 层本地化:?lang=en 与默认(zh)的活动标题不同。
func TestHTTP_LangQueryLocalizes(t *testing.T) {
	r := newRouter(t)
	type resp struct {
		Items []EventView `json:"items"`
	}
	var zh, en resp
	json.Unmarshal(get(t, r, "/api/v1/events").Body.Bytes(), &zh)
	json.Unmarshal(get(t, r, "/api/v1/events?lang=en").Body.Bytes(), &en)
	if len(zh.Items) == 0 || len(en.Items) == 0 {
		t.Fatal("活动列表为空")
	}
	if zh.Items[0].Title == en.Items[0].Title {
		t.Errorf("默认/英文标题应不同: zh=%q en=%q", zh.Items[0].Title, en.Items[0].Title)
	}
}

func TestCommerceWritesAreIdempotentAndUserScoped(t *testing.T) {
	s := newSvc(t)
	if err := s.ApplyPayment("setup-u1", "u1", "points", 1280); err != nil {
		t.Fatal(err)
	}
	start := s.PointsFor("u1", "zh").Balance
	bal, err := s.Purchase("u1", "skin_ember")
	if err != nil || bal != start-680 {
		t.Fatalf("purchase=%d %v", bal, err)
	}
	bal2, err := s.Purchase("u1", "skin_ember")
	if err != nil || bal2 != bal {
		t.Fatal("duplicate purchase charged")
	}
	if s.PointsFor("u2", "zh").Balance != 0 {
		t.Fatal("balance leaked")
	}
	bal, reward, err := s.Checkin("u1")
	if err != nil || reward != 10 || bal != bal2+10 {
		t.Fatalf("checkin=%d/%d %v", bal, reward, err)
	}
	if _, _, err = s.Checkin("u1"); err != ErrAlreadyClaimed {
		t.Fatalf("duplicate checkin=%v", err)
	}
	if _, _, err = s.ClaimQuest("u1", "quest_play_3"); err != ErrNotEarned {
		t.Fatalf("unearned real quest=%v", err)
	}
	if _, _, err = s.ClaimQuest("u1", "quest_remix_1"); err != ErrNotEarned {
		t.Fatalf("unearned=%v", err)
	}
	if _, _, err = s.ClaimAchievement("u1", "ach_first_launch"); err != ErrNotEarned {
		t.Fatalf("unearned achievement=%v", err)
	}
	if err = s.Equip("u1", "cat_character", "av_ember_knight"); err != nil {
		t.Fatal(err)
	}
	if !s.AvatarFor("u1", "zh")[0].Items[0].Equipped {
		t.Fatal("equip not reflected")
	}
}

func TestHTTP_CommerceWrites(t *testing.T) {
	svc := newSvc(t)
	if err := svc.ApplyPayment("setup-u1", "u1", "points", 1280); err != nil {
		t.Fatal(err)
	}
	r := gin.New()
	user := func(c *gin.Context) { c.Set("user_id", "u1") }
	RegisterRoutes(r, svc, user, user)
	for _, path := range []string{"/api/v1/shop/purchase/skin_ember", "/api/v1/welfare/checkin"} {
		req := httptest.NewRequest(http.MethodPost, path, nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != 200 {
			t.Fatalf("%s=%d %s", path, w.Code, w.Body.String())
		}
	}
	for _, path := range []string{"/api/v1/welfare/quests/quest_play_3/claim", "/api/v1/achievements/ach_first_launch/claim"} {
		req := httptest.NewRequest(http.MethodPost, path, nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("unearned %s=%d %s", path, w.Code, w.Body.String())
		}
	}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/avatar/equip", bytes.NewBufferString(`{"category":"cat_character","item":"av_ember_knight"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatalf("equip=%d %s", w.Code, w.Body.String())
	}
}

func TestMembershipPaymentIsUserScoped(t *testing.T) {
	s := newSvc(t)
	if s.MembershipFor("u1", "zh").Active {
		t.Fatal("new user unexpectedly active")
	}
	if err := s.ApplyPayment("member_order", "u1", "membership", 1); err != nil {
		t.Fatal(err)
	}
	if !s.MembershipFor("u1", "zh").Active || s.MembershipFor("u2", "zh").Active {
		t.Fatal("membership scope incorrect")
	}
	if err := s.ApplyPayment("member_order", "u1", "membership", 1); err != nil {
		t.Fatal(err)
	}
}
