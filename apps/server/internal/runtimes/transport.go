// Package runtimes 暴露 Runtime 元数据接口(当前:DSL JSON Schema)。
// schema 文件取自 packages/schemas,这是生产唯一实现;docs/10-data-model.md 早期设想过一张
// runtimes 表,但从未落地,不要按那份文档去找 DB 表。
package runtimes

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/i18n"

	// swag resolves the httpx.Envelope named in the annotations of this file through its imports; the handlers themselves write errors through i18n.
	_ "github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

// safeSegment 限制 name/version 字符集;配合 ".." 检查,杜绝把入参拼进路径造成穿越(系统边界)。
var safeSegment = regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)

func isSafeSegment(s string) bool {
	return safeSegment.MatchString(s) && !strings.Contains(s, "..")
}

// RegisterRoutes 挂载 runtimes 端点。baselineDir 指向 apps/client/runtime。
func RegisterRoutes(r gin.IRouter, schemaDir, baselineDir string) {
	g := r.Group("/api/v1")
	g.GET("/runtimes/:name/:version/schema", schemaHandler(schemaDir))
	g.GET("/runtimes/:name/:version/baseline", baselineHandler(baselineDir))
}

// baselineHandler godoc
// @Summary      取 Runtime 基线 DSL
// @Tags         runtimes
// @Produce      json
// @Param        name     path      string  true  "runtime 名,如 shooter"
// @Param        version  path      string  true  "版本,如 1.0.0"
// @Success      200      {object}  map[string]interface{}
// @Failure      400      {object}  httpx.Envelope  "BAD_REQUEST"
// @Failure      404      {object}  httpx.Envelope  "NOT_FOUND"
// @Router       /runtimes/{name}/{version}/baseline [get]
func baselineHandler(baselineDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		name, version := c.Param("name"), c.Param("version")
		if !isSafeSegment(name) || !isSafeSegment(version) {
			i18n.WriteError(c, http.StatusBadRequest, "BAD_REQUEST")
			return
		}
		data, err := os.ReadFile(filepath.Join(baselineDir, name, "baseline.dsl.json"))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusNotFound, "NOT_FOUND", name+"@"+version)
			return
		}
		var doc map[string]any
		if json.Unmarshal(data, &doc) != nil || baselineVersion(doc) != version {
			i18n.WriteErrorDetail(c, http.StatusNotFound, "NOT_FOUND", name+"@"+version)
			return
		}
		c.Data(http.StatusOK, "application/json; charset=utf-8", data)
	}
}

func baselineVersion(doc map[string]any) string {
	meta, _ := doc["meta"].(map[string]any)
	version, _ := meta["runtime_version"].(string)
	return version
}

// schemaHandler godoc
// @Summary      取 Runtime 的 DSL JSON Schema(客户端校验 / AI 约束用)
// @Tags         runtimes
// @Produce      json
// @Param        name     path      string  true  "runtime 名,如 shooter"
// @Param        version  path      string  true  "版本,如 1.0.0"
// @Success      200      {object}  map[string]interface{}
// @Failure      400      {object}  httpx.Envelope  "BAD_REQUEST"
// @Failure      404      {object}  httpx.Envelope  "NOT_FOUND"
// @Router       /runtimes/{name}/{version}/schema [get]
func schemaHandler(schemaDir string) gin.HandlerFunc {
	return func(c *gin.Context) {
		name := c.Param("name")
		version := c.Param("version")
		if !isSafeSegment(name) || !isSafeSegment(version) {
			i18n.WriteError(c, http.StatusBadRequest, "BAD_REQUEST")
			return
		}
		data, err := os.ReadFile(filepath.Join(schemaDir, name+"-"+version+".schema.json"))
		if err != nil {
			i18n.WriteErrorDetail(c, http.StatusNotFound, "NOT_FOUND", name+"@"+version)
			return
		}
		c.Data(http.StatusOK, "application/json; charset=utf-8", data)
	}
}
