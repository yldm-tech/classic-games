package app

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"forgeplay/server/internal/storage"
)

func TestDefaultMigrationsHaveStableUniqueOrder(t *testing.T) {
	migrations := DefaultMigrations()
	if len(migrations) < 20 {
		t.Fatalf("migration count = %d, want at least 20", len(migrations))
	}

	seen := make(map[string]struct{}, len(migrations))
	previous := ""
	for _, migration := range migrations {
		if migration.ID == "" {
			t.Fatal("migration has empty ID")
		}
		if migration.ID <= previous {
			t.Fatalf("migration IDs are not strictly ordered: %q after %q", migration.ID, previous)
		}
		if _, exists := seen[migration.ID]; exists {
			t.Fatalf("duplicate migration ID %q", migration.ID)
		}
		if len(migration.Models) == 0 {
			t.Fatalf("migration %q has no models", migration.ID)
		}
		seen[migration.ID] = struct{}{}
		previous = migration.ID
	}
}

func TestMigrateIsIdempotentAndCreatesCoreTables(t *testing.T) {
	db, err := storage.Open("file:app_migrations?mode=memory&cache=shared")
	if err != nil {
		t.Fatalf("open database: %v", err)
	}

	for attempt := 1; attempt <= 2; attempt++ {
		if err := Migrate(db, DefaultMigrations()); err != nil {
			t.Fatalf("Migrate attempt %d: %v", attempt, err)
		}
	}

	for _, table := range []string{
		"users", "login_identities", "mods", "games", "comments", "events",
		"reports", "rooms", "replays", "orders",
	} {
		if !db.Migrator().HasTable(table) {
			t.Errorf("missing table %q", table)
		}
	}
}

func TestMigrateRejectsDuplicateIDsBeforeChangingSchema(t *testing.T) {
	db, err := storage.Open("file:duplicate_migrations?mode=memory&cache=shared")
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	migrations := []Migration{
		{ID: "001_duplicate", Models: []any{&migrationFixtureA{}}},
		{ID: "001_duplicate", Models: []any{&migrationFixtureB{}}},
	}

	if err := Migrate(db, migrations); err == nil {
		t.Fatal("Migrate returned nil error")
	}
	if db.Migrator().HasTable(&migrationFixtureA{}) || db.Migrator().HasTable(&migrationFixtureB{}) {
		t.Fatal("schema changed before migration registry validation")
	}
}

func TestAutoMigrateOnlyExistsInAppMigrationRunner(t *testing.T) {
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	internalDir := filepath.Dir(filepath.Dir(currentFile))
	allowed := filepath.Join(filepath.Dir(currentFile), "migrations.go")
	var violations []string

	err := filepath.WalkDir(internalDir, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") || path == allowed {
			return nil
		}
		contents, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		if strings.Contains(string(contents), ".AutoMigrate(") {
			relative, _ := filepath.Rel(internalDir, path)
			violations = append(violations, relative)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("scan migrations: %v", err)
	}
	if len(violations) > 0 {
		t.Fatal(fmt.Sprintf("repository constructors still mutate schema: %s", strings.Join(violations, ", ")))
	}
}

type migrationFixtureA struct{ ID uint }
type migrationFixtureB struct{ ID uint }
