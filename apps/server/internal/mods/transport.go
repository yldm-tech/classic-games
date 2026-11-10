package mods

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"
	"github.com/yldm-tech/classic-games/packages/dsl"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

// RegisterRoutes 挂载 mods/Fork 相关端点(docs/09-api-design.md 的 mods/forks)。
// 读接口(取生效 DSL / 创作链 / Fork Tree)公开;写接口(建 mod / Fork)套 authMW——
// 建 mod 与 Fork 都落持久化记录,身份一律取自 token,不接受匿名写入(与 games/social/moderation 一致,
// 见 main.go「写接口身份一律取自 token」策略)。authMW 可省略(测试/无鉴权场景),此时写接口开放。
func RegisterRoutes(r gin.IRouter, svc *Service, authMW ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if len(authMW) > 1 && authMW[1] != nil {
		g.Use(authMW[1])
	}
	g.GET("/mods/:id/dsl", effectiveDSL(svc))
	g.GET("/mods/:id/lineage", lineage(svc))
	g.GET("/mods/:id/fork-tree", forkTree(svc))

	w := r.Group("/api/v1")
	if len(authMW) > 0 && authMW[0] != nil {
		w.Use(authMW[0])
	}
	w.POST("/mods", createMod(svc))
	w.POST("/mods/:id/fork", forkMod(svc))
	w.GET("/mods/mine", listMyMods(svc))
	w.GET("/drafts", listDrafts(svc))
	w.PUT("/drafts/:id", saveDraft(svc))
}

// listMyMods godoc
// @Summary  我创建的 mod(全部,含草稿与已用于发布的)
// @Tags     mods
// @Produce  json
// @Success  200  {object}  map[string]interface{}
// @Failure  500  {object}  httpx.Envelope
// @Router   /mods/mine [get]
func listMyMods(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, e := svc.Mine(c.GetString("user_id"))
		if e != nil {
			writeModErr(c, e)
			return
		}
		c.JSON(200, gin.H{"items": items})
	}
}

// listDrafts godoc
// @Summary  我的草稿(未发布的 Mod)
// @Tags     mods
// @Produce  json
// @Success  200  {object}  map[string]interface{}
// @Failure  500  {object}  httpx.Envelope
// @Router   /drafts [get]
func listDrafts(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, e := svc.Drafts(c.GetString("user_id"))
		if e != nil {
			writeModErr(c, e)
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// saveDraft godoc
// @Summary  以当前草稿为父保存不可变新版本(RFC 6902 patch)
// @Tags     mods
// @Accept   json
// @Produce  json
// @Param    id    path      string                   true  "草稿 mod id"
// @Param    body  body      object{patch=[]dsl.Op}    true  "RFC 6902 补丁"
// @Success  201   {object}  Mod
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST"
// @Router   /drafts/{id} [put]
func saveDraft(svc *Service) gin.HandlerFunc {
	type request struct {
		Patch []dsl.Op `json:"patch"`
	}
	return func(c *gin.Context) {
		var body request
		if err := c.ShouldBindJSON(&body); err != nil {
			i18n.WriteErrorDetail(c, 400, "BAD_REQUEST", err.Error())
			return
		}
		mod, err := svc.SaveDraftFor(c.GetString("user_id"), c.Param("id"), body.Patch)
		if err != nil {
			writeModErr(c, err)
			return
		}
		c.JSON(http.StatusCreated, mod)
	}
}

// lineage godoc
// @Summary  创作链(根 → 当前)
// @Tags     mods
// @Produce  json
// @Param    id  path  string  true  "mod id"
// @Success  200  {object}  map[string]interface{}
// @Router   /mods/{id}/lineage [get]
func lineage(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.CanRead(c.Param("id"), c.GetString("user_id")); err != nil {
			writeModErr(c, err)
			return
		}
		chain, err := svc.Lineage(c.Param("id"), c.GetString("user_id"))
		if err != nil {
			writeModErr(c, err)
			return
		}
		c.JSON(http.StatusOK, gin.H{"items": chain})
	}
}

// forkTree godoc
// @Summary  Fork Tree(祖先链 + 自身 + 直接子)
// @Tags     mods
// @Produce  json
// @Param    id  path  string  true  "mod id"
// @Success  200  {object}  ForkTreeView
// @Router   /mods/{id}/fork-tree [get]
func forkTree(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.CanRead(c.Param("id"), c.GetString("user_id")); err != nil {
			writeModErr(c, err)
			return
		}
		view, err := svc.ForkTree(c.Param("id"), c.GetString("user_id"))
		if err != nil {
			writeModErr(c, err)
			return
		}
		c.JSON(http.StatusOK, view)
	}
}

