// Command classic-games-mcp is a Model Context Protocol server that lets AI agents work with Classic Games: read and validate the Mod DSL offline, browse games, and fork, patch and publish mods through the backend API.
//
// The stdio transport owns stdout for protocol messages, so everything else (logs, usage, errors) goes to stderr.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"time"

	"github.com/yldm-tech/classic-games/apps/mcp/internal/config"
	"github.com/yldm-tech/classic-games/apps/mcp/internal/schemas"
	"github.com/yldm-tech/classic-games/apps/mcp/internal/server"
	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	version = "0.1.0"

	transportStdio = "stdio"
	transportHTTP  = "http"

	// defaultHTTPAddr binds the loopback interface only: the server acts with the configured token for whoever can reach it.
	defaultHTTPAddr = "127.0.0.1:8765"
	// httpPath is where the streamable HTTP transport is served.
	httpPath = "/mcp"

	idleSessionTimeout = 30 * time.Minute
	shutdownTimeout    = 3 * time.Second
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	err := run(ctx, os.Args[1:], os.Getenv, os.Stdout, os.Stderr)
	stop()
	if err != nil {
		fmt.Fprintln(os.Stderr, "classic-games-mcp:", err)
		os.Exit(1)
	}
}

// run parses the command line, builds the server and serves it until ctx is cancelled or, on stdio, the client disconnects.
func run(ctx context.Context, args []string, getenv func(string) string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet(server.Name, flag.ContinueOnError)
	flags.SetOutput(stderr)
	transport := flags.String("transport", transportStdio, "transport to serve: stdio or http")
	addr := flags.String("addr", defaultHTTPAddr, "listen address for --transport http")
	var allowedHosts hostList
	flags.Var(&allowedHosts, "allowed-host", "host name clients may use in the Host header to reach a non-loopback --addr, such as mcp.example.com; repeatable. The IP address a connection arrives on is always allowed")
	readOnly := flags.Bool("read-only", false, "do not expose tools that write to the backend or spend AI quota")
	showVersion := flags.Bool("version", false, "print the version and exit")
	flags.Usage = func() {
		fmt.Fprintf(stderr, "Usage: %s [--transport stdio|http] [--addr host:port] [--allowed-host name]... [--read-only]\n\nFlags:\n", server.Name)
		flags.PrintDefaults()
		fmt.Fprintf(stderr, "\nEnvironment:\n  %s  backend root URL (default %s)\n  %s       bearer token for the write tools (obtain with: classic-games auth login, then classic-games auth token)\n  %s  directory with the DSL JSON Schemas (default: packages/schemas found above the binary, then above the working directory)\n  %s        language of backend messages and titles: zh, en or ja (default: backend default)\n", config.EnvServerURL, config.DefaultServerURL, config.EnvToken, config.EnvSchemaDir, config.EnvLanguage)
	}
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() > 0 {
		return fmt.Errorf("unexpected argument %q; run with --help for usage", flags.Arg(0))
	}
	if *showVersion {
		fmt.Fprintln(stdout, server.Name, version)
		return nil
	}
	if *transport != transportStdio && *transport != transportHTTP {
		return fmt.Errorf("unknown --transport %q: use %s or %s", *transport, transportStdio, transportHTTP)
	}
	if len(allowedHosts) > 0 && *transport != transportHTTP {
		return fmt.Errorf("--allowed-host only applies to --transport %s", transportHTTP)
	}

	logger := slog.New(slog.NewTextHandler(stderr, nil))
	mcpServer, err := build(config.FromEnv(getenv), *readOnly, logger)
	if err != nil {
		return err
	}

	if *transport == transportHTTP {
		listener, err := net.Listen("tcp", *addr)
		if err != nil {
			return fmt.Errorf("listen on %s: %w", *addr, err)
		}
		return serveHTTP(ctx, listener, mcpServer, allowedHosts, logger)
	}
	logger.Info("serving", "transport", transportStdio)
	if err := mcpServer.Run(ctx, &mcp.StdioTransport{}); err != nil && !errors.Is(err, context.Canceled) {
		return err
	}
	return nil
}

