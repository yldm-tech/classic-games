// Package prefs 暴露用户偏好设置的元数据、当前值与按用户隔离的写入接口：
// 通知设置、隐私设置、青少年模式、黑名单(docs/09-api-design.md、14-security-compliance.md)。
// 文案三语内嵌(//go:embed seed/*.json),开发/测试走内嵌种子;
// 生产可换 prefs 表来源,与 runtimes/mods 基线同理。
//
// 用户面向的文本(label/description/options)按 ?lang= 本地化;
// 机器键(key)与默认值(default)不本地化——它们是契约,不随语言变。
package prefs

import (
	"crypto/sha256"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"
)

//go:embed seed/*.json
var seedFS embed.FS

// 支持的语言;未知或缺省时回落到 zh(对齐客户端 i18n 的回落策略)。
const (
	LangZh      = "zh"
	LangEn      = "en"
	LangJa      = "ja"
	DefaultLang = LangZh
)

// localized 是一段三语文本。Pick 按语言取值,缺失回落 zh,再缺回落空串。
type localized struct {
	Zh string `json:"zh"`
	En string `json:"en"`
	Ja string `json:"ja"`
}

func (l localized) Pick(lang string) string {
	switch lang {
	case LangEn:
		if l.En != "" {
			return l.En
		}
	case LangJa:
		if l.Ja != "" {
			return l.Ja
		}
	}
	return l.Zh // 默认 / 回落
}

// localizedList 是一段三语字符串数组(如青少年规则、段控选项)。
type localizedList struct {
	Zh []string `json:"zh"`
	En []string `json:"en"`
	Ja []string `json:"ja"`
}

func (l localizedList) Pick(lang string) []string {
	switch lang {
	case LangEn:
		if len(l.En) > 0 {
			return l.En
		}
	case LangJa:
		if len(l.Ja) > 0 {
			return l.Ja
		}
	}
	return l.Zh
}

// normalizeLang 把任意入参收敛到受支持的语言;空 / 未知一律 zh。
func normalizeLang(lang string) string {
	switch lang {
	case LangEn, LangJa, LangZh:
		return lang
	default:
		return DefaultLang
	}
}

// ---------- 内嵌种子结构(保留三语,供 Localized 投影) ----------

type notifSeed struct {
	MasterKey     string    `json:"master_key"`
	MasterDefault bool      `json:"master_default"`
	MasterLabel   localized `json:"master_label"`
	MasterSub     localized `json:"master_sub"`
	Groups        []struct {
		Key   string    `json:"key"`
		Label localized `json:"label"`
		Items []struct {
			Key     string    `json:"key"`
			Default bool      `json:"default"`
			Label   localized `json:"label"`
		} `json:"items"`
	} `json:"groups"`
}

type privacySeed struct {
	Note  localized `json:"note"`
	Items []struct {
		Key          string        `json:"key"`
		Kind         string        `json:"kind"` // "segment" | "toggle"
		DefaultIndex int           `json:"default_index"`
		Default      bool          `json:"default"`
		Label        localized     `json:"label"`
		Options      localizedList `json:"options"`
	} `json:"items"`
}

type teenSeed struct {
	DefaultEnabled bool          `json:"default_enabled"`
	PinLength      int           `json:"pin_length"`
	Title          localized     `json:"title"`
	Description    localized     `json:"description"`
	StateOn        localized     `json:"state_on"`
	StateOff       localized     `json:"state_off"`
	PinLabel       localized     `json:"pin_label"`
	PinPlaceholder localized     `json:"pin_placeholder"`
	Rules          localizedList `json:"rules"`
}

type blocksSeed struct {
	Blocked []struct {
		UserID    string    `json:"user_id"`
		BlockedAt localized `json:"blocked_at"`
	} `json:"blocked"`
}

// ---------- 对外响应结构(已按语言投影,文本为单语字符串) ----------

// NotifItem 单条通知开关:key 是契约键,default 是默认开关态,label 已本地化。
type NotifItem struct {
	Key     string `json:"key"`
	Default bool   `json:"default"`
	Label   string `json:"label"`
}

