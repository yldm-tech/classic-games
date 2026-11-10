package moderation

import (
	"testing"

	"forgeplay/server/internal/storage"
)

func TestGorm_ReportAndBlock(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(repo)

	if _, err := s.Report("u1", TargetGame, "game_1", "辱骂"); err != nil {
		t.Fatalf("举报失败: %v", err)
	}

	if err := s.Block("u1", "u2"); err != nil {
		t.Fatalf("首次屏蔽应成功: %v", err)
	}
	if err := s.Block("u1", "u2"); err != nil {
		t.Fatalf("重复屏蔽应幂等成功(不应因主键冲突报错): %v", err)
	}
	if b, _ := s.IsBlocked("u1", "u2"); !b {
		t.Error("应持久化屏蔽关系")
	}
	if b, _ := s.IsBlocked("u2", "u1"); b {
		t.Error("屏蔽是单向的")
	}
	list, _ := s.ListBlocked("u1")
	if len(list) != 1 || list[0] != "u2" {
		t.Errorf("屏蔽列表不对: %v", list)
	}
	entries, err := s.ListBlockEntries("u1")
	if err != nil || len(entries) != 1 || entries[0].BlockedAt.IsZero() {
		t.Fatalf("持久化屏蔽记录应含时间: entries=%+v err=%v", entries, err)
	}
	s.Unblock("u1", "u2")
	if b, _ := s.IsBlocked("u1", "u2"); b {
		t.Error("取消屏蔽后应 false")
	}
}

// GORM 屏蔽/隐藏写入必须幂等:重复调用返回 nil 且保留首次的时间戳(回归守卫 C7)。
func TestGorm_BlockAndHideAreIdempotent(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(repo)

	if err := s.Block("a", "b"); err != nil {
		t.Fatalf("首次屏蔽应成功: %v", err)
	}
	first, _ := s.ListBlockEntries("a")
	if len(first) != 1 {
		t.Fatalf("应有 1 条屏蔽记录, got %d", len(first))
	}
	firstAt := first[0].BlockedAt
	if err := s.Block("a", "b"); err != nil {
		t.Fatalf("重复屏蔽应幂等成功: %v", err)
	}
	again, _ := s.ListBlockEntries("a")
	if len(again) != 1 {
		t.Fatalf("重复屏蔽不应新增记录, got %d", len(again))
	}
	if !again[0].BlockedAt.Equal(firstAt) {
		t.Errorf("重复屏蔽应保留原时间戳: %v != %v", again[0].BlockedAt, firstAt)
	}

	if err := s.HideGame("a", "g1"); err != nil {
		t.Fatalf("首次隐藏应成功: %v", err)
	}
	if err := s.HideGame("a", "g1"); err != nil {
		t.Fatalf("重复隐藏应幂等成功(不应主键冲突): %v", err)
	}
	if hidden, _ := s.IsGameHidden("a", "g1"); !hidden {
		t.Error("应持久化隐藏关系")
	}
}
