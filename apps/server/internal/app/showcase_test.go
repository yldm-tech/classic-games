package app

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

type showcaseTestClient struct {
	t       *testing.T
	handler http.Handler
	token   string
}

// call sends one JSON request and decodes the JSON answer into out when out is not nil.
func (c showcaseTestClient) call(method, path string, body, out any) int {
	c.t.Helper()
	var payload []byte
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			c.t.Fatal(err)
		}
		payload = encoded
	}
	request := httptest.NewRequest(method, path, bytes.NewReader(payload))
	request.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		request.Header.Set("Authorization", "Bearer "+c.token)
	}
	response := httptest.NewRecorder()
	c.handler.ServeHTTP(response, request)
	if out != nil {
		if err := json.Unmarshal(response.Body.Bytes(), out); err != nil {
			c.t.Fatalf("%s %s: status %d, body is not the expected JSON: %v: %s", method, path, response.Code, err, response.Body.String())
		}
	}
	return response.Code
}

type showcaseListedGame struct {
	ID      string `json:"id"`
	ModID   string `json:"mod_id"`
	Runtime string `json:"runtime"`
}

func newShowcaseTestApp(t *testing.T, cfg Config) showcaseTestClient {
	t.Helper()
	instance, err := New(context.Background(), cfg, Options{})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() {
		if closeErr := instance.Close(); closeErr != nil {
			t.Errorf("Close: %v", closeErr)
		}
	})
	client := showcaseTestClient{t: t, handler: instance.Handler()}
	var guest struct {
		Token string `json:"token"`
	}
	if status := client.call(http.MethodPost, "/api/v1/auth/guest", nil, &guest); status != http.StatusOK || guest.Token == "" {
		t.Fatalf("guest login = %d", status)
	}
	client.token = guest.Token
	return client
}

func (c showcaseTestClient) listedGames() []showcaseListedGame {
	c.t.Helper()
	var page struct {
		Items []showcaseListedGame `json:"items"`
	}
	if status := c.call(http.MethodGet, "/api/v1/games?limit=100", nil, &page); status != http.StatusOK {
		c.t.Fatalf("list games = %d", status)
	}
	return page.Items
}

// Every listed game keeps one of two promises: either a mod stands behind it, and then its DSL can be read and it can be forked, or it says it has none (empty mod_id and runtime) and those routes answer GAME_HAS_NO_MOD. A fresh development database holds both kinds: the showcase catalogue and, here, one game published through the API.
func TestListedGamesAreForkableOrMarkedAsHavingNoMod(t *testing.T) {
	cfg := applicationTestConfig(t)
	cfg.Auth.DevAdmin = true
	client := newShowcaseTestApp(t, cfg)

	var mod struct {
		ID string `json:"id"`
	}
	if status := client.call(http.MethodPost, "/api/v1/mods", map[string]any{"runtime": "shooter@1.0.0", "patch": []any{}}, &mod); status != http.StatusCreated || mod.ID == "" {
		t.Fatalf("create mod = %d", status)
	}
	var published showcaseListedGame
	if status := client.call(http.MethodPost, "/api/v1/games", map[string]any{"mod_id": mod.ID, "title": "published through the API"}, &published); status != http.StatusCreated {
		t.Fatalf("publish = %d", status)
	}
	if status := client.call(http.MethodPost, "/api/v1/games/"+published.ID+"/decision", map[string]any{"approve": true}, nil); status != http.StatusOK {
		t.Fatalf("approve = %d", status)
	}

	games := client.listedGames()
	forkable, showcase := 0, 0
	for _, game := range games {
		base := "/api/v1/games/" + game.ID
		if game.ModID == "" {
			showcase++
			if game.Runtime != "" {
				t.Errorf("%s has no mod but claims runtime %q", game.ID, game.Runtime)
			}
			for _, route := range []struct{ method, path string }{
				{http.MethodGet, base + "/dsl"},
				{http.MethodGet, base + "/lineage"},
				{http.MethodGet, base + "/fork-tree"},
				{http.MethodPost, base + "/fork"},
			} {
				var failure struct {
					Error struct {
						Code string `json:"code"`
					} `json:"error"`
				}
				if status := client.call(route.method, route.path, nil, &failure); status != http.StatusNotFound || failure.Error.Code != "GAME_HAS_NO_MOD" {
					t.Errorf("%s %s = %d %s, want 404 GAME_HAS_NO_MOD", route.method, route.path, status, failure.Error.Code)
				}
			}
			continue
		}
		forkable++
		if game.Runtime == "" {
			t.Errorf("%s has mod %s but no runtime", game.ID, game.ModID)
		}
		var dsl map[string]any
		if status := client.call(http.MethodGet, base+"/dsl", nil, &dsl); status != http.StatusOK || len(dsl) == 0 {
			t.Errorf("GET %s/dsl = %d", base, status)
		}
		var fork struct {
			ParentID string `json:"parent_id"`
		}
		if status := client.call(http.MethodPost, base+"/fork", nil, &fork); status != http.StatusCreated || fork.ParentID != game.ModID {
			t.Errorf("POST %s/fork = %d, parent %q, want 201 with parent %q", base, status, fork.ParentID, game.ModID)
		}
	}
	if showcase != 9 || forkable != 1 {
		t.Fatalf("listed %d showcase entries and %d games with a mod, want 9 and 1", showcase, forkable)
	}
}

// The showcase catalogue is invented content. A production database starts empty and stays empty across restarts, including through the library domain, which asks its game source for the same seeds.
func TestProductionDatabaseIsNotSeededWithShowcaseGames(t *testing.T) {
	cfg := applicationTestConfig(t)
	cfg.Environment = Production
	cfg.Security.Secret = strings.Repeat("s", 32)
	// A file, not the shared in-memory database of the other tests: that one is dropped when the application closes, so a second start would not see the first one's rows.
	cfg.Database.DSN = filepath.Join(t.TempDir(), "production.db")
	for start := 1; start <= 2; start++ {
		instance, err := New(context.Background(), cfg, Options{})
		if err != nil {
			t.Fatalf("start %d: New: %v", start, err)
		}
		client := showcaseTestClient{t: t, handler: instance.Handler()}
		if games := client.listedGames(); len(games) != 0 {
			t.Errorf("start %d: a production catalogue lists %d games, want none", start, len(games))
		}
		var downloads struct {
			Items []json.RawMessage `json:"items"`
		}
		if status := client.call(http.MethodGet, "/api/v1/downloads", nil, &downloads); status != http.StatusOK || len(downloads.Items) != 0 {
			t.Errorf("start %d: anonymous downloads = %d with %d items, want 200 with none", start, status, len(downloads.Items))
		}
		if err := instance.Close(); err != nil {
			t.Fatalf("start %d: Close: %v", start, err)
		}
	}
}
