package app

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/yldm-tech/classic-games/apps/server/internal/storage"

	"gorm.io/gorm"
)

func TestNewBuildsApplicationAndRegistersCoreRoutes(t *testing.T) {
	cfg := applicationTestConfig(t)
	instance, err := New(context.Background(), cfg, Options{})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() {
		if closeErr := instance.Close(); closeErr != nil {
			t.Errorf("Close: %v", closeErr)
		}
	})

	routes := make(map[string]struct{})
	for _, route := range instance.Routes() {
		routes[route.Method+" "+route.Path] = struct{}{}
	}
	for _, route := range []string{
		"GET /healthz",
		"POST /api/v1/auth/guest",
		"GET /api/v1/games",
		"POST /api/v1/mods",
		"POST /api/v1/ai/validate",
	} {
		if _, ok := routes[route]; !ok {
			t.Errorf("missing route %s", route)
		}
	}

	response := httptest.NewRecorder()
	instance.Handler().ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("health status = %d", response.Code)
	}
}

func TestNewReturnsBaselineErrorWithoutTerminatingProcess(t *testing.T) {
	cfg := applicationTestConfig(t)
	cfg.Content.ShooterBaseline = filepath.Join(t.TempDir(), "missing.dsl.json")

	instance, err := New(context.Background(), cfg, Options{})
	if instance != nil {
		t.Fatal("New returned application after baseline failure")
	}
	if err == nil || !strings.Contains(err.Error(), "shooter baseline") {
		t.Fatalf("New error = %v", err)
	}
}

func TestCloseReleasesOwnedDatabase(t *testing.T) {
	cfg := applicationTestConfig(t)
	var captured *gorm.DB
	instance, err := New(context.Background(), cfg, Options{
		OpenDatabase: func(dsn string) (*gorm.DB, error) {
			db, openErr := storage.Open(dsn)
			captured = db
			return db, openErr
		},
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if captured == nil {
		t.Fatal("database opener was not used")
	}
	sqlDB, err := captured.DB()
	if err != nil {
		t.Fatalf("sql DB: %v", err)
	}
	if err := instance.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := sqlDB.Ping(); err == nil {
		t.Fatal("database remains open after App.Close")
	}
	if err := instance.Close(); err != nil {
		t.Fatalf("second Close must be idempotent: %v", err)
	}
}

func TestNewRejectsMissingContext(t *testing.T) {
	instance, err := New(nil, applicationTestConfig(t), Options{})
	if instance != nil || err == nil {
		t.Fatalf("New(nil) = %#v, %v", instance, err)
	}
}

func TestCommandEntryRemainsAThinLifecycleAdapter(t *testing.T) {
	root := repositoryRoot(t)
	mainFile, err := os.ReadFile(filepath.Join(root, "apps/server/cmd/server/main.go"))
	if err != nil {
		t.Fatal(err)
	}
	source := string(mainFile)
	if lines := strings.Count(source, "\n") + 1; lines > 80 {
		t.Fatalf("cmd/server/main.go has %d lines; composition belongs in internal/app", lines)
	}
	if !strings.Contains(source, "app.New(") {
		t.Fatal("cmd/server/main.go must delegate assembly to app.New")
	}
	for _, forbidden := range []string{"internal/ai", "internal/auth", "internal/games", "internal/storage"} {
		if strings.Contains(source, forbidden) {
			t.Errorf("cmd/server/main.go imports domain infrastructure %q", forbidden)
		}
	}
}

func applicationTestConfig(t *testing.T) Config {
	t.Helper()
	repositoryRoot := repositoryRoot(t)
	cfg, err := LoadConfig(mapLookup(nil))
	if err != nil {
		t.Fatal(err)
	}
	cfg.Database.DSN = "file:" + strings.NewReplacer("/", "_", " ", "_").Replace(t.Name()) + "?mode=memory&cache=shared"
	cfg.Content.SchemaDir = filepath.Join(repositoryRoot, "packages/schemas")
	cfg.Content.RuntimeDir = filepath.Join(repositoryRoot, "apps/client/runtime")
	cfg.Content.ShooterBaseline = filepath.Join(repositoryRoot, "apps/client/runtime/shooter/baseline.dsl.json")
	cfg.Content.SurvivorBaseline = filepath.Join(repositoryRoot, "apps/client/runtime/survivor/baseline.dsl.json")
	cfg.Content.TowerDefenseBaseline = filepath.Join(repositoryRoot, "apps/client/runtime/tower_defense/baseline.dsl.json")
	return cfg
}

func repositoryRoot(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(currentFile), "../../../.."))
}

func assertErrorIs(t *testing.T, got, want error) {
	t.Helper()
	if !errors.Is(got, want) {
		t.Fatalf("error = %v, want %v", got, want)
	}
}
