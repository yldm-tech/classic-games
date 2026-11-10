package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"
	"unicode"

	"forgeplay/sdk"
)

func TestVersion(t *testing.T) {
	h := newHarness(t)
	mustContain(t, h.ok("version"), "forgeplay 1.2.3 (commit abc1234, built 2026-01-02T03:04:05Z, "+runtime.Version())

	report := decode[versionReport](t, h.ok("version", "--output", "json"))
	if report.Version != "1.2.3" || report.Commit != "abc1234" || report.Date != "2026-01-02T03:04:05Z" || report.SDKVersion != sdk.Version {
		t.Fatalf("version report = %+v", report)
	}
}

func TestOutputFlagIsValidated(t *testing.T) {
	got := newHarness(t).fails("version", "--output", "yaml")
	mustContain(t, got.stderr, `invalid --output "yaml"`)
	if got.stdout != "" {
		t.Fatalf("stdout = %q, want nothing on a usage error", got.stdout)
	}
}

func TestUnknownSubcommandIsAnError(t *testing.T) {
	got := newHarness(t).fails("games", "nope")
	mustContain(t, got.stderr, `unknown command "nope" for "forgeplay games"`)
}

func TestConfigSetGetUnset(t *testing.T) {
	h := newHarness(t)

	mustContain(t, h.ok("config", "path"), filepath.Join(h.configDir, "config.json"))
	if got := strings.TrimSpace(h.ok("config", "get", "server")); got != sdk.DefaultBaseURL {
		t.Fatalf("default server = %q, want %q", got, sdk.DefaultBaseURL)
	}

	h.ok("config", "set", "server", "https://play.example.com/")
	h.ok("config", "set", "language", "en")
	if got := strings.TrimSpace(h.ok("config", "get", "server")); got != "https://play.example.com" {
		t.Fatalf("stored server = %q, want the URL without its trailing slash", got)
	}

	listing := decode[itemList[setting]](t, h.ok("config", "get", "--output", "json"))
	want := map[string]setting{
		"server":   {Key: "server", Value: "https://play.example.com", Source: "config"},
		"language": {Key: "language", Value: "en", Source: "config"},
	}
	for _, item := range listing.Items {
		if expected, ok := want[item.Key]; ok && item != expected {
			t.Fatalf("setting %s = %+v, want %+v", item.Key, item, expected)
		}
	}
	if len(listing.Items) != 3 {
		t.Fatalf("config get lists %d keys, want 3", len(listing.Items))
	}

	h.ok("config", "unset", "server")
	if got := strings.TrimSpace(h.ok("config", "get", "server")); got != sdk.DefaultBaseURL {
		t.Fatalf("server after unset = %q, want the default", got)
	}
}

func TestConfigRejectsBadValues(t *testing.T) {
	h := newHarness(t)
	mustContain(t, h.fails("config", "set", "server", "localhost:8080").stderr, "invalid server URL")
	mustContain(t, h.fails("config", "set", "language", "fr").stderr, `invalid language "fr"`)
	mustContain(t, h.fails("config", "set", "colour", "blue").stderr, `unknown config key "colour"`)
	mustContain(t, h.fails("config", "set", "schema-dir", t.TempDir()).stderr, "holds no *.schema.json files")
	if _, err := os.Stat(filepath.Join(h.configDir, "config.json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("a rejected value still wrote the config file (stat error: %v)", err)
	}
}

func TestServerURLPrecedence(t *testing.T) {
	h := newHarness(t)
	fromFlag, fromEnv, fromConfig := newBackend(t), newBackend(t), newBackend(t)

	h.ok("config", "set", "server", fromConfig.url())
	h.ok("server", "health")
	if fromConfig.count("GET", "/healthz") != 1 {
		t.Fatal("the configured server was not used")
	}

	h.env[EnvServerURL] = fromEnv.url()
	h.ok("server", "health")
	if fromEnv.count("GET", "/healthz") != 1 || fromConfig.count("GET", "/healthz") != 1 {
		t.Fatal("FORGEPLAY_SERVER_URL did not override the config file")
	}

	h.ok("server", "health", "--server", fromFlag.url())
	if fromFlag.count("GET", "/healthz") != 1 || fromEnv.count("GET", "/healthz") != 1 {
		t.Fatal("--server did not override FORGEPLAY_SERVER_URL")
	}

	listing := decode[itemList[setting]](t, h.ok("config", "get", "server", "--output", "json"))
	if listing.Items[0] != (setting{Key: "server", Value: fromEnv.url(), Source: "env"}) {
		t.Fatalf("effective server = %+v, want the env value", listing.Items[0])
	}
}

func TestServerHealthAndInfo(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	mustContain(t, h.ok("server", "health", "--server", b.url()), b.url()+" is healthy")

	health := decode[healthReport](t, h.ok("server", "health", "--server", b.url(), "--output", "json"))
	if !health.OK || health.Server != b.url() {
		t.Fatalf("health report = %+v", health)
	}

	mustContain(t, h.ok("server", "info", "--server", b.url()), "AI mode:", "stub", "SMS gateway:", "no")
	info := decode[map[string]any](t, h.ok("server", "info", "--server", b.url(), "--output", "json"))
	if info["server"] != b.url() || info["environment"] != "development" || info["ai"].(map[string]any)["mode"] != "stub" {
		t.Fatalf("info report = %v", info)
	}
	if providers, ok := info["oauth_providers"].([]any); !ok || len(providers) != 0 {
		t.Fatalf("oauth_providers = %v, want an empty array", info["oauth_providers"])
	}
}

func TestServerHealthFailsWhenTheBackendIsDown(t *testing.T) {
	unhealthy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "upstream unavailable", http.StatusBadGateway)
	}))
	defer unhealthy.Close()
	got := newHarness(t).fails("server", "health", "--server", unhealthy.URL)
	mustContain(t, got.stderr, "Error: HTTP 502: upstream unavailable")

	closed := httptest.NewServer(http.NotFoundHandler())
	closed.Close()
	got = newHarness(t).fails("server", "health", "--server", closed.URL)
	mustContain(t, got.stderr, "Error: sdk: GET /healthz")
}

