package mods

import (
	"fmt"
	"sort"
	"sync"
)

// MemRepo 是 Repository 的内存实现，用于测试与本地隔离场景。
// 并发安全。
type MemRepo struct {
	mu   sync.Mutex
	seq  int
	data map[string]Mod
}

func NewMemRepo() *MemRepo {
	return &MemRepo{data: map[string]Mod{}}
}

func (r *MemRepo) Get(id string) (Mod, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m, ok := r.data[id]
	if !ok {
		return Mod{}, ErrNotFound
	}
	return m, nil
}

func (r *MemRepo) Create(m Mod) (Mod, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.seq++
	m.ID = fmt.Sprintf("mod_%d", r.seq)
	r.data[m.ID] = m
	return m, nil
}

func (r *MemRepo) SetDraft(id string, draft bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	m, ok := r.data[id]
	if !ok {
		return ErrNotFound
	}
	m.Draft = draft
	r.data[id] = m
	return nil
}

func (r *MemRepo) ListChildren(parentID string) ([]Mod, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []Mod
	for _, m := range r.data {
		if m.ParentID == parentID {
			out = append(out, m)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}
func (r *MemRepo) ListByAuthor(authorID string) ([]Mod, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []Mod
	for _, m := range r.data {
		if m.AuthorID == authorID && m.Draft {
			out = append(out, m)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}
