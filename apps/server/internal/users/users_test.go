package users

import (
	"errors"
	"sync"
	"testing"

	"github.com/yldm-tech/classic-games/apps/server/internal/games"
	"github.com/yldm-tech/classic-games/apps/server/internal/storage"
)

func newSvc(t *testing.T) *Service {
	t.Helper()
	repo := games.NewMemRepo()
	if err := games.Seed(repo); err != nil {
		t.Fatal(err)
	}
	return NewService(games.NewService(repo))
}

func TestRealUserProfileAndWorksAggregatePublishedGames(t *testing.T) {
	gameSvc := games.NewService(games.NewMemRepo())
	g1, _ := gameSvc.Publish(games.PublishRequest{ModID: "m1", AuthorID: "real-user", Title: "One"})
	g1, _ = gameSvc.Decide(g1.ID, true)
	_ = gameSvc.IncrementPlays(g1.ID)
	_ = gameSvc.IncrementForks(g1.ID)
	_, _ = gameSvc.Publish(games.PublishRequest{ModID: "m2", AuthorID: "real-user", Title: "Reviewing"})
	fork, _ := gameSvc.Publish(games.PublishRequest{ModID: "m3", AuthorID: "real-user", Title: "Fork", ForkedFrom: g1.ID})
	fork, _ = gameSvc.Decide(fork.ID, true)
	s := NewService(gameSvc)
	s.SetLikeCounter(stubLikes{g1.ID: 7})
	s.SetFavoriteLister(func(userID string) ([]string, error) { return []string{g1.ID}, nil })
	works := s.GamesOf("real-user", "works", "zh")
	if len(works) != 1 || works[0].ID != g1.ID {
		t.Fatalf("works=%+v", works)
	}
	forks := s.GamesOf("real-user", "forks", "zh")
	liked := s.GamesOf("real-user", "liked", "zh")
	if len(forks) != 1 || forks[0].ID != fork.ID || len(liked) != 1 || liked[0].ID != g1.ID {
		t.Fatalf("forks=%+v liked=%+v", forks, liked)
	}
	p, _ := s.Get("real-user")
	if p.Works != 1 || p.Plays != 1 || p.Forks != 1 || p.Likes != 7 {
		t.Fatalf("profile=%+v", p)
	}
}

func TestProfileAndVerificationSurviveRestart(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	store, _ := NewGormStateStore(db)
	repo := games.NewMemRepo()
	_ = games.Seed(repo)
	gs := games.NewService(repo)
	s, _ := NewServiceWithStore(gs, store, []byte("stable-secret"))
	_, e := s.UpdateProfile("u", ProfileUpdate{Name: "Alice", Gender: 2, Tone: "ember", Region: "Tokyo"})
	if e != nil {
		t.Fatal(e)
	}
	_, e = s.SubmitVerification("u", "Alice", "ABCDEF1234")
	if e != nil {
		t.Fatal(e)
	}
	again, e := NewServiceWithStore(gs, store, []byte("stable-secret"))
	if e != nil {
		t.Fatal(e)
	}
	if p, ok := again.Get("@u"); !ok || p.Name != "Alice" {
		t.Fatalf("profile=%+v %v", p, ok)
	}
	if v := again.VerificationStatus("u"); v.Status != "pending" || v.IDMasked != "****1234" {
		t.Fatalf("verification=%+v", v)
	}
}

func TestProfile_Seeded(t *testing.T) {
	s := newSvc(t)
	p, ok := s.Get("@koru")
	if !ok {
		t.Fatal("@koru 应有种子资料")
	}
	// 统计字段不再是硬编码快照,而是按 segs 里的真实作品(ember+cinder,来自 games seed)动态聚合。
	if p.Works != 2 || p.Plays != 70200 || p.Forks != 1940 {
		t.Errorf("统计应基于真实作品动态聚合: %+v", p)
	}
	// Level/Points/Follows 没有真实计算来源(无计分/关注计数源),应是通用默认值而非硬编码虚荣值。
	if p.Level != 1 || p.Points != 0 || p.Follows != 0 {
		t.Errorf("无真实数据来源的字段应为默认值而非硬编码: %+v", p)
	}
}

