package app

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/yldm-tech/classic-games/apps/server/internal/ai"
	"github.com/yldm-tech/classic-games/apps/server/internal/auth"
	"github.com/yldm-tech/classic-games/apps/server/internal/storage"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// OpenDatabase allows callers to replace the process-owned database connection.
type OpenDatabase func(dsn string) (*gorm.DB, error)

// Options contains optional infrastructure adapters for the composition root.
type Options struct {
	OpenDatabase OpenDatabase
	AIProvider   ai.LLMProvider
	CodeSender   auth.CodeSender
}

// App owns the assembled HTTP application and its process-scoped resources.
type App struct {
	cfg      Config
	engine   *gin.Engine
	server   *http.Server
	database *sql.DB

	closeOnce sync.Once
	closeErr  error
}

// New validates and assembles the complete application without starting it.
func New(ctx context.Context, cfg Config, options Options) (*App, error) {
	if ctx == nil {
		return nil, fmt.Errorf("app: context is required")
	}

	openDatabase := options.OpenDatabase
	if openDatabase == nil {
		openDatabase = storage.Open
	}
	db, err := openDatabase(cfg.Database.DSN)
	if err != nil {
		return nil, fmt.Errorf("app: open database: %w", err)
	}
	database, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("app: access database connection: %w", err)
	}
	cleanup := true
	defer func() {
		if cleanup {
			_ = database.Close()
		}
	}()

	if err := Migrate(db, DefaultMigrations()); err != nil {
		return nil, fmt.Errorf("app: migrate database: %w", err)
	}

	provider := options.AIProvider
	if provider == nil {
		provider = ai.StubProvider{}
		if cfg.AI.AnthropicKey != "" {
			provider = ai.NewClaudeProvider(cfg.AI.AnthropicKey, "")
		}
	}
	sender := options.CodeSender
	if sender == nil {
		sender = auth.NewLogSender()
		if cfg.Auth.SMSGatewayURL != "" {
			sender = auth.NewHTTPSender(cfg.Auth.SMSGatewayURL, cfg.Auth.SMSGatewayToken, 10*time.Second)
		}
	}

	engine, err := assembleModules(cfg, db, provider, sender)
	if err != nil {
		return nil, fmt.Errorf("app: assemble modules: %w", err)
	}
	server := &http.Server{
		Addr:              ":" + cfg.HTTP.Port,
		Handler:           engine,
		ReadHeaderTimeout: 10 * time.Second,
	}
	cleanup = false
	return &App{cfg: cfg, engine: engine, server: server, database: database}, nil
}

func (a *App) Handler() http.Handler {
	return a.engine
}

func (a *App) Routes() []gin.RouteInfo {
	return a.engine.Routes()
}

func (a *App) Run(ctx context.Context) error {
	return Run(ctx, a.server, a.cfg.HTTP.ShutdownTimeout)
}

func (a *App) Close() error {
	a.closeOnce.Do(func() {
		a.closeErr = a.database.Close()
	})
	return a.closeErr
}
