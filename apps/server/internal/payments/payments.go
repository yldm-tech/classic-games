package payments

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"time"
)

var (
	ErrDisabled   = errors.New("payments: not configured")
	ErrProduct    = errors.New("payments: unknown product")
	ErrSignature  = errors.New("payments: invalid signature")
	ErrMismatch   = errors.New("payments: order details mismatch")
	ErrTransition = errors.New("payments: invalid order transition")
)

type Product struct {
	ID       string `json:"id"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Kind     string `json:"kind"`
	Value    int    `json:"value"`
}
type Order struct {
	ID            string     `json:"id" gorm:"primaryKey"`
	UserID        string     `json:"-" gorm:"index"`
	ProductID     string     `json:"product_id"`
	Amount        int64      `json:"amount"`
	Currency      string     `json:"currency"`
	Status        string     `json:"status" gorm:"index"`
	TransactionID *string    `json:"transaction_id,omitempty" gorm:"uniqueIndex"`
	CreatedAt     time.Time  `json:"created_at"`
	PaidAt        *time.Time `json:"paid_at,omitempty"`
	ClaimToken    *string    `json:"-"`
	LeaseUntil    *time.Time `json:"-"`
}
type Repository interface {
	Create(Order) (Order, error)
	Get(string) (Order, error)
	ListByUser(string, int) ([]Order, error)
	Claim(string, string, string, time.Time, time.Time) (Order, bool, error)
	ReleaseClaim(string, string, string, time.Time) error
	MarkPaid(string, string, string, time.Time) (bool, error)
}
type Service struct {
	repo     Repository
	secret   []byte
	products map[string]Product
	grant    func(string, string, Product) error
}

func NewService(r Repository, secret string, products []Product, grant func(string, string, Product) error) *Service {
	m := map[string]Product{}
	for _, p := range products {
		m[p.ID] = p
	}
	return &Service{r, []byte(secret), m, grant}
}
func (s *Service) Create(user, product string) (Order, error) {
	if len(s.secret) == 0 {
		return Order{}, ErrDisabled
	}
	p, ok := s.products[product]
	if !ok {
		return Order{}, ErrProduct
	}
	var b [12]byte
	_, _ = rand.Read(b[:])
	return s.repo.Create(Order{ID: "pay_" + hex.EncodeToString(b[:]), UserID: user, ProductID: p.ID, Amount: p.Amount, Currency: p.Currency, Status: "pending", CreatedAt: time.Now().UTC()})
}
func (s *Service) Get(user, id string) (Order, error) {
	o, e := s.repo.Get(id)
	if e == nil && o.UserID != user {
		return Order{}, ErrMismatch
	}
	return o, e
}

const defaultOrderListLimit = 50

// List returns the caller's recent orders. Empty user yields an empty list,
// never another account's history.
func (s *Service) List(user string) ([]Order, error) {
	if user == "" {
		return []Order{}, nil
	}
	items, err := s.repo.ListByUser(user, defaultOrderListLimit)
	if items == nil {
		items = []Order{}
	}
	return items, err
}
func (s *Service) Sign(id, tx string, amount int64, currency string) string {
	m := hmac.New(sha256.New, s.secret)
	fmt.Fprintf(m, "%s\n%s\n%d\n%s", id, tx, amount, currency)
	return hex.EncodeToString(m.Sum(nil))
}
func (s *Service) Confirm(id, tx string, amount int64, currency, sig string) (Order, error) {
	if len(s.secret) == 0 {
		return Order{}, ErrDisabled
	}
	if id == "" || tx == "" {
		return Order{}, ErrMismatch
	}
	want, _ := hex.DecodeString(s.Sign(id, tx, amount, currency))
	got, e := hex.DecodeString(sig)
	if e != nil || !hmac.Equal(want, got) {
		return Order{}, ErrSignature
	}
	o, e := s.repo.Get(id)
	if e != nil {
		return Order{}, e
	}
	if o.Amount != amount || o.Currency != currency {
		return Order{}, ErrMismatch
	}
	if o.Status == "paid" {
		if o.TransactionID == nil || *o.TransactionID != tx {
			return Order{}, ErrMismatch
		}
		return o, nil
	}
	if o.Status != "pending" && (o.Status != "processing" || o.TransactionID == nil || *o.TransactionID != tx) {
		return Order{}, ErrMismatch
	}
	claimToken := randomToken()
	now := time.Now().UTC()
	o, claimed, e := s.repo.Claim(id, tx, claimToken, now, now.Add(5*time.Minute))
	if e != nil {
		return Order{}, e
	}
	if !claimed {
		return Order{}, ErrTransition
	}
	if o.TransactionID == nil || *o.TransactionID != tx {
		return Order{}, ErrMismatch
	}
	if o.Status == "paid" {
		return o, nil
	}
	if s.grant != nil {
		if e = s.grant(o.ID, o.UserID, s.products[o.ProductID]); e != nil {
			if releaseErr := s.repo.ReleaseClaim(id, tx, claimToken, time.Now().UTC()); releaseErr != nil {
				return Order{}, fmt.Errorf("%w (release claim: %v)", e, releaseErr)
			}
			return Order{}, e
		}
	}
	marked, e := s.repo.MarkPaid(id, tx, claimToken, time.Now().UTC())
	if e != nil {
		return Order{}, e
	}
	if !marked {
		latest, getErr := s.repo.Get(id)
		if getErr == nil && latest.Status == "paid" && latest.TransactionID != nil && *latest.TransactionID == tx {
			return latest, nil
		}
		return Order{}, ErrTransition
	}
	return s.repo.Get(id)
}

func randomToken() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}
