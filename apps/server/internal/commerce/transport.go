package commerce

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"forgeplay/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "forgeplay/server/pkg/httpx"
)

// RegisterRoutes 挂载 commerce 只读端点(消费/福利内容)。全部为公开读接口,无鉴权,
// 与 games 读接口同。每个 handler 读 ?lang=(zh/en/ja,默认 zh)做文本本地化。
func RegisterRoutes(r gin.IRouter, svc *Service, middleware ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if len(middleware) > 0 && middleware[0] != nil {
		g.Use(middleware[0])
	}
	g.GET("/points", getPoints(svc))
	g.GET("/shop", getShop(svc))
	g.GET("/membership", getMembership(svc))
	g.GET("/welfare", getWelfare(svc))
	g.GET("/events", listEvents(svc))
	g.GET("/achievements", listAchievements(svc))
	g.GET("/avatar", listAvatar(svc))
	w := r.Group("/api/v1")
	if len(middleware) > 1 && middleware[1] != nil {
		w.Use(middleware[1])
	}
	w.POST("/shop/purchase/:id", purchase(svc))
	w.POST("/welfare/checkin", checkin(svc))
	w.POST("/welfare/quests/:id/claim", claimQuest(svc))
	w.POST("/achievements/:id/claim", claimAchievement(svc))
	w.POST("/avatar/equip", equip(svc))
	w.POST("/live/:id/gift", liveGift(svc))
}

// langOf 解析请求语言:?lang= 优先,其次 Accept-Language,最后默认 zh(走 i18n 统一规则)。
func langOf(c *gin.Context) string { return i18n.Lang(c) }

// getPoints godoc
// @Summary  创作点(余额 + 流水 + 收益中心)
// @Tags     commerce
// @Produce  json
// @Param    lang  query     string  false  "zh/en/ja,默认 zh"
// @Success  200   {object}  PointsView
// @Router   /points [get]
func getPoints(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(200, svc.PointsFor(c.GetString("user_id"), langOf(c)))
	}
}

// getShop godoc
// @Summary  商城(皮肤 / 道具 / 充值档)
// @Tags     commerce
// @Produce  json
// @Param    lang  query     string  false  "zh/en/ja,默认 zh"
// @Success  200   {object}  ShopView
// @Router   /shop [get]
func getShop(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(200, svc.ShopFor(c.GetString("user_id"), langOf(c)))
	}
}

// getMembership godoc
// @Summary  会员 ForgePlay+(权益 + 套餐)
// @Tags     commerce
// @Produce  json
// @Param    lang  query     string  false  "zh/en/ja,默认 zh"
// @Success  200   {object}  MembershipView
// @Router   /membership [get]
func getMembership(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(200, svc.MembershipFor(c.GetString("user_id"), langOf(c)))
	}
}

// getWelfare godoc
// @Summary  福利中心(签到 + 任务 + 邀请)
// @Tags     commerce
// @Produce  json
// @Param    lang  query     string  false  "zh/en/ja,默认 zh"
// @Success  200   {object}  WelfareView
// @Router   /welfare [get]
func getWelfare(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(200, svc.WelfareFor(c.GetString("user_id"), langOf(c)))
	}
}

// listEvents godoc
// @Summary  限时活动列表
// @Tags     commerce
// @Produce  json
// @Param    lang  query     string  false  "zh/en/ja,默认 zh"
// @Success  200   {object}  map[string]interface{}
// @Router   /events [get]
func listEvents(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(200, gin.H{"items": svc.Events(langOf(c))})
	}
}

// listAchievements godoc
// @Summary  成就列表
// @Tags     commerce
// @Produce  json
// @Param    lang  query     string  false  "zh/en/ja,默认 zh"
// @Success  200   {object}  map[string]interface{}
// @Router   /achievements [get]
func listAchievements(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(200, gin.H{"items": svc.AchievementsFor(c.GetString("user_id"), langOf(c))})
	}
}

// listAvatar godoc
// @Summary  形象装扮目录(角色 / 座驾 / 特效)
// @Tags     commerce
// @Produce  json
// @Param    lang  query     string  false  "zh/en/ja,默认 zh"
// @Success  200   {object}  map[string]interface{}
// @Router   /avatar [get]
func listAvatar(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(200, gin.H{"items": svc.AvatarFor(c.GetString("user_id"), langOf(c))})
	}
}

func commerceError(c *gin.Context, err error) {
	status := http.StatusBadRequest
	if err == ErrItemNotFound {
		status = http.StatusNotFound
	}
	i18n.WriteErrorDetail(c, status, "COMMERCE_INVALID", err.Error())
}

