// Package app owns process configuration, dependency assembly, and lifecycle.
package app

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

type LookupEnv func(string) (string, bool)

type Environment string

const (
	Development Environment = "development"
	Production  Environment = "production"
)

type Config struct {
	Environment Environment
	HTTP        HTTPConfig
	Database    DatabaseConfig
	Content     ContentConfig
	AI          AIConfig
	Security    SecurityConfig
	Auth        AuthConfig
	Moderation  ModerationConfig
	Payments    PaymentsConfig
}

type HTTPConfig struct {
	Port            string
	TrustedProxies  []string
	MaxBodyBytes    int64
	ShutdownTimeout time.Duration
	HSTS            bool
}

type DatabaseConfig struct {
	DSN string
}

type ContentConfig struct {
	SchemaDir            string
	RuntimeDir           string
	ShooterBaseline      string
	SurvivorBaseline     string
	TowerDefenseBaseline string
}

type AIConfig struct {
	AnthropicKey string
}

type SecurityConfig struct {
	Secret string
}

type AuthConfig struct {
	SMSGatewayURL   string
	SMSGatewayToken string
	OAuthProviders  map[string]OAuthProviderConfig
	AdminIDs        []string
	DevAdmin        bool
}

type OAuthProviderConfig struct {
	URL         string
	BearerToken string
}

type ModerationConfig struct {
	BlockWordsFile string
	URL            string
	Token          string
}

type PaymentsConfig struct {
	WebhookSecret string
}

func LoadConfig(lookup LookupEnv) (Config, error) {
	if lookup == nil {
		return Config{}, fmt.Errorf("config: environment lookup is required")
	}

	get := func(key, fallback string) string {
		if value, ok := lookup(key); ok && value != "" {
			return value
		}
		return fallback
	}

	environment := Environment(get("FORGEPLAY_ENV", string(Development)))
	if environment != Development && environment != Production {
		return Config{}, fmt.Errorf("config: unsupported FORGEPLAY_ENV %q", environment)
	}

	shutdownTimeout, err := time.ParseDuration(get("FORGEPLAY_SHUTDOWN_TIMEOUT", "10s"))
	if err != nil || shutdownTimeout <= 0 {
		return Config{}, fmt.Errorf("config: FORGEPLAY_SHUTDOWN_TIMEOUT must be positive duration")
	}
	maxBodyBytes, err := strconv.ParseInt(get("FORGEPLAY_MAX_BODY_BYTES", strconv.FormatInt(1<<20, 10)), 10, 64)
	if err != nil || maxBodyBytes <= 0 {
		return Config{}, fmt.Errorf("config: FORGEPLAY_MAX_BODY_BYTES must be a positive integer")
	}
	devAdmin, err := strconv.ParseBool(get("FORGEPLAY_DEV_ADMIN", "false"))
	if err != nil {
		return Config{}, fmt.Errorf("config: FORGEPLAY_DEV_ADMIN must be boolean: %w", err)
	}
	if environment == Production && devAdmin {
		return Config{}, fmt.Errorf("config: FORGEPLAY_DEV_ADMIN cannot be enabled in production")
	}
	secret := get("FORGEPLAY_SECRET", "")
	if environment == Production && len(secret) < 32 {
		return Config{}, fmt.Errorf("config: FORGEPLAY_SECRET must be at least 32 characters in production")
	}
	dsn := get("FORGEPLAY_DB", "")
	if environment == Production && dsn == "" {
		return Config{}, fmt.Errorf("config: FORGEPLAY_DB must be set in production")
	}
	if dsn == "" {
		dsn = "forgeplay.db"
	}

	oauthProviders := make(map[string]OAuthProviderConfig)
	for _, provider := range []string{"WECHAT", "QQ", "APPLE", "GOOGLE", "DISCORD", "LINE"} {
		if url := get("OAUTH_"+provider+"_VERIFY_URL", ""); url != "" {
			oauthProviders[strings.ToLower(provider)] = OAuthProviderConfig{
				URL:         url,
				BearerToken: get("OAUTH_"+provider+"_VERIFY_TOKEN", ""),
			}
		}
	}
	if environment == Production {
		for name, provider := range oauthProviders {
			if err := requireHTTPS("OAUTH_"+strings.ToUpper(name)+"_VERIFY_URL", provider.URL); err != nil {
				return Config{}, err
			}
		}
		if err := requireHTTPS("SMS_GATEWAY_URL", get("SMS_GATEWAY_URL", "")); err != nil {
			return Config{}, err
		}
		if err := requireHTTPS("CONTENT_MODERATION_URL", get("CONTENT_MODERATION_URL", "")); err != nil {
			return Config{}, err
		}
	}

	return Config{
		Environment: environment,
		HTTP: HTTPConfig{
			Port:            get("PORT", "8080"),
			TrustedProxies:  splitUnique(get("FORGEPLAY_TRUSTED_PROXIES", "")),
			MaxBodyBytes:    maxBodyBytes,
			ShutdownTimeout: shutdownTimeout,
			HSTS:            environment == Production,
		},
		Database: DatabaseConfig{DSN: dsn},
		Content: ContentConfig{
			SchemaDir:            get("FORGEPLAY_SCHEMA_DIR", "../../packages/schemas"),
			RuntimeDir:           get("FORGEPLAY_RUNTIME_DIR", "../client/runtime"),
			ShooterBaseline:      get("FORGEPLAY_BASELINE", "../client/runtime/shooter/baseline.dsl.json"),
			SurvivorBaseline:     get("FORGEPLAY_SURVIVOR_BASELINE", "../client/runtime/survivor/baseline.dsl.json"),
			TowerDefenseBaseline: get("FORGEPLAY_TOWER_DEFENSE_BASELINE", "../client/runtime/tower_defense/baseline.dsl.json"),
		},
		AI:       AIConfig{AnthropicKey: get("ANTHROPIC_API_KEY", "")},
		Security: SecurityConfig{Secret: secret},
		Auth: AuthConfig{
			SMSGatewayURL:   get("SMS_GATEWAY_URL", ""),
			SMSGatewayToken: get("SMS_GATEWAY_TOKEN", ""),
			OAuthProviders:  oauthProviders,
			AdminIDs:        splitUnique(get("FORGEPLAY_ADMIN_IDS", "")),
			DevAdmin:        devAdmin,
		},
		Moderation: ModerationConfig{
			BlockWordsFile: get("FORGEPLAY_BLOCK_WORDS_FILE", ""),
			URL:            get("CONTENT_MODERATION_URL", ""),
			Token:          get("CONTENT_MODERATION_TOKEN", ""),
		},
		Payments: PaymentsConfig{WebhookSecret: get("PAYMENT_WEBHOOK_SECRET", "")},
	}, nil
}

