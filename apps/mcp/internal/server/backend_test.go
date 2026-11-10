package server_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
)

const authRequiredMessage = "authentication required: set CLASSIC_GAMES_TOKEN (obtain with: classic-games auth login, then classic-games auth token)"

type gamesOut struct {
	Games      []gameOut `json:"games"`
	NextCursor string    `json:"next_cursor"`
	HasMore    bool      `json:"has_more"`
}

type draftsOut struct {
	Drafts []modOut `json:"drafts"`
	Total  int      `json:"total"`
}

type generatedOut struct {
	Runtime     string         `json:"runtime"`
	Patch       []patchOp      `json:"patch"`
	DSL         map[string]any `json:"dsl"`
	BalanceHint string         `json:"balance_hint"`
	Model       string         `json:"model"`
	Retries     int            `json:"retries"`
	Provenance  string         `json:"provenance"`
}

func titles(games []gameOut) []string {
	out := make([]string, len(games))
	for i, game := range games {
		out[i] = game.Title
	}
	return out
}

func TestListGames(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL})

	all := call[gamesOut](t, cs, "list_games", map[string]any{})
	if want := []string{"Neon Shooter", "Cat Survivor", "Desert Defense"}; !slices.Equal(titles(all.Games), want) || all.HasMore || all.NextCursor != "" {
		t.Fatalf("list_games = %v next=%q more=%v, want %v on a single page", titles(all.Games), all.NextCursor, all.HasMore, want)
	}
	first := all.Games[0]
	if first.GameID != "g_1" || first.Author != "Ada" || first.Runtime != "shooter@1.0.0" || first.Category != "arcade" || !slices.Equal(first.Tags, []string{"arcade"}) || first.Likes != 10 || first.Plays != 100 {
		t.Errorf("first game = %+v", first)
	}
	if first.Status != "" || first.ModID != "" {
		t.Errorf("a listing entry must stay compact, got detail fields: %+v", first)
	}

	// Pagination: a small page carries a cursor that leads to the rest.
	page := call[gamesOut](t, cs, "list_games", map[string]any{"limit": 2})
	if len(page.Games) != 2 || !page.HasMore || page.NextCursor == "" {
		t.Fatalf("limit 2 = %d games next=%q more=%v, want 2 games and a cursor", len(page.Games), page.NextCursor, page.HasMore)
	}
	rest := call[gamesOut](t, cs, "list_games", map[string]any{"limit": 2, "cursor": page.NextCursor})
	if !slices.Equal(titles(rest.Games), []string{"Desert Defense"}) || rest.HasMore {
		t.Errorf("second page = %v more=%v, want the last game only", titles(rest.Games), rest.HasMore)
	}

	// Filters are passed through to the backend.
	if found := call[gamesOut](t, cs, "list_games", map[string]any{"query": "cat"}); !slices.Equal(titles(found.Games), []string{"Cat Survivor"}) {
		t.Errorf("query cat = %v", titles(found.Games))
	}
	if found := call[gamesOut](t, cs, "list_games", map[string]any{"runtime": "tower_defense", "sort": "hot"}); !slices.Equal(titles(found.Games), []string{"Desert Defense"}) {
		t.Errorf("runtime tower_defense = %v", titles(found.Games))
	}
	if found := call[gamesOut](t, cs, "list_games", map[string]any{"ai_generated": false, "sort": "hot"}); !slices.Equal(titles(found.Games), []string{"Desert Defense", "Neon Shooter"}) {
		t.Errorf("ai_generated=false sorted by hot = %v", titles(found.Games))
	}
	if empty := call[gamesOut](t, cs, "list_games", map[string]any{"query": "no such game"}); empty.Games == nil || len(empty.Games) != 0 {
		t.Errorf("an empty result must be an empty list, got %v", empty.Games)
	}

	// Out-of-range arguments are rejected by the input schema before any request is sent.
	before := len(fb.seen())
	mustContain(t, callError(t, cs, "list_games", map[string]any{"limit": 500}), "limit")
	mustContain(t, callError(t, cs, "list_games", map[string]any{"sort": "random"}), "sort")
	if len(fb.seen()) != before {
		t.Error("invalid arguments reached the backend")
	}
}

