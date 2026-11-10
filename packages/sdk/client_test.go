package sdk_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"forgeplay/sdk"
)

func TestNewValidatesBaseURL(t *testing.T) {
	cases := []struct {
		name    string
		baseURL string
		want    string // expected BaseURL(); empty means New must fail
	}{
		{name: "plain", baseURL: "http://localhost:8080", want: "http://localhost:8080"},
		{name: "trailing slash trimmed", baseURL: "http://localhost:8080/", want: "http://localhost:8080"},
		{name: "surrounding space trimmed", baseURL: "  https://api.example.com  ", want: "https://api.example.com"},
		{name: "path prefix kept", baseURL: "https://example.com/forgeplay/", want: "https://example.com/forgeplay"},
		{name: "empty", baseURL: ""},
		{name: "no scheme", baseURL: "localhost:8080"},
		{name: "unsupported scheme", baseURL: "ftp://example.com"},
		{name: "no host", baseURL: "http://"},
		{name: "query not allowed", baseURL: "http://example.com?x=1"},
		{name: "fragment not allowed", baseURL: "http://example.com#top"},
		{name: "unparsable", baseURL: "http://exa mple.com"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, err := sdk.New(tc.baseURL)
			if tc.want == "" {
				if err == nil {
					t.Fatalf("New(%q) succeeded with base %q, want an error", tc.baseURL, client.BaseURL())
				}
				return
			}
			if err != nil {
				t.Fatalf("New(%q): %v", tc.baseURL, err)
			}
			if got := client.BaseURL(); got != tc.want {
				t.Errorf("BaseURL: got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestBaseURLPathPrefixIsKept(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"ok":true,"id":"g1"}`)
	client := newClient(t, server.URL+"/forgeplay/")

	if err := client.Health(context.Background()); err != nil {
		t.Fatalf("Health: %v", err)
	}
	if _, err := client.GetGame(context.Background(), "g1"); err != nil {
		t.Fatalf("GetGame: %v", err)
	}
	got := []string{seen()[0].path, seen()[1].path}
	want := []string{"/forgeplay/healthz", "/forgeplay/api/v1/games/g1"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("paths: got %v, want %v", got, want)
	}
}

func TestDefaultHeadersWithoutOptions(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"environment":"development"}`)
	client := newClient(t, server.URL)

	if _, err := client.Meta(context.Background()); err != nil {
		t.Fatalf("Meta: %v", err)
	}
	header := seen()[0].header
	if _, present := header["Authorization"]; present {
		t.Errorf("Authorization header: got %q, want none for an anonymous client", header.Get("Authorization"))
	}
	if got, want := header.Get("User-Agent"), "forgeplay-sdk-go/"+sdk.Version; got != want {
		t.Errorf("User-Agent header: got %q, want %q", got, want)
	}
}

func TestSetTokenChangesCredentials(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"id":"u1","nickname":"n"}`)
	client := newClient(t, server.URL, sdk.WithToken("first"))
	ctx := context.Background()

	if got := client.Token(); got != "first" {
		t.Fatalf("Token: got %q, want %q", got, "first")
	}
	if _, err := client.CurrentUser(ctx); err != nil {
		t.Fatalf("CurrentUser: %v", err)
	}
	client.SetToken("second")
	if _, err := client.CurrentUser(ctx); err != nil {
		t.Fatalf("CurrentUser: %v", err)
	}
	client.SetToken("")
	if _, err := client.CurrentUser(ctx); err != nil {
		t.Fatalf("CurrentUser: %v", err)
	}

	var got []string
	for _, request := range seen() {
		got = append(got, request.header.Get("Authorization"))
	}
	want := []string{"Bearer first", "Bearer second", ""}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Authorization headers: got %q, want %q", got, want)
	}
}

// TestLoginDoesNotChangeClientToken pins the contract that only SetToken changes credentials.
func TestLoginDoesNotChangeClientToken(t *testing.T) {
	server, _ := fakeBackend(t, 200, `{"token":"issued","user":{"id":"u1","nickname":"n"}}`)
	client := newClient(t, server.URL, sdk.WithToken("original"))
	ctx := context.Background()

	if _, err := client.LoginGuest(ctx); err != nil {
		t.Fatalf("LoginGuest: %v", err)
	}
	if _, err := client.RefreshToken(ctx); err != nil {
		t.Fatalf("RefreshToken: %v", err)
	}
	if err := client.Logout(ctx); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	if got := client.Token(); got != "original" {
		t.Errorf("Token after login, refresh and logout: got %q, want %q", got, "original")
	}
}

func TestLoginWithoutTokenInResponseFails(t *testing.T) {
	server, _ := fakeBackend(t, 200, `{"user":{"id":"u1","nickname":"n"}}`)
	client := newClient(t, server.URL)
	ctx := context.Background()

	if session, err := client.LoginGuest(ctx); err == nil {
		t.Errorf("LoginGuest: got session %#v, want an error for a response without token", session)
	}
	if token, err := client.RefreshToken(ctx); err == nil {
		t.Errorf("RefreshToken: got %q, want an error for a response without token", token)
	}
}

func TestHealthReportsNotOK(t *testing.T) {
	server, _ := fakeBackend(t, 200, `{"ok":false}`)
	client := newClient(t, server.URL)
	if err := client.Health(context.Background()); err == nil {
		t.Fatal("Health: got nil, want an error when the backend reports ok=false")
	}
}

func TestWithLanguage(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"items":[]}`)
	client := newClient(t, server.URL, sdk.WithLanguage("ja"))
	ctx := context.Background()

	if _, err := client.ListGames(ctx, sdk.ListGamesParams{}); err != nil {
		t.Fatalf("ListGames: %v", err)
	}
	if _, err := client.GetRanking(ctx, sdk.RankingParams{Type: sdk.SortNew}); err != nil {
		t.Fatalf("GetRanking: %v", err)
	}
	if _, err := client.ListUserGames(ctx, "u1", sdk.UserGamesForks); err != nil {
		t.Fatalf("ListUserGames: %v", err)
	}

	for i, request := range seen() {
		if got := request.header.Get("Accept-Language"); got != "ja" {
			t.Errorf("request %d Accept-Language: got %q, want %q", i, got, "ja")
		}
	}
	// ListGames honours Accept-Language on the backend, so the query string stays clean.
	if got := seen()[0].query.Encode(); got != "" {
		t.Errorf("ListGames query: got %q, want empty", got)
	}
	// Ranking and a user's games only read ?lang= on the backend.
	if got, want := seen()[1].query.Encode(), "lang=ja&type=new"; got != want {
		t.Errorf("GetRanking query: got %q, want %q", got, want)
	}
	if got, want := seen()[2].query.Encode(), "lang=ja&type=forks"; got != want {
		t.Errorf("ListUserGames query: got %q, want %q", got, want)
	}
}

type countingTransport struct {
	calls atomic.Int32
	next  http.RoundTripper
}

func (t *countingTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	t.calls.Add(1)
	return t.next.RoundTrip(request)
}

func TestWithHTTPClientIsUsed(t *testing.T) {
	server, _ := fakeBackend(t, 200, `{"ok":true}`)
	transport := &countingTransport{next: http.DefaultTransport}
	client := newClient(t, server.URL, sdk.WithHTTPClient(&http.Client{Transport: transport}), sdk.WithHTTPClient(nil))

	if err := client.Health(context.Background()); err != nil {
		t.Fatalf("Health: %v", err)
	}
	if got := transport.calls.Load(); got != 1 {
		t.Errorf("injected transport calls: got %d, want 1", got)
	}
}

func TestPathSegmentsAreEscaped(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"items":[]}`)
	client := newClient(t, server.URL)
	ctx := context.Background()

	if _, err := client.ListComments(ctx, "a?c#d e", sdk.PageParams{}); err != nil {
		t.Fatalf("ListComments: %v", err)
	}
	if _, err := client.GetReplayLeaderboard(ctx, "g?x=1&y=2"); err != nil {
		t.Fatalf("GetReplayLeaderboard: %v", err)
	}

	want := []string{
		"/api/v1/games/a%3Fc%23d%20e/comments",
		"/api/v1/games/g%3Fx=1&y=2/replays/leaderboard",
	}
	if len(seen()) != len(want) {
		t.Fatalf("backend saw %d requests, want %d", len(seen()), len(want))
	}
	for i, request := range seen() {
		if request.path != want[i] {
			t.Errorf("request %d path: got %s, want %s", i, request.path, want[i])
		}
		if len(request.query) != 0 {
			t.Errorf("request %d query: got %v, want none (the id must not leak into the query string)", i, request.query)
		}
	}
}

