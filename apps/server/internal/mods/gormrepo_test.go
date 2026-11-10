package mods

import (
	"testing"

	"forgeplay/server/internal/storage"
)

func newGormSvc(t *testing.T) *Service {
	t.Helper()
	db, err := storage.Open("") // 内存 SQLite
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
	return NewService(repo, fileBaselines{t})
}

// GORM 实现跑通与 MemRepo 相同的 Fork 全流程,证明持久化层可无痛替换。
func TestGorm_ForkFlow(t *testing.T) {
	s := newGormSvc(t)

	root, err := s.CreateRoot("shooter@1.0.0", ops(t, `[{"op":"replace","path":"/player/sprite","value":"cat"}]`), false)
	if err != nil {
		t.Fatal(err)
	}
	eff, err := s.EffectiveDSL(root.ID)
	if err != nil {
		t.Fatal(err)
	}
	if sprite(eff) != "cat" {
		t.Errorf("GORM 持久化后生效 DSL sprite=%s, 期望 cat", sprite(eff))
	}

	// 子:加鸟(补丁 JSON 列经 DB 往返后仍能正确 apply)
	child, _ := s.CreateChild(root.ID, ops(t, `[{"op":"add","path":"/enemies/bird_1","value":{"type":"bird","behavior":"sine","count":10,"hp":15,"speed":12}}]`), false)
	eff2, _ := s.EffectiveDSL(child.ID)
	if _, has := eff2["enemies"].(map[string]any)["bird_1"]; !has {
		t.Error("子 mod 应含 bird_1(补丁链经 DB 往返仍正确)")
	}
	if sprite(eff2) != "cat" {
		t.Error("子 mod 应继承 cat")
	}

	// Fork + Fork Tree
	fork, _ := s.Fork(root.ID)
	if fork.ParentID != root.ID {
		t.Error("Fork parent 不对")
	}
	view, _ := s.ForkTree(root.ID, "")
	if len(view.Children) != 1 { // 私有 fork 草稿不能出现在公开 Fork Tree
		t.Errorf("root 应只公开 1 个非草稿子节点, got %d", len(view.Children))
	}
}

func TestGorm_NotFound(t *testing.T) {
	s := newGormSvc(t)
	if _, err := s.EffectiveDSL("mod_nope"); err != ErrNotFound {
		t.Errorf("期望 ErrNotFound, got %v", err)
	}
}