func TestInterruptCancelsTheRequest(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	slow := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		close(started)
		select {
		case <-r.Context().Done():
		case <-release:
		}
	}))
	defer slow.Close()
	defer close(release)

	// signal.NotifyContext cancels with a cause rather than with context.Canceled; the test does the same.
	ctx, cancel := context.WithCancelCause(context.Background())
	defer cancel(nil)
	go func() {
		<-started
		cancel(errors.New("interrupt signal received"))
	}()

	h := newHarness(t)
	done := make(chan result, 1)
	go func() { done <- h.runWith(ctx, "", "server", "health", "--server", slow.URL) }()
	select {
	case got := <-done:
		if got.code != ExitInterrupted {
			t.Fatalf("exit code = %d, want %d; stderr: %s", got.code, ExitInterrupted, got.stderr)
		}
		mustContain(t, got.stderr, "interrupted")
	case <-time.After(10 * time.Second):
		t.Fatal("the command did not stop after its context was cancelled")
	}
}

func TestInterruptEndsAPromptThatWaitsForInput(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	b.sms = true
	// A terminal that never sends a line: the read end of a pipe nobody writes to.
	terminal, writer := io.Pipe()
	defer writer.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan result, 1)
	go func() {
		done <- h.runReader(ctx, terminal, "auth", "login", "--method", "sms", "--phone", "13800000000")
	}()
	// The code is requested before the prompt, so once the backend has seen the request the command is about to wait for input.
	deadline := time.After(10 * time.Second)
	poll := time.NewTicker(5 * time.Millisecond)
	defer poll.Stop()
	for b.count("POST", "/api/v1/auth/sms/send") == 0 {
		select {
		case <-deadline:
			t.Fatal("the login code was never requested")
		case <-poll.C:
		}
	}
	cancel()
	select {
	case got := <-done:
		if got.code != ExitInterrupted {
			t.Fatalf("exit code = %d, want %d; stderr: %s", got.code, ExitInterrupted, got.stderr)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the prompt kept waiting after the interrupt")
	}
	if _, err := os.Stat(h.credentialsFile()); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("an interrupted login stored credentials (stat error: %v)", err)
	}
}

func TestGuestLoginStoresTheTokenAndNeverPrintsIt(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()

	notLoggedIn := h.fails("auth", "status")
	mustContain(t, notLoggedIn.stdout, "Logged in:", "no")
	mustContain(t, notLoggedIn.stderr, "not logged in to "+b.url())

	login := h.run("auth", "login")
	if login.code != 0 {
		t.Fatalf("login failed: %s", login.stderr)
	}
	mustContain(t, login.stdout, "Logged in to "+b.url()+" as guest user-1 (user-1) (guest session)", "cannot be recovered")
	mustNotContain(t, login.stdout+login.stderr, "secret-token")

	data, err := os.ReadFile(h.credentialsFile())
	if err != nil {
		t.Fatal(err)
	}
	mustContain(t, string(data), `"token": "secret-token-1"`, b.url())
	if runtime.GOOS != "windows" {
		info, err := os.Stat(h.credentialsFile())
		if err != nil {
			t.Fatal(err)
		}
		if mode := info.Mode().Perm(); mode != 0o600 {
			t.Fatalf("credentials.json has mode %o, want 600", mode)
		}
	}

	status := h.run("auth", "status", "--output", "json")
	if status.code != 0 {
		t.Fatalf("status failed: %s", status.stderr)
	}
	mustNotContain(t, status.stdout+status.stderr, "secret-token")
	report := decode[authReport](t, status.stdout)
	if !report.LoggedIn || report.Method != "guest" || report.User == nil || report.User.ID != "user-1" {
		t.Fatalf("status report = %+v", report)
	}
	if got := b.last("GET", "/api/v1/users/me").Auth; got != "Bearer secret-token-1" {
		t.Fatalf("status sent Authorization %q, want the stored token", got)
	}
}

func TestLoginRefusesToReplaceAStoredSession(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")

	again := h.fails("auth", "login")
	mustContain(t, again.stderr, "already logged in to "+b.url(), "--force")
	if b.count("POST", "/api/v1/auth/guest") != 1 {
		t.Fatal("a second guest account was created although the login was refused")
	}

	h.ok("auth", "login", "--force")
	if got := b.last("POST", "/api/v1/auth/guest").Auth; got != "" {
		t.Fatalf("the forced login sent the old token (%q)", got)
	}
	data, _ := os.ReadFile(h.credentialsFile())
	mustContain(t, string(data), "secret-token-2")
	mustNotContain(t, string(data), "secret-token-1")
}

func TestTokensAreKeptPerServer(t *testing.T) {
	h, first, second := newHarness(t), newBackend(t), newBackend(t)
	h.ok("auth", "login", "--server", first.url())

	mustContain(t, h.fails("auth", "status", "--server", second.url()).stderr, "not logged in to "+second.url())
	h.ok("games", "list", "--server", second.url())
	if got := second.last("GET", "/api/v1/games").Auth; got != "" {
		t.Fatalf("the token of one server was sent to another: %q", got)
	}
}

func TestAuthTokenPrintsOnlyTheStoredToken(t *testing.T) {
	h, first, second := newHarness(t), newBackend(t), newBackend(t)
	h.env[EnvServerURL] = first.url()

	missing := h.fails("auth", "token")
	if missing.stdout != "" {
		t.Fatalf("auth token without a session wrote to stdout: %q", missing.stdout)
	}
	mustContain(t, missing.stderr, "not logged in to "+first.url())

	h.ok("auth", "login")
	if got := h.ok("auth", "token"); got != "secret-token-1\n" {
		t.Fatalf("auth token printed %q, want the token on a line of its own", got)
	}
	report := decode[tokenReport](t, h.ok("auth", "token", "--output", "json"))
	if report.Server != first.url() || report.Token != "secret-token-1" {
		t.Fatalf("auth token --output json = %+v", report)
	}
	// Printing is local: the backend is not asked, and the token of one server is not offered for another.
	if n := first.count("GET", "/api/v1/users/me"); n != 0 {
		t.Fatalf("auth token called the backend %d times", n)
	}
	other := h.fails("auth", "token", "--server", second.url())
	mustNotContain(t, other.stdout+other.stderr, "secret-token")
}

func TestRefreshReplacesTheStoredToken(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	mustContain(t, h.fails("auth", "refresh").stderr, "not logged in")

	h.ok("auth", "login")
	refreshed := h.run("auth", "refresh")
	if refreshed.code != 0 {
		t.Fatalf("refresh failed: %s", refreshed.stderr)
	}
	mustNotContain(t, refreshed.stdout+refreshed.stderr, "secret-token")
	data, _ := os.ReadFile(h.credentialsFile())
	mustContain(t, string(data), "secret-token-2", `"method": "guest"`)
	mustNotContain(t, string(data), "secret-token-1")

	h.ok("auth", "status")
	if got := b.last("GET", "/api/v1/users/me").Auth; got != "Bearer secret-token-2" {
		t.Fatalf("status after refresh sent %q, want the new token", got)
	}
}

