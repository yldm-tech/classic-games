package community

import (
	"errors"
	"forgeplay/server/internal/social"
	"forgeplay/server/pkg/httpx"
	"github.com/gin-gonic/gin"
	"net/http"
)

func RegisterRoutes(r gin.IRouter, s *Service, optional, required gin.HandlerFunc) {
	pub := r.Group("/api/v1/games/:id/community")
	if optional != nil {
		pub.Use(optional)
	}
	pub.GET("", getCommunity(s))
	w := r.Group("/api/v1/games/:id/community")
	if required != nil {
		w.Use(required)
	}
	w.POST("/rating", rateCommunity(s))
	w.POST("/posts", createCommunityPost(s))
}

// getCommunity godoc
// @Summary  游戏社区面板(评分摘要 + 帖子列表)
// @Tags     community
// @Produce  json
// @Param    id  path      string  true  "game id"
// @Success  200 {object}  Summary
// @Failure  500 {object}  httpx.Envelope  "COMMUNITY_ERROR"
// @Router   /games/{id}/community [get]
func getCommunity(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		v, e := s.Get(c.Param("id"), c.GetString("user_id"))
		if e != nil {
			httpx.WriteError(c, 500, "COMMUNITY_ERROR", e.Error())
			return
		}
		c.JSON(200, v)
	}
}

// rateCommunity godoc
// @Summary  给游戏打分(1-5,覆盖式更新)
// @Tags     community
// @Accept   json
// @Produce  json
// @Param    id    path      string  true  "game id"
// @Param    body  body      object{value=int}  true  "评分,1-5"
// @Success  200   {object}  Summary
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / RATING_INVALID"
// @Router   /games/{id}/community/rating [post]
func rateCommunity(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Value int `json:"value"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, e := s.Rate(c.Param("id"), c.GetString("user_id"), b.Value)
		if e != nil {
			httpx.WriteError(c, 400, "RATING_INVALID", e.Error())
			return
		}
		c.JSON(200, v)
	}
}

// createCommunityPost godoc
// @Summary  发社区帖子
// @Tags     community
// @Accept   json
// @Produce  json
// @Param    id    path      string  true  "game id"
// @Param    body  body      object{content=string}  true  "帖子内容,1-1000 字符"
// @Success  201   {object}  Post
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / POST_INVALID"
// @Failure  422   {object}  httpx.Envelope  "CONTENT_REJECTED(内容审核不通过)"
// @Router   /games/{id}/community/posts [post]
func createCommunityPost(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Content string `json:"content"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, e := s.Post(c.Param("id"), c.GetString("user_id"), b.Content)
		if e != nil {
			status := 400
			code := "POST_INVALID"
			if errors.Is(e, social.ErrContentRejected) {
				status = http.StatusUnprocessableEntity
				code = "CONTENT_REJECTED"
			}
			httpx.WriteError(c, status, code, e.Error())
			return
		}
		c.JSON(http.StatusCreated, v)
	}
}
