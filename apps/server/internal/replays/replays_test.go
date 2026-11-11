package replays

import (
	"github.com/yldm-tech/classic-games/apps/server/internal/storage"
	"testing"
	"time"
)

func TestReplayPersistAndValidate(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, e := NewGormRepo(db)
	if e != nil {
		t.Fatal(e)
	}
	s := NewService(r)
	frames := []Frame{{AtMS: 0, X: 1, Y: 2, HP: 100}, {AtMS: 1000, X: 3, Y: 4, HP: 90, Score: 10}}
	first, e := s.Create("g", "u", 1000, frames)
	if e != nil {
		t.Fatal(e)
	}
	if first.ID == "" {
		t.Fatal("missing id")
	}
	// The first replay is made an hour old. Left at "now" it is microseconds older than the second, and SQLite cannot order that reliably: timestamps are stored as RFC 3339 text with trailing zeros of the fraction trimmed, so "…06.213Z" sorts after "…06.21304Z" although it is the earlier instant, and Latest then returns the first replay (about one run in a hundred).
	if e = db.Model(&Replay{}).Where("id = ?", first.ID).Update("created_at", first.CreatedAt.Add(-time.Hour)).Error; e != nil {
		t.Fatal(e)
	}
	frames[1].Score = 20
	second, e := s.Create("g", "u", 1000, frames)
	if e != nil {
		t.Fatal(e)
	}
	got, e := s.Latest("g", "u")
	if e != nil || got.ID != second.ID {
		t.Fatalf("latest=%+v %v", got, e)
	}
	if _, e = s.Create("g", "u", 1000, []Frame{{AtMS: 2}, {AtMS: 1}}); e != ErrInvalid {
		t.Fatalf("non-monotonic accepted: %v", e)
	}
}

func TestLeaderboardUsesBestAuthoritativeUserIDs(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	s := NewService(r)
	s.SetScoreResolver(func(_ string, _ string, frames []Frame) (int, bool) { return frames[len(frames)-1].Score, true })
	s.SetUserLookup(func(id string) string { return map[string]string{"u1": "Alice", "u2": "Bob"}[id] })
	frames := func(score int) []Frame { return []Frame{{AtMS: 0, HP: 100}, {AtMS: 100, HP: 90, Score: score}} }
	_, _ = s.Create("g", "u1", 100, frames(10))
	_, _ = s.Create("g", "u1", 100, frames(30))
	_, _ = s.Create("g", "u2", 100, frames(20))
	got, e := s.Leaderboard("g", 10)
	if e != nil || len(got) != 2 || got[0].UserID != "u1" || got[0].Nickname != "Alice" || got[0].Score != 30 || got[1].UserID != "u2" {
		t.Fatalf("board=%+v err=%v", got, e)
	}
}

func TestClientReplayScoreIsNotTrustedWithoutAuthoritativeResolver(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	r, _ := NewGormRepo(db)
	s := NewService(r)
	progressed := 0
	s.SetScoreRecorder(func(_ string, _ int) error { progressed++; return nil })
	replay, err := s.Create("g", "attacker", 100, []Frame{{AtMS: 0, HP: 100, Score: 999999}, {AtMS: 100, HP: 100, Score: 999999}})
	if err != nil {
		t.Fatal(err)
	}
	if replay.Score != 0 || replay.Frames[len(replay.Frames)-1].Score != 0 || progressed != 0 {
		t.Fatalf("untrusted score escaped: replay=%+v progressed=%d", replay, progressed)
	}
	board, err := s.Leaderboard("g", 10)
	if err != nil || len(board) != 0 {
		t.Fatalf("untrusted score on board: %+v %v", board, err)
	}
}

func TestPhysicalScoreAcceptsHonestTraceAndRejectsImpossibleGain(t *testing.T) {
	if score, ok := PhysicalScore([]Frame{{AtMS: 0, HP: 100}, {AtMS: 1000, X: 40, Score: 200}}); !ok || score != 200 {
		t.Fatalf("honest=%d %v", score, ok)
	}
	if _, ok := PhysicalScore([]Frame{{AtMS: 0, HP: 100, Score: 0}, {AtMS: 100, HP: 100, Score: 999999}}); ok {
		t.Fatal("impossible score accepted")
	}
	if _, ok := PhysicalScore([]Frame{{AtMS: 0, HP: 100, Score: 999999}, {AtMS: 100, HP: 100, Score: 999999}}); ok {
		t.Fatal("spawned high score accepted")
	}
	if _, ok := PhysicalScore([]Frame{{AtMS: 0, X: 0}, {AtMS: 100, X: 5000}}); ok {
		t.Fatal("teleport accepted")
	}
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(repo)
	s.SetScoreResolver(func(_ string, _ string, frames []Frame) (int, bool) { return PhysicalScore(frames) })
	honest, err := s.Create("g", "u", 1000, []Frame{{AtMS: 0, HP: 100}, {AtMS: 1000, X: 40, Score: 200}})
	if err != nil || honest.Score != 200 {
		t.Fatalf("honest replay=%+v %v", honest, err)
	}
	bad, err := s.Create("g", "cheater", 100, []Frame{{AtMS: 0, HP: 100, Score: 999999}, {AtMS: 100, HP: 100, Score: 999999}})
	if err != nil || bad.Score != 0 {
		t.Fatalf("cheat replay=%+v %v", bad, err)
	}
}
