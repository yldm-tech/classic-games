package server_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/yldm-tech/classic-games/apps/mcp/internal/schemas"
	"github.com/yldm-tech/classic-games/apps/mcp/internal/server"
	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const testVersion = "9.9.9-test"

// repoRoot is the repository root, four levels above this package (apps/mcp/internal/server).
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Join(filepath.Dir(file), "..", "..", "..", "..")
}

// schemaDir is the real schema directory of the repository.
func schemaDir(t *testing.T) string {
	t.Helper()
	return filepath.Join(repoRoot(t), "packages", "schemas")
}

// baseline loads the real baseline DSL of a runtime from the client tree.
func baseline(t *testing.T, name string) map[string]any {
	t.Helper()
	content, err := os.ReadFile(filepath.Join(repoRoot(t), "apps", "client", "runtime", name, "baseline.dsl.json"))
	if err != nil {
		t.Fatalf("read %s baseline: %v", name, err)
	}
	var document map[string]any
	if err := json.Unmarshal(content, &document); err != nil {
		t.Fatalf("decode %s baseline: %v", name, err)
	}
	return document
}

// session describes how to build the server under test.
type session struct {
	backendURL string
	token      string
	readOnly   bool
}

// connect builds a server from the real schema catalog and connects a real MCP client session to it over the in-memory transport.
func connect(t *testing.T, cfg session) *mcp.ClientSession {
	t.Helper()
	catalog, err := schemas.Open(schemaDir(t))
	if err != nil {
		t.Fatalf("open schema catalog: %v", err)
	}
	if cfg.backendURL == "" {
		// Nothing listens on the discard port, so a test that reaches the backend unexpectedly fails fast.
		cfg.backendURL = "http://127.0.0.1:9"
	}
	backend, err := sdk.New(cfg.backendURL, sdk.WithToken(cfg.token))
	if err != nil {
		t.Fatalf("sdk.New: %v", err)
	}
	mcpServer := server.New(server.Options{Version: testVersion, Catalog: catalog, Backend: backend, ReadOnly: cfg.readOnly})

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	serverTransport, clientTransport := mcp.NewInMemoryTransports()
	serverSession, err := mcpServer.Connect(ctx, serverTransport, nil)
	if err != nil {
		t.Fatalf("server connect: %v", err)
	}
	client := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "1.0.0"}, nil)
	clientSession, err := client.Connect(ctx, clientTransport, nil)
	if err != nil {
		t.Fatalf("client connect: %v", err)
	}
	t.Cleanup(func() {
		_ = clientSession.Close()
		_ = serverSession.Wait()
	})
	return clientSession
}

// callTool calls a tool and fails the test on a protocol error, which tools must never produce for bad input.
func callTool(t *testing.T, cs *mcp.ClientSession, name string, arguments any) *mcp.CallToolResult {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	result, err := cs.CallTool(ctx, &mcp.CallToolParams{Name: name, Arguments: arguments})
	if err != nil {
		t.Fatalf("%s: protocol error: %v", name, err)
	}
	return result
}

// text joins the text content blocks of a result.
func text(result *mcp.CallToolResult) string {
	var parts []string
	for _, content := range result.Content {
		if block, ok := content.(*mcp.TextContent); ok {
			parts = append(parts, block.Text)
		}
	}
	return strings.Join(parts, "\n")
}

// call calls a tool that must succeed and decodes its structured content into Out.
func call[Out any](t *testing.T, cs *mcp.ClientSession, name string, arguments any) Out {
	t.Helper()
	result := callTool(t, cs, name, arguments)
	if result.IsError {
		t.Fatalf("%s: unexpected tool error: %s", name, text(result))
	}
	if result.StructuredContent == nil {
		t.Fatalf("%s: no structured content", name)
	}
	encoded, err := json.Marshal(result.StructuredContent)
	if err != nil {
		t.Fatalf("%s: encode structured content: %v", name, err)
	}
	// The text block must carry the same JSON for clients that ignore structured content.
	var fromText, fromStructured any
	if err := json.Unmarshal([]byte(text(result)), &fromText); err != nil {
		t.Fatalf("%s: text content is not JSON: %v", name, err)
	}
	_ = json.Unmarshal(encoded, &fromStructured)
	if !jsonEqual(fromText, fromStructured) {
		t.Fatalf("%s: text content and structured content differ", name)
	}
	var out Out
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&out); err != nil {
		t.Fatalf("%s: decode structured content into %T: %v\n%s", name, out, err, encoded)
	}
	return out
}

