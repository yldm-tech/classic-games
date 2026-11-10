package ai

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"forgeplay/server/internal/quota"
	"forgeplay/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "forgeplay/server/pkg/httpx"
)

// writeError 走 i18n 统一错误信封(docs/09-api-design.md):按请求语言本地化错误码文案,
// 原始细节(provider/校验器报错)塞进 details.detail,既本地化又不丢排错信息。
func writeError(c *gin.Context, status int, code, detail string) {
	i18n.WriteErrorDetail(c, status, code, detail)
}

// RegisterRoutes 把 AI 相关端点挂到 /api/v1 下(docs/09-api-design.md 的 ai 模块)。
// modMiddleware 可选(如限流/配额),按顺序套在 /ai/mod 之前。框架装配在此;核心逻辑在 Service。
func RegisterRoutes(r gin.IRouter, svc *Service, modMiddleware ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	handlers := append(append([]gin.HandlerFunc{}, modMiddleware...), modHandler(svc))
	g.POST("/ai/mod", handlers...)
	structureHandlers := append(append([]gin.HandlerFunc{}, modMiddleware...), structureHandler(svc))
	g.POST("/ai/structure", structureHandlers...)
	g.POST("/ai/balance", balanceHandler(svc))
	g.POST("/ai/validate", validateHandler(svc))
}

// RegisterQuotaRoute mounts the read-only daily quota surface. It must not
// share the Allow middleware — a status check must not consume a slot.
func RegisterQuotaRoute(r gin.IRouter, quotaSvc *quota.Service, middleware ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	handlers := append(append([]gin.HandlerFunc{}, middleware...), quotaHandler(quotaSvc))
	g.GET("/ai/quota", handlers...)
}

func quotaHandler(quotaSvc *quota.Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, quotaSvc.Status(quota.UserOrIP(c)))
	}
}

// balanceHandler godoc
// @Summary      自动平衡 Runtime DSL
// @Description  按目标难度联动调整玩家与敌人/波次参数，返回 JSON Patch、合法新 DSL 和前后压力指标
// @Tags         ai
// @Accept       json
// @Produce      json
// @Param        body  body      BalanceRequest  true  "runtime / current_dsl / target_difficulty"
// @Success      200   {object}  BalanceResponse
// @Failure      400   {object}  httpx.Envelope
// @Failure      422   {object}  httpx.Envelope
// @Router       /ai/balance [post]
func balanceHandler(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req BalanceRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			writeError(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		response, err := svc.AutoBalance(req)
		if err != nil {
			if errors.Is(err, ErrDSLInvalid) {
				writeError(c, http.StatusUnprocessableEntity, "DSL_INVALID", err.Error())
			} else {
				writeError(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			}
			return
		}
		c.JSON(http.StatusOK, response)
	}
}

// structureHandler godoc
// @Summary      生成敌人或波次结构
// @Description  按提示词、数量和难度向 Runtime map 追加不覆盖的结构节点，并经过 Schema 校验
// @Tags         ai
// @Accept       json
// @Produce      json
// @Param        body  body      StructureRequest  true  "runtime / current_dsl / prompt / count / difficulty"
// @Success      200   {object}  StructureResponse
// @Failure      400   {object}  httpx.Envelope
// @Failure      422   {object}  httpx.Envelope
// @Failure      429   {object}  httpx.Envelope
// @Router       /ai/structure [post]
func structureHandler(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req StructureRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			writeError(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		response, err := svc.GenerateStructure(c.Request.Context(), req)
		if err != nil {
			switch {
			case errors.Is(err, ErrInvalidStructure):
				// Request rejected before the provider call, so quota middleware may refund.
				writeError(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			case errors.Is(err, ErrDSLInvalid):
				c.Set(quota.CtxBilled, true)
				writeError(c, http.StatusUnprocessableEntity, "DSL_INVALID", err.Error())
			default:
				// Any other error occurs after invoking the configured provider and can
				// represent real token cost even when parsing/network handling failed.
				c.Set(quota.CtxBilled, true)
				writeError(c, http.StatusBadGateway, "PROVIDER_ERROR", err.Error())
			}
			return
		}
		c.JSON(http.StatusOK, response)
	}
}

// modHandler godoc
// @Summary      AI 改 DSL(核心接口)
// @Description  自然语言 + 当前 DSL → 6902 补丁 → apply → schema 校验 → 新 DSL
// @Tags         ai
// @Accept       json
// @Produce      json
// @Param        body  body      ModRequest  true  "runtime / current_dsl / prompt"
// @Success      200   {object}  ModResponse
// @Failure      400   {object}  httpx.Envelope  "BAD_REQUEST"
// @Failure      422   {object}  httpx.Envelope  "DSL_INVALID"
// @Failure      429   {object}  httpx.Envelope  "QUOTA_EXCEEDED"
// @Router       /ai/mod [post]
func modHandler(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req ModRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			writeError(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		resp, err := svc.GenerateMod(c.Request.Context(), req)
		if err != nil {
			switch {
			case errors.Is(err, ErrNoCurrentDSL):
				// 调 provider 之前的前置校验失败:无 LLM 成本,配额可回补。
				writeError(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			case errors.Is(err, ErrDSLInvalid):
				// 重试耗尽仍不合法:provider 已被调用(含重试),有真实成本 → 标记已计费,不退配额。
				c.Set(quota.CtxBilled, true)
				writeError(c, http.StatusUnprocessableEntity, "DSL_INVALID", err.Error())
			default:
				// provider 自身错误(网络/限流/模型不可用等):provider 已被调用 → 标记已计费。
				c.Set(quota.CtxBilled, true)
				writeError(c, http.StatusBadGateway, "PROVIDER_ERROR", err.Error())
			}
			return
		}
		c.JSON(http.StatusOK, resp)
	}
}

// validateHandler godoc
// @Summary      校验 DSL 是否合法
// @Tags         ai
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]bool
// @Failure      422  {object}  httpx.Envelope
// @Router       /ai/validate [post]
func validateHandler(svc *Service) gin.HandlerFunc {
	type validateReq struct {
		Runtime string         `json:"runtime"`
		DSL     map[string]any `json:"dsl"`
	}
	return func(c *gin.Context) {
		var req validateReq
		if err := c.ShouldBindJSON(&req); err != nil {
			writeError(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		if err := svc.Validate(req.Runtime, req.DSL); err != nil {
			writeError(c, http.StatusUnprocessableEntity, "DSL_INVALID", err.Error())
			return
		}
		c.JSON(http.StatusOK, gin.H{"valid": true})
	}
}
