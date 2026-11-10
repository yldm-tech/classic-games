package community

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/yldm-tech/classic-games/apps/server/internal/social"
)

var (
	ErrInvalidRating = errors.New("community: rating must be 1-5")
	ErrInvalidPost   = errors.New("community: post must be 1-1000 characters")
)

type Rating struct {
	GameID    string    `json:"game_id" gorm:"primaryKey"`
	UserID    string    `json:"-" gorm:"primaryKey"`
	Value     int       `json:"value"`
	UpdatedAt time.Time `json:"updated_at"`
}
type Post struct {
	ID        string    `json:"id" gorm:"primaryKey"`
	GameID    string    `json:"game_id" gorm:"index"`
	AuthorID  string    `json:"author_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at" gorm:"index"`
}
type Summary struct {
	Average  float64 `json:"average"`
	Count    int64   `json:"count"`
	MyRating int     `json:"my_rating"`
	Posts    []Post  `json:"posts"`
}
type Repository interface {
	UpsertRating(Rating) error
	RatingSummary(string, string) (float64, int64, int, error)
	CreatePost(Post) (Post, error)
	ListPosts(string) ([]Post, error)
}
type Service struct {
	repo      Repository
	moderator social.TextModerator
	blocks    social.BlockLister // 读路径屏蔽过滤(nil = 不过滤,如匿名/未接 moderation)
}

func NewService(r Repository) *Service {
	return &Service{repo: r, moderator: social.NewKeywordModerator()}
}
func (s *Service) SetModerator(m social.TextModerator) {
	if m != nil {
		s.moderator = m
	}
}

// SetBlockLister 注入屏蔽列表来源(moderation 域),开启读路径的帖子屏蔽过滤,
// 与 social 评论保持一致:被屏蔽作者的社区帖不应对屏蔽者可见。
func (s *Service) SetBlockLister(b social.BlockLister) { s.blocks = b }

// dropBlocked 过滤掉作者在 viewer 黑名单里的帖子;取黑名单失败时放行(不因审核侧故障阻断读)。
func (s *Service) dropBlocked(in []Post, viewerID string) []Post {
	if s.blocks == nil || viewerID == "" {
		return in
	}
	blocked, err := s.blocks.ListBlocked(viewerID)
	if err != nil || len(blocked) == 0 {
		return in
	}
	set := make(map[string]struct{}, len(blocked))
	for _, id := range blocked {
		set[id] = struct{}{}
	}
	out := make([]Post, 0, len(in))
	for _, p := range in {
		if _, ok := set[p.AuthorID]; ok {
			continue
		}
		out = append(out, p)
	}
	return out
}
func (s *Service) Rate(gameID, userID string, value int) (Summary, error) {
	if gameID == "" || userID == "" || value < 1 || value > 5 {
		return Summary{}, ErrInvalidRating
	}
	if err := s.repo.UpsertRating(Rating{GameID: gameID, UserID: userID, Value: value, UpdatedAt: time.Now().UTC()}); err != nil {
		return Summary{}, err
	}
	return s.Get(gameID, userID)
}
func (s *Service) Post(gameID, userID, content string) (Post, error) {
	content = strings.TrimSpace(content)
	n := utf8.RuneCountInString(content)
	if gameID == "" || userID == "" || n < 1 || n > 1000 {
		return Post{}, ErrInvalidPost
	}
	if err := s.moderator.Check(content); err != nil {
		return Post{}, err
	}
	var b [12]byte
	if _, err := rand.Read(b[:]); err != nil {
		return Post{}, err
	}
	return s.repo.CreatePost(Post{ID: "post_" + hex.EncodeToString(b[:]), GameID: gameID, AuthorID: userID, Content: content, CreatedAt: time.Now().UTC()})
}
func (s *Service) Get(gameID, userID string) (Summary, error) {
	avg, count, mine, err := s.repo.RatingSummary(gameID, userID)
	if err != nil {
		return Summary{}, err
	}
	posts, err := s.repo.ListPosts(gameID)
	return Summary{Average: avg, Count: count, MyRating: mine, Posts: s.dropBlocked(posts, userID)}, err
}
