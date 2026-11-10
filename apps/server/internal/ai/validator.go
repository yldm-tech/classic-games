package ai

import "fmt"

// MinimalValidator 只做最基本的结构 sanity check(顶层必需键、meta.runtime 一致),
// 不做完整 schema 校验。它是零配置兜底,用于测试或未配置 schema 目录的场景。
//
// 权威校验是 github.com/yldm-tech/classic-games/packages/dsl 的 SchemaValidator(packages/dsl/schema_validator.go),用 santhosh-tekuri/jsonschema 按
// runtime 版本加载 packages/schemas 下对应 schema 文件做完整校验(见 ADR-014)。生产用后者。
type MinimalValidator struct{}

// 各 runtime 的必需顶层键(对齐 schema 的 required)。
var requiredTopKeys = map[string][]string{
	"shooter":       {"meta", "player", "enemies", "stage"},
	"survivor":      {"meta", "hero", "weapon", "waves", "progression", "stage"},
	"tower_defense": {"meta", "stage", "path", "towers", "placements", "waves"},
}

func (MinimalValidator) Validate(runtime string, dsl map[string]any) error {
	name := runtimeName(runtime)
	keys, ok := requiredTopKeys[name]
	if !ok {
		return fmt.Errorf("未知 runtime: %s", name)
	}
	for _, k := range keys {
		if _, exists := dsl[k]; !exists {
			return fmt.Errorf("缺少必需顶层字段: %s", k)
		}
	}
	meta, ok := dsl["meta"].(map[string]any)
	if !ok {
		return fmt.Errorf("meta 不是对象")
	}
	if meta["runtime"] != name {
		return fmt.Errorf("meta.runtime=%v 与请求 runtime=%s 不一致", meta["runtime"], name)
	}
	return nil
}
