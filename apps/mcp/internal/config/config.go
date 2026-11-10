// Package config reads the forgeplay-mcp configuration from the environment and locates the Mod DSL schema directory.
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"forgeplay/mcp/internal/schemas"
)

// Environment variables read by forgeplay-mcp.
const (
	EnvServerURL = "FORGEPLAY_SERVER_URL"
	EnvToken     = "FORGEPLAY_TOKEN"
	EnvSchemaDir = "FORGEPLAY_SCHEMA_DIR"
	EnvLanguage  = "FORGEPLAY_LANG"
)

// DefaultServerURL is where a locally started backend listens.
const DefaultServerURL = "http://localhost:8080"

// repoSchemaDir is where the schemas live inside the ForgePlay repository.
var repoSchemaDir = filepath.Join("packages", "schemas")

// Config is the environment-provided part of the configuration.
type Config struct {
	// ServerURL is the root address of the ForgePlay backend, without the /api/v1 prefix.
	ServerURL string
	// Token is the bearer token for the backend, or "" to stay anonymous.
	Token string
	// SchemaDir is the explicitly configured schema directory, or "" to auto-detect.
	SchemaDir string
	// Language selects the language of backend messages and game titles ("zh", "en" or "ja"), or "" for the backend default.
	Language string
}

// FromEnv reads the configuration through getenv, which is os.Getenv outside tests.
func FromEnv(getenv func(string) string) Config {
	cfg := Config{
		ServerURL: strings.TrimSpace(getenv(EnvServerURL)),
		Token:     strings.TrimSpace(getenv(EnvToken)),
		SchemaDir: strings.TrimSpace(getenv(EnvSchemaDir)),
		Language:  strings.TrimSpace(getenv(EnvLanguage)),
	}
	if cfg.ServerURL == "" {
		cfg.ServerURL = DefaultServerURL
	}
	return cfg
}

// ResolveSchemaDir returns the directory holding the <runtime>-<version>.schema.json files. An explicit directory is used as is and must contain at least one schema. Otherwise the start directories in searchFrom are tried in order, and for each the first packages/schemas directory at or above it that holds a schema wins. The caller passes the directory of the binary before the working directory: a binary built into the repository then always uses the repository's schemas, whatever project a client starts it from, and the working directory only serves `go run` and binaries installed elsewhere. A packages/schemas directory without any <runtime>-<version>.schema.json file (another project's schemas) is skipped.
func ResolveSchemaDir(explicit string, searchFrom ...string) (string, error) {
	if explicit != "" {
		if !hasSchemas(explicit) {
			return "", fmt.Errorf("%s=%s does not contain any <runtime>-<version>.schema.json file; point it at packages/schemas of the ForgePlay repository", EnvSchemaDir, explicit)
		}
		return filepath.Abs(explicit)
	}
	var searched []string
	for _, start := range searchFrom {
		if start == "" {
			continue
		}
		start, err := filepath.Abs(start)
		if err != nil {
			continue
		}
		searched = append(searched, start)
		for dir := start; ; dir = filepath.Dir(dir) {
			candidate := filepath.Join(dir, repoSchemaDir)
			if hasSchemas(candidate) {
				return candidate, nil
			}
			if dir == filepath.Dir(dir) {
				break
			}
		}
	}
	return "", fmt.Errorf("cannot find the ForgePlay DSL schemas: set %s to the directory holding the <runtime>-<version>.schema.json files (packages/schemas in the ForgePlay repository); looked for %s at or above: %s", EnvSchemaDir, repoSchemaDir, strings.Join(searched, ", "))
}

// hasSchemas reports whether dir is a directory with at least one file the schema catalog loads. It uses the catalog's own file-name rule, so a directory is never chosen here and then refused by schemas.Open.
func hasSchemas(dir string) bool {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if !entry.IsDir() && schemas.IsSchemaFile(entry.Name()) {
			return true
		}
	}
	return false
}
