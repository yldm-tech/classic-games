package quota

import (
	"forgeplay/server/internal/storage"
	"testing"
	"time"
)

func TestQuotaSurvivesRestart(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	store, _ := NewGormStateStore(db)
	s, _ := NewServiceWithStore(2, store)
	s.Allow("u")
	s.Allow("u")
	again, e := NewServiceWithStore(2, store)
	if e != nil {
		t.Fatal(e)
	}
	if ok, _ := again.Allow("u"); ok {
		t.Fatal("restart reset quota")
	}
}

func TestAllow_ConsumesAndBlocks(t *testing.T) {
	s := NewService(3)

	for i := 0; i < 3; i++ {
		ok, rem := s.Allow("u1")
		if !ok {
			t.Fatalf("第 %d 次应放行", i+1)
		}
		if rem != 2-i {
			t.Errorf("剩余 = %d, 期望 %d", rem, 2-i)
		}
	}
	// 第 4 次超额
	if ok, _ := s.Allow("u1"); ok {
		t.Error("超额应被拦截")
	}
	if s.Remaining("u1") != 0 {
		t.Error("剩余应为 0")
	}
}

func TestRefund_RestoresOne(t *testing.T) {
	s := NewService(2)
	s.Allow("u1") // 剩 1
	s.Allow("u1") // 剩 0
	if ok, _ := s.Allow("u1"); ok {
		t.Fatal("当日应已超额")
	}
	s.Refund("u1") // 回补一次 → 剩 1
	if s.Remaining("u1") != 1 {
		t.Errorf("回补后剩余应 1, got %d", s.Remaining("u1"))
	}
	if ok, _ := s.Allow("u1"); !ok {
		t.Error("回补后应可再次放行")
	}
}

func TestRefund_NotBelowZero(t *testing.T) {
	s := NewService(2)
	s.Refund("u1") // 从未消费,回补应为空操作,不变负
	if s.Remaining("u1") != 2 {
		t.Errorf("空回补不应改变额度, got %d", s.Remaining("u1"))
	}
}

func TestStatus_IsReadOnly(t *testing.T) {
	s := NewService(4)
	s.Allow("u1")
	before := s.Status("u1")
	if before.Used != 1 || before.Remaining != 3 || before.Limit != 4 {
		t.Fatalf("status = %#v", before)
	}
	after := s.Status("u1")
	if after != before {
		t.Fatalf("Status consumed quota: %#v vs %#v", after, before)
	}
	if s.Remaining("u1") != 3 {
		t.Fatal("Status must not change Remaining")
	}
}

func TestAllow_PerUserIsolated(t *testing.T) {
	s := NewService(1)
	s.Allow("u1")
	if ok, _ := s.Allow("u2"); !ok {
		t.Error("不同用户配额应独立")
	}
}

func TestAllow_DailyReset(t *testing.T) {
	s := NewService(2)
	s.Allow("u1")
	s.Allow("u1")
	if ok, _ := s.Allow("u1"); ok {
		t.Fatal("当日应已超额")
	}
	// 时钟拨到次日 → 重置
	s.now = func() time.Time { return time.Now().Add(24 * time.Hour) }
	if ok, rem := s.Allow("u1"); !ok || rem != 1 {
		t.Errorf("次日应重置, ok=%v rem=%d", ok, rem)
	}
}
