package server_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/yldm-tech/classic-games/packages/dsl"
	"github.com/yldm-tech/classic-games/packages/sdk"
)

const (
	testToken      = "test-token"
	testUserID     = "u_tester"
	testProvenance = "prov-signed-by-backend"
)

// fakeBackend is an in-memory stand-in for the Classic Games HTTP API, limited to the routes classic-games-mcp calls. It keeps the backend's observable rules: writes need a bearer token, drafts are private to their author, a mod's effective DSL is its runtime baseline with the patch chain applied, and errors use the {"error": {"code", "message"}} envelope.
type fakeBackend struct {
	t      *testing.T
	server *httptest.Server

	mu        sync.Mutex
	baselines map[string]map[string]any
	mods      map[string]*sdk.Mod
	modOrder  []string
	games     []*sdk.Game
	nextID    int
	requests  []string
	prompts   []string
	// failures forces an error response for a "METHOD /path" key.
	failures map[string]failure
}

type failure struct {
	status  int
	code    string
	message string
}

func newFakeBackend(t *testing.T) *fakeBackend {
	t.Helper()
	fb := &fakeBackend{t: t, baselines: map[string]map[string]any{}, mods: map[string]*sdk.Mod{}, failures: map[string]failure{}}
	for _, name := range runtimeNames {
		fb.baselines[name+"@1.0.0"] = baseline(t, name)
	}
	seed := []struct {
		runtime, title, author, category string
		patch                            []sdk.PatchOp
		ai                               bool
	}{
		{"shooter@1.0.0", "Neon Shooter", "Ada", "arcade", nil, false},
		{"survivor@1.0.0", "Cat Survivor", "Lin", "roguelike", []sdk.PatchOp{{Op: "replace", Path: "/hero/sprite", Value: json.RawMessage(`"mage"`)}}, true},
		{"tower_defense@1.0.0", "Desert Defense", "Sam", "strategy", []sdk.PatchOp{{Op: "replace", Path: "/stage/background", Value: json.RawMessage(`"desert"`)}}, false},
	}
	for i, entry := range seed {
		mod := fb.storeMod(&sdk.Mod{Runtime: entry.runtime, Patch: entry.patch, AuthorID: "u_seed", AIGenerated: entry.ai})
		fb.games = append(fb.games, &sdk.Game{
			ID: fmt.Sprintf("g_%d", i+1), ModID: mod.ID, AuthorID: "u_seed", By: entry.author, Title: entry.title, Summary: "A " + entry.category + " game", Tags: []string{entry.category},
			Status: sdk.GameStatusPublished, AIGenerated: entry.ai, Runtime: entry.runtime, Category: entry.category, CreatedAt: time.Date(2026, 1, i+1, 0, 0, 0, 0, time.UTC), Likes: 10 * (i + 1), Plays: 100 * (i + 1),
		})
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/games", fb.listGames)
	// Like the real backend, the fixed route wins over the id route: "mine" is the caller's own games, not a game.
	mux.HandleFunc("GET /api/v1/games/mine", func(w http.ResponseWriter, r *http.Request) {
		if _, ok := fb.user(w, r, true); ok {
			writeJSON(w, http.StatusOK, map[string]any{"items": []any{}})
		}
	})
	mux.HandleFunc("GET /api/v1/games/{id}", fb.getGame)
	mux.HandleFunc("GET /api/v1/games/{id}/dsl", fb.getGameDSL)
	mux.HandleFunc("POST /api/v1/games/{id}/fork", fb.forkGame)
	mux.HandleFunc("GET /api/v1/mods/{id}/dsl", fb.getModDSL)
	mux.HandleFunc("GET /api/v1/mods/{id}/fork-tree", fb.getModForkTree)
	mux.HandleFunc("POST /api/v1/mods", fb.createMod)
	mux.HandleFunc("GET /api/v1/drafts", fb.listDrafts)
	mux.HandleFunc("POST /api/v1/drafts/{id}/publish", fb.publishDraft)
	mux.HandleFunc("GET /api/v1/runtimes/{name}/{version}/baseline", fb.getBaseline)
	mux.HandleFunc("POST /api/v1/ai/mod", fb.generateMod)
	fb.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := r.Method + " " + r.URL.Path
		fb.mu.Lock()
		fb.requests = append(fb.requests, key)
		forced, fail := fb.failures[key]
		fb.mu.Unlock()
		if fail {
			writeFailure(w, forced)
			return
		}
		mux.ServeHTTP(w, r)
	}))
	t.Cleanup(fb.server.Close)
	return fb
}

