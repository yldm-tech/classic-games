package sdk_test

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"reflect"
	"slices"
	"testing"
	"time"

	"forgeplay/sdk"
)

// e2eURLEnv names the environment variable that points TestE2E at a running backend. The backend package is internal to apps/server and cannot be booted in-process from this module, so the test talks to a real server over HTTP and is skipped when the variable is unset.
//
// The backend must run with the stub AI provider (no ANTHROPIC_API_KEY) so generation is deterministic and free. From apps/server:
//
//	PORT=18080 FORGEPLAY_DB=/tmp/forgeplay-e2e.db FORGEPLAY_SECRET=local-e2e-secret go run ./cmd/server
//	FORGEPLAY_SDK_E2E_URL=http://127.0.0.1:18080 go test ./... -run TestE2E -count=1   (from packages/sdk)
const e2eURLEnv = "FORGEPLAY_SDK_E2E_URL"

func wantAPIError(t *testing.T, label string, err error, status int, code string) {
	t.Helper()
	if err == nil {
		t.Fatalf("%s: got nil, want %d %s", label, status, code)
	}
	if !sdk.IsStatus(err, status) || !sdk.IsCode(err, code) {
		t.Fatalf("%s: got %v, want %d %s", label, err, status, code)
	}
}

func randomDigits(t *testing.T, count int) string {
	t.Helper()
	raw := make([]byte, count)
	if _, err := rand.Read(raw); err != nil {
		t.Fatalf("random digits: %v", err)
	}
	for i := range raw {
		raw[i] = '0' + raw[i]%10
	}
	return string(raw)
}

func randomHex(t *testing.T, bytes int) string {
	t.Helper()
	raw := make([]byte, bytes)
	if _, err := rand.Read(raw); err != nil {
		t.Fatalf("random hex: %v", err)
	}
	return hex.EncodeToString(raw)
}

func modIDs(mods []sdk.Mod) []string {
	ids := make([]string, len(mods))
	for i, mod := range mods {
		ids[i] = mod.ID
	}
	return ids
}