func TestListGamesDefaultLimit(t *testing.T) {
	var query string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query = r.URL.RawQuery
		writeJSON(w, http.StatusOK, map[string]any{"items": []any{}})
	}))
	defer backend.Close()
	call[gamesOut](t, connect(t, session{backendURL: backend.URL}), "list_games", map[string]any{})
	if query != "limit=10" {
		t.Errorf("backend query = %q, want the small default page limit=10", query)
	}
}

func TestGetGameAndDSL(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL})

	game := call[gameOut](t, cs, "get_game", map[string]any{"game_id": "g_2"})
	if game.Title != "Cat Survivor" || game.Status != "published" || game.ModID != "m_2" || game.AuthorID != "u_seed" || !game.AIGenerated || game.CreatedAt != "2026-01-02T00:00:00Z" {
		t.Errorf("get_game = %+v", game)
	}

	out := call[dslOut](t, cs, "get_game_dsl", map[string]any{"game_id": "g_2"})
	if out.GameID != "g_2" || out.Runtime != "survivor@1.0.0" || at(t, out.DSL, "hero", "sprite") != "mage" {
		t.Errorf("get_game_dsl = %+v", out)
	}
	// The effective DSL of a real game validates with the offline tool.
	if check := call[validationOut](t, cs, "validate_dsl", map[string]any{"dsl": out.DSL}); !check.Valid {
		t.Errorf("game DSL does not validate: %+v", check)
	}

	for _, tool := range []string{"get_game", "get_game_dsl"} {
		message := callError(t, cs, tool, map[string]any{"game_id": "g_404"})
		mustContain(t, message, `"g_404"`, "404 NOT_FOUND", "game not found", "list_games returns game ids")
	}
}

// TestShowcaseGameWithoutDSL covers the games a development backend is seeded with: they are listed and have details, but no mod, so the DSL endpoint answers 404 for a game that does exist.
func TestShowcaseGameWithoutDSL(t *testing.T) {
	fb := newFakeBackend(t)
	fb.addShowcaseGame("ashfall", "Ashfall Kingdom")
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})

	listed := call[gamesOut](t, cs, "list_games", map[string]any{"query": "ashfall"})
	if len(listed.Games) != 1 || listed.Games[0].Runtime != "" {
		t.Fatalf("showcase game listing = %+v", listed.Games)
	}
	if game := call[gameOut](t, cs, "get_game", map[string]any{"game_id": "ashfall"}); game.Title != "Ashfall Kingdom" {
		t.Errorf("get_game = %+v", game)
	}
	for tool, arguments := range map[string]map[string]any{
		"get_game_dsl": {"game_id": "ashfall"},
		"fork_game":    {"game_id": "ashfall"},
		"generate_mod": {"game_id": "ashfall", "instruction": "more lava"},
	} {
		mustContain(t, callError(t, cs, tool, arguments), `game "ashfall" (Ashfall Kingdom) is listed but the backend holds no DSL for it`, "create_mod")
	}
	if fb.count("POST /api/v1/games/ashfall/fork") != 0 || fb.count("POST /api/v1/ai/mod") != 0 {
		t.Errorf("a game without a DSL was forked or sent to the AI: %v", fb.seen())
	}
}

func TestBackendUnreachable(t *testing.T) {
	backend := httptest.NewServer(http.NotFoundHandler())
	url := backend.URL
	backend.Close()
	message := callError(t, connect(t, session{backendURL: url}), "list_games", map[string]any{})
	mustContain(t, message, "cannot reach the Classic Games backend at "+url, "CLASSIC_GAMES_SERVER_URL")
}

