package social

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

// RegisterRoutes 挂载社交端点(docs/09-api-design.md)。
// 读接口(列评论)公开,但套 readOptional 软鉴权:登录则注入 user_id 以过滤被屏蔽作者,匿名照常可读。
// 写接口(评论/点赞)套 authRequired,操作者身份从 token 注入的 user_id 取,不信任 body/query(避免冒名/IDOR)。
// 两个中间件均可为 nil(测试/无鉴权场景)。
func RegisterRoutes(r gin.IRouter, svc *Service, authRequired, readOptional gin.HandlerFunc) {
	pub := r.Group("/api/v1/games/:id")
	if readOptional != nil {
		pub.Use(readOptional)
	}
	pub.GET("/comments", listComments(svc))

	w := r.Group("/api/v1/games/:id")
	if authRequired != nil {
		w.Use(authRequired)
	}
	w.POST("/comments", addComment(svc))
	w.POST("/like", like(svc))
	w.DELETE("/like", unlike(svc))
	w.POST("/favorite", favorite(svc, true))
	w.DELETE("/favorite", favorite(svc, false))
	account := r.Group("/api/v1")
	if authRequired != nil {
		account.Use(authRequired)
	}
	account.GET("/favorites", listFavorites(svc))
}

// favorite godoc
// @Summary  收藏 / 取消收藏
// @Tags     social
// @Produce  json
// @Param    id  path  string  true  "game id"
// @Success  200  {object}  map[string]interface{}  "favorite: true/false"
// @Failure  500  {object}  httpx.Envelope
// @Router   /games/{id}/favorite [post]
// @Router   /games/{id}/favorite [delete]
func favorite(svc *Service, value bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		var err error
		if value {
			err = svc.Favorite(c.Param("id"), c.GetString("user_id"))
		} else {
			err = svc.Unfavorite(c.Param("id"), c.GetString("user_id"))
		}
		if err != nil {
			i18n.WriteErrorDetail(c, 500, "INTERNAL", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"favorite": value})
	}
}

// listFavorites godoc
// @Summary  我的收藏列表
// @Tags     social
// @Produce  json
// @Success  200  {object}  map[string]interface{}
// @Failure  500  {object}  httpx.Envelope
// @Router   /favorites [get]
func listFavorites(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, err := svc.Favorites(c.GetString("user_id"))
		if err != nil {
			i18n.WriteErrorDetail(c, 500, "INTERNAL", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// listComments godoc
// @Summary  评论列表(分页)
// @Tags     social
// @Produce  json
// @Param    id  path  string  true  "game id"
// @Success  200  {object}  map[string]interface{}
// @Router   /games/{id}/comments [get]
func listComments(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		limit, _ := strconv.Atoi(c.Query("limit"))
		// 登录视角过滤被屏蔽作者的评论;匿名(user_id 空)则照常返回全部。
		items, next, err := svc.CommentsForViewer(c.Param("id"), c.GetString("user_id"), c.Query("cursor"), limit)
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": items, "next_cursor": next})
	}
}

// addComment godoc
// @Summary  发评论
// @Tags     social
// @Accept   json
// @Produce  json
// @Param    id  path  string  true  "game id"
// @Success  201  {object}  Comment
// @Failure  400  {object}  httpx.Envelope
// @Router   /games/{id}/comments [post]
func addComment(svc *Service) gin.HandlerFunc {
	type req struct {
		Content string `json:"content"`
	}
	return func(c *gin.Context) {
		var b req
		if err := c.ShouldBindJSON(&b); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		// 作者=已登录用户(token),不取 body,避免冒名。
		cm, err := svc.Comment(c.Param("id"), c.GetString("user_id"), b.Content)
		if err != nil {
			if errors.Is(err, ErrContentRejected) {
				i18n.WriteErrorDetail(c, http.StatusUnprocessableEntity, "CONTENT_REJECTED", err.Error())
				return
			}
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "COMMENT_INVALID", err.Error())
			return
		}
		c.JSON(http.StatusCreated, cm)
	}
}

// like godoc
// @Summary  点赞
// @Tags     social
// @Produce  json
// @Param    id       path   string  true   "game id"
// @Param    user_id  query  string  false  "用户(将由鉴权注入)"
// @Success  200  {object}  map[string]interface{}  "count + liked"
// @Router   /games/{id}/like [post]
func like(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		uid := c.GetString("user_id")
		if err := svc.Like(c.Param("id"), uid); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, likeStatusResp(svc, c.Param("id"), uid, true))
	}
}

// likeStatusResp 取最新点赞数;读失败时不回 count=0(避免写成功后把 UI 计数清零),只回操作后的 liked。
func likeStatusResp(svc *Service, gameID, uid string, liked bool) gin.H {
	count, gotLiked, err := svc.LikeStatus(gameID, uid)
	if err != nil {
		return gin.H{"liked": liked}
	}
	return gin.H{"count": count, "liked": gotLiked}
}

// unlike godoc
// @Summary  取消点赞
// @Tags     social
// @Produce  json
// @Param    id       path   string  true   "game id"
// @Param    user_id  query  string  false  "用户(将由鉴权注入)"
// @Success  200  {object}  map[string]interface{}  "count + liked"
// @Router   /games/{id}/like [delete]
func unlike(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		uid := c.GetString("user_id")
		if err := svc.Unlike(c.Param("id"), uid); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, likeStatusResp(svc, c.Param("id"), uid, false))
	}
}
