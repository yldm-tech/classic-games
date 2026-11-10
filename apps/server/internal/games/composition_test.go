package games

import (
	"encoding/json"
	"net/http"
	"testing"

	"forgeplay/server/internal/mods"
	"github.com/gin-gonic/gin"
)

type fakeModGateway struct {
	modID, author string
	draftCleared  bool
}

func (f *fakeModGateway) EffectiveDSL(id string) (map[string]any, error) {
	f.modID = id
	return map[string]any{"ok": true}, nil
}
func (f *fakeModGateway) ForkFor(author, id string) (mods.Mod, error) {
	f.author, f.modID = author, id
	return mods.Mod{ID: "forked", ParentID: id, AuthorID: author}, nil
}
func (f *fakeModGateway) Lineage(id, viewer string) ([]mods.Mod, error) {
	f.modID = id
	return []mods.Mod{{ID: id}}, nil
}
func (f *fakeModGateway) ForkTree(id, viewer string) (mods.ForkTreeView, error) {
	f.modID = id
	return mods.ForkTreeView{Node: mods.Mod{ID: id}}, nil
}
func (f *fakeModGateway) Get(id string) (mods.Mod, error) {
	return mods.Mod{ID: id, AuthorID: "forker", Draft: true}, nil
}
func (f *fakeModGateway) SetDraft(id string, draft bool) error {
	f.draftCleared = !draft
	return nil
}

func TestHTTP_GameCompositionRoutesResolveGameToMod(t *testing.T) {
	svc := newSvc()
	g, _ := svc.Publish(PublishRequest{ModID: "mod-source", AuthorID: "owner", Title: "x"})
	g, _ = svc.Decide(g.ID, true)
	gw := &fakeModGateway{}
	r := newRouter()
	RegisterCompositionRoutes(r, svc, gw, func(c *gin.Context) { c.Set("user_id", "forker") })

	w := do(t, r, http.MethodGet, "/api/v1/games/"+g.ID+"/dsl", nil)
	if w.Code != http.StatusOK || gw.modID != "mod-source" {
		t.Fatalf("dsl 未解析到 game.mod_id: %d %s", w.Code, w.Body.String())
	}
	w = do(t, r, http.MethodPost, "/api/v1/games/"+g.ID+"/fork", nil)
	if w.Code != http.StatusCreated || gw.author != "forker" || gw.modID != "mod-source" {
		t.Fatalf("fork 未注入登录作者: %d %s", w.Code, w.Body.String())
	}
	updated, _ := svc.Get(g.ID)
	if updated.Forks != 1 {
		t.Fatalf("成功 fork 应原子增加作品 forks, got %d", updated.Forks)
	}
	w = do(t, r, http.MethodGet, "/api/v1/games/"+g.ID+"/lineage", nil)
	if w.Code != http.StatusOK || gw.modID != "mod-source" {
		t.Fatalf("lineage 未解析 mod: %d", w.Code)
	}
	w = do(t, r, http.MethodGet, "/api/v1/games/"+g.ID+"/fork-tree", nil)
	if w.Code != http.StatusOK || gw.modID != "mod-source" {
		t.Fatalf("fork-tree 未解析 mod: %d", w.Code)
	}
}

func TestHTTP_PublishDraftChecksOwnerAndPublishes(t *testing.T) {
	svc := newSvc()
	gw := &fakeModGateway{}
	r := gin.New()
	RegisterDraftPublishRoutes(r, svc, gw, func(c *gin.Context) { c.Set("user_id", "forker") })
	w := do(t, r, http.MethodPost, "/api/v1/drafts/draft_1/publish", map[string]any{"title": "Draft game"})
	if w.Code != http.StatusCreated {
		t.Fatalf("publish draft=%d %s", w.Code, w.Body.String())
	}
	var game Game
	_ = json.Unmarshal(w.Body.Bytes(), &game)
	if game.ModID != "draft_1" || game.AuthorID != "forker" || game.Status != StatusReviewing {
		t.Fatalf("game=%+v", game)
	}
	// 发布必须清除 backing mod 的草稿标记,否则他人无法 Fork 该已发布游戏。回归守卫 C6。
	if !gw.draftCleared {
		t.Fatal("发布草稿后应清除 mod 的 draft 标记")
	}
}

