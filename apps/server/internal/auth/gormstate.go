package auth

import (
	"gorm.io/gorm"
	"time"
)

type savedCode struct {
	CodeHash  string
	ExpiresAt time.Time
	Attempts  int
}
type savedToken struct {
	UserID    string
	ExpiresAt time.Time
}
type savedPasswordAttempt struct {
	Count   int
	ResetAt time.Time
}
type authRuntimeState struct {
	Codes            map[string]savedCode
	LastSentAt       map[string]time.Time
	Tokens           map[string]savedToken
	PasswordAttempts map[string]savedPasswordAttempt
}
type authRuntimeRow struct {
	ID    uint             `gorm:"primaryKey"`
	State authRuntimeState `gorm:"serializer:json"`
}
type RuntimeStore interface {
	Load() (authRuntimeState, error)
	Save(authRuntimeState) error
}
type GormRuntimeStore struct{ db *gorm.DB }

func RuntimeMigrationModels() []any { return []any{&authRuntimeRow{}} }

func NewGormRuntimeStore(db *gorm.DB) (*GormRuntimeStore, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRuntimeStore{db}, nil
}
func (s *GormRuntimeStore) Load() (authRuntimeState, error) {
	var row authRuntimeRow
	e := s.db.First(&row, "id = ?", 1).Error
	if e == gorm.ErrRecordNotFound {
		return authRuntimeState{}, nil
	}
	return row.State, e
}
func (s *GormRuntimeStore) Save(v authRuntimeState) error {
	return s.db.Save(&authRuntimeRow{ID: 1, State: v}).Error
}
