package social

import (
	"testing"

	"forgeplay/server/internal/storage"
)

func newGormSvc(t *testing.T) *Service {
	t.Helper()
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	return NewService(repo)
}

func TestGorm_CommentAndLike(t *testing.T) {
	s := newGormSvc(t)

	s.Comment("game_1", "u1", "好玩")
	s.Comment("game_1", "u2", "二创了")
	items, _, _ := s.Comments("game_1", "", 10)
	if len(items) != 2 {
		t.Errorf("评论应持久化 2 条, got %d", len(items))
	}

	s.Like("game_1", "u1")
	s.Like("game_1", "u1") // 幂等
	s.Like("game_1", "u2")
	count, liked, _ := s.LikeStatus("game_1", "u1")
	if count != 2 || !liked {
		t.Errorf("点赞应去重持久化, count=%d liked=%v", count, liked)
	}
	s.Unlike("game_1", "u1")
	count, liked, _ = s.LikeStatus("game_1", "u1")
	if count != 1 || liked {
		t.Errorf("取消赞后 count=1 liked=false, got %d %v", count, liked)
	}
}

func TestGorm_FavoritesPersist(t *testing.T) {
	s := newGormSvc(t)
	_ = s.Favorite("g1", "u1")
	_ = s.Favorite("g1", "u1")
	items, err := s.Favorites("u1")
	if err != nil || len(items) != 1 || items[0] != "g1" {
		t.Fatalf("收藏未持久化或不幂等: %v %v", items, err)
	}
}
