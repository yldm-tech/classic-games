package storage_test

import (
	"database/sql"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"forgeplay/server/internal/app"
	"forgeplay/server/internal/storage"
)

type storageRecord struct {
	ID   uint `gorm:"primaryKey"`
	Name string
}

func TestOpenSupportsInMemoryMigrations(t *testing.T) {
	db, err := storage.Open("")
	if err != nil {
		t.Fatal(err)
	}
	closeDatabase(t, db)

	if err := db.AutoMigrate(&storageRecord{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if err := db.Create(&storageRecord{Name: "memory"}).Error; err != nil {
		t.Fatalf("create: %v", err)
	}
	var count int64
	if err := db.Model(&storageRecord{}).Count(&count).Error; err != nil || count != 1 {
		t.Fatalf("count = %d, %v", count, err)
	}
}

func TestOpenPersistsFileDatabaseAcrossConnections(t *testing.T) {
	path := filepath.Join(t.TempDir(), "forgeplay.db")
	first, err := storage.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := first.AutoMigrate(&storageRecord{}); err != nil {
		t.Fatal(err)
	}
	if err := first.Create(&storageRecord{Name: "persistent"}).Error; err != nil {
		t.Fatal(err)
	}
	closeNow(t, first)

	second, err := storage.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	closeDatabase(t, second)
	var record storageRecord
	if err := second.First(&record).Error; err != nil || record.Name != "persistent" {
		t.Fatalf("record = %#v, %v", record, err)
	}
}

func TestMaintainedDriverSupportsCentralMigrations(t *testing.T) {
	db, err := storage.Open("file:" + strings.ReplaceAll(t.Name(), "/", "_") + "?mode=memory&cache=shared")
	if err != nil {
		t.Fatal(err)
	}
	closeDatabase(t, db)
	if err := app.Migrate(db, app.DefaultMigrations()); err != nil {
		t.Fatalf("central migrations: %v", err)
	}
}

func TestStorageDoesNotUseUnmaintainedGlebarezDriver(t *testing.T) {
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	goModPath := filepath.Clean(filepath.Join(filepath.Dir(currentFile), "../../go.mod"))
	contents, err := os.ReadFile(goModPath)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(contents), "github.com/glebarez/sqlite") {
		t.Fatal("storage still depends on the unmaintained github.com/glebarez/sqlite driver")
	}
}

func closeDatabase(t *testing.T, db interface{ DB() (*sql.DB, error) }) {
	t.Helper()
	t.Cleanup(func() { closeNow(t, db) })
}

func closeNow(t *testing.T, db interface{ DB() (*sql.DB, error) }) {
	t.Helper()
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatal(err)
	}
}
