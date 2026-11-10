package social

import (
	"os"
	"path/filepath"
	"testing"
)

func newSvc() *Service { return NewService(NewMemRepo()) }

func TestComment_AddAndList(t *testing.T) {
	s := newSvc()
	if _, err := s.Comment("game_1", "user_1", "好玩"); err != nil {
		t.Fatal(err)
	}
	s.Comment("game_1", "user_2", "二创了一版")
	s.Comment("game_2", "user_1", "别的游戏")

	items, _, err := s.Comments("game_1", "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Errorf("game_1 应有 2 条评论, got %d", len(items))
	}
}

func TestComment_Validation(t *testing.T) {
	s := newSvc()
	if _, err := s.Comment("g", "u", "   "); err != ErrEmptyContent {
		t.Errorf("空内容应 ErrEmptyContent, got %v", err)
	}
	long := make([]rune, maxCommentLen+1)
	for i := range long {
		long[i] = '字'
	}
	if _, err := s.Comment("g", "u", string(long)); err != ErrTooLong {
		t.Errorf("超长应 ErrTooLong, got %v", err)
	}
}

func TestLike_ToggleIdempotent(t *testing.T) {
	s := newSvc()
	s.Like("game_1", "user_1")
	s.Like("game_1", "user_1") // 重复点赞幂等
	s.Like("game_1", "user_2")

	count, liked, _ := s.LikeStatus("game_1", "user_1")
	if count != 2 {
		t.Errorf("点赞数应 2(去重), got %d", count)
	}
	if !liked {
		t.Error("user_1 应为已赞")
	}

	s.Unlike("game_1", "user_1")
	count, liked, _ = s.LikeStatus("game_1", "user_1")
	if count != 1 || liked {
		t.Errorf("取消后应 count=1 liked=false, got %d %v", count, liked)
	}
}

func TestFavorite_ToggleAndList(t *testing.T) {
	s := newSvc()
	if err := s.Favorite("game_1", "user_1"); err != nil {
		t.Fatal(err)
	}
	_ = s.Favorite("game_1", "user_1")
	_ = s.Favorite("game_2", "user_1")
	items, err := s.Favorites("user_1")
	if err != nil || len(items) != 2 || items[0] != "game_2" || items[1] != "game_1" {
		t.Fatalf("收藏应幂等并按新到旧列出: %v %v", items, err)
	}
	if err := s.Unfavorite("game_1", "user_1"); err != nil {
		t.Fatal(err)
	}
	items, _ = s.Favorites("user_1")
	if len(items) != 1 || items[0] != "game_2" {
		t.Fatalf("取消收藏未生效: %v", items)
	}
}

func TestComments_Pagination(t *testing.T) {
	s := newSvc()
	for i := 0; i < 5; i++ {
		s.Comment("g", "u", "c")
	}
	p1, c1, _ := s.Comments("g", "", 2)
	if len(p1) != 2 || c1 == "" {
		t.Fatalf("第一页应 2 条 + 游标")
	}
	p2, _, _ := s.Comments("g", c1, 2)
	if len(p2) != 2 {
		t.Fatalf("第二页应 2 条")
	}
}

type stubBlocks map[string][]string

func (s stubBlocks) ListBlocked(uid string) ([]string, error) { return s[uid], nil }

// 评论命中敏感词被拦截(Phase-1 文本审核基线);正常评论通过。
func TestComment_Moderation(t *testing.T) {
	s := newSvc()
	if _, err := s.Comment("g", "u1", "this is spam, buy now"); err != ErrContentRejected {
		t.Errorf("命中敏感词应 ErrContentRejected, got %v", err)
	}
	if _, err := s.Comment("g", "u1", "夜间地图手感不错"); err != nil {
		t.Errorf("正常评论应通过, got %v", err)
	}
}

func TestComment_ModerationRejectsUnicodeAndSeparatorEvasion(t *testing.T) {
	s := newSvc()
	for _, text := range []string{"ＳＰＡＭ", "s.p-a_m", "傻\u200b逼"} {
		if _, err := s.Comment("g", "u", text); err != ErrContentRejected {
			t.Errorf("规避写法 %q 应被拦截, got %v", text, err)
		}
	}
}

func TestKeywordModerator_LoadsExternalWordList(t *testing.T) {
	path := filepath.Join(t.TempDir(), "words.txt")
	if err := os.WriteFile(path, []byte("# custom\n剧透\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	m, err := NewKeywordModeratorFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := m.Check("这 是 剧-透"); err != ErrContentRejected {
		t.Fatalf("外置词库及插字符规避应生效: %v", err)
	}
}

// 登录视角按浏览者黑名单过滤被屏蔽作者的评论;匿名视角不过滤。
func TestCommentsForViewer_FiltersBlocked(t *testing.T) {
	s := newSvc()
	s.SetBlockLister(stubBlocks{"viewer": {"@blocked"}})
	if _, err := s.Comment("g", "@blocked", "hi"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Comment("g", "@ok", "hey"); err != nil {
		t.Fatal(err)
	}
	all, _, _ := s.CommentsForViewer("g", "", "", 10)
	if len(all) != 2 {
		t.Fatalf("匿名视角应看到 2 条, got %d", len(all))
	}
	filtered, _, _ := s.CommentsForViewer("g", "viewer", "", 10)
	if len(filtered) != 1 || filtered[0].AuthorID != "@ok" {
		t.Fatalf("viewer 应只看到未屏蔽作者, got %+v", filtered)
	}
}
