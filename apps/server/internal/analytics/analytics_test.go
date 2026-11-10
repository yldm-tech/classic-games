package analytics

import (
	"testing"

	"github.com/yldm-tech/classic-games/apps/server/internal/storage"
)

func TestSummaryComputesCoreFunnelMetrics(t *testing.T) {
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
	s := NewService(repo)
	events := []Event{
		{Name: GameViewed, SessionID: "a", TargetID: "g1"},
		{Name: GameViewed, SessionID: "b", TargetID: "g1"},
		{Name: ForkStarted, SessionID: "a", TargetID: "g1"},
		{Name: AIEditStarted, SessionID: "a", TargetID: "g1"},
		{Name: AIEditStarted, SessionID: "b", TargetID: "g1"},
		{Name: ModPublished, SessionID: "a", TargetID: "g1", Depth: 3},
		{Name: ForkStarted, SessionID: "not-a-viewer", TargetID: "g1"},
		{Name: ModPublished, SessionID: "not-an-editor", TargetID: "g1", Depth: 2},
	}
	for _, e := range events {
		if err := s.Record(e); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.Summary()
	if err != nil {
		t.Fatal(err)
	}
	if got.GameViewers != 2 || got.ForkStarters != 1 || got.ForkConversion != .5 {
		t.Fatalf("fork metrics=%+v", got)
	}
	if got.AIEditors != 2 || got.AIPublishers != 1 || got.AIPublishRate != .5 {
		t.Fatalf("AI metrics=%+v", got)
	}
	if got.MaxForkDepth != 3 {
		t.Fatalf("depth=%d", got.MaxForkDepth)
	}
}

func TestRecordRejectsUnknownAndMissingSession(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo)
	if err := s.Record(Event{Name: "made_up", SessionID: "x"}); err != ErrInvalidEvent {
		t.Fatalf("got %v", err)
	}
	if err := s.Record(Event{Name: GameViewed}); err != ErrSessionRequired {
		t.Fatalf("got %v", err)
	}
}

func TestCountByTargetCountsRequestedEventOnly(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo)
	for _, e := range []Event{
		{Name: GameViewed, SessionID: "a", TargetID: "g1"},
		{Name: GameViewed, SessionID: "b", TargetID: "g1"},
		{Name: GameViewed, SessionID: "c", TargetID: "g2"},
		{Name: ForkStarted, SessionID: "d", TargetID: "g1"},
	} {
		if err := s.Record(e); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.CountByTarget(GameViewed, []string{"g1", "g2", "missing"})
	if err != nil || got["g1"] != 2 || got["g2"] != 1 || got["missing"] != 0 {
		t.Fatalf("counts=%v err=%v", got, err)
	}
}
