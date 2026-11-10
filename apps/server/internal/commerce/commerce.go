// Package commerce 是消费/福利层：目录从内嵌种子装载，购买、签到、领取与装备
// 按用户隔离维护；用户可见文案三语本地化。
//
// 设计对齐 games:Service 持有内存种子,NewService() 装载;用户可见文本走
// Localized(map[lang]string)+ Pick(lang) 回落,与 games 的标题/简介本地化同理。
package commerce

import (
	"crypto/sha256"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
)

// 支持的语言与默认语言。lang 不在表内或缺该语言时回落到 zh(开发期可见,不空串)。
const (
	LocaleZH      = "zh"
	LocaleEN      = "en"
	LocaleJA      = "ja"
	DefaultLocale = LocaleZH
)

// seedFS 内嵌种子内容。文件即数据源,与 mods 基线、runtimes schema 同思路:
// 开发/测试走内嵌文件,生产可换 DB 来源而不动 transport。
//
//go:embed seed/*.json
var seedFS embed.FS

// Localized 是一段用户可见文案的三语映射(zh/en/ja)。Pick 按 lang 取值并回落 zh,
// 复用 games 标题/简介那套「map[string]string + 回落」的本地化方式。
type Localized map[string]string

// Pick 取指定语言的文案;缺该语言时回落默认语言;再缺则返回空串。
func (l Localized) Pick(lang string) string {
	if v, ok := l[lang]; ok && v != "" {
		return v
	}
	if v, ok := l[DefaultLocale]; ok {
		return v
	}
	return ""
}

// normalizeLang 把入参收敛到受支持的语言集合,未知值回落默认(系统边界容错)。
func normalizeLang(lang string) string {
	switch lang {
	case LocaleZH, LocaleEN, LocaleJA:
		return lang
	default:
		return DefaultLocale
	}
}

// ---- 种子结构(内嵌 JSON 反序列化目标;文本字段为 Localized) ----

// Points 创作点:余额 + 收支流水 + 收益中心(累计/近 7 天/分成流水)。
type Points struct {
	Balance  int            `json:"balance"`
	Ledger   []LedgerEntry  `json:"ledger"`
	Earnings EarningsDetail `json:"earnings"`
}

// LedgerEntry 一条创作点流水。amount 正为收入、负为支出;label/when 本地化。
type LedgerEntry struct {
	Label  Localized `json:"label"`
	Amount int       `json:"amount"`
	When   Localized `json:"when"`
}

// EarningsDetail 收益中心:累计收益、近 7 天柱状、分成流水。
type EarningsDetail struct {
	Total  int           `json:"total"`
	Weekly []int         `json:"weekly"`
	Ledger []LedgerEntry `json:"ledger"`
}

// Shop 商城:皮肤(创作点兑换)、道具、充值档。
type Shop struct {
	Skins        []ShopSkin     `json:"skins"`
	Items        []ShopItem     `json:"items"`
	Recharge     []RechargeTier `json:"recharge"`
	CurrencyUnit Localized      `json:"currency_unit"` // 法币符号(¥ / $)
	RechargeUnit Localized      `json:"recharge_unit"` // 充值得到的「创作点」单位名
}

type ShopSkin struct {
	ID    string    `json:"id"`
	Name  Localized `json:"name"`
	Price int       `json:"price"` // 创作点价(不本地化)
	Tone  string    `json:"tone"`
}

type ShopItem struct {
	ID    string    `json:"id"`
	Name  Localized `json:"name"`
	Price int       `json:"price"`
}

// RechargeTier 一档充值:得到 points 创作点,法币定价 price(各地区不同,故本地化字符串)。
type RechargeTier struct {
	ID     string    `json:"id"`
	Points int       `json:"points"`
	Price  Localized `json:"price"`
}

// Membership 会员 ForgePlay+:权益清单 + 月卡/年卡。
type Membership struct {
	Badge   string           `json:"badge"`
	Tagline Localized        `json:"tagline"`
	Note    Localized        `json:"note"`
	Perks   []Localized      `json:"perks"`
	Plans   []MembershipPlan `json:"plans"`
}

