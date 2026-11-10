// Command classic-games is the command-line client for the Classic Games backend and the Mod DSL.
package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/yldm-tech/classic-games/apps/cli/internal/cli"
)

// version, commit and date are set at link time:
//
//	go build -ldflags "-X main.version=1.2.3 -X main.commit=$(git rev-parse --short HEAD) -X main.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" ./cmd/classic-games
var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

func main() {
	os.Exit(run())
}

// run owns the signal context so its cancel function runs before the process exits. The first interrupt cancels the context, which aborts the request in flight; it also restores the default signal behaviour, so a second interrupt ends the process even if something is still blocked.
func run() int {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	context.AfterFunc(ctx, stop)
	return cli.Run(ctx, os.Args[1:], cli.Options{
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Getenv: os.Getenv,
		Build:  cli.BuildInfo{Version: version, Commit: commit, Date: date},
	})
}