// decodedRouter answers like the gin backend does: it routes on the decoded path, so an escaped slash in an id is a path separator again. It serves the two collisions the SDK has to survive: /games/{id}/comments and the fixed route /games/mine.
func decodedRouter(t *testing.T) (*httptest.Server, func() []string) {
	t.Helper()
	var mu sync.Mutex
	var paths []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		paths = append(paths, r.Method+" "+r.URL.Path)
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/v1/"), "/")
		switch {
		case len(parts) == 2 && parts[0] == "games" && parts[1] == "mine":
			_, _ = io.WriteString(w, `{"items":[]}`)
		case len(parts) == 2 && parts[0] == "games":
			_, _ = fmt.Fprintf(w, `{"id":%q,"title":"A game"}`, parts[1])
		case len(parts) == 3 && parts[0] == "games" && parts[2] == "comments":
			_, _ = io.WriteString(w, `{"items":[],"next_cursor":""}`)
		case len(parts) == 2 && parts[0] == "users" && parts[1] == "me":
			_, _ = io.WriteString(w, `{"id":"u_42","nickname":"Signed in"}`)
		case len(parts) == 2 && parts[0] == "users":
			_, _ = fmt.Fprintf(w, `{"id":%q,"name":%q,"level":1}`, parts[1], parts[1])
		case len(parts) == 4 && parts[0] == "games" && parts[2] == "replays" && parts[3] == "leaderboard":
			_, _ = io.WriteString(w, `{"items":[]}`)
		case len(parts) == 3 && parts[0] == "mods" && parts[2] == "fork-tree":
			_, _ = io.WriteString(w, `{"ancestors":[],"node":{"id":"mod_other","runtime":"shooter@1.0.0","patch":[]},"children":[]}`)
		default:
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"error":{"code":"NOT_FOUND","message":"not found"}}`)
		}
	}))
	t.Cleanup(server.Close)
	return server, func() []string {
		mu.Lock()
		defer mu.Unlock()
		return slices.Clone(paths)
	}
}

// An id with a slash or a dot segment would address another route once the backend decodes the path, so it is refused before any request is sent.
func TestIDsThatChangeTheRouteAreRejected(t *testing.T) {
	server, seen := decodedRouter(t)
	client := newClient(t, server.URL)
	ctx := context.Background()

	calls := map[string]func() error{
		"GetGame slash":           func() error { _, err := client.GetGame(ctx, "a/b"); return err },
		"GetGame comments":        func() error { _, err := client.GetGame(ctx, "g1/comments"); return err },
		"GetGameDSL slash":        func() error { _, err := client.GetGameDSL(ctx, "g1/dsl"); return err },
		"DelistGame slash":        func() error { _, err := client.DelistGame(ctx, "g1/like"); return err },
		"GetLatestReplay slash":   func() error { _, err := client.GetLatestReplay(ctx, "g/1", "../admin"); return err },
		"GetLatestReplay dotdot":  func() error { _, err := client.GetLatestReplay(ctx, "g1", ".."); return err },
		"GetRuntimeSchema slash":  func() error { _, err := client.GetRuntimeSchema(ctx, "shooter/..", "1.0.0"); return err },
		"GetRuntimeSchema dot":    func() error { _, err := client.GetRuntimeSchema(ctx, ".", "1.0.0"); return err },
		"GetUserProfile dotdot":   func() error { _, err := client.GetUserProfile(ctx, ".."); return err },
		"SaveDraft slash":         func() error { _, err := client.SaveDraft(ctx, "d1/publish", nil); return err },
		"GetMod lower-case slash": func() error { _, err := client.GetMod(ctx, "m1/x"); return err },
	}
	for name, call := range calls {
		err := call()
		if err == nil {
			t.Errorf("%s: got nil, want an error", name)
			continue
		}
		var apiErr *sdk.APIError
		if errors.As(err, &apiErr) {
			t.Errorf("%s: got *sdk.APIError %v, want a local error raised before any request", name, err)
		}
		if !strings.Contains(err.Error(), "invalid path parameter") || !errors.Is(err, sdk.ErrInvalidArgument) {
			t.Errorf("%s: error %q does not name the cause or is not ErrInvalidArgument", name, err)
		}
	}
	if got := seen(); len(got) != 0 {
		t.Errorf("backend saw %v, want no request", got)
	}

	// Dots inside a longer segment are ordinary characters.
	if _, err := client.GetGame(ctx, "v1.0..final"); err != nil {
		t.Errorf("GetGame with dots inside the id: %v", err)
	}
}

// An id that equals a fixed route of the backend gets a 200 that is not the resource. The getters report it as not found instead of returning a zero value.
func TestReservedWordIDsAreNotFound(t *testing.T) {
	server, seen := decodedRouter(t)
	client := newClient(t, server.URL)
	ctx := context.Background()

	calls := map[string]func() (any, error){
		"GetGame mine":                func() (any, error) { return client.GetGame(ctx, "mine") },
		"GetUserProfile me":           func() (any, error) { return client.GetUserProfile(ctx, "me") },
		"GetLatestReplay leaderboard": func() (any, error) { return client.GetLatestReplay(ctx, "g1", "leaderboard") },
		"GetMod other node":           func() (any, error) { return client.GetMod(ctx, "mine") },
		"GetModForkTree other node":   func() (any, error) { return client.GetModForkTree(ctx, "mine") },
	}
	for name, call := range calls {
		value, err := call()
		if !sdk.IsNotFound(err) || !sdk.IsCode(err, sdk.CodeNotFound) {
			t.Errorf("%s: got %v, want 404 NOT_FOUND", name, err)
		}
		if !reflect.ValueOf(value).IsNil() {
			t.Errorf("%s: got %#v next to the error, want nil", name, value)
		}
	}
	if got := len(seen()); got != len(calls) {
		t.Errorf("backend saw %d requests, want %d", got, len(calls))
	}

	// The same getters still return real resources.
	if game, err := client.GetGame(ctx, "g1"); err != nil || game.ID != "g1" {
		t.Errorf("GetGame(g1): got %#v, %v", game, err)
	}
	if profile, err := client.GetUserProfile(ctx, "@nobody"); err != nil || profile.ID != "@nobody" {
		t.Errorf("GetUserProfile(@nobody): got %#v, %v", profile, err)
	}
}

func TestAPIErrorMapping(t *testing.T) {
	cases := []struct {
		name        string
		status      int
		contentType string
		body        string
		want        sdk.APIError
		wantText    string
	}{
		{
			name: "envelope", status: 404, contentType: "application/json",
			body:     `{"error":{"code":"NOT_FOUND","message":"The requested resource was not found"}}`,
			want:     sdk.APIError{StatusCode: 404, Code: sdk.CodeNotFound, Message: "The requested resource was not found"},
			wantText: "forgeplay: GET /api/v1/games/g1: 404 NOT_FOUND: The requested resource was not found",
		},
		{
			name: "envelope with details", status: 422, contentType: "application/json",
			body:     `{"error":{"code":"DSL_INVALID","message":"DSL 不合法","details":{"detail":"/player/speed: must be >= 0"}}}`,
			want:     sdk.APIError{StatusCode: 422, Code: sdk.CodeDSLInvalid, Message: "DSL 不合法", Details: map[string]any{"detail": "/player/speed: must be >= 0"}},
			wantText: "forgeplay: GET /api/v1/games/g1: 422 DSL_INVALID: DSL 不合法",
		},
		{
			name: "quota exceeded", status: 429, contentType: "application/json",
			body:     `{"error":{"code":"QUOTA_EXCEEDED","message":"Daily AI quota exhausted"}}`,
			want:     sdk.APIError{StatusCode: 429, Code: sdk.CodeQuotaExceeded, Message: "Daily AI quota exhausted"},
			wantText: "forgeplay: GET /api/v1/games/g1: 429 QUOTA_EXCEEDED: Daily AI quota exhausted",
		},
		{
			name: "envelope without message", status: 401, contentType: "application/json",
			body:     `{"error":{"code":"AUTH_REQUIRED","message":""}}`,
			want:     sdk.APIError{StatusCode: 401, Code: sdk.CodeAuthRequired},
			wantText: "forgeplay: GET /api/v1/games/g1: 401 AUTH_REQUIRED",
		},
		{
			name: "plain text from router", status: 404, contentType: "text/plain",
			body:     "404 page not found\n",
			want:     sdk.APIError{StatusCode: 404, Message: "404 page not found"},
			wantText: "forgeplay: GET /api/v1/games/g1: 404 Not Found: 404 page not found",
		},
		{
			name: "html from proxy", status: 502, contentType: "text/html",
			body:     "<html>bad gateway</html>",
			want:     sdk.APIError{StatusCode: 502, Message: "<html>bad gateway</html>"},
			wantText: "forgeplay: GET /api/v1/games/g1: 502 Bad Gateway: <html>bad gateway</html>",
		},
		{
			name: "long page from proxy is cut", status: 502, contentType: "text/html",
			body:     strings.Repeat("x", 510) + "é" + strings.Repeat("y", 300_000),
			want:     sdk.APIError{StatusCode: 502, Message: strings.Repeat("x", 510) + "é ... (300000 more bytes)"},
			wantText: "forgeplay: GET /api/v1/games/g1: 502 Bad Gateway: " + strings.Repeat("x", 510) + "é ... (300000 more bytes)",
		},
		{
			name: "long page is cut on a rune boundary", status: 502, contentType: "text/html",
			body:     strings.Repeat("x", 511) + "é" + strings.Repeat("y", 100),
			want:     sdk.APIError{StatusCode: 502, Message: strings.Repeat("x", 511) + " ... (102 more bytes)"},
			wantText: "forgeplay: GET /api/v1/games/g1: 502 Bad Gateway: " + strings.Repeat("x", 511) + " ... (102 more bytes)",
		},
		{
			name: "empty body", status: 500,
			want:     sdk.APIError{StatusCode: 500, Message: "Internal Server Error"},
			wantText: "forgeplay: GET /api/v1/games/g1: 500 Internal Server Error",
		},
		{
			name: "json that is not an envelope", status: 400, contentType: "application/json",
			body:     `{"detail":"nope"}`,
			want:     sdk.APIError{StatusCode: 400, Message: `{"detail":"nope"}`},
			wantText: `forgeplay: GET /api/v1/games/g1: 400 Bad Request: {"detail":"nope"}`,
		},
		{
			name: "redirect is not success", status: 304,
			want:     sdk.APIError{StatusCode: 304, Message: "Not Modified"},
			wantText: "forgeplay: GET /api/v1/games/g1: 304 Not Modified",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if tc.contentType != "" {
					w.Header().Set("Content-Type", tc.contentType)
				}
				w.WriteHeader(tc.status)
				_, _ = io.WriteString(w, tc.body)
			}))
			t.Cleanup(server.Close)
			client := newClient(t, server.URL)

			game, err := client.GetGame(context.Background(), "g1")
			if game != nil {
				t.Errorf("result: got %#v, want nil on error", game)
			}
			var apiErr *sdk.APIError
			if !errors.As(err, &apiErr) {
				t.Fatalf("error type: got %T (%v), want *sdk.APIError", err, err)
			}
			want := tc.want
			want.Method, want.Path = http.MethodGet, "/api/v1/games/g1"
			if !reflect.DeepEqual(*apiErr, want) {
				t.Errorf("APIError:\n got  %#v\n want %#v", *apiErr, want)
			}
			if got := err.Error(); got != tc.wantText {
				t.Errorf("Error():\n got  %s\n want %s", got, tc.wantText)
			}
		})
	}
}

// A 2xx body far beyond any real answer is refused with a clear error instead of being read into memory without bound.
func TestOversizedResponseIsRejected(t *testing.T) {
	const limit = 32 << 20
	chunk := strings.Repeat("x", 1<<20)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"id":"g1","summary":"`)
		for written := 0; written <= limit; written += len(chunk) {
			if _, err := io.WriteString(w, chunk); err != nil {
				return
			}
		}
		_, _ = io.WriteString(w, `"}`)
	}))
	t.Cleanup(server.Close)
	client := newClient(t, server.URL)

	game, err := client.GetGame(context.Background(), "g1")
	if err == nil {
		t.Fatalf("GetGame: got a game with a %d byte summary, want an error", len(game.Summary))
	}
	if !strings.Contains(err.Error(), "response larger than 33554432 bytes") || !errors.Is(err, sdk.ErrBadResponse) {
		t.Errorf("GetGame: error %q does not name the size limit or is not ErrBadResponse", err)
	}
}

