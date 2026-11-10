package feedback

import "gorm.io/gorm"

type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Item{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db: db}, nil
}
func (r *GormRepo) Create(i Item) (Item, error) { return i, r.db.Create(&i).Error }
