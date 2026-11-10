package participation

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"
)

var (
	ErrInvalidAmount = errors.New("participation: withdrawal amount is outside available balance")
	ErrDuplicate     = errors.New("participation: pending withdrawal already exists")
	ErrEventNotFound = errors.New("participation: event not found")
)

type Withdrawal struct {
	ID        string    `json:"id" gorm:"primaryKey"`
	UserID    string    `json:"-" gorm:"index"`
	Amount    int       `json:"amount"`
	Status    string    `json:"status" gorm:"index"`
	CreatedAt time.Time `json:"created_at"`
}
type EventJoin struct {
	UserID   string    `json:"-" gorm:"primaryKey"`
	EventID  string    `json:"event_id" gorm:"primaryKey"`
	JoinedAt time.Time `json:"joined_at"`
}
type Repository interface {
	PendingWithdrawal(string) (bool, error)
	CreateWithdrawal(Withdrawal) (Withdrawal, error)
	ListWithdrawals(string) ([]Withdrawal, error)
	SumReserved(string) (int, error)
	Join(EventJoin) (EventJoin, error)
	Joined(string) ([]string, error)
}
type Service struct {
	repo        Repository
	eventExists func(string) bool
	available   func(string) int
}

func NewService(r Repository, exists func(string) bool, available ...func(string) int) *Service {
	var a func(string) int
	if len(available) > 0 {
		a = available[0]
	}
	return &Service{repo: r, eventExists: exists, available: a}
}
func id(prefix string) (string, error) {
	var b [12]byte
	if _, e := rand.Read(b[:]); e != nil {
		return "", e
	}
	return prefix + hex.EncodeToString(b[:]), nil
}
func (s *Service) Withdraw(user string, amount int) (Withdrawal, error) {
	if user == "" || amount < 100 || s.available == nil || amount > s.available(user) {
		return Withdrawal{}, ErrInvalidAmount
	}
	pending, e := s.repo.PendingWithdrawal(user)
	if e != nil {
		return Withdrawal{}, e
	}
	if pending {
		return Withdrawal{}, ErrDuplicate
	}
	vID, e := id("wd_")
	if e != nil {
		return Withdrawal{}, e
	}
	return s.repo.CreateWithdrawal(Withdrawal{ID: vID, UserID: user, Amount: amount, Status: "pending", CreatedAt: time.Now().UTC()})
}
func (s *Service) Join(user, event string) (EventJoin, error) {
	if user == "" || event == "" || s.eventExists == nil || !s.eventExists(event) {
		return EventJoin{}, ErrEventNotFound
	}
	return s.repo.Join(EventJoin{UserID: user, EventID: event, JoinedAt: time.Now().UTC()})
}
func (s *Service) Joined(user string) ([]string, error) { return s.repo.Joined(user) }

// Withdrawals returns the caller's cash-out history. Empty user is an empty list.
func (s *Service) Withdrawals(user string) ([]Withdrawal, error) {
	if user == "" {
		return []Withdrawal{}, nil
	}
	items, err := s.repo.ListWithdrawals(user)
	if items == nil {
		items = []Withdrawal{}
	}
	return items, err
}

// Reserved is the sum of pending and paid cash-outs. Failed rows do not count.
func (s *Service) Reserved(user string) (int, error) {
	if user == "" {
		return 0, nil
	}
	return s.repo.SumReserved(user)
}