type MembershipPlan struct {
	ID     string    `json:"id"`
	Name   Localized `json:"name"`
	Price  Localized `json:"price"`  // 含法币符号的展示价
	Period Localized `json:"period"` // /月 · /mo · /月
	Badge  Localized `json:"badge"`  // 促销角标,可空
}

// Welfare 福利中心:7 天签到、今日任务、邀请。
type Welfare struct {
	Checkin Checkin `json:"checkin"`
	Quests  []Quest `json:"quests"`
	Invite  Invite  `json:"invite"`
}

// Checkin 签到:已连签天数 + 7 天递增奖励(创作点,不本地化)。
type Checkin struct {
	Streak  int   `json:"streak"`
	Rewards []int `json:"rewards"`
	Checked bool  `json:"checked,omitempty"`
}

// Quest 今日任务:进度 progress/target,达成可领 reward 创作点。
type Quest struct {
	ID       string    `json:"id"`
	Title    Localized `json:"title"`
	Progress int       `json:"progress"`
	Target   int       `json:"target"`
	Reward   int       `json:"reward"`
}

type Invite struct {
	Code  string    `json:"code"`
	Title Localized `json:"title"`
	Desc  Localized `json:"desc"`
}

// Event 限时活动:标题/简介本地化,ends_in 为本地化的剩余时长展示串。
type Event struct {
	ID     string    `json:"id"`
	Title  Localized `json:"title"`
	Desc   Localized `json:"desc"`
	EndsIn Localized `json:"ends_in"`
	Tone   string    `json:"tone"`
}

// Achievement 成就:名称/描述本地化,进度 progress/target,达成可领 reward。
type Achievement struct {
	ID       string    `json:"id"`
	Name     Localized `json:"name"`
	Desc     Localized `json:"desc"`
	Progress int       `json:"progress"`
	Target   int       `json:"target"`
	Reward   int       `json:"reward"`
}

// AvatarCatalog 形象装扮目录:角色/座驾/特效三类。
type AvatarCatalog struct {
	Categories []AvatarCategory `json:"categories"`
}

type AvatarCategory struct {
	ID    string       `json:"id"`
	Name  Localized    `json:"name"`
	Items []AvatarItem `json:"items"`
}

type AvatarItem struct {
	ID    string    `json:"id"`
	Name  Localized `json:"name"`
	Tone  string    `json:"tone"`
	Owned bool      `json:"owned"`
}

// ---- 已解析(本地化后)的对外 DTO:文本被压平为按 lang 取出的纯字符串 ----

type LedgerEntryView struct {
	Label  string `json:"label"`
	Amount int    `json:"amount"`
	When   string `json:"when"`
}

type PointsView struct {
	Balance  int                `json:"balance"`
	Ledger   []LedgerEntryView  `json:"ledger"`
	Earnings EarningsDetailView `json:"earnings"`
}

type EarningsDetailView struct {
	Total  int               `json:"total"`
	Weekly []int             `json:"weekly"`
	Ledger []LedgerEntryView `json:"ledger"`
}

type ShopSkinView struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Price int    `json:"price"`
	Tone  string `json:"tone"`
	Owned bool   `json:"owned"`
}

type ShopItemView struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Price int    `json:"price"`
	Owned bool   `json:"owned"`
}

type RechargeTierView struct {
	ID     string `json:"id"`
	Points int    `json:"points"`
	Price  string `json:"price"`
}

type ShopView struct {
	Skins        []ShopSkinView     `json:"skins"`
	Items        []ShopItemView     `json:"items"`
	Recharge     []RechargeTierView `json:"recharge"`
	CurrencyUnit string             `json:"currency_unit"`
	RechargeUnit string             `json:"recharge_unit"`
}

type MembershipPlanView struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Price  string `json:"price"`
	Period string `json:"period"`
	Badge  string `json:"badge"`
}

