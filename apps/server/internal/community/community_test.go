package community

import (
	"forgeplay/server/internal/storage"
	"testing"
)

func TestRatingUpsertAndPost(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, e := NewGormRepo(db)
	if e != nil {
		t.Fatal(e)
	}
	s := NewService(r)
	if _, e = s.Rate("g", "u", 5); e != nil {
		t.Fatal(e)
	}
	sum, e := s.Rate("g", "u", 3)
	if e != nil || sum.Count != 1 || sum.Average != 3 || sum.MyRating != 3 {
		t.Fatalf("%+v %v", sum, e)
	}
	p, e := s.Post("g", "u", " hello ")
	if e != nil || p.Content != "hello" {
		t.Fatalf("%+v %v", p, e)
	}
	sum, _ = s.Get("g", "u")
	if len(sum.Posts) != 1 {
		t.Fatalf("%+v", sum)
	}
	if _, e = s.Post("g", "u", "s.p.a.m"); e == nil {
		t.Fatal("moderation bypass accepted")
	}
}

type stubBlocks map[string][]string

func (b stubBlocks) ListBlocked(userID string) ([]string, error) { return b[userID], nil }

// 被屏蔽作者的社区帖不应出现在屏蔽者读到的列表中(与评论屏蔽一致)。回归守卫 C8。
func TestGet_FiltersBlockedAuthorsPosts(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, e := NewGormRepo(db)
	if e != nil {
		t.Fatal(e)
	}
	s := NewService(r)
	s.SetBlockLister(stubBlocks{"viewer": {"troll"}})
	if _, e = s.Post("g", "troll", "harassment here"); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Post("g", "friend", "nice game"); e != nil {
		t.Fatal(e)
	}
	// viewer 屏蔽了 troll:只应看到 friend 的帖子。
	sum, e := s.Get("g", "viewer")
	if e != nil {
		t.Fatal(e)
	}
	if len(sum.Posts) != 1 || sum.Posts[0].AuthorID != "friend" {
		t.Fatalf("被屏蔽作者的帖子应被过滤, got %+v", sum.Posts)
	}
	// 无屏蔽关系的第三方仍能看到两条。
	other, _ := s.Get("g", "other")
	if len(other.Posts) != 2 {
		t.Fatalf("未屏蔽者应看到全部帖子, got %d", len(other.Posts))
	}
}
