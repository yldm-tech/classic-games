package dsl

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// 载入与客户端同一份基线 DSL,保证两端测的是同一个起点。
// packages/dsl is two levels below the repository root.
func loadBaseline(t *testing.T) map[string]any {
	t.Helper()
	p := filepath.Join("..", "..", "apps", "client", "runtime", "shooter", "baseline.dsl.json")
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("读基线 DSL 失败: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("解析基线 DSL 失败: %v", err)
	}
	return m
}

func enemyTotal(dsl map[string]any) int {
	enemies, _ := dsl["enemies"].(map[string]any)
	total := 0
	for _, v := range enemies {
		e, _ := v.(map[string]any)
		if c, ok := e["count"].(float64); ok {
			total += int(c)
		}
	}
	return total
}

func ops(t *testing.T, raw string) []Op {
	t.Helper()
	var o []Op
	if err := json.Unmarshal([]byte(raw), &o); err != nil {
		t.Fatalf("解析 ops 失败: %v", err)
	}
	return o
}

// 与客户端 spike_test.gd 的 C 用例完全相同的 Fork 补丁链,断言两端结果一致。
func TestApply_ForkChain_MapAddressing(t *testing.T) {
	base := loadBaseline(t)
	patch := ops(t, `[
		{"op":"replace","path":"/player/sprite","value":"cat"},
		{"op":"add","path":"/enemies/bird_1","value":{"type":"bird","behavior":"sine","count":10,"hp":15,"speed":12}},
		{"op":"replace","path":"/enemies/dog_1/count","value":30},
		{"op":"remove","path":"/enemies/turret_1"}
	]`)

	out, err := Apply(base, patch)
	if err != nil {
		t.Fatalf("apply 失败: %v", err)
	}

	// 换皮生效
	player := out["player"].(map[string]any)
	if player["sprite"] != "cat" {
		t.Errorf("sprite = %v, 期望 cat", player["sprite"])
	}
	// dog_1: 20→30,turret_1 删除,新增 bird_1:10 → 40,与客户端 enemy_total 一致
	if got := enemyTotal(out); got != 40 {
		t.Errorf("enemy_total = %d, 期望 40(与客户端一致)", got)
	}
	if _, exists := out["enemies"].(map[string]any)["turret_1"]; exists {
		t.Error("turret_1 应被 remove")
	}

	// 入参不被修改(深拷贝)
	if enemyTotal(base) != 24 {
		t.Errorf("基线被污染:enemy_total = %d, 期望 24", enemyTotal(base))
	}
}

// 黄金对拍:apply 后整树必须逐字节等于 client 与 server 共用的 golden 文件。
// 客户端 spike_test.gd 的 C2 用例对同一份 golden 做同样断言——两端都过 = 两端语义一致。
// 这把「逐字节一致」从注释承诺变成可执行约束。
func TestApply_ForkChain_MatchesGolden(t *testing.T) {
	base := loadBaseline(t)
	patch := ops(t, `[
		{"op":"replace","path":"/player/sprite","value":"cat"},
		{"op":"add","path":"/enemies/bird_1","value":{"type":"bird","behavior":"sine","count":10,"hp":15,"speed":12}},
		{"op":"replace","path":"/enemies/dog_1/count","value":30},
		{"op":"remove","path":"/enemies/turret_1"}
	]`)
	out, err := Apply(base, patch)
	if err != nil {
		t.Fatalf("apply 失败: %v", err)
	}

	goldenPath := filepath.Join("..", "..", "apps", "client", "runtime", "shooter", "testdata", "fork_expected.dsl.json")
	gb, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("读 golden 失败: %v", err)
	}
	var golden map[string]any
	if err := json.Unmarshal(gb, &golden); err != nil {
		t.Fatalf("解析 golden 失败: %v", err)
	}

	// encoding/json marshal 对 map key 排序 → 可直接比规范化字节。
	gotB, _ := json.Marshal(out)
	wantB, _ := json.Marshal(golden)
	if string(gotB) != string(wantB) {
		t.Errorf("apply 结果与 golden 不一致(两端一致性锚点断裂)\n got=%s\nwant=%s", gotB, wantB)
	}
}

// 回归:根路径操作必须被结构化拒绝,绝不 panic(评审 F1)。
func TestApply_RootPathRejected(t *testing.T) {
	base := loadBaseline(t)
	for _, kind := range []string{"add", "replace", "remove", "test"} {
		raw := `[{"op":"` + kind + `","path":"","value":1}]`
		if _, err := Apply(base, ops(t, raw)); err == nil {
			t.Errorf("根路径 %s 应被拒绝", kind)
		}
	}
}

func TestApply_RejectsBadPath(t *testing.T) {
	base := loadBaseline(t)
	_, err := Apply(base, ops(t, `[{"op":"replace","path":"/player/nope","value":1}]`))
	if err == nil {
		t.Error("replace 不存在的路径应报错")
	}
}

func TestApply_RemoveMissing(t *testing.T) {
	base := loadBaseline(t)
	_, err := Apply(base, ops(t, `[{"op":"remove","path":"/enemies/ghost_99"}]`))
	if err == nil {
		t.Error("remove 不存在的 key 应报错")
	}
}

