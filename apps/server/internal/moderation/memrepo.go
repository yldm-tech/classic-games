package moderation

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

// MemRepo 内存实现，用于测试和本地隔离场景。并发安全。
type MemRepo struct {
	mu      sync.Mutex
	seq     int
	reports []Report
	blocks  map[string]map[string]time.Time // userID -> blockedID -> 创建时间
	hidden  map[string]map[string]bool
}

func NewMemRepo() *MemRepo {
	return &MemRepo{blocks: map[string]map[string]time.Time{}, hidden: map[string]map[string]bool{}}
}

func (r *MemRepo) SetHiddenGame(userID, gameID string, hidden bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.hidden[userID] == nil {
		r.hidden[userID] = map[string]bool{}
	}
	if hidden {
		r.hidden[userID][gameID] = true
	} else {
		delete(r.hidden[userID], gameID)
	}
	return nil
}
func (r *MemRepo) IsGameHidden(userID, gameID string) (bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.hidden[userID][gameID], nil
}

func (r *MemRepo) AddReport(rep Report) (Report, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.seq++
	rep.ID = fmt.Sprintf("report_%d", r.seq)
	r.reports = append(r.reports, rep)
	return rep, nil
}

func (r *MemRepo) SetBlock(userID, blockedID string, blocked bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	set := r.blocks[userID]
	if set == nil {
		set = map[string]time.Time{}
		r.blocks[userID] = set
	}
	if blocked {
		if _, exists := set[blockedID]; !exists {
			set[blockedID] = time.Now()
		}
	} else {
		delete(set, blockedID)
	}
	return nil
}

func (r *MemRepo) IsBlocked(userID, blockedID string) (bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	_, ok := r.blocks[userID][blockedID]
	return ok, nil
}

func (r *MemRepo) ListBlockEntries(userID string) ([]BlockEntry, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]BlockEntry, 0, len(r.blocks[userID]))
	for id, at := range r.blocks[userID] {
		out = append(out, BlockEntry{UserID: userID, BlockedID: id, BlockedAt: at})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].BlockedID < out[j].BlockedID })
	return out, nil
}

func (r *MemRepo) ListBlocked(userID string) ([]string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []string
	for id := range r.blocks[userID] {
		out = append(out, id)
	}
	sort.Strings(out)
	return out, nil
}
