package participation

import (
	"forgeplay/server/pkg/httpx"
	"github.com/gin-gonic/gin"
	"net/http"
)

func RegisterRoutes(r gin.IRouter, s *Service, auth gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if auth != nil {
		g.Use(auth)
	}
	g.GET("/events/joined", eventsJoined(s))
	g.POST("/events/:id/join", joinEvent(s))
	g.GET("/earnings/withdrawals", listWithdrawals(s))
	g.POST("/earnings/withdrawals", createWithdrawal(s))
}

// listWithdrawals godoc
// @Summary  当前用户的提现记录
// @Tags     participation
// @Produce  json
// @Success  200 {object}  map[string]interface{}
// @Failure  500 {object}  httpx.Envelope  "PARTICIPATION_ERROR"
// @Router   /earnings/withdrawals [get]
func listWithdrawals(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, e := s.Withdrawals(c.GetString("user_id"))
		if e != nil {
			httpx.WriteError(c, 500, "PARTICIPATION_ERROR", e.Error())
			return
		}
		c.JSON(200, gin.H{"items": items})
	}
}

// eventsJoined godoc
// @Summary  我已参加的活动 id 列表
// @Tags     participation
// @Produce  json
// @Success  200 {object}  map[string]interface{}
// @Failure  500 {object}  httpx.Envelope  "PARTICIPATION_ERROR"
// @Router   /events/joined [get]
func eventsJoined(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		ids, e := s.Joined(c.GetString("user_id"))
		if e != nil {
			httpx.WriteError(c, 500, "PARTICIPATION_ERROR", e.Error())
			return
		}
		c.JSON(200, gin.H{"event_ids": ids})
	}
}

// joinEvent godoc
// @Summary  参加活动
// @Tags     participation
// @Produce  json
// @Param    id  path      string  true  "event id"
// @Success  200 {object}  EventJoin
// @Failure  400 {object}  httpx.Envelope  "EVENT_JOIN_INVALID"
// @Router   /events/{id}/join [post]
func joinEvent(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		v, e := s.Join(c.GetString("user_id"), c.Param("id"))
		if e != nil {
			httpx.WriteError(c, 400, "EVENT_JOIN_INVALID", e.Error())
			return
		}
		c.JSON(http.StatusOK, v)
	}
}

// createWithdrawal godoc
// @Summary  申请收益提现
// @Tags     participation
// @Accept   json
// @Produce  json
// @Param    body  body      object{amount=int}  true  "提现金额"
// @Success  202   {object}  Withdrawal
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST"
// @Failure  409   {object}  httpx.Envelope  "WITHDRAWAL_INVALID(超额/重复提现)"
// @Router   /earnings/withdrawals [post]
func createWithdrawal(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Amount int `json:"amount"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, e := s.Withdraw(c.GetString("user_id"), b.Amount)
		if e != nil {
			httpx.WriteError(c, 409, "WITHDRAWAL_INVALID", e.Error())
			return
		}
		c.JSON(http.StatusAccepted, v)
	}
}
