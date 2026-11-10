package app

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestLoadConfigUsesDevelopmentDefaults(t *testing.T) {
	cfg, err := LoadConfig(mapLookup(nil))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	if cfg.Environment != Development {
		t.Fatalf("environment = %q, want %q", cfg.Environment, Development)
	}
	if cfg.HTTP.Port != "8080" {
		t.Fatalf("port = %q, want 8080", cfg.HTTP.Port)
	}
	if cfg.HTTP.MaxBodyBytes != 1<<20 {
		t.Fatalf("max body = %d, want %d", cfg.HTTP.MaxBodyBytes, 1<<20)
	}
	if cfg.HTTP.ShutdownTimeout != 10*time.Second {
		t.Fatalf("shutdown timeout = %s, want 10s", cfg.HTTP.ShutdownTimeout)
	}
	if cfg.Database.DSN != "classic-games.db" {
		t.Fatalf("database DSN = %q", cfg.Database.DSN)
	}
	if cfg.Content.SchemaDir != "../../packages/schemas" || cfg.Content.RuntimeDir != "../client/runtime" {
		t.Fatalf("content paths = %#v", cfg.Content)
	}
	if cfg.Auth.DevAdmin {
		t.Fatal("development admin bypass must be opt-in")
	}
	if cfg.HTTP.HSTS {
		t.Fatal("development must not enable HSTS")
	}
}

func TestLoadConfigNormalizesListsAndDurations(t *testing.T) {
	cfg, err := LoadConfig(mapLookup(map[string]string{
		"CLASSIC_GAMES_TRUSTED_PROXIES":  " 10.0.0.0/8, ,192.168.0.0/16 ",
		"CLASSIC_GAMES_ADMIN_IDS":        " admin-a,admin-b, admin-a ",
		"CLASSIC_GAMES_SHUTDOWN_TIMEOUT": "750ms",
	}))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	assertStrings(t, cfg.HTTP.TrustedProxies, []string{"10.0.0.0/8", "192.168.0.0/16"})
	assertStrings(t, cfg.Auth.AdminIDs, []string{"admin-a", "admin-b"})
	if cfg.HTTP.ShutdownTimeout != 750*time.Millisecond {
		t.Fatalf("shutdown timeout = %s", cfg.HTTP.ShutdownTimeout)
	}
}

func TestLoadConfigRejectsUnsafeOrInvalidValues(t *testing.T) {
	tests := map[string]map[string]string{
		"production development admin": {
			"CLASSIC_GAMES_ENV":       "production",
			"CLASSIC_GAMES_DEV_ADMIN": "1",
			"CLASSIC_GAMES_SECRET":    "production-secret-must-be-32chars!",
			"CLASSIC_GAMES_DB":        "classic-games-prod.db",
		},
		"production missing secret": {
			"CLASSIC_GAMES_ENV": "production",
			"CLASSIC_GAMES_DB":  "classic-games-prod.db",
		},
		"production short secret": {
			"CLASSIC_GAMES_ENV":    "production",
			"CLASSIC_GAMES_SECRET": "too-short",
			"CLASSIC_GAMES_DB":     "classic-games-prod.db",
		},
		"production missing database": {
			"CLASSIC_GAMES_ENV":    "production",
			"CLASSIC_GAMES_SECRET": "production-secret-must-be-32chars!",
		},
		"production http oauth": {
			"CLASSIC_GAMES_ENV":       "production",
			"CLASSIC_GAMES_SECRET":    "production-secret-must-be-32chars!",
			"CLASSIC_GAMES_DB":        "classic-games-prod.db",
			"OAUTH_GOOGLE_VERIFY_URL": "http://identity.example/verify",
		},
		"production http sms gateway": {
			"CLASSIC_GAMES_ENV":    "production",
			"CLASSIC_GAMES_SECRET": "production-secret-must-be-32chars!",
			"CLASSIC_GAMES_DB":     "classic-games-prod.db",
			"SMS_GATEWAY_URL":      "http://sms.example/send",
		},
		"invalid environment": {
			"CLASSIC_GAMES_ENV": "staging-ish",
		},
		"invalid timeout": {
			"CLASSIC_GAMES_SHUTDOWN_TIMEOUT": "eventually",
		},
		"non-positive timeout": {
			"CLASSIC_GAMES_SHUTDOWN_TIMEOUT": "0s",
		},
		"invalid body limit": {
			"CLASSIC_GAMES_MAX_BODY_BYTES": "huge",
		},
	}

	for name, values := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := LoadConfig(mapLookup(values)); err == nil {
				t.Fatal("LoadConfig returned nil error")
			}
		})
	}
}