func TestLogoutRevokesAndDeletesTheToken(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	mustContain(t, h.ok("auth", "logout"), "Not logged in to "+b.url())

	h.ok("auth", "login")
	mustContain(t, h.ok("auth", "logout"), "Logged out of "+b.url())
	if got := b.last("POST", "/api/v1/auth/logout").Auth; got != "Bearer secret-token-1" {
		t.Fatalf("logout sent Authorization %q, want the token to revoke", got)
	}
	data, _ := os.ReadFile(h.credentialsFile())
	mustNotContain(t, string(data), "secret-token")
	h.fails("auth", "status")
}

func TestLogoutKeepsTheTokenWhenTheServerIsUnreachable(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	b.server.Close()

	got := h.fails("auth", "logout")
	mustContain(t, got.stderr, "was not revoked and is still stored", "--local")
	data, _ := os.ReadFile(h.credentialsFile())
	mustContain(t, string(data), "secret-token-1")

	mustContain(t, h.ok("auth", "logout", "--local"), "Logged out of")
	data, _ = os.ReadFile(h.credentialsFile())
	mustNotContain(t, string(data), "secret-token")
}

func TestStatusReportsARevokedToken(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	b.mu.Lock()
	clear(b.tokens)
	b.mu.Unlock()

	got := h.fails("auth", "status", "--output", "json")
	if report := decode[authReport](t, got.stdout); report.LoggedIn {
		t.Fatalf("status reports a revoked token as logged in: %+v", report)
	}
	mustContain(t, got.stderr, "expired or revoked", "auth login --force")
}

func TestPasswordLoginAndSetPassword(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")

	mustContain(t, h.fails("auth", "set-password").stderr, "--password-stdin")
	tooShort := h.runWith(context.Background(), "short\n", "auth", "set-password", "--password-stdin")
	if tooShort.code != ExitFailure {
		t.Fatalf("a short password was accepted: %+v", tooShort)
	}
	mustContain(t, tooShort.stderr, "PASSWORD_INVALID: ")

	set := h.runWith(context.Background(), "correct horse battery\n", "auth", "set-password", "--password-stdin")
	if set.code != 0 {
		t.Fatalf("set-password failed: %s", set.stderr)
	}
	mustNotContain(t, set.stdout+set.stderr, "correct horse battery")
	if body := b.last("POST", "/api/v1/users/me/password").Body; body != `{"password":"correct horse battery"}` {
		t.Fatalf("set-password sent %s", body)
	}

	h.ok("auth", "logout")
	mustContain(t, h.fails("auth", "login", "--method", "password", "--phone", "13800000000").stderr, "--password-stdin")

	wrong := h.runWith(context.Background(), "wrong password\n", "auth", "login", "--method", "password", "--phone", "13800000000", "--password-stdin")
	if wrong.code != ExitFailure {
		t.Fatalf("a wrong password logged in: %+v", wrong)
	}
	mustContain(t, wrong.stderr, "Error: AUTH_INVALID: 手机号或密码错误")
	mustNotContain(t, wrong.stderr, "auth login --force")

	login := h.runWith(context.Background(), "correct horse battery\n", "auth", "login", "--method", "password", "--phone", "13800000000", "--password-stdin", "--output", "json")
	if login.code != 0 {
		t.Fatalf("password login failed: %s", login.stderr)
	}
	mustNotContain(t, login.stdout+login.stderr, "secret-token", "correct horse battery")
	if report := decode[authReport](t, login.stdout); !report.LoggedIn || report.Method != "password" {
		t.Fatalf("login report = %+v", report)
	}
	if body := b.last("POST", "/api/v1/auth/password/login").Body; body != `{"password":"correct horse battery","phone":"13800000000"}` {
		t.Fatalf("password login sent %s", body)
	}
}

func TestSMSLogin(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()

	mustContain(t, h.fails("auth", "login", "--method", "sms").stderr, "--method sms needs --phone")
	noGateway := h.fails("auth", "login", "--method", "sms", "--phone", "13800000000")
	mustContain(t, noGateway.stderr, "has no SMS gateway configured")
	if b.count("POST", "/api/v1/auth/sms/send") != 0 {
		t.Fatal("a code was requested from a server without an SMS gateway")
	}

	b.sms = true
	login := h.runWith(context.Background(), "123456\n", "auth", "login", "--method", "sms", "--phone", "13800000000")
	if login.code != 0 {
		t.Fatalf("sms login failed: %s", login.stderr)
	}
	mustContain(t, login.stderr, "A login code was sent to 13800000000")
	mustContain(t, login.stdout, "(sms session)")
	if body := b.last("POST", "/api/v1/auth/sms/verify").Body; body != `{"code":"123456","phone":"13800000000"}` {
		t.Fatalf("sms verify sent %s", body)
	}

	// With --code the stored code is verified directly and no new one is requested.
	sent := b.count("POST", "/api/v1/auth/sms/send")
	h.ok("auth", "login", "--force", "--method", "sms", "--phone", "13800000000", "--code", "123456")
	if b.count("POST", "/api/v1/auth/sms/send") != sent {
		t.Fatal("--code still requested a new code")
	}
	mustContain(t, h.fails("auth", "login", "--force", "--method", "sms", "--phone", "13800000000", "--code", "000000").stderr, "AUTH_INVALID: 验证码错误")
}

func TestLoginFlagCombinationsAreChecked(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	mustContain(t, h.fails("auth", "login", "--method", "oauth").stderr, `invalid --method "oauth"`)
	mustContain(t, h.fails("auth", "login", "--phone", "13800000000").stderr, "do not apply to a guest login")
	mustContain(t, h.fails("auth", "login", "--method", "sms", "--phone", "1", "--password-stdin").stderr, "--password-stdin only applies")
	if len(b.requests) != 0 {
		t.Fatalf("a rejected flag combination still reached the backend: %+v", b.requests)
	}
}

