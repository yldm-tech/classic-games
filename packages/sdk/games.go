package sdk

import (
	"context"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

// GameStatus is the moderation state of a published work: reviewing, then published or rejected; a published game can be delisted by its author.
type GameStatus string

const (
	GameStatusReviewing GameStatus = "reviewing"
	GameStatusPublished GameStatus = "published"
	GameStatusRejected  GameStatus = "rejected"
	GameStatusDelisted  GameStatus = "delisted"
)

// Game is a published work: a mod (and therefore an effective DSL) with title, moderation status and counters.
type Game struct {
	ID string `json:"id"`
	// ModID is the mod whose effective DSL this game plays.
	ModID    string `json:"mod_id"`
	AuthorID string `json:"author_id"`
	// By is the author's display name.
	By string `json:"by"`
	// ForkedFrom is the id of the game this one was forked from, if any.
	ForkedFrom string `json:"forked_from,omitempty"`
	// Title and Summary are localized by the backend to the request language when translations exist.
	Title       string     `json:"title"`
	Summary     string     `json:"summary"`
	Tags        []string   `json:"tags,omitempty"`
	Status      GameStatus `json:"status"`
	AIGenerated bool       `json:"ai_generated"`
	// Runtime is a runtime ref such as "shooter@1.0.0".
	Runtime   string    `json:"runtime"`
	CreatedAt time.Time `json:"created_at"`
	// Tone is the colour theme of the game card.
	Tone     string `json:"tone"`
	Category string `json:"cat"`
	Version  string `json:"ver,omitempty"`
	Plays    int    `json:"plays"`
	Forks    int    `json:"forks"`
	Likes    int    `json:"likes"`
	Views    int    `json:"views"`
}

// Sort orders accepted by ListGames and ranking types accepted by GetRanking.
const (
	SortNew    = "new"
	SortHot    = "hot"
	SortRising = "rising"
)

// ListGamesParams filters and pages GET /api/v1/games. The zero value lists every published game, newest first.
type ListGamesParams struct {
	// Query is a case-insensitive substring search over title, summary, author name and tags.
	Query string
	// Sort is SortNew (default), SortHot (most likes) or SortRising (most likes in the last 24 hours). Any other value fails with 400 BAD_REQUEST.
	Sort string
	// Runtime keeps games of one runtime. Both a bare name ("shooter") and a full ref ("shooter@1.0.0") match.
	Runtime string
	// Category keeps games of one category, compared case-insensitively.
	Category string
	// AI keeps only AI-generated games (true) or only non-AI games (false); nil does not filter.
	AI *bool
	PageParams
}

// ListGames calls GET /api/v1/games and returns one page of published games. No authentication needed; with a token, games the user marked as not interested are left out.
func (c *Client) ListGames(ctx context.Context, params ListGamesParams) (*Page[Game], error) {
	query := url.Values{}
	if params.Query != "" {
		query.Set("q", params.Query)
	}
	if params.Sort != "" {
		query.Set("sort", params.Sort)
	}
	if params.Runtime != "" {
		query.Set("runtime", params.Runtime)
	}
	if params.Category != "" {
		query.Set("category", params.Category)
	}
	if params.AI != nil {
		query.Set("ai", strconv.FormatBool(*params.AI))
	}
	params.PageParams.apply(query)
	var out Page[Game]
	if err := c.do(ctx, http.MethodGet, api("games"), query, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// GetGame calls GET /api/v1/games/{id}. Published games are public. A game that is reviewing, rejected or delisted is visible to its author only; everyone else gets 404 NOT_FOUND. An id that the backend routes elsewhere ("mine") is reported as 404 NOT_FOUND too, never as an empty game.
func (c *Client) GetGame(ctx context.Context, gameID string) (*Game, error) {
	var out Game
	path := api("games", segment(gameID))
	if err := c.do(ctx, http.MethodGet, path, nil, nil, &out); err != nil {
		return nil, err
	}
	if out.ID != gameID {
		return nil, notTheResource(path, "game", gameID)
	}
	return &out, nil
}

// GetGameDSL calls GET /api/v1/games/{id}/dsl and returns the game's effective DSL: the runtime baseline with the whole patch chain of the game's mod applied. Same visibility as GetGame.
func (c *Client) GetGameDSL(ctx context.Context, gameID string) (map[string]any, error) {
	var out map[string]any
	if err := c.do(ctx, http.MethodGet, api("games", segment(gameID), "dsl"), nil, nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// GetGameLineage calls GET /api/v1/games/{id}/lineage and returns the mod chain behind the game, root first. Same visibility as GetGame.
func (c *Client) GetGameLineage(ctx context.Context, gameID string) ([]Mod, error) {
	return listItems[Mod](ctx, c, api("games", segment(gameID), "lineage"), nil)
}

// GetGameForkTree calls GET /api/v1/games/{id}/fork-tree and returns the fork tree around the game's mod. Same visibility as GetGame.
func (c *Client) GetGameForkTree(ctx context.Context, gameID string) (*ForkTree, error) {
	var out ForkTree
	if err := c.do(ctx, http.MethodGet, api("games", segment(gameID), "fork-tree"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// ForkGame calls POST /api/v1/games/{id}/fork. It creates a draft mod owned by the token's user whose effective DSL starts equal to the game's, and increments the game's fork counter. Edit the draft with SaveDraft and release it with PublishDraft. Requires a token.
func (c *Client) ForkGame(ctx context.Context, gameID string) (*Mod, error) {
	var out Mod
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "fork"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// PublishGameRequest is the body of POST /api/v1/games.
type PublishGameRequest struct {
	// ModID is the mod to publish. It must belong to the token's user and its effective DSL must pass schema validation.
	ModID string `json:"mod_id"`
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

// PublishGame calls POST /api/v1/games and submits a mod as a game. The game starts in status "reviewing" and becomes public once a moderator approves it. Requires a token. Any rejected request fails with 400 PUBLISH_INVALID. For a draft mod prefer PublishDraft, which also clears the draft flag so other users can fork the result.
func (c *Client) PublishGame(ctx context.Context, request PublishGameRequest) (*Game, error) {
	var out Game
	if err := c.do(ctx, http.MethodPost, api("games"), nil, request, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// ListMyGames calls GET /api/v1/games/mine and returns every game of the token's user in any status. Requires a token. The listing is not paginated.
func (c *Client) ListMyGames(ctx context.Context) ([]Game, error) {
	return listItems[Game](ctx, c, api("games", "mine"), nil)
}

// DelistGame calls POST /api/v1/games/{id}/delist and takes the author's own published game offline. Requires the author's token; a game that is not published fails with 409 INVALID_STATE.
func (c *Client) DelistGame(ctx context.Context, gameID string) (*Game, error) {
	var out Game
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "delist"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// ResubmitGame calls POST /api/v1/games/{id}/resubmit and sends the author's own rejected game back to review. Requires the author's token; a game that is not rejected fails with 409 INVALID_STATE.
func (c *Client) ResubmitGame(ctx context.Context, gameID string) (*Game, error) {
	var out Game
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "resubmit"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// RankingParams selects a leaderboard for GET /api/v1/ranking.
type RankingParams struct {
	// Type is SortHot (default), SortNew or SortRising. Any other value fails with 400 BAD_REQUEST.
	Type string
	// Limit caps the number of entries; 0 returns every published game. The ranking is not paginated.
	Limit int
	// Runtime keeps games of one runtime; a bare name ("shooter") and a full ref ("shooter@1.0.0") both match.
	Runtime string
	// Category keeps games of one category. Unlike ListGamesParams.Category the comparison is case-sensitive, so pass the value exactly as Game.Category reports it.
	Category string
}

// RankedGame is one leaderboard entry: the game plus its 1-based rank. Likes holds the like count the ranking was computed from.
type RankedGame struct {
	Game
	Rank int `json:"rank"`
}

// Ranking is the response of GET /api/v1/ranking.
type Ranking struct {
	// Type echoes the ranking type that was served.
	Type  string       `json:"type"`
	Items []RankedGame `json:"items"`
}

// GetRanking calls GET /api/v1/ranking. No authentication needed; with a token, games the user marked as not interested are left out.
func (c *Client) GetRanking(ctx context.Context, params RankingParams) (*Ranking, error) {
	query := url.Values{}
	if params.Type != "" {
		query.Set("type", params.Type)
	}
	if params.Limit > 0 {
		query.Set("limit", strconv.Itoa(params.Limit))
	}
	if params.Runtime != "" {
		query.Set("runtime", params.Runtime)
	}
	if params.Category != "" {
		query.Set("category", params.Category)
	}
	var out Ranking
	if err := c.do(ctx, http.MethodGet, api("ranking"), c.langQuery(query), nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
