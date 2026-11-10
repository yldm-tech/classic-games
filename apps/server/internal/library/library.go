// Package library 是「我的库」域:下载管理、最近玩过、正在直播(由 apps/client/features/engagement
// 的 downloads/history 与 catalog explore screen 消费)。
// 本域不持有游戏元数据,只持有「关系」(下载了哪些 id、玩了多久、谁在直播哪款);
// 游戏对象统一经 GameSource 向 catalog 域解析,与发现/榜单复用同一份作品记录,不重复落库。
package library

import (
	"errors"
	"forgeplay/server/internal/games"
	"sync"
)

// 支持的展示语言;未知 lang 兜底 langDefault。游戏标题/简介按语言取本地化种子。
const (
	langZH      = "zh"
	langEN      = "en"
	langJA      = "ja"
	langDefault = langZH
)

// loc 是一段三语文本(标题/简介/直播标语)。Pick 按 lang 取,未知兜底中文。
type loc struct {
	zh, en, ja string
}

func (l loc) pick(lang string) string {
	switch lang {
	case langEN:
		return l.en
	case langJA:
		return l.ja
	default:
		return l.zh
	}
}

// titles/summaries 是各游戏 id 的三语本地化种子(取自 apps/client/i18n/strings.gd game_title/desc)。
// games 域当前不存本地化文本,故本地化在展示层(本域)完成;games.Game 只提供结构记录。
var titles = map[string]loc{
	"ember":   {zh: "余烬漂移", en: "Ember Drift", ja: "エンバー・ドリフト"},
	"volt":    {zh: "电光狂奔", en: "Volt Runner", ja: "ボルト・ランナー"},
	"foundry": {zh: "熔炉战棋", en: "Foundry Tactics", ja: "ファウンドリ戦術"},
	"null":    {zh: "幽灵港湾", en: "Null Harbor", ja: "ヌル・ハーバー"},
	"cinder":  {zh: "屋顶高尔夫", en: "Cinder Golf", ja: "シンダー・ゴルフ"},
	"ash":     {zh: "灰烬花园", en: "Ash Garden", ja: "灰の庭"},
	"magma":   {zh: "熔岩迷宫", en: "Magma Maze", ja: "マグマ・メイズ"},
	"echo":    {zh: "回声潮汐", en: "Echo Tide", ja: "エコー・タイド"},
}

var summaries = map[string]loc{
	"ember":   {zh: "在熔岩赛道上漂移冲浪,身后的路一路塌掉。", en: "Surf a melting lava track that collapses behind you.", ja: "溶けて崩れていく溶岩トラックをサーフィン。"},
	"volt":    {zh: "霓虹变电站里的无尽跑酷。", en: "An endless sprint through a neon substation.", ja: "ネオン変電所を駆け抜けるエンドレスラン。"},
	"foundry": {zh: "在渐渐冷却的铸造车间里排兵布阵。", en: "Squad tactics on a cooling forge floor.", ja: "冷えゆく鍛造場での分隊戦術。"},
	"null":    {zh: "重新接线潮汐机器,引幽灵船进港。", en: "Dock ghost ships by rewiring tide machines.", ja: "潮汐マシンを配線し直して幽霊船を接岸。"},
	"cinder":  {zh: "在厂房屋顶之间打迷你高尔夫。", en: "Mini-golf across factory rooftops.", ja: "工場の屋上を渡るミニゴルフ。"},
	"ash":     {zh: "在火山灰里种花。", en: "Grow a garden in volcanic soil.", ja: "火山性の土に庭を育てる。"},
	"magma":   {zh: "一座每 30 秒就把自己重新熔一遍的迷宫。", en: "A maze that re-melts itself every 30 seconds.", ja: "30 秒ごとに自らを溶かし直す迷路。"},
	"echo":    {zh: "踩着声呐波前进 —— 雷达照到哪,关卡就长到哪。", en: "Ride sonar waves; the level is whatever the ping reveals.", ja: "ソナー波に乗れ。ピングが映し出すものこそがレベルだ。"},
}

