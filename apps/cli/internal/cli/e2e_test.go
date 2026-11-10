package cli

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/yldm-tech/classic-games/packages/sdk"
)

// envE2EURL points TestE2E at a running backend, for example one started from apps/server with a temporary database. The test is skipped without it. Each run creates one guest account and spends one unit of the client IP's daily AI quota.
const envE2EURL = "CLASSIC_GAMES_CLI_E2E_URL"

// TestE2E drives the real command tree against a real backend: login, AI generation saved as a draft, an edit, publication, and logout. It only assumes what every backend guarantees; it does not rely on the stub AI or on admin rights.
func TestE2E(t *testing.T) {
	server := os.Getenv(envE2EURL)
	if server == "" {
		t.Skipf("set %s to the URL of a running backend to run this test", envE2EURL)
	}
	h := newHarness(t)
	h.env[EnvServerURL] = server
	h.env[EnvSchemaDir] = repoPath(t, "packages", "schemas")

	h.ok("server", "health")
	info := decode[infoReport](t, h.ok("server", "info", "--output", "json"))
	if info.Meta == nil || info.Environment == "" || info.AI.Mode == "" {
		t.Fatalf("server info = %+v", info)
	}

	h.fails("auth", "status")
	login := h.run("auth", "login")
	if login.code != 0 {
		t.Fatalf("guest login failed: %s", login.stderr)
	}
	status := decode[authReport](t, h.ok("auth", "status", "--output", "json"))
	if !status.LoggedIn || status.User == nil || status.User.ID == "" {
		t.Fatalf("auth status = %+v", status)
	}
	h.ok("auth", "refresh")
	if again := decode[authReport](t, h.ok("auth", "status", "--output", "json")); again.User == nil || again.User.ID != status.User.ID {
		t.Fatalf("the user changed across a token refresh: %+v", again)
	}

	catalog := decode[itemPage[sdk.Game]](t, h.ok("games", "list", "--all", "--output", "json"))
	if len(catalog.Items) == 0 {
		t.Fatal("the catalog is empty; a fresh backend seeds published games")
	}
	shown := decode[sdk.Game](t, h.ok("games", "show", catalog.Items[0].ID, "--output", "json"))
	if shown.ID != catalog.Items[0].ID || shown.Status != sdk.GameStatusPublished {
		t.Fatalf("games show = %+v", shown)
	}

	// Generate on the shooter baseline and keep the result as a draft; the backend has already validated it.
	directory := t.TempDir()
	generatedDSL := filepath.Join(directory, "generated.dsl.json")
	generated := decode[generateReport](t, h.ok("ai", "generate", "turn the player into a cat", "--runtime", "shooter@1.0.0", "--save", "--dsl-out", generatedDSL, "--output", "json"))
	if generated.SavedMod == nil || !generated.SavedMod.Draft || generated.SavedMod.Runtime != "shooter@1.0.0" || len(generated.DSLPatch) == 0 {
		t.Fatalf("ai generate = %+v", generated)
	}
	h.ok("dsl", "validate", generatedDSL)

	// The effective DSL the backend computes for the draft equals what the generation returned.
	draftDSL := filepath.Join(directory, "draft.dsl.json")
	h.ok("mods", "dsl", generated.SavedMod.ID, "-o", draftDSL)
	fromGeneration, err := os.ReadFile(generatedDSL)
	if err != nil {
		t.Fatal(err)
	}
	fromDraft, err := os.ReadFile(draftDSL)
	if err != nil {
		t.Fatal(err)
	}
	if string(fromGeneration) != string(fromDraft) {
		t.Fatalf("the draft's effective DSL differs from the generated one\ngenerated: %s\ndraft: %s", fromGeneration, fromDraft)
	}

	// Edit the draft offline-first: check the patch locally, then save it, then compare both results.
	patch := writeFile(t, "hp.patch.json", `[{"op":"test","path":"/player/sprite","value":"`+spriteOf(t, string(fromDraft))+`"},{"op":"replace","path":"/player/hp","value":250}]`)
	offline := h.ok("dsl", "patch", draftDSL, patch, "--validate")
	saved := decode[sdk.Mod](t, h.ok("mods", "save", generated.SavedMod.ID, "--patch", patch, "--output", "json"))
	if saved.ParentID != generated.SavedMod.ID || !saved.Draft {
		t.Fatalf("mods save = %+v", saved)
	}
	if online := h.ok("mods", "dsl", saved.ID); online != offline {
		t.Fatalf("the backend and the offline patch disagree\nbackend: %s\noffline: %s", online, offline)
	}
	drafts := decode[itemList[sdk.Mod]](t, h.ok("mods", "list", "--output", "json"))
	if len(drafts.Items) != 2 || drafts.Items[0].ID != saved.ID {
		t.Fatalf("mods list = %+v, want the two drafts of this run with the newest first", drafts.Items)
	}

	game := decode[sdk.Game](t, h.ok("mods", "publish", saved.ID, "--title", "CLI e2e game", "--summary", "created by the CLI end-to-end test", "--tag", "e2e", "--output", "json"))
	if game.Status != sdk.GameStatusReviewing || game.ModID != saved.ID || game.Runtime != "shooter@1.0.0" {
		t.Fatalf("published game = %+v", game)
	}
	mine := decode[itemList[sdk.Game]](t, h.ok("games", "mine", "--output", "json"))
	if len(mine.Items) != 1 || mine.Items[0].ID != game.ID {
		t.Fatalf("games mine = %+v", mine.Items)
	}
	mustContain(t, h.fails("games", "delist", game.ID).stderr, sdk.CodeInvalidState+": ")

	quota := decode[sdk.AIQuota](t, h.ok("ai", "quota", "--output", "json"))
	if quota.Limit <= 0 || quota.Used < 1 || quota.Used+quota.Remaining != quota.Limit {
		t.Fatalf("ai quota = %+v", quota)
	}

	h.ok("auth", "logout")
	h.fails("auth", "status")
	mustContain(t, h.fails("games", "mine").stderr, "not logged in")
}

