// Package games 是发布层:把一个 mod(生效 DSL)发布成可被玩/被 Fork 的游戏作品,
// 带审核状态机(docs/10-data-model.md games 表、14-security-compliance.md 审核)。
package games

import (
	"errors"
	"sort"
	"strings"
	"time"

	"github.com/yldm-tech/classic-games/apps/server/pkg/pagex"
)

// Status 是作品审核状态机:reviewing → published / rejected;published → delisted。
type Status string

const (
	StatusReviewing Status = "reviewing"
	StatusPublished Status = "published"
	StatusRejected  Status = "rejected"
	StatusDelisted  Status = "delisted"
)

type Game struct {
	ID          string    `json:"id" gorm:"primaryKey"`
	ModID       string    `json:"mod_id"`
	AuthorID    string    `json:"author_id"`
	By          string    `json:"by"` // 作者展示名(@handle),供客户端卡片直显
	ForkedFrom  string    `json:"forked_from,omitempty"`
	Title       string    `json:"title"`
	Summary     string    `json:"summary"`
	Tags        []string  `json:"tags,omitempty" gorm:"serializer:json"`
	Status      Status    `json:"status" gorm:"index"`
	AIGenerated bool      `json:"ai_generated"`
	Runtime     string    `json:"runtime" gorm:"index"`
	CreatedAt   time.Time `json:"created_at"` // 排序/榜单按时间,而非字典序 ID
	// 客户端卡片展示字段(发布时由 mod/统计填充;种子直接给值)
	Tone     string `json:"tone"`
	Category string `json:"cat"`
	Version  string `json:"ver,omitempty"`
	Plays    int    `json:"plays"`
	Forks    int    `json:"forks"`
	Likes    int    `json:"likes"`
	Views    int    `json:"views" gorm:"-"`
	// 多语言标题/简介(zh/en/ja);按请求 lang 解析进 Title/Summary 再返回。
	TitleI18n   map[string]string `json:"-" gorm:"serializer:json"`
	SummaryI18n map[string]string `json:"-" gorm:"serializer:json"`
}

// Localized 按 lang 把多语言标题/简介解析进 Title/Summary(缺失回退 zh、再回退原值)。
func (g Game) Localized(lang string) Game {
	if v, ok := localePick(g.TitleI18n, lang); ok {
		g.Title = v
	}
	if v, ok := localePick(g.SummaryI18n, lang); ok {
		g.Summary = v
	}
	return g
}

func localePick(m map[string]string, lang string) (string, bool) {
	if m == nil {
		return "", false
	}
	if v, ok := m[lang]; ok && v != "" {
		return v, true
	}
	if v, ok := m["zh"]; ok && v != "" {
		return v, true
	}
	return "", false
}

// LocalizeAll 批量本地化。
func LocalizeAll(gs []Game, lang string) []Game {
	out := make([]Game, len(gs))
	for i, g := range gs {
		out[i] = g.Localized(lang)
	}
	return out
}

type Repository interface {
	Create(g Game) (Game, error)
	Get(id string) (Game, error)
	Update(g Game) error
	// UpdateStatus 原子状态流转:仅当当前状态 == from 时置为 to,返回更新后的 Game。
	// 把前置条件下推到写(UPDATE ... WHERE id=? AND status=?),关掉 Get→check→Update 的 TOCTOU 窗口。
	// 行不存在 → ErrNotFound;状态不匹配(已被并发改过)→ ErrInvalidState。
	UpdateStatus(id string, from, to Status) (Game, error)
	ListByStatus(s Status) ([]Game, error)
	// ListByStatusPage 把分页下推到存储层(LIMIT/OFFSET),避免每页拉全量到内存。
	// hasMore 表示该 offset 之后还有更多(实现内部多取一条判定)。
	ListByStatusPage(s Status, offset, limit int) (items []Game, hasMore bool, err error)
	IncrementPlays(id string) error
	IncrementForks(id string) error
}

var (
	ErrNotFound      = errors.New("games: not found")
	ErrInvalidState  = errors.New("games: 状态不允许此操作")
	ErrTitleRequired = errors.New("games: 标题必填")
	ErrForbidden     = errors.New("games: 无权操作该作品")
	ErrInvalidMod    = errors.New("games: mod 生效 DSL 无效")
)

