package sdk

import (
	"context"
	"net/http"
	"net/url"
	"time"
)

// Comment is one comment on a game.
type Comment struct {
	ID        string    `json:"id"`
	GameID    string    `json:"game_id"`
	AuthorID  string    `json:"author_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

// ListComments calls GET /api/v1/games/{id}/comments and returns one page of comments. No authentication needed; with a token, comments by users the caller blocked are left out.
func (c *Client) ListComments(ctx context.Context, gameID string, page PageParams) (*Page[Comment], error) {
	query := url.Values{}
	page.apply(query)
	var out Page[Comment]
	if err := c.do(ctx, http.MethodGet, api("games", segment(gameID), "comments"), query, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// AddComment calls POST /api/v1/games/{id}/comments. Requires a token; the author is the token's user. Empty content or more than 1000 characters fails with 400 COMMENT_INVALID, content rejected by moderation with 422 CONTENT_REJECTED.
func (c *Client) AddComment(ctx context.Context, gameID, content string) (*Comment, error) {
	var out Comment
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "comments"), nil, map[string]string{"content": content}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// LikeStatus is the result of liking or unliking a game.
type LikeStatus struct {
	// Liked is the caller's like state after the operation.
	Liked bool `json:"liked"`
	// Count is the game's like count after the operation. It is nil in the rare case where the write succeeded but the backend could not read the count back.
	Count *int `json:"count,omitempty"`
}

// LikeGame calls POST /api/v1/games/{id}/like. Requires a token. Liking twice is harmless.
func (c *Client) LikeGame(ctx context.Context, gameID string) (*LikeStatus, error) {
	var out LikeStatus
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "like"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// UnlikeGame calls DELETE /api/v1/games/{id}/like. Requires a token.
func (c *Client) UnlikeGame(ctx context.Context, gameID string) (*LikeStatus, error) {
	var out LikeStatus
	if err := c.do(ctx, http.MethodDelete, api("games", segment(gameID), "like"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// FavoriteGame calls POST /api/v1/games/{id}/favorite and adds the game to the caller's favorites. Requires a token.
func (c *Client) FavoriteGame(ctx context.Context, gameID string) error {
	return c.do(ctx, http.MethodPost, api("games", segment(gameID), "favorite"), nil, nil, nil)
}

// UnfavoriteGame calls DELETE /api/v1/games/{id}/favorite. Requires a token.
func (c *Client) UnfavoriteGame(ctx context.Context, gameID string) error {
	return c.do(ctx, http.MethodDelete, api("games", segment(gameID), "favorite"), nil, nil, nil)
}

// ListFavorites calls GET /api/v1/favorites and returns the ids of the caller's favorite games; load details with GetGame. Requires a token.
func (c *Client) ListFavorites(ctx context.Context) ([]string, error) {
	return listItems[string](ctx, c, api("favorites"), nil)
}

// CommunityPost is one post on a game's community board.
type CommunityPost struct {
	ID        string    `json:"id"`
	GameID    string    `json:"game_id"`
	AuthorID  string    `json:"author_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

// GameCommunity is the community panel of a game: rating summary plus posts.
type GameCommunity struct {
	// Average is the mean rating (1 to 5), or 0 when nobody rated yet.
	Average float64 `json:"average"`
	// Count is the number of ratings.
	Count int64 `json:"count"`
	// MyRating is the caller's own rating, or 0 when anonymous or not rated.
	MyRating int             `json:"my_rating"`
	Posts    []CommunityPost `json:"posts"`
}

// GetGameCommunity calls GET /api/v1/games/{id}/community. No authentication needed; with a token MyRating is filled and posts by blocked users are left out.
func (c *Client) GetGameCommunity(ctx context.Context, gameID string) (*GameCommunity, error) {
	var out GameCommunity
	if err := c.do(ctx, http.MethodGet, api("games", segment(gameID), "community"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// RateGame calls POST /api/v1/games/{id}/community/rating and sets the caller's rating (1 to 5), replacing an earlier one. It returns the updated community panel. Requires a token. A value outside 1..5 fails with 400 RATING_INVALID.
func (c *Client) RateGame(ctx context.Context, gameID string, value int) (*GameCommunity, error) {
	var out GameCommunity
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "community", "rating"), nil, map[string]int{"value": value}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// CreateCommunityPost calls POST /api/v1/games/{id}/community/posts. Requires a token. Content must be 1 to 1000 characters, otherwise 400 POST_INVALID; content rejected by moderation fails with 422 CONTENT_REJECTED.
func (c *Client) CreateCommunityPost(ctx context.Context, gameID, content string) (*CommunityPost, error) {
	var out CommunityPost
	if err := c.do(ctx, http.MethodPost, api("games", segment(gameID), "community", "posts"), nil, map[string]string{"content": content}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Profile is a user's public profile. Counters are aggregated from the user's published games on every read.
type Profile struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Bio  string `json:"bio"`
	// Gender is the numeric gender code the client stores; 0 means not set.
	Gender int `json:"gender"`
	// Tone is the profile colour theme.
	Tone   string `json:"tone"`
	Region string `json:"region"`
	// Joined is the year the user joined.
	Joined  int `json:"joined"`
	Works   int `json:"works"`
	Level   int `json:"level"`
	Points  int `json:"points"`
	Plays   int `json:"plays"`
	Forks   int `json:"forks"`
	Follows int `json:"follows"`
	Likes   int `json:"likes"`
}

// GetUserProfile calls GET /api/v1/users/{id}. No authentication. The backend answers 200 for any id: an unknown user comes back as an empty profile whose ID and Name equal the id, never as 404. The id "me" is the exception: the backend serves the signed-in account there, which is not a profile, so it is reported as 404 NOT_FOUND; use CurrentUser for the token's user.
func (c *Client) GetUserProfile(ctx context.Context, userID string) (*Profile, error) {
	var out Profile
	path := api("users", segment(userID))
	if err := c.do(ctx, http.MethodGet, path, nil, nil, &out); err != nil {
		return nil, err
	}
	if out.ID != userID {
		return nil, notTheResource(path, "user", userID)
	}
	return &out, nil
}

// Kinds of games ListUserGames can return.
const (
	UserGamesWorks = "works" // Published games the user created from scratch (default).
	UserGamesForks = "forks" // Published games the user forked from another game.
	UserGamesLiked = "liked" // Published games the user favorited.
)

// ListUserGames calls GET /api/v1/users/{id}/games and returns the user's published games of one kind (UserGamesWorks when kind is empty). No authentication. The listing is not paginated.
func (c *Client) ListUserGames(ctx context.Context, userID, kind string) ([]Game, error) {
	query := url.Values{}
	if kind != "" {
		query.Set("type", kind)
	}
	return listItems[Game](ctx, c, api("users", segment(userID), "games"), c.langQuery(query))
}

// Person is one entry of a follower or following list.
type Person struct {
	// Handle is the user id of the follower or followed user.
	Handle string `json:"handle"`
	// Mutual and Note belong to the backend's shared person shape. The follower and following listings always leave them at their zero values.
	Mutual bool   `json:"mutual"`
	Note   string `json:"note"`
}

// ListFollowers calls GET /api/v1/users/{id}/followers. No authentication.
func (c *Client) ListFollowers(ctx context.Context, userID string) ([]Person, error) {
	return listItems[Person](ctx, c, api("users", segment(userID), "followers"), nil)
}

// ListFollowing calls GET /api/v1/users/{id}/following. No authentication.
func (c *Client) ListFollowing(ctx context.Context, userID string) ([]Person, error) {
	return listItems[Person](ctx, c, api("users", segment(userID), "following"), nil)
}