func TestBackendFailureHints(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})

	fb.fail("GET /api/v1/games", failure{http.StatusInternalServerError, "INTERNAL", "boom"})
	mustContain(t, callError(t, cs, "list_games", map[string]any{}), "500 INTERNAL: boom", "backend failure", "Retry later")

	fb.fail("POST /api/v1/ai/mod", failure{http.StatusTooManyRequests, "QUOTA_EXCEEDED", "daily quota used"})
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "more enemies", "game_id": "g_1"}), "429 QUOTA_EXCEEDED", "quota is used up", "update_mod")

	fb.fail("POST /api/v1/ai/mod", failure{http.StatusUnprocessableEntity, "DSL_INVALID", "model output invalid"})
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "more enemies", "game_id": "g_1"}), "422 DSL_INVALID", "rephrase the instruction")

	fb.fail("POST /api/v1/ai/mod", failure{http.StatusBadGateway, "PROVIDER_ERROR", "upstream down"})
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "more enemies", "game_id": "g_1"}), "502 PROVIDER_ERROR", "AI provider failed")

	// A response that is not an error envelope still yields a readable message, which says that the answer did not come from a Classic Games backend.
	plain := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "upstream proxy error", http.StatusBadGateway)
	}))
	defer plain.Close()
	mustContain(t, callError(t, connect(t, session{backendURL: plain.URL}), "get_game", map[string]any{"game_id": "g_1"}), `get game "g_1"`, "502 Bad Gateway", `"upstream proxy error"`, "not a Classic Games API error", "CLASSIC_GAMES_SERVER_URL")
}

// A wrong CLASSIC_GAMES_SERVER_URL or a proxy error page must not put a whole HTML page into the model's context.
func TestForeignAnswersAreNotRelayed(t *testing.T) {
	page := "<html><body>" + strings.Repeat("<p>login required</p>", 5000) + "</body></html>"
	notFound := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, page)
	}))
	defer notFound.Close()
	message := callError(t, connect(t, session{backendURL: notFound.URL}), "get_game", map[string]any{"game_id": "g_1"})
	mustContain(t, message, "404 Not Found", "<html><body><p>login required</p>", "CLASSIC_GAMES_SERVER_URL")
	if len(message) > 1000 {
		t.Errorf("the tool error holds %d bytes of a %d byte page, want at most 1000", len(message), len(page))
	}
	if strings.Contains(message, "list_games returns game ids") {
		t.Errorf("a foreign 404 got the hint for a Classic Games 404: %q", message)
	}

	// A 200 that is not JSON is an answer, so the backend was reached; the message must not send the agent after a connection problem.
	html := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		_, _ = io.WriteString(w, page)
	}))
	defer html.Close()
	message = callError(t, connect(t, session{backendURL: html.URL}), "get_game", map[string]any{"game_id": "g_1"})
	mustContain(t, message, "answered, but not like a Classic Games backend", "CLASSIC_GAMES_SERVER_URL")
	if strings.Contains(message, "cannot reach") || len(message) > 1000 {
		t.Errorf("a 200 text/html answer was reported as %q", message)
	}

	// An envelope with an oversized message is capped as well.
	fb := newFakeBackend(t)
	fb.fail("GET /api/v1/games", failure{http.StatusBadRequest, "BAD_REQUEST", strings.Repeat("长", 5000)})
	message = callError(t, connect(t, session{backendURL: fb.server.URL}), "list_games", map[string]any{})
	mustContain(t, message, "400 BAD_REQUEST: 长长长", "(4000 more characters)")
}

// Credentials in CLASSIC_GAMES_SERVER_URL (a backend behind basic auth) belong neither in a tool result nor in the log.
func TestBackendURLCredentialsStayOutOfToolErrors(t *testing.T) {
	cs := connect(t, session{backendURL: "http://user:secret@127.0.0.1:1"})
	message := callError(t, cs, "list_games", map[string]any{})
	mustContain(t, message, "cannot reach the Classic Games backend at http://127.0.0.1:1", "CLASSIC_GAMES_SERVER_URL")
	for _, leaked := range []string{"secret", "user:", "user@"} {
		if strings.Contains(message, leaked) {
			t.Errorf("the tool error contains %q: %q", leaked, message)
		}
	}
}

