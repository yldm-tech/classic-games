package app

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestNewEngineRegistersHealthEndpoint(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine, err := NewEngine(HTTPConfig{MaxBodyBytes: 1024})
	if err != nil {
		t.Fatalf("NewEngine: %v", err)
	}

	response := httptest.NewRecorder()
	engine.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", response.Code, response.Body.String())
	}
	if got := response.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q", got)
	}
	if got := response.Header().Get("X-Frame-Options"); got != "DENY" {
		t.Fatalf("X-Frame-Options = %q", got)
	}
	if got := response.Header().Get("Referrer-Policy"); got != "no-referrer" {
		t.Fatalf("Referrer-Policy = %q", got)
	}
	if got := response.Header().Get("Strict-Transport-Security"); got != "" {
		t.Fatalf("HSTS should be opt-in, got %q", got)
	}
	var body struct {
		OK bool `json:"ok"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil || !body.OK {
		t.Fatalf("health body = %s, err=%v", response.Body.String(), err)
	}
}

func TestNewEngineSetsHSTSWhenEnabled(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine, err := NewEngine(HTTPConfig{MaxBodyBytes: 1024, HSTS: true})
	if err != nil {
		t.Fatalf("NewEngine: %v", err)
	}
	response := httptest.NewRecorder()
	engine.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if got := response.Header().Get("Strict-Transport-Security"); got != "max-age=31536000; includeSubDomains" {
		t.Fatalf("HSTS = %q", got)
	}
}

func TestNewEngineLimitsRequestBodies(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine, err := NewEngine(HTTPConfig{MaxBodyBytes: 4})
	if err != nil {
		t.Fatalf("NewEngine: %v", err)
	}
	engine.POST("/read", func(c *gin.Context) {
		if _, readErr := io.ReadAll(c.Request.Body); readErr != nil {
			c.Status(http.StatusRequestEntityTooLarge)
			return
		}
		c.Status(http.StatusNoContent)
	})

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/read", strings.NewReader("12345"))
	engine.ServeHTTP(response, request)
	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusRequestEntityTooLarge)
	}
}

func TestNewEngineDoesNotTrustUnconfiguredProxyHeaders(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine, err := NewEngine(HTTPConfig{MaxBodyBytes: 1024})
	if err != nil {
		t.Fatalf("NewEngine: %v", err)
	}
	engine.GET("/client-ip", func(c *gin.Context) { c.String(http.StatusOK, c.ClientIP()) })

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/client-ip", nil)
	request.RemoteAddr = "192.0.2.10:4321"
	request.Header.Set("X-Forwarded-For", "203.0.113.99")
	engine.ServeHTTP(response, request)
	if got := response.Body.String(); got != "192.0.2.10" {
		t.Fatalf("client IP = %q, proxy header was trusted", got)
	}
}

func TestNewEngineRejectsInvalidTrustedProxy(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if _, err := NewEngine(HTTPConfig{TrustedProxies: []string{"not-a-cidr"}, MaxBodyBytes: 1024}); err == nil {
		t.Fatal("NewEngine returned nil error")
	}
}