func TestErrorHelpers(t *testing.T) {
	notFound := &sdk.APIError{StatusCode: 404, Code: sdk.CodeNotFound}
	unauthorized := &sdk.APIError{StatusCode: 401, Code: sdk.CodeAuthRequired}
	replayMissing := &sdk.APIError{StatusCode: 404, Code: sdk.CodeReplayNotFound}
	wrapped := fmt.Errorf("load game: %w", notFound)
	plain := errors.New("boom")

	cases := []struct {
		name string
		got  bool
		want bool
	}{
		{"IsCode direct", sdk.IsCode(notFound, sdk.CodeNotFound), true},
		{"IsCode wrapped", sdk.IsCode(wrapped, sdk.CodeNotFound), true},
		{"IsCode other code", sdk.IsCode(notFound, sdk.CodeForbidden), false},
		{"IsCode plain error", sdk.IsCode(plain, sdk.CodeNotFound), false},
		{"IsCode nil", sdk.IsCode(nil, sdk.CodeNotFound), false},
		{"IsStatus wrapped", sdk.IsStatus(wrapped, 404), true},
		{"IsStatus other status", sdk.IsStatus(wrapped, 500), false},
		{"IsStatus nil", sdk.IsStatus(nil, 404), false},
		{"IsNotFound by status", sdk.IsNotFound(replayMissing), true},
		{"IsNotFound unauthorized", sdk.IsNotFound(unauthorized), false},
		{"IsUnauthorized", sdk.IsUnauthorized(unauthorized), true},
		{"IsUnauthorized not found", sdk.IsUnauthorized(notFound), false},
		{"IsUnauthorized plain error", sdk.IsUnauthorized(plain), false},
	}
	for _, tc := range cases {
		if tc.got != tc.want {
			t.Errorf("%s: got %t, want %t", tc.name, tc.got, tc.want)
		}
	}
}

