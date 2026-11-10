package app

import (
	"fmt"

	"forgeplay/server/internal/ai"
	"forgeplay/server/internal/auth"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"gorm.io/gorm"

	_ "forgeplay/server/docs"
)

type moduleInstaller interface {
	Name() string
	Dependencies() []string
	Install(*moduleContext) error
}

type moduleContext struct {
	cfg        Config
	db         *gorm.DB
	provider   ai.LLMProvider
	codeSender auth.CodeSender
	engine     *gin.Engine

	identity   *IdentityModuleResult
	creation   *CreationModuleResult
	catalog    *CatalogModuleResult
	commerce   *CommerceModuleResult
	community  *CommunityModuleResult
	engagement *EngagementModuleResult
	operations *OperationsModuleResult
}

func defaultModuleInstallers() []moduleInstaller {
	return []moduleInstaller{
		identityModule{},
		creationModule{},
		catalogModule{},
		commerceModule{},
		communityModule{},
		engagementModule{},
		operationsModule{},
	}
}

func installModules(ctx *moduleContext, installers []moduleInstaller) error {
	installed := make(map[string]bool, len(installers))
	for _, installer := range installers {
		if installer.Name() == "" || installed[installer.Name()] {
			return fmt.Errorf("module %q: duplicate or empty name", installer.Name())
		}
		for _, dependency := range installer.Dependencies() {
			if !installed[dependency] {
				return fmt.Errorf("module %s: dependency %s is not installed", installer.Name(), dependency)
			}
		}
		if err := installer.Install(ctx); err != nil {
			return fmt.Errorf("module %s: %w", installer.Name(), err)
		}
		installed[installer.Name()] = true
	}
	return nil
}

func assembleModules(cfg Config, db *gorm.DB, provider ai.LLMProvider, codeSender auth.CodeSender) (*gin.Engine, error) {
	engine, err := NewEngine(cfg.HTTP)
	if err != nil {
		return nil, fmt.Errorf("initialize HTTP engine: %w", err)
	}
	engine.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
	ctx := &moduleContext{cfg: cfg, db: db, provider: provider, codeSender: codeSender, engine: engine}
	if err := installModules(ctx, defaultModuleInstallers()); err != nil {
		return nil, err
	}
	return engine, nil
}