// addShowcaseGame lists a published game whose mod the backend does not hold, like the showcase games a development backend is seeded with.
func (fb *fakeBackend) addShowcaseGame(id, title string) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	fb.games = append(fb.games, &sdk.Game{ID: id, ModID: "seed_" + id, AuthorID: "u_seed", By: "@talia", Title: title, Status: sdk.GameStatusPublished, Category: "Strategy", CreatedAt: time.Date(2025, 12, 1, 0, 0, 0, 0, time.UTC)})
}

// storeMod assigns an id and a creation time and records the mod. The caller holds fb.mu or is the constructor.
func (fb *fakeBackend) storeMod(mod *sdk.Mod) *sdk.Mod {
	fb.nextID++
	mod.ID = fmt.Sprintf("m_%d", fb.nextID)
	mod.CreatedAt = time.Date(2026, 2, 1, 0, 0, fb.nextID, 0, time.UTC)
	fb.mods[mod.ID] = mod
	fb.modOrder = append(fb.modOrder, mod.ID)
	return mod
}

// seen returns the "METHOD /path" keys of the requests received so far.
func (fb *fakeBackend) seen() []string {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	return slices.Clone(fb.requests)
}

// count reports how many requests matched the "METHOD /path" key.
func (fb *fakeBackend) count(key string) int {
	total := 0
	for _, request := range fb.seen() {
		if request == key {
			total++
		}
	}
	return total
}

// fail makes every later request matching the "METHOD /path" key answer with the given error.
func (fb *fakeBackend) fail(key string, forced failure) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	fb.failures[key] = forced
}

// promptsSeen returns the "runtime: prompt" pairs the AI endpoint received.
func (fb *fakeBackend) promptsSeen() []string {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	return slices.Clone(fb.prompts)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeFailure(w http.ResponseWriter, forced failure) {
	writeJSON(w, forced.status, map[string]any{"error": map[string]string{"code": forced.code, "message": forced.message}})
}

// user resolves the bearer token. ok is false after a 401 was written for an unknown token or, when required, for a missing one.
func (fb *fakeBackend) user(w http.ResponseWriter, r *http.Request, required bool) (id string, ok bool) {
	header := r.Header.Get("Authorization")
	switch {
	case header == "Bearer "+testToken:
		return testUserID, true
	case header != "" || required:
		writeFailure(w, failure{http.StatusUnauthorized, "AUTH_REQUIRED", "login required"})
		return "", false
	}
	return "", true
}

func (fb *fakeBackend) game(id string) *sdk.Game {
	for _, game := range fb.games {
		if game.ID == id {
			return game
		}
	}
	return nil
}

// effective computes a mod's effective DSL with the shared dsl package, as the real backend does.
func (fb *fakeBackend) effective(modID string) (map[string]any, error) {
	var chain []*sdk.Mod
	for id := modID; id != ""; {
		mod := fb.mods[id]
		if mod == nil {
			return nil, fmt.Errorf("mod %s not found", id)
		}
		chain = append(chain, mod)
		id = mod.ParentID
	}
	slices.Reverse(chain)
	document := fb.baselines[chain[0].Runtime]
	for _, mod := range chain {
		ops := make([]dsl.Op, len(mod.Patch))
		for i, op := range mod.Patch {
			ops[i] = dsl.Op(op)
		}
		patched, err := dsl.Apply(document, ops)
		if err != nil {
			return nil, err
		}
		document = patched
	}
	return document, nil
}

func (fb *fakeBackend) listGames(w http.ResponseWriter, r *http.Request) {
	if _, ok := fb.user(w, r, false); !ok {
		return
	}
	query := r.URL.Query()
	fb.mu.Lock()
	defer fb.mu.Unlock()
	var matched []*sdk.Game
	for _, game := range fb.games {
		if game.Status != sdk.GameStatusPublished {
			continue
		}
		if q := strings.ToLower(query.Get("q")); q != "" && !strings.Contains(strings.ToLower(game.Title), q) {
			continue
		}
		if runtime := query.Get("runtime"); runtime != "" && game.Runtime != runtime && !strings.HasPrefix(game.Runtime, runtime+"@") {
			continue
		}
		if ai := query.Get("ai"); ai != "" && strconv.FormatBool(game.AIGenerated) != ai {
			continue
		}
		matched = append(matched, game)
	}
	if query.Get("sort") == "hot" {
		slices.SortFunc(matched, func(a, b *sdk.Game) int { return b.Likes - a.Likes })
	}
	offset, _ := strconv.Atoi(query.Get("cursor"))
	limit, _ := strconv.Atoi(query.Get("limit"))
	if limit <= 0 {
		limit = 20
	}
	end := min(offset+limit, len(matched))
	page := map[string]any{"items": matched[min(offset, len(matched)):end]}
	if end < len(matched) {
		page["next_cursor"] = strconv.Itoa(end)
	}
	writeJSON(w, http.StatusOK, page)
}

func (fb *fakeBackend) visibleGame(w http.ResponseWriter, r *http.Request) *sdk.Game {
	viewer, ok := fb.user(w, r, false)
	if !ok {
		return nil
	}
	game := fb.game(r.PathValue("id"))
	if game == nil || (game.Status != sdk.GameStatusPublished && game.AuthorID != viewer) {
		writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "game not found"})
		return nil
	}
	return game
}

