class_name GameSession
extends Node

const JsonPatch := preload("res://runtime/json_patch.gd")
const RuntimeLoaderScript := preload("res://runtime/runtime_loader.gd")

## Shell↔Runtime 的唯一通信边界(见 docs/04-architecture.md、16-client-architecture.md)。
## Shell 只通过本节点与游戏运行时交互,绝不伸手进游戏 scene 内部;
## Runtime 也绝不读 Shell 的全局状态/UI/用户数据。守住这条边界,架构逃生口才有效。

## Emitted when a game run finishes. result: { score, duration, cleared, ... }
signal game_ended(result: Dictionary)

## Emitted when the run cannot proceed. err: { code, msg } —— DSL 非法 / runtime 版本不匹配等
signal game_error(err: Dictionary)

## Start a game run.
## payload 两种形态:
##   A 直传生效 DSL:    { "runtime": "shooter@1.0.0", "mod": { ...DSL... } }
##   B 基线 + 补丁链:   { "runtime": "shooter@1.0.0", "baseline": {..}, "patches": [ [6902 ops], ... ] }
## 形态 B 用于 Fork:把补丁链逐层 apply 到基线得生效 DSL(见 docs/05-dsl-design.md)。
func start_game(payload: Dictionary) -> void:
	var runtime_ref: String = str(payload.get("runtime", ""))
	var dsl: Dictionary = _resolve_dsl(payload)
	if dsl.is_empty():
		game_error.emit({"code": "DSL_INVALID", "msg": "payload 缺 mod / baseline"})
		return

	var loader := RuntimeLoaderScript.new()
	var run := loader.load_from_dsl(runtime_ref, dsl)
	if run == null:
		game_error.emit(loader.last_error)
		return

	# 清掉上一局,挂上新运行时节点
	for child in get_children():
		child.queue_free()
	add_child(run)

	# spike:加载成功即视为一局结束并回传摘要。真实运行时会在玩完后才 emit。
	var summary: Dictionary = run.get_meta("summary", {})
	summary["cleared"] = true
	game_ended.emit(summary)

## 把 payload 解析成生效 DSL(处理 Fork 补丁链)。失败返回空字典。
func _resolve_dsl(payload: Dictionary) -> Dictionary:
	if payload.has("mod") and typeof(payload["mod"]) == TYPE_DICTIONARY:
		return payload["mod"]
	if payload.has("baseline") and typeof(payload["baseline"]) == TYPE_DICTIONARY:
		var dsl: Variant = payload["baseline"]
		var patches: Variant = payload.get("patches", [])
		# patches 来自不可信网络形态(Form B Fork 链):非数组、或元素非数组,都返回 {} 走 game_error,
		# 不能把非 Array 直接传给 JsonPatch.apply(ops: Array) —— 那会触发引擎类型错误,绕过本边界的优雅降级。
		if typeof(patches) != TYPE_ARRAY:
			push_error("补丁链不是数组")
			return {}
		for ops in patches:
			if typeof(ops) != TYPE_ARRAY:
				push_error("补丁链元素不是数组")
				return {}
			var res := JsonPatch.apply(dsl, ops)
			if not res["ok"]:
				push_error("补丁链 apply 失败: %s" % res["error"])
				return {}
			dsl = res["result"]
		return dsl
	return {}
