package sdk

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

// PatchOp is one RFC 6902 JSON Patch operation, the unit the AI emits and a mod stores. The backend applies add, replace, remove and test; move and copy are rejected. Its fields and JSON shape are identical to dsl.Op in forgeplay/dsl, so a value converts directly with dsl.Op(op) or sdk.PatchOp(op).
type PatchOp struct {
	Op    string          `json:"op"`
	Path  string          `json:"path"`
	Value json.RawMessage `json:"value,omitempty"`
}

// Mod is one node of the creation graph: a patch relative to the effective DSL of its parent, or relative to the runtime baseline when ParentID is empty. Mods are immutable; saving a draft creates a child mod.
type Mod struct {
	ID       string `json:"id"`
	ParentID string `json:"parent_id,omitempty"`
	// Runtime is a runtime ref such as "shooter@1.0.0". A child always inherits its parent's runtime.
	Runtime string    `json:"runtime"`
	Patch   []PatchOp `json:"patch"`
	// AIGenerated is set by the backend only: when the mod was created with a valid provenance token from an AI endpoint, or when its parent is AI-generated.
	AIGenerated bool      `json:"ai_generated"`
	AuthorID    string    `json:"author_id,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	// Draft marks an unpublished mod. A draft is readable and forkable only by its author.
	Draft bool `json:"draft"`
}

// ForkTree is the local fork tree around one mod.
type ForkTree struct {
	// Ancestors runs from the root mod down to the parent of Node. Other users' drafts are left out.
	Ancestors []Mod `json:"ancestors"`
	Node      Mod   `json:"node"`
	// Children are the direct children of Node that are not drafts. Drafts are never listed here, not even the caller's own.
	Children []Mod `json:"children"`
}

// CreateModRequest is the body of POST /api/v1/mods.
type CreateModRequest struct {
	// Runtime is the runtime ref for a root mod, such as "shooter@1.0.0". It is ignored when ParentID is set.
	Runtime string `json:"runtime,omitempty"`
	// ParentID makes the new mod a child of an existing mod; empty creates a root mod on the runtime baseline.
	ParentID string `json:"parent_id,omitempty"`
	// Patch is relative to the parent's effective DSL (or to the baseline for a root mod). The backend stores it as is and does not apply it at creation time, so a patch that does not apply only surfaces as 422 DSL_INVALID when the effective DSL is read.
	Patch []PatchOp `json:"patch"`
	// AIProvenance is the Provenance token returned by GenerateMod, GenerateStructure or AutoBalance. A valid token marks the mod as AI-generated; an empty or invalid one is ignored.
	AIProvenance string `json:"ai_provenance,omitempty"`
	// Draft creates the mod as a draft that can be saved again with SaveDraft and published with PublishDraft.
	Draft bool `json:"draft,omitempty"`
}

// CreateMod calls POST /api/v1/mods. Requires a token; the author is the token's user. Creating a child of someone else's draft fails with 403 FORBIDDEN.
func (c *Client) CreateMod(ctx context.Context, request CreateModRequest) (*Mod, error) {
	var out Mod
	if err := c.do(ctx, http.MethodPost, api("mods"), nil, request, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// ForkMod calls POST /api/v1/mods/{id}/fork and creates a draft child with an empty patch, so its effective DSL starts equal to the forked mod. Requires a token. Forking someone else's draft fails with 403 FORBIDDEN.
func (c *Client) ForkMod(ctx context.Context, modID string) (*Mod, error) {
	var out Mod
	if err := c.do(ctx, http.MethodPost, api("mods", segment(modID), "fork"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// GetMod returns one mod. The backend has no dedicated endpoint for a single mod, so this reads GET /api/v1/mods/{id}/fork-tree and returns its node; use GetModForkTree when ancestors or children are needed too. The same visibility rules apply.
func (c *Client) GetMod(ctx context.Context, modID string) (*Mod, error) {
	tree, err := c.GetModForkTree(ctx, modID)
	if err != nil {
		return nil, err
	}
	return &tree.Node, nil
}

// GetModDSL calls GET /api/v1/mods/{id}/dsl and returns the effective DSL: the runtime baseline with every patch from the root mod down to this one applied. Public for non-draft mods; a draft needs its author's token, otherwise 403 FORBIDDEN. A patch chain that does not apply fails with 422 DSL_INVALID.
func (c *Client) GetModDSL(ctx context.Context, modID string) (map[string]any, error) {
	var out map[string]any
	if err := c.do(ctx, http.MethodGet, api("mods", segment(modID), "dsl"), nil, nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// GetModLineage calls GET /api/v1/mods/{id}/lineage and returns the chain from the root mod to this one, root first. Other users' drafts are left out. Same visibility as GetModDSL.
func (c *Client) GetModLineage(ctx context.Context, modID string) ([]Mod, error) {
	return listItems[Mod](ctx, c, api("mods", segment(modID), "lineage"), nil)
}

// GetModForkTree calls GET /api/v1/mods/{id}/fork-tree. Same visibility as GetModDSL. An answer whose node is not the requested mod is reported as 404 NOT_FOUND.
func (c *Client) GetModForkTree(ctx context.Context, modID string) (*ForkTree, error) {
	var out ForkTree
	path := api("mods", segment(modID), "fork-tree")
	if err := c.do(ctx, http.MethodGet, path, nil, nil, &out); err != nil {
		return nil, err
	}
	if out.Node.ID != modID {
		return nil, notTheResource(path, "mod", modID)
	}
	return &out, nil
}

// ListMyMods calls GET /api/v1/mods/mine. Requires a token. The listing is not paginated and is ordered newest first. The current backend only returns the caller's draft mods here, the same set as ListDrafts: a mod created with Draft false, or a draft that has been published, is not listed. Reach published mods through ListMyGames and Game.ModID.
func (c *Client) ListMyMods(ctx context.Context) ([]Mod, error) {
	return listItems[Mod](ctx, c, api("mods", "mine"), nil)
}

// ListDrafts calls GET /api/v1/drafts and returns the token user's draft mods, newest first. Requires a token. The listing is not paginated.
func (c *Client) ListDrafts(ctx context.Context) ([]Mod, error) {
	return listItems[Mod](ctx, c, api("drafts"), nil)
}

// SaveDraft calls PUT /api/v1/drafts/{id}. Drafts are immutable versions: the call creates and returns a new draft mod whose parent is draftID and whose patch is relative to draftID's effective DSL. Keep working with the returned id. Requires the author's token; a non-draft target fails with 409 INVALID_STATE.
func (c *Client) SaveDraft(ctx context.Context, draftID string, patch []PatchOp) (*Mod, error) {
	body := struct {
		Patch []PatchOp `json:"patch"`
	}{Patch: patch}
	var out Mod
	if err := c.do(ctx, http.MethodPut, api("drafts", segment(draftID)), nil, body, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// PublishDraftRequest is the body of POST /api/v1/drafts/{id}/publish.
type PublishDraftRequest struct {
	// Title is required.
	Title   string `json:"title"`
	Summary string `json:"summary,omitempty"`
	// Tags holds at most 3 entries.
	Tags     []string `json:"tags,omitempty"`
	Category string   `json:"category,omitempty"`
	// ForkedFrom is the id of the game this work was forked from, when there is one.
	ForkedFrom string `json:"forked_from,omitempty"`
	// AIGenerated lets the author declare AI involvement. The backend forces it to true when the mod carries a valid AI provenance mark.
	AIGenerated bool `json:"ai_generated,omitempty"`
}

// PublishDraft calls POST /api/v1/drafts/{id}/publish. It clears the draft flag of the mod and creates a game in status "reviewing"; the game becomes public once a moderator approves it. Requires the author's token. A non-draft mod fails with 409 INVALID_STATE; a missing title, more than 3 tags or an effective DSL that fails schema validation fails with 400 PUBLISH_INVALID and leaves the draft untouched.
func (c *Client) PublishDraft(ctx context.Context, draftID string, request PublishDraftRequest) (*Game, error) {
	var out Game
	if err := c.do(ctx, http.MethodPost, api("drafts", segment(draftID), "publish"), nil, request, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// SplitRuntimeRef splits a runtime ref such as "shooter@1.0.0" into its name and version. ok is false when ref is not of the form "<name>@<version>".
func SplitRuntimeRef(ref string) (name, version string, ok bool) {
	name, version, found := strings.Cut(ref, "@")
	if !found || name == "" || version == "" || strings.Contains(version, "@") {
		return "", "", false
	}
	return name, version, true
}
