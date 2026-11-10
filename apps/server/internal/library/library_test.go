package library

import (
	"testing"

	"forgeplay/server/internal/games"
	"forgeplay/server/internal/storage"
)

func newSvc() *Service {
	return NewService(games.NewService(games.NewMemRepo()))
}

func TestAuthenticatedLiveDoesNotReturnDemoStreams(t *testing.T) {
	s := NewService(games.NewService(games.NewMemRepo()))
	if got := s.LiveFor("real-user", "zh"); len(got) != 0 {
		t.Fatalf("demo live streams=%+v", got)
	}
}

// 新用户不应继承匿名预览态的种子下载(ember/cinder/magma)——那 3 条只服务未登录预览,
// 真实用户的"我的下载"必须如实反映其从未下载过任何东西。
func TestNewUserDownloadsStartEmpty(t *testing.T) {
	s := newSvc()
	if got := s.DownloadsFor("brand-new-user", "zh"); len(got) != 0 {
		t.Fatalf("新用户下载应为空, got %+v", got)
	}
}

func TestLibraryWritesSurviveRestart(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	store, _ := NewGormStateStore(db)
	gs := games.NewService(games.NewMemRepo())
	s, _ := NewServiceWithStore(gs, store)
	// 手动注入下载关系模拟真实用户已下载的游戏:当前没有"新增下载"写接口,新用户默认空列表
	// (见 downloadsForLocked),这条测试只验证持久化机制本身,不依赖新用户自动预置种子。
	s.mu.Lock()
	s.userDownloads["u"] = append([]downloadRel(nil), s.downloads...)
	s.mu.Unlock()
	downloads := s.DownloadsFor("u", "zh")
	if len(downloads) < 2 {
		t.Fatal("seed downloads missing")
	}
	_ = s.RemoveDownload("u", downloads[0].Game.ID)
	_ = s.MarkDownloadUpdated("u", downloads[1].Game.ID)
	_ = s.ClearHistory("u")
	again, e := NewServiceWithStore(gs, store)
	if e != nil {
		t.Fatal(e)
	}
	got := again.DownloadsFor("u", "zh")
	if len(got) != 2 || got[0].HasUpdate {
		t.Fatalf("downloads=%+v", got)
	}
	for _, group := range again.HistoryFor("u", "zh") {
		if len(group.Items) != 0 {
			t.Fatal("history returned")
		}
	}
}

func TestDownloads_ResolvedAndLocalized(t *testing.T) {
	s := newSvc()

	zh := s.Downloads("zh")
	if len(zh) != 3 {
		t.Fatalf("下载应 3 项, got %d", len(zh))
	}
	// 顺序对应种子:ember / cinder / magma
	if zh[0].Game.Title != "余烬漂移" {
		t.Errorf("zh 第一项标题应「余烬漂移」, got %q", zh[0].Game.Title)
	}
	if zh[0].SizeMB != 86 || zh[0].HasUpdate {
		t.Errorf("ember 应 86MB 无更新, got %dMB update=%v", zh[0].SizeMB, zh[0].HasUpdate)
	}
	if !zh[1].HasUpdate {
		t.Errorf("cinder 应有更新")
	}
	if zh[0].Game.ID == "" || zh[0].Game.AuthorID == "" {
		t.Errorf("应解析到真实游戏 id/作者, got id=%q author=%q", zh[0].Game.ID, zh[0].Game.AuthorID)
	}

	en := s.Downloads("en")
	if en[0].Game.Title != "Ember Drift" {
		t.Errorf("en 第一项标题应「Ember Drift」, got %q", en[0].Game.Title)
	}
	ja := s.Downloads("ja")
	if ja[0].Game.Title != "エンバー・ドリフト" {
		t.Errorf("ja 第一项标题应「エンバー・ドリフト」, got %q", ja[0].Game.Title)
	}
}

func TestDownloads_UnknownLangFallsBackZH(t *testing.T) {
	s := newSvc()
	got := s.Downloads("fr")
	if got[0].Game.Title != "余烬漂移" {
		t.Errorf("未知 lang 应兜底中文, got %q", got[0].Game.Title)
	}
}