// "mine" is a fixed route of the backend (the caller's own games), which answers 200 with a listing. It is not a game, and it must not be reported as an empty game or as a showcase entry.
func TestReservedWordIsNotAGame(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})
	for tool, arguments := range map[string]map[string]any{
		"get_game":     {"game_id": "mine"},
		"get_game_dsl": {"game_id": "mine"},
		"fork_game":    {"game_id": "mine"},
		"generate_mod": {"game_id": "mine", "instruction": "more lava"},
	} {
		message := callError(t, cs, tool, arguments)
		mustContain(t, message, `"mine"`, "404 NOT_FOUND", "list_games returns game ids")
		if strings.Contains(message, "showcase") {
			t.Errorf("%s: %q calls the reserved word a showcase game", tool, message)
		}
	}
	if fb.count("POST /api/v1/games/mine/fork") != 0 || fb.count("POST /api/v1/ai/mod") != 0 {
		t.Errorf("the reserved word was forked or sent to the AI: %v", fb.seen())
	}
}

// A blank id is refused by input validation, and an id that would address another route by the client; neither is a connection problem and neither reaches the backend.
func TestUnusableIDsAreRejectedBeforeAnyRequest(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})
	patch := []patchOp{{Op: "replace", Path: "/player/hp", Value: 150}}
	for tool, arguments := range map[string]map[string]any{
		"get_game":     {"game_id": ""},
		"get_game_dsl": {"game_id": ""},
		"get_mod_dsl":  {"mod_id": ""},
		"fork_game":    {"game_id": ""},
		"update_mod":   {"mod_id": "", "patch": patch},
		"publish_mod":  {"mod_id": "", "title": "Ok"},
	} {
		message := callError(t, cs, tool, arguments)
		mustContain(t, message, "_id")
		if strings.Contains(message, "cannot reach") {
			t.Errorf("%s with an empty id was reported as a connection problem: %q", tool, message)
		}
	}
	for tool, arguments := range map[string]map[string]any{
		"get_game":     {"game_id": "g_1/comments"},
		"get_game_dsl": {"game_id": "../mods"},
		"get_mod_dsl":  {"mod_id": "m_1/fork"},
		"update_mod":   {"mod_id": "..", "patch": patch},
		"publish_mod":  {"mod_id": "m_1/x", "title": "Ok"},
	} {
		message := callError(t, cs, tool, arguments)
		mustContain(t, message, "no request was sent", "invalid path parameter", "exactly as a tool returned it")
		if strings.Contains(message, "cannot reach") {
			t.Errorf("%s with a path-changing id was reported as a connection problem: %q", tool, message)
		}
	}
	if requests := fb.seen(); len(requests) != 0 {
		t.Errorf("unusable ids reached the backend: %v", requests)
	}
}

func TestWriteToolsRequireToken(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL})
	calls := map[string]map[string]any{
		"fork_game":      {"game_id": "g_1"},
		"create_mod":     {"runtime": "shooter@1.0.0"},
		"update_mod":     {"mod_id": "m_1", "patch": []patchOp{{Op: "replace", Path: "/player/hp", Value: 150}}},
		"publish_mod":    {"mod_id": "m_1", "title": "My game"},
		"list_my_drafts": {},
	}
	for tool, arguments := range calls {
		if message := callError(t, cs, tool, arguments); message != authRequiredMessage {
			t.Errorf("%s without a token: %q, want %q", tool, message, authRequiredMessage)
		}
	}
	if requests := fb.seen(); len(requests) != 0 {
		t.Errorf("tools that need a token contacted the backend without one: %v", requests)
	}
}

