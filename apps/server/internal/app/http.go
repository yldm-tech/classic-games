package app

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
)

func NewEngine(cfg HTTPConfig) (*gin.Engine, error) {
	if cfg.MaxBodyBytes <= 0 {
		return nil, fmt.Errorf("http: max body bytes must be positive")
	}

	engine := gin.New()
	engine.Use(gin.Logger(), gin.Recovery(), securityHeaders(cfg.HSTS))
	if err := engine.SetTrustedProxies(cfg.TrustedProxies); err != nil {
		return nil, fmt.Errorf("http: configure trusted proxies: %w", err)
	}
	engine.Use(limitBody(cfg.MaxBodyBytes))
	engine.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})
	return engine, nil
}

func securityHeaders(hsts bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("Referrer-Policy", "no-referrer")
		if hsts {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Next()
	}
}

func limitBody(max int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, max)
		c.Next()
	}
}
