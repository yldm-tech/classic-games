// Package auth 实现手机验证码登录(docs/09-api-design.md auth、04-architecture.md)。
// 未注册手机首次登录自动建号。短信发送、用户存储、token 存储都走接口,
// 用户、登录身份及验证码/token 短时状态均可由 GORM 持久化；短信可接 HTTP 网关。
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"
)

var (
	ErrCodeInvalid     = errors.New("auth: 验证码错误或已过期")
	ErrPhoneEmpty      = errors.New("auth: 手机号为空")
	ErrRateLimited     = errors.New("auth: 发送过于频繁,请稍后再试")
	ErrSendFailed      = errors.New("auth: 验证码发送失败")
	ErrPasswordInvalid = errors.New("auth: 手机号或密码错误")
	ErrPasswordLimited = errors.New("auth: 密码登录尝试过多,请稍后再试")
	ErrPasswordWeak    = errors.New("auth: 密码至少 8 位")
	ErrIdentityBound   = errors.New("auth: 该第三方账号已绑定其他用户")
	ErrSessionStore    = errors.New("auth: 会话持久化失败")
)

const (
	codeTTL               = 5 * time.Minute
	sendCooldown          = 60 * time.Second // 同一手机号两次发码的最小间隔(防短信轰炸/刷费)
	maxVerifyAttempts     = 5                // 单个验证码最多容许的校验失败次数(防暴力猜码)
	maxPasswordAttempts   = 5                // 账号或来源 IP 在窗口内最多进行的密码校验次数
	passwordAttemptWindow = 15 * time.Minute
)

type User struct {
	ID string `json:"id" gorm:"primaryKey"`
	// 手机号是 PII,不外泄到响应 JSON(docs/14「敏感字段不外泄」);仅作登录唯一键持久化。
	// 注:gorm 用字段名落库,json:"-" 不影响持久化。生产还应加密存储(见 PR 说明)。
	Phone        string `json:"-" gorm:"index"`
	Nickname     string `json:"nickname"`
	PasswordHash string `json:"-"`
}

type LoginIdentity struct {
	Provider string `json:"provider" gorm:"primaryKey"`
	Subject  string `json:"-" gorm:"primaryKey"`
	UserID   string `json:"-" gorm:"index"`
}

// CodeSender 发送验证码；HTTPSender 用于真实网关，LogSender 仅用于本地测试。
type CodeSender interface {
	Send(phone, code string) error
}

// UserRepo 用户存储。
type UserRepo interface {
	FindByPhone(phone string) (User, bool)
	FindByID(id string) (User, bool)
	Create(u User) (User, error)
	Update(u User) error
	Delete(id string) error
	FindIdentity(provider, subject string) (LoginIdentity, bool)
	BindIdentity(LoginIdentity) error
	ListIdentities(userID string) ([]LoginIdentity, error)
}

var ErrUserNotFound = errors.New("auth: 用户不存在")

type pendingCode struct {
	codeHash  string
	expiresAt time.Time
	attempts  int
}

type passwordAttempt struct {
	Count   int
	ResetAt time.Time
}

// Service 编排验证码签发/校验与登录。
type Service struct {
	sender CodeSender
	users  UserRepo
	now    func() time.Time

	mu    sync.Mutex
	codes map[string]pendingCode // phone -> code
	// lastSentAt 与 codes 解耦:发码冷却只看它,不受暴力锁定删除 codes 的影响,
	// 否则攻击者用 5 次廉价错码删掉 codes 即可绕过冷却、持续轰炸短信。
	lastSentAt       map[string]time.Time  // phone -> 上次发码时间
	tokens           map[string]tokenEntry // token -> {userID, 过期时间}
	admins           map[string]bool       // 管理员用户 ID 白名单(审核裁决等特权操作)
	devAdmin         bool                  // 仅 dev:任何已登录用户都算管理员(集成测试用,生产严禁开)
	oauth            OAuthVerifier
	runtimeStore     RuntimeStore
	passwordAttempts map[string]passwordAttempt
	passwordInFlight map[string]int
}

// tokenTTL 是 bearer token 有效期;过期后需重新登录或 refresh(防泄露 token 永久可用)。
const tokenTTL = 30 * 24 * time.Hour

// tokenEntry 是一条 token 记录:对应用户 + 过期时间。生产迁 Redis 时用 SETEX/DEL 即可。
type tokenEntry struct {
	userID    string
	expiresAt time.Time
}

