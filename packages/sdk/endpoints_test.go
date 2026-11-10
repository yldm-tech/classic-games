package sdk_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"slices"
	"sync"
	"testing"
	"time"

	"forgeplay/sdk"
)

const (
	testToken     = "tok-123"
	testUserAgent = "sdk-test/1.0"
)

// recorded is what the fake backend saw for one request.
type recorded struct {
	method string
	path   string
	query  url.Values
	header http.Header
	body   []byte
}

// fakeBackend answers every request with a fixed status and body. The returned function reports the requests received so far.
func fakeBackend(t *testing.T, status int, response string) (*httptest.Server, func() []recorded) {
	t.Helper()
	var (
		mu   sync.Mutex
		seen []recorded
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("read request body: %v", err)
		}
		mu.Lock()
		seen = append(seen, recorded{method: r.Method, path: r.URL.EscapedPath(), query: r.URL.Query(), header: r.Header.Clone(), body: body})
		mu.Unlock()
		if response != "" {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
		}
		w.WriteHeader(status)
		_, _ = io.WriteString(w, response)
	}))
	t.Cleanup(server.Close)
	return server, func() []recorded {
		mu.Lock()
		defer mu.Unlock()
		return slices.Clone(seen)
	}
}

func newClient(t *testing.T, baseURL string, options ...sdk.Option) *sdk.Client {
	t.Helper()
	client, err := sdk.New(baseURL, options...)
	if err != nil {
		t.Fatalf("sdk.New(%q): %v", baseURL, err)
	}
	return client
}

func assertJSONEqual(t *testing.T, label string, got []byte, want string) {
	t.Helper()
	var gotValue, wantValue any
	if err := json.Unmarshal(got, &gotValue); err != nil {
		t.Fatalf("%s: got is not JSON (%v): %q", label, err, got)
	}
	if err := json.Unmarshal([]byte(want), &wantValue); err != nil {
		t.Fatalf("%s: want is not JSON (%v): %q", label, err, want)
	}
	if !reflect.DeepEqual(gotValue, wantValue) {
		t.Errorf("%s:\n got  %s\n want %s", label, got, want)
	}
}

func boolPtr(value bool) *bool { return &value }
func intPtr(value int) *int    { return &value }

var createdAt = time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)

const (
	modJSON     = `{"id":"mod_1","parent_id":"mod_0","runtime":"shooter@1.0.0","patch":[{"op":"replace","path":"/player/sprite","value":"cat"}],"ai_generated":true,"author_id":"u1","created_at":"2026-01-02T03:04:05Z","draft":true}`
	gameJSON    = `{"id":"g1","mod_id":"mod_1","author_id":"u1","by":"@u1","forked_from":"g0","title":"Ashfall","summary":"Dodge the ash","tags":["arcade","fast"],"status":"published","ai_generated":true,"runtime":"shooter@1.0.0","created_at":"2026-01-02T03:04:05Z","tone":"ember","cat":"Arcade","ver":"1.2","plays":10,"forks":2,"likes":7,"views":30}`
	dslJSON     = `{"meta":{"runtime":"shooter","runtime_version":"1.0.0"},"player":{"sprite":"cat","speed":220}}`
	commentJSON = `{"id":"c1","game_id":"g1","author_id":"u1","content":"nice","created_at":"2026-01-02T03:04:05Z"}`
	replayJSON  = `{"id":"replay_1","game_id":"g1","user_id":"u1","duration_ms":2000,"frames":[{"at_ms":0,"x":1.5,"y":2,"hp":3,"score":0},{"at_ms":1000,"x":2,"y":2.5,"hp":2,"score":40}],"score":40,"created_at":"2026-01-02T03:04:05Z"}`
)