func (fb *fakeBackend) getGame(w http.ResponseWriter, r *http.Request) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	if game := fb.visibleGame(w, r); game != nil {
		writeJSON(w, http.StatusOK, game)
	}
}

func (fb *fakeBackend) getGameDSL(w http.ResponseWriter, r *http.Request) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	game := fb.visibleGame(w, r)
	if game == nil {
		return
	}
	fb.writeEffective(w, game.ModID)
}

func (fb *fakeBackend) writeEffective(w http.ResponseWriter, modID string) {
	if fb.mods[modID] == nil {
		writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "mods: not found"})
		return
	}
	document, err := fb.effective(modID)
	if err != nil {
		writeFailure(w, failure{http.StatusUnprocessableEntity, "DSL_INVALID", err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, document)
}

func (fb *fakeBackend) forkGame(w http.ResponseWriter, r *http.Request) {
	author, ok := fb.user(w, r, true)
	if !ok {
		return
	}
	fb.mu.Lock()
	defer fb.mu.Unlock()
	game := fb.game(r.PathValue("id"))
	if game == nil || game.Status != sdk.GameStatusPublished {
		writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "game not found"})
		return
	}
	parent := fb.mods[game.ModID]
	if parent == nil {
		writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "mods: not found"})
		return
	}
	game.Forks++
	// The real backend stores a nil patch for a fork, which is encoded as null.
	writeJSON(w, http.StatusCreated, fb.storeMod(&sdk.Mod{ParentID: parent.ID, Runtime: parent.Runtime, AuthorID: author, AIGenerated: parent.AIGenerated, Draft: true}))
}

// readableMod returns the mod named in the path when the caller may read it.
func (fb *fakeBackend) readableMod(w http.ResponseWriter, r *http.Request) *sdk.Mod {
	viewer, ok := fb.user(w, r, false)
	if !ok {
		return nil
	}
	mod := fb.mods[r.PathValue("id")]
	if mod == nil {
		writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "mods: not found"})
		return nil
	}
	if mod.Draft && mod.AuthorID != viewer {
		writeFailure(w, failure{http.StatusForbidden, "FORBIDDEN", "not your draft"})
		return nil
	}
	return mod
}

func (fb *fakeBackend) getModDSL(w http.ResponseWriter, r *http.Request) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	if mod := fb.readableMod(w, r); mod != nil {
		fb.writeEffective(w, mod.ID)
	}
}

func (fb *fakeBackend) getModForkTree(w http.ResponseWriter, r *http.Request) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	if mod := fb.readableMod(w, r); mod != nil {
		writeJSON(w, http.StatusOK, sdk.ForkTree{Node: *mod})
	}
}