// LikeCounter 提供作品的实时点赞数(由 social 域实现),用于读接口把展示 Likes 叠成单一真相源。
type LikeCounter interface {
	LikeCount(gameID string) (int, error)
	LikeCounts(gameIDs []string) (map[string]int, error)
}
type HiddenChecker interface {
	IsGameHidden(userID, gameID string) (bool, error)
}

type Service struct {
	repo       Repository
	likes      LikeCounter       // 可空;非空时 /games 读接口用它覆盖展示 Likes(种子基数 + 真实点赞)
	modAI      func(string) bool // 可空;返回某 mod 是否被权威标记为 AI 生成(发布时据此强制 AI 标识)
	hidden     HiddenChecker
	modRuntime func(string) (string, bool)
	modOwner   func(string) (string, bool)
	modValid   func(string) bool
	viewCounts func([]string) (map[string]int, error)
	authorName func(string) string
	onPublish  func(string) error
	onRemix    func(string) error
}

// SetLikeCounter 注入点赞计数源(social),开启 /games 读接口的 Likes 覆盖。
func (s *Service) SetLikeCounter(c LikeCounter)     { s.likes = c }
func (s *Service) SetHiddenChecker(h HiddenChecker) { s.hidden = h }

// SetModProvenance 注入「mod 是否 AI 生成」查询(mods 域),使发布时无法把 AI 创作改成非 AI。
func (s *Service) SetModProvenance(f func(string) bool)        { s.modAI = f }
func (s *Service) SetModRuntime(f func(string) (string, bool)) { s.modRuntime = f }
func (s *Service) SetModOwner(f func(string) (string, bool))   { s.modOwner = f }
func (s *Service) SetModValidator(f func(string) bool)         { s.modValid = f }
func (s *Service) SetViewCounter(f func([]string) (map[string]int, error)) {
	s.viewCounts = f
}
func (s *Service) SetAuthorName(f func(string) string)     { s.authorName = f }
func (s *Service) SetPublishRecorder(f func(string) error) { s.onPublish = f }
func (s *Service) SetRemixRecorder(f func(string) error)   { s.onRemix = f }