func TestInvalidSuccessBodyIsNotAnAPIError(t *testing.T) {
	server, _ := fakeBackend(t, 200, `{"id": 12`)
	client := newClient(t, server.URL)

	game, err := client.GetGame(context.Background(), "g1")
	if err == nil {
		t.Fatalf("got %#v, want a decode error", game)
	}
	var apiErr *sdk.APIError
	if errors.As(err, &apiErr) {
		t.Errorf("error type: got *sdk.APIError (%v), want a plain decode error", err)
	}
	if !strings.Contains(err.Error(), "decode response") {
		t.Errorf("error text: got %q, want it to mention the decode step", err)
	}
	// The class and the JSON cause are both reachable.
	var syntaxErr *json.SyntaxError
	if !errors.Is(err, sdk.ErrBadResponse) || !(errors.As(err, &syntaxErr) || errors.Is(err, io.ErrUnexpectedEOF)) {
		t.Errorf("error chain: got %#v, want ErrBadResponse wrapping the JSON error", err)
	}
}

func TestNoContentResponse(t *testing.T) {
	server, _ := fakeBackend(t, http.StatusNoContent, "")
	client := newClient(t, server.URL)
	if err := client.Logout(context.Background()); err != nil {
		t.Errorf("Logout on 204: %v", err)
	}
}

