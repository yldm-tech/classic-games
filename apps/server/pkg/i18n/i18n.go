// Package i18n 是后端的多语言设施:把用户可见文案(目前是错误信息)按语言查表返回。
// 文案目录用 //go:embed 嵌进二进制(locales/{zh,en,ja}.json),与客户端 strings.gd 对应。
// 语言取值优先级:?lang= 查询参数 > Accept-Language 请求头 > 默认 zh。错误码即查表 key。
package i18n

import (
	"embed"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
)

// DefaultLang 是缺省/兜底语言:未指定或不支持的语言一律回落到它。
const DefaultLang = "zh"

// Supported 列出受支持的语言(与客户端保持一致)。
var Supported = []string{"zh", "en", "ja"}

//go:embed locales/*.json
var localesFS embed.FS

// catalogs[lang][key] = 文案。进程启动时一次性装载;嵌入资源缺失/损坏属构建期错误,直接 panic。
var catalogs = loadCatalogs()

func loadCatalogs() map[string]map[string]string {
	out := make(map[string]map[string]string, len(Supported))
	for _, lang := range Supported {
		data, err := localesFS.ReadFile("locales/" + lang + ".json")
		if err != nil {
			panic(fmt.Sprintf("i18n: 读取内嵌文案 %s 失败: %v", lang, err))
		}
		m := make(map[string]string)
		if err := json.Unmarshal(data, &m); err != nil {
			panic(fmt.Sprintf("i18n: 解析内嵌文案 %s 失败: %v", lang, err))
		}
		out[lang] = m
	}
	return out
}

// Normalize 把任意语言入参收敛到受支持的语言:大小写无关,去掉地区子标签(ja-JP→ja),
// 不支持的一律回落 DefaultLang。
func Normalize(lang string) string {
	lang = strings.ToLower(strings.TrimSpace(lang))
	if i := strings.IndexByte(lang, '-'); i >= 0 {
		lang = lang[:i]
	}
	if _, ok := catalogs[lang]; ok {
		return lang
	}
	return DefaultLang
}

// Lang 从请求解析语言:?lang= 优先,其次 Accept-Language 的首选项,最后 DefaultLang。
func Lang(c *gin.Context) string {
	if q := c.Query("lang"); q != "" {
		return Normalize(q)
	}
	if al := c.GetHeader("Accept-Language"); al != "" {
		// 形如 "ja,en;q=0.8" → 取第一个标签的主语言。
		tag := al
		if i := strings.IndexAny(tag, ",;"); i >= 0 {
			tag = tag[:i]
		}
		return Normalize(tag)
	}
	return DefaultLang
}

// T 查 lang 下 key 的文案:lang 缺失则查 DefaultLang 兜底;仍无则原样返回 key(便于发现漏配)。
func T(lang, key string) string {
	lang = Normalize(lang)
	if v, ok := catalogs[lang][key]; ok && v != "" {
		return v
	}
	if v, ok := catalogs[DefaultLang][key]; ok && v != "" {
		return v
	}
	return key
}

// WriteError 按请求语言把 code 翻成文案,用统一信封写错误响应。
// code 既是机器可读的错误码,也是文案目录的 key。
func WriteError(c *gin.Context, status int, code string) {
	httpx.WriteError(c, status, code, T(Lang(c), code))
}

// WriteErrorDetail 同 WriteError,但把动态细节(校验器/驱动原始报错、字段名等)记到服务端日志,
// 不放进响应体。这样任何错误响应都只含 {code, 本地化 message}——既不泄露内部信息,也不会出现
// 未翻译的原始文本(原始 err 多为中英混杂)。排错看服务端日志即可。
func WriteErrorDetail(c *gin.Context, status int, code, detail string) {
	log.Printf("i18n: %d %s: %s", status, code, detail)
	WriteError(c, status, code)
}