func (s *Service) BackfillMissingRuntime() (int, error) {
	if s.modRuntime == nil {
		return 0, nil
	}
	updated := 0
	for _, status := range []Status{StatusReviewing, StatusPublished, StatusRejected, StatusDelisted} {
		items, err := s.repo.ListByStatus(status)
		if err != nil {
			return updated, err
		}
		for _, game := range items {
			if game.Runtime != "" {
				continue
			}
			runtime, ok := s.modRuntime(game.ModID)
			if !ok {
				continue
			}
			game.Runtime = runtime
			if err := s.repo.Update(game); err != nil {
				return updated, err
			}
			updated++
		}
	}
	return updated, nil
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

type PublishRequest struct {
	ModID       string   `json:"mod_id"`
	AuthorID    string   `json:"author_id"`
	ForkedFrom  string   `json:"forked_from"`
	Title       string   `json:"title"`
	Summary     string   `json:"summary"`
	Tags        []string `json:"tags"`
	AIGenerated bool     `json:"ai_generated"`
	Runtime     string   `json:"runtime"`
	Category    string   `json:"category"`
}

// Publish 提交发布:作品进入 reviewing,等审核(docs/14 双重审核)。
func (s *Service) Publish(req PublishRequest) (Game, error) {
	if strings.TrimSpace(req.Title) == "" {
		return Game{}, ErrTitleRequired
	}
	if req.ModID == "" {
		return Game{}, errors.New("games: mod_id 必填")
	}
	if len(req.Tags) > 3 {
		return Game{}, errors.New("games: 标签最多 3 个")
	}
	if s.modOwner != nil {
		owner, ok := s.modOwner(req.ModID)
		if !ok {
			return Game{}, errors.New("games: mod 不存在")
		}
		if req.AuthorID == "" || owner != req.AuthorID {
			return Game{}, ErrForbidden
		}
	}
	if s.modValid != nil && !s.modValid(req.ModID) {
		return Game{}, ErrInvalidMod
	}
	// AI 标识:客户端可自报,但若 mod 被服务端权威标记为 AI 生成(凭签名溯源令牌),则强制为 true,
	// 不可在发布时改成非 AI(防漏标,docs/14)。
	aiGenerated := req.AIGenerated
	if s.modAI != nil && s.modAI(req.ModID) {
		aiGenerated = true
	}
	runtime := req.Runtime
	if s.modRuntime != nil {
		var ok bool
		runtime, ok = s.modRuntime(req.ModID)
		if !ok {
			return Game{}, errors.New("games: mod 不存在")
		}
	}
	by := ""
	if s.authorName != nil {
		by = s.authorName(req.AuthorID)
	}
	if by == "" && req.AuthorID != "" {
		by = "@" + req.AuthorID
	}
	game, err := s.repo.Create(Game{
		ModID:       req.ModID,
		AuthorID:    req.AuthorID,
		By:          by,
		ForkedFrom:  req.ForkedFrom,
		Title:       req.Title,
		Summary:     req.Summary,
		Tags:        req.Tags,
		Status:      StatusReviewing,
		AIGenerated: aiGenerated,
		Runtime:     runtime,
		Category:    strings.TrimSpace(req.Category),
	})
	if err == nil && s.onPublish != nil {
		_ = s.onPublish(req.AuthorID)
	}
	return game, err
}

func (s *Service) ListPublishedFilteredPage(cursor string, limit int, runtime, category string) ([]Game, string, error) {
	return s.ListPublishedDiscoveryPage(cursor, limit, runtime, category, "new")
}

func (s *Service) ListPublishedDiscoveryPage(cursor string, limit int, runtime, category, order string) ([]Game, string, error) {
	return s.ListPublishedQueryPage(cursor, limit, runtime, category, order, "", nil)
}

func (s *Service) ListPublishedQueryPage(cursor string, limit int, runtime, category, order, query string, ai *bool) ([]Game, string, error) {
	offset, err := pagex.Decode(cursor)
	if err != nil {
		return nil, "", err
	}
	limit = pagex.ClampLimit(limit)
	all, err := s.repo.ListByStatus(StatusPublished)
	if err != nil {
		return nil, "", err
	}
	filtered := make([]Game, 0, len(all))
	// Category is matched case-insensitively, like the free-text query on the line it shares. Nothing normalises the
	// vocabulary on the way in — the seeded catalogue stores "Arcade" while the client sends the chip label lowercased —
	// so an exact comparison made every category filter return an empty list.
	runtime, query = strings.TrimSpace(runtime), strings.ToLower(strings.TrimSpace(query))
	category = strings.ToLower(strings.TrimSpace(category))
	for _, game := range all {
		name := strings.SplitN(game.Runtime, "@", 2)[0]
		if runtime != "" && runtime != game.Runtime && runtime != name {
			continue
		}
		if category != "" && category != strings.ToLower(game.Category) {
			continue
		}
		if ai != nil && game.AIGenerated != *ai {
			continue
		}
		if query != "" {
			haystack := strings.ToLower(game.Title + "\n" + game.Summary + "\n" + game.By + "\n" + strings.Join(game.Tags, " "))
			if !strings.Contains(haystack, query) {
				continue
			}
		}
		filtered = append(filtered, game)
	}
	switch order {
	case "", "new":
	case "hot":
		if s.likes != nil {
			ids := make([]string, len(filtered))
			for i := range filtered {
				ids[i] = filtered[i].ID
			}
			counts, e := s.likes.LikeCounts(ids)
			if e != nil {
				return nil, "", e
			}
			sort.SliceStable(filtered, func(i, j int) bool {
				if counts[filtered[i].ID] != counts[filtered[j].ID] {
					return counts[filtered[i].ID] > counts[filtered[j].ID]
				}
				return filtered[i].ID > filtered[j].ID
			})
		}
	case "rising":
		growth, ok := s.likes.(interface {
			RecentLikeCounts([]string, time.Time) (map[string]int, error)
		})
		if !ok {
			return nil, "", errors.New("games: rising 排序不可用")
		}
		ids := make([]string, len(filtered))
		for i := range filtered {
			ids[i] = filtered[i].ID
		}
		counts, e := growth.RecentLikeCounts(ids, time.Now().Add(-24*time.Hour))
		if e != nil {
			return nil, "", e
		}
		sort.SliceStable(filtered, func(i, j int) bool {
			if counts[filtered[i].ID] != counts[filtered[j].ID] {
				return counts[filtered[i].ID] > counts[filtered[j].ID]
			}
			return filtered[i].ID > filtered[j].ID
		})
	default:
		return nil, "", errors.New("games: sort 只能是 hot|rising|new")
	}
	if offset >= len(filtered) {
		return []Game{}, "", nil
	}
	end := offset + limit
	if end > len(filtered) {
		end = len(filtered)
	}
	next := ""
	if end < len(filtered) {
		next = pagex.Encode(end)
	}
	return filtered[offset:end], next, nil
}

// Decide 审核裁决:reviewing → published / rejected。仅能从 reviewing 流转。
// 流转走 repo.UpdateStatus 原子完成:并发的重复裁决里只有一个成功,其余拿到 ErrInvalidState(409),
// 而非各读到 reviewing 后互相覆盖(lost update)。
func (s *Service) Decide(gameID string, approve bool) (Game, error) {
	to := StatusRejected
	if approve {
		to = StatusPublished
	}
	return s.repo.UpdateStatus(gameID, StatusReviewing, to)
}

// Delist 下架:仅 published 可下架。同样原子流转,避免并发覆盖。
func (s *Service) Delist(gameID string) (Game, error) {
	return s.repo.UpdateStatus(gameID, StatusPublished, StatusDelisted)
}

// DelistByAuthor 只允许作品作者下架，操作者必须来自鉴权上下文。
func (s *Service) DelistByAuthor(gameID, userID string) (Game, error) {
	g, err := s.repo.Get(gameID)
	if err != nil {
		return Game{}, err
	}
	if userID == "" || g.AuthorID != userID {
		return Game{}, ErrForbidden
	}
	return s.repo.UpdateStatus(gameID, StatusPublished, StatusDelisted)
}

// ResubmitByAuthor 允许作者将 rejected 作品重新送审。
func (s *Service) ResubmitByAuthor(gameID, userID string) (Game, error) {
	g, err := s.repo.Get(gameID)
	if err != nil {
		return Game{}, err
	}
	if userID == "" || g.AuthorID != userID {
		return Game{}, ErrForbidden
	}
	return s.repo.UpdateStatus(gameID, StatusRejected, StatusReviewing)
}

func (s *Service) Get(id string) (Game, error)    { return s.repo.Get(id) }
func (s *Service) ListPublished() ([]Game, error) { return s.repo.ListByStatus(StatusPublished) }
func (s *Service) IncrementPlays(id string) error { return s.repo.IncrementPlays(id) }
func (s *Service) IncrementForks(id string) error { return s.repo.IncrementForks(id) }
func (s *Service) EnsureSeeds() error             { return Seed(s.repo) }

// ListMine returns every published/reviewing/rejected/delisted work owned by
// the authenticated author. Draft mods remain in the mods domain.
func (s *Service) ListMine(authorID string) ([]Game, error) {
	if authorID == "" {
		return []Game{}, nil
	}
	var out []Game
	for _, status := range []Status{StatusPublished, StatusReviewing, StatusRejected, StatusDelisted} {
		items, err := s.repo.ListByStatus(status)
		if err != nil {
			return nil, err
		}
		for _, game := range items {
			if game.AuthorID == authorID {
				out = append(out, game)
			}
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if !out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].CreatedAt.After(out[j].CreatedAt)
		}
		return out[i].ID > out[j].ID
	})
	if s.viewCounts != nil && len(out) > 0 {
		ids := make([]string, len(out))
		for i := range out {
			ids[i] = out[i].ID
		}
		counts, err := s.viewCounts(ids)
		if err != nil {
			return nil, err
		}
		for i := range out {
			out[i].Views = counts[out[i].ID]
		}
	}
	return out, nil
}

// ListPublishedPage 游标分页返回已发布作品。返回(该页, nextCursor)。
// 分页下推到存储层,不再每页拉全量(游标当前编码 offset;keyset 落地后只换 pagex 与 repo 实现)。
func (s *Service) ListPublishedPage(cursor string, limit int) ([]Game, string, error) {
	return s.listStatusPage(StatusPublished, cursor, limit)
}

func (s *Service) ListReviewingPage(cursor string, limit int) ([]Game, string, error) {
	return s.listStatusPage(StatusReviewing, cursor, limit)
}

func (s *Service) listStatusPage(status Status, cursor string, limit int) ([]Game, string, error) {
	offset, err := pagex.Decode(cursor)
	if err != nil {
		return nil, "", err
	}
	limit = pagex.ClampLimit(limit)
	items, hasMore, err := s.repo.ListByStatusPage(status, offset, limit)
	if err != nil {
		return nil, "", err
	}
	next := ""
	if hasMore {
		next = pagex.Encode(offset + limit)
	}
	return items, next, nil
}