// 用户编辑一次资料(常见入站流程)后,Get() 的统计字段不应冻结在编辑时刻的快照——
// 后续发布/游玩/被 Fork 的变化必须继续反映在 Works/Plays/Forks 里。回归守卫:此前
// Get() 命中 profiles[] 后直接原样返回存量值,只有从未编辑过资料的用户才会走动态聚合分支。
func TestGet_StatsStayLiveAfterProfileEdit(t *testing.T) {
	repo := games.NewMemRepo()
	gameSvc := games.NewService(repo)
	s := NewService(gameSvc)
	if _, err := s.UpdateProfile("real-user2", ProfileUpdate{Name: "Alice", Gender: 1, Tone: "ember", Region: "Tokyo"}); err != nil {
		t.Fatal(err)
	}
	g, _ := gameSvc.Publish(games.PublishRequest{ModID: "m1", AuthorID: "real-user2", Title: "One"})
	g, _ = gameSvc.Decide(g.ID, true)
	_ = gameSvc.IncrementPlays(g.ID)
	_ = gameSvc.IncrementForks(g.ID)
	p, ok := s.Get("@real-user2")
	if !ok {
		t.Fatal("已编辑过资料的用户应能查到资料")
	}
	if p.Works != 1 || p.Plays != 1 || p.Forks != 1 {
		t.Fatalf("编辑资料后统计应继续动态聚合,而不是冻结在编辑时刻: %+v", p)
	}
	if p.Name != "Alice" {
		t.Fatalf("身份字段应保留编辑结果: %+v", p)
	}
}

func TestGet_FollowCounterOverlay(t *testing.T) {
	s := newSvc(t)
	s.SetFollowCounter(func(id string) int {
		if id == "@koru" {
			return 3
		}
		return 0
	})
	p, _ := s.Get("@koru")
	if p.Follows != 3 {
		t.Fatalf("Follows 应取自注入的关注计数源: %+v", p)
	}
}

func TestProfile_Unknown(t *testing.T) {
	s := newSvc(t)
	if _, ok := s.Get("@nobody"); ok {
		t.Error("未知用户不应命中种子")
	}
}

func TestUpdateProfileIsScopedAndValidated(t *testing.T) {
	s := newSvc(t)
	got, err := s.UpdateProfile("user_a", ProfileUpdate{Name: "Alice", Bio: "hello", Gender: 1, Tone: "ocean", Region: "Tokyo"})
	if err != nil {
		t.Fatal(err)
	}
	if got.ID != "@user_a" || got.Name != "Alice" || got.Region != "Tokyo" {
		t.Fatalf("unexpected profile: %+v", got)
	}
	if _, ok := s.Get("@user_a"); !ok {
		t.Fatal("updated public profile missing")
	}
	if _, err = s.UpdateProfile("user_b", ProfileUpdate{Name: "", Gender: 9, Tone: "bad"}); err == nil {
		t.Fatal("invalid profile accepted")
	}
}

// failingStore 让第 failOn 次 Save 失败,模拟瞬时持久化故障。
type failingStore struct {
	rows   []userStateRow
	saves  int
	failOn int
}

func (f *failingStore) LoadAll() ([]userStateRow, error) { return f.rows, nil }
func (f *failingStore) Save(v userStateRow) error {
	f.saves++
	if f.failOn > 0 && f.saves == f.failOn {
		return errors.New("store down")
	}
	f.rows = append(f.rows, v)
	return nil
}

// 持久化失败时资料更新必须回滚内存并返回 ErrProfilePersist(而非把脏值留在内存并当作成功)。回归守卫 C16。
func TestUpdateProfile_RollsBackOnPersistFailure(t *testing.T) {
	store := &failingStore{failOn: 1}
	repo := games.NewMemRepo()
	if err := games.Seed(repo); err != nil {
		t.Fatal(err)
	}
	s, err := NewServiceWithStore(games.NewService(repo), store, []byte("stable-secret"))
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.UpdateProfile("newbie", ProfileUpdate{Name: "Alice", Gender: 1, Tone: "ocean", Region: "Tokyo"})
	if !errors.Is(err, ErrProfilePersist) {
		t.Fatalf("持久化失败应返回 ErrProfilePersist, got %v", err)
	}
	// 内存不应领先于存储:失败后 profile 不应可见。
	if p, ok := s.Get("@newbie"); ok {
		t.Fatalf("持久化失败后内存应回滚,不应查到资料: %+v", p)
	}
}

