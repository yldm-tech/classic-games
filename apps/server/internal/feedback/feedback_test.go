package feedback

import (
	"forgeplay/server/internal/storage"
	"testing"
)

func TestSubmitPersistsAndScopes(t *testing.T) {
	db, err := storage.Open("")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(r)
	got, err := s.Submit("u1", "  useful feedback  ")
	if err != nil {
		t.Fatal(err)
	}
	if got.UserID != "u1" || got.Content != "useful feedback" {
		t.Fatalf("%+v", got)
	}
	var stored Item
	if err = db.First(&stored, "id = ?", got.ID).Error; err != nil {
		t.Fatal(err)
	}
	if _, err = s.Submit("u1", ""); err != ErrInvalid {
		t.Fatalf("empty: %v", err)
	}
}