type MembershipView struct {
	Active  bool                 `json:"active"`
	Badge   string               `json:"badge"`
	Tagline string               `json:"tagline"`
	Note    string               `json:"note"`
	Perks   []string             `json:"perks"`
	Plans   []MembershipPlanView `json:"plans"`
}

type QuestView struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Progress int    `json:"progress"`
	Target   int    `json:"target"`
	Reward   int    `json:"reward"`
	Claimed  bool   `json:"claimed"`
}

type InviteView struct {
	Code  string `json:"code"`
	Title string `json:"title"`
	Desc  string `json:"desc"`
}

type WelfareView struct {
	Checkin Checkin     `json:"checkin"`
	Quests  []QuestView `json:"quests"`
	Invite  InviteView  `json:"invite"`
}

type EventView struct {
	ID     string `json:"id"`
	Title  string `json:"title"`
	Desc   string `json:"desc"`
	EndsIn string `json:"ends_in"`
	Tone   string `json:"tone"`
}

type AchievementView struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Desc     string `json:"desc"`
	Progress int    `json:"progress"`
	Target   int    `json:"target"`
	Reward   int    `json:"reward"`
	Claimed  bool   `json:"claimed"`
}

type AvatarItemView struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Tone     string `json:"tone"`
	Owned    bool   `json:"owned"`
	Equipped bool   `json:"equipped"`
}

type AvatarCategoryView struct {
	ID    string           `json:"id"`
	Name  string           `json:"name"`
	Items []AvatarItemView `json:"items"`
}

// ---- Service:内存种子 + 按语言解析 ----

// Service 持有只读目录和按用户隔离的可写权益状态。
type Service struct {
	mu           sync.Mutex
	points       Points
	shop         Shop
	membership   Membership
	welfare      Welfare
	events       []Event
	achievements []Achievement
	avatar       AvatarCatalog
	users        map[string]*userState
	store        StateStore
}

type userState struct {
	Balance         int
	Ledger          []LedgerEntry
	Earnings        EarningsDetail
	Owned           map[string]bool
	Checked         bool
	Streak          int
	LastCheckinDay  string
	Quests          map[string]bool
	Achievements    map[string]bool
	Progress        map[string]int
	PlayedGames     map[string]bool
	QuestDay        string
	Equipped        map[string]string
	Member          bool
	AppliedPayments map[string]bool
}

func (s *Service) ApplyPayment(orderID, userID, kind string, value int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return err
	}
	if st.AppliedPayments == nil {
		st.AppliedPayments = map[string]bool{}
	}
	if st.AppliedPayments[orderID] {
		return nil
	}
	// 快照用于持久化失败时回滚。关键:幂等标记不能在未落库时留存——否则 webhook 重试会命中
	// AppliedPayments 短路、永不补记,而订单已被 MarkPaid,导致真金到账却在重启后丢失(内存领先存储)。
	prevBalance, prevLedger, prevMember := st.Balance, st.Ledger, st.Member
	switch {
	case kind == "points" && value > 0:
		st.Balance += value
		recordLedger(st, "支付到账", value)
	case kind == "membership":
		st.Member = true
	default:
		return ErrItemNotFound
	}
	st.AppliedPayments[orderID] = true
	if err := s.persistLocked(userID, st); err != nil {
		// 回滚全部内存变更(含幂等标记),使失败的支付可被 provider 重试并真正落库。
		st.Balance, st.Ledger, st.Member = prevBalance, prevLedger, prevMember
		delete(st.AppliedPayments, orderID)
		return err
	}
	return nil
}

func (s *Service) CreditPoints(userID string, amount int) error {
	if amount <= 0 {
		return ErrItemNotFound
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return err
	}
	st.Balance += amount
	recordLedger(st, "创作收益", amount)
	recordEarning(st, amount)
	return s.persistLocked(userID, st)
}
func (s *Service) ActivateMembership(userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return err
	}
	st.Member = true
	return s.persistLocked(userID, st)
}