func NewService(sender CodeSender, users UserRepo) *Service {
	return &Service{
		sender: sender, users: users, now: time.Now,
		codes: map[string]pendingCode{}, lastSentAt: map[string]time.Time{},
		tokens:           map[string]tokenEntry{},
		admins:           map[string]bool{},
		passwordAttempts: map[string]passwordAttempt{},
		passwordInFlight: map[string]int{},
	}
}

func NewServiceWithRuntimeStore(sender CodeSender, users UserRepo, store RuntimeStore) (*Service, error) {
	s := NewService(sender, users)
	s.runtimeStore = store
	v, e := store.Load()
	if e != nil {
		return nil, e
	}
	now := s.now()
	for phone, c := range v.Codes {
		if now.Before(c.ExpiresAt) {
			s.codes[phone] = pendingCode{codeHash: c.CodeHash, expiresAt: c.ExpiresAt, attempts: c.Attempts}
		}
	}
	for phone, t := range v.LastSentAt {
		if now.Sub(t) < sendCooldown {
			s.lastSentAt[phone] = t
		}
	}
	for token, e := range v.Tokens {
		if now.Before(e.ExpiresAt) {
			key := token
			if len(key) != 64 {
				key = tokenKey(key)
			}
			s.tokens[key] = tokenEntry{userID: e.UserID, expiresAt: e.ExpiresAt}
		}
	}
	for key, attempt := range v.PasswordAttempts {
		if now.Before(attempt.ResetAt) {
			s.passwordAttempts[key] = passwordAttempt{Count: attempt.Count, ResetAt: attempt.ResetAt}
		}
	}
	if e = s.saveRuntimeLocked(); e != nil {
		return nil, e
	}
	return s, nil
}

func (s *Service) saveRuntimeLocked() error {
	if s.runtimeStore == nil {
		return nil
	}
	v := authRuntimeState{Codes: map[string]savedCode{}, LastSentAt: map[string]time.Time{}, Tokens: map[string]savedToken{}, PasswordAttempts: map[string]savedPasswordAttempt{}}
	for k, c := range s.codes {
		v.Codes[k] = savedCode{c.codeHash, c.expiresAt, c.attempts}
	}
	for k, t := range s.lastSentAt {
		v.LastSentAt[k] = t
	}
	for k, t := range s.tokens {
		v.Tokens[k] = savedToken{t.userID, t.expiresAt}
	}
	for k, attempt := range s.passwordAttempts {
		v.PasswordAttempts[k] = savedPasswordAttempt{Count: attempt.Count, ResetAt: attempt.ResetAt}
	}
	return s.runtimeStore.Save(v)
}

// SetDevAdmin 打开/关闭 dev 管理员旁路(任何登录用户都被当作管理员)。
// 仅供本地/集成测试,生产绝不可开(会让任何人都能做审核裁决)。
func (s *Service) SetDevAdmin(on bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.devAdmin = on
}

// SetAdmins 配置管理员用户 ID 白名单(覆盖式)。空白名单=无人有审核权,是安全默认。
func (s *Service) SetAdmins(ids ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.admins = map[string]bool{}
	for _, id := range ids {
		if id != "" {
			s.admins[id] = true
		}
	}
}

// IsAdmin 判断用户是否为管理员(供审核裁决等特权端点鉴权)。
func (s *Service) IsAdmin(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.devAdmin {
		return id != "" // dev 旁路:任何已登录用户即管理员
	}
	return s.admins[id]
}