// seedGames 是要灌进 games 域的作品(id 取自 client Catalog;by=作者句柄,cat→tag)。
// MemRepo 自分配 game_N 真实 id,故灌完记下「client id → 真实 id」映射,关系按真实 id 引用。
var seedGames = []struct {
	clientID string
	author   string
	cat      string
}{
	{"ember", "@koru", "Racing"},
	{"volt", "@mei", "Arcade"},
	{"foundry", "@arc", "Strategy"},
	{"null", "@jin", "Puzzle"},
	{"cinder", "@koru", "Arcade"},
	{"ash", "@yuna", "Puzzle"},
	{"magma", "@bo", "Puzzle"},
	{"echo", "@ana", "Arcade"},
}

// ResolvedGame 是解析+本地化后的游戏摘要(供库各列表内嵌)。
type ResolvedGame struct {
	ID       string   `json:"id"`
	AuthorID string   `json:"author_id"`
	Title    string   `json:"title"`
	Summary  string   `json:"summary"`
	Tags     []string `json:"tags,omitempty"`
}

// DownloadItem 是一条下载记录:已下游戏 + 包体大小 + 是否有更新。
type DownloadItem struct {
	Game      ResolvedGame `json:"game"`
	SizeMB    int          `json:"size_mb"`
	HasUpdate bool         `json:"has_update"`
}

// HistoryItem 是一条游玩记录:玩过的游戏 + 时长(分钟)。
type HistoryItem struct {
	Game          ResolvedGame `json:"game"`
	MinutesPlayed int          `json:"minutes_played"`
}

// HistoryGroup 是按时间分组的游玩记录(今天/昨天/更早)。
type HistoryGroup struct {
	Group string        `json:"group"` // today / yesterday / earlier
	Items []HistoryItem `json:"items"`
}

// LiveItem 是一路直播:被直播的游戏 + 主播 + 在看人数 + 本地化标语。
type LiveItem struct {
	Game     ResolvedGame `json:"game"`
	Streamer string       `json:"streamer"`
	Viewers  int          `json:"viewers"`
	Title    string       `json:"title"` // 直播标语,本域自带本地化
}

// 关系种子(均按 client id;NewService 灌库后改写为真实 id)。

type downloadRel struct {
	clientID  string
	sizeMB    int
	hasUpdate bool
}

type historyRel struct {
	clientID      string
	minutesPlayed int
}

type liveRel struct {
	clientID string
	streamer string
	viewers  int
	title    loc
}

// GameSource is the narrow catalog port required by the library domain.
type GameSource interface {
	EnsureSeeds() error
	Get(string) (games.Game, error)
	IncrementPlays(string) error
}

// Service 解析库关系到本地化游戏。依赖 GameSource 取作品记录(与发现/榜单同源)。
type Service struct {
	mu            sync.Mutex
	games         GameSource
	idMap         map[string]string // client id → games 域真实 id
	downloads     []downloadRel
	history       [][]historyRel // 下标 0/1/2 = 今天/昨天/更早
	live          []liveRel
	userDownloads map[string][]downloadRel
	userHistory   map[string][][]historyRel
	store         StateStore
	onPlay        func(string, string, int) error
	playGuard     func(string, int) error
}

func (s *Service) SetPlayRecorder(f func(string, string, int) error) { s.onPlay = f }
func (s *Service) SetPlayGuard(f func(string, int) error)            { s.playGuard = f }

var ErrNotFound = errors.New("library: item not found")