func TestRejectedToken(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: "expired-token"})
	message := callError(t, cs, "fork_game", map[string]any{"game_id": "g_1"})
	mustContain(t, message, "401 AUTH_REQUIRED", "The token in CLASSIC_GAMES_TOKEN was rejected", "classic-games auth login", "classic-games auth token")
	if strings.Contains(message, "expired-token") {
		t.Errorf("the error message leaks the token: %q", message)
	}
}

// TestForkPatchPublishWorkflow walks the whole write path the server instructions describe, with a patch written by the agent and one produced by the backend AI.
func TestForkPatchPublishWorkflow(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})

	// Fork: a draft owned by the caller whose DSL equals the game's.
	fork := call[modOut](t, cs, "fork_game", map[string]any{"game_id": "g_1"})
	if fork.ModID == "" || fork.ParentModID != "m_1" || !fork.Draft || fork.Runtime != "shooter@1.0.0" || fork.ForkedFrom != "g_1" || fork.PatchOpCount != 0 {
		t.Fatalf("fork_game = %+v", fork)
	}
	if !jsonEqual(fork.DSL, baseline(t, "shooter")) {
		t.Error("the fork's DSL differs from the game's")
	}
	if forked := call[gameOut](t, cs, "get_game", map[string]any{"game_id": "g_1"}); forked.Forks != 1 {
		t.Errorf("fork count = %d, want 1", forked.Forks)
	}

	// Patch written by the agent: saved as a new immutable version.
	updated := call[modOut](t, cs, "update_mod", map[string]any{"mod_id": fork.ModID, "patch": []patchOp{
		{Op: "replace", Path: "/player/hp", Value: 150},
		{Op: "replace", Path: "/stage/background", Value: "lava"},
	}})
	if updated.ModID == fork.ModID || updated.ParentModID != fork.ModID || !updated.Draft || updated.PatchOpCount != 2 || updated.AIGenerated {
		t.Fatalf("update_mod = %+v", updated)
	}
	if at(t, updated.DSL, "player", "hp") != float64(150) || at(t, updated.DSL, "stage", "background") != "lava" {
		t.Errorf("update_mod DSL does not carry the patch: %v", updated.DSL)
	}

	// The backend computes the same effective DSL the tool returned.
	stored := call[dslOut](t, cs, "get_mod_dsl", map[string]any{"mod_id": updated.ModID})
	if stored.ModID != updated.ModID || stored.Runtime != "shooter@1.0.0" || !jsonEqual(stored.DSL, updated.DSL) {
		t.Errorf("get_mod_dsl differs from the DSL update_mod returned")
	}

	// Patch produced by the backend AI from the draft, then saved with its provenance value.
	generated := call[generatedOut](t, cs, "generate_mod", map[string]any{"instruction": "make the player a cat", "mod_id": updated.ModID})
	if generated.Runtime != "shooter@1.0.0" || generated.Model != "stub" || generated.Provenance != testProvenance || generated.BalanceHint == "" || len(generated.Patch) != 1 {
		t.Fatalf("generate_mod = %+v", generated)
	}
	if generated.Patch[0] != (patchOp{Op: "replace", Path: "/player/sprite", Value: "cat"}) {
		t.Errorf("generated patch = %+v", generated.Patch)
	}
	if at(t, generated.DSL, "player", "sprite") != "cat" || at(t, generated.DSL, "player", "hp") != float64(150) {
		t.Errorf("generated DSL must be the draft's DSL with the patch applied: %v", generated.DSL)
	}
	if got, want := fb.promptsSeen(), []string{"shooter@1.0.0: make the player a cat"}; !slices.Equal(got, want) {
		t.Errorf("backend prompts = %v, want %v", got, want)
	}
	if fb.count("POST /api/v1/mods") != 1 {
		t.Error("generate_mod must not store anything")
	}
	final := call[modOut](t, cs, "update_mod", map[string]any{"mod_id": updated.ModID, "patch": generated.Patch, "ai_provenance": generated.Provenance})
	if final.ParentModID != updated.ModID || !final.AIGenerated || !jsonEqual(final.DSL, generated.DSL) {
		t.Fatalf("update_mod with provenance = %+v", final)
	}

	// Every version is listed as a draft, newest first.
	drafts := call[draftsOut](t, cs, "list_my_drafts", map[string]any{})
	var ids []string
	for _, draft := range drafts.Drafts {
		ids = append(ids, draft.ModID)
	}
	if want := []string{final.ModID, updated.ModID, fork.ModID}; drafts.Total != 3 || !slices.Equal(ids, want) {
		t.Errorf("list_my_drafts = %v (total %d), want %v", ids, drafts.Total, want)
	}
	if newest := call[draftsOut](t, cs, "list_my_drafts", map[string]any{"limit": 1}); newest.Total != 3 || len(newest.Drafts) != 1 || newest.Drafts[0].ModID != final.ModID {
		t.Errorf("list_my_drafts limit 1 = %+v", newest)
	}

	// Publish: the game enters moderation.
	game := call[gameOut](t, cs, "publish_mod", map[string]any{"mod_id": final.ModID, "title": "  Lava Cat  ", "summary": "A cat over lava", "tags": []string{"cat", "lava"}, "category": "arcade", "forked_from": fork.ForkedFrom})
	if game.GameID == "" || game.Status != "reviewing" || game.Title != "Lava Cat" || game.ModID != final.ModID || game.ForkedFrom != "g_1" || !game.AIGenerated || !slices.Equal(game.Tags, []string{"cat", "lava"}) {
		t.Fatalf("publish_mod = %+v", game)
	}
	// A game under review is not listed publicly, but its author can read it.
	if listed := call[gamesOut](t, cs, "list_games", map[string]any{}); slices.Contains(titles(listed.Games), "Lava Cat") {
		t.Error("a game under review appears in the public listing")
	}
	if own := call[gameOut](t, cs, "get_game", map[string]any{"game_id": game.GameID}); own.Status != "reviewing" {
		t.Errorf("author's view of the new game = %+v", own)
	}

	// The published mod is no longer a draft: updating and publishing it again are refused with a way forward.
	posts := fb.count("POST /api/v1/mods")
	mustContain(t, callError(t, cs, "update_mod", map[string]any{"mod_id": final.ModID, "patch": []patchOp{{Op: "replace", Path: "/player/hp", Value: 90}}}), "is not a draft", "fork_game")
	if fb.count("POST /api/v1/mods") != posts {
		t.Error("an update of a published mod was sent to the backend")
	}
	mustContain(t, callError(t, cs, "publish_mod", map[string]any{"mod_id": final.ModID, "title": "Again"}), "409 INVALID_STATE", "not a draft any more")
}