// build wires the schema catalog and the backend client into an MCP server.
func build(cfg config.Config, readOnly bool, logger *slog.Logger) (*mcp.Server, error) {
	workingDir, _ := os.Getwd()
	executableDir := ""
	if executable, err := os.Executable(); err == nil {
		executableDir = filepath.Dir(executable)
	}
	// The directory of the binary comes first: a binary built into the repository must use the repository's schemas, not a packages/schemas directory of whatever project the client starts it in. The working directory is the fallback for `go run` and for a binary installed elsewhere.
	schemaDir, err := config.ResolveSchemaDir(cfg.SchemaDir, executableDir, workingDir)
	if err != nil {
		return nil, err
	}
	catalog, err := schemas.Open(schemaDir)
	if err != nil {
		return nil, err
	}
	backend, err := sdk.New(cfg.ServerURL, sdk.WithToken(cfg.Token), sdk.WithUserAgent(server.Name+"/"+version), sdk.WithLanguage(cfg.Language))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", config.EnvServerURL, err)
	}
	// Secrets are never logged: of the token only whether one is configured, and the backend URL without credentials it may carry.
	logger.Info("configured", "version", version, "backend", server.DisplayURL(backend.BaseURL()), "token", cfg.Token != "", "schema_dir", schemaDir, "runtimes", catalog.Refs(), "read_only", readOnly)
	return server.New(server.Options{Version: version, Catalog: catalog, Backend: backend, ReadOnly: readOnly, Logger: logger}), nil
}

// isLoopback reports whether addr is a TCP address on a loopback interface, the only kind of listener that other machines cannot reach.
func isLoopback(addr net.Addr) bool {
	tcpAddr, ok := addr.(*net.TCPAddr)
	return ok && tcpAddr.IP.IsLoopback()
}

// hostList is a repeatable string flag holding host names in the form hostOf returns: lower case, without a port.
type hostList []string

func (h *hostList) String() string { return strings.Join(*h, ",") }

func (h *hostList) Set(value string) error {
	value = strings.TrimSpace(value)
	// The raw value is checked before the port is cut off: in "http://host/path" everything after the first colon would otherwise pass for a port.
	if value == "" || strings.ContainsAny(value, "/ ") {
		return fmt.Errorf("want a host name such as mcp.example.com, without scheme or path")
	}
	*h = append(*h, hostOf(value))
	return nil
}

// hostOf returns the host part of a Host header value in lower case, without the port and without the brackets of an IPv6 literal.
func hostOf(hostHeader string) string {
	host := hostHeader
	if name, _, err := net.SplitHostPort(hostHeader); err == nil {
		host = name
	}
	return strings.ToLower(strings.Trim(host, "[]"))
}

// checkHost rejects requests whose Host header names something this server was not started for. It closes the gap the SDK leaves: the SDK refuses a foreign Host only on connections that arrive on a loopback address, so on any other address a web page could reach the server through DNS rebinding (its own domain, re-pointed at this machine, makes the browser treat the request as same-origin). A connection that arrives on a non-loopback address is served only when Host is the literal IP address it arrived on, which a rebinding page cannot use, or one of the names given with --allowed-host. Loopback connections are left to the SDK's check.
func checkHost(allowed []string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		local, _ := r.Context().Value(http.LocalAddrContextKey).(*net.TCPAddr)
		if local == nil || local.IP.IsLoopback() {
			next.ServeHTTP(w, r)
			return
		}
		host := hostOf(r.Host)
		if ip := net.ParseIP(host); (ip != nil && ip.Equal(local.IP)) || slices.Contains(allowed, host) {
			next.ServeHTTP(w, r)
			return
		}
		http.Error(w, fmt.Sprintf("Forbidden: Host %q is not served here; connect by IP address, or start %s with --allowed-host %s", r.Host, server.Name, host), http.StatusForbidden)
	})
}

// serveHTTP serves the streamable HTTP transport on listener at httpPath until ctx is cancelled. Every HTTP client shares the one configured backend token, so the listener should stay on a loopback address.
func serveHTTP(ctx context.Context, listener net.Listener, mcpServer *mcp.Server, allowedHosts []string, logger *slog.Logger) error {
	handler := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server { return mcpServer }, &mcp.StreamableHTTPOptions{Logger: logger, SessionTimeout: idleSessionTimeout})
	mux := http.NewServeMux()
	// Reject requests with a foreign Host header and cross-origin browser requests: a web page must not be able to drive a server that holds a token.
	mux.Handle(httpPath, checkHost(allowedHosts, http.NewCrossOriginProtection().Handler(handler)))
	httpServer := &http.Server{Handler: mux, ReadHeaderTimeout: 10 * time.Second}

	if !isLoopback(listener.Addr()) {
		logger.Warn("listening on a non-loopback address: anyone who can reach it can use this server, including its backend token. Requests are served only when their Host header is the IP address they arrive on or a name given with --allowed-host", "addr", listener.Addr().String(), "allowed_hosts", allowedHosts)
	}
	logger.Info("serving", "transport", transportHTTP, "url", "http://"+listener.Addr().String()+httpPath)

	served := make(chan error, 1)
	go func() { served <- httpServer.Serve(listener) }()
	select {
	case err := <-served:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		// Open event streams keep Shutdown waiting; close them once the grace period is over.
		_ = httpServer.Close()
	}
	<-served
	return nil
}
