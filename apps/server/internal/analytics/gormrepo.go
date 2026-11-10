package analytics

import "gorm.io/gorm"

type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Event{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db: db}, nil
}
func (r *GormRepo) Add(e Event) error { return r.db.Create(&e).Error }
func (r *GormRepo) List() ([]Event, error) {
	var out []Event
	err := r.db.Order("created_at, id").Find(&out).Error
	return out, err
}