func TestHTTP_UnpublishedCompositionVisibleOnlyToAuthor(t *testing.T) {
	svc := newSvc()
	game, _ := svc.Publish(PublishRequest{ModID: "m", AuthorID: "owner", Title: "review"})
	gw := &fakeModGateway{}
	makeRouter := func(user string) *gin.Engine {
		r := gin.New()
		write := func(c *gin.Context) { c.Set("user_id", user); c.Next() }
		read := func(c *gin.Context) { c.Set("user_id", user); c.Next() }
		RegisterCompositionRoutes(r, svc, gw, write, read)
		return r
	}
	if w := do(t, makeRouter("outsider"), http.MethodGet, "/api/v1/games/"+game.ID+"/dsl", nil); w.Code != http.StatusNotFound {
		t.Fatalf("outsider unpublished read=%d %s", w.Code, w.Body.String())
	}
	if w := do(t, makeRouter("owner"), http.MethodGet, "/api/v1/games/"+game.ID+"/dsl", nil); w.Code != http.StatusOK {
		t.Fatalf("owner unpublished read=%d %s", w.Code, w.Body.String())
	}
}

// missingModGateway is a mod store that holds no mod at all.
type missingModGateway struct{ calls int }

func (f *missingModGateway) EffectiveDSL(string) (map[string]any, error) {
	f.calls++
	return nil, mods.ErrNotFound
}
func (f *missingModGateway) ForkFor(string, string) (mods.Mod, error) {
	f.calls++
	return mods.Mod{}, mods.ErrNotFound
}
func (f *missingModGateway) Lineage(string, string) ([]mods.Mod, error) {
	f.calls++
	return nil, mods.ErrNotFound
}
func (f *missingModGateway) ForkTree(string, string) (mods.ForkTreeView, error) {
	f.calls++
	return mods.ForkTreeView{}, mods.ErrNotFound
}

func compositionErrorCode(t *testing.T, body []byte) string {
	t.Helper()
	var envelope struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		t.Fatalf("error body is not JSON: %v: %s", err, body)
	}
	return envelope.Error.Code
}

// A showcase entry has no mod. Its DSL, lineage, fork-tree and fork routes must say so with a dedicated code instead of the generic "mods: not found", and must not ask the mod store for an empty id. A row seeded with the old placeholder mod_id, which no mod ever had, gets the same answer.
func TestHTTP_GameWithoutModAnswersDedicatedCode(t *testing.T) {
	repo := NewMemRepo()
	if err := Seed(repo); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.Create(Game{ID: "legacy", ModID: "seed_legacy", Title: "legacy", Status: StatusPublished}); err != nil {
		t.Fatal(err)
	}
	seeded, err := repo.Get("ember")
	if err != nil {
		t.Fatal(err)
	}
	if seeded.ModID != "" || seeded.Runtime != "" {
		t.Fatalf("showcase entries must not claim a mod or a runtime: mod_id=%q runtime=%q", seeded.ModID, seeded.Runtime)
	}

	for _, tc := range []struct {
		gameID       string
		gatewayCalls int
	}{
		{gameID: "ember", gatewayCalls: 0},
		{gameID: "legacy", gatewayCalls: 1},
	} {
		for _, route := range []struct{ method, suffix string }{
			{http.MethodGet, "/dsl"},
			{http.MethodGet, "/lineage"},
			{http.MethodGet, "/fork-tree"},
			{http.MethodPost, "/fork"},
		} {
			gw := &missingModGateway{}
			r := gin.New()
			RegisterCompositionRoutes(r, NewService(repo), gw, func(c *gin.Context) { c.Set("user_id", "forker") })
			w := do(t, r, route.method, "/api/v1/games/"+tc.gameID+route.suffix, nil)
			if w.Code != http.StatusNotFound || compositionErrorCode(t, w.Body.Bytes()) != "GAME_HAS_NO_MOD" {
				t.Errorf("%s %s%s = %d %s, want 404 GAME_HAS_NO_MOD", route.method, tc.gameID, route.suffix, w.Code, w.Body.String())
			}
			if gw.calls != tc.gatewayCalls {
				t.Errorf("%s %s%s reached the mod store %d times, want %d", route.method, tc.gameID, route.suffix, gw.calls, tc.gatewayCalls)
			}
		}
	}
	if game, _ := repo.Get("ember"); game.Forks != seeded.Forks {
		t.Errorf("a refused fork must not count: forks %d -> %d", seeded.Forks, game.Forks)
	}

	// A game that does not exist keeps the generic code.
	r := gin.New()
	RegisterCompositionRoutes(r, NewService(repo), &missingModGateway{})
	if w := do(t, r, http.MethodGet, "/api/v1/games/nope/dsl", nil); w.Code != http.StatusNotFound || compositionErrorCode(t, w.Body.Bytes()) != "NOT_FOUND" {
		t.Errorf("unknown game = %d %s, want 404 NOT_FOUND", w.Code, w.Body.String())
	}
}
