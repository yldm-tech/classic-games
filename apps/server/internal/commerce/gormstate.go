package commerce

import (
	"encoding/json"
	"errors"

	"gorm.io/gorm"
)

type StateStore interface {
	Load(userID string) (*userState, error)
	Save(userID string, state *userState) error
}

type commerceStateRow struct {
	UserID string `gorm:"primaryKey"`
	Data   []byte `gorm:"not null"`
}
type GormStateStore struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&commerceStateRow{}} }

func NewGormStateStore(db *gorm.DB) (*GormStateStore, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormStateStore{db}, nil
}
func (s *GormStateStore) Load(userID string) (*userState, error) {
	var row commerceStateRow
	err := s.db.First(&row, "user_id = ?", userID).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var st userState
	if err = json.Unmarshal(row.Data, &st); err != nil {
		return nil, err
	}
	return &st, nil
}
func (s *GormStateStore) Save(userID string, st *userState) error {
	data, err := json.Marshal(st)
	if err != nil {
		return err
	}
	return s.db.Save(&commerceStateRow{UserID: userID, Data: data}).Error
}
