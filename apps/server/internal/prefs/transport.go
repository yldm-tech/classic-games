package prefs

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

// RegisterRoutes 挂载偏好设置端点(docs/09-api-design.md)。
// 读接口软鉴权并本地化，写接口必须鉴权。
func RegisterRoutes(r gin.IRouter, svc *Service, middleware ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if len(middleware) > 0 && middleware[0] != nil {
		g.Use(middleware[0])
	}
	g.GET("/prefs/notifications", notifications(svc))
	g.GET("/prefs/privacy", privacy(svc))
	g.GET("/prefs/teen", teen(svc))
	w := r.Group("/api/v1")
	if len(middleware) > 1 && middleware[1] != nil {
		w.Use(middleware[1])
	}
	w.POST("/prefs/notifications/:key", setNotification(svc))
	w.POST("/prefs/privacy/:key", setPrivacy(svc))
	w.POST("/prefs/teen", setTeen(svc))
	// /blocks 改由 moderation 域提供真实黑名单(见 moderation.listBlocks);此处不再以种子顶替。
}

// notifications godoc
// @Summary  通知设置元数据(总开关 + 互动/系统分组)
// @Tags     prefs
// @Produce  json
// @Param    lang  query     string  false  "语言:zh(默认)/ en / ja"
// @Success  200   {object}  NotifPrefs
// @Router   /prefs/notifications [get]
func notifications(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, svc.NotificationsFor(c.GetString("user_id"), i18n.Lang(c)))
	}
}

// privacy godoc
// @Summary  隐私设置元数据(段控 + 开关)
// @Tags     prefs
// @Produce  json
// @Param    lang  query     string  false  "语言:zh(默认)/ en / ja"
// @Success  200   {object}  PrivacyPrefs
// @Router   /prefs/privacy [get]
func privacy(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, svc.PrivacyFor(c.GetString("user_id"), i18n.Lang(c)))
	}
}

// teen godoc
// @Summary  青少年模式元数据(规则说明 + 默认态)
// @Tags     prefs
// @Produce  json
// @Param    lang  query     string  false  "语言:zh(默认)/ en / ja"
// @Success  200   {object}  TeenPrefs
// @Router   /prefs/teen [get]
func teen(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, svc.TeenFor(c.GetString("user_id"), i18n.Lang(c)))
	}
}

// setNotification godoc
// @Summary  设置通知开关
// @Tags     prefs
// @Accept   json
// @Produce  json
// @Param    key  path      string  true  "通知项 key"
// @Success  200  {object}  map[string]interface{}
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法) / PREF_INVALID(key 不存在)"
// @Router   /prefs/notifications/{key} [post]
func setNotification(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Value bool `json:"value"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		if err := s.SetNotification(c.GetString("user_id"), c.Param("key"), b.Value); err != nil {
			i18n.WriteErrorDetail(c, 400, "PREF_INVALID", err.Error())
			return
		}
		c.JSON(200, gin.H{"saved": true})
	}
}

// setPrivacy godoc
// @Summary  设置隐私选项
// @Tags     prefs
// @Accept   json
// @Produce  json
// @Param    key  path      string  true  "隐私项 key"
// @Success  200  {object}  map[string]interface{}
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法) / PREF_INVALID(key 不存在或取值非法)"
// @Router   /prefs/privacy/{key} [post]
func setPrivacy(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Value any `json:"value"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		value := b.Value
		if n, ok := value.(float64); ok {
			value = int(n)
		}
		if err := s.SetPrivacy(c.GetString("user_id"), c.Param("key"), value); err != nil {
			i18n.WriteErrorDetail(c, 400, "PREF_INVALID", err.Error())
			return
		}
		c.JSON(200, gin.H{"saved": true})
	}
}

// setTeen godoc
// @Summary  开关青少年模式(校验 PIN)
// @Tags     prefs
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法) / PIN_INVALID(PIN 校验失败)"
// @Router   /prefs/teen [post]
func setTeen(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Enabled bool   `json:"enabled"`
			PIN     string `json:"pin"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		if err := s.SetTeen(c.GetString("user_id"), b.Enabled, b.PIN); err != nil {
			i18n.WriteErrorDetail(c, 400, "PIN_INVALID", err.Error())
			return
		}
		c.JSON(200, gin.H{"enabled": b.Enabled})
	}
}
