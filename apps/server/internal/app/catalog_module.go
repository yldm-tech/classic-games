package app

import (
	"fmt"
	"log"
	"time"

	"forgeplay/server/internal/games"
	"forgeplay/server/internal/library"
	"forgeplay/server/internal/ranking"
	"forgeplay/server/internal/users"
)

type catalogModule struct{}

type lateLikeSource struct{ delegate ranking.LikeSource }

func (s *lateLikeSource) LikeCounts(ids []string) (map[string]int, error) {
	if s.delegate == nil {
		return nil, fmt.Errorf("catalog like source is not connected")
	}
	return s.delegate.LikeCounts(ids)
}
func (s *lateLikeSource) RecentLikeCounts(ids []string, since time.Time) (map[string]int, error) {
	if s.delegate == nil {
		return nil, fmt.Errorf("catalog like source is not connected")
	}
	return s.delegate.RecentLikeCounts(ids, since)
}

// showcaseGatedGames is the game source handed to the library domain. The library asks its source to make sure the showcase catalogue is loaded; this keeps that request behind the same environment decision as the seed in Install.
type showcaseGatedGames struct {
	library.GameSource
	seed bool
}

func (g showcaseGatedGames) EnsureSeeds() error {
	if !g.seed {
		return nil
	}
	return g.GameSource.EnsureSeeds()
}

type CatalogModuleResult struct {
	Community  CatalogCommunityPort
	Commerce   CatalogCommercePort
	Engagement CatalogEngagementPort
	Operations CatalogOperationsPort
}

type CatalogCommunityPort struct {
	PublishedGames           func() ([]games.Game, error)
	SetGameHiddenChecker     func(games.HiddenChecker)
	SetGameLikeCounter       func(games.LikeCounter)
	SetUserLikeCounter       func(games.LikeCounter)
	SetFavoriteLister        func(func(string) ([]string, error))
	SetFollowCounter         func(func(string) int)
	ConnectRankingLikeSource func(ranking.LikeSource)
	SetRankingHiddenChecker  func(games.HiddenChecker)
	SetTop10Recorder         func(func(string) error)
}

type CatalogCommercePort struct {
	SetPublishRecorder func(func(string) error)
	SetRemixRecorder   func(func(string) error)
}

type CatalogEngagementPort struct {
	Games   library.GameSource
	GetGame func(string) (games.Game, error)
}

type CatalogOperationsPort struct {
	SetViewCounter func(func([]string) (map[string]int, error))
}

func (catalogModule) Name() string           { return "catalog" }
func (catalogModule) Dependencies() []string { return []string{"identity", "creation"} }

func (catalogModule) Install(ctx *moduleContext) error {
	repository, err := games.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize games repository: %w", err)
	}
	gameService := games.NewService(repository)
	gameService.SetModProvenance(ctx.creation.IsAIGenerated)
	gameService.SetModRuntime(ctx.creation.Runtime)
	gameService.SetModOwner(ctx.creation.Owner)
	gameService.SetModValidator(ctx.creation.Validate)
	if count, backfillErr := gameService.BackfillMissingRuntime(); backfillErr != nil {
		return fmt.Errorf("backfill games runtime: %w", backfillErr)
	} else if count > 0 {
		log.Printf("games runtime 已回填 %d 条", count)
	}
	// The showcase catalogue carries invented play, fork and like counts and entries without a mod, so only a development backend gets it. A production database starts with an empty catalogue.
	seedShowcase := ctx.cfg.Environment == Development
	if seedShowcase {
		if err := games.Seed(repository); err != nil {
			return fmt.Errorf("seed games: %w", err)
		}
	}
	gameService.SetAuthorName(ctx.identity.UserName)

	userStore, err := users.NewGormStateStore(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize users state store: %w", err)
	}
	userService, err := users.NewServiceWithStore(gameService, userStore, []byte(ctx.cfg.Security.Secret))
	if err != nil {
		return fmt.Errorf("initialize users state: %w", err)
	}
	likes := &lateLikeSource{}
	rankService := ranking.NewService(gameService, likes)

	games.RegisterRoutes(ctx.engine, gameService, ctx.identity.Required, ctx.identity.AdminRequired, ctx.identity.Optional)
	games.RegisterCompositionRoutes(ctx.engine, gameService, ctx.creation.ModGateway, ctx.identity.Required, ctx.identity.Optional)
	games.RegisterDraftPublishRoutes(ctx.engine, gameService, ctx.creation.DraftGateway, ctx.identity.Required)
	users.RegisterRoutes(ctx.engine, userService, ctx.identity.Required, ctx.identity.AdminRequired)
	ranking.RegisterRoutes(ctx.engine, rankService, ctx.identity.Optional)
	ctx.catalog = &CatalogModuleResult{
		Community: CatalogCommunityPort{
			PublishedGames:           gameService.ListPublished,
			SetGameHiddenChecker:     gameService.SetHiddenChecker,
			SetGameLikeCounter:       gameService.SetLikeCounter,
			SetUserLikeCounter:       userService.SetLikeCounter,
			SetFavoriteLister:        userService.SetFavoriteLister,
			SetFollowCounter:         userService.SetFollowCounter,
			ConnectRankingLikeSource: func(source ranking.LikeSource) { likes.delegate = source },
			SetRankingHiddenChecker:  func(checker games.HiddenChecker) { rankService.SetHiddenChecker(checker) },
			SetTop10Recorder:         rankService.SetTop10Recorder,
		},
		Commerce: CatalogCommercePort{
			SetPublishRecorder: gameService.SetPublishRecorder,
			SetRemixRecorder:   gameService.SetRemixRecorder,
		},
		Engagement: CatalogEngagementPort{Games: showcaseGatedGames{GameSource: gameService, seed: seedShowcase}, GetGame: gameService.Get},
		Operations: CatalogOperationsPort{SetViewCounter: gameService.SetViewCounter},
	}
	return nil
}
