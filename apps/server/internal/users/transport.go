package users

import (
	"errors"
	"forgeplay/server/pkg/httpx"
	"net/http"

	"github.com/gin-gonic/gin"
)

// writeProfileError 区分校验失败(400)与持久化失败(500,不回显底层错误)。
func writeProfileError(c *gin.Context, err error) {
	if errors.Is(err, ErrProfilePersist) {
		httpx.WriteError(c, http.StatusInternalServerError, "INTERNAL", "failed to save profile")
		return
	}
	httpx.WriteError(c, http.StatusBadRequest, "PROFILE_INVALID", err.Error())
}

// RegisterRoutes 挂载用户资料/内容端点。读接口公开。
func RegisterRoutes(r gin.IRouter, svc *Service, middleware ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	g.GET("/users/:id/profile", getProfile(svc))
	g.GET("/users/:id", getProfile(svc))
	g.GET("/users/:id/games", listUserGames(svc))
	w := r.Group("/api/v1")
	if len(middleware) > 0 && middleware[0] != nil {
		w.Use(middleware[0])
	}
	w.POST("/users/me/profile", updateProfile(svc))
	w.PATCH("/users/me", patchProfile(svc))
	w.POST("/users/me/verification", submitVerification(svc))
	w.POST("/auth/realname", submitVerification(svc))
	w.GET("/users/me/verification", getVerification(svc))
	if len(middleware) > 1 && middleware[1] != nil {
		a := r.Group("/api/v1")
		a.Use(middleware[1])
		a.GET("/verifications/queue", listPendingVerifications(svc))
		a.POST("/users/:id/verification/decision", decideVerification(svc))
	}
}

// patchProfile godoc
// @Summary  编辑资料(局部更新,仅传字段生效)
// @Tags     users
// @Accept   json
// @Produce  json
// @Param    body  body      ProfilePatch  true  "待更新字段(昵称/简介/性别/语气/地区)"
// @Success  200   {object}  Profile
// @Failure  400   {object}  httpx.Envelope  "PROFILE_INVALID"
// @Failure  500   {object}  httpx.Envelope  "INTERNAL(持久化失败)"
// @Router   /users/me [patch]
func patchProfile(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b ProfilePatch
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		p, err := s.PatchProfile(c.GetString("user_id"), b)
		if err != nil {
			writeProfileError(c, err)
			return
		}
		c.JSON(200, p)
	}
}

// updateProfile godoc
// @Summary  编辑资料(整份覆盖更新:昵称/简介/头像/地区)
// @Tags     users
// @Accept   json
// @Produce  json
// @Param    body  body      ProfileUpdate  true  "完整资料"
// @Success  200   {object}  Profile
// @Failure  400   {object}  httpx.Envelope  "PROFILE_INVALID"
// @Failure  500   {object}  httpx.Envelope  "INTERNAL(持久化失败)"
// @Router   /users/me/profile [post]
func updateProfile(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b ProfileUpdate
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		p, err := s.UpdateProfile(c.GetString("user_id"), b)
		if err != nil {
			writeProfileError(c, err)
			return
		}
		c.JSON(200, p)
	}
}

// submitVerification godoc
// @Summary  实名认证(合规):提交姓名+证件号,进入待审核
// @Tags     users
// @Accept   json
// @Produce  json
// @Param    body  body      object{name=string,id_number=string}  true  "姓名 + 证件号(不落库原文)"
// @Success  202   {object}  VerificationStatus
// @Failure  400   {object}  httpx.Envelope  "VERIFICATION_INVALID"
// @Router   /users/me/verification [post]
func submitVerification(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Name     string `json:"name"`
			IDNumber string `json:"id_number"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, err := s.SubmitVerification(c.GetString("user_id"), b.Name, b.IDNumber)
		if err != nil {
			httpx.WriteError(c, 400, "VERIFICATION_INVALID", err.Error())
			return
		}
		c.JSON(202, v)
	}
}

// getVerification godoc
// @Summary  实名认证状态
// @Tags     users
// @Produce  json
// @Success  200  {object}  VerificationStatus
// @Router   /users/me/verification [get]
func getVerification(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) { c.JSON(200, s.VerificationStatus(c.GetString("user_id"))) }
}

// listPendingVerifications godoc
// @Summary  待审核实名队列(admin)
// @Tags     users
// @Produce  json
// @Success  200  {object}  map[string]interface{}
// @Router   /verifications/queue [get]
func listPendingVerifications(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) { c.JSON(200, gin.H{"items": s.ListPendingVerifications()}) }
}

// decideVerification godoc
// @Summary  实名审核裁决(admin)
// @Tags     users
// @Accept   json
// @Produce  json
// @Param    id    path  string  true  "user id"
// @Param    body  body  object{approve=bool}  true  "是否通过"
// @Success  200   {object}  VerificationStatus
// @Failure  400   {object}  httpx.Envelope
// @Router   /users/{id}/verification/decision [post]
func decideVerification(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Approve bool `json:"approve"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, err := s.DecideVerification(c.Param("id"), b.Approve)
		if err != nil {
			httpx.WriteError(c, 400, "VERIFICATION_INVALID", err.Error())
			return
		}
		c.JSON(200, v)
	}
}

// getProfile godoc
// @Summary  公开主页(用户资料)
// @Tags     users
// @Produce  json
// @Param    id  path  string  true  "user id"
// @Success  200  {object}  Profile
// @Router   /users/{id} [get]
func getProfile(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		p, _ := svc.Get(c.Param("id"))
		c.JSON(http.StatusOK, p)
	}
}

// listUserGames godoc
// @Summary  某用户的作品(works/forks/liked)
// @Tags     users
// @Produce  json
// @Param    id    path   string  true   "user id"
// @Param    type  query  string  false  "works|forks|liked(默认 works)"
// @Param    lang  query  string  false  "展示语言 zh/en/ja(默认 zh)"
// @Success  200   {object}  map[string]interface{}
// @Router   /users/{id}/games [get]
func listUserGames(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		typ := c.DefaultQuery("type", "works")
		lang := c.DefaultQuery("lang", "zh")
		c.JSON(http.StatusOK, gin.H{"items": svc.GamesOf(c.Param("id"), typ, lang)})
	}
}
