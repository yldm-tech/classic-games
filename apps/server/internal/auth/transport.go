package auth

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

const ctxUserID = "user_id"

// CtxUserIsGuest marks a request authenticated by a self-issued guest token. Downstream metering reads this to avoid
// treating a free-to-mint identity as its own quota subject; it is a plain context key so no package has to import auth.
const CtxUserIsGuest = "user_is_guest"

// RegisterRoutes 挂载 auth 端点(docs/09-api-design.md)。
func RegisterRoutes(r gin.IRouter, svc *Service) {
	g := r.Group("/api/v1/auth")
	g.POST("/sms/send", sendCode(svc))
	g.POST("/sms/verify", verify(svc))
	g.POST("/guest", guestLogin(svc)) // 游客 token(先逛后登录)
	g.POST("/oauth/exchange", oauthExchange(svc))
	g.POST("/oauth/:provider", oauthProvider(svc))
	g.POST("/password/login", passwordLogin(svc))
	g.POST("/logout", logout(svc))        // 注销:作废当前 token(幂等)
	g.POST("/refresh", refreshToken(svc)) // 续期:旧 token 换新 token

	// 需登录的端点
	me := r.Group("/api/v1")
	me.Use(Required(svc))
	me.GET("/users/me", currentUser(svc))
	me.DELETE("/users/me", deleteCurrentUser(svc))
	me.GET("/users/me/security", securityInfo(svc))
	me.POST("/users/me/password", setPassword(svc))
	me.POST("/users/me/oauth/bind", bindOAuth(svc))
	me.POST("/users/me/phone", changePhone(svc))
}

// oauthProvider godoc
// @Summary  第三方登录(wechat/apple/google...)
// @Tags     auth
// @Accept   json
// @Produce  json
// @Param    provider  path      string  true  "OAuth 提供方,如 wechat/apple/google"
// @Success  200  {object}  map[string]interface{}  "token + user"
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法)"
// @Failure  401  {object}  httpx.Envelope  "OAUTH_FAILED"
// @Failure  503  {object}  httpx.Envelope  "OAUTH_FAILED(第三方服务不可用)"
// @Router   /auth/oauth/{provider} [post]
func oauthProvider(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Code string `json:"code"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		token, user, err := svc.OAuthLogin(c.Param("provider"), b.Code)
		if err != nil {
			status := http.StatusUnauthorized
			if errors.Is(err, ErrOAuthUnavailable) {
				status = http.StatusServiceUnavailable
			}
			i18n.WriteErrorDetail(c, status, "OAUTH_FAILED", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"token": token, "user": user})
	}
}

// changePhone godoc
// @Summary  更换绑定手机号(需短信验证码,登录态)
// @Tags     auth
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "SecurityInfo"
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法) / PHONE_CHANGE_FAILED"
// @Router   /users/me/phone [post]
func changePhone(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Phone string `json:"phone"`
			Code  string `json:"code"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		if e := s.ChangePhone(UserID(c), b.Phone, b.Code); e != nil {
			i18n.WriteErrorDetail(c, 400, "PHONE_CHANGE_FAILED", e.Error())
			return
		}
		c.JSON(200, s.SecurityInfo(UserID(c)))
	}
}

// passwordLogin godoc
// @Summary  账号密码登录
// @Tags     auth
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "token + user"
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法)"
// @Failure  401  {object}  httpx.Envelope  "AUTH_INVALID"
// @Failure  429  {object}  httpx.Envelope  "AUTH_INVALID(登录尝试过于频繁)"
// @Router   /auth/password/login [post]
func passwordLogin(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Phone    string `json:"phone"`
			Password string `json:"password"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		tok, u, e := s.PasswordLoginWithIP(b.Phone, b.Password, c.ClientIP())
		if e != nil {
			status := http.StatusUnauthorized
			if errors.Is(e, ErrPasswordLimited) {
				status = http.StatusTooManyRequests
			}
			i18n.WriteErrorDetail(c, status, "AUTH_INVALID", e.Error())
			return
		}
		c.JSON(200, gin.H{"token": tok, "user": u})
	}
}

// setPassword godoc
// @Summary  设置 / 修改登录密码(登录态)
// @Tags     auth
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法) / PASSWORD_INVALID"
// @Router   /users/me/password [post]
func setPassword(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Password string `json:"password"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		if e := s.SetPassword(UserID(c), b.Password); e != nil {
			i18n.WriteErrorDetail(c, 400, "PASSWORD_INVALID", e.Error())
			return
		}
		c.JSON(200, gin.H{"password_set": true})
	}
}