// SendCode 生成 6 位验证码、存储、发送。
// 同一手机号在 sendCooldown 内重复请求被拒(ErrRateLimited),防短信轰炸与刷费。
// 冷却基于 lastSentAt(与 codes 生命周期解耦):暴力锁定删 codes 不会重置冷却;
// 只有成功 Login 消费才清掉 lastSentAt,允许立即重发(已证明拥有该号)。
func (s *Service) SendCode(phone string) error {
	if phone == "" {
		return ErrPhoneEmpty
	}
	now := s.now()
	// 先在锁内做廉价的冷却检查:必然被拒的请求直接返回,不再白算一次 bcrypt。
	// 否则未鉴权的 /auth/sms/send 每个被限流的请求仍付 ~cost-10 hash,构成 CPU 放大面。
	s.mu.Lock()
	if t, ok := s.lastSentAt[phone]; ok && now.Sub(t) < sendCooldown {
		s.mu.Unlock()
		return ErrRateLimited
	}
	s.mu.Unlock()

	// bcrypt 仍在锁外计算(不长时间持锁,保留原设计意图)。
	code := gen6()
	codeHash, hashErr := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if hashErr != nil {
		return hashErr
	}

	s.mu.Lock()
	// 解锁到重锁之间可能有并发写入,重查一次冷却(double-check)守住窗口。
	if t, ok := s.lastSentAt[phone]; ok && now.Sub(t) < sendCooldown {
		s.mu.Unlock()
		return ErrRateLimited
	}
	s.lastSentAt[phone] = now
	s.codes[phone] = pendingCode{codeHash: string(codeHash), expiresAt: now.Add(codeTTL)}
	if err := s.saveRuntimeLocked(); err != nil {
		s.mu.Unlock()
		return err
	}
	s.mu.Unlock()
	if err := s.sender.Send(phone, code); err != nil {
		s.mu.Lock()
		// 仅回滚本次写入，避免未来 sender 异步化后误删更新值。
		if pending, ok := s.codes[phone]; ok && pending.codeHash == string(codeHash) {
			delete(s.codes, phone)
			delete(s.lastSentAt, phone)
		}
		_ = s.saveRuntimeLocked()
		s.mu.Unlock()
		return err
	}
	return nil
}

// nickPrefix 取本地化的默认昵称前缀(注册时按请求语言固定;lang 省略则默认 zh)。
func nickPrefix(key string, lang []string) string {
	l := i18n.DefaultLang
	if len(lang) > 0 {
		l = lang[0]
	}
	return i18n.T(l, key)
}

// Login 校验验证码;未注册自动建号;签发 token。返回 (token, user)。
// lang 可选(取请求语言),用于给新用户生成本地化默认昵称。
func (s *Service) Login(phone, code string, lang ...string) (string, User, error) {
	if phone == "" {
		return "", User{}, ErrPhoneEmpty
	}
	s.mu.Lock()
	valid := s.consumeCodeLocked(phone, code)
	persistErr := s.saveRuntimeLocked()
	s.mu.Unlock()
	if persistErr != nil {
		return "", User{}, persistErr
	}
	if !valid {
		return "", User{}, ErrCodeInvalid
	}

	u, exists := s.users.FindByPhone(phone)
	if !exists {
		var err error
		// 昵称用随机后缀,不泄露手机号片段(隐私);前缀按请求语言本地化。
		u, err = s.users.Create(User{Phone: phone, Nickname: nickPrefix("nickname_player", lang) + randSuffix()})
		if err != nil {
			// 并发首登同号:唯一索引冲突 → 回查既有用户,当作"已存在"(幂等)。
			if existing, ok := s.users.FindByPhone(phone); ok {
				u = existing
			} else {
				return "", User{}, err
			}
		}
	}

	if token := s.issueToken(u); token != "" {
		return token, u, nil
	}
	return "", User{}, ErrSessionStore
}

func (s *Service) ChangePhone(userID, phone, code string) error {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return ErrPhoneEmpty
	}
	s.mu.Lock()
	valid := s.consumeCodeLocked(phone, code)
	persistErr := s.saveRuntimeLocked()
	s.mu.Unlock()
	if persistErr != nil {
		return persistErr
	}
	if !valid {
		return ErrCodeInvalid
	}
	if other, exists := s.users.FindByPhone(phone); exists && other.ID != userID {
		return errors.New("auth: 手机号已绑定")
	}
	u, exists := s.users.FindByID(userID)
	if !exists {
		return ErrUserNotFound
	}
	u.Phone = phone
	return s.users.Update(u)
}

// consumeCodeLocked centralizes one-time consumption and brute-force accounting for
// every verification flow. Caller must hold s.mu.
func (s *Service) consumeCodeLocked(phone, code string) bool {
	pc, ok := s.codes[phone]
	// 无论待验证码是否存在,都执行一次等价 bcrypt 比较,消除"该号是否正处于验证流程"的
	// 时序旁路(与 password.go 的 dummyPasswordHash 同一防御:不存在时对 dummy 哈希比较)。
	hash := dummyPasswordHash
	if ok {
		hash = []byte(pc.codeHash)
	}
	match := bcrypt.CompareHashAndPassword(hash, []byte(code)) == nil
	valid := ok && match && s.now().Before(pc.expiresAt)
	if valid {
		delete(s.codes, phone)
		delete(s.lastSentAt, phone)
		return true
	}
	if ok {
		pc.attempts++
		if pc.attempts >= maxVerifyAttempts {
			delete(s.codes, phone)
		} else {
			s.codes[phone] = pc
		}
	}
	return false
}

