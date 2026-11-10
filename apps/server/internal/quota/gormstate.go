package quota

import "gorm.io/gorm"

type quotaStateRow struct {
	UserID string `gorm:"primaryKey"`
	Day    string
	Count  int
}
type StateStore interface {
	LoadAll() ([]quotaStateRow, error)
	Save(quotaStateRow) error
}
type GormStateStore struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&quotaStateRow{}} }

func NewGormStateStore(db *gorm.DB) (*GormStateStore, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormStateStore{db}, nil
}
func (s *GormStateStore) LoadAll() ([]quotaStateRow, error) {
	var out []quotaStateRow
	e := s.db.Find(&out).Error
	return out, e
}
func (s *GormStateStore) Save(v quotaStateRow) error { return s.db.Save(&v).Error }
