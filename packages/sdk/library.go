package sdk

import (
	"context"
	"fmt"
	"net/http"
	"time"
)

// LibraryGame is the game summary embedded in library listings, localized to the request language.
type LibraryGame struct {
	ID       string   `json:"id"`
	AuthorID string   `json:"author_id"`
	Title    string   `json:"title"`
	Summary  string   `json:"summary"`
	Tags     []string `json:"tags,omitempty"`
}

// DownloadItem is one downloaded game.
type DownloadItem struct {
	Game      LibraryGame `json:"game"`
	SizeMB    int         `json:"size_mb"`
	HasUpdate bool        `json:"has_update"`
}

// HistoryItem is one recently played game.
type HistoryItem struct {
	Game          LibraryGame `json:"game"`
	MinutesPlayed int         `json:"minutes_played"`
}

// History groups reported in HistoryGroup.Group.
const (
	HistoryToday     = "today"
	HistoryYesterday = "yesterday"
	HistoryEarlier   = "earlier"
)

// HistoryGroup is the play history of one time bucket.
type HistoryGroup struct {
	// Group is HistoryToday, HistoryYesterday or HistoryEarlier.
	Group string        `json:"group"`
	Items []HistoryItem `json:"items"`
}

// LiveItem is one live stream of a game.
type LiveItem struct {
	Game     LibraryGame `json:"game"`
	Streamer string      `json:"streamer"`
	Viewers  int         `json:"viewers"`
	// Title is the stream's tagline.
	Title string `json:"title"`
}

// ListDownloads calls GET /api/v1/downloads and returns the caller's downloaded games. Authentication is optional: an anonymous caller gets the backend's demo listing, a signed-in caller their own.
func (c *Client) ListDownloads(ctx context.Context) ([]DownloadItem, error) {
	return listItems[DownloadItem](ctx, c, api("downloads"), nil)
}

// ListHistory calls GET /api/v1/history and returns the caller's recently played games grouped by day. Authentication is optional: an anonymous caller gets the backend's demo listing, a signed-in caller their own.
func (c *Client) ListHistory(ctx context.Context) ([]HistoryGroup, error) {
	var out struct {
		Groups []HistoryGroup `json:"groups"`
	}
	if err := c.do(ctx, http.MethodGet, api("history"), nil, nil, &out); err != nil {
		return nil, err
	}
	return out.Groups, nil
}

// ListLive calls GET /api/v1/live and returns the live streams. Authentication is optional: an anonymous caller gets the backend's demo listing, a signed-in caller an empty list.
func (c *Client) ListLive(ctx context.Context) ([]LiveItem, error) {
	return listItems[LiveItem](ctx, c, api("live"), nil)
}

// RecordPlay calls POST /api/v1/games/{id}/played and reports one play session of the given length, which feeds the caller's history and the game's play counter. Requires a token. An unknown game fails with 404 NOT_FOUND, a session blocked by teen-mode limits with 403 TEEN_BLOCKED. The duration is sent in whole milliseconds and must not be negative.
func (c *Client) RecordPlay(ctx context.Context, gameID string, duration time.Duration) error {
	if duration < 0 {
		return fmt.Errorf("sdk: record play: negative duration %s", duration)
	}
	body := map[string]int64{"duration_ms": duration.Milliseconds()}
	return c.do(ctx, http.MethodPost, api("games", segment(gameID), "played"), nil, body, nil)
}

// ReplayFrame is one sample of a play session.
type ReplayFrame struct {
	// AtMS is the time of the sample in milliseconds since the start of the session. Frames must be strictly increasing and not exceed the replay duration.
	AtMS  int     `json:"at_ms"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	HP    int     `json:"hp"`
	Score int     `json:"score"`
}

// Replay is a stored play session.
type Replay struct {
	ID         string        `json:"id"`
	GameID     string        `json:"game_id"`
	UserID     string        `json:"user_id"`
	DurationMS int           `json:"duration_ms"`
	Frames     []ReplayFrame `json:"frames"`
	// Score is the score the backend derived from the frames; it does not trust the scores a client reports.
	Score     int       `json:"score"`
	CreatedAt time.Time `json:"created_at"`
}

// LeaderboardEntry is one row of a game's replay leaderboard.
type LeaderboardEntry struct {
	UserID   string `json:"user_id"`
	Nickname string `json:"nickname"`
	Score    int    `json:"score"`
	Rank     int    `json:"rank"`
}

// GetReplayLeaderboard calls GET /api/v1/games/{id}/replays/leaderboard and returns the top 20 scores of a game. No authentication.
func (c *Client) GetReplayLeaderboard(ctx context.Context, gameID string) ([]LeaderboardEntry, error) {
	return listItems[LeaderboardEntry](ctx, c, api("games", segment(gameID), "replays", "leaderboard"), nil)
}

// GetLatestReplay calls GET /api/v1/games/{id}/replays/{user} and returns a user's most recent replay of a game, frames included. No authentication. Fails with 404 REPLAY_NOT_FOUND when the user has none. The user id "leaderboard" is a route of its own (GetReplayLeaderboard), so it is reported as 404 NOT_FOUND.
func (c *Client) GetLatestReplay(ctx context.Context, gameID, userID string) (*Replay, error) {
	var out Replay
	path := api("games", segment(gameID), "replays", segment(userID))
	if err := c.do(ctx, http.MethodGet, path, nil, nil, &out); err != nil {
		return nil, err
	}
	if out.ID == "" || out.UserID != userID {
		return nil, notTheResource(path, "user", userID)
	}
	return &out, nil
}

// SubmitReplayRequest is the body of POST /api/v1/games/{id}/replays.
type SubmitReplayRequest struct {
	// DurationMS is the session length in milliseconds, 1 to 1,800,000 (30 minutes).
	DurationMS int `json:"duration_ms"`
	// Frames holds 2 to 18,000 samples in strictly increasing AtMS order.
	Frames []ReplayFrame `json:"frames"`
}

// SubmitReplay calls POST /api/v1/games/{id}/replays and stores a play session for the token's user. The backend recomputes the score from the frames. Requires a token. A request outside the documented limits fails with 400 REPLAY_INVALID, a session blocked by teen-mode limits with 403 TEEN_BLOCKED.
func (c *Client) SubmitReplay(ctx context.Context, gameID string, request SubmitReplayRequest) (*Replay, error) {
	var out Replay
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "replays"), nil, request, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