// purchase godoc
// @Summary  购买商城商品(皮肤 / 道具,扣创作点)
// @Tags     commerce
// @Produce  json
// @Param    id  path      string  true  "商品 id"
// @Success  200  {object}  map[string]interface{}  "balance + owned"
// @Failure  400  {object}  httpx.Envelope  "COMMERCE_INVALID(余额不足)"
// @Failure  404  {object}  httpx.Envelope  "COMMERCE_INVALID(商品不存在)"
// @Router   /shop/purchase/{id} [post]
func purchase(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		balance, err := s.Purchase(c.GetString("user_id"), c.Param("id"))
		if err != nil {
			commerceError(c, err)
			return
		}
		c.JSON(200, gin.H{"balance": balance, "owned": true})
	}
}

// checkin godoc
// @Summary  每日签到(领取创作点奖励)
// @Tags     commerce
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "balance + reward + checked"
// @Failure  400  {object}  httpx.Envelope  "COMMERCE_INVALID(今日已签到)"
// @Router   /welfare/checkin [post]
func checkin(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		balance, reward, err := s.Checkin(c.GetString("user_id"))
		if err != nil {
			commerceError(c, err)
			return
		}
		c.JSON(200, gin.H{"balance": balance, "reward": reward, "checked": true})
	}
}

// claimQuest godoc
// @Summary  领取福利任务奖励
// @Tags     commerce
// @Produce  json
// @Param    id  path      string  true  "任务 id"
// @Success  200  {object}  map[string]interface{}  "balance + reward + claimed"
// @Failure  400  {object}  httpx.Envelope  "COMMERCE_INVALID(未达成 / 已领取)"
// @Failure  404  {object}  httpx.Envelope  "COMMERCE_INVALID(任务不存在)"
// @Router   /welfare/quests/{id}/claim [post]
func claimQuest(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		balance, reward, err := s.ClaimQuest(c.GetString("user_id"), c.Param("id"))
		if err != nil {
			commerceError(c, err)
			return
		}
		c.JSON(200, gin.H{"balance": balance, "reward": reward, "claimed": true})
	}
}

// claimAchievement godoc
// @Summary  领取成就奖励
// @Tags     commerce
// @Produce  json
// @Param    id  path      string  true  "成就 id"
// @Success  200  {object}  map[string]interface{}  "balance + reward + claimed"
// @Failure  400  {object}  httpx.Envelope  "COMMERCE_INVALID(未达成 / 已领取)"
// @Failure  404  {object}  httpx.Envelope  "COMMERCE_INVALID(成就不存在)"
// @Router   /achievements/{id}/claim [post]
func claimAchievement(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		balance, reward, err := s.ClaimAchievement(c.GetString("user_id"), c.Param("id"))
		if err != nil {
			commerceError(c, err)
			return
		}
		c.JSON(200, gin.H{"balance": balance, "reward": reward, "claimed": true})
	}
}

// equip godoc
// @Summary  装扮换装(角色 / 座驾 / 特效)
// @Tags     commerce
// @Accept   json
// @Produce  json
// @Success  200  {object}  map[string]interface{}  "equipped"
// @Failure  400  {object}  httpx.Envelope  "BAD_REQUEST(请求体非法) / COMMERCE_INVALID(未拥有该道具)"
// @Router   /avatar/equip [post]
func equip(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Category string `json:"category"`
			Item     string `json:"item"`
		}
		if c.ShouldBindJSON(&b) != nil {
			i18n.WriteError(c, 400, "BAD_REQUEST")
			return
		}
		if err := s.Equip(c.GetString("user_id"), b.Category, b.Item); err != nil {
			commerceError(c, err)
			return
		}
		c.JSON(200, gin.H{"equipped": true})
	}
}

// liveGift godoc
// @Summary  直播间刷礼物(扣创作点)
// @Tags     commerce
// @Produce  json
// @Param    id  path      string  true  "直播 id"
// @Success  200  {object}  map[string]interface{}  "balance + cost + sent"
// @Failure  400  {object}  httpx.Envelope  "COMMERCE_INVALID(余额不足)"
// @Router   /live/{id}/gift [post]
func liveGift(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		const cost = 10
		balance, err := s.SendLiveGift(c.GetString("user_id"), cost)
		if err != nil {
			commerceError(c, err)
			return
		}
		c.JSON(200, gin.H{"balance": balance, "cost": cost, "sent": true})
	}
}
