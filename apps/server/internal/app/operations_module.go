package app

import (
	"fmt"
	"time"

	"github.com/yldm-tech/classic-games/apps/server/internal/analytics"
	"github.com/yldm-tech/classic-games/apps/server/internal/feedback"
	"github.com/yldm-tech/classic-games/apps/server/internal/meta"
	"github.com/yldm-tech/classic-games/apps/server/internal/prefs"
)

type operationsModule struct{}
type OperationsModuleResult struct{}

func (operationsModule) Name() string { return "operations" }
func (operationsModule) Dependencies() []string {
	return []string{"identity", "catalog", "community", "engagement"}
}

func (operationsModule) Install(ctx *moduleContext) error {
	prefsStore, err := prefs.NewGormStateStore(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize preferences state store: %w", err)
	}
	prefsService, err := prefs.NewServiceWithStore(prefsStore)
	if err != nil {
		return fmt.Errorf("initialize preferences state: %w", err)
	}
	analyticsRepo, err := analytics.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize analytics repository: %w", err)
	}
	analyticsService := analytics.NewService(analyticsRepo)
	ctx.catalog.Operations.SetViewCounter(func(ids []string) (map[string]int, error) {
		return analyticsService.CountByTarget(analytics.GameViewed, ids)
	})
	feedbackRepo, err := feedback.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize feedback repository: %w", err)
	}
	feedbackService := feedback.NewService(feedbackRepo)
	feedbackService.SetModerator(ctx.community.Moderator)

	prefs.RegisterRoutes(ctx.engine, prefsService, ctx.identity.Optional, ctx.identity.Required)
	analytics.RegisterRoutes(ctx.engine, analyticsService, ctx.identity.Optional, ctx.identity.AdminRequired)
	feedback.RegisterRoutes(ctx.engine, feedbackService, ctx.identity.Required)
	meta.RegisterRoutes(ctx.engine, ctx.cfg.PublicCapabilities)
	if ctx.engagement != nil && ctx.engagement.SetPlayGuard != nil {
		ctx.engagement.SetPlayGuard(func(userID string, extraSeconds int) error {
			return prefsService.GuardPlay(userID, extraSeconds, time.Now())
		})
	}
	ctx.operations = &OperationsModuleResult{}
	return nil
}
