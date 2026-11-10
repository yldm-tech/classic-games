package quota

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"forgeplay/server/pkg/i18n"
)

// CtxBilled 是上下文标记:置位表示本请求已发生真实下游成本(如已调用 LLM provider)。
// 已计费的请求即便返回 4xx/5xx 也不退配额——否则「失败即免费」会让人用必然失败的输入
// (如刻意构造非法 DSL,触发最多 3 次真实 Claude 调用后返回 422)无限刷爆成本。
const CtxBilled = "quota_billed"

// Middleware 按 key(用户)消耗配额;超额返回 429 QUOTA_EXCEEDED。
// key 通常优先取鉴权注入的 user_id,无登录时退回 client IP。
func Middleware(svc *Service, key func(*gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		k := key(c)
		if ok, _ := svc.Allow(k); !ok {
			i18n.WriteError(c, http.StatusTooManyRequests, "QUOTA_EXCEEDED")
			c.Abort()
			return
		}
		c.Next()
		// 仅「未发生真实成本」的失败才回补(如请求体非法、前置校验未过,在调 provider 之前就返回)。
		// 已计费的失败(provider 已被调用)不退,守住成本闸门。
		if c.Writer.Status() >= 400 && !c.GetBool(CtxBilled) {
			svc.Refund(k)
		}
	}
}

// CtxUserIsGuest mirrors the context key the auth middleware sets for a self-issued guest token. It is duplicated as a
// plain string rather than imported so this package stays free of domain dependencies.
const CtxUserIsGuest = "user_is_guest"

// UserOrIP 是默认 key:有登录用 user_id,否则 client IP。
//
// Guests are the exception, and they are the reason this function cannot simply trust user_id. POST /auth/guest is
// public and unmetered, so a caller who wants a second daily allowance only has to ask for another guest token: a new
// user id is a new bucket, and the cost gate that quota exists to be — the one docs/14-security-compliance.md calls for
// on the paid LLM endpoints — stops holding. A guest identity costs nothing to mint, so it cannot be the unit that
// meters a resource that costs money; guests are metered by the address they arrive from, like any other anonymous
// caller. Real, claimed identities keep their own per-user allowance.
func UserOrIP(c *gin.Context) string {
	if c.GetBool(CtxUserIsGuest) {
		return c.ClientIP()
	}
	if v, ok := c.Get("user_id"); ok {
		if id, ok := v.(string); ok && id != "" {
			return id
		}
	}
	return c.ClientIP()
}
