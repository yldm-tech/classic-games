package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// harness runs the real command tree against buffers and a private configuration directory.
type harness struct {
	t         *testing.T
	configDir string
	env       map[string]string
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "forgeplay")
	return &harness{t: t, configDir: dir, env: map[string]string{"FORGEPLAY_CONFIG_DIR": dir}}
}

type result struct {
	stdout string
	stderr string
	code   int
}

func (h *harness) run(args ...string) result {
	h.t.Helper()
	return h.runWith(context.Background(), "", args...)
}

func (h *harness) runWith(ctx context.Context, stdin string, args ...string) result {
	h.t.Helper()
	return h.runReader(ctx, strings.NewReader(stdin), args...)
}

func (h *harness) runReader(ctx context.Context, stdin io.Reader, args ...string) result {
	h.t.Helper()
	var stdout, stderr bytes.Buffer
	code := Run(ctx, args, Options{
		Stdin:  stdin,
		Stdout: &stdout,
		Stderr: &stderr,
		Getenv: func(key string) string { return h.env[key] },
		Build:  BuildInfo{Version: "1.2.3", Commit: "abc1234", Date: "2026-01-02T03:04:05Z"},
	})
	return result{stdout: stdout.String(), stderr: stderr.String(), code: code}
}

// ok runs a command that must succeed and returns its stdout.
func (h *harness) ok(args ...string) string {
	h.t.Helper()
	got := h.run(args...)
	if got.code != 0 {
		h.t.Fatalf("forgeplay %s: exit %d\nstdout: %s\nstderr: %s", strings.Join(args, " "), got.code, got.stdout, got.stderr)
	}
	return got.stdout
}

// fails runs a command that must exit with status 1 and returns the result.
func (h *harness) fails(args ...string) result {
	h.t.Helper()
	got := h.run(args...)
	if got.code != ExitFailure {
		h.t.Fatalf("forgeplay %s: exit %d, want %d\nstdout: %s\nstderr: %s", strings.Join(args, " "), got.code, ExitFailure, got.stdout, got.stderr)
	}
	return got
}

func (h *harness) credentialsFile() string { return filepath.Join(h.configDir, "credentials.json") }

func decode[T any](t *testing.T, data string) T {
	t.Helper()
	var value T
	if err := json.Unmarshal([]byte(data), &value); err != nil {
		t.Fatalf("output is not the expected JSON: %v\n%s", err, data)
	}
	return value
}

func mustContain(t *testing.T, text string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(text, want) {
			t.Fatalf("output lacks %q:\n%s", want, text)
		}
	}
}

func mustNotContain(t *testing.T, text string, unwanted ...string) {
	t.Helper()
	for _, bad := range unwanted {
		if strings.Contains(text, bad) {
			t.Fatalf("output must not contain %q:\n%s", bad, text)
		}
	}
}

// repoPath resolves a path relative to the repository root, four levels above this package.
func repoPath(t *testing.T, parts ...string) string {
	t.Helper()
	path, err := filepath.Abs(filepath.Join(append([]string{"..", "..", "..", ".."}, parts...)...))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("repository fixture is missing: %v", err)
	}
	return path
}

