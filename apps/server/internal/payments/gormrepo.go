package payments

import (
	"gorm.io/gorm"
	"time"
)

type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Order{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db}, nil
}
func (r *GormRepo) Create(o Order) (Order, error) { return o, r.db.Create(&o).Error }
func (r *GormRepo) Get(id string) (Order, error) {
	var o Order
	e := r.db.First(&o, "id = ?", id).Error
	return o, e
}
func (r *GormRepo) ListByUser(user string, limit int) ([]Order, error) {
	var orders []Order
	q := r.db.Where("user_id = ?", user).Order("created_at DESC")
	if limit > 0 {
		q = q.Limit(limit)
	}
	if e := q.Find(&orders).Error; e != nil {
		return nil, e
	}
	if orders == nil {
		orders = []Order{}
	}
	return orders, nil
}
func (r *GormRepo) Claim(id, providerTx, claimToken string, now, leaseUntil time.Time) (Order, bool, error) {
	result := r.db.Model(&Order{}).
		Where("id = ? AND (status = ? OR (status = ? AND transaction_id = ? AND (lease_until IS NULL OR lease_until <= ?)))", id, "pending", "processing", providerTx, now).
		Updates(map[string]any{"status": "processing", "transaction_id": providerTx, "claim_token": claimToken, "lease_until": leaseUntil})
	if result.Error != nil {
		return Order{}, false, result.Error
	}
	o, err := r.Get(id)
	if err != nil {
		return Order{}, false, err
	}
	if result.RowsAffected != 1 {
		if o.TransactionID == nil || *o.TransactionID != providerTx {
			return Order{}, false, ErrMismatch
		}
		return o, false, nil
	}
	if o.TransactionID == nil || *o.TransactionID != providerTx || o.ClaimToken == nil || *o.ClaimToken != claimToken || o.Status != "processing" {
		return Order{}, false, ErrMismatch
	}
	return o, true, nil
}
func (r *GormRepo) ReleaseClaim(id, providerTx, claimToken string, at time.Time) error {
	v := r.db.Model(&Order{}).
		Where("id = ? AND status = ? AND transaction_id = ? AND claim_token = ?", id, "processing", providerTx, claimToken).
		Updates(map[string]any{"claim_token": nil, "lease_until": at})
	if v.Error != nil {
		return v.Error
	}
	if v.RowsAffected != 1 {
		return ErrTransition
	}
	return nil
}
func (r *GormRepo) MarkPaid(id, providerTx, claimToken string, at time.Time) (bool, error) {
	v := r.db.Model(&Order{}).
		Where("id = ? AND status = ? AND transaction_id = ? AND claim_token = ?", id, "processing", providerTx, claimToken).
		Updates(map[string]any{"status": "paid", "paid_at": at, "claim_token": nil, "lease_until": nil})
	return v.RowsAffected == 1, v.Error
}
