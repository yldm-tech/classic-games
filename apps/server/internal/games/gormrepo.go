package games

import (
	"crypto/rand"
	"encoding/hex"
	"errors"

	"gorm.io/gorm"
)

// GormRepo 是 Repository 的 GORM 实现,可直接替换 MemRepo。
type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Game{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db: db}, nil
}

func (r *GormRepo) Create(g Game) (Game, error) {
	if g.ID == "" {
		g.ID = "game_" + randID()
	}
	if err := r.db.Create(&g).Error; err != nil {
		return Game{}, err
	}
	return g, nil
}

func (r *GormRepo) Get(id string) (Game, error) {
	var g Game
	err := r.db.First(&g, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return Game{}, ErrNotFound
	}
	return g, err
}

func (r *GormRepo) Update(g Game) error {
	// 单条 UPDATE ... WHERE id=?:用 RowsAffected 判存在,避免「先 Count 再 Save」的 TOCTOU,
	// 也避免 Save 把已删行重新 INSERT 回来。Select("*") 让零值字段也参与更新(全量替换语义)。
	res := r.db.Model(&Game{}).Where("id = ?", g.ID).Select("*").Updates(&g)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *GormRepo) IncrementPlays(id string) error {
	res := r.db.Model(&Game{}).Where("id = ?", id).UpdateColumn("plays", gorm.Expr("plays + ?", 1))
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *GormRepo) IncrementForks(id string) error {
	res := r.db.Model(&Game{}).Where("id = ?", id).UpdateColumn("forks", gorm.Expr("forks + ?", 1))
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *GormRepo) UpdateStatus(id string, from, to Status) (Game, error) {
	// 前置条件下推到 WHERE:仅当 status 仍是 from 才写,关掉读-改-写之间的 TOCTOU 窗口。
	res := r.db.Model(&Game{}).Where("id = ? AND status = ?", id, from).Update("status", to)
	if res.Error != nil {
		return Game{}, res.Error
	}
	if res.RowsAffected == 0 {
		// 没命中:区分「行不存在」与「状态不匹配」(已被并发改过)。
		if _, err := r.Get(id); err != nil {
			return Game{}, err // ErrNotFound
		}
		return Game{}, ErrInvalidState
	}
	return r.Get(id)
}

func (r *GormRepo) ListByStatus(s Status) ([]Game, error) {
	var out []Game
	// 新→旧(按创建时间);随机 hex ID 的字典序不代表时间。
	err := r.db.Where("status = ?", s).Order("created_at DESC, id DESC").Find(&out).Error
	return out, err
}

func (r *GormRepo) ListByStatusPage(s Status, offset, limit int) ([]Game, bool, error) {
	var out []Game
	// 分页下推到 SQL(LIMIT/OFFSET);多取一条判定是否还有下一页,省去额外 COUNT。
	err := r.db.Where("status = ?", s).
		Order("created_at DESC, id DESC").
		Offset(offset).Limit(limit + 1).
		Find(&out).Error
	if err != nil {
		return nil, false, err
	}
	hasMore := len(out) > limit
	if hasMore {
		out = out[:limit]
	}
	return out, hasMore, nil
}

func randID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
