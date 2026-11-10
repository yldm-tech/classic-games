package dsl

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// Migrate upgrades known historical DSL majors and returns the target runtime ref. targetVersion is written into meta.runtime_version, so it must be a plain <major>.<minor>.<patch> version; anything else has no migration path.
func Migrate(runtime, targetVersion string, input map[string]any) (string, map[string]any, error) {
	parts := strings.SplitN(runtime, "@", 2)
	if len(parts) != 2 || parts[0] != "shooter" || major(parts[1]) != 0 || !isPlainVersion(targetVersion) || major(targetVersion) != 1 {
		return runtime, nil, fmt.Errorf("无迁移路径: %s -> %s", runtime, targetVersion)
	}
	out, err := deepCopy(input)
	if err != nil {
		return runtime, nil, err
	}
	meta, _ := out["meta"].(map[string]any)
	if meta == nil {
		meta = map[string]any{}
	}
	meta["runtime"], meta["runtime_version"] = "shooter", targetVersion
	if _, ok := meta["fork_of"]; !ok {
		meta["fork_of"] = nil
	}
	out["meta"] = meta
	player, _ := out["player"].(map[string]any)
	if player == nil {
		player = map[string]any{}
	}
	if kind, ok := player["weapon"].(string); ok {
		player["weapon"] = legacyWeapon(kind)
	}
	if _, ok := player["size"]; !ok {
		player["size"] = 1.0
	}
	out["player"] = player
	if items, ok := out["enemies"].([]any); ok {
		out["enemies"] = arrayToIDMap(items, "enemy")
	}
	if items, ok := out["drops"].([]any); ok {
		out["drops"] = arrayToIDMap(items, "drop")
	}
	return "shooter@" + targetVersion, out, nil
}

func major(v string) int { n, _ := strconv.Atoi(strings.SplitN(v, ".", 2)[0]); return n }

// isPlainVersion reports whether v is three dot-separated decimal numbers without signs, spaces or leading zeros, such as "1.0.0".
func isPlainVersion(v string) bool {
	parts := strings.Split(v, ".")
	if len(parts) != 3 {
		return false
	}
	for _, part := range parts {
		if part == "" || (len(part) > 1 && part[0] == '0') {
			return false
		}
		for _, r := range part {
			if r < '0' || r > '9' {
				return false
			}
		}
	}
	return true
}
func legacyWeapon(kind string) map[string]any {
	switch kind {
	case "spread":
		return map[string]any{"type": "spread", "damage": 20, "fire_rate": 5, "bullet_count": 3}
	case "laser":
		return map[string]any{"type": "laser", "damage": 20, "width": 1.0}
	case "missile":
		return map[string]any{"type": "missile", "damage": 20, "fire_rate": 3, "turn_rate": 2.0}
	case "boomerang":
		return map[string]any{"type": "boomerang", "damage": 20, "range": 8.0}
	case "orbit":
		return map[string]any{"type": "orbit", "damage": 20, "orbit_count": 3}
	default:
		return map[string]any{"type": "straight", "damage": 20, "fire_rate": 5}
	}
}
func arrayToIDMap(items []any, prefix string) map[string]any {
	out := map[string]any{}
	for i, raw := range items {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		b, _ := json.Marshal(item)
		var cp map[string]any
		_ = json.Unmarshal(b, &cp)
		id, _ := cp["id"].(string)
		if id == "" {
			id = fmt.Sprintf("%s_%d", prefix, i+1)
		}
		delete(cp, "id")
		out[id] = cp
	}
	return out
}