// NotifGroup 通知分组(互动消息 / 系统消息)。
type NotifGroup struct {
	Key   string      `json:"key"`
	Label string      `json:"label"`
	Items []NotifItem `json:"items"`
}

// NotifPrefs 通知设置:总开关 + 分组。
type NotifPrefs struct {
	MasterKey     string       `json:"master_key"`
	MasterDefault bool         `json:"master_default"`
	MasterLabel   string       `json:"master_label"`
	MasterSub     string       `json:"master_sub"`
	Groups        []NotifGroup `json:"groups"`
}

// PrivacyItem 单条隐私项:段控(segment,带选项数组 + 默认下标)或开关(toggle,带默认布尔)。
type PrivacyItem struct {
	Key   string `json:"key"`
	Kind  string `json:"kind"`
	Label string `json:"label"`
	// 不能用 omitempty:段控默认下标 0(第一项)、开关默认 false 都是有意义的零值;
	// 省略会让客户端读不到 key 而出错(privacy_screen 按 kind 取 default_index/default)。
	DefaultIndex int      `json:"default_index"`
	Options      []string `json:"options,omitempty"`
	Default      bool     `json:"default"`
}

// PrivacyPrefs 隐私设置:说明 + 项目列表。
type PrivacyPrefs struct {
	Note  string        `json:"note"`
	Items []PrivacyItem `json:"items"`
}

// TeenPrefs 青少年模式:默认态 + 规则说明文案。
type TeenPrefs struct {
	DefaultEnabled bool     `json:"default_enabled"`
	PinLength      int      `json:"pin_length"`
	Title          string   `json:"title"`
	Description    string   `json:"description"`
	StateOn        string   `json:"state_on"`
	StateOff       string   `json:"state_off"`
	PinLabel       string   `json:"pin_label"`
	PinPlaceholder string   `json:"pin_placeholder"`
	Rules          []string `json:"rules"`
}

// BlockedUser 黑名单中的一条:被屏蔽用户 + 屏蔽时间描述(已本地化)。
type BlockedUser struct {
	UserID    string `json:"user_id"`
	BlockedAt string `json:"blocked_at"`
}

// ---------- Service ----------

// Service 持有三语元数据种子与并发安全的用户偏好状态。
type Service struct {
	mu      sync.Mutex
	notif   notifSeed
	privacy privacySeed
	teen    teenSeed
	blocks  blocksSeed
	users   map[string]*userPrefs
	store   StateStore
}

type userPrefs struct {
	Notifications map[string]bool
	Privacy       map[string]any
	TeenEnabled   bool
	PinHash       [32]byte
	TeenDay       string
	TeenPlaySecs  int
}

var ErrUnknownKey = errors.New("prefs: unknown key")
var ErrInvalidPIN = errors.New("prefs: invalid pin")
var ErrTeenCurfew = errors.New("prefs: teen curfew")
var ErrTeenLimit = errors.New("prefs: teen daily limit")

const (
	TeenDailyLimitSecs = 40 * 60
	TeenCurfewStart    = 22
	TeenCurfewEnd      = 8
)

// NewService 从内嵌 JSON 种子构造 Service。种子非法属编程/资源错误,直接返回 error 让上层 fail-fast。
func NewService() (*Service, error) {
	s := &Service{users: map[string]*userPrefs{}}
	if err := loadSeed("seed/notifications.json", &s.notif); err != nil {
		return nil, err
	}
	if err := loadSeed("seed/privacy.json", &s.privacy); err != nil {
		return nil, err
	}
	if err := loadSeed("seed/teen.json", &s.teen); err != nil {
		return nil, err
	}
	if err := loadSeed("seed/blocks.json", &s.blocks); err != nil {
		return nil, err
	}
	return s, nil
}

func NewServiceWithStore(store StateStore) (*Service, error) {
	s, e := NewService()
	if e != nil {
		return nil, e
	}
	s.store = store
	rows, e := store.LoadAll()
	if e != nil {
		return nil, e
	}
	for _, row := range rows {
		v := row.State
		if v.Notifications == nil {
			v.Notifications = map[string]bool{}
		}
		if v.Privacy == nil {
			v.Privacy = map[string]any{}
		}
		for _, it := range s.privacy.Items {
			if it.Kind == "segment" {
				if n, ok := v.Privacy[it.Key].(float64); ok {
					v.Privacy[it.Key] = int(n)
				}
			}
		}
		s.users[row.UserID] = &v
	}
	return s, nil
}
func (s *Service) saveLocked(userID string) error {
	if s.store == nil {
		return nil
	}
	return s.store.Save(prefStateRow{UserID: userID, State: *s.stateLocked(userID)})
}

