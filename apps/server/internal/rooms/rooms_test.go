package rooms

import (
	"github.com/yldm-tech/classic-games/apps/server/internal/storage"
	"sync"
	"testing"
)

func startedRoom(t *testing.T) (*Service, Room) {
	t.Helper()
	db, err := storage.Open("")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(repo)
	r, err := s.Create("host")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.Join(r.Code, "guest"); err != nil {
		t.Fatal(err)
	}
	if _, err = s.Ready(r.ID, "host", true); err != nil {
		t.Fatal(err)
	}
	if _, err = s.Ready(r.ID, "guest", true); err != nil {
		t.Fatal(err)
	}
	r, err = s.Start(r.ID, "host")
	if err != nil {
		t.Fatal(err)
	}
	return s, r
}

func TestRoomRequiresTwoPlayersAndRejectsLateOrConcurrentOverfill(t *testing.T) {
	db, err := storage.Open("file:rooms_concurrency_" + token(8) + "?mode=memory&cache=shared")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(repo)
	solo, err := s.Create("solo")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = s.Ready(solo.ID, "solo", true)
	if _, err := s.Start(solo.ID, "solo"); err != ErrNotReady {
		t.Fatalf("solo start=%v", err)
	}

	room, err := s.Create("host")
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func(n int) { defer wg.Done(); _, _ = s.Join(room.Code, string(rune('a'+n))) }(i)
	}
	wg.Wait()
	filled, err := repo.ByID(room.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(filled.Members) > 4 {
		t.Fatalf("room overfilled: %d", len(filled.Members))
	}
	for _, member := range filled.Members {
		_, _ = s.Ready(room.ID, member.UserID, true)
	}
	if _, err = s.Start(room.ID, "host"); err != nil {
		t.Fatalf("start filled room: %v", err)
	}
	if _, err = s.Join(room.Code, "late"); err != ErrStarted {
		t.Fatalf("late join=%v", err)
	}
}

func TestConcurrentJoinAndStartNeverCreatesMemberWithoutPlayer(t *testing.T) {
	db, err := storage.Open("file:rooms_start_join_" + token(8) + "?mode=memory&cache=shared")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	// A single SQLite connection gives deterministic transaction serialization;
	// the invariant is database-level and remains the same with PostgreSQL writers.
	sqlDB.SetMaxOpenConns(1)
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	s := NewService(repo)
	for i := 0; i < 25; i++ {
		r, _ := s.Create("host_" + token(4))
		guest := "guest_" + token(4)
		late := "late_" + token(4)
		_, _ = s.Join(r.Code, guest)
		_, _ = s.Ready(r.ID, r.HostID, true)
		_, _ = s.Ready(r.ID, guest, true)
		start := make(chan struct{})
		var wg sync.WaitGroup
		wg.Add(2)
		go func() { defer wg.Done(); <-start; _, _ = s.Start(r.ID, r.HostID) }()
		go func() { defer wg.Done(); <-start; _, _ = s.Join(r.Code, late) }()
		close(start)
		wg.Wait()

		room, getErr := repo.ByID(r.ID)
		if getErr != nil {
			t.Fatal(getErr)
		}
		if room.Status == MatchStarted {
			match, matchErr := repo.MatchByRoom(r.ID)
			if matchErr != nil {
				t.Fatal(matchErr)
			}
			if len(match.Players) != len(room.Members) {
				t.Fatalf("started room has %d members but %d players", len(room.Members), len(match.Players))
			}
		}
	}
}

func TestRoomLifecycleAndAuthorization(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo)
	r, e := s.Create("host")
	if e != nil || len(r.Members) != 1 {
		t.Fatalf("%+v %v", r, e)
	}
	r, e = s.Join(r.Code, "guest")
	if e != nil || len(r.Members) != 2 {
		t.Fatalf("join %+v %v", r, e)
	}
	if _, e = s.Start(r.ID, "guest"); e != ErrForbidden {
		t.Fatalf("guest start %v", e)
	}
	s.Ready(r.ID, "host", true)
	if _, e = s.Start(r.ID, "host"); e != ErrNotReady {
		t.Fatalf("early start %v", e)
	}
	s.Ready(r.ID, "guest", true)
	r, e = s.Start(r.ID, "host")
	if e != nil || r.Status != "started" {
		t.Fatalf("start %+v %v", r, e)
	}
}

