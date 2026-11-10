// Package quota 实现按用户的每日配额(docs/14-security-compliance.md)。
// AI 调用是随创作行为线性增长且单价不低的成本——配额是控制「成本失控」这一最现实风险的核心闸门。
// 纯逻辑、并发安全、时钟可注入;接成 gin 中间件即可门控 /ai/mod。
package quota

import (
	"sync"
	"time"
)

type dayCount struct {
	day   string // YYYY-MM-DD(按本地日切)
	count int
}

// Service 维护每用户每日计数。store 是内存实现;生产可换 Redis(同接口)。
type Service struct {
	maxPerDay int
	now       func() time.Time

	mu    sync.Mutex
	users map[string]dayCount
	store StateStore
}

func NewServiceWithStore(maxPerDay int, store StateStore) (*Service, error) {
	s := NewService(maxPerDay)
	s.store = store
	rows, e := store.LoadAll()
	if e != nil {
		return nil, e
	}
	today := s.now().Format("2006-01-02")
	for _, row := range rows {
		if row.Day == today {
			s.users[row.UserID] = dayCount{day: row.Day, count: row.Count}
		}
	}
	return s, nil
}
func (s *Service) saveLocked(id string, dc dayCount) error {
	if s.store == nil {
		return nil
	}
	return s.store.Save(quotaStateRow{UserID: id, Day: dc.day, Count: dc.count})
}

func NewService(maxPerDay int) *Service {
	if maxPerDay <= 0 {
		maxPerDay = 20
	}
	return &Service{maxPerDay: maxPerDay, now: time.Now, users: map[string]dayCount{}}
}

// Allow 尝试为 userID 记一次用量:未超额则 +1 并返回 (true, 剩余);超额返回 (false, 0)。
// 跨天自动重置。
func (s *Service) Allow(userID string) (allowed bool, remaining int) {
	today := s.now().Format("2006-01-02")
	s.mu.Lock()
	defer s.mu.Unlock()

	dc := s.users[userID]
	if dc.day != today {
		dc = dayCount{day: today, count: 0}
	}
	if dc.count >= s.maxPerDay {
		s.users[userID] = dc
		return false, 0
	}
	dc.count++
	s.users[userID] = dc
	if s.saveLocked(userID, dc) != nil {
		dc.count--
		s.users[userID] = dc
		return false, 0
	}
	return true, s.maxPerDay - dc.count
}

// Refund 回退一次今日用量(下游失败补偿);不低于 0,且仅当天计数有效。
func (s *Service) Refund(userID string) {
	today := s.now().Format("2006-01-02")
	s.mu.Lock()
	defer s.mu.Unlock()
	dc := s.users[userID]
	if dc.day == today && dc.count > 0 {
		dc.count--
		s.users[userID] = dc
		if s.saveLocked(userID, dc) != nil {
			dc.count++
			s.users[userID] = dc
		}
	}
}

// Snapshot is the read-only daily quota surface. It never consumes a slot.
type Snapshot struct {
	Used      int `json:"used"`
	Remaining int `json:"remaining"`
	Limit     int `json:"limit"`
}

// Status returns today's used/remaining/limit without incrementing the counter.
func (s *Service) Status(userID string) Snapshot {
	remaining := s.Remaining(userID)
	return Snapshot{Used: s.maxPerDay - remaining, Remaining: remaining, Limit: s.maxPerDay}
}

// Remaining 返回用户今日剩余额度(不消耗)。
func (s *Service) Remaining(userID string) int {
	today := s.now().Format("2006-01-02")
	s.mu.Lock()
	defer s.mu.Unlock()
	dc := s.users[userID]
	if dc.day != today {
		return s.maxPerDay
	}
	r := s.maxPerDay - dc.count
	if r < 0 {
		r = 0
	}
	return r
}
