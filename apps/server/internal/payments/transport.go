package payments

import (
	"github.com/gin-gonic/gin"
	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
	"net/http"
)

func RegisterRoutes(r gin.IRouter, s *Service, auth gin.HandlerFunc) {
	g := r.Group("/api/v1/payments")
	if auth != nil {
		g.Use(auth)
	}
	g.POST("/orders", createOrder(s))
	g.GET("/orders", listOrders(s))
	g.GET("/orders/:id", getOrder(s))
	r.POST("/api/v1/payments/webhook", paymentsWebhook(s))
}

// listOrders godoc
// @Summary  当前用户的支付订单
// @Tags     payments
// @Produce  json
// @Success  200 {object}  map[string]interface{}
// @Failure  500 {object}  httpx.Envelope  "PAYMENT_ERROR"
// @Router   /payments/orders [get]
func listOrders(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		items, e := s.List(c.GetString("user_id"))
		if e != nil {
			httpx.WriteError(c, 500, "PAYMENT_ERROR", e.Error())
			return
		}
		c.JSON(200, gin.H{"items": items})
	}
}

// createOrder godoc
// @Summary  创建支付订单
// @Tags     payments
// @Accept   json
// @Produce  json
// @Param    body  body      object{product_id=string}  true  "商品 id"
// @Success  201   {object}  Order
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / PAYMENT_INVALID"
// @Router   /payments/orders [post]
func createOrder(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			ProductID string `json:"product_id"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		o, e := s.Create(c.GetString("user_id"), b.ProductID)
		if e != nil {
			httpx.WriteError(c, 400, "PAYMENT_INVALID", e.Error())
			return
		}
		c.JSON(http.StatusCreated, o)
	}
}

// getOrder godoc
// @Summary  查询支付订单
// @Tags     payments
// @Produce  json
// @Param    id  path      string  true  "order id"
// @Success  200 {object}  Order
// @Failure  404 {object}  httpx.Envelope  "PAYMENT_NOT_FOUND"
// @Router   /payments/orders/{id} [get]
func getOrder(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		o, e := s.Get(c.GetString("user_id"), c.Param("id"))
		if e != nil {
			httpx.WriteError(c, 404, "PAYMENT_NOT_FOUND", e.Error())
			return
		}
		c.JSON(200, o)
	}
}

// paymentsWebhook godoc
// @Summary  支付渠道回调(确认订单支付结果)
// @Tags     payments
// @Accept   json
// @Produce  json
// @Param    body  body      object{order_id=string,transaction_id=string,amount=int,currency=string}  true  "回调载荷,需带 X-Classic-Games-Signature 签名头"
// @Success  200   {object}  Order
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / PAYMENT_REJECTED(签名或状态不合法)"
// @Router   /payments/webhook [post]
func paymentsWebhook(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			OrderID       string `json:"order_id"`
			TransactionID string `json:"transaction_id"`
			Amount        int64  `json:"amount"`
			Currency      string `json:"currency"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		o, e := s.Confirm(b.OrderID, b.TransactionID, b.Amount, b.Currency, c.GetHeader("X-Classic-Games-Signature"))
		if e != nil {
			httpx.WriteError(c, 400, "PAYMENT_REJECTED", e.Error())
			return
		}
		c.JSON(200, o)
	}
}
