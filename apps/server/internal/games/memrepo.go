package games

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

// MemRepo 内存实现，用于测试和本地隔离场景。并发安全。
type MemRepo struct {
	mu   sync.Mutex
	seq  int
	data map[string]Game
}

func NewMemRepo() *MemRepo {
	return &MemRepo{data: map[string]Game{}}
}

func (r *MemRepo) Create(g Game) (Game, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	// 与 GormRepo 一致:有 ID 则保留(种子/导入用),无则生成。
	if g.ID == "" {
		r.seq++
		g.ID = fmt.Sprintf("game_%d", r.seq)
	}
	if g.CreatedAt.IsZero() {
		g.CreatedAt = time.Now()
	}
	r.data[g.ID] = g
	return g, nil
}

func (r *MemRepo) Get(id string) (Game, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	g, ok := r.data[id]
	if !ok {
		return Game{}, ErrNotFound
	}
	return g, nil
}

func (r *MemRepo) Update(g Game) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.data[g.ID]; !ok {
		return ErrNotFound
	}
	r.data[g.ID] = g
	return nil
}

func (r *MemRepo) IncrementPlays(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	g, ok := r.data[id]
	if !ok {
		return ErrNotFound
	}
	g.Plays++
	r.data[id] = g
	return nil
}

func (r *MemRepo) IncrementForks(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	g, ok := r.data[id]
	if !ok {
		return ErrNotFound
	}
	g.Forks++
	r.data[id] = g
	return nil
}

func (r *MemRepo) UpdateStatus(id string, from, to Status) (Game, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	g, ok := r.data[id]
	if !ok {
		return Game{}, ErrNotFound
	}
	// 在锁内完成 check-then-set,与 GormRepo 的条件 UPDATE 等价(并发裁决只有一个成功)。
	if g.Status != from {
		return Game{}, ErrInvalidState
	}
	g.Status = to
	r.data[id] = g
	return g, nil
}

func (r *MemRepo) ListByStatus(s Status) ([]Game, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.listByStatusLocked(s), nil
}

func (r *MemRepo) listByStatusLocked(s Status) []Game {
	var out []Game
	for _, g := range r.data {
		if g.Status == s {
			out = append(out, g)
		}
	}
	// 新→旧(按创建时间,而非字典序 ID);时间相同按 ID 兜底确定性。
	sort.Slice(out, func(i, j int) bool {
		if !out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].CreatedAt.After(out[j].CreatedAt)
		}
		return out[i].ID > out[j].ID
	})
	return out
}

func (r *MemRepo) ListByStatusPage(s Status, offset, limit int) ([]Game, bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	all := r.listByStatusLocked(s)
	if offset >= len(all) {
		return []Game{}, false, nil
	}
	end := offset + limit
	hasMore := end < len(all)
	if end > len(all) {
		end = len(all)
	}
	return all[offset:end], hasMore, nil
}