func TestContextCancellation(t *testing.T) {
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-release:
		case <-r.Context().Done():
		}
	}))
	t.Cleanup(server.Close)
	t.Cleanup(func() { close(release) })
	client := newClient(t, server.URL)

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	_, err := client.GetGame(ctx, "g1")
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("error: got %v, want one wrapping context.DeadlineExceeded", err)
	}
	var apiErr *sdk.APIError
	if errors.As(err, &apiErr) {
		t.Errorf("error type: got *sdk.APIError, want a transport error")
	}
}

func TestNilContextIsRejected(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"ok":true}`)
	client := newClient(t, server.URL)
	//nolint:staticcheck // A nil context is the input under test.
	if err := client.Health(nil); err == nil {
		t.Fatal("Health(nil): got nil, want an error")
	}
	if len(seen()) != 0 {
		t.Errorf("backend saw %d requests, want none", len(seen()))
	}
}

func TestEmptyPathParametersAreRejected(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"items":[]}`)
	client := newClient(t, server.URL)
	ctx := context.Background()

	calls := map[string]func() error{
		"GetGame":          func() error { _, err := client.GetGame(ctx, ""); return err },
		"GetGameDSL":       func() error { _, err := client.GetGameDSL(ctx, ""); return err },
		"GetMod":           func() error { _, err := client.GetMod(ctx, ""); return err },
		"SaveDraft":        func() error { _, err := client.SaveDraft(ctx, "", nil); return err },
		"GetLatestReplay":  func() error { _, err := client.GetLatestReplay(ctx, "g1", ""); return err },
		"GetRuntimeSchema": func() error { _, err := client.GetRuntimeSchema(ctx, "", "1.0.0"); return err },
	}
	for name, call := range calls {
		err := call()
		if err == nil {
			t.Errorf("%s with an empty argument: got nil, want an error", name)
			continue
		}
		var apiErr *sdk.APIError
		if errors.As(err, &apiErr) {
			t.Errorf("%s: got *sdk.APIError %v, want a local error raised before any request", name, err)
		}
		if !strings.Contains(err.Error(), "empty path parameter") || !errors.Is(err, sdk.ErrInvalidArgument) {
			t.Errorf("%s: error %q does not name the cause or is not ErrInvalidArgument", name, err)
		}
	}
	if len(seen()) != 0 {
		t.Errorf("backend saw %d requests, want none", len(seen()))
	}
}

