// Command server starts the ForgePlay HTTP application.
package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"forgeplay/server/internal/app"
)

// @title        ForgePlay API
// @version      0.1
// @description  AI 驱动的小游戏创作社区后端(详见 docs/09-api-design.md)。
// @BasePath     /api/v1
func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := app.LoadConfig(os.LookupEnv)
	if err != nil {
		log.Fatalf("load configuration: %v", err)
	}
	log.Printf("config: %s", cfg)

	application, err := app.New(ctx, cfg, app.Options{})
	if err != nil {
		log.Fatalf("assemble application: %v", err)
	}
	defer func() {
		if err := application.Close(); err != nil {
			log.Printf("close application: %v", err)
		}
	}()

	if err := application.Run(ctx); err != nil {
		log.Fatalf("run application: %v", err)
	}
}
