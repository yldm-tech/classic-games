package ranking

import (
	"testing"

	"forgeplay/server/internal/games"
	"forgeplay/server/internal/social"
)

func publishApprove(t *testing.T, g *games.Service, title string) games.Game {
	t.Helper()
	game, err := g.Publish(games.PublishRequest{ModID: "m", Title: title})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := g.Decide(game.ID, true); err != nil {
		t.Fatal(err)
	}
	return game
}

func TestRanked_Hot(t *testing.T) {
	gsvc := games.NewService(games.NewMemRepo())
	ssvc := social.NewService(social.NewMemRepo())

	a := publishApprove(t, gsvc, "A")
	b := publishApprove(t, gsvc, "B")
	// b 两赞,a 一赞 → b 应排第一
	ssvc.Like(b.ID, "u1")
	ssvc.Like(b.ID, "u2")
	ssvc.Like(a.ID, "u1")

	r := NewService(gsvc, ssvc)
	hot, err := r.Ranked("hot", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(hot) != 2 {
		t.Fatalf("应 2 项, got %d", len(hot))
	}
	if hot[0].ID != b.ID || hot[0].Rank != 1 || hot[0].Likes != 2 {
		t.Errorf("第一名应是 B(2赞), got %+v", hot[0])
	}
	if hot[1].ID != a.ID || hot[1].Rank != 2 {
		t.Errorf("第二名应是 A, got %+v", hot[1])
	}
}

// 回归:有展示赞基数的种子作品,被「第 1 个真实 social 赞」不该反超跌到中间作品之下(round-6 c>0 悬崖)。
func TestRanked_SeedLikesNoInversionOnFirstLike(t *testing.T) {
	repo := games.NewMemRepo()
	gsvc := games.NewService(repo)
	for _, g := range []games.Game{
		{ID: "seed", Title: "Seed", Status: games.StatusPublished},
		{ID: "mid", Title: "Mid", Status: games.StatusPublished},
	} {
		if _, err := repo.Create(g); err != nil {
			t.Fatal(err)
		}
	}
	ssvc := social.NewService(social.NewMemRepo())
	// 展示人气基数走 social 单一真相源(种子启动时灌入)。
	ssvc.SetBaseLikes("seed", 9300)
	ssvc.SetBaseLikes("mid", 5000)
	r := NewService(gsvc, ssvc)

	rankOf := func(items []Ranked, id string) int {
		for _, it := range items {
			if it.ID == id {
				return it.Rank
			}
		}
		return -1
	}

	hot, _ := r.Ranked("hot", 0)
	if rankOf(hot, "seed") >= rankOf(hot, "mid") {
		t.Fatalf("初始:种子(9300)应排在 mid(5000)之前")
	}
	ssvc.Like("seed", "u1") // 第 1 个真实赞
	hot2, _ := r.Ranked("hot", 0)
	if rankOf(hot2, "seed") >= rankOf(hot2, "mid") {
		t.Errorf("第 1 个真实赞后种子不应跌到 mid 之下(无悬崖), seed rank %d mid rank %d", rankOf(hot2, "seed"), rankOf(hot2, "mid"))
	}
}

func TestRanked_New(t *testing.T) {
	gsvc := games.NewService(games.NewMemRepo())
	ssvc := social.NewService(social.NewMemRepo())
	publishApprove(t, gsvc, "first")
	last := publishApprove(t, gsvc, "last")

	r := NewService(gsvc, ssvc)
	got, _ := r.Ranked("new", 0)
	if got[0].ID != last.ID {
		t.Errorf("新作榜第一应是最后发布的, got %s", got[0].Title)
	}
}

func TestRanked_Limit(t *testing.T) {
	gsvc := games.NewService(games.NewMemRepo())
	ssvc := social.NewService(social.NewMemRepo())
	for i := 0; i < 5; i++ {
		publishApprove(t, gsvc, "g")
	}
	r := NewService(gsvc, ssvc)
	got, _ := r.Ranked("hot", 3)
	if len(got) != 3 {
		t.Errorf("limit=3 应返回 3 项, got %d", len(got))
	}
}

func TestRankedFiltersRuntimeAndCategory(t *testing.T) {
	gsvc := games.NewService(games.NewMemRepo())
	ssvc := social.NewService(social.NewMemRepo())
	a, _ := gsvc.Publish(games.PublishRequest{ModID: "a", Title: "A", Runtime: "survivor@1.0.0", Category: "survival"})
	_, _ = gsvc.Decide(a.ID, true)
	b, _ := gsvc.Publish(games.PublishRequest{ModID: "b", Title: "B", Runtime: "tower_defense@1.0.0", Category: "strategy"})
	_, _ = gsvc.Decide(b.ID, true)
	items, err := NewService(gsvc, ssvc).RankedFilteredFor("", "hot", 10, "survivor", "survival")
	if err != nil || len(items) != 1 || items[0].ID != a.ID {
		t.Fatalf("filtered=%+v err=%v", items, err)
	}
}

func TestRanked_UnknownType(t *testing.T) {
	r := NewService(games.NewService(games.NewMemRepo()), social.NewService(social.NewMemRepo()))
	if _, err := r.Ranked("bogus", 0); err != ErrUnknownType {
		t.Errorf("未知类型应 ErrUnknownType, got %v", err)
	}
}

func TestRanked_RisingUsesRecentGrowthNotHistoricalTotal(t *testing.T) {
	repo := games.NewMemRepo()
	gsvc := games.NewService(repo)
	old := publishApprove(t, gsvc, "historical")
	fast := publishApprove(t, gsvc, "rising")
	ssvc := social.NewService(social.NewMemRepo())
	ssvc.SetBaseLikes(old.ID, 10000)
	ssvc.Like(fast.ID, "u1")
	ssvc.Like(fast.ID, "u2")
	got, err := NewService(gsvc, ssvc).Ranked("rising", 0)
	if err != nil {
		t.Fatal(err)
	}
	if got[0].ID != fast.ID {
		t.Fatalf("近期新增 2 赞的作品应超过只有历史基数的作品: %+v", got)
	}
}