func TestGamesListShowAndDSL(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()

	firstPage := h.ok("games", "list", "--runtime", "shooter", "--sort", "hot", "--query", "seed", "--ai=false")
	mustContain(t, firstPage, "ID", "TITLE", "game-seed-1", "Seed Game 1", "Seed Studio", "More results: --cursor c1")
	mustNotContain(t, firstPage, "game-seed-2")
	query := b.last("GET", "/api/v1/games").Query
	mustContain(t, query, "runtime=shooter", "sort=hot", "q=seed", "ai=false")

	secondPage := decode[itemPage[sdk.Game]](t, h.ok("games", "list", "--cursor", "c1", "--output", "json"))
	if len(secondPage.Items) != 1 || secondPage.Items[0].ID != "game-seed-2" || !secondPage.Items[0].AIGenerated || secondPage.NextCursor != "c2" {
		t.Fatalf("second page = %+v", secondPage)
	}

	everything := decode[itemPage[sdk.Game]](t, h.ok("games", "list", "--all", "--limit", "2", "--output", "json"))
	if len(everything.Items) != 3 || everything.NextCursor != "" {
		t.Fatalf("--all returned %d games with cursor %q, want 3 and no cursor", len(everything.Items), everything.NextCursor)
	}
	mustContain(t, h.fails("games", "list", "--all", "--cursor", "c1").stderr, "cannot be combined with --cursor")

	mustContain(t, h.ok("games", "show", seedGameID), "Title:", "Seed Game 1", "Runtime:", "shooter@1.0.0", "Author:", "Seed Studio (user-seed)", "2026-01-01T00:00:00Z")
	shown := decode[sdk.Game](t, h.ok("games", "show", seedGameID, "--output", "json"))
	if shown.ID != seedGameID || shown.ModID != seedModID || shown.Status != sdk.GameStatusPublished || shown.Likes != 5 {
		t.Fatalf("games show = %+v", shown)
	}

	document := decode[map[string]any](t, h.ok("games", "dsl", seedGameID))
	if document["meta"].(map[string]any)["runtime"] != "shooter" {
		t.Fatalf("games dsl printed %v", document["meta"])
	}
	out := filepath.Join(t.TempDir(), "game.dsl.json")
	mustContain(t, h.ok("games", "dsl", seedGameID, "-o", out), "Wrote "+out)
	written, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if decode[map[string]any](t, string(written))["player"] == nil {
		t.Fatal("the written DSL has no player section")
	}

	ranking := decode[sdk.Ranking](t, h.ok("games", "ranking", "--type", "rising", "--limit", "2", "--output", "json"))
	if ranking.Type != "rising" || len(ranking.Items) != 2 || ranking.Items[1].Rank != 2 {
		t.Fatalf("ranking = %+v", ranking)
	}
	mustContain(t, h.ok("games", "ranking"), "RANK", "Seed Game 2")
}

func TestBackendErrorsAreRenderedAsCodeAndMessage(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()

	missing := h.fails("games", "show", "no-such-game")
	if missing.stdout != "" {
		t.Fatalf("stdout = %q, want nothing on failure", missing.stdout)
	}
	if missing.stderr != "Error: NOT_FOUND: 作品不存在\n" {
		t.Fatalf("stderr = %q", missing.stderr)
	}
}

func TestAnEmptyIDIsRejectedBeforeCallingTheBackend(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	for _, args := range [][]string{{"games", "show", ""}, {"games", "dsl", " "}, {"mods", "show", ""}, {"mods", "publish", "", "--title", "x"}} {
		mustContain(t, h.fails(args...).stderr, "the id argument is empty")
	}
	mustContain(t, h.fails("games", "show").stderr, "accepts 1 arg(s), received 0")
	if len(b.requests) != 0 {
		t.Fatalf("an empty id still reached the backend: %+v", b.requests)
	}
}

func TestCommandsThatNeedALoginFailBeforeCallingTheBackend(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	for _, args := range [][]string{
		{"games", "fork", seedGameID},
		{"games", "mine"},
		{"games", "delist", seedGameID},
		{"mods", "list"},
		{"mods", "create", "--runtime", "shooter@1.0.0"},
		{"mods", "fork", seedModID},
		{"mods", "publish", seedModID, "--title", "x"},
		{"ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--save"},
	} {
		mustContain(t, h.fails(args...).stderr, "not logged in to "+b.url(), "forgeplay auth login")
	}
	if len(b.requests) != 0 {
		t.Fatalf("commands without a login still reached the backend: %+v", b.requests)
	}
}

func TestAnExpiredSessionPointsToLogin(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	b.mu.Lock()
	clear(b.tokens)
	b.mu.Unlock()
	mustContain(t, h.fails("games", "mine").stderr, "Error: AUTH_REQUIRED: 请先登录", "run 'forgeplay auth login --force'")

	// The hint has to work as printed: the rejected session is still stored, so a login without --force is refused.
	mustContain(t, h.fails("auth", "login").stderr, "already logged in")
	h.ok("auth", "login", "--force")
	h.ok("games", "mine")
}

// "mine" is a fixed route of the backend and an id with a slash is another route once the backend decodes the path; neither is a game, and neither may come back as an empty one.
func TestIDsThatAreOtherRoutesAreNotShownAsEmptyGames(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")

	for _, output := range []string{"table", "json"} {
		mine := h.fails("games", "show", "mine", "--output", output)
		if mine.stdout != "" {
			t.Fatalf("games show mine printed %q, want nothing", mine.stdout)
		}
		mustContain(t, mine.stderr, "Error: NOT_FOUND: ", `"mine"`)
	}

	before := len(b.requests)
	for _, args := range [][]string{
		{"games", "show", seedGameID + "/comments"},
		{"games", "dsl", seedGameID + "/dsl"},
		{"games", "delist", seedGameID + "/like"},
		{"mods", "show", "../games"},
		{"mods", "save", seedModID + "/publish", "--patch", writeFile(t, "empty.json", `[]`)},
	} {
		got := h.fails(args...)
		if got.stdout != "" {
			t.Fatalf("forgeplay %s printed %q, want nothing", strings.Join(args, " "), got.stdout)
		}
		mustContain(t, got.stderr, "invalid path parameter")
	}
	if len(b.requests) != before {
		t.Fatalf("an id that changes the route still reached the backend: %+v", b.requests[before:])
	}
}

// Titles, summaries, tags and author names are written by other users. Whatever they contain, table and detail output must not pass escape sequences on to the terminal, while JSON output keeps the exact text.
func TestServerProvidedTextCannotControlTheTerminal(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	title := "A\x1b[31mRED\x1b[0m\x1b]0;pwned\aB"
	b.mu.Lock()
	b.games[0]["title"] = title
	b.games[0]["summary"] = "sum\x1b[2Jx\u009b31m\x7f"
	b.games[0]["by"] = "Seed\x1b[1m Studio"
	b.games[0]["tags"] = []string{"se\x1bed"}
	b.mu.Unlock()

	for _, args := range [][]string{{"games", "show", seedGameID}, {"games", "list", "--limit", "3"}, {"games", "ranking"}} {
		out := h.ok(args...)
		mustContain(t, out, "A\ufffd[31mRED")
		for _, r := range out {
			if r != '\n' && unicode.IsControl(r) {
				t.Fatalf("forgeplay %s printed the control character %U:\n%q", strings.Join(args, " "), r, out)
			}
		}
	}
	shown := decode[sdk.Game](t, h.ok("games", "show", seedGameID, "--output", "json"))
	if shown.Title != title {
		t.Fatalf("JSON title = %q, want the original %q", shown.Title, title)
	}
	mustNotContain(t, h.ok("games", "show", seedGameID, "--output", "json"), "\x1b")
}

