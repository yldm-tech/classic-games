package library

import "gorm.io/gorm"

type savedDownload struct {
	ClientID  string
	SizeMB    int
	HasUpdate bool
}
type savedHistory struct {
	ClientID      string
	MinutesPlayed int
}
type savedLibrary struct {
	Downloads []savedDownload
	History   [][]savedHistory
}
type libraryStateRow struct {
	UserID string       `gorm:"primaryKey"`
	State  savedLibrary `gorm:"serializer:json"`
}
type StateStore interface {
	LoadAll() ([]libraryStateRow, error)
	Save(libraryStateRow) error
}
type GormStateStore struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&libraryStateRow{}} }

func NewGormStateStore(db *gorm.DB) (*GormStateStore, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormStateStore{db}, nil
}
func (s *GormStateStore) LoadAll() ([]libraryStateRow, error) {
	var out []libraryStateRow
	e := s.db.Find(&out).Error
	return out, e
}
func (s *GormStateStore) Save(v libraryStateRow) error { return s.db.Save(&v).Error }
