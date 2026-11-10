package games

import (
	_ "embed"
	"encoding/json"
	"time"
)

//go:embed seed/games.json
var seedGamesJSON []byte

type seedGame struct {
	ID      string            `json:"id"`
	Tone    string            `json:"tone"`
	By      string            `json:"by"`
	Plays   int               `json:"plays"`
	Forks   int               `json:"forks"`
	Likes   int               `json:"likes"`
	Cat     string            `json:"cat"`
	AI      bool              `json:"ai"`
	Title   map[string]string `json:"title"`
	Summary map[string]string `json:"summary"`
}

// Seed loads the showcase catalogue: published entries that give /games and /ranking something to return on a development backend. It is idempotent and adds only the seed ids that are not published yet.
//
// A showcase entry is a catalogue card, not a playable mod. ModID and Runtime stay empty, which is how a client recognises a game that cannot be forked, and the DSL, lineage, fork-tree and fork routes answer GAME_HAS_NO_MOD for it. The play, fork and like counts are invented, so the composition root loads the catalogue in development only.
func Seed(repo Repository) error {
	existing, err := repo.ListByStatus(StatusPublished)
	if err != nil {
		return err
	}
	present := map[string]bool{}
	for _, game := range existing {
		present[game.ID] = true
	}
	var seeds []seedGame
	if err := json.Unmarshal(seedGamesJSON, &seeds); err != nil {
		return err
	}
	base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	for i, s := range seeds {
		if present[s.ID] {
			continue
		}
		g := Game{
			ID:          s.ID,
			AuthorID:    s.By,
			By:          s.By,
			Title:       s.Title["zh"],
			Summary:     s.Summary["zh"],
			Status:      StatusPublished,
			AIGenerated: s.AI,
			Tone:        s.Tone,
			Category:    s.Cat,
			Plays:       s.Plays,
			Forks:       s.Forks,
			Likes:       s.Likes,
			TitleI18n:   s.Title,
			SummaryI18n: s.Summary,
			// 错开创建时间,让"新作"榜排序稳定(越靠后越新)
			CreatedAt: base.Add(time.Duration(i) * time.Hour),
		}
		if _, err := repo.Create(g); err != nil {
			return err
		}
	}
	return nil
}
