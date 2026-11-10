package dsl

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/santhosh-tekuri/jsonschema/v6"
)

// safeSegment 限制 name/version 字符集;配合 ".." 检查,杜绝把入参拼进 schema 文件路径造成穿越
// (与 runtimes.isSafeSegment 同策略;此处 /ai/validate 无鉴权,attacker 可控 runtime,必须挡)。
var safeSegment = regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)

func isSafeSegment(s string) bool {
	return safeSegment.MatchString(s) && !strings.Contains(s, "..")
}

// SchemaValidator 是权威校验器:按 runtime 版本加载对应 JSON Schema 文件
// (packages/schemas/<name>-<version>.schema.json,draft 2020-12)做完整校验。
// 这是 docs/12-ai-prompt.md 里「后端 apply 后用 DSL schema 校验 new_dsl」的落地实现,
// 取代 MinimalValidator。编译结果按 runtime ref 缓存,并发安全。
type SchemaValidator struct {
	schemaDir string
	// registeredOnly disables the lazy read from schemaDir: only schemas added with Register are known.
	registeredOnly bool
	mu             sync.Mutex
	cache          map[string]*jsonschema.Schema
}

// NewSchemaValidator 指向存放 schema 文件的目录(仓库内 packages/schemas)。
func NewSchemaValidator(schemaDir string) *SchemaValidator {
	return &SchemaValidator{schemaDir: schemaDir, cache: map[string]*jsonschema.Schema{}}
}

// NewRegisteredSchemaValidator returns a validator that never reads the disk: it only knows the schemas added with Register. Use it when the schema files were already read once and later changes on disk must not change what is enforced.
func NewRegisteredSchemaValidator() *SchemaValidator {
	return &SchemaValidator{registeredOnly: true, cache: map[string]*jsonschema.Schema{}}
}

// Register compiles schema, the content of a <name>-<version>.schema.json file, and uses it for the runtime ref from now on. It fails when the ref is malformed or the schema does not compile.
func (v *SchemaValidator) Register(runtime string, schema []byte) error {
	name, version := parseRuntimeRef(runtime)
	if name == "" || version == "" || !isSafeSegment(name) || !isSafeSegment(version) {
		return classify(ErrInvalidRuntimeRef, "非法 runtime ref: %q", runtime)
	}
	sch, err := compileSchema(schema)
	if err != nil {
		return err
	}
	v.mu.Lock()
	defer v.mu.Unlock()
	v.cache[runtime] = sch
	return nil
}

func (v *SchemaValidator) Validate(runtime string, dsl map[string]any) error {
	_, err := v.ValidateResolved(runtime, dsl)
	return err
}

// ValidateResolved is Validate that also returns the runtime ref whose schema the document was checked against. It differs from runtime when a legacy shooter@0.x document was migrated first; violations then refer to the migrated document. The returned ref is "" when no schema could be resolved.
func (v *SchemaValidator) ValidateResolved(runtime string, dsl map[string]any) (string, error) {
	sch, err := v.schemaFor(runtime)
	if err != nil {
		name, version := parseRuntimeRef(runtime)
		if name == "shooter" && strings.HasPrefix(version, "0.") {
			var migrated map[string]any
			runtime, migrated, err = Migrate(runtime, "1.0.0", dsl)
			if err != nil {
				return "", err
			}
			dsl = migrated
			sch, err = v.schemaFor(runtime)
		}
		if err != nil {
			return "", err
		}
	}
	// 经 jsonschema.UnmarshalJSON 规范化实例(数字/类型按 v6 约定),再校验。
	b, err := json.Marshal(dsl)
	if err != nil {
		return runtime, err
	}
	inst, err := jsonschema.UnmarshalJSON(bytes.NewReader(b))
	if err != nil {
		return runtime, fmt.Errorf("DSL 解析失败: %w", err)
	}
	if err := sch.Validate(inst); err != nil {
		return runtime, fmt.Errorf("DSL 不合 schema: %w", err)
	}
	return runtime, nil
}

// schemaFor 把 "shooter@1.0.0" 映射到 schema 文件并编译(带缓存)。
func (v *SchemaValidator) schemaFor(runtime string) (*jsonschema.Schema, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if sch, ok := v.cache[runtime]; ok {
		return sch, nil
	}

	name, version := parseRuntimeRef(runtime)
	if name == "" || version == "" {
		return nil, classify(ErrInvalidRuntimeRef, "非法 runtime ref: %q", runtime)
	}
	// name/version 会拼进文件路径,挡掉 ".." 与非白名单字符,杜绝路径穿越(系统边界净化)。
	if !isSafeSegment(name) || !isSafeSegment(version) {
		return nil, classify(ErrInvalidRuntimeRef, "非法 runtime ref: %q", runtime)
	}
	if v.registeredOnly {
		return nil, classify(ErrUnknownRuntime, "找不到 %s@%s 的 schema", name, version)
	}
	file := filepath.Join(v.schemaDir, fmt.Sprintf("%s-%s.schema.json", name, version))
	data, err := os.ReadFile(file)
	if err != nil {
		// 不回显解析后的绝对路径 / OS 错误(避免路径泄露),只给出 runtime ref。
		return nil, classify(ErrUnknownRuntime, "找不到 %s@%s 的 schema", name, version)
	}
	sch, err := compileSchema(data)
	if err != nil {
		return nil, err
	}
	v.cache[runtime] = sch
	return sch, nil
}

// compileSchema compiles one schema document. The compiler gets a loader that refuses every URL scheme, so a "$ref" that points outside the document (file://, http://, https://) fails to compile instead of making the process read a local file or fetch a URL. The repository schemas only use "#/$defs/..." references, which need no loading.
func compileSchema(data []byte) (*jsonschema.Schema, error) {
	doc, err := jsonschema.UnmarshalJSON(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("schema 解析失败: %w", err)
	}
	c := jsonschema.NewCompiler()
	c.UseLoader(jsonschema.SchemeURLLoader{})
	const ref = "schema.json"
	if err := c.AddResource(ref, doc); err != nil {
		return nil, err
	}
	sch, err := c.Compile(ref)
	if err != nil {
		return nil, fmt.Errorf("schema 编译失败: %w", err)
	}
	return sch, nil
}

func parseRuntimeRef(ref string) (name, version string) {
	i := strings.IndexByte(ref, '@')
	if i < 0 {
		return ref, ""
	}
	return ref[:i], ref[i+1:]
}