// GuestLogin 为游客签发临时身份与 token(无手机号,合成唯一标识)。
// 让"先逛后登录"流程在全站鉴权下仍可用;游客身份不可恢复(换设备即新游客)。
// guestPhonePrefix marks a self-issued guest account. Guest identities cost nothing to obtain, so anything that meters
// a scarce resource must not treat them as distinct subjects — see IsGuest and quota.UserOrIP.
const guestPhonePrefix = "guest:"

// IsGuest reports whether the id belongs to a self-issued guest account rather than a real, claimed identity.
func (s *Service) IsGuest(id string) bool {
	if id == "" {
		return false
	}
	u, ok := s.users.FindByID(id)
	if !ok {
		return false
	}
	return strings.HasPrefix(u.Phone, guestPhonePrefix)
}

func (s *Service) GuestLogin(lang ...string) (string, User, error) {
	u, err := s.users.Create(User{Phone: guestPhonePrefix + randSuffix() + randSuffix(), Nickname: nickPrefix("nickname_guest", lang) + randSuffix()})
	if err != nil {
		return "", User{}, err
	}
	if token := s.issueToken(u); token != "" {
		return token, u, nil
	}
	return "", User{}, ErrSessionStore
}

// issueToken 生成并登记一个新 token(带 TTL)。
func (s *Service) issueToken(u User) string {
	token := randToken()
	key := tokenKey(token)
	s.mu.Lock()
	s.tokens[key] = tokenEntry{userID: u.ID, expiresAt: s.now().Add(tokenTTL)}
	if s.saveRuntimeLocked() != nil {
		delete(s.tokens, key)
		token = ""
	}
	s.mu.Unlock()
	return token
}

// Logout 注销:删除该 token(幂等;无效 token 也安全)。供 POST /auth/logout。
func (s *Service) Logout(token string) error {
	s.mu.Lock()
	key := tokenKey(token)
	old, had := s.tokens[key]
	delete(s.tokens, key)
	err := s.saveRuntimeLocked()
	if err != nil && had {
		s.tokens[key] = old
	}
	s.mu.Unlock()
	return err
}

// Refresh 轮换 token:旧 token 有效则作废它并签发新 token(滑动续期)。供 POST /auth/refresh。
// 无效/过期 token 返回 ("", false)。
func (s *Service) Refresh(token string) (string, bool) {
	s.mu.Lock()
	key := tokenKey(token)
	e, ok := s.tokens[key]
	valid := ok && s.now().Before(e.expiresAt)
	if valid {
		delete(s.tokens, key)
		if s.saveRuntimeLocked() != nil {
			s.tokens[key] = e
			valid = false
		}
	}
	s.mu.Unlock()
	if !valid {
		return "", false
	}
	// 与其他签发点对称(Login/GuestLogin/oauth/password):issueToken 持久化失败返回 ""。
	// 此时旧 token 已作废,不能再回报成功——否则客户端会存下空 token 并被静默登出。
	newTok := s.issueToken(User{ID: e.userID})
	if newTok == "" {
		return "", false
	}
	return newTok, true
}

// User 按 ID 取用户(供 /users/me 等)。
func (s *Service) User(id string) (User, error) {
	u, ok := s.users.FindByID(id)
	if !ok {
		return User{}, ErrUserNotFound
	}
	return u, nil
}

func (s *Service) DeleteAccount(id string) error {
	u, ok := s.users.FindByID(id)
	if !ok {
		return ErrUserNotFound
	}
	if err := s.users.Delete(id); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for token, entry := range s.tokens {
		if entry.userID == id {
			delete(s.tokens, token)
		}
	}
	delete(s.codes, u.Phone)
	delete(s.lastSentAt, u.Phone)
	delete(s.admins, id)
	return s.saveRuntimeLocked()
}

// UserIDForToken 解析 token 对应的用户(供鉴权中间件用)。过期 token 视为无效并顺手清理。
func (s *Service) UserIDForToken(token string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := tokenKey(token)
	e, ok := s.tokens[key]
	if !ok {
		return "", false
	}
	if !s.now().Before(e.expiresAt) {
		delete(s.tokens, key)
		_ = s.saveRuntimeLocked()
		return "", false
	}
	return e.userID, true
}

func gen6() string {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "000000"
	}
	return fmt.Sprintf("%06d", n.Int64())
}

func randToken() string {
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func tokenKey(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

// randSuffix 返回 8 位随机十六进制(用于昵称/合成手机号,避免可预测/碰撞)。
func randSuffix() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