// bindOAuth godoc
// @Summary  绑定第三方账号(登录态)
// @Tags     auth
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "SecurityInfo"
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法) / OAUTH_BIND_FAILED"
// @Failure  409  {object}  httpx.Envelope  "OAUTH_BIND_FAILED(该第三方身份已被绑定)"
// @Router   /users/me/oauth/bind [post]
func bindOAuth(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Provider string `json:"provider"`
			Code     string `json:"code"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		if e := s.BindOAuth(UserID(c), b.Provider, b.Code); e != nil {
			status := 400
			if errors.Is(e, ErrIdentityBound) {
				status = 409
			}
			i18n.WriteErrorDetail(c, status, "OAUTH_BIND_FAILED", e.Error())
			return
		}
		c.JSON(200, s.SecurityInfo(UserID(c)))
	}
}

// oauthExchange godoc
// @Summary  第三方登录(通用 provider+code 交换接口)
// @Tags     auth
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "token + user"
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法)"
// @Failure  401  {object}  httpx.Envelope  "OAUTH_INVALID"
// @Failure  503  {object}  httpx.Envelope  "OAUTH_INVALID(第三方服务不可用)"
// @Router   /auth/oauth/exchange [post]
func oauthExchange(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Provider string `json:"provider"`
			Code     string `json:"code"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		token, u, err := svc.OAuthLogin(b.Provider, b.Code)
		if err != nil {
			status := http.StatusUnauthorized
			if errors.Is(err, ErrOAuthUnavailable) {
				status = http.StatusServiceUnavailable
			}
			i18n.WriteErrorDetail(c, status, "OAUTH_INVALID", err.Error())
			return
		}
		c.JSON(200, gin.H{"token": token, "user": u})
	}
}

// deleteCurrentUser godoc
// @Summary  注销账号(删除当前用户,登录态)
// @Tags     auth
// @Produce  json
// @Success  204  "无内容"
// @Failure  500  {object}  httpx.Envelope  "DELETE_FAILED"
// @Router   /users/me [delete]
func deleteCurrentUser(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.DeleteAccount(UserID(c)); err != nil {
			i18n.WriteErrorDetail(c, http.StatusInternalServerError, "DELETE_FAILED", err.Error())
			return
		}
		c.Status(http.StatusNoContent)
	}
}

// tokenFromHeader 从 Authorization: Bearer <token> 取 token。
func tokenFromHeader(c *gin.Context) string {
	return strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer ")
}

// Required 是鉴权中间件:解析 token,注入用户到 context;无效 token 直接 401。
// 其它模块需登录的端点可复用它。
func Required(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		uid, ok := svc.UserIDForToken(tokenFromHeader(c))
		if !ok {
			i18n.WriteError(c, http.StatusUnauthorized, "AUTH_REQUIRED")
			c.Abort()
			return
		}
		c.Set(ctxUserID, uid)
		c.Set(CtxUserIsGuest, svc.IsGuest(uid))
		c.Next()
	}
}

// Optional 解析 token 注入身份;无 token / 失效不报错(用于可匿名但登录后增强的端点,
// 如 AI 配额:登录按用户计,匿名按 IP 计)。
func Optional(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if uid, ok := svc.UserIDForToken(tokenFromHeader(c)); ok {
			c.Set(ctxUserID, uid)
			c.Set(CtxUserIsGuest, svc.IsGuest(uid))
		}
		c.Next()
	}
}

