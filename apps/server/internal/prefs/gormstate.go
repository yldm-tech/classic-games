package prefs

import "gorm.io/gorm"

type prefStateRow struct {
	UserID string    `gorm:"primaryKey"`
	State  userPrefs `gorm:"serializer:json"`
}
type StateStore interface {
	LoadAll() ([]prefStateRow, error)
	Save(prefStateRow) error
}
type GormStateStore struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&prefStateRow{}} }

func NewGormStateStore(db *gorm.DB) (*GormStateStore, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormStateStore{db}, nil
}
func (s *GormStateStore) LoadAll() ([]prefStateRow, error) {
	var out []prefStateRow
	e := s.db.Find(&out).Error
	return out, e
}
func (s *GormStateStore) Save(v prefStateRow) error { return s.db.Save(&v).Error }