func TestLoadConfigAcceptsProductionWithSecret(t *testing.T) {
	cfg, err := LoadConfig(mapLookup(map[string]string{
		"CLASSIC_GAMES_ENV":       "production",
		"CLASSIC_GAMES_SECRET":    "production-secret-must-be-32chars!",
		"CLASSIC_GAMES_DB":        "postgres://classic-games/prod",
		"OAUTH_GOOGLE_VERIFY_URL": "https://identity.example/verify",
		"SMS_GATEWAY_URL":         "https://sms.example/send",
	}))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if cfg.Environment != Production {
		t.Fatalf("environment = %q", cfg.Environment)
	}
	if cfg.Security.Secret != "production-secret-must-be-32chars!" {
		t.Fatalf("secret not retained")
	}
	if cfg.Database.DSN != "postgres://classic-games/prod" {
		t.Fatalf("database DSN = %q", cfg.Database.DSN)
	}
	if !cfg.HTTP.HSTS {
		t.Fatal("production must enable HSTS")
	}
}

func TestConfigStringRedactsSecrets(t *testing.T) {
	secrets := []string{"anthropic-secret", "classic-games-secret", "sms-secret", "moderation-secret", "payment-secret", "oauth-secret"}
	cfg, err := LoadConfig(mapLookup(map[string]string{
		"ANTHROPIC_API_KEY":         secrets[0],
		"CLASSIC_GAMES_SECRET":      secrets[1],
		"SMS_GATEWAY_TOKEN":         secrets[2],
		"CONTENT_MODERATION_TOKEN":  secrets[3],
		"PAYMENT_WEBHOOK_SECRET":    secrets[4],
		"OAUTH_GOOGLE_VERIFY_URL":   "https://identity.example/verify",
		"OAUTH_GOOGLE_VERIFY_TOKEN": secrets[5],
	}))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	printed := cfg.String()
	for _, secret := range secrets {
		if strings.Contains(printed, secret) {
			t.Fatalf("Config.String leaked secret %q: %s", secret, printed)
		}
	}
	if !strings.Contains(printed, "production=false") {
		t.Fatalf("Config.String omitted safe summary: %s", printed)
	}
}

// CLASSIC_GAMES_DB is a SQLite file path, but the configuration is logged before the database is opened, so a connection string put there by mistake must not reach the log with its password.
func TestConfigStringRedactsDatabaseCredentials(t *testing.T) {
	for _, dsn := range []string{
		"postgres://classic-games:db-password@db.internal:5432/classic-games?sslmode=require",
		"host=db.internal user=classic-games password=db-password dbname=classic-games",
		"classic-games:db-password@tcp(db.internal:3306)/classic-games",
		"file:classic-games.db?_pragma=key('db-password')",
	} {
		printed := Config{Database: DatabaseConfig{DSN: dsn}}.String()
		if strings.Contains(printed, "db-password") {
			t.Errorf("Config.String leaked the password of %q: %s", dsn, printed)
		}
	}
	for dsn, want := range map[string]string{
		"classic-games.db":                    "database=classic-games.db ",
		"/var/lib/classic-games/data.db":      "database=/var/lib/classic-games/data.db ",
		"file:/var/lib/classic-games/data.db": "database=file:/var/lib/classic-games/data.db ",
		"file:classic-games.db?mode=ro":       "database=file:classic-games.db ",
		":memory:":                            "database=:memory: ",
	} {
		if printed := (Config{Database: DatabaseConfig{DSN: dsn}}).String(); !strings.Contains(printed, want) {
			t.Errorf("Config.String for %q = %s, want it to contain %q", dsn, printed, want)
		}
	}
}

func TestPublicCapabilitiesOmitsSecretsAndReportsWiring(t *testing.T) {
	cfg, err := LoadConfig(mapLookup(map[string]string{
		"ANTHROPIC_API_KEY":        "sk-secret-must-not-leak",
		"SMS_GATEWAY_URL":          "https://sms.example.test",
		"SMS_GATEWAY_TOKEN":        "sms-token-secret",
		"OAUTH_APPLE_VERIFY_URL":   "https://apple.example.test/verify",
		"OAUTH_APPLE_VERIFY_TOKEN": "apple-token-secret",
		"PAYMENT_WEBHOOK_SECRET":   "pay-secret",
		"CLASSIC_GAMES_ADMIN_IDS":  "admin-a",
		"CONTENT_MODERATION_URL":   "https://mod.example.test",
		"CONTENT_MODERATION_TOKEN": "mod-token-secret",
	}))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	caps := cfg.PublicCapabilities()
	encoded := fmt.Sprintf("%v", caps)
	for _, secret := range []string{"sk-secret-must-not-leak", "sms-token-secret", "apple-token-secret", "pay-secret", "mod-token-secret", "admin-a"} {
		if strings.Contains(encoded, secret) {
			t.Fatalf("PublicCapabilities leaked %q: %v", secret, caps)
		}
	}
	if mode, _ := caps["ai"].(map[string]any)["mode"].(string); mode != "live" {
		t.Fatalf("ai mode = %v", caps["ai"])
	}
	if caps["sms"] != true || caps["payments"] != true || caps["admin_configured"] != true || caps["moderation"] != true {
		t.Fatalf("wired flags = %#v", caps)
	}
	providers, _ := caps["oauth_providers"].([]string)
	assertStrings(t, providers, []string{"apple"})
}

func mapLookup(values map[string]string) LookupEnv {
	return func(key string) (string, bool) {
		value, ok := values[key]
		return value, ok
	}
}

func assertStrings(t *testing.T, got, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("got %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %q, want %q", got, want)
		}
	}
}
