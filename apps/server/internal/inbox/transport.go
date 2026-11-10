package inbox

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"forgeplay/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "forgeplay/server/pkg/httpx"
)

// RegisterRoutes 挂载消息中心端点；读接口软鉴权，写接口必须鉴权。
// 用户可见文本走 ?lang=(zh|en|ja),缺省 zh;counts/index/handle/icon 等不本地化。
func RegisterRoutes(r gin.IRouter, svc *Service, middleware ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if len(middleware) > 0 && middleware[0] != nil {
		g.Use(middleware[0])
	}
	g.GET("/activity", listActivity(svc))
	g.GET("/chats", listChats(svc))
	g.GET("/messages/conversations", listChats(svc))
	g.GET("/chats/:idx/messages", listMessages(svc))
	g.GET("/messages/:idx", listMessages(svc))
	g.GET("/conversations/:handle/messages", listMessagesWith(svc))
	g.GET("/follow", listFollow(svc))
	g.GET("/friends/suggestions", listSuggestions(svc))
	g.GET("/users/:id/following", listFollowingOf(svc))
	g.GET("/users/:id/followers", listFollowersOf(svc))
	w := r.Group("/api/v1")
	if len(middleware) > 1 && middleware[1] != nil {
		w.Use(middleware[1])
	}
	w.POST("/chats/:idx/messages", sendMessage(svc))
	w.POST("/messages/:idx", sendMessage(svc))
	w.POST("/conversations/:handle/messages", sendMessageTo(svc))
	w.POST("/follow/:handle", setFollow(svc, true))
	w.DELETE("/follow/:handle", setFollow(svc, false))
	w.POST("/friends/:handle", addFriend(svc))
	w.POST("/users/:id/follow", setFollowByUser(svc, true))
	w.DELETE("/users/:id/follow", setFollowByUser(svc, false))
}

// setFollowByUser godoc
// @Summary  关注 / 取关(按用户 id)
// @Tags     inbox
// @Produce  json
// @Param    id  path      string  true  "目标用户 id"
// @Success  200  {object}  map[string]bool  "following"
// @Failure  500  {object}  httpx.Envelope  "INTERNAL"
// @Router   /users/{id}/follow [post]
func setFollowByUser(svc *Service, on bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.SetFollowing(c.GetString("user_id"), c.Param("id"), on); err != nil {
			i18n.WriteErrorDetail(c, 500, "INTERNAL", err.Error())
			return
		}
		c.JSON(200, gin.H{"following": on})
	}
}

// listFollowingOf godoc
// @Summary  某用户的关注列表
// @Tags     inbox
// @Produce  json
// @Param    id  path      string  true  "用户 id"
// @Success  200  {object}  map[string]interface{}
// @Router   /users/{id}/following [get]
func listFollowingOf(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) { c.JSON(200, gin.H{"items": svc.FollowingOf(c.Param("id"))}) }
}

// listFollowersOf godoc
// @Summary  某用户的粉丝列表
// @Tags     inbox
// @Produce  json
// @Param    id  path      string  true  "用户 id"
// @Success  200  {object}  map[string]interface{}
// @Router   /users/{id}/followers [get]
func listFollowersOf(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) { c.JSON(200, gin.H{"items": svc.FollowersOf(c.Param("id"))}) }
}

// listActivity godoc
// @Summary  通知动态列表
// @Tags     inbox
// @Produce  json
// @Param    lang  query     string  false  "zh|en|ja(默认 zh)"
// @Success  200   {object}  map[string]interface{}
// @Router   /activity [get]
func listActivity(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"items": svc.ActivityFor(c.GetString("user_id"), i18n.Lang(c))})
	}
}

// listChats godoc
// @Summary  私信会话列表
// @Tags     inbox
// @Produce  json
// @Param    lang  query     string  false  "zh|en|ja(默认 zh)"
// @Success  200   {object}  map[string]interface{}
// @Router   /chats [get]
func listChats(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if userID := c.GetString("user_id"); userID != "" {
			c.JSON(http.StatusOK, gin.H{"items": svc.ChatsFor(userID, i18n.Lang(c))})
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": svc.Chats(i18n.Lang(c))})
	}
}

// listMessagesWith godoc
// @Summary  会话消息(按对方 handle)
// @Tags     inbox
// @Produce  json
// @Param    handle  path      string  true  "对方 handle"
// @Success  200  {object}  map[string]interface{}
// @Failure  403  {object}  httpx.Envelope  "NOT_FRIEND(非好友关系不能查看)"
// @Router   /conversations/{handle}/messages [get]
func listMessagesWith(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, err := svc.MessagesWith(c.GetString("user_id"), c.Param("handle"))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusForbidden, "NOT_FRIEND", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// sendMessageTo godoc
// @Summary  发私信(按对方 handle)
// @Tags     inbox
// @Accept   json
// @Produce  json
// @Param    handle  path      string  true  "对方 handle"
// @Success  201  {object}  map[string]interface{}
// @Failure  400  {object}  httpx.Envelope  "MESSAGE_INVALID(消息格式错误)"
// @Failure  403  {object}  httpx.Envelope  "NOT_FRIEND(非好友关系不能私信)"
// @Router   /conversations/{handle}/messages [post]
func sendMessageTo(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var body struct {
			Text string `json:"text"`
		}
		if c.ShouldBindJSON(&body) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "消息格式错误")
			return
		}
		items, err := svc.SendMessageTo(c.GetString("user_id"), c.Param("handle"), body.Text)
		if err != nil {
			status, code := http.StatusBadRequest, "MESSAGE_INVALID"
			if err == ErrNotFriend {
				status, code = http.StatusForbidden, "NOT_FRIEND"
			}
			i18n.WriteErrorDetail(c, status, code, err.Error())
			return
		}
		c.JSON(http.StatusCreated, gin.H{"items": items})
	}
}