func TestE2E(t *testing.T) {
	baseURL := os.Getenv(e2eURLEnv)
	if baseURL == "" {
		t.Skipf("%s is not set; start a backend and point the variable at it to run the end-to-end test", e2eURLEnv)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	anonymous := newClient(t, baseURL, sdk.WithLanguage("en"))
	client := newClient(t, baseURL, sdk.WithLanguage("en"), sdk.WithUserAgent("forgeplay-sdk-e2e"))

	// ---- health and meta ----
	if err := anonymous.Health(ctx); err != nil {
		t.Fatalf("Health: %v", err)
	}
	meta, err := anonymous.Meta(ctx)
	if err != nil {
		t.Fatalf("Meta: %v", err)
	}
	if meta.Environment != "development" && meta.Environment != "production" {
		t.Errorf("Meta.Environment: got %q, want development or production", meta.Environment)
	}
	if meta.AI.Mode != sdk.AIModeStub {
		t.Fatalf("Meta.AI.Mode: got %q, want %q; run the end-to-end test against a backend without ANTHROPIC_API_KEY", meta.AI.Mode, sdk.AIModeStub)
	}

	// ---- auth: anonymous is rejected, guest login works ----
	_, err = anonymous.CurrentUser(ctx)
	wantAPIError(t, "CurrentUser without token", err, http.StatusUnauthorized, sdk.CodeAuthRequired)
	if !sdk.IsUnauthorized(err) {
		t.Errorf("IsUnauthorized: got false for %v", err)
	}

	session, err := client.LoginGuest(ctx)
	if err != nil {
		t.Fatalf("LoginGuest: %v", err)
	}
	if session.Token == "" || session.User.ID == "" || session.User.Nickname == "" {
		t.Fatalf("LoginGuest: incomplete session %#v", session)
	}
	client.SetToken(session.Token)
	me, err := client.CurrentUser(ctx)
	if err != nil {
		t.Fatalf("CurrentUser: %v", err)
	}
	if *me != session.User {
		t.Errorf("CurrentUser: got %#v, want the login user %#v", *me, session.User)
	}
	userID := me.ID

	// ---- catalog: list, paginate, search, filter, get ----
	firstPage, err := anonymous.ListGames(ctx, sdk.ListGamesParams{PageParams: sdk.PageParams{Limit: sdk.MaxPageLimit}})
	if err != nil {
		t.Fatalf("ListGames: %v", err)
	}
	if len(firstPage.Items) < 3 {
		t.Fatalf("ListGames: got %d games, want the seeded catalog (at least 3)", len(firstPage.Items))
	}
	for _, game := range firstPage.Items {
		if game.Status != sdk.GameStatusPublished {
			t.Errorf("ListGames: game %s has status %q, want published", game.ID, game.Status)
		}
		if game.ID == "" || game.Title == "" || game.CreatedAt.IsZero() {
			t.Errorf("ListGames: incomplete game %#v", game)
		}
	}
	smallPage, err := anonymous.ListGames(ctx, sdk.ListGamesParams{PageParams: sdk.PageParams{Limit: 2}})
	if err != nil {
		t.Fatalf("ListGames(limit=2): %v", err)
	}
	if len(smallPage.Items) != 2 || !smallPage.HasMore() {
		t.Fatalf("ListGames(limit=2): got %d items and next cursor %q, want 2 items and a next page", len(smallPage.Items), smallPage.NextCursor)
	}
	var walked []string
	for game, err := range sdk.Paginate(ctx, func(ctx context.Context, cursor string) (*sdk.Page[sdk.Game], error) {
		return anonymous.ListGames(ctx, sdk.ListGamesParams{PageParams: sdk.PageParams{Cursor: cursor, Limit: 2}})
	}) {
		if err != nil {
			t.Fatalf("Paginate(ListGames): %v", err)
		}
		walked = append(walked, game.ID)
	}
	var listed []string
	for _, game := range firstPage.Items {
		listed = append(listed, game.ID)
	}
	if firstPage.HasMore() {
		t.Logf("catalog has more than %d games; comparing the first page only", sdk.MaxPageLimit)
		walked = walked[:len(listed)]
	}
	if !reflect.DeepEqual(walked, listed) {
		t.Errorf("Paginate(ListGames, limit=2): got %v, want the same order as one large page %v", walked, listed)
	}

	seed := firstPage.Items[0]
	// Search by author name: the backend matches the query against the stored default-language title and summary, so a title localized by WithLanguage is not a reliable search term.
	found, err := anonymous.ListGames(ctx, sdk.ListGamesParams{Query: seed.By})
	if err != nil {
		t.Fatalf("ListGames(q): %v", err)
	}
	if !slices.ContainsFunc(found.Items, func(game sdk.Game) bool { return game.ID == seed.ID }) {
		t.Errorf("ListGames(q=%q): game %s is missing from %d results", seed.By, seed.ID, len(found.Items))
	}
	for _, game := range found.Items {
		if game.By != seed.By {
			t.Logf("ListGames(q=%q) also matched %s by %s through its title, summary or tags", seed.By, game.ID, game.By)
		}
	}
	none, err := anonymous.ListGames(ctx, sdk.ListGamesParams{Query: "no-such-game-" + randomHex(t, 8)})
	if err != nil {
		t.Fatalf("ListGames(q=nonsense): %v", err)
	}
	if len(none.Items) != 0 || none.HasMore() {
		t.Errorf("ListGames(q=nonsense): got %d items, want none", len(none.Items))
	}
	byCategory, err := anonymous.ListGames(ctx, sdk.ListGamesParams{Category: seed.Category, Sort: sdk.SortHot})
	if err != nil {
		t.Fatalf("ListGames(category, sort=hot): %v", err)
	}
	if len(byCategory.Items) == 0 {
		t.Errorf("ListGames(category=%q): got no games, want at least %s", seed.Category, seed.ID)
	}
	for i, game := range byCategory.Items {
		if game.Category != seed.Category {
			t.Errorf("ListGames(category=%q): game %s has category %q", seed.Category, game.ID, game.Category)
		}
		if i > 0 && game.Likes > byCategory.Items[i-1].Likes {
			t.Errorf("ListGames(sort=hot): game %s with %d likes is listed after one with %d", game.ID, game.Likes, byCategory.Items[i-1].Likes)
		}
	}
	_, err = anonymous.ListGames(ctx, sdk.ListGamesParams{Sort: "bogus"})
	wantAPIError(t, "ListGames(sort=bogus)", err, http.StatusBadRequest, sdk.CodeBadRequest)
	_, err = anonymous.ListGames(ctx, sdk.ListGamesParams{PageParams: sdk.PageParams{Cursor: "!!not-a-cursor!!"}})
	wantAPIError(t, "ListGames(bad cursor)", err, http.StatusBadRequest, sdk.CodeBadRequest)

	fetched, err := anonymous.GetGame(ctx, seed.ID)
	if err != nil {
		t.Fatalf("GetGame: %v", err)
	}
	if fetched.ID != seed.ID || fetched.Title != seed.Title || fetched.ModID != seed.ModID {
		t.Errorf("GetGame: got %#v, want the listed game %#v", fetched, seed)
	}
	_, err = anonymous.GetGame(ctx, "no-such-game")
	wantAPIError(t, "GetGame(unknown)", err, http.StatusNotFound, sdk.CodeNotFound)
	if !sdk.IsNotFound(err) {
		t.Errorf("IsNotFound: got false for %v", err)
	}
	var apiErr *sdk.APIError
	if !errors.As(err, &apiErr) || apiErr.Message != "The requested resource was not found" {
		t.Errorf("GetGame(unknown): got %v, want the English message selected by WithLanguage", err)
	}

	// ---- ranking ----
	ranking, err := anonymous.GetRanking(ctx, sdk.RankingParams{Type: sdk.SortHot, Limit: 3})
	if err != nil {
		t.Fatalf("GetRanking: %v", err)
	}
	if ranking.Type != sdk.SortHot || len(ranking.Items) != 3 {
		t.Fatalf("GetRanking(hot, limit=3): got type %q with %d items", ranking.Type, len(ranking.Items))
	}
	for i, item := range ranking.Items {
		if item.Rank != i+1 {
			t.Errorf("GetRanking: item %d has rank %d, want %d", i, item.Rank, i+1)
		}
		if i > 0 && item.Likes > ranking.Items[i-1].Likes {
			t.Errorf("GetRanking(hot): %s with %d likes ranks below one with %d", item.ID, item.Likes, ranking.Items[i-1].Likes)
		}
	}
	top, err := anonymous.GetGame(ctx, ranking.Items[0].ID)
	if err != nil {
		t.Fatalf("GetGame(top ranked): %v", err)
	}
	if ranking.Items[0].Title != top.Title {
		t.Errorf("GetRanking: title %q differs from GetGame title %q, so the language was not applied to the ranking", ranking.Items[0].Title, top.Title)
	}
	_, err = anonymous.GetRanking(ctx, sdk.RankingParams{Type: "bogus"})
	wantAPIError(t, "GetRanking(type=bogus)", err, http.StatusBadRequest, sdk.CodeBadRequest)

	// ---- runtimes ----
	const runtimeRef = "shooter@1.0.0"
	runtimeName, runtimeVersion, ok := sdk.SplitRuntimeRef(runtimeRef)
	if !ok {
		t.Fatalf("SplitRuntimeRef(%q) failed", runtimeRef)
	}
	schema, err := anonymous.GetRuntimeSchema(ctx, runtimeName, runtimeVersion)
	if err != nil {
		t.Fatalf("GetRuntimeSchema: %v", err)
	}
	var schemaDoc map[string]any
	if err := json.Unmarshal(schema, &schemaDoc); err != nil {
		t.Fatalf("GetRuntimeSchema: not a JSON object: %v", err)
	}
	if _, has := schemaDoc["$schema"]; !has {
		t.Errorf("GetRuntimeSchema: document has no $schema key")
	}
	baseline, err := anonymous.GetRuntimeBaseline(ctx, runtimeName, runtimeVersion)
	if err != nil {
		t.Fatalf("GetRuntimeBaseline: %v", err)
	}
	baselineMeta, _ := baseline["meta"].(map[string]any)
	if baselineMeta["runtime"] != runtimeName || baselineMeta["runtime_version"] != runtimeVersion {
		t.Errorf("GetRuntimeBaseline: meta is %v, want runtime %s version %s", baselineMeta, runtimeName, runtimeVersion)
	}
	_, err = anonymous.GetRuntimeSchema(ctx, "no_such_runtime", "9.9.9")
	wantAPIError(t, "GetRuntimeSchema(unknown)", err, http.StatusNotFound, sdk.CodeNotFound)
	_, err = anonymous.GetRuntimeBaseline(ctx, runtimeName, "9.9.9")
	wantAPIError(t, "GetRuntimeBaseline(wrong version)", err, http.StatusNotFound, sdk.CodeNotFound)

	// ---- AI: validate, quota semantics, generation ----
	if err := anonymous.ValidateDSL(ctx, runtimeRef, baseline); err != nil {
		t.Fatalf("ValidateDSL(baseline): %v", err)
	}
	err = anonymous.ValidateDSL(ctx, runtimeRef, map[string]any{"bogus": true})
	wantAPIError(t, "ValidateDSL(invalid)", err, http.StatusUnprocessableEntity, sdk.CodeDSLInvalid)

	quotaBefore, err := client.AIQuota(ctx)
	if err != nil {
		t.Fatalf("AIQuota: %v", err)
	}
	if quotaBefore.Limit <= 0 || quotaBefore.Used+quotaBefore.Remaining != quotaBefore.Limit {
		t.Fatalf("AIQuota: inconsistent snapshot %#v", quotaBefore)
	}
	if quotaBefore.Remaining < 2 {
		t.Fatalf("AIQuota: only %d calls left today for this client address; restart the backend with a fresh database", quotaBefore.Remaining)
	}

	_, err = client.GenerateMod(ctx, sdk.GenerateModRequest{Runtime: runtimeRef, Prompt: "missing dsl"})
	wantAPIError(t, "GenerateMod(without current_dsl)", err, http.StatusBadRequest, sdk.CodeBadRequest)
	quotaRefunded, err := client.AIQuota(ctx)
	if err != nil {
		t.Fatalf("AIQuota: %v", err)
	}
	if quotaRefunded.Used != quotaBefore.Used {
		t.Errorf("AIQuota after a rejected request: used %d, want %d (a 400 must be refunded)", quotaRefunded.Used, quotaBefore.Used)
	}

	generated, err := client.GenerateMod(ctx, sdk.GenerateModRequest{Runtime: runtimeRef, CurrentDSL: baseline, Prompt: "turn the player into a cat"})
	if err != nil {
		t.Fatalf("GenerateMod: %v", err)
	}
	wantStubPatch := []sdk.PatchOp{{Op: "replace", Path: "/player/sprite", Value: json.RawMessage(`"cat"`)}}
	if !reflect.DeepEqual(generated.DSLPatch, wantStubPatch) {
		t.Errorf("GenerateMod: patch %+v, want the stub patch %+v", generated.DSLPatch, wantStubPatch)
	}
	generatedPlayer, _ := generated.NewDSL["player"].(map[string]any)
	if generatedPlayer["sprite"] != "cat" {
		t.Errorf("GenerateMod: new_dsl player sprite is %v, want cat", generatedPlayer["sprite"])
	}
	if generated.Model != "stub" || generated.Retries != 0 {
		t.Errorf("GenerateMod: model %q retries %d, want stub and 0", generated.Model, generated.Retries)
	}
	if err := anonymous.ValidateDSL(ctx, runtimeRef, generated.NewDSL); err != nil {
		t.Errorf("ValidateDSL(generated): %v", err)
	}
	quotaAfter, err := client.AIQuota(ctx)
	if err != nil {
		t.Fatalf("AIQuota: %v", err)
	}
	if quotaAfter.Used != quotaBefore.Used+1 || quotaAfter.Remaining != quotaBefore.Remaining-1 {
		t.Errorf("AIQuota after one generation: got %#v, want used %d remaining %d", quotaAfter, quotaBefore.Used+1, quotaBefore.Remaining-1)
	}

	structure, err := client.GenerateStructure(ctx, sdk.GenerateStructureRequest{Runtime: runtimeRef, CurrentDSL: baseline, Prompt: "two fast flyers", Count: 2, Difficulty: 3})
	if err != nil {
		t.Fatalf("GenerateStructure: %v", err)
	}
	structureEnemies, _ := structure.NewDSL["enemies"].(map[string]any)
	if len(structure.GeneratedKeys) != 2 || len(structure.DSLPatch) == 0 {
		t.Errorf("GenerateStructure: %d keys and %d ops, want 2 keys and a patch", len(structure.GeneratedKeys), len(structure.DSLPatch))
	}
	for _, key := range structure.GeneratedKeys {
		if _, has := structureEnemies[key]; !has {
			t.Errorf("GenerateStructure: generated key %q is missing from new_dsl enemies", key)
		}
	}
	_, err = client.GenerateStructure(ctx, sdk.GenerateStructureRequest{Runtime: runtimeRef, CurrentDSL: baseline, Prompt: "too many", Count: 99, Difficulty: 3})
	wantAPIError(t, "GenerateStructure(count=99)", err, http.StatusBadRequest, sdk.CodeBadRequest)

	balanced, err := anonymous.AutoBalance(ctx, sdk.AutoBalanceRequest{Runtime: runtimeRef, CurrentDSL: baseline, TargetDifficulty: 5})
	if err != nil {
		t.Fatalf("AutoBalance: %v", err)
	}
	if len(balanced.DSLPatch) == 0 || balanced.NewDSL == nil || balanced.Model == "" {
		t.Errorf("AutoBalance: incomplete response %#v", balanced)
	}
	_, err = anonymous.AutoBalance(ctx, sdk.AutoBalanceRequest{Runtime: runtimeRef, CurrentDSL: baseline, TargetDifficulty: 9})
	wantAPIError(t, "AutoBalance(difficulty=9)", err, http.StatusBadRequest, sdk.CodeBadRequest)

	// ---- mods: create from the AI result, read back, drafts ----
	_, err = anonymous.CreateMod(ctx, sdk.CreateModRequest{Runtime: runtimeRef, Patch: generated.DSLPatch})
	wantAPIError(t, "CreateMod without token", err, http.StatusUnauthorized, sdk.CodeAuthRequired)

	draft, err := client.CreateMod(ctx, sdk.CreateModRequest{Runtime: runtimeRef, Patch: generated.DSLPatch, AIProvenance: generated.Provenance, Draft: true})
	if err != nil {
		t.Fatalf("CreateMod: %v", err)
	}
	if draft.ID == "" || draft.Runtime != runtimeRef || !draft.Draft || draft.AuthorID != userID || draft.ParentID != "" || draft.CreatedAt.IsZero() {
		t.Errorf("CreateMod: unexpected mod %#v", draft)
	}
	if !reflect.DeepEqual(draft.Patch, generated.DSLPatch) {
		t.Errorf("CreateMod: stored patch %+v, want %+v", draft.Patch, generated.DSLPatch)
	}
	if wantAI := generated.Provenance != ""; draft.AIGenerated != wantAI {
		t.Errorf("CreateMod: ai_generated is %t, want %t (provenance token present: %t)", draft.AIGenerated, wantAI, wantAI)
	}
	draftDSL, err := client.GetModDSL(ctx, draft.ID)
	if err != nil {
		t.Fatalf("GetModDSL: %v", err)
	}
	if !reflect.DeepEqual(draftDSL, generated.NewDSL) {
		t.Errorf("GetModDSL: effective DSL differs from the AI new_dsl\n got  %v\n want %v", draftDSL, generated.NewDSL)
	}
	_, err = anonymous.GetModDSL(ctx, draft.ID)
	wantAPIError(t, "GetModDSL(someone else's draft)", err, http.StatusForbidden, sdk.CodeForbidden)
	_, err = client.GetModDSL(ctx, "mod_does_not_exist")
	wantAPIError(t, "GetModDSL(unknown)", err, http.StatusNotFound, sdk.CodeNotFound)

	gotMod, err := client.GetMod(ctx, draft.ID)
	if err != nil {
		t.Fatalf("GetMod: %v", err)
	}
	if gotMod.ID != draft.ID || gotMod.Runtime != draft.Runtime || gotMod.AuthorID != draft.AuthorID || gotMod.Draft != draft.Draft || gotMod.AIGenerated != draft.AIGenerated || !reflect.DeepEqual(gotMod.Patch, draft.Patch) || !gotMod.CreatedAt.Equal(draft.CreatedAt) {
		t.Errorf("GetMod: got %#v, want the created mod %#v", gotMod, draft)
	}

	speedPatch := []sdk.PatchOp{{Op: "replace", Path: "/player/speed", Value: json.RawMessage(`12`)}}
	saved, err := client.SaveDraft(ctx, draft.ID, speedPatch)
	if err != nil {
		t.Fatalf("SaveDraft: %v", err)
	}
	if saved.ID == draft.ID || saved.ParentID != draft.ID || !saved.Draft || saved.Runtime != runtimeRef {
		t.Errorf("SaveDraft: got %#v, want a new draft whose parent is %s", saved, draft.ID)
	}
	savedDSL, err := client.GetModDSL(ctx, saved.ID)
	if err != nil {
		t.Fatalf("GetModDSL(saved): %v", err)
	}
	savedPlayer, _ := savedDSL["player"].(map[string]any)
	if savedPlayer["sprite"] != "cat" || savedPlayer["speed"] != float64(12) {
		t.Errorf("GetModDSL(saved): player is %v, want sprite cat and speed 12 (both patches applied)", savedPlayer)
	}

	lineage, err := client.GetModLineage(ctx, saved.ID)
	if err != nil {
		t.Fatalf("GetModLineage: %v", err)
	}
	if got, want := modIDs(lineage), []string{draft.ID, saved.ID}; !reflect.DeepEqual(got, want) {
		t.Errorf("GetModLineage: got %v, want root first %v", got, want)
	}
	tree, err := client.GetModForkTree(ctx, saved.ID)
	if err != nil {
		t.Fatalf("GetModForkTree: %v", err)
	}
	if tree.Node.ID != saved.ID || !reflect.DeepEqual(modIDs(tree.Ancestors), []string{draft.ID}) || len(tree.Children) != 0 {
		t.Errorf("GetModForkTree: got node %s ancestors %v children %v", tree.Node.ID, modIDs(tree.Ancestors), modIDs(tree.Children))
	}

	drafts, err := client.ListDrafts(ctx)
	if err != nil {
		t.Fatalf("ListDrafts: %v", err)
	}
	if got, want := modIDs(drafts), []string{saved.ID, draft.ID}; !reflect.DeepEqual(got, want) {
		t.Errorf("ListDrafts: got %v, want newest first %v", got, want)
	}
	for _, mod := range drafts {
		if !mod.Draft {
			t.Errorf("ListDrafts: mod %s is not a draft", mod.ID)
		}
	}

	// ---- publish a draft, then read the game back ----
	_, err = client.PublishDraft(ctx, saved.ID, sdk.PublishDraftRequest{Title: "  "})
	wantAPIError(t, "PublishDraft(blank title)", err, http.StatusBadRequest, sdk.CodePublishInvalid)

	title := "SDK e2e " + randomHex(t, 4)
	game, err := client.PublishDraft(ctx, saved.ID, sdk.PublishDraftRequest{Title: title, Summary: "Published by the SDK end-to-end test", Tags: []string{"e2e", "cat"}, Category: "Arcade"})
	if err != nil {
		t.Fatalf("PublishDraft: %v", err)
	}
	if game.ID == "" || game.ModID != saved.ID || game.AuthorID != userID || game.Title != title || game.Status != sdk.GameStatusReviewing || game.Runtime != runtimeRef || game.Category != "Arcade" {
		t.Errorf("PublishDraft: unexpected game %#v", game)
	}
	if !reflect.DeepEqual(game.Tags, []string{"e2e", "cat"}) {
		t.Errorf("PublishDraft: tags %v, want [e2e cat]", game.Tags)
	}
	if wantAI := generated.Provenance != ""; game.AIGenerated != wantAI {
		t.Errorf("PublishDraft: ai_generated is %t, want %t (forced by the mod's provenance mark)", game.AIGenerated, wantAI)
	}
	_, err = client.PublishDraft(ctx, saved.ID, sdk.PublishDraftRequest{Title: title})
	wantAPIError(t, "PublishDraft(already published)", err, http.StatusConflict, sdk.CodeInvalidState)

	_, err = anonymous.GetGame(ctx, game.ID)
	wantAPIError(t, "GetGame(reviewing game, anonymous)", err, http.StatusNotFound, sdk.CodeNotFound)
	own, err := client.GetGame(ctx, game.ID)
	if err != nil {
		t.Fatalf("GetGame(own reviewing game): %v", err)
	}
	if own.ID != game.ID || own.Status != sdk.GameStatusReviewing {
		t.Errorf("GetGame(own reviewing game): got %#v", own)
	}
	gameDSL, err := client.GetGameDSL(ctx, game.ID)
	if err != nil {
		t.Fatalf("GetGameDSL: %v", err)
	}
	if !reflect.DeepEqual(gameDSL, savedDSL) {
		t.Errorf("GetGameDSL: differs from the published mod's effective DSL")
	}
	gameLineage, err := client.GetGameLineage(ctx, game.ID)
	if err != nil {
		t.Fatalf("GetGameLineage: %v", err)
	}
	if got, want := modIDs(gameLineage), []string{draft.ID, saved.ID}; !reflect.DeepEqual(got, want) {
		t.Errorf("GetGameLineage: got %v, want %v", got, want)
	}
	gameTree, err := client.GetGameForkTree(ctx, game.ID)
	if err != nil {
		t.Fatalf("GetGameForkTree: %v", err)
	}
	if gameTree.Node.ID != saved.ID || gameTree.Node.Draft {
		t.Errorf("GetGameForkTree: node %#v, want mod %s with the draft flag cleared by publishing", gameTree.Node, saved.ID)
	}
	myGames, err := client.ListMyGames(ctx)
	if err != nil {
		t.Fatalf("ListMyGames: %v", err)
	}
	if !slices.ContainsFunc(myGames, func(g sdk.Game) bool { return g.ID == game.ID }) {
		t.Errorf("ListMyGames: game %s is missing from %d games", game.ID, len(myGames))
	}
	_, err = client.DelistGame(ctx, game.ID)
	wantAPIError(t, "DelistGame(reviewing game)", err, http.StatusConflict, sdk.CodeInvalidState)
	_, err = client.ResubmitGame(ctx, game.ID)
	wantAPIError(t, "ResubmitGame(reviewing game)", err, http.StatusConflict, sdk.CodeInvalidState)

	// ---- forks ----
	gameFork, err := client.ForkGame(ctx, game.ID)
	if err != nil {
		t.Fatalf("ForkGame: %v", err)
	}
	if gameFork.ParentID != saved.ID || !gameFork.Draft || len(gameFork.Patch) != 0 || gameFork.AuthorID != userID {
		t.Errorf("ForkGame: got %#v, want an empty draft child of %s", gameFork, saved.ID)
	}
	forkDSL, err := client.GetModDSL(ctx, gameFork.ID)
	if err != nil {
		t.Fatalf("GetModDSL(fork): %v", err)
	}
	if !reflect.DeepEqual(forkDSL, gameDSL) {
		t.Errorf("ForkGame: the fork's effective DSL differs from the game's")
	}
	modFork, err := client.ForkMod(ctx, saved.ID)
	if err != nil {
		t.Fatalf("ForkMod: %v", err)
	}
	if modFork.ParentID != saved.ID || !modFork.Draft || modFork.ID == gameFork.ID {
		t.Errorf("ForkMod: got %#v, want a new draft child of %s", modFork, saved.ID)
	}
	_, err = client.ForkMod(ctx, "mod_does_not_exist")
	wantAPIError(t, "ForkMod(unknown)", err, http.StatusNotFound, sdk.CodeNotFound)

	// ---- publish a non-draft mod directly ----
	child, err := client.CreateMod(ctx, sdk.CreateModRequest{ParentID: saved.ID, Patch: []sdk.PatchOp{{Op: "replace", Path: "/player/hp", Value: json.RawMessage(`150`)}}})
	if err != nil {
		t.Fatalf("CreateMod(child): %v", err)
	}
	if child.ParentID != saved.ID || child.Draft || child.Runtime != runtimeRef {
		t.Errorf("CreateMod(child): got %#v", child)
	}
	second, err := client.PublishGame(ctx, sdk.PublishGameRequest{ModID: child.ID, Title: title + " II", ForkedFrom: game.ID})
	if err != nil {
		t.Fatalf("PublishGame: %v", err)
	}
	if second.ModID != child.ID || second.Status != sdk.GameStatusReviewing || second.ForkedFrom != game.ID || second.AuthorID != userID {
		t.Errorf("PublishGame: unexpected game %#v", second)
	}
	_, err = client.PublishGame(ctx, sdk.PublishGameRequest{ModID: child.ID, Title: "too many tags", Tags: []string{"a", "b", "c", "d"}})
	wantAPIError(t, "PublishGame(4 tags)", err, http.StatusBadRequest, sdk.CodePublishInvalid)

	myMods, err := client.ListMyMods(ctx)
	if err != nil {
		t.Fatalf("ListMyMods: %v", err)
	}
	// The backend lists only drafts under /mods/mine, so the published mod and the non-draft child are not expected here.
	myModIDs := modIDs(myMods)
	for _, id := range []string{draft.ID, gameFork.ID, modFork.ID} {
		if !slices.Contains(myModIDs, id) {
			t.Errorf("ListMyMods: draft %s is missing from %v", id, myModIDs)
		}
	}
	for _, mod := range myMods {
		if mod.AuthorID != userID {
			t.Errorf("ListMyMods: mod %s belongs to %s, want only mods of %s", mod.ID, mod.AuthorID, userID)
		}
	}

	// ---- social: comments, likes, favorites, community ----
	comment, err := client.AddComment(ctx, seed.ID, "SDK e2e comment "+randomHex(t, 4))
	if err != nil {
		t.Fatalf("AddComment: %v", err)
	}
	if comment.ID == "" || comment.GameID != seed.ID || comment.AuthorID != userID || comment.CreatedAt.IsZero() {
		t.Errorf("AddComment: unexpected comment %#v", comment)
	}
	_, err = client.AddComment(ctx, seed.ID, "   ")
	wantAPIError(t, "AddComment(blank)", err, http.StatusBadRequest, sdk.CodeCommentInvalid)
	commentSeen := false
	for item, err := range sdk.Paginate(ctx, func(ctx context.Context, cursor string) (*sdk.Page[sdk.Comment], error) {
		return anonymous.ListComments(ctx, seed.ID, sdk.PageParams{Cursor: cursor, Limit: sdk.MaxPageLimit})
	}) {
		if err != nil {
			t.Fatalf("Paginate(ListComments): %v", err)
		}
		if item.ID == comment.ID && item.Content == comment.Content {
			commentSeen = true
		}
	}
	if !commentSeen {
		t.Errorf("ListComments: comment %s is missing", comment.ID)
	}

	liked, err := client.LikeGame(ctx, seed.ID)
	if err != nil {
		t.Fatalf("LikeGame: %v", err)
	}
	if !liked.Liked || liked.Count == nil {
		t.Fatalf("LikeGame: got %#v, want liked with a count", liked)
	}
	unliked, err := client.UnlikeGame(ctx, seed.ID)
	if err != nil {
		t.Fatalf("UnlikeGame: %v", err)
	}
	if unliked.Liked || unliked.Count == nil || *unliked.Count != *liked.Count-1 {
		t.Errorf("UnlikeGame: got liked=%t count=%v, want not liked and count %d", unliked.Liked, unliked.Count, *liked.Count-1)
	}

	if err := client.FavoriteGame(ctx, seed.ID); err != nil {
		t.Fatalf("FavoriteGame: %v", err)
	}
	favorites, err := client.ListFavorites(ctx)
	if err != nil {
		t.Fatalf("ListFavorites: %v", err)
	}
	if !slices.Contains(favorites, seed.ID) {
		t.Errorf("ListFavorites: got %v, want it to contain %s", favorites, seed.ID)
	}
	likedGames, err := anonymous.ListUserGames(ctx, userID, sdk.UserGamesLiked)
	if err != nil {
		t.Fatalf("ListUserGames(liked): %v", err)
	}
	if !slices.ContainsFunc(likedGames, func(g sdk.Game) bool { return g.ID == seed.ID }) {
		t.Errorf("ListUserGames(liked): favorite %s is missing from %d games", seed.ID, len(likedGames))
	}
	if err := client.UnfavoriteGame(ctx, seed.ID); err != nil {
		t.Fatalf("UnfavoriteGame: %v", err)
	}
	favorites, err = client.ListFavorites(ctx)
	if err != nil {
		t.Fatalf("ListFavorites: %v", err)
	}
	if slices.Contains(favorites, seed.ID) {
		t.Errorf("ListFavorites after UnfavoriteGame: still contains %s", seed.ID)
	}

	rated, err := client.RateGame(ctx, seed.ID, 4)
	if err != nil {
		t.Fatalf("RateGame: %v", err)
	}
	if rated.MyRating != 4 || rated.Count < 1 || rated.Average < 1 || rated.Average > 5 {
		t.Errorf("RateGame: got %#v, want my rating 4 inside a consistent summary", rated)
	}
	_, err = client.RateGame(ctx, seed.ID, 9)
	wantAPIError(t, "RateGame(9)", err, http.StatusBadRequest, sdk.CodeRatingInvalid)
	post, err := client.CreateCommunityPost(ctx, seed.ID, "SDK e2e post "+randomHex(t, 4))
	if err != nil {
		t.Fatalf("CreateCommunityPost: %v", err)
	}
	_, err = client.CreateCommunityPost(ctx, seed.ID, "")
	wantAPIError(t, "CreateCommunityPost(empty)", err, http.StatusBadRequest, sdk.CodePostInvalid)
	panel, err := client.GetGameCommunity(ctx, seed.ID)
	if err != nil {
		t.Fatalf("GetGameCommunity: %v", err)
	}
	if panel.MyRating != 4 || !slices.ContainsFunc(panel.Posts, func(p sdk.CommunityPost) bool { return p.ID == post.ID && p.AuthorID == userID }) {
		t.Errorf("GetGameCommunity: my rating %d and %d posts, want rating 4 and post %s", panel.MyRating, len(panel.Posts), post.ID)
	}
	anonymousPanel, err := anonymous.GetGameCommunity(ctx, seed.ID)
	if err != nil {
		t.Fatalf("GetGameCommunity(anonymous): %v", err)
	}
	if anonymousPanel.MyRating != 0 || anonymousPanel.Count != panel.Count {
		t.Errorf("GetGameCommunity(anonymous): got my rating %d count %d, want 0 and %d", anonymousPanel.MyRating, anonymousPanel.Count, panel.Count)
	}

	// ---- users ----
	profile, err := anonymous.GetUserProfile(ctx, seed.AuthorID)
	if err != nil {
		t.Fatalf("GetUserProfile: %v", err)
	}
	if profile.ID != seed.AuthorID || profile.Works < 1 {
		t.Errorf("GetUserProfile(%s): got %#v, want at least one work", seed.AuthorID, profile)
	}
	works, err := anonymous.ListUserGames(ctx, seed.AuthorID, sdk.UserGamesWorks)
	if err != nil {
		t.Fatalf("ListUserGames(works): %v", err)
	}
	if !slices.ContainsFunc(works, func(g sdk.Game) bool { return g.ID == seed.ID }) {
		t.Errorf("ListUserGames(%s, works): game %s is missing from %d games", seed.AuthorID, seed.ID, len(works))
	}
	if _, err := anonymous.ListFollowers(ctx, seed.AuthorID); err != nil {
		t.Errorf("ListFollowers: %v", err)
	}
	if _, err := anonymous.ListFollowing(ctx, userID); err != nil {
		t.Errorf("ListFollowing: %v", err)
	}

	// ---- library ----
	err = anonymous.RecordPlay(ctx, seed.ID, 90*time.Second)
	wantAPIError(t, "RecordPlay without token", err, http.StatusUnauthorized, sdk.CodeAuthRequired)
	if err := client.RecordPlay(ctx, seed.ID, 90*time.Second); err != nil {
		t.Fatalf("RecordPlay: %v", err)
	}
	err = client.RecordPlay(ctx, "no-such-game", time.Second)
	wantAPIError(t, "RecordPlay(unknown game)", err, http.StatusNotFound, sdk.CodeNotFound)
	history, err := client.ListHistory(ctx)
	if err != nil {
		t.Fatalf("ListHistory: %v", err)
	}
	playedToday := false
	for _, group := range history {
		for _, item := range group.Items {
			if group.Group == sdk.HistoryToday && item.Game.ID == seed.ID && item.MinutesPlayed == 2 {
				playedToday = true
			}
		}
	}
	if !playedToday {
		t.Errorf("ListHistory: want %s under today with 2 minutes (90s rounded up), got %#v", seed.ID, history)
	}
	downloads, err := client.ListDownloads(ctx)
	if err != nil {
		t.Fatalf("ListDownloads: %v", err)
	}
	if len(downloads) != 0 {
		t.Errorf("ListDownloads: a new account has %d downloads, want none", len(downloads))
	}
	anonymousLive, err := anonymous.ListLive(ctx)
	if err != nil {
		t.Fatalf("ListLive: %v", err)
	}
	for _, item := range anonymousLive {
		if item.Game.ID == "" || item.Streamer == "" {
			t.Errorf("ListLive: incomplete item %#v", item)
		}
	}

	// ---- replays ----
	frames := []sdk.ReplayFrame{{AtMS: 0, X: 10, Y: 10, HP: 3, Score: 0}, {AtMS: 1000, X: 30, Y: 10, HP: 3, Score: 120}, {AtMS: 2000, X: 60, Y: 20, HP: 2, Score: 300}}
	replay, err := client.SubmitReplay(ctx, seed.ID, sdk.SubmitReplayRequest{DurationMS: 2000, Frames: frames})
	if err != nil {
		t.Fatalf("SubmitReplay: %v", err)
	}
	if replay.ID == "" || replay.GameID != seed.ID || replay.UserID != userID || replay.Score != 300 || replay.DurationMS != 2000 || !reflect.DeepEqual(replay.Frames, frames) {
		t.Errorf("SubmitReplay: unexpected replay %#v", replay)
	}
	_, err = client.SubmitReplay(ctx, seed.ID, sdk.SubmitReplayRequest{DurationMS: 2000, Frames: frames[:1]})
	wantAPIError(t, "SubmitReplay(one frame)", err, http.StatusBadRequest, sdk.CodeReplayInvalid)
	latest, err := anonymous.GetLatestReplay(ctx, seed.ID, userID)
	if err != nil {
		t.Fatalf("GetLatestReplay: %v", err)
	}
	if latest.ID != replay.ID || latest.Score != 300 || len(latest.Frames) != len(frames) {
		t.Errorf("GetLatestReplay: got %#v, want replay %s", latest, replay.ID)
	}
	_, err = anonymous.GetLatestReplay(ctx, seed.ID, "user_without_replays")
	wantAPIError(t, "GetLatestReplay(no replay)", err, http.StatusNotFound, sdk.CodeReplayNotFound)
	leaderboard, err := anonymous.GetReplayLeaderboard(ctx, seed.ID)
	if err != nil {
		t.Fatalf("GetReplayLeaderboard: %v", err)
	}
	if !slices.ContainsFunc(leaderboard, func(entry sdk.LeaderboardEntry) bool {
		return entry.UserID == userID && entry.Score == 300 && entry.Rank >= 1 && entry.Nickname == me.Nickname
	}) {
		t.Errorf("GetReplayLeaderboard: want an entry for %s with score 300, got %#v", userID, leaderboard)
	}

	// ---- auth lifecycle: SMS and password errors, password, refresh, logout ----
	phone := "139" + randomDigits(t, 8)
	if err := anonymous.SendSMSCode(ctx, phone); err != nil {
		t.Fatalf("SendSMSCode: %v", err)
	}
	err = anonymous.SendSMSCode(ctx, phone)
	wantAPIError(t, "SendSMSCode(again within cooldown)", err, http.StatusTooManyRequests, sdk.CodeRateLimited)
	_, err = anonymous.LoginSMS(ctx, phone, "000000x")
	wantAPIError(t, "LoginSMS(wrong code)", err, http.StatusUnauthorized, sdk.CodeAuthInvalid)
	_, err = anonymous.LoginPassword(ctx, phone, "not-the-password")
	wantAPIError(t, "LoginPassword(wrong credentials)", err, http.StatusUnauthorized, sdk.CodeAuthInvalid)

	err = client.SetPassword(ctx, "short")
	wantAPIError(t, "SetPassword(too short)", err, http.StatusBadRequest, sdk.CodePasswordInvalid)
	if err := client.SetPassword(ctx, "e2e-"+randomHex(t, 8)); err != nil {
		t.Fatalf("SetPassword: %v", err)
	}

	oldToken := client.Token()
	newToken, err := client.RefreshToken(ctx)
	if err != nil {
		t.Fatalf("RefreshToken: %v", err)
	}
	if newToken == "" || newToken == oldToken {
		t.Fatalf("RefreshToken: got %q, want a new token", newToken)
	}
	if client.Token() != oldToken {
		t.Errorf("RefreshToken changed the client token; only SetToken may do that")
	}
	_, err = client.CurrentUser(ctx)
	wantAPIError(t, "CurrentUser with the rotated-out token", err, http.StatusUnauthorized, sdk.CodeAuthRequired)
	_, err = client.RefreshToken(ctx)
	wantAPIError(t, "RefreshToken with the rotated-out token", err, http.StatusUnauthorized, sdk.CodeAuthRequired)
	client.SetToken(newToken)
	refreshed, err := client.CurrentUser(ctx)
	if err != nil {
		t.Fatalf("CurrentUser after refresh: %v", err)
	}
	if refreshed.ID != userID {
		t.Errorf("CurrentUser after refresh: got user %s, want %s", refreshed.ID, userID)
	}

	if err := client.Logout(ctx); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	_, err = client.CurrentUser(ctx)
	wantAPIError(t, "CurrentUser after logout", err, http.StatusUnauthorized, sdk.CodeAuthRequired)
	if err := client.Logout(ctx); err != nil {
		t.Errorf("Logout twice: %v, want nil because logout is idempotent", err)
	}
}
