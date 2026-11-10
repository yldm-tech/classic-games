package moderation

import (
	"crypto/rand"
	"encoding/hex"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// blockRow 是屏蔽关系的 GORM 模型(user_id 屏蔽 blocked_id,联合主键幂等)。
type blockRow struct {
	UserID    string `gorm:"primaryKey"`
	BlockedID string `gorm:"primaryKey"`
	BlockedAt time.Time
}
type hiddenGameRow struct {
	UserID   string `gorm:"primaryKey"`
	GameID   string `gorm:"primaryKey"`
	HiddenAt time.Time
}

func (r *GormRepo) ListBlockEntries(userID string) ([]BlockEntry, error) {
	var rows []blockRow
	if err := r.db.Where("user_id = ?", userID).Order("blocked_id").Find(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]BlockEntry, len(rows))
	for i, row := range rows {
		out[i] = BlockEntry{UserID: row.UserID, BlockedID: row.BlockedID, BlockedAt: row.BlockedAt}
	}
	return out, nil
}

// GormRepo 是 moderation.Repository 的 GORM 实现。
type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Report{}, &blockRow{}, &hiddenGameRow{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db: db}, nil
}

func (r *GormRepo) SetHiddenGame(userID, gameID string, hidden bool) error {
	if hidden {
		// DoNothing 保证幂等:重复隐藏保留原 HiddenAt,不因 time.Now() 进查询条件而误触发 INSERT/主键冲突。
		row := hiddenGameRow{UserID: userID, GameID: gameID, HiddenAt: time.Now().UTC()}
		return r.db.Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error
	}
	return r.db.Delete(&hiddenGameRow{UserID: userID, GameID: gameID}).Error
}
func (r *GormRepo) IsGameHidden(userID, gameID string) (bool, error) {
	var n int64
	e := r.db.Model(&hiddenGameRow{}).Where("user_id = ? AND game_id = ?", userID, gameID).Count(&n).Error
	return n > 0, e
}

func (r *GormRepo) AddReport(rep Report) (Report, error) {
	if rep.ID == "" {
		b := make([]byte, 8)
		_, _ = rand.Read(b)
		rep.ID = "report_" + hex.EncodeToString(b)
	}
	if err := r.db.Create(&rep).Error; err != nil {
		return Report{}, err
	}
	return rep, nil
}

func (r *GormRepo) SetBlock(userID, blockedID string, blocked bool) error {
	if blocked {
		// DoNothing 保证幂等:重复屏蔽保留原 BlockedAt,不因 time.Now() 进查询条件而误触发 INSERT/主键冲突。
		row := blockRow{UserID: userID, BlockedID: blockedID, BlockedAt: time.Now().UTC()}
		return r.db.Clauses(clause.OnConflict{DoNothing: true}).Create(&row).Error
	}
	return r.db.Delete(&blockRow{UserID: userID, BlockedID: blockedID}).Error
}

func (r *GormRepo) IsBlocked(userID, blockedID string) (bool, error) {
	var n int64
	err := r.db.Model(&blockRow{}).Where("user_id = ? AND blocked_id = ?", userID, blockedID).Count(&n).Error
	return n > 0, err
}

func (r *GormRepo) ListBlocked(userID string) ([]string, error) {
	var rows []blockRow
	if err := r.db.Where("user_id = ?", userID).Order("blocked_id").Find(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]string, len(rows))
	for i, b := range rows {
		out[i] = b.BlockedID
	}
	return out, nil
}