func TestRecordPlayRejectsNegativeDuration(t *testing.T) {
	server, seen := fakeBackend(t, 200, `{"recorded":true}`)
	client := newClient(t, server.URL)
	if err := client.RecordPlay(context.Background(), "g1", -time.Second); err == nil {
		t.Fatal("RecordPlay(-1s): got nil, want an error")
	}
	if len(seen()) != 0 {
		t.Errorf("backend saw %d requests, want none", len(seen()))
	}
}

func TestSplitRuntimeRef(t *testing.T) {
	cases := []struct {
		ref         string
		wantName    string
		wantVersion string
		wantOK      bool
	}{
		{ref: "shooter@1.0.0", wantName: "shooter", wantVersion: "1.0.0", wantOK: true},
		{ref: "tower_defense@1.0.0", wantName: "tower_defense", wantVersion: "1.0.0", wantOK: true},
		{ref: "shooter"},
		{ref: "shooter@"},
		{ref: "@1.0.0"},
		{ref: "a@b@c"},
		{ref: ""},
	}
	for _, tc := range cases {
		name, version, ok := sdk.SplitRuntimeRef(tc.ref)
		if name != tc.wantName || version != tc.wantVersion || ok != tc.wantOK {
			t.Errorf("SplitRuntimeRef(%q): got (%q, %q, %t), want (%q, %q, %t)", tc.ref, name, version, ok, tc.wantName, tc.wantVersion, tc.wantOK)
		}
	}
}

