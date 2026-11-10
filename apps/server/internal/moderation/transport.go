package moderation

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

// RegisterRoutes 挂载举报/屏蔽端点(docs/09-api-design.md moderation)。
// 全是写操作:套 authMW,操作者身份从 token 注入的 user_id 取,不信任 body。
func RegisterRoutes(r gin.IRouter, svc *Service, authMW ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	g.Use(authMW...)
	g.GET("/blocks", listBlocks(svc)) // 真实黑名单(取代 prefs 的种子 /blocks)
	g.POST("/report", report(svc))
	g.POST("/block/:userId", block(svc))
	g.DELETE("/block/:userId", unblock(svc))
	g.POST("/games/:id/not-interested", hideGame(svc))
}

// hideGame godoc
// @Summary  对某游戏标记"不感兴趣"(从列表隐藏)
// @Tags     moderation
// @Produce  json
// @Param    id  path  string  true  "game id"
// @Success  200  {object}  map[string]bool
// @Failure  400  {object}  httpx.Envelope
// @Router   /games/{id}/not-interested [post]
func hideGame(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.HideGame(c.GetString("user_id"), c.Param("id")); err != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"hidden": true})
	}
}

// listBlocks godoc
// @Summary  我的黑名单(已屏蔽用户)
// @Tags     moderation
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "items: [{user_id}]"
// @Router   /blocks [get]
func listBlocks(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, err := svc.ListBlockEntries(c.GetString("user_id"))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// report godoc
// @Summary  举报(游戏/评论/用户)
// @Tags     moderation
// @Accept   json
// @Produce  json
// @Success  201  {object}  Report
// @Failure  400  {object}  httpx.Envelope
// @Router   /report [post]
func report(svc *Service) gin.HandlerFunc {
	type req struct {
		TargetType TargetType `json:"target_type"`
		TargetID   string     `json:"target_id"`
		Reason     string     `json:"reason"`
	}
	return func(c *gin.Context) {
		var b req
		if err := c.ShouldBindJSON(&b); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		// 举报人=已登录用户(token),不取 body。
		rep, err := svc.Report(c.GetString("user_id"), b.TargetType, b.TargetID, b.Reason)
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "REPORT_INVALID", err.Error())
			return
		}
		c.JSON(http.StatusCreated, rep)
	}
}

// block godoc
// @Summary  屏蔽用户
// @Tags     moderation
// @Accept   json
// @Produce  json
// @Param    userId  path  string  true  "被屏蔽用户 id"
// @Success  200  {object}  map[string]bool
// @Router   /block/{userId} [post]
func block(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 屏蔽发起人=已登录用户(token)。
		if err := svc.Block(c.GetString("user_id"), c.Param("userId")); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"blocked": true})
	}
}

// unblock godoc
// @Summary  取消屏蔽
// @Tags     moderation
// @Accept   json
// @Produce  json
// @Param    userId  path  string  true  "被屏蔽用户 id"
// @Success  200  {object}  map[string]bool
// @Router   /block/{userId} [delete]
func unblock(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.Unblock(c.GetString("user_id"), c.Param("userId")); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"blocked": false})
	}
}
