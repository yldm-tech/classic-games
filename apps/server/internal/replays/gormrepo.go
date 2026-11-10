package replays

import "gorm.io/gorm"

type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Replay{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db}, nil
}
func (r *GormRepo) Create(v Replay) (Replay, error) { return v, r.db.Create(&v).Error }
func (r *GormRepo) Latest(game, user string) (Replay, error) {
	var v Replay
	e := r.db.Where("game_id = ? AND user_id = ?", game, user).Order("created_at DESC, id DESC").First(&v).Error
	return v, e
}
func (r *GormRepo) Leaderboard(game string, limit int) ([]LeaderboardRow, error) {
	var out []LeaderboardRow
	e := r.db.Model(&Replay{}).Select("user_id, MAX(score) AS score").Where("game_id = ? AND score > 0", game).Group("user_id").Order("score DESC, user_id ASC").Limit(limit).Scan(&out).Error
	return out, e
}