func TestAuthoritativeMatchRejectsUnauthorizedUnstartedAndStaleInput(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo)
	waiting, _ := s.Create("waiting-host")
	if _, err := s.SubmitInput(waiting.ID, "waiting-host", PlayerInput{Seq: 1, MoveX: 1}); err != ErrNotStarted {
		t.Fatalf("waiting input error = %v, want %v", err, ErrNotStarted)
	}

	s, room := startedRoom(t)
	if _, err := s.Snapshot(room.ID, "outsider"); err != ErrForbidden {
		t.Fatalf("outsider snapshot error = %v, want %v", err, ErrForbidden)
	}
	if _, err := s.SubmitInput(room.ID, "outsider", PlayerInput{Seq: 1}); err != ErrForbidden {
		t.Fatalf("outsider input error = %v, want %v", err, ErrForbidden)
	}
	if _, err := s.SubmitInput(room.ID, "host", PlayerInput{Seq: 0}); err != ErrInvalidInput {
		t.Fatalf("zero sequence error = %v, want %v", err, ErrInvalidInput)
	}
	if _, err := s.SubmitInput(room.ID, "host", PlayerInput{Seq: 1, MoveX: 1}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SubmitInput(room.ID, "host", PlayerInput{Seq: 1, MoveX: -1}); err != ErrStaleInput {
		t.Fatalf("replayed sequence error = %v, want %v", err, ErrStaleInput)
	}
}

func TestAuthoritativeMatchIsDeterministicAndVisibleToAllMembers(t *testing.T) {
	s, room := startedRoom(t)
	initial, err := s.Snapshot(room.ID, "host")
	if err != nil {
		t.Fatal(err)
	}
	if initial.Tick != 0 || initial.Status != MatchStarted || len(initial.Players) != 2 {
		t.Fatalf("initial snapshot = %+v", initial)
	}
	for _, player := range initial.Players {
		if player.Health != 100 || player.LastSeq != 0 {
			t.Fatalf("initial player = %+v", player)
		}
	}

	updated, err := s.SubmitInput(room.ID, "host", PlayerInput{Seq: 1, MoveX: 1, MoveY: -1, Fire: true})
	if err != nil {
		t.Fatal(err)
	}
	if updated.Tick != 1 {
		t.Fatalf("tick = %d, want 1", updated.Tick)
	}
	host := updated.Player("host")
	guest := updated.Player("guest")
	if host == nil || host.X != -56 || host.Y != -8 || host.Score != 10 || host.LastSeq != 1 {
		t.Fatalf("host after input = %+v", host)
	}
	if guest == nil || guest.Health != 90 {
		t.Fatalf("guest after deterministic hit = %+v", guest)
	}

	seenByGuest, err := s.Snapshot(room.ID, "guest")
	if err != nil {
		t.Fatal(err)
	}
	if seenByGuest.Tick != updated.Tick || seenByGuest.Player("host").X != host.X || seenByGuest.Player("guest").Health != guest.Health {
		t.Fatalf("guest snapshot = %+v, host snapshot = %+v", seenByGuest, updated)
	}
}

func TestAuthoritativeMatchFinishesAndPersistsAcrossServiceRestart(t *testing.T) {
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo)
	r, _ := s.Create("host")
	_, _ = s.Join(r.Code, "guest")
	_, _ = s.Ready(r.ID, "host", true)
	_, _ = s.Ready(r.ID, "guest", true)
	_, _ = s.Start(r.ID, "host")

	var snapshot MatchSnapshot
	for seq := int64(1); seq <= 10; seq++ {
		var err error
		snapshot, err = s.SubmitInput(r.ID, "host", PlayerInput{Seq: seq, Fire: true})
		if err != nil {
			t.Fatalf("input %d: %v", seq, err)
		}
	}
	if snapshot.Status != MatchFinished || snapshot.WinnerID != "host" || snapshot.Player("guest").Health != 0 {
		t.Fatalf("finished snapshot = %+v", snapshot)
	}
	if _, err := s.SubmitInput(r.ID, "guest", PlayerInput{Seq: 1}); err != ErrMatchFinished {
		t.Fatalf("post-finish input error = %v, want %v", err, ErrMatchFinished)
	}

	restartedRepo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	restored, err := NewService(restartedRepo).Snapshot(r.ID, "guest")
	if err != nil {
		t.Fatal(err)
	}
	if restored.Tick != 10 || restored.Status != MatchFinished || restored.WinnerID != "host" {
		t.Fatalf("restored snapshot = %+v", restored)
	}
}
