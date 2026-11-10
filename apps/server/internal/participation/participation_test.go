package participation

import (
	"testing"
	"time"

	"forgeplay/server/internal/storage"
)

func TestWithdrawAndJoinPersist(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	s := NewService(r, func(id string) bool { return id == "event_1" }, func(string) int { return 500 })
	if _, e := s.Withdraw("u", 501); e != ErrInvalidAmount {
		t.Fatalf("overdraw %v", e)
	}
	w, e := s.Withdraw("u", 100)
	if e != nil || w.Status != "pending" {
		t.Fatalf("%+v %v", w, e)
	}
	if _, e = s.Withdraw("u", 100); e != ErrDuplicate {
		t.Fatalf("duplicate %v", e)
	}
	if _, e = s.Join("u", "bad"); e != ErrEventNotFound {
		t.Fatalf("bad event %v", e)
	}
	s.Join("u", "event_1")
	s.Join("u", "event_1")
	ids, e := s.Joined("u")
	if e != nil || len(ids) != 1 {
		t.Fatalf("%v %v", ids, e)
	}
}

// 部分唯一索引应在 DB 层拦下第二条 pending 提现,即便绕过 Service 预检也只允许一条。回归守卫 C13/C18。
func TestCreateWithdrawal_UniqueIndexBlocksSecondPending(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	if _, e := r.CreateWithdrawal(Withdrawal{ID: "wd_1", UserID: "u", Amount: 100, Status: "pending"}); e != nil {
		t.Fatalf("首条 pending 应成功: %v", e)
	}
	// 直接建第二条 pending(绕过 PendingWithdrawal 预检),索引应拦下并归一为 ErrDuplicate。
	if _, e := r.CreateWithdrawal(Withdrawal{ID: "wd_2", UserID: "u", Amount: 100, Status: "pending"}); e != ErrDuplicate {
		t.Fatalf("第二条 pending 应被唯一索引拒绝(ErrDuplicate), got %v", e)
	}
	// 非 pending(如已完成)不受部分索引约束,允许存在。
	if _, e := r.CreateWithdrawal(Withdrawal{ID: "wd_3", UserID: "u", Amount: 100, Status: "paid"}); e != nil {
		t.Fatalf("非 pending 提现不应受约束: %v", e)
	}
}

func TestWithdrawalsListAndReserved(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	s := NewService(r, func(string) bool { return true }, func(string) int { return 500 })
	if items, e := s.Withdrawals(""); e != nil || len(items) != 0 {
		t.Fatalf("empty user leaked withdrawals=%+v err=%v", items, e)
	}
	// Fixture rows get explicit older timestamps: with an implicit "now" they can tie with the pending row at storage precision, and the id DESC tiebreaker then sorts them first.
	older := time.Now().UTC().Add(-time.Hour)
	if _, e := r.CreateWithdrawal(Withdrawal{ID: "wd_paid", UserID: "u", Amount: 120, Status: "paid", CreatedAt: older}); e != nil {
		t.Fatal(e)
	}
	if _, e := r.CreateWithdrawal(Withdrawal{ID: "wd_fail", UserID: "u", Amount: 80, Status: "failed", CreatedAt: older}); e != nil {
		t.Fatal(e)
	}
	pending, e := s.Withdraw("u", 100)
	if e != nil {
		t.Fatal(e)
	}
	items, e := s.Withdrawals("u")
	if e != nil || len(items) != 3 {
		t.Fatalf("list=%+v err=%v", items, e)
	}
	if items[0].ID != pending.ID {
		t.Fatalf("newest first got %s want %s", items[0].ID, pending.ID)
	}
	reserved, e := s.Reserved("u")
	if e != nil || reserved != 220 {
		t.Fatalf("reserved=%d err=%v", reserved, e)
	}
	other, e := s.Withdrawals("other")
	if e != nil || len(other) != 0 {
		t.Fatalf("other user leaked=%+v err=%v", other, e)
	}
}