func TestUpdateModRejectsBeforeSaving(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})
	fork := call[modOut](t, cs, "fork_game", map[string]any{"game_id": "g_1"})
	posts := fb.count("POST /api/v1/mods")

	// A patch whose result breaks the schema: the violations come back and nothing is stored.
	message := callError(t, cs, "update_mod", map[string]any{"mod_id": fork.ModID, "patch": []patchOp{
		{Op: "replace", Path: "/player/hp", Value: 5000},
		{Op: "replace", Path: "/player/sprite", Value: "dinosaur"},
		{Op: "add", Path: "/player/shield", Value: true},
	}})
	mustContain(t, message, "nothing was saved", "breaks the shooter@1.0.0 schema in 3 place(s)", "- /player: ", "- /player/hp: ", "- /player/sprite: ", "get_dsl_schema")

	// A patch that does not apply to the draft's current DSL.
	message = callError(t, cs, "update_mod", map[string]any{"mod_id": fork.ModID, "patch": []patchOp{{Op: "remove", Path: "/enemies/ghost_9"}}})
	mustContain(t, message, "nothing was saved", `patch operation 1 (remove "/enemies/ghost_9") does not apply`)

	// An empty patch is rejected by the input schema.
	mustContain(t, callError(t, cs, "update_mod", map[string]any{"mod_id": fork.ModID, "patch": []patchOp{}}), "patch")

	if fb.count("POST /api/v1/mods") != posts {
		t.Errorf("a rejected update reached POST /api/v1/mods: %v", fb.seen())
	}
	// The draft is untouched and still accepts a correct patch.
	if stored := call[dslOut](t, cs, "get_mod_dsl", map[string]any{"mod_id": fork.ModID}); !jsonEqual(stored.DSL, baseline(t, "shooter")) {
		t.Error("a rejected update changed the draft")
	}
	call[modOut](t, cs, "update_mod", map[string]any{"mod_id": fork.ModID, "patch": []patchOp{{Op: "replace", Path: "/player/hp", Value: 500}}})

	mustContain(t, callError(t, cs, "update_mod", map[string]any{"mod_id": "m_404", "patch": []patchOp{{Op: "replace", Path: "/player/hp", Value: 1}}}), `read mod "m_404"`, "404 NOT_FOUND")
}

