package games

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"forgeplay/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "forgeplay/server/pkg/httpx"
)

// RegisterRoutes 挂载 games 端点(docs/09-api-design.md)。
// 读接口公开;发布套 authMW(作者=登录用户);审核裁决套 adminMW(仅管理员)。
// authMW/adminMW 可为 nil(测试/无鉴权场景)。
func RegisterRoutes(r gin.IRouter, svc *Service, authMW, adminMW gin.HandlerFunc, optionalMW ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if len(optionalMW) > 0 && optionalMW[0] != nil {
		g.Use(optionalMW[0])
	}
	g.GET("/games", listPublished(svc))
	g.GET("/games/:id", getGame(svc))

	w := r.Group("/api/v1")
	if authMW != nil {
		w.Use(authMW)
	}
	w.GET("/games/mine", listMine(svc))
	w.POST("/games", publish(svc))
	w.POST("/games/:id/delist", delist(svc))
	w.POST("/games/:id/resubmit", resubmit(svc))

	a := r.Group("/api/v1")
	if adminMW != nil {
		a.Use(adminMW)
	}
	a.POST("/games/:id/decision", decide(svc)) // moderation(admin)
	a.GET("/moderation/queue", moderationQueue(svc))
}

// listMine godoc
// @Summary  我的作品(各审核状态:published/reviewing/rejected/delisted)
// @Tags     games
// @Produce  json
// @Param    lang  query  string  false  "展示语言 zh/en/ja(默认 zh)"
// @Success  200   {object}  map[string]interface{}
// @Failure  500   {object}  httpx.Envelope
// @Router   /games/mine [get]
func listMine(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, err := svc.ListMine(c.GetString("user_id"))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": LocalizeAll(items, langOf(c))})
	}
}

// moderationQueue godoc
// @Summary  审核队列(仅 reviewing,admin,游标分页)
// @Tags     games
// @Produce  json
// @Param    cursor  query  string  false  "游标"
// @Param    limit   query  int     false  "每页"
// @Success  200     {object}  map[string]interface{}
// @Failure  400     {object}  httpx.Envelope
// @Router   /moderation/queue [get]
func moderationQueue(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		limit, _ := strconv.Atoi(c.Query("limit"))
		items, next, err := svc.ListReviewingPage(c.Query("cursor"), limit)
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": LocalizeAll(items, langOf(c)), "next_cursor": next})
	}
}

// publish godoc
// @Summary  发布游戏(进审核)
// @Tags     games
// @Accept   json
// @Produce  json
// @Param    body  body      PublishRequest  true  "mod_id / title / ..."
// @Success  201   {object}  Game
// @Router   /games [post]
func publish(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req PublishRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		req.AuthorID = c.GetString("user_id") // 作者=登录用户,覆盖 body,避免伪造
		g, err := svc.Publish(req)
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "PUBLISH_INVALID", err.Error())
			return
		}
		c.JSON(http.StatusCreated, g)
	}
}

// getGame godoc
// @Summary  游戏详情
// @Tags     games
// @Produce  json
// @Param    id   path      string  true  "game id"
// @Success  200  {object}  Game
// @Failure  404  {object}  httpx.Envelope
// @Router   /games/{id} [get]
func getGame(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, err := svc.Get(c.Param("id"))
		if err != nil {
			writeErr(c, err)
			return
		}
		// 非已发布态(reviewing/rejected/delisted)仅作者本人可见,与 compositionGame 的门控一致;
		// 否则未发布/被下架的内容会经详情接口对任何持有 id 的人公开。
		if g.Status != StatusPublished && c.GetString("user_id") != g.AuthorID {
			i18n.WriteErrorDetail(c, http.StatusNotFound, "NOT_FOUND", ErrNotFound.Error())
			return
		}
		gv := g.Localized(langOf(c))
		// 点赞数以 social 为单一真相源(种子基数 + 真实点赞),覆盖库里的静态展示值,
		// 与 /ranking、/like 保持一致。
		if svc.likes != nil {
			if n, e := svc.likes.LikeCount(gv.ID); e == nil {
				gv.Likes = n
			}
		}
		c.JSON(http.StatusOK, gv)
	}
}

// langOf 解析请求语言:?lang= 优先,其次 Accept-Language,最后默认 zh(走 i18n 统一规则)。
func langOf(c *gin.Context) string { return i18n.Lang(c) }

