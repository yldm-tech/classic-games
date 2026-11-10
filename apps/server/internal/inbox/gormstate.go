package inbox

import "gorm.io/gorm"

type userState struct {
	Messages      map[int][]Message
	Conversations map[string][]Message
	Following     map[string]bool
	Friends       map[string]bool
}
type inboxStateRow struct {
	UserID string    `gorm:"primaryKey"`
	State  userState `gorm:"serializer:json"`
}
type StateStore interface {
	LoadAll() ([]inboxStateRow, error)
	Save(inboxStateRow) error
}
type GormStateStore struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&inboxStateRow{}} }

func NewGormStateStore(db *gorm.DB) (*GormStateStore, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormStateStore{db}, nil
}
func (s *GormStateStore) LoadAll() ([]inboxStateRow, error) {
	var out []inboxStateRow
	e := s.db.Find(&out).Error
	return out, e
}
func (s *GormStateStore) Save(v inboxStateRow) error { return s.db.Save(&v).Error }
