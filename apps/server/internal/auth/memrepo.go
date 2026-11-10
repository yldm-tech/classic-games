package auth

import (
	"errors"
	"fmt"
	"sort"
	"sync"
)

// MemUserRepo 是用于测试与本地隔离场景的内存用户存储。
type MemUserRepo struct {
	mu         sync.Mutex
	seq        int
	byID       map[string]User
	byPhone    map[string]string // phone -> id
	identities map[string]LoginIdentity
}

func NewMemUserRepo() *MemUserRepo {
	return &MemUserRepo{byID: map[string]User{}, byPhone: map[string]string{}, identities: map[string]LoginIdentity{}}
}

func (r *MemUserRepo) Update(u User) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	old, ok := r.byID[u.ID]
	if !ok {
		return ErrUserNotFound
	}
	if u.Phone != old.Phone {
		if other := r.byPhone[u.Phone]; u.Phone != "" && other != "" && other != u.ID {
			return errors.New("auth: 手机号已存在")
		}
		delete(r.byPhone, old.Phone)
		if u.Phone != "" {
			r.byPhone[u.Phone] = u.ID
		}
	}
	r.byID[u.ID] = u
	return nil
}
func identityKey(p, s string) string { return p + "\x00" + s }
func (r *MemUserRepo) FindIdentity(p, s string) (LoginIdentity, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	v, ok := r.identities[identityKey(p, s)]
	return v, ok
}
func (r *MemUserRepo) BindIdentity(v LoginIdentity) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	k := identityKey(v.Provider, v.Subject)
	if old, ok := r.identities[k]; ok && old.UserID != v.UserID {
		return ErrIdentityBound
	}
	r.identities[k] = v
	return nil
}
func (r *MemUserRepo) ListIdentities(uid string) ([]LoginIdentity, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []LoginIdentity
	for _, v := range r.identities {
		if v.UserID == uid {
			out = append(out, v)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Provider < out[j].Provider })
	return out, nil
}

func (r *MemUserRepo) FindByPhone(phone string) (User, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	id, ok := r.byPhone[phone]
	if !ok {
		return User{}, false
	}
	return r.byID[id], true
}

func (r *MemUserRepo) FindByID(id string) (User, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	u, ok := r.byID[id]
	return u, ok
}

func (r *MemUserRepo) Create(u User) (User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if u.Phone != "" {
		if _, exists := r.byPhone[u.Phone]; exists {
			return User{}, fmt.Errorf("auth: 手机号已存在") // 与 GORM uniqueIndex 一致
		}
	}
	r.seq++
	u.ID = fmt.Sprintf("user_%d", r.seq)
	r.byID[u.ID] = u
	r.byPhone[u.Phone] = u.ID
	return u, nil
}

func (r *MemUserRepo) Delete(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	u, ok := r.byID[id]
	if !ok {
		return ErrUserNotFound
	}
	delete(r.byID, id)
	if u.Phone != "" {
		delete(r.byPhone, u.Phone)
	}
	for k, v := range r.identities {
		if v.UserID == id {
			delete(r.identities, k)
		}
	}
	return nil
}

// LogSender 是 stub 短信发送器:不真发,记录最后一次,供本地/测试。
type LogSender struct {
	mu   sync.Mutex
	Last map[string]string // phone -> code
}

func NewLogSender() *LogSender { return &LogSender{Last: map[string]string{}} }

func (s *LogSender) Send(phone, code string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.Last[phone] = code
	return nil
}