func moduleRouteOwners() map[string][]string {
	return map[string][]string{
		"identity": {
			"DELETE /api/v1/users/me", "GET /api/v1/users/me", "GET /api/v1/users/me/security",
			"POST /api/v1/auth/guest", "POST /api/v1/auth/logout", "POST /api/v1/auth/oauth/:provider",
			"POST /api/v1/auth/oauth/exchange", "POST /api/v1/auth/password/login", "POST /api/v1/auth/refresh",
			"POST /api/v1/auth/sms/send", "POST /api/v1/auth/sms/verify", "POST /api/v1/users/me/oauth/bind",
			"POST /api/v1/users/me/password", "POST /api/v1/users/me/phone",
		},
		"creation": {
			"GET /api/v1/drafts", "GET /api/v1/mods/:id/dsl", "GET /api/v1/mods/:id/fork-tree",
			"GET /api/v1/mods/:id/lineage", "GET /api/v1/mods/mine",
			"GET /api/v1/runtimes/:name/:version/baseline", "GET /api/v1/runtimes/:name/:version/schema",
			"GET /api/v1/ai/quota",
			"POST /api/v1/ai/balance", "POST /api/v1/ai/mod", "POST /api/v1/ai/structure",
			"POST /api/v1/ai/validate", "POST /api/v1/mods", "POST /api/v1/mods/:id/fork", "PUT /api/v1/drafts/:id",
		},
		"catalog": {
			"GET /api/v1/games", "GET /api/v1/games/:id", "GET /api/v1/games/:id/dsl",
			"GET /api/v1/games/:id/fork-tree", "GET /api/v1/games/:id/lineage", "GET /api/v1/games/mine",
			"GET /api/v1/moderation/queue", "GET /api/v1/ranking", "GET /api/v1/users/:id",
			"GET /api/v1/users/:id/games", "GET /api/v1/users/:id/profile", "GET /api/v1/users/me/verification",
			"GET /api/v1/verifications/queue",
			"PATCH /api/v1/users/me", "POST /api/v1/auth/realname", "POST /api/v1/drafts/:id/publish",
			"POST /api/v1/games", "POST /api/v1/games/:id/decision", "POST /api/v1/games/:id/delist",
			"POST /api/v1/games/:id/fork", "POST /api/v1/games/:id/resubmit", "POST /api/v1/users/me/profile",
			"POST /api/v1/users/me/verification", "POST /api/v1/users/:id/verification/decision",
		},
		"commerce": {
			"GET /api/v1/achievements", "GET /api/v1/avatar", "GET /api/v1/earnings/withdrawals", "GET /api/v1/events", "GET /api/v1/events/joined",
			"GET /api/v1/membership", "GET /api/v1/payments/orders", "GET /api/v1/payments/orders/:id", "GET /api/v1/points", "GET /api/v1/shop",
			"GET /api/v1/welfare", "POST /api/v1/achievements/:id/claim", "POST /api/v1/avatar/equip",
			"POST /api/v1/earnings/withdrawals", "POST /api/v1/events/:id/join", "POST /api/v1/live/:id/gift",
			"POST /api/v1/payments/orders", "POST /api/v1/payments/webhook", "POST /api/v1/shop/purchase/:id",
			"POST /api/v1/welfare/checkin", "POST /api/v1/welfare/quests/:id/claim",
		},
		"community": {
			"DELETE /api/v1/block/:userId", "DELETE /api/v1/follow/:handle", "DELETE /api/v1/games/:id/favorite",
			"DELETE /api/v1/games/:id/like", "DELETE /api/v1/users/:id/follow", "GET /api/v1/activity",
			"GET /api/v1/blocks", "GET /api/v1/chats", "GET /api/v1/chats/:idx/messages",
			"GET /api/v1/conversations/:handle/messages", "GET /api/v1/favorites", "GET /api/v1/follow",
			"GET /api/v1/friends/suggestions", "GET /api/v1/games/:id/comments", "GET /api/v1/games/:id/community",
			"GET /api/v1/messages/:idx", "GET /api/v1/messages/conversations", "GET /api/v1/users/:id/followers",
			"GET /api/v1/users/:id/following", "POST /api/v1/block/:userId", "POST /api/v1/chats/:idx/messages",
			"POST /api/v1/conversations/:handle/messages", "POST /api/v1/follow/:handle", "POST /api/v1/friends/:handle",
			"POST /api/v1/games/:id/comments", "POST /api/v1/games/:id/community/posts",
			"POST /api/v1/games/:id/community/rating", "POST /api/v1/games/:id/favorite",
			"POST /api/v1/games/:id/like", "POST /api/v1/games/:id/not-interested", "POST /api/v1/messages/:idx",
			"POST /api/v1/report", "POST /api/v1/users/:id/follow",
		},
		"engagement": {
			"DELETE /api/v1/downloads/:gameId", "DELETE /api/v1/history", "GET /api/v1/downloads",
			"GET /api/v1/games/:id/replays/:user", "GET /api/v1/games/:id/replays/leaderboard", "GET /api/v1/history",
			"GET /api/v1/live", "GET /api/v1/rooms/:id", "GET /api/v1/rooms/:id/snapshot",
			"POST /api/v1/downloads/:gameId/update", "POST /api/v1/games/:id/played", "POST /api/v1/games/:id/replays",
			"POST /api/v1/rooms", "POST /api/v1/rooms/:id/input", "POST /api/v1/rooms/:id/ready",
			"POST /api/v1/rooms/:id/start", "POST /api/v1/rooms/join",
		},
		"operations": {
			"GET /api/v1/analytics/summary", "GET /api/v1/meta", "GET /api/v1/prefs/notifications", "GET /api/v1/prefs/privacy",
			"GET /api/v1/prefs/teen", "POST /api/v1/analytics/events", "POST /api/v1/feedback",
			"POST /api/v1/prefs/notifications/:key", "POST /api/v1/prefs/privacy/:key", "POST /api/v1/prefs/teen",
		},
	}
}