// test op:通过 / 不通过 / 路径不存在(评审 F4 覆盖缺口)。
func TestApply_TestOp(t *testing.T) {
	base := loadBaseline(t)
	// 通过:player.sprite 确为 plane,test 通过后续 replace 才执行
	out, err := Apply(base, ops(t, `[
		{"op":"test","path":"/player/sprite","value":"plane"},
		{"op":"replace","path":"/player/sprite","value":"cat"}
	]`))
	if err != nil {
		t.Fatalf("test 通过场景不应报错: %v", err)
	}
	if out["player"].(map[string]any)["sprite"] != "cat" {
		t.Error("test 通过后 replace 应生效")
	}
	// 不通过:实际是 plane 而非 ufo
	if _, err := Apply(base, ops(t, `[{"op":"test","path":"/player/sprite","value":"ufo"}]`)); err == nil {
		t.Error("test 值不符应报错")
	}
	// 路径不存在
	if _, err := Apply(base, ops(t, `[{"op":"test","path":"/player/nope","value":1}]`)); err == nil {
		t.Error("test 路径不存在应报错")
	}
}

// RFC 6901 指针转义:~1 = "/",~0 = "~"(评审 F4:parsePointer 转义零覆盖)。
func TestApply_PointerEscape(t *testing.T) {
	doc := map[string]any{"a/b": map[string]any{}, "c~d": 1}
	out, err := Apply(doc, ops(t, `[
		{"op":"add","path":"/a~1b/x","value":42},
		{"op":"replace","path":"/c~0d","value":2}
	]`))
	if err != nil {
		t.Fatalf("转义路径 apply 失败: %v", err)
	}
	if out["a/b"].(map[string]any)["x"].(float64) != 42 {
		t.Errorf("~1 应解码为 /,得到 %v", out["a/b"])
	}
	if out["c~d"].(float64) != 2 {
		t.Errorf("~0 应解码为 ~,得到 %v", out["c~d"])
	}
}

func TestApply_ArrayOperationsMatchRFC6902(t *testing.T) {
	doc := map[string]any{"items": []any{"a", "b", "c"}}
	out, err := Apply(doc, ops(t, `[
		{"op":"add","path":"/items/1","value":"x"},
		{"op":"add","path":"/items/-","value":"z"},
		{"op":"replace","path":"/items/2","value":"B"},
		{"op":"remove","path":"/items/0"}
	]`))
	if err != nil {
		t.Fatalf("数组补丁失败: %v", err)
	}
	got, _ := json.Marshal(out["items"])
	if string(got) != `["x","B","c","z"]` {
		t.Fatalf("数组结果 = %s", got)
	}
	if original, _ := json.Marshal(doc["items"]); string(original) != `["a","b","c"]` {
		t.Fatalf("输入数组被修改: %s", original)
	}
}

func TestApply_ArrayOperationsRejectInvalidIndexes(t *testing.T) {
	doc := map[string]any{"items": []any{"a"}}
	cases := []string{
		`[{"op":"add","path":"/items/2","value":"x"}]`,
		`[{"op":"replace","path":"/items/1","value":"x"}]`,
		`[{"op":"replace","path":"/items/-","value":"x"}]`,
		`[{"op":"remove","path":"/items/-"}]`,
		`[{"op":"remove","path":"/items/nope"}]`,
	}
	for _, raw := range cases {
		if _, err := Apply(doc, ops(t, raw)); err == nil {
			t.Errorf("非法数组路径应拒绝: %s", raw)
		}
	}
}

// Callers classify failures with errors.Is and read the failing operation from OpError, while the message stays the text the backend and the client share.
func TestApply_ErrorsAreClassifiedAndKeepTheirText(t *testing.T) {
	base := loadBaseline(t)
	cases := []struct {
		name  string
		patch string
		class error
		text  string
		index int
	}{
		{"replace missing target", `[{"op":"replace","path":"/player/nope","value":1}]`, ErrTargetMissing, "replace 目标不存在: /nope", 0},
		{"remove missing target", `[{"op":"test","path":"/player/sprite","value":"plane"},{"op":"remove","path":"/enemies/ghost_99"}]`, ErrTargetMissing, "remove 目标不存在: /ghost_99", 1},
		{"test missing path", `[{"op":"test","path":"/player/nope","value":1}]`, ErrTargetMissing, "test 路径不存在: /player/nope", 0},
		{"test mismatch", `[{"op":"add","path":"/player/extra","value":1},{"op":"add","path":"/player/more","value":2},{"op":"test","path":"/player/sprite","value":"ufo"}]`, ErrTestFailed, "test 不通过: /player/sprite", 2},
		{"add missing parent", `[{"op":"add","path":"/nope/deeper/key","value":1}]`, ErrParentMissing, "add 路径父级不存在: /nope/deeper/key", 0},
		{"remove missing parent", `[{"op":"remove","path":"/nope/key"}]`, ErrParentMissing, "remove 路径父级不存在: /nope/key", 0},
		{"array index", `[{"op":"add","path":"/list","value":[1]},{"op":"replace","path":"/list/5","value":2}]`, ErrIndexOutOfRange, "replace 数组下标非法或越界: 5", 1},
		{"root path", `[{"op":"remove","path":""}]`, ErrRootPath, "不支持根路径操作: remove", 0},
		{"unsupported op", `[{"op":"move","path":"/a"}]`, ErrUnsupportedOp, "不支持的 op: move", 0},
	}
	for _, c := range cases {
		_, err := Apply(base, ops(t, c.patch))
		if err == nil {
			t.Errorf("%s: got nil, want an error", c.name)
			continue
		}
		if !errors.Is(err, c.class) {
			t.Errorf("%s: error %v does not match %v", c.name, err, c.class)
		}
		if err.Error() != c.text {
			t.Errorf("%s: message %q, want %q", c.name, err.Error(), c.text)
		}
		var opErr *OpError
		if !errors.As(err, &opErr) || opErr.Index != c.index {
			t.Errorf("%s: got %#v, want an *OpError with index %d", c.name, err, c.index)
		}
	}
}