// pagedBackend serves a three-page game listing keyed by cursor. The returned function reports the cursors requested so far.
func pagedBackend(t *testing.T) (*sdk.Client, func() []string) {
	t.Helper()
	pages := map[string]string{
		"":   `{"items":[{"id":"g1"},{"id":"g2"}],"next_cursor":"c2"}`,
		"c2": `{"items":[{"id":"g3"}],"next_cursor":"c3"}`,
		"c3": `{"items":[{"id":"g4"},{"id":"g5"}],"next_cursor":""}`,
	}
	var (
		mu      sync.Mutex
		cursors []string
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cursor := r.URL.Query().Get("cursor")
		mu.Lock()
		cursors = append(cursors, cursor)
		mu.Unlock()
		body, ok := pages[cursor]
		if !ok {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = io.WriteString(w, `{"error":{"code":"BAD_REQUEST","message":"bad cursor"}}`)
			return
		}
		_, _ = io.WriteString(w, body)
	}))
	t.Cleanup(server.Close)
	return newClient(t, server.URL), func() []string {
		mu.Lock()
		defer mu.Unlock()
		return slices.Clone(cursors)
	}
}

func TestPaginateWalksEveryPage(t *testing.T) {
	client, cursors := pagedBackend(t)
	ctx := context.Background()

	var ids []string
	for game, err := range sdk.Paginate(ctx, func(ctx context.Context, cursor string) (*sdk.Page[sdk.Game], error) {
		return client.ListGames(ctx, sdk.ListGamesParams{PageParams: sdk.PageParams{Cursor: cursor}})
	}) {
		if err != nil {
			t.Fatalf("Paginate: %v", err)
		}
		ids = append(ids, game.ID)
	}
	if want := []string{"g1", "g2", "g3", "g4", "g5"}; !reflect.DeepEqual(ids, want) {
		t.Errorf("items: got %v, want %v", ids, want)
	}
	if want := []string{"", "c2", "c3"}; !reflect.DeepEqual(cursors(), want) {
		t.Errorf("cursors requested: got %q, want %q", cursors(), want)
	}
}

