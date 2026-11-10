// Package ranking 计算榜单(热门/飙升/新作,docs/09-api-design.md ranking)。
// 依赖 games(已发布作品)与点赞计数,通过接口注入,不反向耦合。
package ranking

import (
	"errors"
	"sort"
	"strings"
	"time"

	"forgeplay/server/internal/games"
)

// GameSource 提供已发布作品(games.Service 满足)。
type GameSource interface {
	ListPublished() ([]games.Game, error)
}

// LikeSource 提供点赞计数(social.Service 满足)。批量接口避免逐游戏查询(N+1)。
type LikeSource interface {
	LikeCounts(gameIDs []string) (map[string]int, error)
	RecentLikeCounts(gameIDs []string, since time.Time) (map[string]int, error)
}

type Service struct {
	gamesSrc GameSource
	likes    LikeSource
	hidden   interface {
		IsGameHidden(userID, gameID string) (bool, error)
	}
	onTop10 func(string) error
}

func (s *Service) SetTop10Recorder(f func(string) error) { s.onTop10 = f }

func (s *Service) SetHiddenChecker(h interface {
	IsGameHidden(userID, gameID string) (bool, error)
}) {
	s.hidden = h
}

func NewService(gamesSrc GameSource, likes LikeSource) *Service {
	return &Service{gamesSrc: gamesSrc, likes: likes}
}

// Ranked 是带名次与点赞数的榜单项。
type Ranked struct {
	games.Game
	Likes int `json:"likes"`
	Rank  int `json:"rank"`
}

var ErrUnknownType = errors.New("ranking: 未知榜单类型")

// Ranked 返回指定类型榜单。type ∈ hot / new / rising。
func (s *Service) Ranked(kind string, limit int) ([]Ranked, error) {
	return s.RankedFor("", kind, limit)
}
func (s *Service) RankedFor(userID, kind string, limit int) ([]Ranked, error) {
	return s.RankedFilteredFor(userID, kind, limit, "", "")
}
func (s *Service) RankedFilteredFor(userID, kind string, limit int, runtime, category string) ([]Ranked, error) {
	gs, err := s.gamesSrc.ListPublished()
	if err != nil {
		return nil, err
	}
	filtered := make([]games.Game, 0, len(gs))
	for _, game := range gs {
		name := strings.SplitN(game.Runtime, "@", 2)[0]
		if runtime != "" && runtime != game.Runtime && runtime != name {
			continue
		}
		if category != "" && category != game.Category {
			continue
		}
		filtered = append(filtered, game)
	}
	gs = filtered
	ids := make([]string, len(gs))
	for i, g := range gs {
		ids[i] = g.ID
	}
	// 一次批量取点赞数(避免 N+1);DB 故障时返回错误而非静默把赞当 0。
	counts, err := s.likes.LikeCounts(ids)
	if err != nil {
		return nil, err
	}
	items := make([]Ranked, 0, len(gs))
	for _, g := range gs {
		if s.hidden != nil && userID != "" {
			hidden, e := s.hidden.IsGameHidden(userID, g.ID)
			if e != nil {
				return nil, e
			}
			if hidden {
				continue
			}
		}
		// social.LikeCounts 已是单一真相源(种子展示基数 + 真实点赞),直接用,不再叠加 g.Likes。
		items = append(items, Ranked{Game: g, Likes: counts[g.ID]})
	}

	switch kind {
	case "hot":
		// 热门:按点赞降序(并列按 ID 稳定)
		sort.SliceStable(items, func(i, j int) bool {
			if items[i].Likes != items[j].Likes {
				return items[i].Likes > items[j].Likes
			}
			return items[i].ID > items[j].ID
		})
	case "new":
		// 新作:按创建时间降序(不能用字典序 ID:随机 hex 无序,且 game_9 > game_10 反了)
		sort.SliceStable(items, func(i, j int) bool {
			if !items[i].CreatedAt.Equal(items[j].CreatedAt) {
				return items[i].CreatedAt.After(items[j].CreatedAt)
			}
			return items[i].ID > items[j].ID
		})
	case "rising":
		// 飙升:按最近 24 小时真实点赞数排序；种子历史展示基数不混入增速。
		recent, err := s.likes.RecentLikeCounts(ids, time.Now().Add(-24*time.Hour))
		if err != nil {
			return nil, err
		}
		sort.SliceStable(items, func(i, j int) bool {
			si, sj := recent[items[i].ID], recent[items[j].ID]
			if si != sj {
				return si > sj
			}
			if items[i].Likes != items[j].Likes {
				return items[i].Likes > items[j].Likes
			}
			return items[i].ID > items[j].ID
		})
	default:
		return nil, ErrUnknownType
	}

	if limit > 0 && len(items) > limit {
		items = items[:limit]
	}
	for i := range items {
		items[i].Rank = i + 1
		if kind == "hot" && i < 10 && items[i].AuthorID != "" && s.onTop10 != nil {
			_ = s.onTop10(items[i].AuthorID)
		}
	}
	return items, nil
}
