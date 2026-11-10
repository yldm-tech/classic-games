package community

import "gorm.io/gorm"

type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Rating{}, &Post{}} }

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db}, nil
}
func (r *GormRepo) UpsertRating(v Rating) error { return r.db.Save(&v).Error }
func (r *GormRepo) RatingSummary(gameID, userID string) (float64, int64, int, error) {
	var row struct {
		Average float64
		Count   int64
	}
	if err := r.db.Model(&Rating{}).Select("COALESCE(AVG(value),0) average, COUNT(*) count").Where("game_id = ?", gameID).Scan(&row).Error; err != nil {
		return 0, 0, 0, err
	}
	var mine Rating
	err := r.db.Where("game_id = ? AND user_id = ?", gameID, userID).First(&mine).Error
	if err == gorm.ErrRecordNotFound {
		err = nil
	}
	return row.Average, row.Count, mine.Value, err
}
func (r *GormRepo) CreatePost(p Post) (Post, error) { return p, r.db.Create(&p).Error }
func (r *GormRepo) ListPosts(gameID string) ([]Post, error) {
	var out []Post
	err := r.db.Where("game_id = ?", gameID).Order("created_at DESC, id DESC").Limit(100).Find(&out).Error
	return out, err
}
