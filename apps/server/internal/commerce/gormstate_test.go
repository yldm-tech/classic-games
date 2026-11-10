package commerce

import (
	"forgeplay/server/internal/storage"
	"testing"
)

func TestGormStateSurvivesServiceRestart(t *testing.T) {
	db, err := storage.Open("")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	store, err := NewGormStateStore(db)
	if err != nil {
		t.Fatal(err)
	}
	s1, err := NewServiceWithStore(store)
	if err != nil {
		t.Fatal(err)
	}
	start := 1280
	if err := s1.ApplyPayment("setup-restart", "restart_user", "points", start); err != nil {
		t.Fatal(err)
	}
	if _, err = s1.Purchase("restart_user", "skin_ember"); err != nil {
		t.Fatal(err)
	}
	if err = s1.ApplyPayment("pay_restart", "restart_user", "membership", 1); err != nil {
		t.Fatal(err)
	}
	if _, _, err = s1.Checkin("restart_user"); err != nil {
		t.Fatal(err)
	}
	s2, err := NewServiceWithStore(store)
	if err != nil {
		t.Fatal(err)
	}
	if got := s2.PointsFor("restart_user", "zh").Balance; got != start-680+10 {
		t.Fatalf("balance not restored: %d", got)
	}
	if !s2.ShopFor("restart_user", "zh").Skins[0].Owned {
		t.Fatal("purchase not restored")
	}
	if !s2.MembershipFor("restart_user", "zh").Active {
		t.Fatal("membership not restored")
	}
	if !s2.WelfareFor("restart_user", "zh").Checkin.Checked {
		t.Fatal("checkin not restored")
	}
	if err = s2.ApplyPayment("pay_restart", "restart_user", "membership", 1); err != nil {
		t.Fatal(err)
	}
}