// "tags" is a list, so JSON output always carries it as an array, also for a game the backend sends without the key.
func TestGameJSONAlwaysCarriesATagsArray(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	b.mu.Lock()
	delete(b.games[0], "tags")
	b.mu.Unlock()
	draft := decode[sdk.Mod](t, h.ok("mods", "create", "--runtime", "shooter@1.0.0", "--output", "json"))

	mustContain(t, h.ok("games", "show", seedGameID, "--output", "json"), `"tags": []`)
	mustContain(t, h.ok("mods", "publish", draft.ID, "--title", "No tags", "--output", "json"), `"tags": []`)

	type listing struct {
		Items []map[string]json.RawMessage `json:"items"`
	}
	for _, args := range [][]string{{"games", "list", "--all"}, {"games", "mine"}, {"games", "ranking"}} {
		items := decode[listing](t, h.ok(append(args, "--output", "json")...)).Items
		if len(items) == 0 {
			t.Fatalf("forgeplay %s lists nothing", strings.Join(args, " "))
		}
		for _, item := range items {
			var tags []string
			if err := json.Unmarshal(item["tags"], &tags); err != nil || tags == nil {
				t.Fatalf("forgeplay %s: item %s has tags %s, want an array", strings.Join(args, " "), item["id"], item["tags"])
			}
		}
	}
	// A game that has tags keeps them, and the output still decodes into the SDK type.
	second := decode[sdk.Game](t, h.ok("games", "show", "game-seed-2", "--output", "json"))
	if len(second.Tags) != 1 || second.Tags[0] != "seed" {
		t.Fatalf("tags of game-seed-2 = %v", second.Tags)
	}
}

// A patch with move or copy can never be applied, and its "from" member would be lost on the way, so it is refused before anything is stored.
func TestUnsupportedPatchOperationsAreNotSent(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	draft := decode[sdk.Mod](t, h.ok("mods", "create", "--runtime", "shooter@1.0.0", "--output", "json"))
	created := b.count("POST", "/api/v1/mods")

	move := writeFile(t, "move.json", `[{"op":"replace","path":"/player/hp","value":1},{"op":"move","path":"/x","from":"/y"}]`)
	got := h.fails("mods", "save", draft.ID, "--patch", move)
	mustContain(t, got.stderr, move+`: operation 1 uses unsupported op "move"`, "supported: add, replace, remove, test")
	if b.count("PUT", "/api/v1/drafts/"+draft.ID) != 0 {
		t.Fatal("a patch with a move operation was sent to the backend")
	}

	fromStdin := h.runWith(context.Background(), `[{"op":"copy","path":"/x","from":"/y"}]`, "mods", "create", "--runtime", "shooter@1.0.0", "--patch", "-")
	if fromStdin.code != ExitFailure {
		t.Fatalf("mods create with a copy operation: exit %d, want %d", fromStdin.code, ExitFailure)
	}
	mustContain(t, fromStdin.stderr, `standard input: operation 0 uses unsupported op "copy"`)
	if b.count("POST", "/api/v1/mods") != created {
		t.Fatal("a patch with a copy operation was sent to the backend")
	}
}

// Replacing a stored session revokes the replaced token, but only once the new session is in place.
func TestForcedLoginRevokesTheReplacedSession(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	b.sms = true

	// A login that fails leaves the stored session alone: revoking first would destroy a guest account.
	mustContain(t, h.fails("auth", "login", "--force", "--method", "sms", "--phone", "13800000000", "--code", "000000").stderr, "AUTH_INVALID")
	if b.count("POST", "/api/v1/auth/logout") != 0 {
		t.Fatal("the stored session was revoked although the new login failed")
	}
	data, _ := os.ReadFile(h.credentialsFile())
	mustContain(t, string(data), "secret-token-1")
	h.ok("auth", "status")

	forced := h.run("auth", "login", "--force")
	if forced.code != 0 {
		t.Fatalf("forced login failed: %s", forced.stderr)
	}
	mustContain(t, forced.stdout, "The previous session (guest user-1 (user-1)) was revoked.")
	mustNotContain(t, forced.stdout+forced.stderr, "secret-token")
	if got := b.last("POST", "/api/v1/auth/logout").Auth; got != "Bearer secret-token-1" {
		t.Fatalf("the revocation sent Authorization %q, want the replaced token", got)
	}
	b.mu.Lock()
	loginAt, logoutAt := -1, -1
	for i, request := range b.requests {
		switch request.Path {
		case "/api/v1/auth/guest":
			loginAt = i
		case "/api/v1/auth/logout":
			logoutAt = i
		}
	}
	_, oldValid := b.tokens["secret-token-1"]
	_, newValid := b.tokens["secret-token-2"]
	b.mu.Unlock()
	if logoutAt < loginAt {
		t.Fatal("the replaced session was revoked before the new login succeeded")
	}
	if oldValid || !newValid {
		t.Fatalf("after the forced login: old token valid %v, new token valid %v; want false and true", oldValid, newValid)
	}
	h.ok("auth", "status")
	if got := b.last("GET", "/api/v1/users/me").Auth; got != "Bearer secret-token-2" {
		t.Fatalf("status after the forced login sent %q, want the new token", got)
	}
}

// A revocation that fails does not undo the login: the new session is stored and the failure is a warning.
func TestForcedLoginWarnsWhenTheReplacedSessionCannotBeRevoked(t *testing.T) {
	h := newHarness(t)
	var sessions atomic.Int32
	flaky := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/auth/guest" {
			fail(w, http.StatusInternalServerError, "INTERNAL", "logout is broken")
			return
		}
		n := sessions.Add(1)
		reply(w, http.StatusOK, map[string]any{"token": fmt.Sprintf("secret-token-%d", n), "user": map[string]any{"id": fmt.Sprintf("user-%d", n), "nickname": "guest"}})
	}))
	defer flaky.Close()
	h.env[EnvServerURL] = flaky.URL
	h.ok("auth", "login")

	forced := h.run("auth", "login", "--force")
	if forced.code != 0 {
		t.Fatalf("exit %d, want 0: the new session is in place; stderr: %s", forced.code, forced.stderr)
	}
	mustContain(t, forced.stderr, "Warning: the previous session could not be revoked", "INTERNAL: logout is broken")
	mustNotContain(t, forced.stdout, "was revoked")
	data, _ := os.ReadFile(h.credentialsFile())
	mustContain(t, string(data), "secret-token-2")
	mustNotContain(t, string(data), "secret-token-1")
}

