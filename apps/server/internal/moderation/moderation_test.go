package moderation

import (
	"testing"
	"time"
)

func newSvc() *Service { return NewService(NewMemRepo()) }

func TestReport_Validation(t *testing.T) {
	s := newSvc()
	if _, err := s.Report("u1", TargetGame, "game_1", "辱骂"); err != nil {
		t.Fatalf("合法举报不应报错: %v", err)
	}
	if _, err := s.Report("u1", "bogus", "x", "r"); err != ErrBadTarget {
		t.Errorf("非法类型应 ErrBadTarget, got %v", err)
	}
	if _, err := s.Report("u1", TargetGame, "game_1", "  "); err != ErrNoReason {
		t.Errorf("空理由应 ErrNoReason, got %v", err)
	}
	if _, err := s.Report("u1", TargetGame, "", "理由"); err != ErrNoTarget {
		t.Errorf("空对象应 ErrNoTarget, got %v", err)
	}
	if _, err := s.Report("u1", TargetUser, "u1", "理由"); err != ErrSelf {
		t.Errorf("举报自己应 ErrSelf, got %v", err)
	}
}

func TestBlock_RejectsSelf(t *testing.T) {
	s := newSvc()
	if err := s.Block("u1", "u1"); err != ErrSelf {
		t.Errorf("屏蔽自己应 ErrSelf, got %v", err)
	}
}

func TestBlock_ToggleIdempotent(t *testing.T) {
	s := newSvc()
	s.Block("u1", "u2")
	s.Block("u1", "u2") // 幂等
	if b, _ := s.IsBlocked("u1", "u2"); !b {
		t.Error("u1 应已屏蔽 u2")
	}
	if b, _ := s.IsBlocked("u2", "u1"); b {
		t.Error("屏蔽是单向的")
	}
	list, _ := s.ListBlocked("u1")
	if len(list) != 1 || list[0] != "u2" {
		t.Errorf("屏蔽列表不对: %v", list)
	}

	s.Unblock("u1", "u2")
	if b, _ := s.IsBlocked("u1", "u2"); b {
		t.Error("取消屏蔽后应为 false")
	}
}

func TestBlockEntriesIncludeStableTimestamp(t *testing.T) {
	s := newSvc()
	before := time.Now()
	if err := s.Block("u1", "u2"); err != nil {
		t.Fatal(err)
	}
	first, err := s.ListBlockEntries("u1")
	if err != nil || len(first) != 1 {
		t.Fatalf("entries=%v err=%v", first, err)
	}
	if first[0].BlockedAt.Before(before) || first[0].BlockedAt.IsZero() {
		t.Fatalf("缺少屏蔽时间: %+v", first[0])
	}
	if err := s.Block("u1", "u2"); err != nil {
		t.Fatal(err)
	}
	second, _ := s.ListBlockEntries("u1")
	if !second[0].BlockedAt.Equal(first[0].BlockedAt) {
		t.Fatal("幂等屏蔽不应重置时间")
	}
}

func TestHideGameIsUserScopedAndPersistent(t *testing.T) {
	s := newSvc()
	if err := s.HideGame("u1", "g1"); err != nil {
		t.Fatal(err)
	}
	if ok, _ := s.IsGameHidden("u1", "g1"); !ok {
		t.Fatal("u1 should hide g1")
	}
	if ok, _ := s.IsGameHidden("u2", "g1"); ok {
		t.Fatal("hidden preference leaked to u2")
	}
}