var ErrInsufficientPoints = errors.New("commerce: insufficient points")
var ErrItemNotFound = errors.New("commerce: item not found")
var ErrAlreadyClaimed = errors.New("commerce: already claimed")
var ErrNotEarned = errors.New("commerce: reward not earned")

// NewService 从内嵌 JSON 装载全部种子。种子缺失/损坏属构建期错误,直接返回 error,
// 由调用方(main 装配)决定是否 fatal,而非静默起一个空服务。
func NewService() (*Service, error) {
	s := &Service{users: map[string]*userState{}}
	if err := loadSeed("seed/points.json", &s.points); err != nil {
		return nil, err
	}
	if err := loadSeed("seed/shop.json", &s.shop); err != nil {
		return nil, err
	}
	if err := loadSeed("seed/membership.json", &s.membership); err != nil {
		return nil, err
	}
	if err := loadSeed("seed/welfare.json", &s.welfare); err != nil {
		return nil, err
	}
	var ev struct {
		Events []Event `json:"events"`
	}
	if err := loadSeed("seed/events.json", &ev); err != nil {
		return nil, err
	}
	s.events = ev.Events
	var ach struct {
		Achievements []Achievement `json:"achievements"`
	}
	if err := loadSeed("seed/achievements.json", &ach); err != nil {
		return nil, err
	}
	s.achievements = ach.Achievements
	if err := loadSeed("seed/avatar.json", &s.avatar); err != nil {
		return nil, err
	}
	return s, nil
}

func NewServiceWithStore(store StateStore) (*Service, error) {
	s, err := NewService()
	if err != nil {
		return nil, err
	}
	s.store = store
	return s, nil
}

// loadSeed 读取并反序列化一个内嵌种子文件到 dst。
func loadSeed(name string, dst any) error {
	data, err := seedFS.ReadFile(name)
	if err != nil {
		return fmt.Errorf("commerce: 读取种子 %s 失败: %w", name, err)
	}
	if err := json.Unmarshal(data, dst); err != nil {
		return fmt.Errorf("commerce: 解析种子 %s 失败: %w", name, err)
	}
	return nil
}

// ---- 按语言解析:把内部 Localized 压平为对外 *View ----

func (s *Service) Points(lang string) PointsView {
	return s.PointsFor("", lang)
}

func (s *Service) PointsFor(userID, lang string) PointsView {
	s.mu.Lock()
	st := s.viewStateLocked(userID)
	balance := st.Balance
	ledger := s.points.Ledger
	earnings := s.points.Earnings
	if userID != "" {
		ledger = append([]LedgerEntry(nil), st.Ledger...)
		earnings = st.Earnings
		if earnings.Weekly == nil {
			earnings.Weekly = []int{0, 0, 0, 0, 0, 0, 0}
		}
	}
	s.mu.Unlock()
	lang = normalizeLang(lang)
	return PointsView{
		Balance:  balance,
		Ledger:   ledgerView(ledger, lang),
		Earnings: EarningsDetailView{Total: earnings.Total, Weekly: earnings.Weekly, Ledger: ledgerView(earnings.Ledger, lang)},
	}
}

func recordLedger(st *userState, label string, amount int) {
	text := Localized{"zh": label, "en": label, "ja": label}
	st.Ledger = append([]LedgerEntry{{Label: text, Amount: amount, When: Localized{"zh": "刚刚", "en": "now", "ja": "たった今"}}}, st.Ledger...)
}

func recordEarning(st *userState, amount int) {
	if len(st.Earnings.Weekly) != 7 {
		st.Earnings.Weekly = []int{0, 0, 0, 0, 0, 0, 0}
	}
	st.Earnings.Total += amount
	st.Earnings.Weekly[6] += amount
	entry := LedgerEntry{Label: Localized{"zh": "创作收益", "en": "Creator earnings", "ja": "クリエイター収益"}, Amount: amount, When: Localized{"zh": "刚刚", "en": "now", "ja": "たった今"}}
	st.Earnings.Ledger = append([]LedgerEntry{entry}, st.Earnings.Ledger...)
}