func loadSeed(name string, dst any) error {
	data, err := seedFS.ReadFile(name)
	if err != nil {
		return fmt.Errorf("prefs: 读取种子 %s 失败: %w", name, err)
	}
	if err := json.Unmarshal(data, dst); err != nil {
		return fmt.Errorf("prefs: 解析种子 %s 失败: %w", name, err)
	}
	return nil
}

// Notifications 返回按 lang 本地化的通知设置。
func (s *Service) Notifications(lang string) NotifPrefs {
	return s.NotificationsFor("", lang)
}
func (s *Service) NotificationsFor(userID, lang string) NotifPrefs {
	s.mu.Lock()
	st := s.stateLocked(userID)
	values := map[string]bool{}
	for k, v := range st.Notifications {
		values[k] = v
	}
	s.mu.Unlock()
	lang = normalizeLang(lang)
	out := NotifPrefs{
		MasterKey:     s.notif.MasterKey,
		MasterDefault: s.notif.MasterDefault,
		MasterLabel:   s.notif.MasterLabel.Pick(lang),
		MasterSub:     s.notif.MasterSub.Pick(lang),
		Groups:        make([]NotifGroup, 0, len(s.notif.Groups)),
	}
	if v, ok := values[out.MasterKey]; ok {
		out.MasterDefault = v
	}
	for _, g := range s.notif.Groups {
		grp := NotifGroup{
			Key:   g.Key,
			Label: g.Label.Pick(lang),
			Items: make([]NotifItem, 0, len(g.Items)),
		}
		for _, it := range g.Items {
			value := it.Default
			if v, ok := values[it.Key]; ok {
				value = v
			}
			grp.Items = append(grp.Items, NotifItem{
				Key:     it.Key,
				Default: value,
				Label:   it.Label.Pick(lang),
			})
		}
		out.Groups = append(out.Groups, grp)
	}
	return out
}

func (s *Service) stateLocked(userID string) *userPrefs {
	if st := s.users[userID]; st != nil {
		return st
	}
	st := &userPrefs{Notifications: map[string]bool{}, Privacy: map[string]any{}, TeenEnabled: s.teen.DefaultEnabled}
	s.users[userID] = st
	return st
}
func (s *Service) SetNotification(userID, key string, value bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	valid := key == s.notif.MasterKey
	for _, g := range s.notif.Groups {
		for _, it := range g.Items {
			if it.Key == key {
				valid = true
			}
		}
	}
	if !valid {
		return ErrUnknownKey
	}
	s.stateLocked(userID).Notifications[key] = value
	return s.saveLocked(userID)
}

// Privacy 返回按 lang 本地化的隐私设置。
func (s *Service) Privacy(lang string) PrivacyPrefs {
	return s.PrivacyFor("", lang)
}
func (s *Service) PrivacyFor(userID, lang string) PrivacyPrefs {
	s.mu.Lock()
	st := s.stateLocked(userID)
	values := map[string]any{}
	for k, v := range st.Privacy {
		values[k] = v
	}
	s.mu.Unlock()
	lang = normalizeLang(lang)
	out := PrivacyPrefs{
		Note:  s.privacy.Note.Pick(lang),
		Items: make([]PrivacyItem, 0, len(s.privacy.Items)),
	}
	for _, it := range s.privacy.Items {
		pi := PrivacyItem{
			Key:   it.Key,
			Kind:  it.Kind,
			Label: it.Label.Pick(lang),
		}
		switch it.Kind {
		case "segment":
			pi.DefaultIndex = it.DefaultIndex
			if v, ok := values[it.Key]; ok {
				pi.DefaultIndex = v.(int)
			}
			pi.Options = it.Options.Pick(lang)
		default: // toggle
			pi.Default = it.Default
			if v, ok := values[it.Key]; ok {
				pi.Default = v.(bool)
			}
		}
		out.Items = append(out.Items, pi)
	}
	return out
}

