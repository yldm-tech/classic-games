package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func env(values map[string]string) func(string) string {
	return func(key string) string { return values[key] }
}

func TestFromEnv(t *testing.T) {
	defaults := FromEnv(env(nil))
	if defaults != (Config{ServerURL: "http://localhost:8080"}) {
		t.Errorf("defaults = %+v, want only the default server URL", defaults)
	}

	cfg := FromEnv(env(map[string]string{
		EnvServerURL: " https://classic-games.example/api-root ",
		EnvToken:     " secret-token\n",
		EnvSchemaDir: "/srv/schemas",
		EnvLanguage:  "en",
	}))
	want := Config{ServerURL: "https://classic-games.example/api-root", Token: "secret-token", SchemaDir: "/srv/schemas", Language: "en"}
	if cfg != want {
		t.Errorf("FromEnv = %+v, want %+v", cfg, want)
	}
}

// writeSchema creates dir with one schema file in it.
func writeSchema(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "shooter-1.0.0.schema.json"), []byte(`{"type":"object"}`), 0o600); err != nil {
		t.Fatal(err)
	}
}

// realPath resolves symlinks so paths under a macOS temp directory compare equal.
func realPath(t *testing.T, path string) string {
	t.Helper()
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		t.Fatal(err)
	}
	return resolved
}

func TestResolveSchemaDirExplicit(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "my-schemas")
	writeSchema(t, dir)
	got, err := ResolveSchemaDir(dir, "/nonexistent")
	if err != nil || got != dir {
		t.Errorf("ResolveSchemaDir(explicit) = %q, %v; want %q", got, err, dir)
	}

	// An explicit directory is never replaced by auto-detection, even when a repository is in reach.
	repo := t.TempDir()
	writeSchema(t, filepath.Join(repo, "packages", "schemas"))
	empty := t.TempDir()
	if _, err := ResolveSchemaDir(empty, repo); err == nil || !strings.Contains(err.Error(), EnvSchemaDir+"="+empty) {
		t.Errorf("explicit directory without schemas: %v, want an error naming %s", err, EnvSchemaDir)
	}
}

func TestResolveSchemaDirAutoDetect(t *testing.T) {
	repo := realPath(t, t.TempDir())
	want := filepath.Join(repo, "packages", "schemas")
	writeSchema(t, want)
	nested := filepath.Join(repo, "apps", "mcp", "bin")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}

	for name, searchFrom := range map[string][]string{
		"from the repository root":      {repo},
		"from a nested directory":       {nested},
		"second start directory":        {realPath(t, t.TempDir()), nested},
		"empty start directory skipped": {"", repo},
	} {
		if got, err := ResolveSchemaDir("", searchFrom...); err != nil || got != want {
			t.Errorf("%s: ResolveSchemaDir = %q, %v; want %q", name, got, err, want)
		}
	}
}

// The start directories are tried in order, and a packages/schemas directory that holds no DSL schema (another project's schemas) is passed over instead of being chosen and then refused.
func TestResolveSchemaDirOrderAndForeignDirectories(t *testing.T) {
	first := realPath(t, t.TempDir())
	second := realPath(t, t.TempDir())
	writeSchema(t, filepath.Join(first, "packages", "schemas"))
	writeSchema(t, filepath.Join(second, "packages", "schemas"))
	if got, err := ResolveSchemaDir("", first, second); err != nil || got != filepath.Join(first, "packages", "schemas") {
		t.Errorf("both start directories hold schemas: got %q, %v; want the first", got, err)
	}

	foreign := realPath(t, t.TempDir())
	foreignSchemas := filepath.Join(foreign, "packages", "schemas")
	if err := os.MkdirAll(foreignSchemas, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(foreignSchemas, "user.schema.json"), []byte(`{"type":"object"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got, err := ResolveSchemaDir("", foreign, second); err != nil || got != filepath.Join(second, "packages", "schemas") {
		t.Errorf("first start directory holds another project's schemas: got %q, %v; want the second", got, err)
	}
	if _, err := ResolveSchemaDir(foreignSchemas); err == nil || !strings.Contains(err.Error(), EnvSchemaDir) {
		t.Errorf("explicit directory with another project's schemas: %v, want an error naming %s", err, EnvSchemaDir)
	}
	// A nested project inside the repository does not hide the repository's schemas.
	nested := filepath.Join(second, "vendor", "other")
	if err := os.MkdirAll(filepath.Join(nested, "packages", "schemas"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(nested, "packages", "schemas", "user.schema.json"), []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got, err := ResolveSchemaDir("", nested); err != nil || got != filepath.Join(second, "packages", "schemas") {
		t.Errorf("nested foreign directory: got %q, %v; want the enclosing repository's schemas", got, err)
	}
}

func TestResolveSchemaDirNotFound(t *testing.T) {
	outside := realPath(t, t.TempDir())
	// A packages/schemas directory without schema files does not count.
	if err := os.MkdirAll(filepath.Join(outside, "packages", "schemas"), 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := ResolveSchemaDir("", outside)
	if err == nil {
		t.Fatal("ResolveSchemaDir found schemas where there are none")
	}
	for _, fragment := range []string{"set " + EnvSchemaDir, "packages/schemas", outside} {
		if !strings.Contains(err.Error(), fragment) {
			t.Errorf("error %q does not contain %q", err, fragment)
		}
	}
}
