package i18n

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestNormalize(t *testing.T) {
	cases := map[string]string{
		"en": "en", "EN": "en", "ja": "ja", "ja-JP": "ja", "zh-Hans": "zh",
		"": "zh", "fr": "zh", "  En  ": "en",
	}
	for in, want := range cases {
		if got := Normalize(in); got != want {
			t.Errorf("Normalize(%q)=%q, 期望 %q", in, got, want)
		}
	}
}

func TestT(t *testing.T) {
	if got := T("en", "NOT_FOUND"); got != "The requested resource was not found" {
		t.Errorf("T(en,NOT_FOUND)=%q", got)
	}
	if got := T("ja", "INSUFFICIENT"); got != "創作ポイントが不足しています" {
		t.Errorf("T(ja,INSUFFICIENT)=%q", got)
	}
	// 不支持的语言回落 zh
	if got := T("fr", "FORBIDDEN"); got != "没有权限执行该操作" {
		t.Errorf("T(fr,FORBIDDEN) 应回落 zh, 实际 %q", got)
	}
	// 未知 key 原样返回(便于发现漏配)
	if got := T("en", "NO_SUCH_KEY"); got != "NO_SUCH_KEY" {
		t.Errorf("T(en,未知)=%q, 期望原样返回 key", got)
	}
}

// 三语 catalog 的 key 必须完全一致,防止漏翻。
func TestCatalogsAligned(t *testing.T) {
	zh := catalogs["zh"]
	for _, lang := range Supported {
		m := catalogs[lang]
		if len(m) != len(zh) {
			t.Errorf("%s 的 key 数=%d, zh=%d", lang, len(m), len(zh))
		}
		for k := range zh {
			if v, ok := m[k]; !ok || v == "" {
				t.Errorf("%s 缺少 key %q", lang, k)
			}
		}
	}
}

func newCtx(target, acceptLang string) *gin.Context {
	gin.SetMode(gin.TestMode)
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest(http.MethodGet, target, nil)
	if acceptLang != "" {
		c.Request.Header.Set("Accept-Language", acceptLang)
	}
	return c
}

func TestLang(t *testing.T) {
	if got := Lang(newCtx("/?lang=en", "ja")); got != "en" { // ?lang 优先于 header
		t.Errorf("?lang=en 应胜出, 实际 %q", got)
	}
	if got := Lang(newCtx("/", "ja,en;q=0.8")); got != "ja" { // 无 ?lang 时取 header 首选
		t.Errorf("Accept-Language=ja 应取 ja, 实际 %q", got)
	}
	if got := Lang(newCtx("/", "")); got != "zh" { // 都没有 → 默认
		t.Errorf("无语言信息应默认 zh, 实际 %q", got)
	}
	if got := Lang(newCtx("/", "fr-FR")); got != "zh" { // 不支持回落
		t.Errorf("fr-FR 应回落 zh, 实际 %q", got)
	}
}

func TestWriteError(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/?lang=ja", nil)
	WriteError(c, http.StatusConflict, "ALREADY_CHECKED_IN")

	if w.Code != http.StatusConflict {
		t.Fatalf("状态码=%d, 期望 409", w.Code)
	}
	var env struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &env); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if env.Error.Code != "ALREADY_CHECKED_IN" {
		t.Errorf("code=%q", env.Error.Code)
	}
	if env.Error.Message != "本日はチェックイン済みです" {
		t.Errorf("ja 文案未生效: %q", env.Error.Message)
	}
}

func TestWriteErrorDetail(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/?lang=en", nil)
	WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", "field x missing")

	var env struct {
		Error struct {
			Code    string         `json:"code"`
			Message string         `json:"message"`
			Details map[string]any `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &env); err != nil {
		t.Fatalf("解析失败: %v", err)
	}
	if env.Error.Message != "Invalid request parameters" {
		t.Errorf("en 文案=%q", env.Error.Message)
	}
	// detail 只进服务端日志,不回响应体(避免未翻译/内部信息出现在返回里)。
	if env.Error.Details != nil {
		t.Errorf("4xx 不应回传 details(只记日志), 实际 %v", env.Error.Details)
	}
}

// 5xx 不应把内部细节回给客户端(防信息泄露):只本地化通用文案,details 为空。
func TestWriteErrorDetail_5xxHidesDetail(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/?lang=en", nil)
	WriteErrorDetail(c, http.StatusInternalServerError, "INTERNAL", "pq: duplicate key value violates unique constraint \"x\"")

	var env struct {
		Error struct {
			Message string         `json:"message"`
			Details map[string]any `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &env); err != nil {
		t.Fatalf("解析失败: %v", err)
	}
	if env.Error.Message != "Internal server error, please try again" {
		t.Errorf("5xx 文案=%q", env.Error.Message)
	}
	if env.Error.Details != nil {
		t.Errorf("5xx 不应回传 details(防泄露), 实际 %v", env.Error.Details)
	}
}
