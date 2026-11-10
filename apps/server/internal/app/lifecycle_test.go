package app

import (
	"context"
	"errors"
	"net/http"
	"sync"
	"testing"
	"time"
)

func TestRunShutsServerDownWhenContextIsCancelled(t *testing.T) {
	server := newFakeHTTPServer(http.ErrServerClosed)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, server, 2*time.Second) }()

	waitChannel(t, server.started, "server start")
	cancel()

	if err := waitValue(t, done, "server shutdown"); err != nil {
		t.Fatalf("Run: %v", err)
	}
	waitChannel(t, server.stopped, "Shutdown call")
	if !server.shutdownHadDeadline {
		t.Fatal("Shutdown context has no deadline")
	}
}

func TestRunReturnsListenError(t *testing.T) {
	want := errors.New("listen failed")
	server := newFakeHTTPServer(want)
	server.returnImmediately = true

	err := Run(context.Background(), server, time.Second)
	if !errors.Is(err, want) {
		t.Fatalf("Run error = %v, want %v", err, want)
	}
}

type fakeHTTPServer struct {
	started             chan struct{}
	stopped             chan struct{}
	listenErr           error
	returnImmediately   bool
	shutdownHadDeadline bool
	startOnce           sync.Once
	stopOnce            sync.Once
}

func newFakeHTTPServer(listenErr error) *fakeHTTPServer {
	return &fakeHTTPServer{
		started:   make(chan struct{}),
		stopped:   make(chan struct{}),
		listenErr: listenErr,
	}
}

func (s *fakeHTTPServer) ListenAndServe() error {
	s.startOnce.Do(func() { close(s.started) })
	if !s.returnImmediately {
		<-s.stopped
	}
	return s.listenErr
}

func (s *fakeHTTPServer) Shutdown(ctx context.Context) error {
	_, s.shutdownHadDeadline = ctx.Deadline()
	s.stopOnce.Do(func() { close(s.stopped) })
	return nil
}

func waitChannel(t *testing.T, channel <-chan struct{}, description string) {
	t.Helper()
	select {
	case <-channel:
	case <-t.Context().Done():
		t.Fatalf("test cancelled while waiting for %s", description)
	}
}

func waitValue[T any](t *testing.T, channel <-chan T, description string) T {
	t.Helper()
	select {
	case value := <-channel:
		return value
	case <-t.Context().Done():
		t.Fatalf("test cancelled while waiting for %s", description)
		var zero T
		return zero
	}
}