// A proxy error page can be megabytes of HTML; only its start belongs in the error message.
func TestALongErrorPageIsNotDumpedToTheTerminal(t *testing.T) {
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(http.StatusBadGateway)
		_, _ = io.WriteString(w, "<html>"+strings.Repeat("x", 300_000)+"</html>")
	}))
	defer proxy.Close()
	got := newHarness(t).fails("server", "health", "--server", proxy.URL)
	mustContain(t, got.stderr, "Error: HTTP 502: <html>xxx", "more bytes)")
	if len(got.stderr) > 1024 {
		t.Fatalf("stderr holds %d bytes, want at most 1024", len(got.stderr))
	}
}

// A configuration directory that other users can write to lets them swap the stored token or the server URL, so every command that connects says so; the directory itself is left alone because it may not belong to the CLI.
func TestASharedConfigDirectoryIsReported(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX permission bits are not enforced on Windows")
	}
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	quiet := h.run("auth", "login")
	mustNotContain(t, quiet.stderr, "Warning")

	if err := os.Chmod(h.configDir, 0o777); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(h.credentialsFile(), 0o644); err != nil {
		t.Fatal(err)
	}
	status := h.run("auth", "status")
	if status.code != 0 {
		t.Fatalf("auth status failed: %s", status.stderr)
	}
	if want := "Warning: " + h.configDir + " is writable by other users (mode 0777); credentials and settings stored there can be replaced\n"; status.stderr != want {
		t.Fatalf("stderr = %q, want %q", status.stderr, want)
	}
	for path, want := range map[string]os.FileMode{h.configDir: 0o777, h.credentialsFile(): 0o600} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if got := info.Mode().Perm(); got != want {
			t.Fatalf("%s has mode %o, want %o", path, got, want)
		}
	}
}

func TestModLifecycle(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	patch := writeFile(t, "patch.json", `[{"op":"replace","path":"/player/hp","value":250}]`)

	created := decode[sdk.Mod](t, h.ok("mods", "create", "--runtime", "shooter@1.0.0", "--patch", patch, "--output", "json"))
	if !created.Draft || created.Runtime != "shooter@1.0.0" || len(created.Patch) != 1 || created.Patch[0].Path != "/player/hp" {
		t.Fatalf("created mod = %+v", created)
	}
	sent := decode[map[string]any](t, b.last("POST", "/api/v1/mods").Body)
	if sent["runtime"] != "shooter@1.0.0" || sent["draft"] != true || sent["parent_id"] != nil {
		t.Fatalf("create sent %v", sent)
	}
	if op := sent["patch"].([]any)[0].(map[string]any); op["op"] != "replace" || op["value"] != float64(250) {
		t.Fatalf("create sent patch %v", sent["patch"])
	}

	// Without --patch the body carries an empty array, never null.
	h.ok("mods", "create", "--parent", created.ID, "--draft=false")
	mustContain(t, b.last("POST", "/api/v1/mods").Body, `"patch":[]`, `"parent_id":"`+created.ID+`"`)
	mustNotContain(t, b.last("POST", "/api/v1/mods").Body, `"draft"`)

	mustContain(t, h.fails("mods", "create").stderr, "exactly one of --runtime")
	mustContain(t, h.fails("mods", "create", "--runtime", "shooter@1.0.0", "--parent", created.ID).stderr, "exactly one of --runtime")
	mustContain(t, h.fails("mods", "create", "--runtime", "shooter").stderr, `invalid --runtime "shooter"`)

	saved := decode[sdk.Mod](t, h.runWith(context.Background(), `[{"op":"remove","path":"/boss"}]`, "mods", "save", created.ID, "--patch", "-", "--output", "json").stdout)
	if saved.ParentID != created.ID || saved.ID == created.ID || !saved.Draft {
		t.Fatalf("saved draft = %+v", saved)
	}
	mustContain(t, b.last("PUT", "/api/v1/drafts/"+created.ID).Body, `{"patch":[{"op":"remove","path":"/boss"}]}`)

	forked := h.ok("mods", "fork", seedModID)
	mustContain(t, forked, "Forked mod "+seedModID+" into draft mod ", "Parent:", seedModID, "Draft:", "yes")

	listing := h.ok("mods", "list")
	mustContain(t, listing, "ID", "RUNTIME", created.ID, saved.ID)
	drafts := decode[itemList[sdk.Mod]](t, h.ok("mods", "list", "--output", "json"))
	if len(drafts.Items) != 3 || drafts.Items[0].ID == created.ID {
		t.Fatalf("drafts = %+v, want 3 with the newest first", drafts.Items)
	}

	mustContain(t, h.ok("mods", "show", created.ID), "Patch operations:", "1", "replace", "/player/hp", "250")
	lineage := decode[itemList[sdk.Mod]](t, h.ok("mods", "lineage", saved.ID, "--output", "json"))
	if len(lineage.Items) != 2 || lineage.Items[0].ID != seedModID || lineage.Items[1].ID != saved.ID {
		t.Fatalf("lineage = %+v", lineage.Items)
	}
	if decode[map[string]any](t, h.ok("mods", "dsl", saved.ID))["meta"] == nil {
		t.Fatal("mods dsl printed no meta")
	}
}