type createModReq struct {
	Runtime  string   `json:"runtime"`
	ParentID string   `json:"parent_id"`
	Patch    []dsl.Op `json:"patch"`
	// AIProvenance 是 /ai/mod 返回的溯源令牌;校验通过则该 mod 被标记为 AI 生成(防漏标)。
	AIProvenance string `json:"ai_provenance"`
	Draft        bool   `json:"draft"`
}

// createMod godoc
// @Summary  建 mod(parent_id 空=根,否则子 mod)
// @Tags     mods
// @Accept   json
// @Produce  json
// @Param    body  body      createModReq  true  "runtime / parent_id / patch"
// @Success  201   {object}  Mod
// @Router   /mods [post]
func createMod(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req createModReq
		if err := c.ShouldBindJSON(&req); err != nil {
			i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
			return
		}
		var (
			m   Mod
			err error
		)
		ai := svc.VerifyProvenance(req.AIProvenance) // 仅有效令牌才标记 AI 生成,客户端无法伪造
		if req.ParentID == "" {
			m, err = svc.CreateRootFor(c.GetString("user_id"), req.Runtime, req.Patch, ai, req.Draft)
		} else {
			m, err = svc.CreateChildFor(c.GetString("user_id"), req.ParentID, req.Patch, ai, req.Draft)
		}
		if err != nil {
			writeModErr(c, err)
			return
		}
		c.JSON(http.StatusCreated, m)
	}
}

// forkMod godoc
// @Summary  Fork 出新草稿
// @Tags     mods
// @Produce  json
// @Param    id   path      string  true  "mod id"
// @Success  201  {object}  Mod
// @Router   /mods/{id}/fork [post]
func forkMod(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		m, err := svc.ForkFor(c.GetString("user_id"), c.Param("id"))
		if err != nil {
			writeModErr(c, err)
			return
		}
		c.JSON(http.StatusCreated, m)
	}
}

// effectiveDSL godoc
// @Summary  取生效 DSL(基线 + 补丁链)
// @Tags     mods
// @Produce  json
// @Param    id   path      string  true  "mod id"
// @Success  200  {object}  map[string]interface{}
// @Failure  404  {object}  httpx.Envelope
// @Router   /mods/{id}/dsl [get]
func effectiveDSL(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := svc.CanRead(c.Param("id"), c.GetString("user_id")); err != nil {
			writeModErr(c, err)
			return
		}
		eff, err := svc.EffectiveDSL(c.Param("id"))
		if err != nil {
			writeModErr(c, err)
			return
		}
		c.JSON(http.StatusOK, eff)
	}
}

func writeModErr(c *gin.Context, err error) {
	if errors.Is(err, ErrForbidden) {
		i18n.WriteErrorDetail(c, http.StatusForbidden, "FORBIDDEN", err.Error())
		return
	}
	if errors.Is(err, ErrNotDraft) {
		i18n.WriteErrorDetail(c, http.StatusConflict, "INVALID_STATE", err.Error())
		return
	}
	if errors.Is(err, ErrNotFound) {
		i18n.WriteErrorDetail(c, http.StatusNotFound, "NOT_FOUND", err.Error())
		return
	}
	// 补丁 apply 失败等当作不可处理实体
	i18n.WriteErrorDetail(c, http.StatusUnprocessableEntity, "DSL_INVALID", err.Error())
}