// 两个并发 PATCH 各改不同字段,读—改—写全程持锁应保留两者(旧代码读写分锁会丢更新)。回归守卫 C14。
func TestPatchProfile_ConcurrentDistinctFieldsNoLostUpdate(t *testing.T) {
	for iter := 0; iter < 50; iter++ {
		s := newSvc(t)
		uid := "raceuser"
		if _, err := s.UpdateProfile(uid, ProfileUpdate{Name: "init", Bio: "init", Gender: 0, Tone: "ember", Region: "init"}); err != nil {
			t.Fatal(err)
		}
		name, bio := "NAME", "BIO"
		var wg sync.WaitGroup
		wg.Add(2)
		go func() { defer wg.Done(); s.PatchProfile(uid, ProfilePatch{Name: &name}) }()
		go func() { defer wg.Done(); s.PatchProfile(uid, ProfilePatch{Bio: &bio}) }()
		wg.Wait()
		p, _ := s.Get("@" + uid)
		if p.Name != name || p.Bio != bio {
			t.Fatalf("迭代 %d 丢失并发更新: name=%q bio=%q", iter, p.Name, p.Bio)
		}
	}
}

func TestVerificationNeverStoresOrReturnsRawID(t *testing.T) {
	s := newSvc(t)
	raw := "11010519491231002X"
	got, err := s.SubmitVerification("user_a", "张三", raw)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != "pending" || got.IDMasked != "****002X" {
		t.Fatalf("unexpected status: %+v", got)
	}
	s.mu.RLock()
	record := s.verifications["user_a"]
	s.mu.RUnlock()
	if record.digest == ([32]byte{}) {
		t.Fatal("verification digest missing")
	}
	if s.VerificationStatus("none").Status != "not_submitted" {
		t.Fatal("new user must not be verified")
	}
}

func TestVerificationRejectsInvalidChineseIDChecksum(t *testing.T) {
	s := newSvc(t)
	if _, err := s.SubmitVerification("user_b", "张三", "110105194912310021"); !errors.Is(err, ErrVerificationInvalid) {
		t.Fatalf("bad checksum accepted: %v", err)
	}
}

func TestAdminCanDecidePendingVerification(t *testing.T) {
	s := newSvc(t)
	if _, err := s.SubmitVerification("user_c", "张三", "11010519491231002X"); err != nil {
		t.Fatal(err)
	}
	pending := s.ListPendingVerifications()
	found := false
	for _, item := range pending {
		if item.UserID == "user_c" {
			found = true
		}
	}
	if !found {
		t.Fatalf("pending queue missing submitter: %+v", pending)
	}
	got, err := s.DecideVerification("user_c", true)
	if err != nil || got.Status != "verified" {
		t.Fatalf("approve=%+v %v", got, err)
	}
	if s.VerificationStatus("user_c").Status != "verified" {
		t.Fatal("status not persisted in memory")
	}
	if _, err := s.DecideVerification("user_c", false); !errors.Is(err, ErrVerificationState) {
		t.Fatalf("second decide=%v", err)
	}
}

func TestGamesOf_Localized(t *testing.T) {
	s := newSvc(t)
	works := s.GamesOf("@koru", "works", "en")
	if len(works) != 2 {
		t.Fatalf("@koru 作品段应有 2 个, got %d", len(works))
	}
	// works=[ember,cinder];ember 英文标题应被解析
	if works[0].Title != "Ember Drift" {
		t.Errorf("英文本地化标题不对: %q", works[0].Title)
	}
	forks := s.GamesOf("@koru", "forks", "zh")
	if len(forks) != 2 {
		t.Errorf("二创段应有 2 个, got %d", len(forks))
	}
}

type stubLikes map[string]int

func (s stubLikes) LikeCount(id string) (int, error) { return s[id], nil }
func (s stubLikes) LikeCounts(ids []string) (map[string]int, error) {
	out := map[string]int{}
	for _, id := range ids {
		out[id] = s[id]
	}
	return out, nil
}

// 注入 LikeCounter 后,我的页作品的点赞数以 social 为准(与 /games、/ranking、/like 一致)。
func TestGamesOf_LikeOverlay(t *testing.T) {
	s := newSvc(t)
	works := s.GamesOf("@koru", "works", "zh")
	if len(works) == 0 {
		t.Skip("无种子作品")
	}
	s.SetLikeCounter(stubLikes{works[0].ID: 12345})
	got := s.GamesOf("@koru", "works", "zh")
	if got[0].Likes != 12345 {
		t.Errorf("作品点赞数应被 social 覆盖为 12345, got %d", got[0].Likes)
	}
}
