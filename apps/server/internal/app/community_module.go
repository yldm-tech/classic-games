package app

import (
	"fmt"
	"log"
	"time"

	"forgeplay/server/internal/community"
	"forgeplay/server/internal/inbox"
	"forgeplay/server/internal/moderation"
	"forgeplay/server/internal/social"
)

type communityModule struct{}

type CommunityModuleResult struct {
	Moderator social.TextModerator
}

func (communityModule) Name() string { return "community" }
func (communityModule) Dependencies() []string {
	return []string{"identity", "catalog", "commerce"}
}

func (communityModule) Install(ctx *moduleContext) error {
	inboxStore, err := inbox.NewGormStateStore(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize inbox state store: %w", err)
	}
	inboxService, err := inbox.NewServiceWithStore(inboxStore)
	if err != nil {
		return fmt.Errorf("initialize inbox state: %w", err)
	}
	socialRepo, err := social.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize social repository: %w", err)
	}
	socialService := social.NewService(socialRepo)
	moderator, err := buildTextModerator(ctx.cfg)
	if err != nil {
		return err
	}
	socialService.SetModerator(moderator)
	moderationRepo, err := moderation.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize moderation repository: %w", err)
	}
	moderationService := moderation.NewService(moderationRepo)
	socialService.SetBlockLister(moderationService)
	communityRepo, err := community.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize community repository: %w", err)
	}
	communityService := community.NewService(communityRepo)
	communityService.SetModerator(moderator)
	communityService.SetBlockLister(moderationService)

	if seeded, listErr := ctx.catalog.Community.PublishedGames(); listErr == nil {
		for _, game := range seeded {
			if game.Likes > 0 {
				if setErr := socialService.SetBaseLikes(game.ID, game.Likes); setErr != nil {
					log.Printf("social 点赞基数灌入失败 %s: %v", game.ID, setErr)
				}
			}
		}
	}
	ctx.catalog.Community.SetGameHiddenChecker(moderationService)
	ctx.catalog.Community.SetGameLikeCounter(socialService)
	ctx.catalog.Community.SetUserLikeCounter(socialService)
	ctx.catalog.Community.SetFavoriteLister(socialService.Favorites)
	ctx.catalog.Community.SetFollowCounter(func(handle string) int { return len(inboxService.FollowersOf(handle)) })
	ctx.catalog.Community.ConnectRankingLikeSource(socialService)
	ctx.catalog.Community.SetRankingHiddenChecker(moderationService)
	ctx.catalog.Community.SetTop10Recorder(func(user string) error { return ctx.commerce.RecordAction(user, "weekly_top10", "", 1) })
	socialService.SetCommentRecorder(func(user string) error { return ctx.commerce.RecordAction(user, "comment", "", 0) })
	inboxService.SetFriendRecorder(func(user string) error { return ctx.commerce.RecordAction(user, "friend", "", 0) })

	social.RegisterRoutes(ctx.engine, socialService, ctx.identity.Required, ctx.identity.Optional)
	moderation.RegisterRoutes(ctx.engine, moderationService, ctx.identity.Required)
	inbox.RegisterRoutes(ctx.engine, inboxService, ctx.identity.Optional, ctx.identity.Required)
	community.RegisterRoutes(ctx.engine, communityService, ctx.identity.Optional, ctx.identity.Required)
	ctx.community = &CommunityModuleResult{Moderator: moderator}
	return nil
}

func buildTextModerator(cfg Config) (social.TextModerator, error) {
	var moderator social.TextModerator = social.NewKeywordModerator()
	if path := cfg.Moderation.BlockWordsFile; path != "" {
		fileModerator, err := social.NewKeywordModeratorFile(path)
		if err != nil {
			return nil, fmt.Errorf("load moderation word list: %w", err)
		}
		moderator = fileModerator
		log.Printf("social: 已加载外置内容审核词库 %s", path)
	}
	if url := cfg.Moderation.URL; url != "" {
		moderator = social.ChainModerator{moderator, social.NewHTTPModerator(url, cfg.Moderation.Token, 10*time.Second)}
	}
	return moderator, nil
}
