// Package analytics records the minimum product events needed to evaluate ForgePlay's creation flywheel.
package analytics

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"
)

type EventName string

const (
	GameViewed    EventName = "game_viewed"
	ForkStarted   EventName = "fork_started"
	AIEditStarted EventName = "ai_edit_started"
	ModPublished  EventName = "mod_published"
)

var (
	ErrInvalidEvent    = errors.New("analytics: invalid event")
	ErrSessionRequired = errors.New("analytics: session_id required")
)

type Event struct {
	ID        string    `json:"id" gorm:"primaryKey"`
	Name      EventName `json:"name" gorm:"index"`
	SessionID string    `json:"session_id" gorm:"index"`
	UserID    string    `json:"-" gorm:"index"`
	TargetID  string    `json:"target_id,omitempty" gorm:"index"`
	Depth     int       `json:"depth,omitempty"`
	CreatedAt time.Time `json:"created_at" gorm:"index"`
}

// EventRequest is what a client may set. Id and created_at are server-owned: the ingestion endpoint is unauthenticated,
// so letting a caller pick the primary key or the timestamp would let anyone overwrite rows and skew the funnel report.
type EventRequest struct {
	Name      EventName `json:"name"`
	SessionID string    `json:"session_id"`
	TargetID  string    `json:"target_id,omitempty"`
	Depth     int       `json:"depth,omitempty"`
}

type Summary struct {
	GameViewers    int     `json:"game_viewers"`
	ForkStarters   int     `json:"fork_starters"`
	ForkConversion float64 `json:"fork_conversion"`
	AIEditors      int     `json:"ai_editors"`
	AIPublishers   int     `json:"ai_publishers"`
	AIPublishRate  float64 `json:"ai_publish_rate"`
	MaxForkDepth   int     `json:"max_fork_depth"`
}

type Repository interface {
	Add(Event) error
	List() ([]Event, error)
}
type Service struct{ repo Repository }

func NewService(repo Repository) *Service { return &Service{repo: repo} }

func (s *Service) Record(e Event) error {
	if e.SessionID == "" {
		return ErrSessionRequired
	}
	if e.Name != GameViewed && e.Name != ForkStarted && e.Name != AIEditStarted && e.Name != ModPublished {
		return ErrInvalidEvent
	}
	if e.Depth < 0 {
		return ErrInvalidEvent
	}
	if e.ID == "" {
		var b [12]byte
		_, _ = rand.Read(b[:])
		e.ID = "evt_" + hex.EncodeToString(b[:])
	}
	return s.repo.Add(e)
}

func (s *Service) Summary() (Summary, error) {
	events, err := s.repo.List()
	if err != nil {
		return Summary{}, err
	}
	views, forks, edits, pubs := map[string]bool{}, map[string]bool{}, map[string]bool{}, map[string]bool{}
	var out Summary
	for _, e := range events {
		switch e.Name {
		case GameViewed:
			views[e.SessionID] = true
		case ForkStarted:
			forks[e.SessionID] = true
		case AIEditStarted:
			edits[e.SessionID] = true
		case ModPublished:
			pubs[e.SessionID] = true
			if e.Depth > out.MaxForkDepth {
				out.MaxForkDepth = e.Depth
			}
		}
	}
	out.GameViewers, out.ForkStarters = len(views), intersectionCount(forks, views)
	out.AIEditors, out.AIPublishers = len(edits), intersectionCount(pubs, edits)
	if out.GameViewers > 0 {
		out.ForkConversion = float64(out.ForkStarters) / float64(out.GameViewers)
	}
	if out.AIEditors > 0 {
		out.AIPublishRate = float64(out.AIPublishers) / float64(out.AIEditors)
	}
	return out, nil
}

func (s *Service) CountByTarget(name EventName, targetIDs []string) (map[string]int, error) {
	out := make(map[string]int, len(targetIDs))
	wanted := make(map[string]struct{}, len(targetIDs))
	for _, id := range targetIDs {
		out[id] = 0
		wanted[id] = struct{}{}
	}
	events, err := s.repo.List()
	if err != nil {
		return nil, err
	}
	for _, event := range events {
		if event.Name == name {
			if _, ok := wanted[event.TargetID]; ok {
				out[event.TargetID]++
			}
		}
	}
	return out, nil
}

func intersectionCount(a, cohort map[string]bool) int {
	n := 0
	for id := range a {
		if cohort[id] {
			n++
		}
	}
	return n
}