// callError calls a tool that must fail with a tool error (isError) and returns the error text.
func callError(t *testing.T, cs *mcp.ClientSession, name string, arguments any) string {
	t.Helper()
	result := callTool(t, cs, name, arguments)
	if !result.IsError {
		t.Fatalf("%s: expected a tool error, got: %s", name, text(result))
	}
	message := text(result)
	if message == "" {
		t.Fatalf("%s: tool error without a message", name)
	}
	return message
}

func jsonEqual(a, b any) bool {
	encodedA, _ := json.Marshal(a)
	encodedB, _ := json.Marshal(b)
	return string(encodedA) == string(encodedB)
}

// mustContain fails unless every fragment occurs in message.
func mustContain(t *testing.T, message string, fragments ...string) {
	t.Helper()
	for _, fragment := range fragments {
		if !strings.Contains(message, fragment) {
			t.Errorf("message %q does not contain %q", message, fragment)
		}
	}
}

// Output shapes as a client sees them. Decoding is strict, so a field added to or removed from a tool output fails the tests until it is reflected here.

type patchOp struct {
	Op    string `json:"op"`
	Path  string `json:"path"`
	Value any    `json:"value,omitempty"`
}

type violation struct {
	Path    string `json:"path"`
	Message string `json:"message"`
}

type validationOut struct {
	Runtime        string      `json:"runtime"`
	MigratedFrom   string      `json:"migrated_from"`
	Valid          bool        `json:"valid"`
	ViolationCount int         `json:"violation_count"`
	Violations     []violation `json:"violations"`
}

type patchedOut struct {
	validationOut
	DSL map[string]any `json:"dsl"`
}

type modOut struct {
	ModID        string         `json:"mod_id"`
	ParentModID  string         `json:"parent_mod_id"`
	Runtime      string         `json:"runtime"`
	Draft        bool           `json:"draft"`
	AIGenerated  bool           `json:"ai_generated"`
	PatchOpCount int            `json:"patch_op_count"`
	CreatedAt    string         `json:"created_at"`
	ForkedFrom   string         `json:"forked_from,omitempty"`
	DSL          map[string]any `json:"dsl,omitempty"`
}

type gameOut struct {
	GameID      string   `json:"game_id"`
	Title       string   `json:"title"`
	Summary     string   `json:"summary"`
	Author      string   `json:"author"`
	Runtime     string   `json:"runtime"`
	Category    string   `json:"category"`
	Tags        []string `json:"tags"`
	AIGenerated bool     `json:"ai_generated"`
	Likes       int      `json:"likes"`
	Plays       int      `json:"plays"`
	Forks       int      `json:"forks"`
	Status      string   `json:"status,omitempty"`
	ModID       string   `json:"mod_id,omitempty"`
	AuthorID    string   `json:"author_id,omitempty"`
	ForkedFrom  string   `json:"forked_from,omitempty"`
	Views       int      `json:"views,omitempty"`
	CreatedAt   string   `json:"created_at,omitempty"`
}

type dslOut struct {
	GameID  string         `json:"game_id,omitempty"`
	ModID   string         `json:"mod_id,omitempty"`
	Runtime string         `json:"runtime"`
	DSL     map[string]any `json:"dsl"`
}

// at walks a decoded JSON document along keys and returns the value found there.
func at(t *testing.T, document map[string]any, keys ...string) any {
	t.Helper()
	var current any = document
	for _, key := range keys {
		object, ok := current.(map[string]any)
		if !ok {
			t.Fatalf("path %v: %q is not inside an object", keys, key)
		}
		current, ok = object[key]
		if !ok {
			t.Fatalf("path %v: key %q is missing", keys, key)
		}
	}
	return current
}