// NewService 灌入 client 种子作品到 games 域,记录 id 映射,并播种库关系。
// 关系内部统一用 games 域真实 id,确保 Downloads/History/Live 经 GameSource.Get 命中。
func NewService(g GameSource) *Service {
	s, _ := newService(g, nil)
	return s
}
func NewServiceWithStore(g GameSource, store StateStore) (*Service, error) {
	return newService(g, store)
}
func newService(g GameSource, store StateStore) (*Service, error) {
	if err := g.EnsureSeeds(); err != nil {
		return nil, err
	}
	idMap := make(map[string]string, len(seedGames))
	for _, sg := range seedGames {
		if _, err := g.Get(sg.clientID); err == nil {
			idMap[sg.clientID] = sg.clientID
		}
	}

	s := &Service{
		games: g,
		idMap: idMap,
		downloads: []downloadRel{
			{clientID: "ember", sizeMB: 86, hasUpdate: false},
			{clientID: "cinder", sizeMB: 64, hasUpdate: true},
			{clientID: "magma", sizeMB: 48, hasUpdate: false},
		},
		history: [][]historyRel{
			{{clientID: "ember", minutesPlayed: 36}, {clientID: "magma", minutesPlayed: 12}},
			{{clientID: "cinder", minutesPlayed: 24}},
			{{clientID: "null", minutesPlayed: 45}, {clientID: "echo", minutesPlayed: 8}},
		},
		live: []liveRel{
			{clientID: "ember", streamer: "@mei", viewers: 1342, title: loc{
				zh: "冲周榜第 1,来抄作业",
				en: "Chasing weekly #1 — copy my lines",
				ja: "週間1位を狙う — ライン参考にどうぞ",
			}},
			{clientID: "magma", streamer: "@bo", viewers: 286, title: loc{
				zh: "《熔岩迷宫》速通练习",
				en: "Magma Maze speedrun practice",
				ja: "『マグマ・メイズ』RTA練習",
			}},
		},
		userDownloads: map[string][]downloadRel{}, userHistory: map[string][][]historyRel{},
		store: store,
	}
	if store != nil {
		rows, e := store.LoadAll()
		if e != nil {
			return nil, e
		}
		for _, row := range rows {
			for _, v := range row.State.Downloads {
				s.userDownloads[row.UserID] = append(s.userDownloads[row.UserID], downloadRel{clientID: v.ClientID, sizeMB: v.SizeMB, hasUpdate: v.HasUpdate})
			}
			hist := make([][]historyRel, len(row.State.History))
			for i, g := range row.State.History {
				for _, v := range g {
					hist[i] = append(hist[i], historyRel{clientID: v.ClientID, minutesPlayed: v.MinutesPlayed})
				}
			}
			s.userHistory[row.UserID] = hist
		}
	}
	return s, nil
}

func (s *Service) saveLocked(uid string) error {
	if s.store == nil {
		return nil
	}
	v := savedLibrary{}
	for _, d := range s.userDownloads[uid] {
		v.Downloads = append(v.Downloads, savedDownload{d.clientID, d.sizeMB, d.hasUpdate})
	}
	for _, group := range s.userHistory[uid] {
		var out []savedHistory
		for _, h := range group {
			out = append(out, savedHistory{h.clientID, h.minutesPlayed})
		}
		v.History = append(v.History, out)
	}
	return s.store.Save(libraryStateRow{UserID: uid, State: v})
}

func normLang(lang string) string {
	switch lang {
	case langZH, langEN, langJA:
		return lang
	default:
		return langDefault
	}
}

// resolve 把 client id 解析为本地化游戏摘要。games 域查不到时返回 false(关系被跳过)。
func (s *Service) resolve(clientID, lang string) (ResolvedGame, bool) {
	realID, ok := s.idMap[clientID]
	if !ok {
		realID = clientID
	}
	g, err := s.games.Get(realID)
	if err != nil {
		return ResolvedGame{}, false
	}
	g = g.Localized(lang)
	return ResolvedGame{
		ID:       g.ID,
		AuthorID: g.AuthorID,
		Title:    g.Title,
		Summary:  g.Summary,
		Tags:     g.Tags,
	}, true
}