func TestHistory_GroupedAndLocalized(t *testing.T) {
	s := newSvc()
	groups := s.History("en")
	if len(groups) != 3 {
		t.Fatalf("历史应 3 组, got %d", len(groups))
	}
	if groups[0].Group != "today" || groups[1].Group != "yesterday" || groups[2].Group != "earlier" {
		t.Errorf("分组名应 today/yesterday/earlier, got %q/%q/%q",
			groups[0].Group, groups[1].Group, groups[2].Group)
	}
	if len(groups[0].Items) != 2 {
		t.Fatalf("今天应 2 项, got %d", len(groups[0].Items))
	}
	if groups[0].Items[0].Game.Title != "Ember Drift" {
		t.Errorf("今天第一项应「Ember Drift」, got %q", groups[0].Items[0].Game.Title)
	}
	if groups[0].Items[0].MinutesPlayed != 36 {
		t.Errorf("ember 应玩 36 分钟, got %d", groups[0].Items[0].MinutesPlayed)
	}
	if groups[0].Items[0].Game.ID == "" {
		t.Errorf("历史项应解析到真实游戏 id")
	}
}

func TestLive_ResolvedWithBlurb(t *testing.T) {
	s := newSvc()
	live := s.Live("ja")
	if len(live) != 2 {
		t.Fatalf("直播应 2 路, got %d", len(live))
	}
	if live[0].Game.Title != "エンバー・ドリフト" {
		t.Errorf("第一路游戏应「エンバー・ドリフト」, got %q", live[0].Game.Title)
	}
	if live[0].Streamer != "@mei" || live[0].Viewers != 1342 {
		t.Errorf("第一路应 @mei/1342, got %s/%d", live[0].Streamer, live[0].Viewers)
	}
	if live[0].Title != "週間1位を狙う — ライン参考にどうぞ" {
		t.Errorf("直播标语本地化错误, got %q", live[0].Title)
	}
	// 标语随 lang 切换
	en := s.Live("en")
	if en[0].Title != "Chasing weekly #1 — copy my lines" {
		t.Errorf("en 标语错误, got %q", en[0].Title)
	}
	if en[0].Game.ID == "" {
		t.Errorf("直播项应解析到真实游戏 id")
	}
}

func TestLibraryMutationsAreUserScoped(t *testing.T) {
	s := newSvc()
	// 手动注入下载关系模拟真实用户已下载的游戏(新用户默认空列表,见 downloadsForLocked)。
	s.mu.Lock()
	s.userDownloads["u1"] = append([]downloadRel(nil), s.downloads...)
	s.userDownloads["u2"] = append([]downloadRel(nil), s.downloads...)
	s.mu.Unlock()
	items := s.DownloadsFor("u1", "zh")
	if err := s.MarkDownloadUpdated("u1", items[1].Game.ID); err != nil {
		t.Fatal(err)
	}
	if s.DownloadsFor("u1", "zh")[1].HasUpdate {
		t.Fatal("更新后应清除 update 标记")
	}
	if !s.DownloadsFor("u2", "zh")[1].HasUpdate {
		t.Fatal("用户之间不可串状态")
	}
	if err := s.RemoveDownload("u1", items[0].Game.ID); err != nil {
		t.Fatal(err)
	}
	if len(s.DownloadsFor("u1", "zh")) != 2 || len(s.DownloadsFor("u2", "zh")) != 3 {
		t.Fatal("删除应仅影响 u1")
	}
	seedGameID := s.History("zh")[0].Items[0].Game.ID
	if err := s.RecordPlay("u2", seedGameID, 60000); err != nil {
		t.Fatal(err)
	}
	s.ClearHistory("u1")
	for _, g := range s.HistoryFor("u1", "zh") {
		if len(g.Items) != 0 {
			t.Fatal("u1 历史应清空")
		}
	}
	if len(s.HistoryFor("u2", "zh")[0].Items) == 0 {
		t.Fatal("u2 历史不应被清空")
	}
}

func TestRecordPlayAddsGenericGameAndIncrementsCount(t *testing.T) {
	gs := games.NewService(games.NewMemRepo())
	g, _ := gs.Publish(games.PublishRequest{ModID: "m", Title: "User Game", AuthorID: "author"})
	g, _ = gs.Decide(g.ID, true)
	s := NewService(gs)
	if err := s.RecordPlay("u", g.ID, 90000); err != nil {
		t.Fatal(err)
	}
	if err := s.RecordPlay("u", g.ID, 30000); err != nil {
		t.Fatal(err)
	}
	groups := s.HistoryFor("u", "en")
	if len(groups) == 0 || len(groups[0].Items) != 1 || groups[0].Items[0].Game.ID != g.ID || groups[0].Items[0].MinutesPlayed != 3 {
		t.Fatalf("history=%+v", groups)
	}
	got, _ := gs.Get(g.ID)
	if got.Plays != 2 {
		t.Fatalf("plays=%d", got.Plays)
	}
}