// PublicCapabilities is the non-secret surface clients can show in About/Settings.
// It never includes tokens, secrets, admin IDs, or gateway URLs.
func (c Config) PublicCapabilities() map[string]any {
	providers := make([]string, 0, len(c.Auth.OAuthProviders))
	for name := range c.Auth.OAuthProviders {
		providers = append(providers, name)
	}
	sort.Strings(providers)
	aiMode := "stub"
	if c.AI.AnthropicKey != "" {
		aiMode = "live"
	}
	return map[string]any{
		"environment":      string(c.Environment),
		"ai":               map[string]any{"mode": aiMode},
		"sms":              c.Auth.SMSGatewayURL != "" && c.Auth.SMSGatewayToken != "",
		"oauth_providers":  providers,
		"payments":         c.Payments.WebhookSecret != "",
		"admin_configured": len(c.Auth.AdminIDs) > 0 || c.Auth.DevAdmin,
		"moderation":       c.Moderation.URL != "",
	}
}

// databaseForLog returns the FORGEPLAY_DB value in a form that is safe to log. The value is meant to be a SQLite file path, which is shown without its query parameters. A value that looks like the connection string of another database (a URL whose scheme is not "file", or keyword=value pairs) can carry a password, and the configuration is logged before the database is opened, so such a value is replaced as a whole.
func databaseForLog(dsn string) string {
	path, _, _ := strings.Cut(dsn, "?")
	if (strings.Contains(path, "://") && !strings.HasPrefix(path, "file:")) || strings.ContainsAny(path, "=@") {
		return "(redacted: not a SQLite file path)"
	}
	return path
}

func (c Config) String() string {
	return fmt.Sprintf(
		"environment=%s production=%t port=%s database=%s schema=%s runtime=%s trusted_proxies=%d ai=%t sms=%t moderation=%t payments=%t",
		c.Environment,
		c.Environment == Production,
		c.HTTP.Port,
		databaseForLog(c.Database.DSN),
		c.Content.SchemaDir,
		c.Content.RuntimeDir,
		len(c.HTTP.TrustedProxies),
		c.AI.AnthropicKey != "",
		c.Auth.SMSGatewayURL != "",
		c.Moderation.URL != "",
		c.Payments.WebhookSecret != "",
	)
}

func requireHTTPS(name, url string) error {
	if url == "" {
		return nil
	}
	if strings.HasPrefix(url, "https://") {
		return nil
	}
	return fmt.Errorf("config: %s must use https in production", name)
}

func splitUnique(raw string) []string {
	seen := make(map[string]struct{})
	values := make([]string, 0)
	for _, item := range strings.Split(raw, ",") {
		value := strings.TrimSpace(item)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		values = append(values, value)
	}
	return values
}
