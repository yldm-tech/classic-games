package analytics

import (
	"net/http"

	"forgeplay/server/pkg/httpx"
	"github.com/gin-gonic/gin"
)

func RegisterRoutes(r gin.IRouter, svc *Service, optionalAuth, admin gin.HandlerFunc) {
	track := r.Group("/api/v1")
	if optionalAuth != nil {
		track.Use(optionalAuth)
	}
	track.POST("/analytics/events", record(svc))
	metrics := r.Group("/api/v1")
	if admin != nil {
		metrics.Use(admin)
	}
	metrics.GET("/analytics/summary", summary(svc))
}

// record godoc
// @Summary  上报埋点事件(game_viewed/fork_started/ai_edit_started/mod_published 等)
// @Tags     analytics
// @Accept   json
// @Produce  json
// @Param    body  body  Event  true  "事件"
// @Success  204   "no content"
// @Failure  400   {object}  httpx.Envelope  "EVENT_INVALID"
// @Router   /analytics/events [post]
func record(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Bound through an explicit request shape rather than the persisted row: this endpoint is unauthenticated, and
		// binding Event directly let an anonymous caller choose the primary key — overwriting or colliding with existing
		// rows — and backdate created_at, which feeds the funnel numbers in /analytics/summary.
		var body EventRequest
		if err := c.ShouldBindJSON(&body); err != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", err.Error())
			return
		}
		e := Event{Name: body.Name, SessionID: body.SessionID, TargetID: body.TargetID, Depth: body.Depth}
		e.UserID = c.GetString("user_id")
		if err := svc.Record(e); err != nil {
			httpx.WriteError(c, 400, "EVENT_INVALID", err.Error())
			return
		}
		c.Status(http.StatusNoContent)
	}
}

// summary godoc
// @Summary  埋点汇总(admin:Fork 转化率 / AI 改完发布率 / 最大 Fork 深度)
// @Tags     analytics
// @Produce  json
// @Success  200  {object}  Summary
// @Failure  500  {object}  httpx.Envelope
// @Router   /analytics/summary [get]
func summary(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		out, err := svc.Summary()
		if err != nil {
			httpx.WriteError(c, 500, "INTERNAL", err.Error())
			return
		}
		c.JSON(200, out)
	}
}
