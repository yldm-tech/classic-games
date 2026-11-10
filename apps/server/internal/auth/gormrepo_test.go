package auth

import (
	"testing"

	"forgeplay/server/internal/storage"
)

func TestGorm_LoginAutoCreatesAndReuses(t *testing.T) {
	db, _ := storage.Open("")
	models := append(IdentityMigrationModels(), RuntimeMigrationModels()...)
	if migrateErr := db.AutoMigrate(models...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterIdentityMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormUserRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	sender := NewLogSender()
	svc := NewService(sender, repo)

	svc.SendCode("13800001234")
	_, u1, err := svc.Login("13800001234", sender.Last["13800001234"])
	if err != nil {
		t.Fatalf("登录失败: %v", err)
	}
	if u1.ID == "" {
		t.Fatal("应建用户")
	}
	// 再次登录同号 → 复用(持久化查得到)
	svc.SendCode("13800001234")
	_, u2, _ := svc.Login("13800001234", sender.Last["13800001234"])
	if u1.ID != u2.ID {
		t.Errorf("同号应复用持久化用户, %s != %s", u1.ID, u2.ID)
	}
}
