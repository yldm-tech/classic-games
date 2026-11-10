// Package httpx 是跨模块复用的 HTTP 横切设施(错误信封、分页游标等),见 apps/server/README.md。
package httpx

import "github.com/gin-gonic/gin"

// Envelope 是统一错误信封,对齐 docs/09-api-design.md:
//
//	{ "error": { "code": "...", "message": "...", "details": {} } }
type Envelope struct {
	Error Body `json:"error"`
}

type Body struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

// WriteError 用统一信封写错误响应。各模块 handler 复用,保证错误形态一致。
func WriteError(c *gin.Context, status int, code, msg string) {
	c.JSON(status, Envelope{Error: Body{Code: code, Message: msg}})
}
