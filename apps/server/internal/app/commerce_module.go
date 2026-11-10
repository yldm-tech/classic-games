package app

import (
	"fmt"

	"forgeplay/server/internal/commerce"
	"forgeplay/server/internal/participation"
	"forgeplay/server/internal/payments"
)

type commerceModule struct{}

type CommerceModuleResult struct {
	RecordAction func(string, string, string, int) error
}

func (commerceModule) Name() string { return "commerce" }
func (commerceModule) Dependencies() []string {
	return []string{"identity", "catalog"}
}

func (commerceModule) Install(ctx *moduleContext) error {
	store, err := commerce.NewGormStateStore(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize commerce state store: %w", err)
	}
	service, err := commerce.NewServiceWithStore(store)
	if err != nil {
		return fmt.Errorf("initialize commerce state: %w", err)
	}
	participationRepo, err := participation.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize participation repository: %w", err)
	}
	participationService := participation.NewService(participationRepo, service.EventExists, func(user string) int {
		total := service.AvailableEarnings(user)
		reserved, reservedErr := participationRepo.SumReserved(user)
		if reservedErr != nil || reserved >= total {
			return 0
		}
		return total - reserved
	})
	paymentRepo, err := payments.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize payments repository: %w", err)
	}
	products := []payments.Product{
		{ID: "tier_60", Amount: 600, Currency: "CNY", Kind: "points", Value: 60},
		{ID: "tier_300", Amount: 3000, Currency: "CNY", Kind: "points", Value: 300},
		{ID: "tier_680", Amount: 6800, Currency: "CNY", Kind: "points", Value: 680},
		{ID: "tier_1280", Amount: 12800, Currency: "CNY", Kind: "points", Value: 1280},
		{ID: "plan_monthly", Amount: 1800, Currency: "CNY", Kind: "membership", Value: 1},
		{ID: "plan_yearly", Amount: 16800, Currency: "CNY", Kind: "membership", Value: 1},
	}
	paymentService := payments.NewService(paymentRepo, ctx.cfg.Payments.WebhookSecret, products, func(orderID, user string, product payments.Product) error {
		return service.ApplyPayment(orderID, user, product.Kind, product.Value)
	})
	ctx.catalog.Commerce.SetPublishRecorder(func(user string) error { return service.RecordAction(user, "publish", "", 0) })
	ctx.catalog.Commerce.SetRemixRecorder(func(user string) error { return service.RecordAction(user, "remix", "", 0) })

	commerce.RegisterRoutes(ctx.engine, service, ctx.identity.Optional, ctx.identity.Required)
	participation.RegisterRoutes(ctx.engine, participationService, ctx.identity.Required)
	payments.RegisterRoutes(ctx.engine, paymentService, ctx.identity.Required)
	ctx.commerce = &CommerceModuleResult{RecordAction: service.RecordAction}
	return nil
}