func writeFile(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// recorded is one request the fake backend received.
type recorded struct {
	Method string
	Path   string
	Query  string
	Auth   string
	Body   string
}

// backend is an in-memory stand-in for apps/server that speaks the same wire format for the endpoints the CLI calls: the error envelope, bearer tokens, cursor pages and the draft/publish state machine.
type backend struct {
	t      *testing.T
	server *httptest.Server

	mu       sync.Mutex
	requests []recorded
	tokens   map[string]string // token -> user id
	sequence int
	games    []map[string]any
	mods     map[string]map[string]any
	sms      bool
	password string
	quota    int
	baseline map[string]any
	// unsigned makes the backend answer like one without FORGEPLAY_SECRET: a generation carries no provenance.
	unsigned bool
}

const (
	seedGameID = "game-seed-1"
	seedModID  = "mod-seed-1"
)

func newBackend(t *testing.T) *backend {
	t.Helper()
	baselineData, err := os.ReadFile(repoPath(t, "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	if err != nil {
		t.Fatal(err)
	}
	b := &backend{t: t, tokens: map[string]string{}, mods: map[string]map[string]any{}, baseline: decode[map[string]any](t, string(baselineData))}
	b.mods[seedModID] = map[string]any{"id": seedModID, "runtime": "shooter@1.0.0", "patch": []any{}, "ai_generated": false, "author_id": "user-seed", "created_at": "2026-01-01T00:00:00Z", "draft": false}
	for i := 1; i <= 3; i++ {
		b.games = append(b.games, map[string]any{
			"id": fmt.Sprintf("game-seed-%d", i), "mod_id": seedModID, "author_id": "user-seed", "by": "Seed Studio", "title": fmt.Sprintf("Seed Game %d", i), "summary": "A seeded shooter", "tags": []string{"seed"},
			"status": "published", "ai_generated": i == 2, "runtime": "shooter@1.0.0", "created_at": "2026-01-01T00:00:00Z", "tone": "ember", "cat": "action", "plays": 10 * i, "forks": i, "likes": 5 * i, "views": 100 * i,
		})
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { reply(w, http.StatusOK, map[string]any{"ok": true}) })
	mux.HandleFunc("GET /api/v1/meta", func(w http.ResponseWriter, _ *http.Request) {
		reply(w, http.StatusOK, map[string]any{"environment": "development", "ai": map[string]any{"mode": "stub"}, "sms": b.sms, "oauth_providers": []string{}, "payments": false, "admin_configured": false, "moderation": false})
	})

	mux.HandleFunc("POST /api/v1/auth/guest", func(w http.ResponseWriter, _ *http.Request) { b.issueSession(w, "guest") })
	mux.HandleFunc("POST /api/v1/auth/sms/send", func(w http.ResponseWriter, _ *http.Request) { reply(w, http.StatusOK, map[string]any{"ok": true}) })
	mux.HandleFunc("POST /api/v1/auth/sms/verify", func(w http.ResponseWriter, r *http.Request) {
		body := readBody[map[string]string](r)
		if body["code"] != "123456" {
			fail(w, http.StatusUnauthorized, "AUTH_INVALID", "验证码错误")
			return
		}
		b.issueSession(w, "phone")
	})
	mux.HandleFunc("POST /api/v1/auth/password/login", func(w http.ResponseWriter, r *http.Request) {
		body := readBody[map[string]string](r)
		if b.password == "" || body["password"] != b.password {
			fail(w, http.StatusUnauthorized, "AUTH_INVALID", "手机号或密码错误")
			return
		}
		b.issueSession(w, "phone")
	})
	mux.HandleFunc("POST /api/v1/auth/refresh", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		b.mu.Lock()
		delete(b.tokens, bearer(r))
		b.sequence++
		token := fmt.Sprintf("secret-token-%d", b.sequence)
		b.tokens[token] = user
		b.mu.Unlock()
		reply(w, http.StatusOK, map[string]any{"token": token})
	})
	mux.HandleFunc("POST /api/v1/auth/logout", func(w http.ResponseWriter, r *http.Request) {
		b.mu.Lock()
		delete(b.tokens, bearer(r))
		b.mu.Unlock()
		reply(w, http.StatusOK, map[string]any{"ok": true})
	})
	mux.HandleFunc("GET /api/v1/users/me", func(w http.ResponseWriter, r *http.Request) {
		if user, ok := b.authenticate(w, r); ok {
			reply(w, http.StatusOK, map[string]any{"id": user, "nickname": "Player " + user})
		}
	})
	mux.HandleFunc("POST /api/v1/users/me/password", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := b.authenticate(w, r); !ok {
			return
		}
		body := readBody[map[string]string](r)
		if len(body["password"]) < 8 {
			fail(w, http.StatusBadRequest, "PASSWORD_INVALID", "密码至少 8 位")
			return
		}
		b.mu.Lock()
		b.password = body["password"]
		b.mu.Unlock()
		reply(w, http.StatusOK, map[string]any{"ok": true})
	})

	mux.HandleFunc("GET /api/v1/games", func(w http.ResponseWriter, r *http.Request) {
		// One game per page unless a limit is given, so the cursor walk is exercised.
		start := 0
		fmt.Sscanf(r.URL.Query().Get("cursor"), "c%d", &start)
		size := 1
		fmt.Sscanf(r.URL.Query().Get("limit"), "%d", &size)
		b.mu.Lock()
		published := []map[string]any{}
		for _, game := range b.games {
			if game["status"] == "published" {
				published = append(published, game)
			}
		}
		b.mu.Unlock()
		end := min(start+size, len(published))
		next := ""
		if end < len(published) {
			next = fmt.Sprintf("c%d", end)
		}
		reply(w, http.StatusOK, map[string]any{"items": published[start:end], "next_cursor": next})
	})
	mux.HandleFunc("GET /api/v1/games/mine", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		b.mu.Lock()
		mine := []map[string]any{}
		for _, game := range b.games {
			if game["author_id"] == user {
				mine = append(mine, game)
			}
		}
		b.mu.Unlock()
		reply(w, http.StatusOK, map[string]any{"items": mine})
	})
	mux.HandleFunc("GET /api/v1/games/{id}", func(w http.ResponseWriter, r *http.Request) {
		if game := b.findGame(w, r.PathValue("id")); game != nil {
			reply(w, http.StatusOK, game)
		}
	})
	mux.HandleFunc("GET /api/v1/games/{id}/dsl", func(w http.ResponseWriter, r *http.Request) {
		if game := b.findGame(w, r.PathValue("id")); game != nil {
			reply(w, http.StatusOK, b.baseline)
		}
	})
	mux.HandleFunc("POST /api/v1/games/{id}/fork", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		if game := b.findGame(w, r.PathValue("id")); game != nil {
			reply(w, http.StatusCreated, b.addMod(user, game["mod_id"].(string), "shooter@1.0.0", []any{}, true, false))
		}
	})
	mux.HandleFunc("POST /api/v1/games/{id}/delist", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := b.authenticate(w, r); !ok {
			return
		}
		if game := b.findGame(w, r.PathValue("id")); game != nil {
			b.mu.Lock()
			game["status"] = "delisted"
			b.mu.Unlock()
			reply(w, http.StatusOK, game)
		}
	})
	mux.HandleFunc("POST /api/v1/games", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		body := readBody[map[string]any](r)
		modID, _ := body["mod_id"].(string)
		reply(w, http.StatusCreated, b.addGame(user, modID, body))
	})
	mux.HandleFunc("GET /api/v1/ranking", func(w http.ResponseWriter, r *http.Request) {
		kind := r.URL.Query().Get("type")
		if kind == "" {
			kind = "hot"
		}
		items := []map[string]any{}
		for i, game := range b.games[:2] {
			entry := map[string]any{"rank": i + 1}
			for key, value := range game {
				entry[key] = value
			}
			items = append(items, entry)
		}
		reply(w, http.StatusOK, map[string]any{"type": kind, "items": items})
	})

	mux.HandleFunc("POST /api/v1/mods", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		body := readBody[map[string]any](r)
		runtime, _ := body["runtime"].(string)
		parent, _ := body["parent_id"].(string)
		if parent != "" {
			runtime = "shooter@1.0.0"
		}
		draft, _ := body["draft"].(bool)
		provenance, _ := body["ai_provenance"].(string)
		reply(w, http.StatusCreated, b.addMod(user, parent, runtime, body["patch"], draft, provenance == "signed-provenance"))
	})
	mux.HandleFunc("POST /api/v1/mods/{id}/fork", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		if mod := b.findMod(w, r.PathValue("id")); mod != nil {
			reply(w, http.StatusCreated, b.addMod(user, mod["id"].(string), mod["runtime"].(string), []any{}, true, false))
		}
	})
	mux.HandleFunc("GET /api/v1/mods/{id}/fork-tree", func(w http.ResponseWriter, r *http.Request) {
		if mod := b.findMod(w, r.PathValue("id")); mod != nil {
			reply(w, http.StatusOK, map[string]any{"ancestors": []any{}, "node": mod, "children": []any{}})
		}
	})
	mux.HandleFunc("GET /api/v1/mods/{id}/lineage", func(w http.ResponseWriter, r *http.Request) {
		if mod := b.findMod(w, r.PathValue("id")); mod != nil {
			reply(w, http.StatusOK, map[string]any{"items": []any{b.mods[seedModID], mod}})
		}
	})
	mux.HandleFunc("GET /api/v1/mods/{id}/dsl", func(w http.ResponseWriter, r *http.Request) {
		if mod := b.findMod(w, r.PathValue("id")); mod != nil {
			reply(w, http.StatusOK, b.baseline)
		}
	})
	mux.HandleFunc("GET /api/v1/drafts", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		b.mu.Lock()
		drafts := []map[string]any{}
		for i := b.sequence; i > 0; i-- {
			if mod, found := b.mods[fmt.Sprintf("mod-%d", i)]; found && mod["draft"] == true && mod["author_id"] == user {
				drafts = append(drafts, mod)
			}
		}
		b.mu.Unlock()
		reply(w, http.StatusOK, map[string]any{"items": drafts})
	})
	mux.HandleFunc("PUT /api/v1/drafts/{id}", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		mod := b.findMod(w, r.PathValue("id"))
		if mod == nil {
			return
		}
		if mod["draft"] != true {
			fail(w, http.StatusConflict, "INVALID_STATE", "不是草稿")
			return
		}
		body := readBody[map[string]any](r)
		reply(w, http.StatusOK, b.addMod(user, mod["id"].(string), mod["runtime"].(string), body["patch"], true, false))
	})
	mux.HandleFunc("POST /api/v1/drafts/{id}/publish", func(w http.ResponseWriter, r *http.Request) {
		user, ok := b.authenticate(w, r)
		if !ok {
			return
		}
		mod := b.findMod(w, r.PathValue("id"))
		if mod == nil {
			return
		}
		b.mu.Lock()
		mod["draft"] = false
		b.mu.Unlock()
		reply(w, http.StatusCreated, b.addGame(user, mod["id"].(string), readBody[map[string]any](r)))
	})

	mux.HandleFunc("GET /api/v1/runtimes/{name}/{version}/baseline", func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("name") != "shooter" || r.PathValue("version") != "1.0.0" {
			fail(w, http.StatusNotFound, "NOT_FOUND", "runtime 不存在")
			return
		}
		reply(w, http.StatusOK, b.baseline)
	})
	mux.HandleFunc("POST /api/v1/ai/mod", func(w http.ResponseWriter, r *http.Request) {
		body := readBody[map[string]any](r)
		current, _ := body["current_dsl"].(map[string]any)
		if current == nil {
			fail(w, http.StatusBadRequest, "BAD_REQUEST", "缺少 current_dsl")
			return
		}
		b.mu.Lock()
		exhausted := b.quota >= 20
		if !exhausted {
			b.quota++
		}
		unsigned := b.unsigned
		b.mu.Unlock()
		if exhausted {
			fail(w, http.StatusTooManyRequests, "QUOTA_EXCEEDED", "今日 AI 次数已用完")
			return
		}
		current["player"].(map[string]any)["sprite"] = "cat"
		generated := map[string]any{
			"dsl_patch": []any{map[string]any{"op": "replace", "path": "/player/sprite", "value": "cat"}},
			"new_dsl":   current, "balance_hint": "stub hint", "model": "stub", "tokens": map[string]any{"prompt": 12, "completion": 7}, "retries": 0, "provenance": "signed-provenance",
		}
		if unsigned {
			delete(generated, "provenance")
		}
		reply(w, http.StatusOK, generated)
	})
	mux.HandleFunc("GET /api/v1/ai/quota", func(w http.ResponseWriter, _ *http.Request) {
		b.mu.Lock()
		used := b.quota
		b.mu.Unlock()
		reply(w, http.StatusOK, map[string]any{"used": used, "remaining": 20 - used, "limit": 20})
	})

	b.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		r.Body = io.NopCloser(bytes.NewReader(body))
		b.mu.Lock()
		b.requests = append(b.requests, recorded{Method: r.Method, Path: r.URL.Path, Query: r.URL.RawQuery, Auth: r.Header.Get("Authorization"), Body: string(body)})
		b.mu.Unlock()
		mux.ServeHTTP(w, r)
	}))
	t.Cleanup(b.server.Close)
	return b
}