var (
	wantPatch = []sdk.PatchOp{{Op: "replace", Path: "/player/sprite", Value: json.RawMessage(`"cat"`)}}
	wantMod   = sdk.Mod{ID: "mod_1", ParentID: "mod_0", Runtime: "shooter@1.0.0", Patch: wantPatch, AIGenerated: true, AuthorID: "u1", CreatedAt: createdAt, Draft: true}
	wantGame  = sdk.Game{ID: "g1", ModID: "mod_1", AuthorID: "u1", By: "@u1", ForkedFrom: "g0", Title: "Ashfall", Summary: "Dodge the ash", Tags: []string{"arcade", "fast"}, Status: sdk.GameStatusPublished, AIGenerated: true, Runtime: "shooter@1.0.0", CreatedAt: createdAt, Tone: "ember", Category: "Arcade", Version: "1.2", Plays: 10, Forks: 2, Likes: 7, Views: 30}
	wantDSL   = map[string]any{
		"meta":   map[string]any{"runtime": "shooter", "runtime_version": "1.0.0"},
		"player": map[string]any{"sprite": "cat", "speed": float64(220)},
	}
	wantComment = sdk.Comment{ID: "c1", GameID: "g1", AuthorID: "u1", Content: "nice", CreatedAt: createdAt}
	wantFrames  = []sdk.ReplayFrame{{AtMS: 0, X: 1.5, Y: 2, HP: 3, Score: 0}, {AtMS: 1000, X: 2, Y: 2.5, HP: 2, Score: 40}}
	wantReplay  = sdk.Replay{ID: "replay_1", GameID: "g1", UserID: "u1", DurationMS: 2000, Frames: wantFrames, Score: 40, CreatedAt: createdAt}
	wantSession = sdk.Session{Token: "new-token", User: sdk.User{ID: "u1", Nickname: "Guest1a2b"}}
	wantTree    = sdk.ForkTree{Ancestors: []sdk.Mod{wantMod}, Node: wantMod, Children: []sdk.Mod{}}
	wantPanel   = sdk.GameCommunity{Average: 4.5, Count: 2, MyRating: 5, Posts: []sdk.CommunityPost{{ID: "post_1", GameID: "g1", AuthorID: "u1", Content: "hello", CreatedAt: createdAt}}}
)

const (
	sessionJSON = `{"token":"new-token","user":{"id":"u1","nickname":"Guest1a2b"}}`
	treeJSON    = `{"ancestors":[` + modJSON + `],"node":` + modJSON + `,"children":[]}`
	panelJSON   = `{"average":4.5,"count":2,"my_rating":5,"posts":[{"id":"post_1","game_id":"g1","author_id":"u1","content":"hello","created_at":"2026-01-02T03:04:05Z"}]}`
)

// endpointCase describes one SDK method call and the exact HTTP exchange it must produce.
type endpointCase struct {
	name string
	// call invokes the method under test; the returned value is compared with want.
	call func(ctx context.Context, client *sdk.Client) (any, error)
	// wantMethod, wantPath, wantQuery and wantBody describe the expected request. An empty wantBody means the request must carry no body.
	wantMethod string
	wantPath   string
	wantQuery  url.Values
	wantBody   string
	// status and response are what the fake backend answers.
	status   int
	response string
	// want is the expected decoded result; nil for methods that only return an error.
	want any
}

