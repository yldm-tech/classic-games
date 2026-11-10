package replays

import (
	"testing"

	"github.com/yldm-tech/classic-games/apps/server/internal/storage"
)

// Migrations run on every process start, so anything registered in the migration set must be safe to repeat. This
// pins that property for replays: a leaderboard score persisted before a restart must still be there afterwards. It
// exists because migration 017 used to carry an `After` hook that ran `UPDATE replays SET score = 0 WHERE score <> 0`
// on every boot, which emptied every leaderboard on each deploy. The bug survived review because all the other tests
// ran that hook against an empty database before creating any rows.
func TestScoresSurviveRepeatedMigration(t *testing.T) {
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
	if _, createErr := repo.Create(Replay{ID: "rp1", GameID: "g", UserID: "u1", Score: 200, DurationMS: 1000}); createErr != nil {
		t.Fatal(createErr)
	}

	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}

	board, err := repo.Leaderboard("g", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(board) != 1 || board[0].Score != 200 {
		t.Fatalf("leaderboard lost the score across a re-migration: %+v", board)
	}
	latest, err := repo.Latest("g", "u1")
	if err != nil {
		t.Fatal(err)
	}
	if latest.Score != 200 {
		t.Fatalf("latest replay score = %d, want 200", latest.Score)
	}
}
