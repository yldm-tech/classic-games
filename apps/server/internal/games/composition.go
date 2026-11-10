package games

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/internal/mods"
	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"
)

// ModGateway keeps the public game resource API while delegating DSL lineage storage to mods.
type ModGateway interface {
	EffectiveDSL(string) (map[string]any, error)
	ForkFor(authorID, modID string) (mods.Mod, error)
	Lineage(modID, viewer string) ([]mods.Mod, error)
	ForkTree(modID, viewer string) (mods.ForkTreeView, error)
}

type DraftGateway interface {
	Get(string) (mods.Mod, error)
	SetDraft(id string, draft bool) error
}

func RegisterDraftPublishRoutes(r gin.IRouter, games *Service, drafts DraftGateway, authMW ...gin.HandlerFunc) {
	g := r.Group("/api/v1/drafts")
	g.Use(authMW...)
	g.POST("/:id/publish", func(c *gin.Context) {
		mod, err := drafts.Get(c.Param("id"))
		if err != nil {
			writeComposition(c, nil, err, 0)
			return
		}
		if !mod.Draft {
			httpx.WriteError(c, http.StatusConflict, "INVALID_STATE", "目标不是草稿")
			return
		}
		if mod.AuthorID == "" || mod.AuthorID != c.GetString("user_id") {
			httpx.WriteError(c, http.StatusForbidden, "FORBIDDEN", "无权发布该草稿")
			return
		}
		var req PublishRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", err.Error())
			return
		}
		req.ModID, req.AuthorID = mod.ID, c.GetString("user_id")
		// 发布前清除草稿标记,让其他用户可 Fork 由该草稿发布出的游戏
		// (ForkFor 会拒绝 parent.Draft 的外部 Fork)。清标记本身失败则整体失败,尚未发布。
		if err := drafts.SetDraft(mod.ID, false); err != nil {
			httpx.WriteError(c, http.StatusInternalServerError, "INTERNAL", "failed to publish draft")
			return
		}
		game, err := games.Publish(req)
		if err != nil {
			// 发布失败:回滚草稿标记,使草稿保持可编辑/可重试(Publish 非幂等,不能发布后再回滚)。
			_ = drafts.SetDraft(mod.ID, true)
			httpx.WriteError(c, 400, "PUBLISH_INVALID", err.Error())
			return
		}
		c.JSON(http.StatusCreated, game)
	})
}

func RegisterCompositionRoutes(r gin.IRouter, games *Service, modGateway ModGateway, authMW ...gin.HandlerFunc) {
	g := r.Group("/api/v1/games/:id")
	if len(authMW) > 1 && authMW[1] != nil {
		g.Use(authMW[1])
	}
	g.GET("/dsl", func(c *gin.Context) {
		game, ok := compositionGame(c, games)
		if !ok {
			return
		}
		value, err := modGateway.EffectiveDSL(game.ModID)
		writeGameComposition(c, value, err, http.StatusOK)
	})
	g.GET("/lineage", func(c *gin.Context) {
		game, ok := compositionGame(c, games)
		if !ok {
			return
		}
		value, err := modGateway.Lineage(game.ModID, c.GetString("user_id"))
		writeGameComposition(c, gin.H{"items": value}, err, http.StatusOK)
	})
	g.GET("/fork-tree", func(c *gin.Context) {
		game, ok := compositionGame(c, games)
		if !ok {
			return
		}
		value, err := modGateway.ForkTree(game.ModID, c.GetString("user_id"))
		writeGameComposition(c, value, err, http.StatusOK)
	})
	w := r.Group("/api/v1/games/:id")
	if len(authMW) > 0 && authMW[0] != nil {
		w.Use(authMW[0])
	}
	w.POST("/fork", func(c *gin.Context) {
		game, ok := compositionGame(c, games)
		if !ok {
			return
		}
		value, err := modGateway.ForkFor(c.GetString("user_id"), game.ModID)
		if err == nil {
			err = games.IncrementForks(game.ID)
		}
		if err == nil && games.onRemix != nil {
			_ = games.onRemix(c.GetString("user_id"))
		}
		writeGameComposition(c, value, err, http.StatusCreated)
	})
}

func compositionGame(c *gin.Context, svc *Service) (Game, bool) {
	game, err := svc.Get(c.Param("id"))
	if err != nil {
		writeErr(c, err)
		return Game{}, false
	}
	if game.Status != StatusPublished && (c.GetString("user_id") == "" || c.GetString("user_id") != game.AuthorID) {
		httpx.WriteError(c, http.StatusNotFound, "NOT_FOUND", ErrNotFound.Error())
		return Game{}, false
	}
	if game.ModID == "" {
		writeNoMod(c)
		return Game{}, false
	}
	return game, true
}

// writeGameComposition answers a request that resolved a game to its mod. The game exists at this point, so a mod the gateway cannot find means the game has no mod behind it, not that the game is missing: rows seeded before showcase entries stopped carrying a placeholder mod_id are in that state. It gets the same answer as an empty mod_id.
func writeGameComposition(c *gin.Context, value any, err error, status int) {
	if err == mods.ErrNotFound {
		writeNoMod(c)
		return
	}
	writeComposition(c, value, err, status)
}

// writeNoMod keeps the 404 status the routes always gave for these games and replaces the generic code with one that tells "this game cannot be read or forked" apart from "no such game".
func writeNoMod(c *gin.Context) {
	i18n.WriteError(c, http.StatusNotFound, "GAME_HAS_NO_MOD")
}

func writeComposition(c *gin.Context, value any, err error, status int) {
	if err != nil {
		if err == mods.ErrNotFound {
			httpx.WriteError(c, http.StatusNotFound, "NOT_FOUND", err.Error())
		} else {
			httpx.WriteError(c, http.StatusUnprocessableEntity, "DSL_INVALID", err.Error())
		}
		return
	}
	c.JSON(status, value)
}
