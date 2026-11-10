package rooms

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"math"
	"sort"
	"strings"
	"time"
)

var (
	ErrNotFound      = errors.New("rooms: not found")
	ErrForbidden     = errors.New("rooms: host required")
	ErrNotReady      = errors.New("rooms: all members must be ready")
	ErrFull          = errors.New("rooms: room is full")
	ErrNotStarted    = errors.New("rooms: match has not started")
	ErrInvalidInput  = errors.New("rooms: invalid player input")
	ErrStaleInput    = errors.New("rooms: stale player input")
	ErrMatchFinished = errors.New("rooms: match has finished")
	ErrStarted       = errors.New("rooms: room already started")
	ErrPlayBlocked   = errors.New("rooms: teen play blocked")
)

const (
	MatchStarted  = "started"
	MatchFinished = "finished"
	moveStep      = 8.0
	spawnSpacing  = 128.0
	maxPosition   = 1000.0
	fireRange     = 160.0
	hitDamage     = 10
)

type Room struct {
	ID          string    `json:"id" gorm:"primaryKey"`
	Code        string    `json:"code" gorm:"uniqueIndex"`
	HostID      string    `json:"host_id"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
	Members     []Member  `json:"members" gorm:"foreignKey:RoomID"`
	MemberCount int       `json:"-" gorm:"not null;default:0"`
}
type Member struct {
	RoomID   string    `json:"-" gorm:"primaryKey"`
	UserID   string    `json:"user_id" gorm:"primaryKey"`
	Ready    bool      `json:"ready"`
	JoinedAt time.Time `json:"joined_at"`
}

// PlayerInput is the complete client command for one authoritative match tick.
// Seq is scoped to one player and prevents retries from applying twice.
type PlayerInput struct {
	Seq   int64   `json:"seq"`
	MoveX float64 `json:"move_x"`
	MoveY float64 `json:"move_y"`
	Fire  bool    `json:"fire"`
}

type PlayerState struct {
	RoomID  string  `json:"-" gorm:"primaryKey"`
	UserID  string  `json:"user_id" gorm:"primaryKey"`
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	Score   int     `json:"score"`
	Health  int     `json:"health"`
	LastSeq int64   `json:"last_seq"`
}

type Match struct {
	RoomID    string        `json:"room_id" gorm:"primaryKey"`
	Tick      int64         `json:"tick"`
	Status    string        `json:"status"`
	WinnerID  string        `json:"winner_id"`
	UpdatedAt time.Time     `json:"updated_at"`
	Players   []PlayerState `json:"players" gorm:"foreignKey:RoomID;references:RoomID"`
}

type MatchSnapshot struct {
	RoomID    string        `json:"room_id"`
	Tick      int64         `json:"tick"`
	Status    string        `json:"status"`
	WinnerID  string        `json:"winner_id,omitempty"`
	UpdatedAt time.Time     `json:"updated_at"`
	Players   []PlayerState `json:"players"`
}

func (s MatchSnapshot) Player(userID string) *PlayerState {
	for i := range s.Players {
		if s.Players[i].UserID == userID {
			return &s.Players[i]
		}
	}
	return nil
}

type Repository interface {
	Create(Room) (Room, error)
	ByID(string) (Room, error)
	ByCode(string) (Room, error)
	JoinMember(Member, int) error
	SetReady(string, string, bool) error
	StartMatch(string) error
	MatchByRoom(string) (Match, error)
	MutateMatch(string, func(*Match) error) (Match, error)
}
type Service struct {
	repo      Repository
	playGuard func(string, int) error
}

func NewService(r Repository) *Service                    { return &Service{r, nil} }
func (s *Service) SetPlayGuard(f func(string, int) error) { s.playGuard = f }
func token(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return strings.ToUpper(hex.EncodeToString(b))
}
func (s *Service) Create(host string) (Room, error) {
	if err := s.guardPlay(host); err != nil {
		return Room{}, err
	}
	now := time.Now().UTC()
	return s.repo.Create(Room{ID: "room_" + token(8), Code: token(3), HostID: host, Status: "waiting", CreatedAt: now, MemberCount: 1, Members: []Member{{UserID: host, Ready: false, JoinedAt: now}}})
}

func (s *Service) guardPlay(user string) error {
	if s.playGuard == nil || user == "" {
		return nil
	}
	if err := s.playGuard(user, 0); err != nil {
		return ErrPlayBlocked
	}
	return nil
}
func (s *Service) Get(id, user string) (Room, error) {
	r, e := s.repo.ByID(id)
	if e != nil {
		return Room{}, e
	}
	for _, m := range r.Members {
		if m.UserID == user {
			return r, nil
		}
	}
	return Room{}, ErrForbidden
}
func (s *Service) Join(code, user string) (Room, error) {
	if err := s.guardPlay(user); err != nil {
		return Room{}, err
	}
	r, e := s.repo.ByCode(strings.ToUpper(strings.TrimSpace(code)))
	if e != nil {
		return Room{}, e
	}
	if r.Status != "waiting" {
		return Room{}, ErrStarted
	}
	if len(r.Members) >= 4 {
		return Room{}, ErrFull
	}
	for _, m := range r.Members {
		if m.UserID == user {
			return r, nil
		}
	}
	if e = s.repo.JoinMember(Member{RoomID: r.ID, UserID: user, JoinedAt: time.Now().UTC()}, 4); e != nil {
		return Room{}, e
	}
	return s.repo.ByID(r.ID)
}
func (s *Service) Ready(id, user string, on bool) (Room, error) {
	if _, e := s.Get(id, user); e != nil {
		return Room{}, e
	}
	if e := s.repo.SetReady(id, user, on); e != nil {
		return Room{}, e
	}
	return s.repo.ByID(id)
}
func (s *Service) Start(id, user string) (Room, error) {
	r, e := s.Get(id, user)
	if e != nil {
		return Room{}, e
	}
	if r.HostID != user {
		return Room{}, ErrForbidden
	}
	if len(r.Members) < 2 {
		return Room{}, ErrNotReady
	}
	for _, m := range r.Members {
		if !m.Ready {
			return Room{}, ErrNotReady
		}
	}
	if e = s.repo.StartMatch(id); e != nil {
		return Room{}, e
	}
	return s.repo.ByID(id)
}

func newMatch(id string, members []Member, now time.Time) Match {
	players := make([]PlayerState, 0, len(members))
	center := float64(len(members)-1) * spawnSpacing / 2
	for i, member := range members {
		players = append(players, PlayerState{
			RoomID: id, UserID: member.UserID,
			X: float64(i)*spawnSpacing - center, Health: 100,
		})
	}
	return Match{RoomID: id, Status: MatchStarted, UpdatedAt: now, Players: players}
}

func validInput(input PlayerInput) bool {
	return input.Seq > 0 && !math.IsNaN(input.MoveX) && !math.IsNaN(input.MoveY) &&
		!math.IsInf(input.MoveX, 0) && !math.IsInf(input.MoveY, 0) &&
		input.MoveX >= -1 && input.MoveX <= 1 && input.MoveY >= -1 && input.MoveY <= 1
}

func clamp(value, low, high float64) float64 {
	return math.Max(low, math.Min(high, value))
}

func snapshot(match Match) MatchSnapshot {
	players := append([]PlayerState(nil), match.Players...)
	sort.Slice(players, func(i, j int) bool { return players[i].UserID < players[j].UserID })
	return MatchSnapshot{
		RoomID: match.RoomID, Tick: match.Tick, Status: match.Status,
		WinnerID: match.WinnerID, UpdatedAt: match.UpdatedAt, Players: players,
	}
}

func (s *Service) Snapshot(id, user string) (MatchSnapshot, error) {
	if _, err := s.Get(id, user); err != nil {
		return MatchSnapshot{}, err
	}
	match, err := s.repo.MatchByRoom(id)
	if err != nil {
		return MatchSnapshot{}, err
	}
	return snapshot(match), nil
}

func (s *Service) SubmitInput(id, user string, input PlayerInput) (MatchSnapshot, error) {
	if !validInput(input) {
		return MatchSnapshot{}, ErrInvalidInput
	}
	if _, err := s.Get(id, user); err != nil {
		return MatchSnapshot{}, err
	}
	match, err := s.repo.MutateMatch(id, func(match *Match) error {
		if match.Status == MatchFinished {
			return ErrMatchFinished
		}
		if match.Status != MatchStarted {
			return ErrNotStarted
		}
		var actor *PlayerState
		for i := range match.Players {
			if match.Players[i].UserID == user {
				actor = &match.Players[i]
				break
			}
		}
		if actor == nil {
			return ErrForbidden
		}
		if input.Seq <= actor.LastSeq {
			return ErrStaleInput
		}
		actor.X = clamp(actor.X+input.MoveX*moveStep, -maxPosition, maxPosition)
		actor.Y = clamp(actor.Y+input.MoveY*moveStep, -maxPosition, maxPosition)
		actor.LastSeq = input.Seq
		if input.Fire {
			var target *PlayerState
			bestDistance := math.MaxFloat64
			for i := range match.Players {
				candidate := &match.Players[i]
				if candidate.UserID == user || candidate.Health <= 0 {
					continue
				}
				distance := math.Hypot(candidate.X-actor.X, candidate.Y-actor.Y)
				if distance <= fireRange && (distance < bestDistance ||
					(distance == bestDistance && (target == nil || candidate.UserID < target.UserID))) {
					target, bestDistance = candidate, distance
				}
			}
			if target != nil {
				target.Health = max(0, target.Health-hitDamage)
				actor.Score += hitDamage
				if target.Health == 0 {
					match.Status = MatchFinished
					match.WinnerID = actor.UserID
				}
			}
		}
		match.Tick++
		match.UpdatedAt = time.Now().UTC()
		return nil
	})
	if err != nil {
		return MatchSnapshot{}, err
	}
	return snapshot(match), nil
}