func (b *backend) url() string { return b.server.URL }

// last returns the most recent request matching method and path.
func (b *backend) last(method, path string) recorded {
	b.t.Helper()
	b.mu.Lock()
	defer b.mu.Unlock()
	for i := len(b.requests) - 1; i >= 0; i-- {
		if b.requests[i].Method == method && b.requests[i].Path == path {
			return b.requests[i]
		}
	}
	b.t.Fatalf("the backend never received %s %s; it received %+v", method, path, b.requests)
	return recorded{}
}

func (b *backend) count(method, path string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	total := 0
	for _, request := range b.requests {
		if request.Method == method && request.Path == path {
			total++
		}
	}
	return total
}

func (b *backend) issueSession(w http.ResponseWriter, kind string) {
	b.mu.Lock()
	b.sequence++
	token := fmt.Sprintf("secret-token-%d", b.sequence)
	user := fmt.Sprintf("user-%d", b.sequence)
	b.tokens[token] = user
	b.mu.Unlock()
	reply(w, http.StatusOK, map[string]any{"token": token, "user": map[string]any{"id": user, "nickname": kind + " " + user}})
}

func (b *backend) authenticate(w http.ResponseWriter, r *http.Request) (string, bool) {
	b.mu.Lock()
	user, ok := b.tokens[bearer(r)]
	b.mu.Unlock()
	if !ok {
		fail(w, http.StatusUnauthorized, "AUTH_REQUIRED", "请先登录")
	}
	return user, ok
}

