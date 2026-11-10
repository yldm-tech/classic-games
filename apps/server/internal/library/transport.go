package library

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"
)

// RegisterRoutes 挂载「我的库」端点(docs/09-api-design.md)。
// 均为读接口,公开;按 ?lang= 取展示语言(zh/en/ja,未知兜底 zh)。
func RegisterRoutes(r gin.IRouter, svc *Service, middleware ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if len(middleware) > 0 && middleware[0] != nil {
		g.Use(middleware[0])
	}
	g.GET("/downloads", listDownloads(svc))
	g.GET("/history", listHistory(svc))
	g.GET("/live", listLive(svc))
	w := r.Group("/api/v1")
	if len(middleware) > 1 && middleware[1] != nil {
		w.Use(middleware[1])
	}
	w.POST("/downloads/:gameId/update", updateDownload(svc))
	w.DELETE("/downloads/:gameId", removeDownload(svc))
	w.DELETE("/history", clearHistory(svc))
	w.POST("/games/:id/played", recordPlay(svc))
}

// recordPlay godoc
// @Summary  记录一次游玩(时长上报)
// @Tags     library
// @Accept   json
// @Produce  json
// @Param    id  path      string  true  "游戏 id"
// @Success  200  {object}  map[string]bool  "recorded"
// @Failure  400  {object}  map[string]interface{}  "BAD_REQUEST(duration_ms 非法)"
// @Failure  404  {object}  map[string]interface{}  "NOT_FOUND"
// @Router   /games/{id}/played [post]
func recordPlay(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var body struct {
			DurationMS int `json:"duration_ms"`
		}
		if c.ShouldBindJSON(&body) != nil || body.DurationMS < 0 {
			c.JSON(400, gin.H{"error": gin.H{"code": "BAD_REQUEST", "message": "invalid duration_ms"}})
			return
		}
		if err := svc.RecordPlay(c.GetString("user_id"), c.Param("id"), body.DurationMS); err != nil {
			if errors.Is(err, ErrNotFound) {
				c.JSON(404, gin.H{"error": gin.H{"code": "NOT_FOUND", "message": err.Error()}})
				return
			}
			c.JSON(403, gin.H{"error": gin.H{"code": "TEEN_BLOCKED", "message": err.Error()}})
			return
		}
		c.JSON(200, gin.H{"recorded": true})
	}
}

// listDownloads godoc
// @Summary  我的下载(已下游戏 + 大小 + 是否有更新)
// @Tags     library
// @Produce  json
// @Param    lang  query     string  false  "展示语言 zh/en/ja"
// @Success  200   {object}  map[string]interface{}
// @Router   /downloads [get]
func listDownloads(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items := svc.DownloadsFor(c.GetString("user_id"), i18n.Lang(c))
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// listHistory godoc
// @Summary  最近玩过(按今天/昨天/更早分组)
// @Tags     library
// @Produce  json
// @Param    lang  query     string  false  "展示语言 zh/en/ja"
// @Success  200   {object}  map[string]interface{}
// @Router   /history [get]
func listHistory(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		groups := svc.HistoryFor(c.GetString("user_id"), i18n.Lang(c))
		c.JSON(http.StatusOK, gin.H{"groups": groups})
	}
}

// updateDownload godoc
// @Summary  标记下载已更新到最新版本
// @Tags     library
// @Produce  json
// @Param    gameId  path      string  true  "游戏 id"
// @Success  200  {object}  map[string]bool  "updated"
// @Failure  404  {object}  map[string]interface{}  "NOT_FOUND"
// @Router   /downloads/{gameId}/update [post]
func updateDownload(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.MarkDownloadUpdated(c.GetString("user_id"), c.Param("gameId")); err != nil {
			c.JSON(404, gin.H{"error": gin.H{"code": "NOT_FOUND", "message": err.Error()}})
			return
		}
		c.JSON(200, gin.H{"updated": true})
	}
}

// removeDownload godoc
// @Summary  删除下载记录
// @Tags     library
// @Produce  json
// @Param    gameId  path  string  true  "游戏 id"
// @Success  204  "无内容"
// @Failure  404  {object}  map[string]interface{}  "NOT_FOUND"
// @Router   /downloads/{gameId} [delete]
func removeDownload(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.RemoveDownload(c.GetString("user_id"), c.Param("gameId")); err != nil {
			c.JSON(404, gin.H{"error": gin.H{"code": "NOT_FOUND", "message": err.Error()}})
			return
		}
		c.Status(http.StatusNoContent)
	}
}

// clearHistory godoc
// @Summary  清空最近玩过记录
// @Tags     library
// @Produce  json
// @Success  204  "无内容"
// @Failure  500  {object}  map[string]interface{}  "INTERNAL"
// @Router   /history [delete]
func clearHistory(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if e := svc.ClearHistory(c.GetString("user_id")); e != nil {
			c.JSON(500, gin.H{"error": gin.H{"code": "INTERNAL", "message": e.Error()}})
			return
		}
		c.Status(http.StatusNoContent)
	}
}

// listLive godoc
// @Summary  正在直播(游戏 + 主播 + 在看人数 + 标语)
// @Tags     library
// @Produce  json
// @Param    lang  query     string  false  "展示语言 zh/en/ja"
// @Success  200   {object}  map[string]interface{}
// @Router   /live [get]
func listLive(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items := svc.LiveFor(c.GetString("user_id"), i18n.Lang(c))
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}
