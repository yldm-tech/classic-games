package games

import (
	"testing"

	"forgeplay/server/internal/storage"
)

func newGormSvc(t *testing.T) *Service {
	t.Helper()
	db, err := storage.Open("")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	return NewService(repo)
}

// GORM 实现跑通发布→审核→列表,且字段(含 JSON tags)经 DB 往返正确。
func TestGorm_PublishApproveList(t *testing.T) {
	s := newGormSvc(t)

	g, err := s.Publish(PublishRequest{ModID: "mod_1", Title: "电光狂奔", Tags: []string{"竞速", "AI"}, AIGenerated: true})
	if err != nil {
		t.Fatal(err)
	}
	if g.Status != StatusReviewing {
		t.Fatalf("发布后应 reviewing, got %s", g.Status)
	}

	// 审核通过(Update 落库)
	if _, err := s.Decide(g.ID, true); err != nil {
		t.Fatal(err)
	}

	// 重新读取:状态已持久化为 published,tags(JSON 列)往返正确
	got, err := s.Get(g.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != StatusPublished {
		t.Errorf("持久化状态=%s, 期望 published", got.Status)
	}
	if len(got.Tags) != 2 || got.Tags[0] != "竞速" {
		t.Errorf("tags JSON 列往返不对: %v", got.Tags)
	}

	// 列表
	list, _ := s.ListPublished()
	if len(list) != 1 {
		t.Errorf("已发布列表应 1 项, got %d", len(list))
	}
}

// Update 对不存在的行返回 ErrNotFound(RowsAffected==0),不会静默 INSERT 回来。
func TestGorm_UpdateMissing(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	if err := repo.Update(Game{ID: "nope", Status: StatusPublished}); err != ErrNotFound {
		t.Errorf("更新不存在的行应 ErrNotFound, got %v", err)
	}
	if _, err := repo.Get("nope"); err != ErrNotFound {
		t.Error("失败的 Update 不应把行插回来")
	}
}

func TestGorm_Pagination(t *testing.T) {
	s := newGormSvc(t)
	for i := 0; i < 3; i++ {
		g, _ := s.Publish(PublishRequest{ModID: "m", Title: "g"})
		s.Decide(g.ID, true)
	}
	p1, c1, _ := s.ListPublishedPage("", 2)
	if len(p1) != 2 || c1 == "" {
		t.Fatalf("第一页应 2 项 + 游标")
	}
	p2, c2, _ := s.ListPublishedPage(c1, 2)
	if len(p2) != 1 || c2 != "" {
		t.Fatalf("第二页应 1 项 + 空游标")
	}
}