func (fb *fakeBackend) createMod(w http.ResponseWriter, r *http.Request) {
	author, ok := fb.user(w, r, true)
	if !ok {
		return
	}
	var request sdk.CreateModRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeFailure(w, failure{http.StatusBadRequest, "BAD_REQUEST", err.Error()})
		return
	}
	fb.mu.Lock()
	defer fb.mu.Unlock()
	mod := &sdk.Mod{Runtime: request.Runtime, Patch: request.Patch, AuthorID: author, AIGenerated: request.AIProvenance == testProvenance, Draft: request.Draft}
	if request.ParentID != "" {
		parent := fb.mods[request.ParentID]
		if parent == nil {
			writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "mods: not found"})
			return
		}
		if parent.Draft && parent.AuthorID != author {
			writeFailure(w, failure{http.StatusForbidden, "FORBIDDEN", "not your draft"})
			return
		}
		mod.ParentID, mod.Runtime, mod.AIGenerated = parent.ID, parent.Runtime, mod.AIGenerated || parent.AIGenerated
	}
	writeJSON(w, http.StatusCreated, fb.storeMod(mod))
}

func (fb *fakeBackend) listDrafts(w http.ResponseWriter, r *http.Request) {
	author, ok := fb.user(w, r, true)
	if !ok {
		return
	}
	fb.mu.Lock()
	defer fb.mu.Unlock()
	drafts := []*sdk.Mod{}
	for _, id := range slices.Backward(fb.modOrder) {
		if mod := fb.mods[id]; mod.Draft && mod.AuthorID == author {
			drafts = append(drafts, mod)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": drafts})
}

func (fb *fakeBackend) publishDraft(w http.ResponseWriter, r *http.Request) {
	author, ok := fb.user(w, r, true)
	if !ok {
		return
	}
	var request sdk.PublishDraftRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeFailure(w, failure{http.StatusBadRequest, "BAD_REQUEST", err.Error()})
		return
	}
	fb.mu.Lock()
	defer fb.mu.Unlock()
	mod := fb.mods[r.PathValue("id")]
	switch {
	case mod == nil:
		writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "mods: not found"})
	case !mod.Draft:
		writeFailure(w, failure{http.StatusConflict, "INVALID_STATE", "not a draft"})
	case mod.AuthorID != author:
		writeFailure(w, failure{http.StatusForbidden, "FORBIDDEN", "not your draft"})
	case request.Title == "" || len(request.Tags) > 3:
		writeFailure(w, failure{http.StatusBadRequest, "PUBLISH_INVALID", "title is required and at most 3 tags are allowed"})
	default:
		mod.Draft = false
		game := &sdk.Game{
			ID: fmt.Sprintf("g_%d", len(fb.games)+1), ModID: mod.ID, AuthorID: author, By: "Tester", ForkedFrom: request.ForkedFrom, Title: request.Title, Summary: request.Summary, Tags: request.Tags,
			Status: sdk.GameStatusReviewing, AIGenerated: request.AIGenerated || mod.AIGenerated, Runtime: mod.Runtime, Category: request.Category, CreatedAt: time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC),
		}
		fb.games = append(fb.games, game)
		writeJSON(w, http.StatusCreated, game)
	}
}

func (fb *fakeBackend) getBaseline(w http.ResponseWriter, r *http.Request) {
	fb.mu.Lock()
	defer fb.mu.Unlock()
	document, ok := fb.baselines[r.PathValue("name")+"@"+r.PathValue("version")]
	if !ok {
		writeFailure(w, failure{http.StatusNotFound, "NOT_FOUND", "runtime not found"})
		return
	}
	writeJSON(w, http.StatusOK, document)
}

// generateMod answers like the backend's stub AI provider: a fixed patch that turns the shooter player into a cat.
func (fb *fakeBackend) generateMod(w http.ResponseWriter, r *http.Request) {
	if _, ok := fb.user(w, r, false); !ok {
		return
	}
	var request sdk.GenerateModRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil || request.CurrentDSL == nil || request.Prompt == "" {
		writeFailure(w, failure{http.StatusBadRequest, "BAD_REQUEST", "runtime, current_dsl and prompt are required"})
		return
	}
	fb.mu.Lock()
	fb.prompts = append(fb.prompts, request.Runtime+": "+request.Prompt)
	fb.mu.Unlock()
	patch := []sdk.PatchOp{{Op: "replace", Path: "/player/sprite", Value: json.RawMessage(`"cat"`)}}
	patched, err := dsl.Apply(request.CurrentDSL, []dsl.Op{dsl.Op(patch[0])})
	if err != nil {
		writeFailure(w, failure{http.StatusUnprocessableEntity, "DSL_INVALID", err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, sdk.GenerateModResponse{DSLPatch: patch, NewDSL: patched, BalanceHint: "the cat is smaller than the plane", Model: "stub", Provenance: testProvenance})
}
