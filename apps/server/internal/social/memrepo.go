package social

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

// MemRepo 内存实现，用于测试和本地隔离场景。并发安全。
type MemRepo struct {
	mu        sync.Mutex
	seq       int
	comments  map[string][]Comment            // gameID -> comments(按时间/ID 升序)
	likes     map[string]map[string]time.Time // gameID -> userID -> 点赞时间
	base      map[string]int                  // gameID -> 展示基数(种子历史人气;真实点赞在其上累加)
	favorites map[string]map[string]time.Time // userID -> gameID -> 收藏时间
}

func NewMemRepo() *MemRepo {
	return &MemRepo{comments: map[string][]Comment{}, likes: map[string]map[string]time.Time{}, base: map[string]int{}, favorites: map[string]map[string]time.Time{}}
}

func (r *MemRepo) SetFavorite(gameID, userID string, favorite bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	set := r.favorites[userID]
	if set == nil {
		set = map[string]time.Time{}
		r.favorites[userID] = set
	}
	if favorite {
		if _, ok := set[gameID]; !ok {
			set[gameID] = time.Now()
		}
	} else {
		delete(set, gameID)
	}
	return nil
}

func (r *MemRepo) ListFavorites(userID string) ([]string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	type pair struct {
		id string
		at time.Time
	}
	rows := make([]pair, 0, len(r.favorites[userID]))
	for id, at := range r.favorites[userID] {
		rows = append(rows, pair{id, at})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].at.Equal(rows[j].at) {
			return rows[i].id > rows[j].id
		}
		return rows[i].at.After(rows[j].at)
	})
	out := make([]string, len(rows))
	for i := range rows {
		out[i] = rows[i].id
	}
	return out, nil
}

// SetBaseLikes 设置某游戏的点赞展示基数(种子历史人气),使 social 成为点赞数的单一真相源。
func (r *MemRepo) SetBaseLikes(gameID string, n int) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.base[gameID] = n
	return nil
}

func (r *MemRepo) AddComment(c Comment) (Comment, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.seq++
	c.ID = fmt.Sprintf("cmt_%d", r.seq)
	if c.CreatedAt.IsZero() {
		c.CreatedAt = time.Now()
	}
	r.comments[c.GameID] = append(r.comments[c.GameID], c)
	return c, nil
}

func (r *MemRepo) ListComments(gameID string) ([]Comment, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	src := r.comments[gameID]
	out := make([]Comment, len(src))
	copy(out, src) // 已按插入顺序;返回副本避免外部改动
	return out, nil
}

func (r *MemRepo) SetLike(gameID, userID string, liked bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	set := r.likes[gameID]
	if set == nil {
		set = map[string]time.Time{}
		r.likes[gameID] = set
	}
	if liked {
		if _, exists := set[userID]; !exists {
			set[userID] = time.Now()
		}
	} else {
		delete(set, userID)
	}
	return nil
}

func (r *MemRepo) LikeCount(gameID string) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.base[gameID] + len(r.likes[gameID]), nil
}

func (r *MemRepo) LikeCounts(gameIDs []string) (map[string]int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make(map[string]int, len(gameIDs))
	for _, id := range gameIDs {
		out[id] = r.base[id] + len(r.likes[id])
	}
	return out, nil
}

func (r *MemRepo) RecentLikeCounts(gameIDs []string, since time.Time) (map[string]int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make(map[string]int, len(gameIDs))
	for _, id := range gameIDs {
		for _, likedAt := range r.likes[id] {
			if !likedAt.Before(since) {
				out[id]++
			}
		}
	}
	return out, nil
}

func (r *MemRepo) HasLiked(gameID, userID string) (bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	_, ok := r.likes[gameID][userID]
	return ok, nil
}
