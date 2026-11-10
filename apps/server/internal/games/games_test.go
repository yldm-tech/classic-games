package games

import (
	"sync"
	"testing"
)

func newSvc() *Service { return NewService(NewMemRepo()) }

func TestPublish_EntersReviewing(t *testing.T) {
	s := newSvc()
	g, err := s.Publish(PublishRequest{ModID: "mod_1", Title: "电光狂奔", AIGenerated: true})
	if err != nil {
		t.Fatal(err)
	}
	if g.Status != StatusReviewing {
		t.Errorf("status=%s, 期望 reviewing", g.Status)
	}
}

func TestPublish_RuntimeComesFromTrustedMod(t *testing.T) {
	s := newSvc()
	s.SetModRuntime(func(id string) (string, bool) { return map[string]string{"m": "survivor@1.0.0"}[id], id == "m" })
	g, err := s.Publish(PublishRequest{ModID: "m", Runtime: "attacker@9.0.0", Title: "x", Category: "survival"})
	if err != nil {
		t.Fatal(err)
	}
	if g.Runtime != "survivor@1.0.0" || g.Category != "survival" {
		t.Fatalf("runtime/category=%q/%q", g.Runtime, g.Category)
	}
}

func TestPublishRequiresModOwnerAndValidEffectiveDSL(t *testing.T) {
	s := newSvc()
	s.SetModOwner(func(id string) (string, bool) {
		return map[string]string{"mine": "owner", "foreign": "other", "broken": "owner"}[id], id != "missing"
	})
	s.SetModValidator(func(id string) bool { return id != "broken" })
	if _, err := s.Publish(PublishRequest{ModID: "foreign", AuthorID: "owner", Title: "stolen"}); err != ErrForbidden {
		t.Fatalf("foreign mod publish error = %v", err)
	}
	if _, err := s.Publish(PublishRequest{ModID: "broken", AuthorID: "owner", Title: "broken"}); err != ErrInvalidMod {
		t.Fatalf("broken mod publish error = %v", err)
	}
	if _, err := s.Publish(PublishRequest{ModID: "mine", AuthorID: "owner", Title: "valid"}); err != nil {
		t.Fatalf("owned valid mod rejected: %v", err)
	}
}

func TestBackfillMissingRuntimeFromMod(t *testing.T) {
	repo := NewMemRepo()
	svc := NewService(repo)
	old, _ := repo.Create(Game{ModID: "legacy", Title: "old", Status: StatusPublished})
	svc.SetModRuntime(func(id string) (string, bool) { return "tower_defense@1.0.0", id == "legacy" })
	if n, err := svc.BackfillMissingRuntime(); err != nil || n != 1 {
		t.Fatalf("backfill n=%d err=%v", n, err)
	}
	got, _ := repo.Get(old.ID)
	if got.Runtime != "tower_defense@1.0.0" {
		t.Fatalf("runtime=%q", got.Runtime)
	}
}

func TestPublish_Validation(t *testing.T) {
	s := newSvc()
	if _, err := s.Publish(PublishRequest{ModID: "mod_1"}); err == nil {
		t.Error("缺标题应报错")
	}
	if _, err := s.Publish(PublishRequest{Title: "x"}); err == nil {
		t.Error("缺 mod_id 应报错")
	}
	if _, err := s.Publish(PublishRequest{ModID: "m", Title: "x", Tags: []string{"a", "b", "c", "d"}}); err == nil {
		t.Error(">3 标签应报错")
	}
}

func TestDecide_StateMachine(t *testing.T) {
	s := newSvc()
	g, _ := s.Publish(PublishRequest{ModID: "mod_1", Title: "x"})

	// reviewing → published
	got, err := s.Decide(g.ID, true)
	if err != nil || got.Status != StatusPublished {
		t.Fatalf("通过审核应 published, got=%v err=%v", got.Status, err)
	}
	// 已 published 再裁决应拒绝(非 reviewing)
	if _, err := s.Decide(g.ID, true); err != ErrInvalidState {
		t.Errorf("已 published 再裁决应 ErrInvalidState, got %v", err)
	}
	// 出现在已发布列表
	list, _ := s.ListPublished()
	if len(list) != 1 {
		t.Errorf("已发布列表 %d 项, 期望 1", len(list))
	}
}

func TestDecide_Reject(t *testing.T) {
	s := newSvc()
	g, _ := s.Publish(PublishRequest{ModID: "mod_1", Title: "x"})
	got, _ := s.Decide(g.ID, false)
	if got.Status != StatusRejected {
		t.Errorf("拒绝应 rejected, got %s", got.Status)
	}
}

func TestDelist_OnlyPublished(t *testing.T) {
	s := newSvc()
	g, _ := s.Publish(PublishRequest{ModID: "mod_1", Title: "x"})
	// reviewing 不能下架
	if _, err := s.Delist(g.ID); err != ErrInvalidState {
		t.Errorf("reviewing 下架应 ErrInvalidState, got %v", err)
	}
	s.Decide(g.ID, true)
	got, err := s.Delist(g.ID)
	if err != nil || got.Status != StatusDelisted {
		t.Errorf("published 应可下架, got=%v err=%v", got.Status, err)
	}
}

