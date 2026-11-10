package replays

import (
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
	"net/http"
)

func RegisterRoutes(r gin.IRouter, s *Service, auth gin.HandlerFunc) {
	pub := r.Group("/api/v1/games/:id/replays")
	pub.GET("/leaderboard", replaysLeaderboard(s))
	pub.GET("/:user", replaysLatest(s))
	w := r.Group("/api/v1/games/:id/replays")
	if auth != nil {
		w.Use(auth)
	}
	w.POST("", createReplay(s))
}

// replaysLeaderboard godoc
// @Summary  游戏回放排行榜(前 20)
// @Tags     replays
// @Produce  json
// @Param    id  path      string  true  "game id"
// @Success  200 {object}  map[string]interface{}
// @Failure  500 {object}  httpx.Envelope  "INTERNAL"
// @Router   /games/{id}/replays/leaderboard [get]
func replaysLeaderboard(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		v, e := s.Leaderboard(c.Param("id"), 20)
		if e != nil {
			httpx.WriteError(c, 500, "INTERNAL", e.Error())
			return
		}
		c.JSON(200, gin.H{"items": v})
	}
}

// replaysLatest godoc
// @Summary  取某用户在某游戏的最新回放
// @Tags     replays
// @Produce  json
// @Param    id    path      string  true  "game id"
// @Param    user  path      string  true  "user id"
// @Success  200   {object}  Replay
// @Failure  404   {object}  httpx.Envelope  "REPLAY_NOT_FOUND"
// @Router   /games/{id}/replays/{user} [get]
func replaysLatest(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		v, e := s.Latest(c.Param("id"), c.Param("user"))
		if e != nil {
			httpx.WriteError(c, 404, "REPLAY_NOT_FOUND", e.Error())
			return
		}
		c.JSON(200, v)
	}
}

// createReplay godoc
// @Summary  上传对局回放(逐帧轨迹,服务端复核分数)
// @Tags     replays
// @Accept   json
// @Produce  json
// @Param    id    path      string                            true  "game id"
// @Param    body  body      object{duration_ms=int,frames=[]Frame}  true  "回放时长(ms)+逐帧数据"
// @Success  201   {object}  Replay
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / REPLAY_INVALID"
// @Router   /games/{id}/replays [post]
func createReplay(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			DurationMS int     `json:"duration_ms"`
			Frames     []Frame `json:"frames"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, e := s.Create(c.Param("id"), c.GetString("user_id"), b.DurationMS, b.Frames)
		if e != nil {
			if errors.Is(e, ErrPlayBlocked) {
				httpx.WriteError(c, http.StatusForbidden, "TEEN_BLOCKED", e.Error())
				return
			}
			httpx.WriteError(c, 400, "REPLAY_INVALID", e.Error())
			return
		}
		c.JSON(http.StatusCreated, v)
	}
}