func (s *Service) RecordPlay(userID, gameID string, durationMS int) error {
	if userID == "" || durationMS < 0 {
		return ErrNotFound
	}
	if _, err := s.games.Get(gameID); err != nil {
		return ErrNotFound
	}
	if s.playGuard != nil {
		extra := durationMS / 1000
		if extra < 1 {
			extra = 1
		}
		if err := s.playGuard(userID, extra); err != nil {
			return err
		}
	}
	minutes := (durationMS + 59999) / 60000
	if minutes < 1 {
		minutes = 1
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	groups := s.historyForLocked(userID)
	if len(groups) < 3 {
		groups = [][]historyRel{{}, {}, {}}
	}
	found := -1
	for i, row := range groups[0] {
		if row.clientID == gameID {
			found = i
			break
		}
	}
	if found >= 0 {
		row := groups[0][found]
		row.minutesPlayed += minutes
		groups[0] = append([]historyRel{row}, append(groups[0][:found], groups[0][found+1:]...)...)
	} else {
		groups[0] = append([]historyRel{{clientID: gameID, minutesPlayed: minutes}}, groups[0]...)
	}
	s.userHistory[userID] = groups
	if err := s.saveLocked(userID); err != nil {
		return err
	}
	if err := s.games.IncrementPlays(gameID); err != nil {
		return err
	}
	if s.onPlay != nil {
		game, _ := s.games.Get(gameID)
		_ = s.onPlay(userID, gameID, game.Plays)
	}
	return nil
}

// Downloads 返回已下载游戏(解析+本地化)。
func (s *Service) Downloads(lang string) []DownloadItem {
	return s.DownloadsFor("", lang)
}

func (s *Service) DownloadsFor(userID, lang string) []DownloadItem {
	s.mu.Lock()
	defer s.mu.Unlock()
	lang = normLang(lang)
	rels := s.downloadsForLocked(userID)
	out := make([]DownloadItem, 0, len(rels))
	for _, d := range rels {
		game, ok := s.resolve(d.clientID, lang)
		if !ok {
			continue
		}
		out = append(out, DownloadItem{Game: game, SizeMB: d.sizeMB, HasUpdate: d.hasUpdate})
	}
	return out
}

func (s *Service) downloadsForLocked(userID string) []downloadRel {
	if userID == "" {
		return s.downloads
	}
	if rows, ok := s.userDownloads[userID]; ok {
		return rows
	}
	// 新用户从空列表开始,不继承匿名态的种子下载(与 historyForLocked 的空态一致);
	// s.downloads 只服务未登录预览。
	rows := []downloadRel{}
	s.userDownloads[userID] = rows
	return rows
}

func (s *Service) MarkDownloadUpdated(userID, gameID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	rows := s.downloadsForLocked(userID)
	for i := range rows {
		if s.idMap[rows[i].clientID] == gameID {
			rows[i].hasUpdate = false
			s.userDownloads[userID] = rows
			return s.saveLocked(userID)
		}
	}
	return ErrNotFound
}

func (s *Service) RemoveDownload(userID, gameID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	rows := s.downloadsForLocked(userID)
	for i := range rows {
		if s.idMap[rows[i].clientID] == gameID {
			rows = append(rows[:i], rows[i+1:]...)
			s.userDownloads[userID] = rows
			return s.saveLocked(userID)
		}
	}
	return ErrNotFound
}

// History 返回分组游玩记录(今天/昨天/更早)。空组也保留,前端据此渲染分组标题。
func (s *Service) History(lang string) []HistoryGroup {
	return s.HistoryFor("", lang)
}

func (s *Service) HistoryFor(userID, lang string) []HistoryGroup {
	s.mu.Lock()
	defer s.mu.Unlock()
	lang = normLang(lang)
	names := []string{"today", "yesterday", "earlier"}
	rels := s.historyForLocked(userID)
	out := make([]HistoryGroup, 0, len(rels))
	for gi, group := range rels {
		items := make([]HistoryItem, 0, len(group))
		for _, h := range group {
			game, ok := s.resolve(h.clientID, lang)
			if !ok {
				continue
			}
			items = append(items, HistoryItem{Game: game, MinutesPlayed: h.minutesPlayed})
		}
		name := "earlier"
		if gi < len(names) {
			name = names[gi]
		}
		out = append(out, HistoryGroup{Group: name, Items: items})
	}
	return out
}

func (s *Service) historyForLocked(userID string) [][]historyRel {
	if userID == "" {
		return s.history
	}
	if rows, ok := s.userHistory[userID]; ok {
		return rows
	}
	rows := [][]historyRel{{}, {}, {}}
	s.userHistory[userID] = rows
	return rows
}

func (s *Service) ClearHistory(userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.userHistory[userID] = [][]historyRel{{}, {}, {}}
	return s.saveLocked(userID)
}

// Live 返回正在直播列表(解析+本地化标语)。
func (s *Service) Live(lang string) []LiveItem {
	lang = normLang(lang)
	out := make([]LiveItem, 0, len(s.live))
	for _, lv := range s.live {
		game, ok := s.resolve(lv.clientID, lang)
		if !ok {
			continue
		}
		out = append(out, LiveItem{
			Game:     game,
			Streamer: lv.streamer,
			Viewers:  lv.viewers,
			Title:    lv.title.pick(lang),
		})
	}
	return out
}

func (s *Service) LiveFor(userID, lang string) []LiveItem {
	if userID != "" {
		return []LiveItem{}
	}
	return s.Live(lang)
}
