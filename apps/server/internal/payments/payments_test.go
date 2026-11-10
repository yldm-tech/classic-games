package payments

import (
	"github.com/yldm-tech/classic-games/apps/server/internal/storage"
	"sync/atomic"
	"testing"
	"time"
)

func TestSignedIdempotentPayment(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	grants := 0
	applied := map[string]bool{}
	s := NewService(r, "secret", []Product{{ID: "p", Amount: 100, Currency: "CNY", Kind: "points", Value: 300}}, func(id, _ string, _ Product) error {
		if !applied[id] {
			grants++
			applied[id] = true
		}
		return nil
	})
	o, e := s.Create("u", "p")
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.Confirm(o.ID, "tx", 101, "CNY", s.Sign(o.ID, "tx", 101, "CNY")); e != ErrMismatch {
		t.Fatalf("mismatch %v", e)
	}
	sig := s.Sign(o.ID, "tx", 100, "CNY")
	got, e := s.Confirm(o.ID, "tx", 100, "CNY", sig)
	if e != nil || got.Status != "paid" || grants != 1 {
		t.Fatalf("%+v %v grants=%d", got, e, grants)
	}
	_, e = s.Confirm(o.ID, "tx", 100, "CNY", sig)
	if e != nil || grants != 1 {
		t.Fatalf("idempotency %v grants=%d", e, grants)
	}
	otherSig := s.Sign(o.ID, "other", 100, "CNY")
	if _, e = s.Confirm(o.ID, "other", 100, "CNY", otherSig); e != ErrMismatch {
		t.Fatalf("different transaction replay: %v", e)
	}
	if _, e = s.Confirm(o.ID, "", 100, "CNY", s.Sign(o.ID, "", 100, "CNY")); e != ErrMismatch {
		t.Fatalf("empty transaction: %v", e)
	}
}

func TestTransactionConflictNeverGrantsBeforeAtomicClaim(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	grants := 0
	s := NewService(r, "secret", []Product{{ID: "p", Amount: 100, Currency: "CNY", Kind: "points", Value: 1}}, func(_ string, _ string, _ Product) error { grants++; return nil })
	first, err := s.Create("u1", "p")
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.Create("u2", "p")
	if err != nil {
		t.Fatal(err)
	}
	tx := "provider-transaction"
	if _, err := s.Confirm(first.ID, tx, 100, "CNY", s.Sign(first.ID, tx, 100, "CNY")); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Confirm(second.ID, tx, 100, "CNY", s.Sign(second.ID, tx, 100, "CNY")); err == nil {
		t.Fatal("duplicate provider transaction accepted")
	}
	if grants != 1 {
		t.Fatalf("entitlement granted before transaction claim: %d", grants)
	}
	stored, _ := r.Get(second.ID)
	if stored.Status != "pending" {
		t.Fatalf("conflicting order status=%s", stored.Status)
	}
}

func TestProcessingOrderHasSingleGrantExecutor(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	entered := make(chan struct{})
	release := make(chan struct{})
	var grants atomic.Int32
	s := NewService(r, "secret", []Product{{ID: "p", Amount: 100, Currency: "CNY", Kind: "points", Value: 1}}, func(_ string, _ string, _ Product) error {
		grants.Add(1)
		close(entered)
		<-release
		return nil
	})
	o, _ := s.Create("u", "p")
	sig := s.Sign(o.ID, "tx", 100, "CNY")
	firstDone := make(chan error, 1)
	go func() {
		_, err := s.Confirm(o.ID, "tx", 100, "CNY", sig)
		firstDone <- err
	}()
	<-entered
	if _, err := s.Confirm(o.ID, "tx", 100, "CNY", sig); err != ErrTransition {
		t.Fatalf("concurrent processing callback=%v", err)
	}
	close(release)
	if err := <-firstDone; err != nil {
		t.Fatal(err)
	}
	if _, err := s.Confirm(o.ID, "tx", 100, "CNY", sig); err != nil {
		t.Fatalf("paid retry=%v", err)
	}
	if grants.Load() != 1 {
		t.Fatalf("grant executors=%d", grants.Load())
	}
}

func TestFailedGrantReleasesClaimAndExpiredLeaseCanRecover(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	grants := 0
	s := NewService(r, "secret", []Product{{ID: "p", Amount: 100, Currency: "CNY", Kind: "points", Value: 1}}, func(_ string, _ string, _ Product) error {
		grants++
		if grants == 1 {
			return ErrTransition
		}
		return nil
	})
	o, _ := s.Create("u", "p")
	sig := s.Sign(o.ID, "tx", 100, "CNY")
	if _, err := s.Confirm(o.ID, "tx", 100, "CNY", sig); err == nil {
		t.Fatal("first grant failure was swallowed")
	}
	paid, err := s.Confirm(o.ID, "tx", 100, "CNY", sig)
	if err != nil || paid.Status != "paid" || grants != 2 {
		t.Fatalf("released retry=%+v err=%v grants=%d", paid, err, grants)
	}

	other, _ := s.Create("u", "p")
	start := time.Now().UTC()
	if _, claimed, err := r.Claim(other.ID, "tx-expired", "owner-1", start, start.Add(time.Minute)); err != nil || !claimed {
		t.Fatalf("initial lease=%v claimed=%v", err, claimed)
	}
	if _, claimed, err := r.Claim(other.ID, "tx-expired", "owner-2", start.Add(30*time.Second), start.Add(2*time.Minute)); err != nil || claimed {
		t.Fatalf("active lease reacquired=%v claimed=%v", err, claimed)
	}
	if got, claimed, err := r.Claim(other.ID, "tx-expired", "owner-3", start.Add(2*time.Minute), start.Add(3*time.Minute)); err != nil || !claimed || got.ClaimToken == nil || *got.ClaimToken != "owner-3" {
		t.Fatalf("expired lease recovery=%+v claimed=%v err=%v", got, claimed, err)
	}
}

func TestListOrdersIsScopedToCaller(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	s := NewService(r, "secret", []Product{{ID: "p", Amount: 100, Currency: "CNY", Kind: "points", Value: 1}}, nil)
	mine, err := s.Create("u1", "p")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.Create("u2", "p"); err != nil {
		t.Fatal(err)
	}
	items, err := s.List("u1")
	if err != nil || len(items) != 1 || items[0].ID != mine.ID {
		t.Fatalf("scoped list=%+v err=%v", items, err)
	}
	empty, err := s.List("")
	if err != nil || len(empty) != 0 {
		t.Fatalf("empty user leaked orders=%+v err=%v", empty, err)
	}
}
