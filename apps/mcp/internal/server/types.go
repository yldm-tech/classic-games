package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"forgeplay/dsl"
	"forgeplay/mcp/internal/schemas"
	"forgeplay/sdk"
)

// maxViolations caps the violations listed in one result; a broken document can produce hundreds and the first ones are enough to act on.
const maxViolations = 50

// maxViolationMessage caps one violation message, in characters. A message can name every offending key (an object with thousands of unknown properties yields one violation listing them all), so the cap on the number of violations alone does not bound a result.
const maxViolationMessage = 500

// excerpt cuts text to at most limit characters and says how many were left out.
func excerpt(text string, limit int) string {
	if utf8.RuneCountInString(text) <= limit {
		return text
	}
	runes := []rune(text)
	return fmt.Sprintf("%s ... (%d more characters)", string(runes[:limit]), len(runes)-limit)
}

// PatchOp is one RFC 6902 operation as tools accept and return it. Its fields match dsl.Op and sdk.PatchOp, so values convert directly.
type PatchOp struct {
	Op    string          `json:"op" jsonschema:"operation: add, replace, remove or test (move and copy are not supported)"`
	Path  string          `json:"path" jsonschema:"JSON Pointer (RFC 6901) to the target, for example /player/hp or /enemies/dog_1/count. The document root is not a valid target. add creates or overwrites a key; replace and remove need an existing target."`
	Value json.RawMessage `json:"value,omitempty" jsonschema:"any JSON value: the new value for add and replace, the expected value for test. Omit for remove."`
}

// Violation is one schema violation as tools report it.
type Violation struct {
	Path    string `json:"path" jsonschema:"JSON Pointer to the offending value; an empty string is the document root"`
	Message string `json:"message" jsonschema:"what is wrong at that path; cut after 500 characters, with a note of how many were left out"`
}

// Validation is the schema check outcome embedded in tool outputs.
type Validation struct {
	Valid          bool        `json:"valid" jsonschema:"true when the DSL satisfies the runtime schema"`
	ViolationCount int         `json:"violation_count" jsonschema:"total number of violations found"`
	Violations     []Violation `json:"violations" jsonschema:"the violations, sorted by path; at most 50 are listed, violation_count has the total"`
}

// checked is the outcome of validating one document: the result, the ref of the schema that was used and, when the document was a legacy one that got migrated first, the ref that was asked for.
type checked struct {
	Validation
	runtime      string
	migratedFrom string
}

// ModInfo describes one mod in tool outputs.
type ModInfo struct {
	ModID        string `json:"mod_id" jsonschema:"id of the mod; pass it to get_mod_dsl, update_mod, generate_mod and publish_mod"`
	ParentModID  string `json:"parent_mod_id" jsonschema:"id of the mod this one patches, or an empty string for a root mod on the runtime baseline"`
	Runtime      string `json:"runtime" jsonschema:"runtime ref, for example shooter@1.0.0"`
	Draft        bool   `json:"draft" jsonschema:"true while the mod is unpublished; drafts are visible to their author only"`
	AIGenerated  bool   `json:"ai_generated" jsonschema:"true when the mod or one of its ancestors was saved with a valid AI provenance value"`
	PatchOpCount int    `json:"patch_op_count" jsonschema:"number of patch operations this mod adds on top of its parent"`
	CreatedAt    string `json:"created_at" jsonschema:"creation time, RFC 3339"`
}

// GameSummary is the compact game shape used in listings.
type GameSummary struct {
	GameID      string   `json:"game_id" jsonschema:"id of the game; pass it to get_game, get_game_dsl and fork_game"`
	Title       string   `json:"title" jsonschema:"game title"`
	Summary     string   `json:"summary" jsonschema:"short description written by the author"`
	Author      string   `json:"author" jsonschema:"display name of the author"`
	Runtime     string   `json:"runtime" jsonschema:"runtime ref, for example shooter@1.0.0; an empty string for a showcase entry that has no DSL"`
	Category    string   `json:"category" jsonschema:"category label"`
	Tags        []string `json:"tags" jsonschema:"up to 3 tags"`
	AIGenerated bool     `json:"ai_generated" jsonschema:"true when the game is labelled as AI-generated"`
	Likes       int      `json:"likes" jsonschema:"like count"`
	Plays       int      `json:"plays" jsonschema:"play count"`
	Forks       int      `json:"forks" jsonschema:"number of times the game was forked"`
}

