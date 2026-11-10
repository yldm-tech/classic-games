package meta

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Snapshot returns the public, non-secret capability surface.
type Snapshot func() map[string]any

// RegisterRoutes mounts GET /api/v1/meta. No auth: clients use this to show
// honest "not configured yet" status before operators wire secrets.
func RegisterRoutes(r gin.IRouter, snapshot Snapshot) {
	r.GET("/api/v1/meta", func(c *gin.Context) {
		if snapshot == nil {
			c.JSON(http.StatusOK, map[string]any{})
			return
		}
		c.JSON(http.StatusOK, snapshot())
	})
}