// RequireAdmin 在 Required 基础上要求管理员身份;非管理员返回 403(审核裁决等特权操作)。
func RequireAdmin(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		uid, ok := svc.UserIDForToken(tokenFromHeader(c))
		if !ok {
			i18n.WriteError(c, http.StatusUnauthorized, "AUTH_REQUIRED")
			c.Abort()
			return
		}
		if !svc.IsAdmin(uid) {
			i18n.WriteError(c, http.StatusForbidden, "FORBIDDEN")
			c.Abort()
			return
		}
		c.Set(ctxUserID, uid)
		c.Next()
	}
}

// UserID 从 context 取当前用户 ID(在 Required/Optional/RequireAdmin 之后可用)。
func UserID(c *gin.Context) string {
	v, _ := c.Get(ctxUserID)
	id, _ := v.(string)
	return id
}

// securityInfo godoc
// @Summary  账号安全信息(手机 / 密码 / 已绑定第三方账号,登录态)
// @Tags     auth
// @Produce  json
// @Success  200  {object}  map[string]interface{}
// @Router   /users/me/security [get]
func securityInfo(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) { c.JSON(200, svc.SecurityInfo(UserID(c))) }
}

// guestLogin godoc
// @Summary  游客登录(签发临时 token)
// @Tags     auth
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "token + user"
// @Router   /auth/guest [post]
func guestLogin(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		token, u, err := svc.GuestLogin(i18n.Lang(c))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"token": token, "user": u})
	}
}

// currentUser godoc
// @Summary  当前用户(需登录)
// @Tags     auth
// @Produce  json
// @Param    Authorization  header    string  true  "Bearer <token>"
// @Success  200  {object}  User
// @Failure  401  {object}  httpx.Envelope
// @Router   /users/me [get]
func currentUser(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		u, err := svc.User(UserID(c))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusNotFound, "NOT_FOUND", err.Error())
			return
		}
		c.JSON(http.StatusOK, u)
	}
}

// logout godoc
// @Summary  注销(作废当前 token,幂等)
// @Tags     auth
// @Produce  json
// @Success  200  {object}  map[string]bool
// @Router   /auth/logout [post]
func logout(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 幂等:删除携带的 token;无效/缺失 token 也返回成功,避免注销报错。
		if err := svc.Logout(tokenFromHeader(c)); err != nil {
			i18n.WriteErrorDetail(c, 500, "INTERNAL", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"ok": true})
	}
}

// refreshToken godoc
// @Summary  续期(旧 token 换新 token)
// @Tags     auth
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "token"
// @Failure  401  {object}  httpx.Envelope  "AUTH_REQUIRED"
// @Router   /auth/refresh [post]
func refreshToken(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		newTok, ok := svc.Refresh(tokenFromHeader(c))
		if !ok {
			i18n.WriteErrorDetail(c, http.StatusUnauthorized, "AUTH_REQUIRED", "token 无效或已过期")
			return
		}
		c.JSON(http.StatusOK, gin.H{"token": newTok})
	}
}

// sendCode godoc
// @Summary  发送手机验证码
// @Tags     auth
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]bool
// @Router   /auth/sms/send [post]
func sendCode(svc *Service) gin.HandlerFunc {
	type req struct {
		Phone string `json:"phone"`
	}
	return func(c *gin.Context) {
		var b req
		if err := c.ShouldBindJSON(&b); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		if err := svc.SendCode(b.Phone); err != nil {
			if errors.Is(err, ErrRateLimited) {
				i18n.WriteErrorDetail(c, http.StatusTooManyRequests, "RATE_LIMITED", err.Error())
				return
			}
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"sent": true})
	}
}

// verify godoc
// @Summary  验证码登录(未注册自动建号)
// @Tags     auth
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "token + user"
// @Failure  401  {object}  httpx.Envelope  "AUTH_INVALID"
// @Router   /auth/sms/verify [post]
func verify(svc *Service) gin.HandlerFunc {
	type req struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
	}
	return func(c *gin.Context) {
		var b req
		if err := c.ShouldBindJSON(&b); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		token, u, err := svc.Login(b.Phone, b.Code, i18n.Lang(c))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusUnauthorized, "AUTH_INVALID", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"token": token, "user": u})
	}
}
