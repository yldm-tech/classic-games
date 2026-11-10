// Package social 实现最小社区互动:评论、点赞(docs/09-api-design.md social、10-data-model.md)。
// 内存实现 + Repository 接口;生产换 GORM。
package social

import (
	"bufio"
	"errors"
	"os"
	"strings"
	"time"
	"unicode"

	"github.com/yldm-tech/classic-games/apps/server/pkg/pagex"
	"golang.org/x/text/unicode/norm"
)

var (
	ErrEmptyContent    = errors.New("social: 评论内容为空")
	ErrTooLong         = errors.New("social: 评论过长")
	ErrContentRejected = errors.New("social: 评论命中内容审核,已拦截")
)

const maxCommentLen = 1000

// TextModerator 文本审核(docs/14-security-compliance.md §一「评论…走文本审核(敏感词 + 模型)」)。
// 默认是本地敏感词过滤；配置 CONTENT_MODERATION_URL 后叠加外部审核。Check 返回非 nil 表示拦截。
type TextModerator interface {
	Check(text string) error
}

// keywordModerator 是 Phase-1 基线:命中任一关键词即拦截(大小写不敏感)。词表可扩展/外置。
type keywordModerator struct{ words []string }

// NewKeywordModerator 用给定词表构造；输入与词条都做 NFKC、大小写折叠并移除分隔符。
func NewKeywordModerator(words ...string) TextModerator {
	if len(words) == 0 {
		words = defaultBlockWords
	}
	return &keywordModerator{words: words}
}

// defaultBlockWords 是随程序分发的最低安全基线；生产可用 CLASSIC_GAMES_BLOCK_WORDS_FILE 外置扩充。
var defaultBlockWords = []string{"fuck", "shit", "spam", "傻逼", "草泥马"}

func (m *keywordModerator) Check(text string) error {
	low := moderationFold(text)
	for _, w := range m.words {
		if folded := moderationFold(w); folded != "" && strings.Contains(low, folded) {
			return ErrContentRejected
		}
	}
	return nil
}

// NewKeywordModeratorFile 从 UTF-8 文本加载词库，一行一词，空行和 # 注释忽略。
func NewKeywordModeratorFile(path string) (TextModerator, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	words := append([]string{}, defaultBlockWords...)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" && !strings.HasPrefix(line, "#") {
			words = append(words, line)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return NewKeywordModerator(words...), nil
}

func moderationFold(text string) string {
	text = strings.ToLower(norm.NFKC.String(text))
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsNumber(r) {
			return r
		}
		return -1
	}, text)
}

// BlockLister 提供某用户屏蔽的用户 ID 列表(由 moderation 域实现),
// 供读路径过滤被屏蔽作者的内容(docs/14 的「屏蔽」处置链)。
type BlockLister interface {
	ListBlocked(userID string) ([]string, error)
}

type Comment struct {
	ID        string    `json:"id" gorm:"primaryKey"`
	GameID    string    `json:"game_id" gorm:"index"`
	AuthorID  string    `json:"author_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"` // 评论按时间排序,而非字典序 ID
}

type Repository interface {
	AddComment(c Comment) (Comment, error)
	ListComments(gameID string) ([]Comment, error)
	SetLike(gameID, userID string, liked bool) error
	LikeCount(gameID string) (int, error)
	// LikeCounts 批量取多个游戏的点赞数(榜单聚合用,避免 N+1)。无赞的 gameID 计 0。
	LikeCounts(gameIDs []string) (map[string]int, error)
	RecentLikeCounts(gameIDs []string, since time.Time) (map[string]int, error)
	HasLiked(gameID, userID string) (bool, error)
	// SetBaseLikes 设置点赞展示基数(种子历史人气);LikeCount/LikeCounts 在其上累加真实点赞。
	SetBaseLikes(gameID string, n int) error
	SetFavorite(gameID, userID string, favorite bool) error
	ListFavorites(userID string) ([]string, error)
}

type Service struct {
	repo      Repository
	moderator TextModerator // 评论写路径的文本审核(默认基线敏感词)
	blocks    BlockLister   // 读路径屏蔽过滤(nil = 不过滤,如匿名/未接 moderation)
	onComment func(string) error
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo, moderator: NewKeywordModerator()}
}

// SetModerator 替换文本审核器(生产接入模型审核时用)。
func (s *Service) SetModerator(m TextModerator) {
	if m != nil {
		s.moderator = m
	}
}

// SetBlockLister 注入屏蔽列表来源(moderation 域),开启读路径的屏蔽过滤。
func (s *Service) SetBlockLister(b BlockLister)            { s.blocks = b }
func (s *Service) SetCommentRecorder(f func(string) error) { s.onComment = f }