func (s *Service) RecordAction(userID, action, targetID string, value int) error {
	if userID == "" {
		return ErrItemNotFound
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return err
	}
	ensureDaily(st)
	switch action {
	case "play":
		if targetID != "" {
			st.PlayedGames[targetID] = true
		}
		st.Progress["quest_play_3"] = len(st.PlayedGames)
	case "comment":
		st.Progress["quest_comment_1"]++
	case "remix":
		st.Progress["quest_remix_1"]++
		st.Progress["ach_remix_pro"]++
	case "publish":
		st.Progress["ach_first_launch"] = 1
	case "friend":
		st.Progress["ach_social_butterfly"]++
	case "score":
		if value > st.Progress["ach_touch_master"] {
			st.Progress["ach_touch_master"] = value
		}
	case "game_plays":
		if value > st.Progress["ach_crowd_puller"] {
			st.Progress["ach_crowd_puller"] = value
		}
	case "weekly_top10":
		st.Progress["ach_weekly_top10"] = 1
	default:
		return ErrItemNotFound
	}
	return s.persistLocked(userID, st)
}

func ensureDaily(st *userState) {
	today := time.Now().UTC().Format("2006-01-02")
	if st.QuestDay == today {
		return
	}
	st.QuestDay = today
	st.Quests = map[string]bool{}
	st.PlayedGames = map[string]bool{}
	for key := range st.Progress {
		if strings.HasPrefix(key, "quest_") {
			delete(st.Progress, key)
		}
	}
}

// ensureMaps initialises every map on a state so callers can write into it without a nil check. A state decoded from
// an older stored blob may be missing any of them.
func ensureMaps(st *userState) {
	if st.Owned == nil {
		st.Owned = map[string]bool{}
	}
	if st.Quests == nil {
		st.Quests = map[string]bool{}
	}
	if st.Achievements == nil {
		st.Achievements = map[string]bool{}
	}
	if st.Progress == nil {
		st.Progress = map[string]int{}
	}
	if st.PlayedGames == nil {
		st.PlayedGames = map[string]bool{}
	}
	if st.Equipped == nil {
		st.Equipped = map[string]string{}
	}
	if st.AppliedPayments == nil {
		st.AppliedPayments = map[string]bool{}
	}
}

// stateLocked returns the caller's authoritative wallet state, loading it from the store on first use.
//
// A store read that fails is reported, never defaulted. Treating an unreadable row as "new user" would hand the caller
// a zero wallet, and because that state is cached for the life of the process and persisted with a full-row write, the
// next mutation would overwrite the user's real balance, membership, owned items and — most damagingly — the
// AppliedPayments keys that make payment webhooks idempotent. The store already separates "not found" (nil, nil) from
// a genuine failure (nil, err); this is the layer that has to respect that distinction.
func (s *Service) stateLocked(userID string) (*userState, error) {
	if st := s.users[userID]; st != nil {
		return st, nil
	}
	var st *userState
	if s.store != nil {
		loaded, err := s.store.Load(userID)
		if err != nil {
			// Not cached: the next call retries the store instead of serving this failure forever.
			return nil, err
		}
		st = loaded
	}
	if st == nil {
		st = &userState{}
		// Unauthenticated catalog snapshot may show prototype numbers.
		// Spendable wallets for real user IDs always start at 0.
		if userID == "" {
			st.Balance = s.points.Balance
		}
	}
	ensureMaps(st)
	s.users[userID] = st
	return st, nil
}

// viewStateLocked is the read-only counterpart of stateLocked. The view API has no channel for an error, so an
// unreadable state degrades to an empty snapshot rather than failing the page. That snapshot is deliberately neither
// cached nor persisted, so a later read retries the store and a later mutation still refuses to write over the row.
func (s *Service) viewStateLocked(userID string) *userState {
	st, err := s.stateLocked(userID)
	if err != nil {
		st = &userState{}
		ensureMaps(st)
	}
	return st
}

func (s *Service) persistLocked(userID string, st *userState) error {
	if s.store == nil {
		return nil
	}
	return s.store.Save(userID, st)
}