func TestDraftsArePrivate(t *testing.T) {
	fb := newFakeBackend(t)
	owner := connect(t, session{backendURL: fb.server.URL, token: testToken})
	fork := call[modOut](t, owner, "fork_game", map[string]any{"game_id": "g_3"})

	anonymous := connect(t, session{backendURL: fb.server.URL})
	message := callError(t, anonymous, "get_mod_dsl", map[string]any{"mod_id": fork.ModID})
	mustContain(t, message, "403 FORBIDDEN", "private to their author", authRequiredMessage)

	// A published mod is readable without a token.
	if public := call[dslOut](t, anonymous, "get_mod_dsl", map[string]any{"mod_id": "m_3"}); at(t, public.DSL, "stage", "background") != "desert" {
		t.Errorf("public mod DSL = %v", public.DSL)
	}
}

func TestCreateMod(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})

	// Without a patch the draft is the unmodified baseline.
	blank := call[modOut](t, cs, "create_mod", map[string]any{"runtime": "survivor@1.0.0"})
	if blank.ModID == "" || blank.ParentModID != "" || !blank.Draft || blank.Runtime != "survivor@1.0.0" || blank.PatchOpCount != 0 || !jsonEqual(blank.DSL, baseline(t, "survivor")) {
		t.Fatalf("create_mod without a patch = %+v", blank)
	}

	patched := call[modOut](t, cs, "create_mod", map[string]any{"runtime": "tower_defense@1.0.0", "patch": []patchOp{{Op: "replace", Path: "/stage/starting_gold", Value: 900}}})
	if patched.PatchOpCount != 1 || at(t, patched.DSL, "stage", "starting_gold") != float64(900) {
		t.Fatalf("create_mod with a patch = %+v", patched)
	}
	if stored := call[dslOut](t, cs, "get_mod_dsl", map[string]any{"mod_id": patched.ModID}); !jsonEqual(stored.DSL, patched.DSL) {
		t.Error("the stored DSL differs from the one create_mod returned")
	}

	posts := fb.count("POST /api/v1/mods")
	mustContain(t, callError(t, cs, "create_mod", map[string]any{"runtime": "tower_defense@1.0.0", "patch": []patchOp{{Op: "replace", Path: "/stage/base_hp", Value: 0}}}), "nothing was saved", "- /stage/base_hp: ")
	// An unknown runtime is not an id problem: the hint points at list_runtimes, not at the game and mod listings.
	unknownRuntime := callError(t, cs, "create_mod", map[string]any{"runtime": "racing@1.0.0"})
	mustContain(t, unknownRuntime, `the backend has no runtime "racing@1.0.0"`, "list_runtimes", "shooter@1.0.0, survivor@1.0.0, tower_defense@1.0.0")
	if strings.Contains(unknownRuntime, "list_games") {
		t.Errorf("an unknown runtime got the hint about game ids: %q", unknownRuntime)
	}
	mustContain(t, callError(t, cs, "create_mod", map[string]any{"runtime": "shooter"}), "not a runtime ref", "shooter@1.0.0")
	if fb.count("POST /api/v1/mods") != posts {
		t.Error("a rejected create_mod reached POST /api/v1/mods")
	}
}

