package app

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"
)

type HTTPServer interface {
	ListenAndServe() error
	Shutdown(context.Context) error
}

func Run(ctx context.Context, server HTTPServer, shutdownTimeout time.Duration) error {
	if ctx == nil {
		return fmt.Errorf("http lifecycle: context is required")
	}
	if server == nil {
		return fmt.Errorf("http lifecycle: server is required")
	}
	if shutdownTimeout <= 0 {
		return fmt.Errorf("http lifecycle: shutdown timeout must be positive")
	}

	serveErr := make(chan error, 1)
	go func() {
		serveErr <- server.ListenAndServe()
	}()

	select {
	case err := <-serveErr:
		return normalizeServeError(err)
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("http lifecycle: shutdown: %w", err)
		}
		return normalizeServeError(<-serveErr)
	}
}

func normalizeServeError(err error) error {
	if err == nil || errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return fmt.Errorf("http lifecycle: serve: %w", err)
}