func (s *Service) Purchase(userID, id string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return 0, err
	}
	price := -1
	for _, v := range s.shop.Skins {
		if v.ID == id {
			price = v.Price
		}
	}
	for _, v := range s.shop.Items {
		if v.ID == id {
			price = v.Price
		}
	}
	if price < 0 {
		return st.Balance, ErrItemNotFound
	}
	if st.Owned[id] {
		return st.Balance, nil
	}
	if st.Balance < price {
		return st.Balance, ErrInsufficientPoints
	}
	st.Balance -= price
	st.Owned[id] = true
	recordLedger(st, "购买 "+id, -price)
	return st.Balance, s.persistLocked(userID, st)
}
func (s *Service) SendLiveGift(userID string, cost int) (int, error) {
	if cost <= 0 {
		return 0, ErrItemNotFound
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return 0, err
	}
	if st.Balance < cost {
		return st.Balance, ErrInsufficientPoints
	}
	st.Balance -= cost
	recordLedger(st, "直播礼物", -cost)
	return st.Balance, s.persistLocked(userID, st)
}
func (s *Service) Checkin(userID string) (int, int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return 0, 0, err
	}
	today := time.Now().UTC().Format("2006-01-02")
	if st.LastCheckinDay == today {
		return st.Balance, 0, ErrAlreadyClaimed
	}
	yesterday := time.Now().UTC().AddDate(0, 0, -1).Format("2006-01-02")
	if st.LastCheckinDay != yesterday {
		st.Streak = 0
	}
	// st.Streak counts consecutive days for the whole lifetime of the account; the reward ladder is a repeating cycle.
	// Clamping the index to the last rung instead of wrapping paid the top reward every day from day 8 onward, which
	// turned the escalating 7-day ladder into an unbounded mint of the most valuable tier.
	reward := 0
	if rungs := len(s.welfare.Checkin.Rewards); rungs > 0 {
		reward = s.welfare.Checkin.Rewards[st.Streak%rungs]
	}
	st.Checked = true
	st.Streak++
	st.LastCheckinDay = today
	st.Balance += reward
	recordLedger(st, "每日签到", reward)
	return st.Balance, reward, s.persistLocked(userID, st)
}
func (s *Service) ClaimQuest(userID, id string) (int, int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return 0, 0, err
	}
	ensureDaily(st)
	for _, q := range s.welfare.Quests {
		if q.ID == id {
			progress := q.Progress
			if userID != "" {
				progress = st.Progress[id]
			}
			if progress < q.Target {
				return st.Balance, 0, ErrNotEarned
			}
			if st.Quests[id] {
				return st.Balance, 0, ErrAlreadyClaimed
			}
			st.Quests[id] = true
			st.Balance += q.Reward
			recordLedger(st, "任务奖励", q.Reward)
			return st.Balance, q.Reward, s.persistLocked(userID, st)
		}
	}
	return st.Balance, 0, ErrItemNotFound
}
func (s *Service) ClaimAchievement(userID, id string) (int, int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return 0, 0, err
	}
	for _, a := range s.achievements {
		if a.ID == id {
			progress := a.Progress
			if userID != "" {
				progress = st.Progress[id]
			}
			if progress < a.Target {
				return st.Balance, 0, ErrNotEarned
			}
			if st.Achievements[id] {
				return st.Balance, 0, ErrAlreadyClaimed
			}
			st.Achievements[id] = true
			st.Balance += a.Reward
			recordLedger(st, "成就奖励", a.Reward)
			return st.Balance, a.Reward, s.persistLocked(userID, st)
		}
	}
	return st.Balance, 0, ErrItemNotFound
}
func (s *Service) Equip(userID, category, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.stateLocked(userID)
	if err != nil {
		return err
	}
	for _, c := range s.avatar.Categories {
		if c.ID == category {
			for _, it := range c.Items {
				if it.ID == id {
					if !it.Owned && !st.Owned[id] {
						return ErrItemNotFound
					}
					st.Equipped[category] = id
					return s.persistLocked(userID, st)
				}
			}
		}
	}
	return ErrItemNotFound
}