func TestAuthorLifecycleAuthorization(t *testing.T) {
	s := newSvc()
	g, _ := s.Publish(PublishRequest{ModID: "m", Title: "x", AuthorID: "owner"})
	if _, err := s.DelistByAuthor(g.ID, "other"); err != ErrForbidden {
		t.Fatalf("foreign delist: %v", err)
	}
	s.Decide(g.ID, true)
	if got, err := s.DelistByAuthor(g.ID, "owner"); err != nil || got.Status != StatusDelisted {
		t.Fatalf("owner delist: %+v %v", got, err)
	}
	r, _ := s.Publish(PublishRequest{ModID: "r", Title: "x", AuthorID: "owner"})
	s.Decide(r.ID, false)
	if _, err := s.ResubmitByAuthor(r.ID, "other"); err != ErrForbidden {
		t.Fatalf("foreign resubmit: %v", err)
	}
	if got, err := s.ResubmitByAuthor(r.ID, "owner"); err != nil || got.Status != StatusReviewing {
		t.Fatalf("resubmit: %+v %v", got, err)
	}
}

func TestGet_NotFound(t *testing.T) {
	s := newSvc()
	if _, err := s.Get("nope"); err != ErrNotFound {
		t.Errorf("期望 ErrNotFound, got %v", err)
	}
}

// 并发裁决:同一 reviewing 作品被同时 approve / reject,只能有一个成功,另一个拿 ErrInvalidState,
// 不会互相覆盖(lost update)。锁住 UpdateStatus 的原子流转契约。
func TestDecide_ConcurrentNoLostUpdate(t *testing.T) {
	s := newSvc()
	g, _ := s.Publish(PublishRequest{ModID: "mod_1", Title: "x"})

	var wg sync.WaitGroup
	results := make([]error, 2)
	approve := []bool{true, false}
	wg.Add(2)
	for i := 0; i < 2; i++ {
		go func(idx int) {
			defer wg.Done()
			_, results[idx] = s.Decide(g.ID, approve[idx])
		}(i)
	}
	wg.Wait()

	okCount, invalidCount := 0, 0
	for _, err := range results {
		switch err {
		case nil:
			okCount++
		case ErrInvalidState:
			invalidCount++
		default:
			t.Fatalf("非预期错误: %v", err)
		}
	}
	if okCount != 1 || invalidCount != 1 {
		t.Fatalf("应恰好一个成功一个 ErrInvalidState, got ok=%d invalid=%d", okCount, invalidCount)
	}
	// 终态必是单一终态(published 或 rejected),未被双写污染。
	final, _ := s.Get(g.ID)
	if final.Status != StatusPublished && final.Status != StatusRejected {
		t.Errorf("终态应为 published/rejected, got %s", final.Status)
	}
}

// 发布时:mod 被权威标记为 AI 则强制 ai_generated=true(客户端不能改成非 AI);非 AI mod 遵从 req。
func TestPublish_AIProvenanceForced(t *testing.T) {
	s := newSvc()
	s.SetModProvenance(func(modID string) bool { return modID == "ai_mod" })
	g, err := s.Publish(PublishRequest{ModID: "ai_mod", Title: "T", AIGenerated: false})
	if err != nil {
		t.Fatal(err)
	}
	if !g.AIGenerated {
		t.Error("AI mod 发布应强制 ai_generated=true,即便 req 自报 false")
	}
	g2, _ := s.Publish(PublishRequest{ModID: "human_mod", Title: "T", AIGenerated: false})
	if g2.AIGenerated {
		t.Error("非 AI mod 应遵从 req=false")
	}
}

func TestPublishUsesAuthoritativeAuthorDisplayName(t *testing.T) {
	s := newSvc()
	s.SetAuthorName(func(id string) string { return map[string]string{"u": "@real"}[id] })
	g, err := s.Publish(PublishRequest{ModID: "m", AuthorID: "u", Title: "T"})
	if err != nil || g.By != "@real" {
		t.Fatalf("game=%+v err=%v", g, err)
	}
}

func TestListMineReturnsOnlyAuthorsWorksAcrossStatuses(t *testing.T) {
	svc := newSvc()
	svc.SetViewCounter(func(ids []string) (map[string]int, error) {
		return map[string]int{"game_1": 12, "game_2": 5}, nil
	})
	ownedReview, _ := svc.Publish(PublishRequest{ModID: "m1", AuthorID: "owner", Title: "Review"})
	ownedPublished, _ := svc.Publish(PublishRequest{ModID: "m2", AuthorID: "owner", Title: "Published"})
	ownedPublished, _ = svc.Decide(ownedPublished.ID, true)
	foreign, _ := svc.Publish(PublishRequest{ModID: "m3", AuthorID: "other", Title: "Foreign"})
	_, _ = svc.Decide(foreign.ID, true)

	got, err := svc.ListMine("owner")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].ID != ownedPublished.ID || got[1].ID != ownedReview.ID {
		t.Fatalf("mine=%+v", got)
	}
	if got[0].Views != 5 || got[1].Views != 12 {
		t.Fatalf("authoritative views not joined: %+v", got)
	}
}
