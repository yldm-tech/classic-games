package feedback

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"forgeplay/server/internal/social"
	"strings"
	"time"
	"unicode/utf8"
)

var ErrInvalid = errors.New("feedback: content must be 1-2000 characters")

type Item struct {
	ID        string    `json:"id" gorm:"primaryKey"`
	UserID    string    `json:"-" gorm:"index"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}
type Repository interface{ Create(Item) (Item, error) }
type Service struct {
	repo      Repository
	moderator social.TextModerator
}

func NewService(r Repository) *Service {
	return &Service{repo: r, moderator: social.NewKeywordModerator()}
}
func (s *Service) SetModerator(m social.TextModerator) {
	if m != nil {
		s.moderator = m
	}
}
func (s *Service) Submit(userID, content string) (Item, error) {
	content = strings.TrimSpace(content)
	n := utf8.RuneCountInString(content)
	if userID == "" || n < 1 || n > 2000 {
		return Item{}, ErrInvalid
	}
	if s.moderator != nil {
		if err := s.moderator.Check(content); err != nil {
			return Item{}, err
		}
	}
	var b [12]byte
	if _, err := rand.Read(b[:]); err != nil {
		return Item{}, err
	}
	return s.repo.Create(Item{ID: "fb_" + hex.EncodeToString(b[:]), UserID: userID, Content: content, CreatedAt: time.Now().UTC()})
}
