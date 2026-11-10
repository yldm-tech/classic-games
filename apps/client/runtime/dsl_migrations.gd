class_name DslMigrations
extends RefCounted

static func can_migrate(runtime_name: String, from_version: String, to_version: String) -> bool:
	return runtime_name == "shooter" and _major(from_version) == 0 and _major(to_version) == 1

static func migrate(runtime_name: String, from_version: String, to_version: String, input: Dictionary) -> Dictionary:
	if not can_migrate(runtime_name, from_version, to_version): return {}
	var out := input.duplicate(true)
	var meta: Dictionary = out.get("meta", {}) if out.get("meta") is Dictionary else {}
	meta["runtime"] = "shooter"; meta["runtime_version"] = to_version
	if not meta.has("fork_of"): meta["fork_of"] = null
	out["meta"] = meta
	var player: Dictionary = out.get("player", {}) if out.get("player") is Dictionary else {}
	if player.get("weapon") is String: player["weapon"] = _legacy_weapon(str(player["weapon"]))
	if not player.has("size"): player["size"] = 1.0
	out["player"] = player
	if out.get("enemies") is Array: out["enemies"] = _array_to_id_map(out["enemies"], "enemy")
	if out.get("drops") is Array: out["drops"] = _array_to_id_map(out["drops"], "drop")
	return out

static func _legacy_weapon(kind: String) -> Dictionary:
	match kind:
		"spread": return {"type":"spread","damage":20,"fire_rate":5,"bullet_count":3}
		"laser": return {"type":"laser","damage":20,"width":1.0}
		"missile": return {"type":"missile","damage":20,"fire_rate":3,"turn_rate":2.0}
		"boomerang": return {"type":"boomerang","damage":20,"range":8.0}
		"orbit": return {"type":"orbit","damage":20,"orbit_count":3}
		_: return {"type":"straight","damage":20,"fire_rate":5}

static func _array_to_id_map(items: Array, prefix: String) -> Dictionary:
	var out := {}
	for i in items.size():
		if not items[i] is Dictionary: continue
		var item: Dictionary = items[i].duplicate(true)
		# 仅当 id 为非空字符串才用它,否则退回生成键——与服务端 migrate.go arrayToIDMap 同语义。
		# get("id", default) 只在键缺失时回退,对 id="" 或数字 id 会与服务端分叉,破坏跨迁移边界的补丁链。
		var raw_id: Variant = item.get("id", null)
		var stable_id: String = str(raw_id) if (raw_id is String and raw_id != "") else "%s_%d" % [prefix, i + 1]
		item.erase("id"); out[stable_id] = item
	return out

static func _major(version: String) -> int:
	var parts := version.split(".")
	return int(parts[0]) if not parts.is_empty() and parts[0].is_valid_int() else -1