func TestPublishPicksTheEndpointByDraftState(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	draft := decode[sdk.Mod](t, h.ok("mods", "create", "--runtime", "shooter@1.0.0", "--output", "json"))
	final := decode[sdk.Mod](t, h.ok("mods", "create", "--runtime", "shooter@1.0.0", "--draft=false", "--output", "json"))

	mustContain(t, h.fails("mods", "publish", draft.ID).stderr, `required flag(s) "title" not set`)
	mustContain(t, h.fails("mods", "publish", draft.ID, "--title", "x", "--tag", "a,b,c,d").stderr, "at most 3 tags")

	published := h.ok("mods", "publish", draft.ID, "--title", "Cat <Shooter> & Co", "--summary", "The player is a cat", "--tag", "cat", "--tag", "shooter", "--category", "action")
	mustContain(t, published, "Submitted mod "+draft.ID+" as game ", "(status reviewing)", "Cat <Shooter> & Co", "cat, shooter")
	body := decode[map[string]any](t, b.last("POST", "/api/v1/drafts/"+draft.ID+"/publish").Body)
	if body["title"] != "Cat <Shooter> & Co" || body["category"] != "action" || len(body["tags"].([]any)) != 2 {
		t.Fatalf("publish draft sent %v", body)
	}
	if b.count("POST", "/api/v1/games") != 0 {
		t.Fatal("a draft was published through POST /games, which leaves its draft flag set")
	}

	game := decode[sdk.Game](t, h.ok("mods", "publish", final.ID, "--title", "Final", "--ai-generated", "--output", "json"))
	if game.Status != sdk.GameStatusReviewing || game.ModID != final.ID || !game.AIGenerated {
		t.Fatalf("published game = %+v", game)
	}
	mustContain(t, b.last("POST", "/api/v1/games").Body, `"mod_id":"`+final.ID+`"`, `"title":"Final"`)

	mine := decode[itemList[sdk.Game]](t, h.ok("games", "mine", "--output", "json"))
	if len(mine.Items) != 2 {
		t.Fatalf("games mine lists %d games, want the 2 just submitted", len(mine.Items))
	}
	// JSON output keeps "<" and "&" readable instead of < escapes.
	mustContain(t, h.ok("games", "mine", "--output", "json"), `"title": "Cat <Shooter> & Co"`)
}

func TestGamesForkAndDelist(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")

	fork := decode[sdk.Mod](t, h.ok("games", "fork", seedGameID, "--output", "json"))
	if !fork.Draft || fork.ParentID != seedModID {
		t.Fatalf("forked mod = %+v", fork)
	}
	if got := b.last("POST", "/api/v1/games/"+seedGameID+"/fork").Auth; got != "Bearer secret-token-1" {
		t.Fatalf("fork sent Authorization %q", got)
	}
	mustContain(t, h.ok("games", "delist", seedGameID), "Delisted game "+seedGameID, "delisted")
}