func ledgerView(in []LedgerEntry, lang string) []LedgerEntryView {
	out := make([]LedgerEntryView, 0, len(in))
	for _, e := range in {
		out = append(out, LedgerEntryView{Label: e.Label.Pick(lang), Amount: e.Amount, When: e.When.Pick(lang)})
	}
	return out
}

func (s *Service) Shop(lang string) ShopView {
	return s.ShopFor("", lang)
}
func (s *Service) ShopFor(userID, lang string) ShopView {
	s.mu.Lock()
	st := s.viewStateLocked(userID)
	owned := map[string]bool{}
	for k, v := range st.Owned {
		owned[k] = v
	}
	s.mu.Unlock()
	lang = normalizeLang(lang)
	skins := make([]ShopSkinView, 0, len(s.shop.Skins))
	for _, sk := range s.shop.Skins {
		skins = append(skins, ShopSkinView{ID: sk.ID, Name: sk.Name.Pick(lang), Price: sk.Price, Tone: sk.Tone, Owned: owned[sk.ID]})
	}
	items := make([]ShopItemView, 0, len(s.shop.Items))
	for _, it := range s.shop.Items {
		items = append(items, ShopItemView{ID: it.ID, Name: it.Name.Pick(lang), Price: it.Price, Owned: owned[it.ID]})
	}
	tiers := make([]RechargeTierView, 0, len(s.shop.Recharge))
	for _, t := range s.shop.Recharge {
		tiers = append(tiers, RechargeTierView{ID: t.ID, Points: t.Points, Price: t.Price.Pick(lang)})
	}
	return ShopView{
		Skins:        skins,
		Items:        items,
		Recharge:     tiers,
		CurrencyUnit: s.shop.CurrencyUnit.Pick(lang),
		RechargeUnit: s.shop.RechargeUnit.Pick(lang),
	}
}

func (s *Service) Membership(lang string) MembershipView {
	return s.MembershipFor("", lang)
}
func (s *Service) MembershipFor(userID, lang string) MembershipView {
	s.mu.Lock()
	active := s.viewStateLocked(userID).Member
	s.mu.Unlock()
	lang = normalizeLang(lang)
	perks := make([]string, 0, len(s.membership.Perks))
	for _, p := range s.membership.Perks {
		perks = append(perks, p.Pick(lang))
	}
	plans := make([]MembershipPlanView, 0, len(s.membership.Plans))
	for _, p := range s.membership.Plans {
		plans = append(plans, MembershipPlanView{ID: p.ID, Name: p.Name.Pick(lang), Price: p.Price.Pick(lang), Period: p.Period.Pick(lang), Badge: p.Badge.Pick(lang)})
	}
	return MembershipView{
		Active:  active,
		Badge:   s.membership.Badge,
		Tagline: s.membership.Tagline.Pick(lang),
		Note:    s.membership.Note.Pick(lang),
		Perks:   perks,
		Plans:   plans,
	}
}

