package ai

import (
	"context"
	"time"

	"gorm.io/gorm"
)

// aiCallRow 是 ai_calls 审计表(docs/10-data-model.md):每次 AI 调用的模型/token/重试/成败,
// 用于成本核算与质量回归。
type aiCallRow struct {
	ID               uint `gorm:"primaryKey;autoIncrement"`
	Runtime          string
	Model            string
	PromptTokens     int
	CompletionTokens int
	Retries          int
	Valid            bool
	ErrCode          string
	CreatedAt        time.Time
}

// GormRecorder 把 CallRecord 落库,实现 Recorder。
type GormRecorder struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&aiCallRow{}} }

func NewGormRecorder(db *gorm.DB) (*GormRecorder, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRecorder{db: db}, nil
}

func (r *GormRecorder) Record(_ context.Context, rec CallRecord) {
	// 审计失败不应影响主流程,best-effort 落库。
	_ = r.db.Create(&aiCallRow{
		Runtime:          rec.Runtime,
		Model:            rec.Model,
		PromptTokens:     rec.Tokens.Prompt,
		CompletionTokens: rec.Tokens.Completion,
		Retries:          rec.Retries,
		Valid:            rec.Valid,
		ErrCode:          rec.ErrCode,
	}).Error
}

// TotalTokens 返回累计 token(成本核算)。
func (r *GormRecorder) TotalTokens() (int, error) {
	var row struct{ Total int }
	err := r.db.Model(&aiCallRow{}).
		Select("COALESCE(SUM(prompt_tokens + completion_tokens), 0) AS total").
		Scan(&row).Error
	return row.Total, err
}

// CallCount 返回累计调用次数。
func (r *GormRecorder) CallCount() (int64, error) {
	var n int64
	err := r.db.Model(&aiCallRow{}).Count(&n).Error
	return n, err
}
