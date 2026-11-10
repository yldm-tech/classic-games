package ai

import (
	"context"
	"testing"

	"forgeplay/server/internal/storage"
)

// GormRecorder 持久化 ai_calls 并能聚合 token(成本核算基础);
// 同时验证它能作为真实 Recorder 喂给 Service。
func TestGormRecorder_PersistsAndSums(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	rec, err := NewGormRecorder(db)
	if err != nil {
		t.Fatal(err)
	}

	rec.Record(context.Background(), CallRecord{Runtime: "shooter@1.0.0", Model: "fake", Tokens: TokenUsage{Prompt: 100, Completion: 20}, Valid: true})
	rec.Record(context.Background(), CallRecord{Runtime: "shooter@1.0.0", Model: "fake", Tokens: TokenUsage{Prompt: 50, Completion: 10}, Valid: false, ErrCode: "DSL_INVALID"})

	total, err := rec.TotalTokens()
	if err != nil {
		t.Fatal(err)
	}
	if total != 180 { // 100+20+50+10
		t.Errorf("累计 token = %d, 期望 180", total)
	}
	n, _ := rec.CallCount()
	if n != 2 {
		t.Errorf("调用次数 = %d, 期望 2", n)
	}
}

func TestGormRecorder_WiresIntoService(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	rec, _ := NewGormRecorder(db)

	ops := parseOps(t, forkPatchJSON)
	prov := &funcProvider{fn: func(_ int, _ string) (PatchSuggestion, error) {
		return PatchSuggestion{Ops: ops, Model: "fake", Tokens: TokenUsage{Prompt: 200, Completion: 40}}, nil
	}}
	svc := NewService(prov, newValidator(t), rec, 2)

	if _, err := svc.GenerateMod(context.Background(), baseReq(t)); err != nil {
		t.Fatal(err)
	}
	// 一次成功创作 → 审计落库一条,token 记下
	if total, _ := rec.TotalTokens(); total != 240 {
		t.Errorf("审计 token = %d, 期望 240", total)
	}
}