func (s *Service) SetPrivacy(userID, key string, value any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, it := range s.privacy.Items {
		if it.Key != key {
			continue
		}
		if it.Kind == "segment" {
			v, ok := value.(int)
			if !ok || v < 0 || v >= len(it.Options.Zh) {
				return ErrUnknownKey
			}
		} else {
			if _, ok := value.(bool); !ok {
				return ErrUnknownKey
			}
		}
		s.stateLocked(userID).Privacy[key] = value
		return s.saveLocked(userID)
	}
	return ErrUnknownKey
}

// Teen 返回按 lang 本地化的青少年模式设置。
func (s *Service) Teen(lang string) TeenPrefs {
	return s.TeenFor("", lang)
}
func (s *Service) TeenFor(userID, lang string) TeenPrefs {
	s.mu.Lock()
	enabled := s.stateLocked(userID).TeenEnabled
	s.mu.Unlock()
	lang = normalizeLang(lang)
	return TeenPrefs{
		DefaultEnabled: enabled,
		PinLength:      s.teen.PinLength,
		Title:          s.teen.Title.Pick(lang),
		Description:    s.teen.Description.Pick(lang),
		StateOn:        s.teen.StateOn.Pick(lang),
		StateOff:       s.teen.StateOff.Pick(lang),
		PinLabel:       s.teen.PinLabel.Pick(lang),
		PinPlaceholder: s.teen.PinPlaceholder.Pick(lang),
		Rules:          s.teen.Rules.Pick(lang),
	}
}

func (s *Service) SetTeen(userID string, enabled bool, pin string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	st := s.stateLocked(userID)
	if len(pin) != s.teen.PinLength {
		return ErrInvalidPIN
	}
	hash := sha256.Sum256([]byte(pin))
	// 青少年模式一旦启用,任何改动(关闭 或 重新启用/改 PIN)都必须先验证当前 PIN。
	// 否则可用"重新启用并设新 PIN"覆盖家长设定的 PIN,再用新 PIN 关闭,两步绕过家长控制。
	if st.TeenEnabled && st.PinHash != hash {
		return ErrInvalidPIN
	}
	if enabled {
		st.PinHash = hash
	}
	st.TeenEnabled = enabled
	return s.saveLocked(userID)
}

func inCurfew(now time.Time) bool {
	hour := now.Hour()
	return hour >= TeenCurfewStart || hour < TeenCurfewEnd
}

// GuardPlay rejects play/replay/room actions when teen mode is on and the
// published curfew or daily limit would be violated. extraSeconds is added
// after a successful check so duration accounting lives on the server.
func (s *Service) GuardPlay(userID string, extraSeconds int, now time.Time) error {
	if userID == "" {
		return nil
	}
	if now.IsZero() {
		now = time.Now()
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	st := s.stateLocked(userID)
	if !st.TeenEnabled {
		return nil
	}
	if inCurfew(now) {
		return ErrTeenCurfew
	}
	day := now.Format("2006-01-02")
	dayChanged := st.TeenDay != day
	if dayChanged {
		st.TeenDay = day
		st.TeenPlaySecs = 0
	}
	if extraSeconds < 0 {
		extraSeconds = 0
	}
	if st.TeenPlaySecs >= TeenDailyLimitSecs {
		return ErrTeenLimit
	}
	if extraSeconds == 0 {
		if dayChanged {
			return s.saveLocked(userID)
		}
		return nil
	}
	st.TeenPlaySecs += extraSeconds
	return s.saveLocked(userID)
}

// Blocks 返回按 lang 本地化的黑名单(种子数据)。
// 注:moderation 域只有 POST/DELETE /block/:userId 无列表接口,故此处补 GET /blocks。
func (s *Service) Blocks(lang string) []BlockedUser {
	lang = normalizeLang(lang)
	out := make([]BlockedUser, 0, len(s.blocks.Blocked))
	for _, b := range s.blocks.Blocked {
		out = append(out, BlockedUser{
			UserID:    b.UserID,
			BlockedAt: b.BlockedAt.Pick(lang),
		})
	}
	return out
}
