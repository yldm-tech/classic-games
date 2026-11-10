package users

import (
	"testing"

	"github.com/yldm-tech/classic-games/apps/server/internal/games"
)

// A profile listing is public. The works and forks branches already restrict themselves to published games, but the
// branch that resolves an explicit id set did not, so a game still under review — or one that was rejected or delisted
// by a moderator — stayed readable to anonymous callers through anyone's liked list.
func TestLikedListHidesGamesThatAreNotPublished(t *testing.T) {
	gameSvc := games.NewService(games.NewMemRepo())

	published, err := gameSvc.Publish(games.PublishRequest{ModID: "m1", AuthorID: "author", Title: "Visible"})
	if err != nil {
		t.Fatal(err)
	}
	if published, err = gameSvc.Decide(published.ID, true); err != nil {
		t.Fatal(err)
	}
	reviewing, err := gameSvc.Publish(games.PublishRequest{ModID: "m2", AuthorID: "author", Title: "Still In Review"})
	if err != nil {
		t.Fatal(err)
	}
	rejected, err := gameSvc.Publish(games.PublishRequest{ModID: "m3", AuthorID: "author", Title: "Rejected"})
	if err != nil {
		t.Fatal(err)
	}
	if rejected, err = gameSvc.Decide(rejected.ID, false); err != nil {
		t.Fatal(err)
	}

	svc := NewService(gameSvc)
	// The reader liked all three; only the published one may be served.
	svc.SetFavoriteLister(func(string) ([]string, error) {
		return []string{published.ID, reviewing.ID, rejected.ID}, nil
	})

	liked := svc.GamesOf("reader", "liked", "zh")
	if len(liked) != 1 || liked[0].ID != published.ID {
		titles := make([]string, len(liked))
		for i := range liked {
			titles[i] = liked[i].Title
		}
		t.Fatalf("liked list served %v, want only the published game", titles)
	}
}
