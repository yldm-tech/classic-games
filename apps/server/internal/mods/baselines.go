package mods

import "fmt"

// MapBaselines 是 map 支撑的 BaselineProvider:按 "name@version" 注册基线 DSL。
// 这是生产唯一实现(apps/server/cmd/server/main.go 启动时从内嵌基线文件灌入)——
// docs/10-data-model.md 早期设想过一张 runtimes 表,但从未落地,不要按那份文档去找 DB 表。
type MapBaselines struct {
	m map[string]map[string]any
}

func NewMapBaselines() *MapBaselines {
	return &MapBaselines{m: map[string]map[string]any{}}
}

func (b *MapBaselines) Register(runtime string, baseline map[string]any) {
	b.m[runtime] = baseline
}

func (b *MapBaselines) BaselineFor(runtime string) (map[string]any, error) {
	base, ok := b.m[runtime]
	if !ok {
		return nil, fmt.Errorf("无 %s 的基线", runtime)
	}
	return base, nil
}