func spriteOf(t *testing.T, document string) string {
	t.Helper()
	player, _ := decode[map[string]any](t, document)["player"].(map[string]any)
	sprite, ok := player["sprite"].(string)
	if !ok {
		t.Fatalf("the DSL has no player.sprite string: %s", document)
	}
	return sprite
}

// TestE2EReadmeExample walks the first example of the README ("Start a game from the runtime baseline, change it with a hand-written patch and publish it") against a real backend, so the documented sequence keeps working on a freshly started server. It also checks what the README says about the seeded showcase games.
func TestE2EReadmeExample(t *testing.T) {
	server := os.Getenv(envE2EURL)
	if server == "" {
		t.Skipf("set %s to the URL of a running backend to run this test", envE2EURL)
	}
	h := newHarness(t)
	h.env[EnvServerURL] = server
	h.env[EnvSchemaDir] = repoPath(t, "packages", "schemas")
	directory := t.TempDir()
	current := filepath.Join(directory, "current.dsl.json")

	h.ok("auth", "login")
	draft := decode[sdk.Mod](t, h.ok("mods", "create", "--runtime", "shooter@1.0.0", "--output", "json"))
	h.ok("mods", "dsl", draft.ID, "-o", current)
	patch := writeFile(t, "patch.json", `[{"op":"replace","path":"/player/hp","value":250}]`)
	h.ok("dsl", "patch", current, patch, "--validate")
	saved := decode[sdk.Mod](t, h.ok("mods", "save", draft.ID, "--patch", patch, "--output", "json"))
	game := decode[sdk.Game](t, h.ok("mods", "publish", saved.ID, "--title", "Tanky", "--output", "json"))
	if game.Status != sdk.GameStatusReviewing || game.ModID != saved.ID {
		t.Fatalf("published game = %+v", game)
	}
	mustContain(t, h.ok("mods", "publish", "--help"), "--forked-from")

	// A game without a mod behind it is listed but cannot be read or forked.
	catalog := decode[itemPage[sdk.Game]](t, h.ok("games", "list", "--all", "--output", "json"))
	for _, listed := range catalog.Items {
		if listed.Runtime != "" {
			continue
		}
		for _, command := range []string{"dsl", "fork"} {
			if got := h.fails("games", command, listed.ID); got.stdout != "" {
				t.Fatalf("games %s on a game without a mod printed %q", command, got.stdout)
			}
		}
		break
	}
	h.ok("auth", "logout")
}