func (s *Service) Welfare(lang string) WelfareView {
	return s.WelfareFor("", lang)
}
func (s *Service) WelfareFor(userID, lang string) WelfareView {
	s.mu.Lock()
	st := s.viewStateLocked(userID)
	if userID != "" {
		ensureDaily(st)
	}
	checked := st.LastCheckinDay == time.Now().UTC().Format("2006-01-02")
	// Reported as a position within the reward cycle, not as the lifetime streak: the client renders one cell per rung
	// and indexes the reward array with this value, so anything past the last rung would fall out of range.
	streak := st.Streak
	if checked && streak > 0 {
		streak--
	}
	if rungs := len(s.welfare.Checkin.Rewards); rungs > 0 {
		streak %= rungs
	}
	if userID == "" {
		streak = s.welfare.Checkin.Streak
	}
	claimed := map[string]bool{}
	progressByID := map[string]int{}
	for k, v := range st.Quests {
		claimed[k] = v
	}
	for k, v := range st.Progress {
		progressByID[k] = v
	}
	s.mu.Unlock()
	lang = normalizeLang(lang)
	quests := make([]QuestView, 0, len(s.welfare.Quests))
	for _, q := range s.welfare.Quests {
		progress := q.Progress
		if userID != "" {
			progress = progressByID[q.ID]
		}
		quests = append(quests, QuestView{ID: q.ID, Title: q.Title.Pick(lang), Progress: progress, Target: q.Target, Reward: q.Reward, Claimed: claimed[q.ID]})
	}
	inviteCode := s.welfare.Invite.Code
	if userID != "" {
		digest := sha256.Sum256([]byte(userID))
		inviteCode = fmt.Sprintf("FP-%X", digest[:4])
	}
	return WelfareView{
		Checkin: Checkin{Streak: streak, Rewards: s.welfare.Checkin.Rewards, Checked: checked},
		Quests:  quests,
		Invite:  InviteView{Code: inviteCode, Title: s.welfare.Invite.Title.Pick(lang), Desc: s.welfare.Invite.Desc.Pick(lang)},
	}
}

func (s *Service) Events(lang string) []EventView {
	lang = normalizeLang(lang)
	out := make([]EventView, 0, len(s.events))
	for _, e := range s.events {
		out = append(out, EventView{ID: e.ID, Title: e.Title.Pick(lang), Desc: e.Desc.Pick(lang), EndsIn: e.EndsIn.Pick(lang), Tone: e.Tone})
	}
	return out
}

func (s *Service) EventExists(id string) bool {
	for _, e := range s.events {
		if e.ID == id {
			return true
		}
	}
	return false
}
func (s *Service) AvailableEarnings(userID string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if userID == "" {
		return s.points.Earnings.Total
	}
	return s.viewStateLocked(userID).Earnings.Total
}

func (s *Service) Achievements(lang string) []AchievementView {
	return s.AchievementsFor("", lang)
}
func (s *Service) AchievementsFor(userID, lang string) []AchievementView {
	s.mu.Lock()
	st := s.viewStateLocked(userID)
	claimed := map[string]bool{}
	progressByID := map[string]int{}
	for k, v := range st.Achievements {
		claimed[k] = v
	}
	for k, v := range st.Progress {
		progressByID[k] = v
	}
	s.mu.Unlock()
	lang = normalizeLang(lang)
	out := make([]AchievementView, 0, len(s.achievements))
	for _, a := range s.achievements {
		progress := a.Progress
		if userID != "" {
			progress = progressByID[a.ID]
		}
		out = append(out, AchievementView{ID: a.ID, Name: a.Name.Pick(lang), Desc: a.Desc.Pick(lang), Progress: progress, Target: a.Target, Reward: a.Reward, Claimed: claimed[a.ID]})
	}
	return out
}

func (s *Service) Avatar(lang string) []AvatarCategoryView {
	return s.AvatarFor("", lang)
}
func (s *Service) AvatarFor(userID, lang string) []AvatarCategoryView {
	s.mu.Lock()
	st := s.viewStateLocked(userID)
	equipped := map[string]string{}
	owned := map[string]bool{}
	for k, v := range st.Equipped {
		equipped[k] = v
	}
	for k, v := range st.Owned {
		owned[k] = v
	}
	s.mu.Unlock()
	lang = normalizeLang(lang)
	out := make([]AvatarCategoryView, 0, len(s.avatar.Categories))
	for _, c := range s.avatar.Categories {
		items := make([]AvatarItemView, 0, len(c.Items))
		for _, it := range c.Items {
			items = append(items, AvatarItemView{ID: it.ID, Name: it.Name.Pick(lang), Tone: it.Tone, Owned: it.Owned || owned[it.ID], Equipped: equipped[c.ID] == it.ID})
		}
		out = append(out, AvatarCategoryView{ID: c.ID, Name: c.Name.Pick(lang), Items: items})
	}
	return out
}

func btoi(v bool) int {
	if v {
		return 1
	}
	return 0
}