func TestPaginateStopsWhenCallerBreaks(t *testing.T) {
	client, cursors := pagedBackend(t)
	ctx := context.Background()

	var ids []string
	for game, err := range sdk.Paginate(ctx, func(ctx context.Context, cursor string) (*sdk.Page[sdk.Game], error) {
		return client.ListGames(ctx, sdk.ListGamesParams{PageParams: sdk.PageParams{Cursor: cursor}})
	}) {
		if err != nil {
			t.Fatalf("Paginate: %v", err)
		}
		ids = append(ids, game.ID)
		if game.ID == "g3" {
			break
		}
	}
	if want := []string{"g1", "g2", "g3"}; !reflect.DeepEqual(ids, want) {
		t.Errorf("items: got %v, want %v", ids, want)
	}
	if want := []string{"", "c2"}; !reflect.DeepEqual(cursors(), want) {
		t.Errorf("cursors requested: got %q, want %q (the third page must not be fetched)", cursors(), want)
	}
}

func TestPaginateYieldsFetchError(t *testing.T) {
	calls := 0
	fetch := func(ctx context.Context, cursor string) (*sdk.Page[string], error) {
		calls++
		if cursor == "" {
			return &sdk.Page[string]{Items: []string{"a"}, NextCursor: "next"}, nil
		}
		return nil, &sdk.APIError{StatusCode: 400, Code: sdk.CodeBadRequest}
	}

	var items []string
	var errs []error
	for item, err := range sdk.Paginate(context.Background(), fetch) {
		if err != nil {
			errs = append(errs, err)
			continue
		}
		items = append(items, item)
	}
	if want := []string{"a"}; !reflect.DeepEqual(items, want) {
		t.Errorf("items: got %v, want %v", items, want)
	}
	if len(errs) != 1 || !sdk.IsCode(errs[0], sdk.CodeBadRequest) {
		t.Errorf("errors: got %v, want exactly one BAD_REQUEST", errs)
	}
	if calls != 2 {
		t.Errorf("fetch calls: got %d, want 2 (iteration must stop after the error)", calls)
	}
}

func TestPaginateGuardsAgainstBrokenPages(t *testing.T) {
	cases := []struct {
		name      string
		fetch     func(ctx context.Context, cursor string) (*sdk.Page[string], error)
		wantCalls int
	}{
		{
			name: "same cursor returned twice",
			fetch: func(ctx context.Context, cursor string) (*sdk.Page[string], error) {
				return &sdk.Page[string]{Items: []string{"a"}, NextCursor: "stuck"}, nil
			},
			wantCalls: 2,
		},
		{
			name:      "nil page without error",
			fetch:     func(ctx context.Context, cursor string) (*sdk.Page[string], error) { return nil, nil },
			wantCalls: 1,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			var errs []error
			for _, err := range sdk.Paginate(context.Background(), func(ctx context.Context, cursor string) (*sdk.Page[string], error) {
				calls++
				return tc.fetch(ctx, cursor)
			}) {
				if err != nil {
					errs = append(errs, err)
				}
			}
			if len(errs) != 1 {
				t.Errorf("errors: got %v, want exactly one", errs)
			}
			if calls != tc.wantCalls {
				t.Errorf("fetch calls: got %d, want %d", calls, tc.wantCalls)
			}
		})
	}
}

func TestPageHasMore(t *testing.T) {
	var nilPage *sdk.Page[sdk.Game]
	if nilPage.HasMore() {
		t.Error("nil page: HasMore is true, want false")
	}
	if (&sdk.Page[sdk.Game]{}).HasMore() {
		t.Error("last page: HasMore is true, want false")
	}
	if !(&sdk.Page[sdk.Game]{NextCursor: "MjA"}).HasMore() {
		t.Error("page with next cursor: HasMore is false, want true")
	}
}
