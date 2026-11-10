package replays

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"
)

var ErrInvalid = errors.New("replays: invalid timeline")
var ErrPlayBlocked = errors.New("replays: teen play blocked")

type Frame struct {
	AtMS  int     `json:"at_ms"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	HP    int     `json:"hp"`
	Score int     `json:"score"`
}
type Replay struct {
	ID         string    `json:"id" gorm:"primaryKey"`
	GameID     string    `json:"game_id" gorm:"index"`
	UserID     string    `json:"user_id" gorm:"index"`
	DurationMS int       `json:"duration_ms"`
	Frames     []Frame   `json:"frames" gorm:"serializer:json"`
	Score      int       `json:"score" gorm:"index"`
	CreatedAt  time.Time `json:"created_at" gorm:"index"`
}
type Repository interface {
	Create(Replay) (Replay, error)
	Latest(string, string) (Replay, error)
	Leaderboard(string, int) ([]LeaderboardRow, error)
}
type LeaderboardRow struct {
	UserID string `json:"user_id"`
	Score  int    `json:"score"`
}
type LeaderboardEntry struct {
	UserID   string `json:"user_id"`
	Nickname string `json:"nickname"`
	Score    int    `json:"score"`
	Rank     int    `json:"rank"`
}
type Service struct {
	repo          Repository
	userName      func(string) string
	onScore       func(string, int) error
	scoreResolver func(game, user string, frames []Frame) (int, bool)
	playGuard     func(string, int) error
}

func NewService(r Repository) *Service                                          { return &Service{repo: r} }
func (s *Service) SetUserLookup(f func(string) string)                          { s.userName = f }
func (s *Service) SetScoreRecorder(f func(string, int) error)                   { s.onScore = f }
func (s *Service) SetScoreResolver(f func(string, string, []Frame) (int, bool)) { s.scoreResolver = f }
func (s *Service) SetPlayGuard(f func(string, int) error)                       { s.playGuard = f }
func (s *Service) Create(game, user string, duration int, frames []Frame) (Replay, error) {
	if s.playGuard != nil {
		if err := s.playGuard(user, 0); err != nil {
			return Replay{}, ErrPlayBlocked
		}
	}
	if game == "" || user == "" || duration < 1 || duration > 30*60*1000 || len(frames) < 2 || len(frames) > 18000 {
		return Replay{}, ErrInvalid
	}
	last := -1
	for _, f := range frames {
		if f.AtMS < 0 || f.AtMS > duration || f.AtMS <= last || f.HP < 0 || f.Score < 0 {
			return Replay{}, ErrInvalid
		}
		last = f.AtMS
	}
	storedFrames := append([]Frame(nil), frames...)
	trustedScore, trusted := 0, false
	if s.scoreResolver != nil {
		trustedScore, trusted = s.scoreResolver(game, user, frames)
		if trustedScore < 0 {
			trusted = false
			trustedScore = 0
		}
	}
	if !trusted {
		trustedScore = 0
		for i := range storedFrames {
			storedFrames[i].Score = 0
		}
	} else {
		storedFrames[len(storedFrames)-1].Score = trustedScore
	}
	var b [12]byte
	_, _ = rand.Read(b[:])
	replay, err := s.repo.Create(Replay{ID: "replay_" + hex.EncodeToString(b[:]), GameID: game, UserID: user, DurationMS: duration, Frames: storedFrames, Score: trustedScore, CreatedAt: time.Now().UTC()})
	if err == nil && trusted && trustedScore > 0 && s.onScore != nil {
		_ = s.onScore(user, replay.Score)
	}
	return replay, err
}
func (s *Service) Latest(game, user string) (Replay, error) { return s.repo.Latest(game, user) }
func (s *Service) Leaderboard(game string, limit int) ([]LeaderboardEntry, error) {
	if limit < 1 || limit > 100 {
		limit = 20
	}
	rows, e := s.repo.Leaderboard(game, limit)
	if e != nil {
		return nil, e
	}
	out := make([]LeaderboardEntry, len(rows))
	for i, v := range rows {
		name := v.UserID
		if s.userName != nil {
			if n := s.userName(v.UserID); n != "" {
				name = n
			}
		}
		out[i] = LeaderboardEntry{UserID: v.UserID, Nickname: name, Score: v.Score, Rank: i + 1}
	}
	return out, nil
}