// GameDetail is the full game shape returned by get_game and publish_mod.
type GameDetail struct {
	GameSummary
	Status     string `json:"status" jsonschema:"moderation state: reviewing, published, rejected or delisted"`
	ModID      string `json:"mod_id" jsonschema:"id of the mod whose effective DSL the game plays"`
	AuthorID   string `json:"author_id" jsonschema:"user id of the author"`
	ForkedFrom string `json:"forked_from" jsonschema:"id of the game this one was forked from, or an empty string"`
	Views      int    `json:"views" jsonschema:"view count"`
	CreatedAt  string `json:"created_at" jsonschema:"publication time, RFC 3339"`
}

func modInfo(mod *sdk.Mod) ModInfo {
	return ModInfo{
		ModID:        mod.ID,
		ParentModID:  mod.ParentID,
		Runtime:      mod.Runtime,
		Draft:        mod.Draft,
		AIGenerated:  mod.AIGenerated,
		PatchOpCount: len(mod.Patch),
		CreatedAt:    mod.CreatedAt.UTC().Format(time.RFC3339),
	}
}

func gameSummary(game *sdk.Game) GameSummary {
	return GameSummary{
		GameID:      game.ID,
		Title:       game.Title,
		Summary:     game.Summary,
		Author:      game.By,
		Runtime:     game.Runtime,
		Category:    game.Category,
		Tags:        nonNil(game.Tags),
		AIGenerated: game.AIGenerated,
		Likes:       game.Likes,
		Plays:       game.Plays,
		Forks:       game.Forks,
	}
}

func gameDetail(game *sdk.Game) GameDetail {
	return GameDetail{
		GameSummary: gameSummary(game),
		Status:      string(game.Status),
		ModID:       game.ModID,
		AuthorID:    game.AuthorID,
		ForkedFrom:  game.ForkedFrom,
		Views:       game.Views,
		CreatedAt:   game.CreatedAt.UTC().Format(time.RFC3339),
	}
}

// nonNil turns a nil slice into an empty one so it is encoded as [] rather than null, which the output schemas require.
func nonNil[T any](items []T) []T {
	if items == nil {
		return []T{}
	}
	return items
}

// validation converts catalog violations into the output shape, listing at most maxViolations.
func validation(found []schemas.Violation) Validation {
	listed := found
	if len(listed) > maxViolations {
		listed = listed[:maxViolations]
	}
	violations := make([]Violation, len(listed))
	for i, violation := range listed {
		violations[i] = Violation{Path: violation.Path, Message: excerpt(violation.Message, maxViolationMessage)}
	}
	return Validation{Valid: len(found) == 0, ViolationCount: len(found), Violations: violations}
}

// describe renders violations as the text of a tool error, one per line.
func (v Validation) describe() string {
	var builder strings.Builder
	for _, violation := range v.Violations {
		path := violation.Path
		if path == "" {
			path = "(document root)"
		}
		fmt.Fprintf(&builder, "\n- %s: %s", path, violation.Message)
	}
	if hidden := v.ViolationCount - len(v.Violations); hidden > 0 {
		fmt.Fprintf(&builder, "\n- and %d more", hidden)
	}
	return builder.String()
}

func toSDKPatch(patch []PatchOp) []sdk.PatchOp {
	out := make([]sdk.PatchOp, len(patch))
	for i, op := range patch {
		out[i] = sdk.PatchOp(op)
	}
	return out
}

func fromSDKPatch(patch []sdk.PatchOp) []PatchOp {
	out := make([]PatchOp, len(patch))
	for i, op := range patch {
		out[i] = PatchOp(op)
	}
	return out
}