// listPublished godoc
// @Summary  已发布游戏列表(游标分页)
// @Tags     games
// @Produce  json
// @Param    cursor  query     string  false  "游标"
// @Param    limit   query     int     false  "每页"
// @Success  200     {object}  map[string]interface{}
// @Router   /games [get]
func listPublished(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		limit, _ := strconv.Atoi(c.Query("limit"))
		var items []Game
		var next string
		var err error
		category := c.Query("category")
		if category == "" {
			category = c.Query("cat")
		}
		var aiFilter *bool
		if raw := c.Query("ai"); raw != "" {
			value, parseErr := strconv.ParseBool(raw)
			if parseErr != nil {
				i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", "ai 必须是 true 或 false")
				return
			}
			aiFilter = &value
		}
		if c.Query("runtime") != "" || category != "" || c.Query("sort") != "" || c.Query("q") != "" || aiFilter != nil {
			items, next, err = svc.ListPublishedQueryPage(c.Query("cursor"), limit, c.Query("runtime"), category, c.Query("sort"), c.Query("q"), aiFilter)
		} else {
			items, next, err = svc.ListPublishedPage(c.Query("cursor"), limit)
		}
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		out := LocalizeAll(items, langOf(c))
		if svc.hidden != nil && c.GetString("user_id") != "" {
			visible := out[:0]
			for _, item := range out {
				hidden, e := svc.hidden.IsGameHidden(c.GetString("user_id"), item.ID)
				if e != nil {
					i18n.WriteErrorDetail(c, 500, "INTERNAL", e.Error())
					return
				}
				if !hidden {
					visible = append(visible, item)
				}
			}
			out = visible
		}
		// 列表点赞数同样以 social 为准(批量一次取,避免 N+1)。
		if svc.likes != nil {
			ids := make([]string, len(out))
			for i := range out {
				ids[i] = out[i].ID
			}
			if counts, e := svc.likes.LikeCounts(ids); e == nil {
				for i := range out {
					out[i].Likes = counts[out[i].ID]
				}
			}
		}
		c.JSON(http.StatusOK, gin.H{"items": out, "next_cursor": next})
	}
}

// decide godoc
// @Summary  审核裁决(admin)
// @Tags     games
// @Accept   json
// @Produce  json
// @Param    id    path      string  true  "game id"
// @Success  200   {object}  Game
// @Failure  409   {object}  httpx.Envelope  "INVALID_STATE"
// @Router   /games/{id}/decision [post]
func decide(svc *Service) gin.HandlerFunc {
	type body struct {
		Approve bool `json:"approve"`
	}
	return func(c *gin.Context) {
		var b body
		if err := c.ShouldBindJSON(&b); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		g, err := svc.Decide(c.Param("id"), b.Approve)
		if err != nil {
			writeErr(c, err)
			return
		}
		c.JSON(http.StatusOK, g)
	}
}

// delist godoc
// @Summary  作者下架自己已发布的作品
// @Tags     games
// @Produce  json
// @Param    id  path  string  true  "game id"
// @Success  200  {object}  Game
// @Failure  403  {object}  httpx.Envelope  "FORBIDDEN"
// @Failure  404  {object}  httpx.Envelope  "NOT_FOUND"
// @Failure  409  {object}  httpx.Envelope  "INVALID_STATE"
// @Router   /games/{id}/delist [post]
func delist(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, err := svc.DelistByAuthor(c.Param("id"), c.GetString("user_id"))
		if err != nil {
			writeErr(c, err)
			return
		}
		c.JSON(http.StatusOK, g)
	}
}

// resubmit godoc
// @Summary  作者将被拒作品重新提交(回到审核中)
// @Tags     games
// @Produce  json
// @Param    id  path  string  true  "game id"
// @Success  200  {object}  Game
// @Failure  403  {object}  httpx.Envelope  "FORBIDDEN"
// @Failure  404  {object}  httpx.Envelope  "NOT_FOUND"
// @Failure  409  {object}  httpx.Envelope  "INVALID_STATE"
// @Router   /games/{id}/resubmit [post]
func resubmit(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, err := svc.ResubmitByAuthor(c.Param("id"), c.GetString("user_id"))
		if err != nil {
			writeErr(c, err)
			return
		}
		c.JSON(http.StatusOK, g)
	}
}

func writeErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		i18n.WriteErrorDetail(c, http.StatusNotFound, "NOT_FOUND", err.Error())
	case errors.Is(err, ErrInvalidState):
		i18n.WriteErrorDetail(c, http.StatusConflict, "INVALID_STATE", err.Error())
	case errors.Is(err, ErrForbidden):
		i18n.WriteErrorDetail(c, http.StatusForbidden, "FORBIDDEN", err.Error())
	default:
		i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
	}
}