func TestAIGenerateFromTheBaseline(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()

	mustContain(t, h.fails("ai", "generate", "cats").stderr, "pass --runtime, --game, --mod or --dsl")
	mustContain(t, h.fails("ai", "generate", "cats", "--runtime", "shooter").stderr, `invalid --runtime "shooter"`)
	mustContain(t, h.fails("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--game", seedGameID).stderr, "none of the others can be")
	if b.count("POST", "/api/v1/ai/mod") != 0 {
		t.Fatal("a rejected invocation still spent AI quota")
	}

	patchOut := filepath.Join(t.TempDir(), "patch.json")
	dslOut := filepath.Join(t.TempDir(), "new.dsl.json")
	generated := h.ok("ai", "generate", "turn the player into a cat", "--runtime", "shooter@1.0.0", "--patch-out", patchOut, "--dsl-out", dslOut)
	mustContain(t, generated, "Generated a patch with 1 operation(s) for shooter@1.0.0, based on the runtime baseline", "Model:", "stub", "Tokens:", "12 prompt, 7 completion", "Balance hint:", "stub hint", "OP", "replace", "/player/sprite", `"cat"`)
	mustNotContain(t, generated, "signed-provenance")

	request := decode[sdk.GenerateModRequest](t, b.last("POST", "/api/v1/ai/mod").Body)
	if request.Runtime != "shooter@1.0.0" || request.Prompt != "turn the player into a cat" || request.CurrentDSL["player"] == nil {
		t.Fatalf("generate sent runtime %q, prompt %q, dsl keys %d", request.Runtime, request.Prompt, len(request.CurrentDSL))
	}
	if b.count("POST", "/api/v1/mods") != 0 {
		t.Fatal("a mod was stored without --save")
	}

	// The written patch applies offline to the baseline and yields the DSL the backend returned.
	baseline := repoPath(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json")
	applied := h.ok("dsl", "patch", baseline, patchOut, "--validate")
	fromBackend, err := os.ReadFile(dslOut)
	if err != nil {
		t.Fatal(err)
	}
	if applied != string(fromBackend) {
		t.Fatalf("applying the generated patch offline differs from the backend's new_dsl\noffline: %s\nbackend: %s", applied, fromBackend)
	}

	quota := decode[sdk.AIQuota](t, h.ok("ai", "quota", "--output", "json"))
	if quota.Used != 1 || quota.Remaining != 19 || quota.Limit != 20 {
		t.Fatalf("quota = %+v", quota)
	}
	mustContain(t, h.ok("ai", "quota"), "Used:", "Remaining:", "19", "Daily limit:", "20")
}

func TestAIGenerateSaveStoresADraftWithProvenance(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")

	fromGame := decode[generateReport](t, h.ok("ai", "generate", "cats", "--game", seedGameID, "--save", "--output", "json"))
	if fromGame.Runtime != "shooter@1.0.0" || fromGame.Model != "stub" || len(fromGame.DSLPatch) != 1 || fromGame.NewDSL == nil || fromGame.Provenance != "signed-provenance" {
		t.Fatalf("report = %+v", fromGame)
	}
	if fromGame.SavedMod == nil || !fromGame.SavedMod.Draft || !fromGame.SavedMod.AIGenerated || fromGame.SavedMod.ParentID != seedModID {
		t.Fatalf("saved mod = %+v, want an AI-marked draft under the game's mod", fromGame.SavedMod)
	}
	sent := decode[map[string]any](t, b.last("POST", "/api/v1/mods").Body)
	if sent["parent_id"] != seedModID || sent["ai_provenance"] != "signed-provenance" || sent["draft"] != true || sent["runtime"] != nil {
		t.Fatalf("save sent %v", sent)
	}

	fromBaseline := h.ok("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--save")
	mustContain(t, fromBaseline, "Saved as:", "draft mod mod-", "AI generated mark:", "yes")
	sent = decode[map[string]any](t, b.last("POST", "/api/v1/mods").Body)
	if sent["runtime"] != "shooter@1.0.0" || sent["parent_id"] != nil {
		t.Fatalf("saving a baseline result sent %v, want a root mod", sent)
	}

	fromMod := decode[generateReport](t, h.ok("ai", "generate", "cats", "--mod", fromGame.SavedMod.ID, "--output", "json"))
	if fromMod.SavedMod != nil || fromMod.Runtime != "shooter@1.0.0" {
		t.Fatalf("report without --save = %+v", fromMod)
	}
}

// A backend without FORGEPLAY_SECRET signs nothing, so the saved draft has no AI mark. The output has to say so instead of implying that --save always marks the draft.
func TestAIGenerateSaveSaysWhenTheDraftIsNotMarked(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	b.mu.Lock()
	b.unsigned = true
	b.mu.Unlock()

	mustContain(t, h.ok("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--save"), "Saved as:", "draft mod mod-", "AI generated mark:  no")
	sent := decode[map[string]any](t, b.last("POST", "/api/v1/mods").Body)
	if provenance, present := sent["ai_provenance"]; present && provenance != "" {
		t.Fatalf("the save sent ai_provenance %v although the backend issued none", provenance)
	}
	saved := decode[generateReport](t, h.ok("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--save", "--output", "json"))
	if saved.Provenance != "" || saved.SavedMod == nil || saved.SavedMod.AIGenerated {
		t.Fatalf("report = %+v with saved mod %+v, want no provenance and an unmarked draft", saved, saved.SavedMod)
	}
}

func TestAIGenerateFromALocalFile(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	baseline := repoPath(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json")

	mustContain(t, h.ok("ai", "generate", "cats", "--dsl", baseline), "based on "+baseline)
	if request := decode[sdk.GenerateModRequest](t, b.last("POST", "/api/v1/ai/mod").Body); request.Runtime != "shooter@1.0.0" {
		t.Fatalf("runtime read from the file's meta = %q", request.Runtime)
	}
	mustContain(t, h.fails("ai", "generate", "cats", "--dsl", baseline, "--save").stderr, "none of the others can be")
	mustContain(t, h.fails("ai", "generate", "cats", "--dsl", writeFile(t, "bare.json", `{"player":{"sprite":"dog"}}`)).stderr, "pass --runtime")
}

func TestAIGenerateReportsAnExhaustedQuota(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	b.quota = 20
	got := h.fails("ai", "generate", "cats", "--runtime", "shooter@1.0.0")
	if got.stderr != "Error: QUOTA_EXCEEDED: 今日 AI 次数已用完\n" {
		t.Fatalf("stderr = %q", got.stderr)
	}
}

// A generation has already cost a quota unit when its result is written, so a file that cannot be written must not swallow the result.
func TestAIGenerateStillPrintsTheResultWhenAnOutputFileCannotBeWritten(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	missing := filepath.Join(t.TempDir(), "missing", "patch.json")
	dslOut := filepath.Join(t.TempDir(), "new.dsl.json")

	got := h.fails("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--patch-out", missing, "--dsl-out", dslOut, "--output", "json")
	mustContain(t, got.stderr, "Error: write "+missing)
	report := decode[generateReport](t, got.stdout)
	if len(report.DSLPatch) != 1 || report.NewDSL == nil {
		t.Fatalf("report = %+v, want the generated patch and DSL", report)
	}
	if b.count("POST", "/api/v1/ai/mod") != 1 {
		t.Fatalf("the backend generated %d times, want 1", b.count("POST", "/api/v1/ai/mod"))
	}
	if _, err := os.Stat(dslOut); err != nil {
		t.Fatalf("the DSL file that could be written is missing: %v", err)
	}

	// The table view names only the file that was written.
	table := h.fails("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--patch-out", missing, "--dsl-out", dslOut)
	mustContain(t, table.stdout, "Generated a patch with 1 operation(s)", "DSL written to:", dslOut)
	mustNotContain(t, table.stdout, "Patch written to")

	// With --save failing as well, both failures are reported and the result is still printed.
	b.mu.Lock()
	clear(b.tokens)
	b.mu.Unlock()
	both := h.fails("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--patch-out", missing, "--save", "--output", "json")
	mustContain(t, both.stderr, "write "+missing, "the patch was generated but could not be saved as a draft", "AUTH_REQUIRED")
	if report := decode[generateReport](t, both.stdout); len(report.DSLPatch) != 1 || report.SavedMod != nil {
		t.Fatalf("report = %+v, want the generated patch without a saved mod", report)
	}
}

func TestAIGenerateStillPrintsTheResultWhenSavingFails(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	h.ok("auth", "login")
	// The session is revoked between the login check and the save, after the quota unit is spent.
	b.mu.Lock()
	clear(b.tokens)
	b.mu.Unlock()

	got := h.fails("ai", "generate", "cats", "--runtime", "shooter@1.0.0", "--save", "--output", "json")
	report := decode[generateReport](t, got.stdout)
	if len(report.DSLPatch) != 1 || report.SavedMod != nil {
		t.Fatalf("report = %+v, want the generated patch without a saved mod", report)
	}
	mustContain(t, got.stderr, "the patch was generated but could not be saved as a draft", "AUTH_REQUIRED")
}

func TestDescribeError(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want string
	}{
		{"envelope", &sdk.APIError{StatusCode: 404, Code: "NOT_FOUND", Message: "game not found"}, "NOT_FOUND: game not found"},
		{"no envelope", &sdk.APIError{StatusCode: 502, Message: "Bad Gateway"}, "HTTP 502: Bad Gateway"},
		{"no message", &sdk.APIError{StatusCode: 500, Code: "INTERNAL", Method: "GET", Path: "/api/v1/games"}, "INTERNAL: GET /api/v1/games failed"},
		{"wrapped", fmt.Errorf("could not save the draft: %w", &sdk.APIError{StatusCode: 409, Code: "INVALID_STATE", Message: "not a draft", Method: "PUT", Path: "/api/v1/drafts/m1"}), "could not save the draft: INVALID_STATE: not a draft"},
		{"missing session", &sdk.APIError{StatusCode: 401, Code: "AUTH_REQUIRED", Message: "login first"}, "AUTH_REQUIRED: login first\nThe stored login is missing, expired or revoked: run 'forgeplay auth login --force'."},
		{"wrong credentials", &sdk.APIError{StatusCode: 401, Code: "AUTH_INVALID", Message: "wrong password"}, "AUTH_INVALID: wrong password"},
		{"plain", errors.New("read patch.json: no such file"), "read patch.json: no such file"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := describeError(c.err); got != c.want {
				t.Fatalf("describeError = %q, want %q", got, c.want)
			}
		})
	}
}

func TestJSONOutputIsStable(t *testing.T) {
	h, b := newHarness(t), newBackend(t)
	h.env[EnvServerURL] = b.url()
	first := h.ok("games", "show", seedGameID, "--output", "json")
	second := h.ok("games", "show", seedGameID, "--output", "json")
	if first != second {
		t.Fatalf("two runs printed different JSON:\n%s\n%s", first, second)
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal([]byte(first), &keys); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"id", "mod_id", "author_id", "by", "title", "summary", "status", "ai_generated", "runtime", "created_at", "plays", "forks", "likes", "views"} {
		if _, ok := keys[key]; !ok {
			t.Fatalf("games show JSON lacks %q: %s", key, first)
		}
	}
}