// applyPatch applies patch to document and returns the patched copy; document is not modified. The error names the first operation that is malformed or does not apply. The document is copied once for the whole patch (dsl.Apply copies its input), so the cost grows with the patch plus the document, not with their product.
func applyPatch(document map[string]any, patch []PatchOp) (map[string]any, error) {
	// Operations are judged in order, as if applied one at a time: the ones before the first malformed operation are applied, and a failure among them is reported before the malformed one.
	var malformed error
	ops := make([]dsl.Op, 0, len(patch))
	for i, op := range patch {
		if malformed = checkOp(i, op); malformed != nil {
			break
		}
		ops = append(ops, dsl.Op(op))
	}
	patched, err := dsl.Apply(document, ops)
	if err != nil {
		var opErr *dsl.OpError
		if !errors.As(err, &opErr) {
			return nil, fmt.Errorf("the document could not be copied: %w", err)
		}
		op := patch[opErr.Index]
		return nil, fmt.Errorf("%s does not apply: %s. Each operation runs on the document as left by the previous ones: replace, remove and test need an existing target, add needs an existing parent, and an array index must be in range", position(opErr.Index, op), applyFailure(op, opErr.Err))
	}
	if malformed != nil {
		return nil, malformed
	}
	return patched, nil
}

// position names an operation in an error: its 1-based place in the patch, its op and its path.
func position(index int, op PatchOp) string {
	return fmt.Sprintf("patch operation %d (%s %q)", index+1, op.Op, op.Path)
}

// checkOp reports what is wrong with an operation regardless of the document it is applied to, or nil.
func checkOp(index int, op PatchOp) error {
	switch op.Op {
	case "add", "replace", "test":
		if len(op.Value) == 0 {
			return fmt.Errorf("%s has no value: %s needs a \"value\" field (JSON null is allowed)", position(index, op), op.Op)
		}
	case "remove":
	case "move":
		return fmt.Errorf("%s is not supported: express move as a remove and an add", position(index, op))
	case "copy":
		return fmt.Errorf("%s is not supported: express copy as an add with the value to copy", position(index, op))
	default:
		return fmt.Errorf("%s has an unknown op: use add, replace, remove or test", position(index, op))
	}
	if !strings.HasPrefix(op.Path, "/") {
		return fmt.Errorf("%s has an invalid path: a path is a JSON Pointer starting with \"/\", such as /player/hp, and the document root cannot be patched", position(index, op))
	}
	return nil
}

// applyFailure says in English why forgeplay/dsl could not apply op. The messages of forgeplay/dsl are Chinese, shared with the backend and the game client, and name only the tail of the pointer, so the reason is rebuilt here from the error class and the full path. An error without a known class is passed on as it is.
func applyFailure(op PatchOp, err error) string {
	switch {
	case errors.Is(err, dsl.ErrTestFailed):
		return fmt.Sprintf("the value at %s is not the expected one", op.Path)
	case errors.Is(err, dsl.ErrTargetMissing):
		return fmt.Sprintf("%s does not exist", op.Path)
	case errors.Is(err, dsl.ErrParentMissing):
		return fmt.Sprintf("the parent of %s does not exist or is not an object or an array", op.Path)
	case errors.Is(err, dsl.ErrIndexOutOfRange):
		return fmt.Sprintf("the array index at the end of %s is not a number or is out of range", op.Path)
	default:
		return err.Error()
	}
}

// runtimeOf picks the runtime ref for a document: the explicit one when given, otherwise the one in the document's meta section.
func runtimeOf(explicit string, document map[string]any) (string, error) {
	if explicit != "" {
		if _, _, ok := sdk.SplitRuntimeRef(explicit); !ok {
			return "", fmt.Errorf("runtime %q is not a runtime ref: use <name>@<version>, for example shooter@1.0.0 (list_runtimes shows the available ones)", explicit)
		}
		return explicit, nil
	}
	ref, ok := schemas.RefOf(document)
	if !ok {
		return "", fmt.Errorf("cannot tell which runtime the DSL belongs to: it has no meta.runtime and meta.runtime_version, so pass the runtime argument, for example shooter@1.0.0")
	}
	return ref, nil
}
