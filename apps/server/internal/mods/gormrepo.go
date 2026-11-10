package mods

import (
	"crypto/rand"
	"encoding/hex"
	"errors"

	"gorm.io/gorm"
)

// GormRepo 是 Repository 的 GORM 实现。与 MemRepo 行为一致,可直接替换(见 mods_test 的对照)。
type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Mod{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db: db}, nil
}

func (r *GormRepo) Get(id string) (Mod, error) {
	var m Mod
	err := r.db.First(&m, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return Mod{}, ErrNotFound
	}
	return m, err
}

func (r *GormRepo) Create(m Mod) (Mod, error) {
	if m.ID == "" {
		m.ID = "mod_" + randID()
	}
	if err := r.db.Create(&m).Error; err != nil {
		return Mod{}, err
	}
	return m, nil
}

func (r *GormRepo) SetDraft(id string, draft bool) error {
	res := r.db.Model(&Mod{}).Where("id = ?", id).Update("draft", draft)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *GormRepo) ListChildren(parentID string) ([]Mod, error) {
	var out []Mod
	err := r.db.Where("parent_id = ?", parentID).Order("id").Find(&out).Error
	return out, err
}
func (r *GormRepo) ListByAuthor(authorID string) ([]Mod, error) {
	var out []Mod
	e := r.db.Where("author_id = ? AND draft = ?", authorID, true).Order("created_at DESC, id DESC").Find(&out).Error
	return out, e
}

func randID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