// listMessages godoc
// @Summary  会话气泡(对方种子消息 + 自动回复模板)
// @Tags     inbox
// @Produce  json
// @Param    idx   path      int     true   "会话索引"
// @Param    lang  query     string  false  "zh|en|ja(默认 zh)"
// @Success  200   {object}  map[string]interface{}
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST(idx 非整数)"
// @Failure  404   {object}  httpx.Envelope  "NOT_FOUND(idx 越界)"
// @Router   /chats/{idx}/messages [get]
func listMessages(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		idx, err := strconv.Atoi(c.Param("idx"))
		if err != nil {
			i18n.WriteError(c, http.StatusBadRequest, "BAD_REQUEST")
			return
		}
		items, ok := svc.MessagesFor(c.GetString("user_id"), idx, i18n.Lang(c))
		if !ok {
			i18n.WriteError(c, http.StatusNotFound, "NOT_FOUND")
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// sendMessage godoc
// @Summary  发私信(按会话索引)
// @Tags     inbox
// @Accept   json
// @Produce  json
// @Param    idx  path      int  true  "会话索引"
// @Success  201  {object}  map[string]interface{}
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(idx 非整数或消息格式错误) / MESSAGE_INVALID"
// @Router   /chats/{idx}/messages [post]
func sendMessage(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		idx, err := strconv.Atoi(c.Param("idx"))
		if err != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "idx 必须是整数")
			return
		}
		var body struct {
			Text string `json:"text"`
		}
		if c.ShouldBindJSON(&body) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "消息格式错误")
			return
		}
		if _, err = svc.SendMessage(c.GetString("user_id"), idx, body.Text); err != nil {
			i18n.WriteErrorDetail(c, 400, "MESSAGE_INVALID", err.Error())
			return
		}
		items, _ := svc.MessagesFor(c.GetString("user_id"), idx, c.Query("lang"))
		c.JSON(201, gin.H{"items": items})
	}
}

// setFollow godoc
// @Summary  关注 / 取关(按 handle)
// @Tags     inbox
// @Produce  json
// @Param    handle  path      string  true  "目标用户 handle"
// @Success  200  {object}  map[string]bool  "following"
// @Router   /follow/{handle} [post]
func setFollow(svc *Service, on bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.SetFollowing(c.GetString("user_id"), c.Param("handle"), on); err != nil {
			i18n.WriteErrorDetail(c, 500, "INTERNAL", err.Error())
			return
		}
		c.JSON(200, gin.H{"following": on})
	}
}

// addFriend godoc
// @Summary  加好友
// @Tags     inbox
// @Produce  json
// @Param    handle  path      string  true  "目标用户 handle"
// @Success  201  {object}  map[string]bool  "friend"
// @Failure  500  {object}  httpx.Envelope  "INTERNAL"
// @Router   /friends/{handle} [post]
func addFriend(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.AddFriend(c.GetString("user_id"), c.Param("handle")); err != nil {
			i18n.WriteErrorDetail(c, 500, "INTERNAL", err.Error())
			return
		}
		c.JSON(201, gin.H{"friend": true})
	}
}

// listFollow godoc
// @Summary  关注 / 粉丝列表
// @Tags     inbox
// @Produce  json
// @Param    type  query     string  false  "following|followers(默认 following)"
// @Param    lang  query     string  false  "zh|en|ja(默认 zh)"
// @Success  200   {object}  map[string]interface{}
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST(type 非法)"
// @Router   /follow [get]
func listFollow(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		kind := c.DefaultQuery("type", "following")
		var items []Person
		switch kind {
		case "following":
			items = svc.FollowingOf(c.GetString("user_id"))
		case "followers":
			items = svc.FollowersOf(c.GetString("user_id"))
		default:
			i18n.WriteError(c, http.StatusBadRequest, "BAD_REQUEST")
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// listSuggestions godoc
// @Summary  加好友推荐 + 邀请码
// @Tags     inbox
// @Produce  json
// @Param    lang  query     string  false  "zh|en|ja(默认 zh)"
// @Success  200   {object}  map[string]interface{}
// @Router   /friends/suggestions [get]
func listSuggestions(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetString("user_id") != "" {
			c.JSON(http.StatusOK, gin.H{"items": []Suggestion{}, "invite_code": ""})
			return
		}
		items, code := svc.Suggestions(i18n.Lang(c))
		c.JSON(http.StatusOK, gin.H{"items": items, "invite_code": code})
	}
}
