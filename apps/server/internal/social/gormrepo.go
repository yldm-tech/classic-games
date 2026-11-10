package social

import (
	"crypto/rand"
	"encoding/hex"
	"time"

	"gorm.io/gorm"
)

// likeRow 是点赞的 GORM 模型(game_id + user_id 联合主键,天然去重幂等)。
type likeRow struct {
	GameID    string    `gorm:"primaryKey"`
	UserID    string    `gorm:"primaryKey"`
	CreatedAt time.Time `gorm:"index"`
}

type favoriteRow struct {
	GameID    string    `gorm:"primaryKey"`
	UserID    string    `gorm:"primaryKey;index"`
	CreatedAt time.Time `gorm:"index"`
}

func (r *GormRepo) RecentLikeCounts(gameIDs []string, since time.Time) (map[string]int, error) {
	out := make(map[string]int, len(gameIDs))
	for _, id := range gameIDs {
		out[id] = 0
	}
	if len(gameIDs) == 0 {
		return out, nil
	}
	type agg struct {
		GameID string
		N      int
	}
	var rows []agg
	err := r.db.Model(&likeRow{}).Select("game_id, count(*) as n").
		Where("game_id IN ? AND created_at >= ?", gameIDs, since).
		Group("game_id").Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, row := range rows {
		out[row.GameID] = row.N
	}
	return out, nil
}

// baseLikeRow 是某游戏的点赞展示基数(种子历史人气);真实点赞在其上累加。
type baseLikeRow struct {
	GameID string `gorm:"primaryKey"`
	Count  int
}

// GormRepo 是 social.Repository 的 GORM 实现。
type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any {
	return []any{&Comment{}, &likeRow{}, &baseLikeRow{}, &favoriteRow{}}
}

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db: db}, nil
}

func (r *GormRepo) SetFavorite(gameID, userID string, favorite bool) error {
	if favorite {
		return r.db.FirstOrCreate(&favoriteRow{GameID: gameID, UserID: userID}).Error
	}
	return r.db.Delete(&favoriteRow{}, "game_id = ? AND user_id = ?", gameID, userID).Error
}

func (r *GormRepo) ListFavorites(userID string) ([]string, error) {
	var rows []favoriteRow
	if err := r.db.Where("user_id = ?", userID).Order("created_at DESC, game_id DESC").Find(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]string, len(rows))
	for i := range rows {
		out[i] = rows[i].GameID
	}
	return out, nil
}

// SetBaseLikes upsert 某游戏的展示基数。
func (r *GormRepo) SetBaseLikes(gameID string, n int) error {
	return r.db.Save(&baseLikeRow{GameID: gameID, Count: n}).Error
}

// baseLikes 取某游戏的展示基数(无则 0)。
func (r *GormRepo) baseLikes(gameID string) int {
	var row baseLikeRow
	if err := r.db.First(&row, "game_id = ?", gameID).Error; err != nil {
		return 0
	}
	return row.Count
}

func (r *GormRepo) AddComment(c Comment) (Comment, error) {
	if c.ID == "" {
		b := make([]byte, 8)
		_, _ = rand.Read(b)
		c.ID = "cmt_" + hex.EncodeToString(b)
	}
	if err := r.db.Create(&c).Error; err != nil {
		return Comment{}, err
	}
	return c, nil
}

func (r *GormRepo) ListComments(gameID string) ([]Comment, error) {
	var out []Comment
	// 按时间(旧→新,与 MemRepo 插入序一致);随机 hex ID 字典序无意义。
	err := r.db.Where("game_id = ?", gameID).Order("created_at, id").Find(&out).Error
	return out, err
}

func (r *GormRepo) SetLike(gameID, userID string, liked bool) error {
	if liked {
		// upsert,重复点赞幂等;直接以待建行为查询条件(两列均主键),避免空 dest。
		return r.db.FirstOrCreate(&likeRow{GameID: gameID, UserID: userID}).Error
	}
	return r.db.Delete(&likeRow{GameID: gameID, UserID: userID}).Error
}

func (r *GormRepo) LikeCount(gameID string) (int, error) {
	var n int64
	err := r.db.Model(&likeRow{}).Where("game_id = ?", gameID).Count(&n).Error
	return r.baseLikes(gameID) + int(n), err
}

func (r *GormRepo) LikeCounts(gameIDs []string) (map[string]int, error) {
	out := make(map[string]int, len(gameIDs))
	for _, id := range gameIDs {
		out[id] = 0 // 无赞的游戏也补 0,语义稳定
	}
	if len(gameIDs) == 0 {
		return out, nil
	}
	type agg struct {
		GameID string
		N      int
	}
	var rows []agg
	err := r.db.Model(&likeRow{}).
		Select("game_id, count(*) as n").
		Where("game_id IN ?", gameIDs).
		Group("game_id").
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, x := range rows {
		out[x.GameID] = x.N
	}
	// 叠加展示基数(种子历史人气),使 social 为单一真相源。
	var bases []baseLikeRow
	if err := r.db.Where("game_id IN ?", gameIDs).Find(&bases).Error; err != nil {
		return nil, err
	}
	for _, b := range bases {
		out[b.GameID] += b.Count
	}
	return out, nil
}

func (r *GormRepo) HasLiked(gameID, userID string) (bool, error) {
	var n int64
	err := r.db.Model(&likeRow{}).Where("game_id = ? AND user_id = ?", gameID, userID).Count(&n).Error
	return n > 0, err
}
