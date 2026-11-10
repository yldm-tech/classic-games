package server

import (
	"context"
	"fmt"

	"github.com/yldm-tech/classic-games/apps/mcp/internal/schemas"
	"github.com/yldm-tech/classic-games/packages/sdk"

	"github.com/google/jsonschema-go/jsonschema"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// The read tools query the Classic Games backend and change nothing there.

const (
	defaultGamesLimit  = 10
	maxGamesLimit      = 50
	defaultDraftsLimit = 20
	maxDraftsLimit     = 100
)

type listGamesInput struct {
	Query       string `json:"query,omitempty" jsonschema:"case-insensitive text search over title, summary, author name and tags"`
	Sort        string `json:"sort,omitempty" jsonschema:"order of the results: new (most recent first), hot (most liked) or rising (most liked in the last 24 hours)"`
	Runtime     string `json:"runtime,omitempty" jsonschema:"keep games of one runtime: a name such as shooter, or a ref such as shooter@1.0.0"`
	Category    string `json:"category,omitempty" jsonschema:"keep games of one category, compared case-insensitively"`
	AIGenerated *bool  `json:"ai_generated,omitempty" jsonschema:"true keeps only AI-generated games, false only the others; omit for both"`
	Limit       int    `json:"limit,omitempty" jsonschema:"maximum number of games to return"`
	Cursor      string `json:"cursor,omitempty" jsonschema:"next_cursor of the previous page; omit for the first page"`
}

type listGamesOutput struct {
	Games      []GameSummary `json:"games" jsonschema:"one page of published games"`
	NextCursor string        `json:"next_cursor" jsonschema:"pass as cursor to get the next page; an empty string on the last page"`
	HasMore    bool          `json:"has_more" jsonschema:"true when another page follows"`
}

type gameInput struct {
	GameID string `json:"game_id" jsonschema:"id of the game, as returned by list_games"`
}

type gameDSLOutput struct {
	GameID  string         `json:"game_id" jsonschema:"id of the game"`
	Runtime string         `json:"runtime" jsonschema:"runtime ref of the DSL, for example shooter@1.0.0"`
	DSL     map[string]any `json:"dsl" jsonschema:"the game's effective DSL: the runtime baseline with the whole patch chain applied"`
}

type modInput struct {
	ModID string `json:"mod_id" jsonschema:"id of the mod, as returned by fork_game, create_mod, update_mod or list_my_drafts"`
}

type modDSLOutput struct {
	ModID   string         `json:"mod_id" jsonschema:"id of the mod"`
	Runtime string         `json:"runtime" jsonschema:"runtime ref of the DSL, for example shooter@1.0.0"`
	DSL     map[string]any `json:"dsl" jsonschema:"the mod's effective DSL: the runtime baseline with every patch from the root mod down to this one applied"`
}

type listMyDraftsInput struct {
	Limit int `json:"limit,omitempty" jsonschema:"maximum number of drafts to return, newest first"`
}

type listMyDraftsOutput struct {
	Drafts []ModInfo `json:"drafts" jsonschema:"the signed-in user's drafts, newest first"`
	Total  int       `json:"total" jsonschema:"number of drafts the user has, which can exceed the number listed"`
}

func (s *service) addReadTools(server *mcp.Server) {
	addTool(server, &mcp.Tool{
		Name:        "list_games",
		Description: "Search and list published games, newest first by default. Returns a compact page; follow next_cursor for more. No authentication needed.",
		Annotations: readOnly("List games", true),
	}, func(input *jsonschema.Schema) {
		enum(input, "sort", sdk.SortNew, sdk.SortHot, sdk.SortRising)
		intRange(input, "limit", 1, maxGamesLimit, defaultGamesLimit)
	}, s.listGames)

	addTool(server, &mcp.Tool{
		Name:        "get_game",
		Description: "Return the details of one game: title, author, runtime, moderation status, counters, the mod it plays and the game it was forked from. A game that is not published is visible to its author only.",
		Annotations: readOnly("Get game", true),
	}, func(input *jsonschema.Schema) { requireID(input, "game_id") }, s.getGame)

	addTool(server, &mcp.Tool{
		Name:        "get_game_dsl",
		Description: "Return the effective DSL of a game, the JSON document its runtime interprets. Use it to study a game or as the base document for apply_dsl_patch. To change the game, fork it with fork_game first.",
		Annotations: readOnly("Get game DSL", true),
	}, func(input *jsonschema.Schema) { requireID(input, "game_id") }, s.getGameDSL)

	addTool(server, &mcp.Tool{
		Name:        "get_mod_dsl",
		Description: "Return the effective DSL of a mod. Use it to reload the current state of one of your drafts before writing the next patch. A draft is readable by its author only, so it needs CLASSIC_GAMES_TOKEN.",
		Annotations: readOnly("Get mod DSL", true),
	}, func(input *jsonschema.Schema) { requireID(input, "mod_id") }, s.getModDSL)

	addTool(server, &mcp.Tool{
		Name:        "list_my_drafts",
		Description: "List the unpublished draft mods of the signed-in user, newest first, to resume earlier work. Because every update_mod creates a new draft version, older versions of the same work are listed too; parent_mod_id links them. Needs CLASSIC_GAMES_TOKEN.",
		Annotations: readOnly("List my drafts", true),
	}, func(input *jsonschema.Schema) {
		intRange(input, "limit", 1, maxDraftsLimit, defaultDraftsLimit)
	}, s.listMyDrafts)
}

func (s *service) listGames(ctx context.Context, _ *mcp.CallToolRequest, in listGamesInput) (*mcp.CallToolResult, listGamesOutput, error) {
	limit := in.Limit
	if limit <= 0 {
		limit = defaultGamesLimit
	}
	page, err := s.backend.ListGames(ctx, sdk.ListGamesParams{
		Query:      in.Query,
		Sort:       in.Sort,
		Runtime:    in.Runtime,
		Category:   in.Category,
		AI:         in.AIGenerated,
		PageParams: sdk.PageParams{Cursor: in.Cursor, Limit: limit},
	})
	if err != nil {
		return nil, listGamesOutput{}, s.backendError("list games", err)
	}
	out := listGamesOutput{Games: make([]GameSummary, len(page.Items)), NextCursor: page.NextCursor, HasMore: page.HasMore()}
	for i := range page.Items {
		out.Games[i] = gameSummary(&page.Items[i])
	}
	return nil, out, nil
}

func (s *service) getGame(ctx context.Context, _ *mcp.CallToolRequest, in gameInput) (*mcp.CallToolResult, GameDetail, error) {
	game, err := s.backend.GetGame(ctx, in.GameID)
	if err != nil {
		return nil, GameDetail{}, s.backendError(fmt.Sprintf("get game %q", in.GameID), err)
	}
	return nil, gameDetail(game), nil
}

func (s *service) getGameDSL(ctx context.Context, _ *mcp.CallToolRequest, in gameInput) (*mcp.CallToolResult, gameDSLOutput, error) {
	document, err := s.gameDSL(ctx, in.GameID)
	if err != nil {
		return nil, gameDSLOutput{}, err
	}
	runtime, _ := schemas.RefOf(document)
	return nil, gameDSLOutput{GameID: in.GameID, Runtime: runtime, DSL: document}, nil
}

// gameDSL reads the effective DSL of a game and returns a tool error on failure. The backend answers 404 both for an unknown game and for a catalogue entry whose mod it does not hold (the showcase games a development backend is seeded with), so on a 404 the game itself is looked up to tell the two apart.
func (s *service) gameDSL(ctx context.Context, gameID string) (map[string]any, error) {
	document, err := s.backend.GetGameDSL(ctx, gameID)
	if err == nil {
		return nonNilMap(document), nil
	}
	if sdk.IsNotFound(err) {
		if game, lookupErr := s.backend.GetGame(ctx, gameID); lookupErr == nil {
			return nil, fmt.Errorf("game %q (%s) is listed but the backend holds no DSL for it: it is a showcase entry without a mod, so it cannot be read, forked or used as a source. Choose another game, or start from a runtime baseline with create_mod", gameID, game.Title)
		}
	}
	return nil, s.backendError(fmt.Sprintf("get the DSL of game %q", gameID), err)
}

func (s *service) getModDSL(ctx context.Context, _ *mcp.CallToolRequest, in modInput) (*mcp.CallToolResult, modDSLOutput, error) {
	document, err := s.backend.GetModDSL(ctx, in.ModID)
	if err != nil {
		return nil, modDSLOutput{}, s.backendError(fmt.Sprintf("get the DSL of mod %q", in.ModID), err)
	}
	runtime, _ := schemas.RefOf(document)
	return nil, modDSLOutput{ModID: in.ModID, Runtime: runtime, DSL: nonNilMap(document)}, nil
}

func (s *service) listMyDrafts(ctx context.Context, _ *mcp.CallToolRequest, in listMyDraftsInput) (*mcp.CallToolResult, listMyDraftsOutput, error) {
	if err := s.requireToken(); err != nil {
		return nil, listMyDraftsOutput{}, err
	}
	drafts, err := s.backend.ListDrafts(ctx)
	if err != nil {
		return nil, listMyDraftsOutput{}, s.backendError("list drafts", err)
	}
	limit := in.Limit
	if limit <= 0 {
		limit = defaultDraftsLimit
	}
	out := listMyDraftsOutput{Total: len(drafts), Drafts: make([]ModInfo, 0, min(limit, len(drafts)))}
	for i := range drafts {
		if len(out.Drafts) == limit {
			break
		}
		out.Drafts = append(out.Drafts, modInfo(&drafts[i]))
	}
	return nil, out, nil
}

// nonNilMap turns a nil document into an empty one so it is encoded as {} rather than null, which the output schemas require.
func nonNilMap(document map[string]any) map[string]any {
	if document == nil {
		return map[string]any{}
	}
	return document
}
