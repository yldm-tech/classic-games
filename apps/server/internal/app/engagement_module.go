package app

import (
	"fmt"

	"github.com/yldm-tech/classic-games/apps/server/internal/library"
	"github.com/yldm-tech/classic-games/apps/server/internal/replays"
	"github.com/yldm-tech/classic-games/apps/server/internal/rooms"
)

type engagementModule struct{}
type EngagementModuleResult struct {
	SetPlayGuard func(func(string, int) error)
}

func (engagementModule) Name() string { return "engagement" }
func (engagementModule) Dependencies() []string {
	return []string{"identity", "catalog", "commerce"}
}

func (engagementModule) Install(ctx *moduleContext) error {
	libraryStore, err := library.NewGormStateStore(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize library state store: %w", err)
	}
	libraryService, err := library.NewServiceWithStore(ctx.catalog.Engagement.Games, libraryStore)
	if err != nil {
		return fmt.Errorf("initialize library state: %w", err)
	}
	roomRepo, err := rooms.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize rooms repository: %w", err)
	}
	roomService := rooms.NewService(roomRepo)
	replayRepo, err := replays.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize replays repository: %w", err)
	}
	replayService := replays.NewService(replayRepo)
	replayService.SetUserLookup(func(id string) string {
		return ctx.identity.UserName(id)
	})
	replayService.SetScoreResolver(func(_ string, _ string, frames []replays.Frame) (int, bool) {
		return replays.PhysicalScore(frames)
	})
	replayService.SetScoreRecorder(func(user string, score int) error {
		return ctx.commerce.RecordAction(user, "score", "", score)
	})
	libraryService.SetPlayRecorder(func(user, gameID string, totalPlays int) error {
		if err := ctx.commerce.RecordAction(user, "play", gameID, 0); err != nil {
			return err
		}
		if game, getErr := ctx.catalog.Engagement.GetGame(gameID); getErr == nil && game.AuthorID != "" {
			return ctx.commerce.RecordAction(game.AuthorID, "game_plays", gameID, totalPlays)
		}
		return nil
	})

	library.RegisterRoutes(ctx.engine, libraryService, ctx.identity.Optional, ctx.identity.Required)
	rooms.RegisterRoutes(ctx.engine, roomService, ctx.identity.Required)
	replays.RegisterRoutes(ctx.engine, replayService, ctx.identity.Required)
	ctx.engagement = &EngagementModuleResult{
		SetPlayGuard: func(guard func(string, int) error) {
			libraryService.SetPlayGuard(guard)
			roomService.SetPlayGuard(guard)
			replayService.SetPlayGuard(guard)
		},
	}
	return nil
}
