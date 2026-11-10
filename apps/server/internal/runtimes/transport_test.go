package runtimes

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// schemaDir 指向仓库内 packages/schemas(runtimes 包在 apps/server/internal/runtimes/,到仓库根是 4 层)。
func testRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterRoutes(r, filepath.Join("..", "..", "..", "..", "packages", "schemas"), filepath.Join("..", "..", "..", "..", "apps", "client", "runtime"))
	return r
}

func get(r *gin.Engine, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestSchema_Found(t *testing.T) {
	w := get(testRouter(), "/api/v1/runtimes/shooter/1.0.0/schema")
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d, 期望 200; body=%s", w.Code, w.Body)
	}
	if ct := w.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Errorf("Content-Type=%q, 期望 application/json", ct)
	}
	var doc map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &doc); err != nil {
		t.Fatalf("返回体不是合法 JSON: %v", err)
	}
	if _, ok := doc["$schema"]; !ok {
		t.Errorf("返回体缺 $schema,似乎不是 schema 文件")
	}
}

func TestSchema_NotFound(t *testing.T) {
	w := get(testRouter(), "/api/v1/runtimes/shooter/9.9.9/schema")
	if w.Code != http.StatusNotFound {
		t.Fatalf("status=%d, 期望 404", w.Code)
	}
	if !strings.Contains(w.Body.String(), "NOT_FOUND") {
		t.Errorf("body=%s, 期望 NOT_FOUND 信封", w.Body)
	}
}

func TestSchema_RejectsTraversal(t *testing.T) {
	w := get(testRouter(), "/api/v1/runtimes/a..b/1.0.0/schema")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status=%d, 期望 400; body=%s", w.Code, w.Body)
	}
	if !strings.Contains(w.Body.String(), "BAD_REQUEST") {
		t.Errorf("body=%s, 期望 BAD_REQUEST 信封", w.Body)
	}
}

func TestBaseline_Found(t *testing.T) {
	w := get(testRouter(), "/api/v1/runtimes/survivor/1.0.0/baseline")
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d, 期望 200; body=%s", w.Code, w.Body)
	}
	var doc map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &doc); err != nil {
		t.Fatalf("返回体不是合法 JSON: %v", err)
	}
	if doc["meta"].(map[string]any)["runtime"] != "survivor" {
		t.Fatalf("返回了错误 baseline: %v", doc["meta"])
	}
}