func TestGenerateModSources(t *testing.T) {
	fb := newFakeBackend(t)
	// generate_mod needs no token: the backend meters anonymous callers by IP address.
	cs := connect(t, session{backendURL: fb.server.URL})

	fromGame := call[generatedOut](t, cs, "generate_mod", map[string]any{"instruction": "cat please", "game_id": "g_1"})
	if at(t, fromGame.DSL, "player", "sprite") != "cat" || fromGame.Retries != 0 {
		t.Errorf("generate_mod from a game = %+v", fromGame)
	}

	document := baseline(t, "shooter")
	document["player"].(map[string]any)["hp"] = 321
	fromDocument := call[generatedOut](t, cs, "generate_mod", map[string]any{"instruction": "cat please", "dsl": document})
	if at(t, fromDocument.DSL, "player", "hp") != float64(321) || at(t, fromDocument.DSL, "player", "sprite") != "cat" {
		t.Errorf("generate_mod from a document = %v", fromDocument.DSL)
	}

	before := fb.count("POST /api/v1/ai/mod")
	// A document the backend could only answer with 422 is refused locally, because the backend bills the generation anyway.
	invalid := baseline(t, "shooter")
	invalid["junk"] = 1
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "cat please", "dsl": invalid}), "no AI quota was spent", "breaks the shooter@1.0.0 schema in 1 place(s)", "junk")
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "cat please", "dsl": baseline(t, "shooter"), "runtime": "survivor@1.0.0"}), "no AI quota was spent", "breaks the survivor@1.0.0 schema")
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "cat please", "dsl": baseline(t, "shooter"), "runtime": "racing@1.0.0"}), "no AI quota was spent", `no schema for runtime "racing@1.0.0"`)
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "cat please"}), "exactly one source document", "got 0")
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "cat please", "game_id": "g_1", "dsl": document}), "exactly one source document", "got 2")
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "   ", "game_id": "g_1"}), "instruction is empty")
	mustContain(t, callError(t, cs, "generate_mod", map[string]any{"instruction": "cat please", "game_id": "g_404"}), `get the DSL of game "g_404"`, "404 NOT_FOUND")
	if fb.count("POST /api/v1/ai/mod") != before {
		t.Error("an invalid generate_mod call spent AI quota")
	}
}

func TestPublishModErrors(t *testing.T) {
	fb := newFakeBackend(t)
	cs := connect(t, session{backendURL: fb.server.URL, token: testToken})
	fork := call[modOut](t, cs, "fork_game", map[string]any{"game_id": "g_1"})

	mustContain(t, callError(t, cs, "publish_mod", map[string]any{"mod_id": fork.ModID, "title": ""}), "title")
	mustContain(t, callError(t, cs, "publish_mod", map[string]any{"mod_id": fork.ModID, "title": "   "}), "title is empty")
	mustContain(t, callError(t, cs, "publish_mod", map[string]any{"mod_id": fork.ModID, "title": "Ok", "tags": []string{"a", "b", "c", "d"}}), "tags")
	if fb.count("POST /api/v1/drafts/"+fork.ModID+"/publish") != 0 {
		t.Error("an invalid publish request reached the backend")
	}

	fb.fail("POST /api/v1/drafts/"+fork.ModID+"/publish", failure{http.StatusBadRequest, "PUBLISH_INVALID", "effective DSL is invalid"})
	mustContain(t, callError(t, cs, "publish_mod", map[string]any{"mod_id": fork.ModID, "title": "Ok"}), "400 PUBLISH_INVALID: effective DSL is invalid", "validate_dsl")

	mustContain(t, callError(t, cs, "publish_mod", map[string]any{"mod_id": "m_404", "title": "Ok"}), `publish mod "m_404"`, "404 NOT_FOUND")
}