// SetBaseLikes 设置某游戏点赞展示基数(种子启动时按作品历史人气灌入,使 social 成为点赞单一真相源)。
func (s *Service) SetBaseLikes(gameID string, n int) error { return s.repo.SetBaseLikes(gameID, n) }

// Comment 发表评论。先文本审核(敏感词),命中则 ErrContentRejected;通过才落库。
func (s *Service) Comment(gameID, authorID, content string) (Comment, error) {
	content = strings.TrimSpace(content)
	if content == "" {
		return Comment{}, ErrEmptyContent
	}
	if len([]rune(content)) > maxCommentLen {
		return Comment{}, ErrTooLong
	}
	if s.moderator != nil {
		if err := s.moderator.Check(content); err != nil {
			return Comment{}, err
		}
	}
	comment, err := s.repo.AddComment(Comment{GameID: gameID, AuthorID: authorID, Content: content})
	if err == nil && s.onComment != nil {
		_ = s.onComment(authorID)
	}
	return comment, err
}

// Comments 游标分页列出某游戏的评论(匿名视角,不做屏蔽过滤)。
func (s *Service) Comments(gameID, cursor string, limit int) ([]Comment, string, error) {
	return s.CommentsForViewer(gameID, "", cursor, limit)
}

// CommentsForViewer 同 Comments,但按 viewerID 过滤掉被该用户屏蔽的作者的评论(viewerID 为空则不过滤)。
// 先在「未过滤」的稳定列表上分页(游标=未过滤偏移,与浏览者/屏蔽状态无关),再从该页剔除被屏蔽作者。
// 故某页可能短于 limit(甚至为空),但游标始终稳定——避免匿名取的游标登录后重放、或屏蔽集变化时错位跳/重复评论。
func (s *Service) CommentsForViewer(gameID, viewerID, cursor string, limit int) ([]Comment, string, error) {
	all, err := s.repo.ListComments(gameID)
	if err != nil {
		return nil, "", err
	}
	page, next, err := pagex.Page(all, cursor, limit)
	if err != nil {
		return nil, "", err
	}
	if viewerID != "" && s.blocks != nil {
		page = s.dropBlocked(page, viewerID)
	}
	return page, next, nil
}

// dropBlocked 过滤掉作者在 viewer 黑名单里的评论;取黑名单失败时放行(不因审核侧故障阻断读)。
func (s *Service) dropBlocked(in []Comment, viewerID string) []Comment {
	blocked, err := s.blocks.ListBlocked(viewerID)
	if err != nil || len(blocked) == 0 {
		return in
	}
	set := make(map[string]struct{}, len(blocked))
	for _, id := range blocked {
		set[id] = struct{}{}
	}
	out := make([]Comment, 0, len(in))
	for _, c := range in {
		if _, ok := set[c.AuthorID]; ok {
			continue
		}
		out = append(out, c)
	}
	return out
}

// LikeCount 返回某游戏的点赞数(供排行榜聚合)。
func (s *Service) LikeCount(gameID string) (int, error) { return s.repo.LikeCount(gameID) }

// LikeCounts 批量返回多个游戏的点赞数(榜单一次聚合,避免 N+1)。
func (s *Service) LikeCounts(gameIDs []string) (map[string]int, error) {
	return s.repo.LikeCounts(gameIDs)
}

// RecentLikeCounts 返回时间窗内仍有效的真实点赞数；历史展示基数不计入增速。
func (s *Service) RecentLikeCounts(gameIDs []string, since time.Time) (map[string]int, error) {
	return s.repo.RecentLikeCounts(gameIDs, since)
}

// Like / Unlike 切换点赞;幂等。
func (s *Service) Like(gameID, userID string) error   { return s.repo.SetLike(gameID, userID, true) }
func (s *Service) Unlike(gameID, userID string) error { return s.repo.SetLike(gameID, userID, false) }

// LikeStatus 返回点赞数与当前用户是否已赞。
func (s *Service) LikeStatus(gameID, userID string) (count int, liked bool, err error) {
	count, err = s.repo.LikeCount(gameID)
	if err != nil {
		return 0, false, err
	}
	if userID != "" {
		liked, err = s.repo.HasLiked(gameID, userID)
	}
	return count, liked, err
}

func (s *Service) Favorite(gameID, userID string) error {
	return s.repo.SetFavorite(gameID, userID, true)
}
func (s *Service) Unfavorite(gameID, userID string) error {
	return s.repo.SetFavorite(gameID, userID, false)
}
func (s *Service) Favorites(userID string) ([]string, error) { return s.repo.ListFavorites(userID) }
