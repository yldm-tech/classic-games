package quota

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func TestMiddleware_BlocksOverQuota(t *testing.T) {
	r := gin.New()
	svc := NewService(2)
	r.POST("/x", Middleware(svc, func(c *gin.Context) string { return "u1" }), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	hit := func() int {
		req := httptest.NewRequest(http.MethodPost, "/x", nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w.Code
	}

	if hit() != 200 || hit() != 200 {
		t.Fatal("前两次应放行")
	}
	if hit() != http.StatusTooManyRequests {
		t.Error("第三次应 429 QUOTA_EXCEEDED")
	}
}

// 下游失败(>=400)应回补额度,不白扣。
func TestMiddleware_RefundsOnDownstreamError(t *testing.T) {
	r := gin.New()
	svc := NewService(1)
	r.POST("/x", Middleware(svc, func(c *gin.Context) string { return "u1" }), func(c *gin.Context) {
		c.JSON(http.StatusBadGateway, gin.H{"error": "provider down"}) // 模拟 AI provider 故障
	})
	hit := func() int {
		req := httptest.NewRequest(http.MethodPost, "/x", nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w.Code
	}
	// 配额=1;两次都因下游 502 被回补,所以两次都能进入处理器(都返回 502 而非 429)
	if hit() != http.StatusBadGateway || hit() != http.StatusBadGateway {
		t.Error("下游失败应回补额度,不应在第二次被 429 拦截")
	}
	if svc.Remaining("u1") != 1 {
		t.Errorf("失败请求不应消耗额度, 剩余 %d 期望 1", svc.Remaining("u1"))
	}
}

// 已计费的下游失败(provider 已被调用,有真实成本)不应回补——否则「失败即免费」可刷爆成本。
func TestMiddleware_NoRefundWhenBilled(t *testing.T) {
	r := gin.New()
	svc := NewService(1)
	r.POST("/x", Middleware(svc, func(c *gin.Context) string { return "u1" }), func(c *gin.Context) {
		c.Set(CtxBilled, true) // 模拟 LLM provider 已被调用
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "DSL_INVALID"})
	})
	hit := func() int {
		req := httptest.NewRequest(http.MethodPost, "/x", nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w.Code
	}
	// 配额=1:第一次进处理器返回 422(已计费,不退);第二次应被 429 拦截。
	if hit() != http.StatusUnprocessableEntity {
		t.Fatal("第一次应进入处理器返回 422")
	}
	if hit() != http.StatusTooManyRequests {
		t.Error("已计费失败不回补,第二次应 429")
	}
	if svc.Remaining("u1") != 0 {
		t.Errorf("已计费请求应消耗额度, 剩余 %d 期望 0", svc.Remaining("u1"))
	}
}
