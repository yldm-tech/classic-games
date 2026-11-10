package app

import (
	"fmt"
	"log"
	"time"

	"github.com/yldm-tech/classic-games/apps/server/internal/auth"

	"github.com/gin-gonic/gin"
)

type identityModule struct{}

type IdentityModuleResult struct {
	Required      gin.HandlerFunc
	Optional      gin.HandlerFunc
	AdminRequired gin.HandlerFunc
	UserName      func(string) string
}

func (identityModule) Name() string           { return "identity" }
func (identityModule) Dependencies() []string { return nil }

func (identityModule) Install(ctx *moduleContext) error {
	userRepo, err := auth.NewGormUserRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize user repository: %w", err)
	}
	runtimeStore, err := auth.NewGormRuntimeStore(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize transient state store: %w", err)
	}
	service, err := auth.NewServiceWithRuntimeStore(ctx.codeSender, userRepo, runtimeStore)
	if err != nil {
		return fmt.Errorf("initialize transient state: %w", err)
	}
	oauthConfigs := make(map[string]auth.OAuthProviderConfig, len(ctx.cfg.Auth.OAuthProviders))
	for provider, cfg := range ctx.cfg.Auth.OAuthProviders {
		oauthConfigs[provider] = auth.OAuthProviderConfig{URL: cfg.URL, BearerToken: cfg.BearerToken}
	}
	if len(oauthConfigs) > 0 {
		service.SetOAuthVerifier(auth.NewHTTPOAuthVerifier(oauthConfigs, 10*time.Second))
	}
	if len(ctx.cfg.Auth.AdminIDs) > 0 {
		service.SetAdmins(ctx.cfg.Auth.AdminIDs...)
	} else {
		log.Print("auth: 未设 CLASSIC_GAMES_ADMIN_IDS,审核裁决端点将拒绝所有请求(403)")
	}
	if ctx.cfg.Auth.DevAdmin {
		service.SetDevAdmin(true)
		log.Print("auth: ⚠️ CLASSIC_GAMES_DEV_ADMIN=1,所有登录用户均被当作管理员(仅限 dev,勿用于生产)")
	}
	result := &IdentityModuleResult{
		Required:      auth.Required(service),
		Optional:      auth.Optional(service),
		AdminRequired: auth.RequireAdmin(service),
		UserName: func(id string) string {
			user, lookupErr := service.User(id)
			if lookupErr != nil {
				return ""
			}
			return user.Nickname
		},
	}
	auth.RegisterRoutes(ctx.engine, service)
	ctx.identity = result
	return nil
}
