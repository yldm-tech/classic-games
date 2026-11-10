package server

import (
	"context"
	"fmt"
	"strings"

	"forgeplay/sdk"

	"github.com/google/jsonschema-go/jsonschema"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// The write tools create drafts, save patches, spend AI quota or publish. They are left out in read-only mode.

// maxTags is the number of tags the backend accepts on a published game.
const maxTags = 3

type draftOutput struct {
	ModInfo
	DSL map[string]any `json:"dsl" jsonschema:"the draft's effective DSL after this call; write the next patch against it"`
}

type forkGameOutput struct {
	ModInfo
	ForkedFrom string         `json:"forked_from" jsonschema:"id of the forked game; pass it as forked_from to publish_mod so the new game credits its origin"`
	DSL        map[string]any `json:"dsl" jsonschema:"the draft's effective DSL, equal to the forked game's; write the patch against it"`
}

type createModInput struct {
	Runtime      string    `json:"runtime" jsonschema:"runtime ref whose baseline the draft starts from, for example shooter@1.0.0; list_runtimes returns the valid values"`
	Patch        []PatchOp `json:"patch,omitempty" jsonschema:"RFC 6902 operations relative to the runtime baseline. Omit to create an unmodified draft and receive the baseline DSL."`
	AIProvenance string    `json:"ai_provenance,omitempty" jsonschema:"the provenance value returned by generate_mod, when the patch came from it; it labels the mod as AI-generated"`
}

type updateModInput struct {
	ModID        string    `json:"mod_id" jsonschema:"id of the draft to build on, as returned by fork_game, create_mod, a previous update_mod or list_my_drafts"`
	Patch        []PatchOp `json:"patch" jsonschema:"RFC 6902 operations relative to the draft's current effective DSL, applied in order"`
	AIProvenance string    `json:"ai_provenance,omitempty" jsonschema:"the provenance value returned by generate_mod, when the patch came from it; it labels the mod as AI-generated"`
}

type generateModInput struct {
	Instruction string         `json:"instruction" jsonschema:"what to change, in natural language, for example: make the player a cat and double the boss health"`
	ModID       string         `json:"mod_id,omitempty" jsonschema:"use the effective DSL of this mod as the document to change. Pass exactly one of mod_id, game_id or dsl."`
	GameID      string         `json:"game_id,omitempty" jsonschema:"use the effective DSL of this game as the document to change. Pass exactly one of mod_id, game_id or dsl."`
	DSL         map[string]any `json:"dsl,omitempty" jsonschema:"a complete DSL document to change. Pass exactly one of mod_id, game_id or dsl."`
	Runtime     string         `json:"runtime,omitempty" jsonschema:"runtime ref of the document, for example shooter@1.0.0. Defaults to meta.runtime and meta.runtime_version of the document."`
}

type generateModOutput struct {
	Runtime     string         `json:"runtime" jsonschema:"runtime ref of the document"`
	Patch       []PatchOp      `json:"patch" jsonschema:"the RFC 6902 patch the backend AI produced, relative to the source document"`
	DSL         map[string]any `json:"dsl" jsonschema:"the source document with the patch applied, already validated by the backend"`
	BalanceHint string         `json:"balance_hint" jsonschema:"optional remark from the model about game balance; an empty string when there is none"`
	Model       string         `json:"model" jsonschema:"model that produced the patch; stub means the backend runs without a real model and returns a fixed patch"`
	Retries     int            `json:"retries" jsonschema:"extra model calls the backend needed before the result was valid"`
	Provenance  string         `json:"provenance" jsonschema:"signed proof that the patch came from the backend AI; pass it as ai_provenance to update_mod or create_mod together with this patch. An empty string when the backend does not sign results."`
}

type publishModInput struct {
	ModID       string   `json:"mod_id" jsonschema:"id of the draft to publish; use the newest id returned by update_mod"`
	Title       string   `json:"title" jsonschema:"title of the game, shown in listings"`
	Summary     string   `json:"summary,omitempty" jsonschema:"short description of the game"`
	Tags        []string `json:"tags,omitempty" jsonschema:"up to 3 tags"`
	Category    string   `json:"category,omitempty" jsonschema:"category label"`
	ForkedFrom  string   `json:"forked_from,omitempty" jsonschema:"id of the game this draft was forked from, as returned by fork_game"`
	AIGenerated bool     `json:"ai_generated,omitempty" jsonschema:"declare that AI was involved in making the game. The backend sets it regardless when the mod carries an AI provenance mark."`
}

func (s *service) addWriteTools(server *mcp.Server) {
	addTool(server, &mcp.Tool{
		Name:        "fork_game",
		Description: "Start editing an existing game: create a draft mod owned by the signed-in user whose DSL starts equal to the game's, and return its mod_id and DSL. Every call creates a new draft and counts as one fork of the game. Needs FORGEPLAY_TOKEN.",
		Annotations: additive("Fork game"),
	}, func(input *jsonschema.Schema) { requireID(input, "game_id") }, s.forkGame)

	addTool(server, &mcp.Tool{
		Name:        "create_mod",
		Description: "Start a new game from scratch: create a draft mod on a runtime's baseline DSL, optionally with a first patch, and return its mod_id and effective DSL. The patch is applied and validated against the runtime schema first; if the result is invalid nothing is stored and the violations are returned. Needs FORGEPLAY_TOKEN.",
		Annotations: additive("Create mod"),
	}, func(input *jsonschema.Schema) { patchInput(input, 0) }, s.createMod)

	addTool(server, &mcp.Tool{
		Name:        "update_mod",
		Description: "Save a patch on top of one of your drafts. The patch is applied to the draft's current DSL and validated against the runtime schema first; if it does not apply or the result is invalid nothing is stored and the reason is returned. Drafts are immutable versions: the result carries a new mod_id that supersedes the one passed in, so use it for every later call. Needs FORGEPLAY_TOKEN.",
		Annotations: additive("Update mod"),
	}, func(input *jsonschema.Schema) {
		requireID(input, "mod_id")
		patchInput(input, 1)
	}, s.updateMod)

	addTool(server, &mcp.Tool{
		Name:        "generate_mod",
		Description: "Ask the backend AI to turn a natural-language instruction into an RFC 6902 patch for a DSL document. The backend applies and validates the patch and returns it with the resulting DSL. Nothing is stored: save the patch with update_mod (or create_mod), passing the provenance value. Each call consumes one unit of the backend's daily AI generation quota, per account when signed in and per IP address otherwise. A document passed as dsl must already be valid for its runtime: it is checked against the schema first, and an invalid one is refused with its violations before any quota is spent, so fix it with apply_dsl_patch rather than asking the AI to repair it.",
		Annotations: additive("Generate mod with AI"),
	}, func(input *jsonschema.Schema) {
		input.Properties["instruction"].MinLength = jsonschema.Ptr(1)
	}, s.generateMod)

	addTool(server, &mcp.Tool{
		Name:        "publish_mod",
		Description: "Submit a draft as a game. The draft stops being a draft and the game enters moderation with status reviewing; it becomes public once a moderator approves it. This cannot be undone from this server, so call it only when the user asked to publish. Needs FORGEPLAY_TOKEN.",
		// Publishing is not additive: it permanently clears the draft state of the mod and submits content under the user's name, so the destructive hint is set and clients ask for confirmation.
		Annotations: &mcp.ToolAnnotations{Title: "Publish mod", ReadOnlyHint: false, IdempotentHint: false, DestructiveHint: boolPtr(true), OpenWorldHint: boolPtr(true)},
	}, func(input *jsonschema.Schema) {
		requireID(input, "mod_id")
		input.Properties["title"].MinLength = jsonschema.Ptr(1)
		input.Properties["tags"].MaxItems = jsonschema.Ptr(maxTags)
	}, s.publishMod)
}

func (s *service) forkGame(ctx context.Context, _ *mcp.CallToolRequest, in gameInput) (*mcp.CallToolResult, forkGameOutput, error) {
	if err := s.requireToken(); err != nil {
		return nil, forkGameOutput{}, err
	}
	// The fork starts with an empty patch, so its effective DSL is the game's. Reading the DSL first means a failure here leaves no stray draft behind.
	document, err := s.gameDSL(ctx, in.GameID)
	if err != nil {
		return nil, forkGameOutput{}, err
	}
	mod, err := s.backend.ForkGame(ctx, in.GameID)
	if err != nil {
		return nil, forkGameOutput{}, s.backendError(fmt.Sprintf("fork game %q", in.GameID), err)
	}
	return nil, forkGameOutput{ModInfo: modInfo(mod), ForkedFrom: in.GameID, DSL: document}, nil
}

func (s *service) createMod(ctx context.Context, _ *mcp.CallToolRequest, in createModInput) (*mcp.CallToolResult, draftOutput, error) {
	if err := s.requireToken(); err != nil {
		return nil, draftOutput{}, err
	}
	name, version, ok := sdk.SplitRuntimeRef(in.Runtime)
	if !ok {
		return nil, draftOutput{}, fmt.Errorf("runtime %q is not a runtime ref: use <name>@<version>, for example shooter@1.0.0 (list_runtimes shows the available ones)", in.Runtime)
	}
	baseline, err := s.backend.GetRuntimeBaseline(ctx, name, version)
	if sdk.IsNotFound(err) {
		// The generic 404 hint talks about game and mod ids, which is not the mistake here. The backend decides which baselines exist; the catalog lists what this server knows.
		return nil, draftOutput{}, fmt.Errorf("the backend has no runtime %q, so there is no baseline to start from. list_runtimes shows the runtimes this server has schemas for (%s)", in.Runtime, strings.Join(s.catalog.Refs(), ", "))
	}
	if err != nil {
		return nil, draftOutput{}, s.backendError(fmt.Sprintf("read the baseline DSL of runtime %q", in.Runtime), err)
	}
	document, err := s.patchAndCheck(in.Runtime, baseline, in.Patch)
	if err != nil {
		return nil, draftOutput{}, err
	}
	mod, err := s.backend.CreateMod(ctx, sdk.CreateModRequest{Runtime: in.Runtime, Patch: toSDKPatch(in.Patch), AIProvenance: in.AIProvenance, Draft: true})
	if err != nil {
		return nil, draftOutput{}, s.backendError(fmt.Sprintf("create a draft mod on runtime %q", in.Runtime), err)
	}
	return nil, draftOutput{ModInfo: modInfo(mod), DSL: document}, nil
}

func (s *service) updateMod(ctx context.Context, _ *mcp.CallToolRequest, in updateModInput) (*mcp.CallToolResult, draftOutput, error) {
	if err := s.requireToken(); err != nil {
		return nil, draftOutput{}, err
	}
	parent, err := s.backend.GetMod(ctx, in.ModID)
	if err != nil {
		return nil, draftOutput{}, s.backendError(fmt.Sprintf("read mod %q", in.ModID), err)
	}
	if !parent.Draft {
		return nil, draftOutput{}, fmt.Errorf("mod %q is not a draft, so it cannot be updated: it was published or never was a draft. To keep editing a published game, call fork_game with its game_id and update the draft it returns", in.ModID)
	}
	current, err := s.backend.GetModDSL(ctx, in.ModID)
	if err != nil {
		return nil, draftOutput{}, s.backendError(fmt.Sprintf("read the DSL of mod %q", in.ModID), err)
	}
	document, err := s.patchAndCheck(parent.Runtime, current, in.Patch)
	if err != nil {
		return nil, draftOutput{}, err
	}
	// A draft version is a child mod of the previous one. POST /mods is used rather than PUT /drafts/{id} because only it accepts the AI provenance value.
	mod, err := s.backend.CreateMod(ctx, sdk.CreateModRequest{ParentID: in.ModID, Patch: toSDKPatch(in.Patch), AIProvenance: in.AIProvenance, Draft: true})
	if err != nil {
		return nil, draftOutput{}, s.backendError(fmt.Sprintf("save a new version of mod %q", in.ModID), err)
	}
	return nil, draftOutput{ModInfo: modInfo(mod), DSL: document}, nil
}

// patchAndCheck applies patch to base and validates the result against the runtime schema. It returns the patched document, or an error that explains why nothing should be saved.
func (s *service) patchAndCheck(runtime string, base map[string]any, patch []PatchOp) (map[string]any, error) {
	document, err := applyPatch(base, patch)
	if err != nil {
		return nil, fmt.Errorf("nothing was saved: %w", err)
	}
	checked, err := s.check(runtime, document)
	if err != nil {
		return nil, fmt.Errorf("nothing was saved: %w", err)
	}
	if !checked.Valid {
		return nil, fmt.Errorf("nothing was saved: the patched DSL breaks the %s schema in %d place(s). Fix the patch and call again (get_dsl_schema lists the allowed values):%s", checked.runtime, checked.ViolationCount, checked.describe())
	}
	return document, nil
}

func (s *service) generateMod(ctx context.Context, _ *mcp.CallToolRequest, in generateModInput) (*mcp.CallToolResult, generateModOutput, error) {
	if strings.TrimSpace(in.Instruction) == "" {
		return nil, generateModOutput{}, fmt.Errorf("instruction is empty: describe the change to make, for example \"make the player a cat\"")
	}
	sources := 0
	for _, given := range []bool{in.ModID != "", in.GameID != "", len(in.DSL) > 0} {
		if given {
			sources++
		}
	}
	if sources != 1 {
		return nil, generateModOutput{}, fmt.Errorf("pass exactly one source document: mod_id (a mod's DSL), game_id (a game's DSL) or dsl (a document you provide); got %d", sources)
	}
	document := in.DSL
	var err error
	switch {
	case in.ModID != "":
		if document, err = s.backend.GetModDSL(ctx, in.ModID); err != nil {
			return nil, generateModOutput{}, s.backendError(fmt.Sprintf("read the DSL of mod %q", in.ModID), err)
		}
	case in.GameID != "":
		if document, err = s.gameDSL(ctx, in.GameID); err != nil {
			return nil, generateModOutput{}, err
		}
	}
	runtime, err := runtimeOf(in.Runtime, document)
	if err != nil {
		return nil, generateModOutput{}, err
	}
	if len(in.DSL) > 0 {
		// The backend bills a generation as soon as the model was called and only validates the result, so a source document that can never validate, or that does not belong to the runtime, would cost a quota unit for a certain 422. A mod or game DSL comes from the backend, which has validated it already.
		checked, err := s.check(runtime, document)
		if err != nil {
			return nil, generateModOutput{}, fmt.Errorf("no AI quota was spent: %w", err)
		}
		if !checked.Valid {
			return nil, generateModOutput{}, fmt.Errorf("no AI quota was spent: the dsl document breaks the %s schema in %d place(s), and the backend AI only works on a valid document. Fix it first (apply_dsl_patch checks a patch against it, get_dsl_schema lists the allowed values):%s", checked.runtime, checked.ViolationCount, checked.describe())
		}
	}
	generated, err := s.backend.GenerateMod(ctx, sdk.GenerateModRequest{Runtime: runtime, CurrentDSL: document, Prompt: in.Instruction})
	if err != nil {
		return nil, generateModOutput{}, s.backendError("generate a patch with the backend AI", err)
	}
	return nil, generateModOutput{
		Runtime:     runtime,
		Patch:       fromSDKPatch(generated.DSLPatch),
		DSL:         nonNilMap(generated.NewDSL),
		BalanceHint: generated.BalanceHint,
		Model:       generated.Model,
		Retries:     generated.Retries,
		Provenance:  generated.Provenance,
	}, nil
}

func (s *service) publishMod(ctx context.Context, _ *mcp.CallToolRequest, in publishModInput) (*mcp.CallToolResult, GameDetail, error) {
	if err := s.requireToken(); err != nil {
		return nil, GameDetail{}, err
	}
	title := strings.TrimSpace(in.Title)
	if title == "" {
		return nil, GameDetail{}, fmt.Errorf("title is empty: a published game needs a title")
	}
	game, err := s.backend.PublishDraft(ctx, in.ModID, sdk.PublishDraftRequest{
		Title:       title,
		Summary:     in.Summary,
		Tags:        in.Tags,
		Category:    in.Category,
		ForkedFrom:  in.ForkedFrom,
		AIGenerated: in.AIGenerated,
	})
	if err != nil {
		return nil, GameDetail{}, s.backendError(fmt.Sprintf("publish mod %q", in.ModID), err)
	}
	return nil, gameDetail(game), nil
}