func endpointCases() []endpointCase {
	return []endpointCase{
		// ---- meta ----
		{
			name:       "Health",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return nil, c.Health(ctx) },
			wantMethod: http.MethodGet, wantPath: "/healthz",
			status: 200, response: `{"ok":true}`,
		},
		{
			name:       "Meta",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.Meta(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/meta",
			status: 200, response: `{"environment":"development","ai":{"mode":"stub"},"sms":false,"oauth_providers":["google","wechat"],"payments":false,"admin_configured":true,"moderation":false}`,
			want: &sdk.Meta{Environment: "development", AI: sdk.MetaAI{Mode: sdk.AIModeStub}, OAuthProviders: []string{"google", "wechat"}, AdminConfigured: true},
		},

		// ---- auth ----
		{
			name:       "LoginGuest",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.LoginGuest(ctx) },
			wantMethod: http.MethodPost, wantPath: "/api/v1/auth/guest",
			status: 200, response: sessionJSON, want: &wantSession,
		},
		{
			name:       "SendSMSCode",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return nil, c.SendSMSCode(ctx, "13800000000") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/auth/sms/send", wantBody: `{"phone":"13800000000"}`,
			status: 200, response: `{"sent":true}`,
		},
		{
			name:       "LoginSMS",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.LoginSMS(ctx, "13800000000", "123456") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/auth/sms/verify", wantBody: `{"phone":"13800000000","code":"123456"}`,
			status: 200, response: sessionJSON, want: &wantSession,
		},
		{
			name: "LoginPassword",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.LoginPassword(ctx, "13800000000", "hunter2hunter2")
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/auth/password/login", wantBody: `{"phone":"13800000000","password":"hunter2hunter2"}`,
			status: 200, response: sessionJSON, want: &wantSession,
		},
		{
			name:       "RefreshToken",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.RefreshToken(ctx) },
			wantMethod: http.MethodPost, wantPath: "/api/v1/auth/refresh",
			status: 200, response: `{"token":"rotated"}`, want: "rotated",
		},
		{
			name:       "Logout",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return nil, c.Logout(ctx) },
			wantMethod: http.MethodPost, wantPath: "/api/v1/auth/logout",
			status: 200, response: `{"ok":true}`,
		},
		{
			name:       "CurrentUser",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.CurrentUser(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/users/me",
			status: 200, response: `{"id":"u1","nickname":"Player9f"}`, want: &sdk.User{ID: "u1", Nickname: "Player9f"},
		},
		{
			name: "SetPassword",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return nil, c.SetPassword(ctx, "hunter2hunter2")
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/users/me/password", wantBody: `{"password":"hunter2hunter2"}`,
			status: 200, response: `{"password_set":true}`,
		},

		// ---- games ----
		{
			name:       "ListGames/defaults",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListGames(ctx, sdk.ListGamesParams{}) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games",
			status: 200, response: `{"items":[` + gameJSON + `],"next_cursor":"MjA"}`,
			want: &sdk.Page[sdk.Game]{Items: []sdk.Game{wantGame}, NextCursor: "MjA"},
		},
		{
			name: "ListGames/all filters",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.ListGames(ctx, sdk.ListGamesParams{Query: "ash fall", Sort: sdk.SortHot, Runtime: "shooter", Category: "arcade", AI: boolPtr(false), PageParams: sdk.PageParams{Cursor: "MjA", Limit: 50}})
			},
			wantMethod: http.MethodGet, wantPath: "/api/v1/games",
			wantQuery: url.Values{"q": {"ash fall"}, "sort": {"hot"}, "runtime": {"shooter"}, "category": {"arcade"}, "ai": {"false"}, "cursor": {"MjA"}, "limit": {"50"}},
			status:    200, response: `{"items":[],"next_cursor":""}`,
			want: &sdk.Page[sdk.Game]{Items: []sdk.Game{}},
		},
		{
			name:       "GetGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetGame(ctx, "g1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1",
			status: 200, response: gameJSON, want: &wantGame,
		},
		{
			name:       "GetGameDSL",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetGameDSL(ctx, "g1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/dsl",
			status: 200, response: dslJSON, want: wantDSL,
		},
		{
			name:       "GetGameLineage",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetGameLineage(ctx, "g1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/lineage",
			status: 200, response: `{"items":[` + modJSON + `]}`, want: []sdk.Mod{wantMod},
		},
		{
			name:       "GetGameForkTree",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetGameForkTree(ctx, "g1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/fork-tree",
			status: 200, response: treeJSON, want: &wantTree,
		},
		{
			name:       "ForkGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ForkGame(ctx, "g1") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/fork",
			status: 201, response: modJSON, want: &wantMod,
		},
		{
			name: "PublishGame",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.PublishGame(ctx, sdk.PublishGameRequest{ModID: "mod_1", Title: "Ashfall", Summary: "Dodge the ash", Tags: []string{"arcade", "fast"}, Category: "Arcade", ForkedFrom: "g0", AIGenerated: true})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/games",
			wantBody: `{"mod_id":"mod_1","title":"Ashfall","summary":"Dodge the ash","tags":["arcade","fast"],"category":"Arcade","forked_from":"g0","ai_generated":true}`,
			status:   201, response: gameJSON, want: &wantGame,
		},
		{
			name: "PublishGame/minimal body omits optional fields",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.PublishGame(ctx, sdk.PublishGameRequest{ModID: "mod_1", Title: "Ashfall"})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/games", wantBody: `{"mod_id":"mod_1","title":"Ashfall"}`,
			status: 201, response: gameJSON, want: &wantGame,
		},
		{
			name:       "ListMyGames",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListMyGames(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/mine",
			status: 200, response: `{"items":[` + gameJSON + `]}`, want: []sdk.Game{wantGame},
		},
		{
			name:       "DelistGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.DelistGame(ctx, "g1") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/delist",
			status: 200, response: gameJSON, want: &wantGame,
		},
		{
			name:       "ResubmitGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ResubmitGame(ctx, "g1") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/resubmit",
			status: 200, response: gameJSON, want: &wantGame,
		},

		// ---- ranking ----
		{
			name:       "GetRanking/defaults",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetRanking(ctx, sdk.RankingParams{}) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/ranking",
			status: 200, response: `{"type":"hot","items":[{"id":"g1","mod_id":"mod_1","author_id":"u1","by":"@u1","title":"Ashfall","summary":"","status":"published","ai_generated":false,"runtime":"shooter@1.0.0","created_at":"2026-01-02T03:04:05Z","tone":"ember","cat":"Arcade","plays":1,"forks":0,"views":0,"likes":12,"rank":1}]}`,
			want: &sdk.Ranking{Type: "hot", Items: []sdk.RankedGame{{Game: sdk.Game{ID: "g1", ModID: "mod_1", AuthorID: "u1", By: "@u1", Title: "Ashfall", Status: sdk.GameStatusPublished, Runtime: "shooter@1.0.0", CreatedAt: createdAt, Tone: "ember", Category: "Arcade", Plays: 1, Likes: 12}, Rank: 1}}},
		},
		{
			name: "GetRanking/all filters",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.GetRanking(ctx, sdk.RankingParams{Type: sdk.SortRising, Limit: 5, Runtime: "survivor@1.0.0", Category: "Arcade"})
			},
			wantMethod: http.MethodGet, wantPath: "/api/v1/ranking",
			wantQuery: url.Values{"type": {"rising"}, "limit": {"5"}, "runtime": {"survivor@1.0.0"}, "category": {"Arcade"}},
			status:    200, response: `{"type":"rising","items":[]}`,
			want: &sdk.Ranking{Type: "rising", Items: []sdk.RankedGame{}},
		},

		// ---- mods and drafts ----
		{
			name: "CreateMod/root",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.CreateMod(ctx, sdk.CreateModRequest{Runtime: "shooter@1.0.0", Patch: wantPatch, AIProvenance: "prov-token", Draft: true})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/mods",
			wantBody: `{"runtime":"shooter@1.0.0","patch":[{"op":"replace","path":"/player/sprite","value":"cat"}],"ai_provenance":"prov-token","draft":true}`,
			status:   201, response: modJSON, want: &wantMod,
		},
		{
			name: "CreateMod/child with remove op",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.CreateMod(ctx, sdk.CreateModRequest{ParentID: "mod_0", Patch: []sdk.PatchOp{{Op: "remove", Path: "/enemies/bat"}}})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/mods",
			wantBody: `{"parent_id":"mod_0","patch":[{"op":"remove","path":"/enemies/bat"}]}`,
			status:   201, response: modJSON, want: &wantMod,
		},
		{
			name:       "ForkMod",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ForkMod(ctx, "mod_0") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/mods/mod_0/fork",
			status: 201, response: modJSON, want: &wantMod,
		},
		{
			name:       "GetMod",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetMod(ctx, "mod_1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/mods/mod_1/fork-tree",
			status: 200, response: treeJSON, want: &wantMod,
		},
		{
			name:       "GetModDSL",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetModDSL(ctx, "mod_1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/mods/mod_1/dsl",
			status: 200, response: dslJSON, want: wantDSL,
		},
		{
			name:       "GetModLineage",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetModLineage(ctx, "mod_1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/mods/mod_1/lineage",
			status: 200, response: `{"items":[` + modJSON + `]}`, want: []sdk.Mod{wantMod},
		},
		{
			name:       "GetModForkTree",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetModForkTree(ctx, "mod_1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/mods/mod_1/fork-tree",
			status: 200, response: treeJSON, want: &wantTree,
		},
		{
			name:       "ListMyMods",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListMyMods(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/mods/mine",
			status: 200, response: `{"items":[` + modJSON + `]}`, want: []sdk.Mod{wantMod},
		},
		{
			name:       "ListDrafts",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListDrafts(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/drafts",
			status: 200, response: `{"items":[` + modJSON + `]}`, want: []sdk.Mod{wantMod},
		},
		{
			name:       "SaveDraft",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.SaveDraft(ctx, "mod_0", wantPatch) },
			wantMethod: http.MethodPut, wantPath: "/api/v1/drafts/mod_0",
			wantBody: `{"patch":[{"op":"replace","path":"/player/sprite","value":"cat"}]}`,
			status:   201, response: modJSON, want: &wantMod,
		},
		{
			name: "PublishDraft",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.PublishDraft(ctx, "mod_1", sdk.PublishDraftRequest{Title: "Ashfall", Summary: "Dodge the ash", Tags: []string{"arcade"}, Category: "Arcade", ForkedFrom: "g0", AIGenerated: true})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/drafts/mod_1/publish",
			wantBody: `{"title":"Ashfall","summary":"Dodge the ash","tags":["arcade"],"category":"Arcade","forked_from":"g0","ai_generated":true}`,
			status:   201, response: gameJSON, want: &wantGame,
		},

		// ---- AI and runtimes ----
		{
			name: "GenerateMod",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.GenerateMod(ctx, sdk.GenerateModRequest{Runtime: "shooter@1.0.0", CurrentDSL: wantDSL, Prompt: "make the player a cat"})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/ai/mod",
			wantBody: `{"runtime":"shooter@1.0.0","current_dsl":` + dslJSON + `,"prompt":"make the player a cat"}`,
			status:   200, response: `{"dsl_patch":[{"op":"replace","path":"/player/sprite","value":"cat"}],"new_dsl":` + dslJSON + `,"balance_hint":"fine","model":"stub","tokens":{"prompt":120,"completion":30},"retries":1,"provenance":"prov-token"}`,
			want: &sdk.GenerateModResponse{DSLPatch: wantPatch, NewDSL: wantDSL, BalanceHint: "fine", Model: "stub", Tokens: sdk.TokenUsage{Prompt: 120, Completion: 30}, Retries: 1, Provenance: "prov-token"},
		},
		{
			name: "GenerateStructure",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.GenerateStructure(ctx, sdk.GenerateStructureRequest{Runtime: "shooter@1.0.0", CurrentDSL: wantDSL, Prompt: "two fast bats", Count: 2, Difficulty: 3})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/ai/structure",
			wantBody: `{"runtime":"shooter@1.0.0","current_dsl":` + dslJSON + `,"prompt":"two fast bats","count":2,"difficulty":3}`,
			status:   200, response: `{"dsl_patch":[{"op":"replace","path":"/player/sprite","value":"cat"}],"new_dsl":` + dslJSON + `,"generated_keys":["bat_1","bat_2"],"model":"structure-v1","balance_hint":"ok","provenance":"prov-token"}`,
			want: &sdk.GenerateStructureResponse{DSLPatch: wantPatch, NewDSL: wantDSL, GeneratedKeys: []string{"bat_1", "bat_2"}, Model: "structure-v1", BalanceHint: "ok", Provenance: "prov-token"},
		},
		{
			name: "AutoBalance",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.AutoBalance(ctx, sdk.AutoBalanceRequest{Runtime: "shooter@1.0.0", CurrentDSL: wantDSL, TargetDifficulty: 4})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/ai/balance",
			wantBody: `{"runtime":"shooter@1.0.0","current_dsl":` + dslJSON + `,"target_difficulty":4}`,
			status:   200, response: `{"dsl_patch":[{"op":"replace","path":"/player/sprite","value":"cat"}],"new_dsl":` + dslJSON + `,"metrics":{"before":1.25,"after":2.5},"model":"balance-v1","balance_hint":"harder","provenance":"prov-token"}`,
			want: &sdk.AutoBalanceResponse{DSLPatch: wantPatch, NewDSL: wantDSL, Metrics: sdk.BalanceMetrics{Before: 1.25, After: 2.5}, Model: "balance-v1", BalanceHint: "harder", Provenance: "prov-token"},
		},
		{
			name: "ValidateDSL",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return nil, c.ValidateDSL(ctx, "shooter@1.0.0", wantDSL)
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/ai/validate", wantBody: `{"runtime":"shooter@1.0.0","dsl":` + dslJSON + `}`,
			status: 200, response: `{"valid":true}`,
		},
		{
			name:       "AIQuota",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.AIQuota(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/ai/quota",
			status: 200, response: `{"used":3,"remaining":17,"limit":20}`, want: &sdk.AIQuota{Used: 3, Remaining: 17, Limit: 20},
		},
		{
			name: "GetRuntimeSchema",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.GetRuntimeSchema(ctx, "shooter", "1.0.0")
			},
			wantMethod: http.MethodGet, wantPath: "/api/v1/runtimes/shooter/1.0.0/schema",
			status: 200, response: `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object"}`,
			want: json.RawMessage(`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object"}`),
		},
		{
			name: "GetRuntimeBaseline",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.GetRuntimeBaseline(ctx, "tower_defense", "1.0.0")
			},
			wantMethod: http.MethodGet, wantPath: "/api/v1/runtimes/tower_defense/1.0.0/baseline",
			status: 200, response: dslJSON, want: wantDSL,
		},

		// ---- social and community ----
		{
			name: "ListComments/defaults",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.ListComments(ctx, "g1", sdk.PageParams{})
			},
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/comments",
			status: 200, response: `{"items":[` + commentJSON + `],"next_cursor":""}`,
			want: &sdk.Page[sdk.Comment]{Items: []sdk.Comment{wantComment}},
		},
		{
			name: "ListComments/paged",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.ListComments(ctx, "g1", sdk.PageParams{Cursor: "NQ", Limit: 5})
			},
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/comments", wantQuery: url.Values{"cursor": {"NQ"}, "limit": {"5"}},
			status: 200, response: `{"items":[],"next_cursor":"MTA"}`,
			want: &sdk.Page[sdk.Comment]{Items: []sdk.Comment{}, NextCursor: "MTA"},
		},
		{
			name:       "AddComment",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.AddComment(ctx, "g1", "nice") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/comments", wantBody: `{"content":"nice"}`,
			status: 201, response: commentJSON, want: &wantComment,
		},
		{
			name:       "LikeGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.LikeGame(ctx, "g1") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/like",
			status: 200, response: `{"count":8,"liked":true}`, want: &sdk.LikeStatus{Liked: true, Count: intPtr(8)},
		},
		{
			name:       "UnlikeGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.UnlikeGame(ctx, "g1") },
			wantMethod: http.MethodDelete, wantPath: "/api/v1/games/g1/like",
			status: 200, response: `{"count":0,"liked":false}`, want: &sdk.LikeStatus{Liked: false, Count: intPtr(0)},
		},
		{
			name:       "LikeGame/count unavailable",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.LikeGame(ctx, "g1") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/like",
			status: 200, response: `{"liked":true}`, want: &sdk.LikeStatus{Liked: true},
		},
		{
			name:       "FavoriteGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return nil, c.FavoriteGame(ctx, "g1") },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/favorite",
			status: 200, response: `{"favorite":true}`,
		},
		{
			name:       "UnfavoriteGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return nil, c.UnfavoriteGame(ctx, "g1") },
			wantMethod: http.MethodDelete, wantPath: "/api/v1/games/g1/favorite",
			status: 200, response: `{"favorite":false}`,
		},
		{
			name:       "ListFavorites",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListFavorites(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/favorites",
			status: 200, response: `{"items":["g1","g2"]}`, want: []string{"g1", "g2"},
		},
		{
			name:       "GetGameCommunity",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetGameCommunity(ctx, "g1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/community",
			status: 200, response: panelJSON, want: &wantPanel,
		},
		{
			name:       "RateGame",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.RateGame(ctx, "g1", 5) },
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/community/rating", wantBody: `{"value":5}`,
			status: 200, response: panelJSON, want: &wantPanel,
		},
		{
			name: "CreateCommunityPost",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.CreateCommunityPost(ctx, "g1", "hello")
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/community/posts", wantBody: `{"content":"hello"}`,
			status: 201, response: `{"id":"post_1","game_id":"g1","author_id":"u1","content":"hello","created_at":"2026-01-02T03:04:05Z"}`,
			want: &sdk.CommunityPost{ID: "post_1", GameID: "g1", AuthorID: "u1", Content: "hello", CreatedAt: createdAt},
		},

		// ---- users ----
		{
			name:       "GetUserProfile",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetUserProfile(ctx, "@talia") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/users/@talia",
			status: 200, response: `{"id":"@talia","name":"Talia","bio":"maker","gender":2,"tone":"moss","region":"JP","joined":2024,"works":3,"level":4,"points":120,"plays":900,"forks":12,"follows":5,"likes":77}`,
			want: &sdk.Profile{ID: "@talia", Name: "Talia", Bio: "maker", Gender: 2, Tone: "moss", Region: "JP", Joined: 2024, Works: 3, Level: 4, Points: 120, Plays: 900, Forks: 12, Follows: 5, Likes: 77},
		},
		{
			name:       "ListUserGames/default kind",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListUserGames(ctx, "u1", "") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/users/u1/games",
			status: 200, response: `{"items":[` + gameJSON + `]}`, want: []sdk.Game{wantGame},
		},
		{
			name: "ListUserGames/liked",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.ListUserGames(ctx, "u1", sdk.UserGamesLiked)
			},
			wantMethod: http.MethodGet, wantPath: "/api/v1/users/u1/games", wantQuery: url.Values{"type": {"liked"}},
			status: 200, response: `{"items":[]}`, want: []sdk.Game{},
		},
		{
			name:       "ListFollowers",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListFollowers(ctx, "u1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/users/u1/followers",
			status: 200, response: `{"items":[{"handle":"u2","mutual":false,"note":""}]}`, want: []sdk.Person{{Handle: "u2"}},
		},
		{
			name:       "ListFollowing",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListFollowing(ctx, "u1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/users/u1/following",
			status: 200, response: `{"items":[{"handle":"u3","mutual":true,"note":"friend"}]}`, want: []sdk.Person{{Handle: "u3", Mutual: true, Note: "friend"}},
		},

		// ---- library and replays ----
		{
			name:       "ListDownloads",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListDownloads(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/downloads",
			status: 200, response: `{"items":[{"game":{"id":"g1","author_id":"u1","title":"Ashfall","summary":"Dodge","tags":["arcade"]},"size_mb":12,"has_update":true}]}`,
			want: []sdk.DownloadItem{{Game: sdk.LibraryGame{ID: "g1", AuthorID: "u1", Title: "Ashfall", Summary: "Dodge", Tags: []string{"arcade"}}, SizeMB: 12, HasUpdate: true}},
		},
		{
			name:       "ListHistory",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListHistory(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/history",
			status: 200, response: `{"groups":[{"group":"today","items":[{"game":{"id":"g1","author_id":"u1","title":"Ashfall","summary":"Dodge"},"minutes_played":7}]},{"group":"yesterday","items":[]}]}`,
			want: []sdk.HistoryGroup{
				{Group: sdk.HistoryToday, Items: []sdk.HistoryItem{{Game: sdk.LibraryGame{ID: "g1", AuthorID: "u1", Title: "Ashfall", Summary: "Dodge"}, MinutesPlayed: 7}}},
				{Group: sdk.HistoryYesterday, Items: []sdk.HistoryItem{}},
			},
		},
		{
			name:       "ListLive",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.ListLive(ctx) },
			wantMethod: http.MethodGet, wantPath: "/api/v1/live",
			status: 200, response: `{"items":[{"game":{"id":"g1","author_id":"u1","title":"Ashfall","summary":"Dodge"},"streamer":"@arc","viewers":321,"title":"speedrun"}]}`,
			want: []sdk.LiveItem{{Game: sdk.LibraryGame{ID: "g1", AuthorID: "u1", Title: "Ashfall", Summary: "Dodge"}, Streamer: "@arc", Viewers: 321, Title: "speedrun"}},
		},
		{
			name: "RecordPlay",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return nil, c.RecordPlay(ctx, "g1", 90*time.Second+500*time.Millisecond)
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/played", wantBody: `{"duration_ms":90500}`,
			status: 200, response: `{"recorded":true}`,
		},
		{
			name:       "GetReplayLeaderboard",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetReplayLeaderboard(ctx, "g1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/replays/leaderboard",
			status: 200, response: `{"items":[{"user_id":"u1","nickname":"Player9f","score":40,"rank":1}]}`,
			want: []sdk.LeaderboardEntry{{UserID: "u1", Nickname: "Player9f", Score: 40, Rank: 1}},
		},
		{
			name:       "GetLatestReplay",
			call:       func(ctx context.Context, c *sdk.Client) (any, error) { return c.GetLatestReplay(ctx, "g1", "u1") },
			wantMethod: http.MethodGet, wantPath: "/api/v1/games/g1/replays/u1",
			status: 200, response: replayJSON, want: &wantReplay,
		},
		{
			name: "SubmitReplay",
			call: func(ctx context.Context, c *sdk.Client) (any, error) {
				return c.SubmitReplay(ctx, "g1", sdk.SubmitReplayRequest{DurationMS: 2000, Frames: wantFrames})
			},
			wantMethod: http.MethodPost, wantPath: "/api/v1/games/g1/replays",
			wantBody: `{"duration_ms":2000,"frames":[{"at_ms":0,"x":1.5,"y":2,"hp":3,"score":0},{"at_ms":1000,"x":2,"y":2.5,"hp":2,"score":40}]}`,
			status:   201, response: replayJSON, want: &wantReplay,
		},
	}
}

// TestEndpoints drives every endpoint method against a fake backend and checks the exact request it sends and how it decodes the response.
func TestEndpoints(t *testing.T) {
	for _, tc := range endpointCases() {
		t.Run(tc.name, func(t *testing.T) {
			server, seen := fakeBackend(t, tc.status, tc.response)
			client := newClient(t, server.URL, sdk.WithToken(testToken), sdk.WithUserAgent(testUserAgent))

			got, err := tc.call(context.Background(), client)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if len(seen()) != 1 {
				t.Fatalf("backend saw %d requests, want exactly 1", len(seen()))
			}
			request := seen()[0]

			if request.method != tc.wantMethod {
				t.Errorf("method: got %s, want %s", request.method, tc.wantMethod)
			}
			if request.path != tc.wantPath {
				t.Errorf("path: got %s, want %s", request.path, tc.wantPath)
			}
			wantQuery := tc.wantQuery
			if wantQuery == nil {
				wantQuery = url.Values{}
			}
			if !reflect.DeepEqual(request.query, wantQuery) {
				t.Errorf("query: got %v, want %v", request.query, wantQuery)
			}

			if got := request.header.Get("Authorization"); got != "Bearer "+testToken {
				t.Errorf("Authorization header: got %q, want %q", got, "Bearer "+testToken)
			}
			if got := request.header.Get("User-Agent"); got != testUserAgent {
				t.Errorf("User-Agent header: got %q, want %q", got, testUserAgent)
			}
			if got := request.header.Get("Accept"); got != "application/json" {
				t.Errorf("Accept header: got %q, want application/json", got)
			}
			if got := request.header.Get("Accept-Language"); got != "" {
				t.Errorf("Accept-Language header: got %q, want none without WithLanguage", got)
			}

			if tc.wantBody == "" {
				if len(request.body) != 0 {
					t.Errorf("body: got %q, want no body", request.body)
				}
				if got := request.header.Get("Content-Type"); got != "" {
					t.Errorf("Content-Type header: got %q, want none for a request without body", got)
				}
			} else {
				assertJSONEqual(t, "request body", request.body, tc.wantBody)
				if got := request.header.Get("Content-Type"); got != "application/json" {
					t.Errorf("Content-Type header: got %q, want application/json", got)
				}
			}

			if tc.want != nil && !reflect.DeepEqual(got, tc.want) {
				t.Errorf("result:\n got  %#v\n want %#v", got, tc.want)
			}
		})
	}
}

// TestEndpointErrors checks that every endpoint method surfaces a backend error envelope as *APIError with the request it belongs to.
func TestEndpointErrors(t *testing.T) {
	for _, tc := range endpointCases() {
		t.Run(tc.name, func(t *testing.T) {
			server, _ := fakeBackend(t, http.StatusForbidden, `{"error":{"code":"FORBIDDEN","message":"no access"}}`)
			client := newClient(t, server.URL, sdk.WithToken(testToken))

			got, err := tc.call(context.Background(), client)
			if err == nil {
				t.Fatalf("expected an error, got result %#v", got)
			}
			apiErr, ok := err.(*sdk.APIError)
			if !ok {
				t.Fatalf("error type: got %T (%v), want *sdk.APIError", err, err)
			}
			want := sdk.APIError{StatusCode: http.StatusForbidden, Code: sdk.CodeForbidden, Message: "no access", Method: tc.wantMethod, Path: tc.wantPath}
			if !reflect.DeepEqual(*apiErr, want) {
				t.Errorf("APIError:\n got  %#v\n want %#v", *apiErr, want)
			}
			if got != nil && !reflect.ValueOf(got).IsZero() {
				t.Errorf("result on error: got %#v, want a zero value", got)
			}
		})
	}
}