func (b *backend) addMod(author, parent, runtime string, patch any, draft, aiGenerated bool) map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.sequence++
	if patch == nil {
		patch = []any{}
	}
	mod := map[string]any{"id": fmt.Sprintf("mod-%d", b.sequence), "runtime": runtime, "patch": patch, "ai_generated": aiGenerated, "author_id": author, "created_at": "2026-03-04T05:06:07Z", "draft": draft}
	if parent != "" {
		mod["parent_id"] = parent
	}
	b.mods[mod["id"].(string)] = mod
	return mod
}

func (b *backend) addGame(author, modID string, body map[string]any) map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.sequence++
	game := map[string]any{
		"id": fmt.Sprintf("game-%d", b.sequence), "mod_id": modID, "author_id": author, "by": "Player " + author, "title": body["title"], "summary": body["summary"], "tags": body["tags"],
		"status": "reviewing", "ai_generated": body["ai_generated"] == true, "runtime": "shooter@1.0.0", "created_at": "2026-03-04T05:06:07Z", "tone": "ember", "cat": body["category"], "plays": 0, "forks": 0, "likes": 0, "views": 0,
	}
	b.games = append(b.games, game)
	return game
}

func (b *backend) findGame(w http.ResponseWriter, id string) map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, game := range b.games {
		if game["id"] == id {
			return game
		}
	}
	fail(w, http.StatusNotFound, "NOT_FOUND", "作品不存在")
	return nil
}

func (b *backend) findMod(w http.ResponseWriter, id string) map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	if mod, ok := b.mods[id]; ok {
		return mod
	}
	fail(w, http.StatusNotFound, "NOT_FOUND", "mod 不存在")
	return nil
}

func bearer(r *http.Request) string {
	return strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
}

func readBody[T any](r *http.Request) T {
	var value T
	_ = json.NewDecoder(r.Body).Decode(&value)
	return value
}

func reply(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func fail(w http.ResponseWriter, status int, code, message string) {
	reply(w, status, map[string]any{"error": map[string]any{"code": code, "message": message}})
}
