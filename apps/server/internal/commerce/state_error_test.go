package commerce

import (
	"errors"
	"testing"

	"github.com/yldm-tech/classic-games/apps/server/internal/storage"
)

// flakyStore fails the next Load once, then delegates. It models a transient read failure: a dropped connection, a
// locked database file, or a corrupt stored blob.
type flakyStore struct {
	inner   StateStore
	failNow bool
}

var errTransientRead = errors.New("commerce: simulated transient read failure")

func (f *flakyStore) Load(userID string) (*userState, error) {
	if f.failNow {
		f.failNow = false
		return nil, errTransientRead
	}
	return f.inner.Load(userID)
}

func (f *flakyStore) Save(userID string, st *userState) error { return f.inner.Save(userID, st) }

// A store read that fails must never be mistaken for a new user. Before this was fixed, stateLocked discarded the
// error, cached an empty wallet for the life of the process, and the next mutation persisted that emptiness over the
// user's row — destroying their balance, membership, owned items and the payment idempotency keys.
func TestTransientLoadFailureDoesNotDestroyWallet(t *testing.T) {
	db, err := storage.Open("")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	inner, err := NewGormStateStore(db)
	if err != nil {
		t.Fatal(err)
	}

	funded, err := NewServiceWithStore(inner)
	if err != nil {
		t.Fatal(err)
	}
	if payErr := funded.ApplyPayment("pay_setup", "u", "points", 5000); payErr != nil {
		t.Fatal(payErr)
	}
	if payErr := funded.ApplyPayment("pay_member", "u", "membership", 1); payErr != nil {
		t.Fatal(payErr)
	}

	// A fresh process whose very first read of this user fails.
	flaky := &flakyStore{inner: inner, failNow: true}
	restarted, err := NewServiceWithStore(flaky)
	if err != nil {
		t.Fatal(err)
	}
	if creditErr := restarted.CreditPoints("u", 1); !errors.Is(creditErr, errTransientRead) {
		t.Fatalf("mutation after a failed load returned %v, want the read error — it must not operate on a fabricated empty wallet", creditErr)
	}

	// The store recovered, so the next call must see the real state rather than a cached empty one.
	if balance := restarted.PointsFor("u", "zh").Balance; balance != 5000 {
		t.Fatalf("balance after a recovered read = %d, want 5000", balance)
	}
	if !restarted.MembershipFor("u", "zh").Active {
		t.Fatal("membership lost after a transient read failure")
	}

	// And the durable row must still be intact for any later process.
	final, err := NewServiceWithStore(inner)
	if err != nil {
		t.Fatal(err)
	}
	if balance := final.PointsFor("u", "zh").Balance; balance != 5000 {
		t.Fatalf("persisted balance = %d, want 5000", balance)
	}
}
