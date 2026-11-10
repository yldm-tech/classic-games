package users

import "gorm.io/gorm"

type userStateRow struct {
	UserID             string             `gorm:"primaryKey"`
	Handle             string             `gorm:"index"`
	Profile            Profile            `gorm:"serializer:json"`
	Verification       VerificationStatus `gorm:"serializer:json"`
	VerificationDigest []byte
}

type StateStore interface {
	LoadAll() ([]userStateRow, error)
	Save(userStateRow) error
}
type GormStateStore struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&userStateRow{}} }

func NewGormStateStore(db *gorm.DB) (*GormStateStore, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormStateStore{db}, nil
}
func (s *GormStateStore) LoadAll() ([]userStateRow, error) {
	var out []userStateRow
	e := s.db.Find(&out).Error
	return out, e
}
func (s *GormStateStore) Save(v userStateRow) error { return s.db.Save(&v).Error }
