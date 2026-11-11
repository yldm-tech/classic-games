class_name GameSession
extends Node

const JsonPatch := preload("res://runtime/json_patch.gd")
const RuntimeLoaderScript := preload("res://runtime/runtime_loader.gd")

## Shell↔Runtime 的唯一通信边界(见 docs/04-architecture.md、16-client-architecture.md)。
## Shell 只通过本节点与游戏运行时交互,绝不伸手进游戏 scene 内部;
## Runtime 也绝不读 Shell 的全局状态/UI/用户数据。守住这条边界,架构逃生口才有效。

## Emitted when a game run finishes. result: { score, duration, cleared, ... }
## After start_run the result is the final snapshot(): the runtime summary plus play_seconds (active seconds, pauses excluded), timed_out, aborted (the host ended it) and runtime_ref.
signal game_ended(result: Dictionary)

## Emitted when the run cannot proceed. err: { code, msg } —— DSL 非法 / runtime 版本不匹配等
signal game_error(err: Dictionary)

## Live-run signals (start_run). A host that only uses start_game never sees these.
## info: { runtime, stage_size }
signal game_started(info: Dictionary)
## Emitted whenever the running game's score changes.
signal score_changed(score: int)
## Emitted when set_paused actually changes the state.
signal paused_changed(paused: bool)

## Logical size of the stage every runtime draws into, centred on its own origin. A host puts this node inside a SubViewport of exactly this size and scales the viewport, never the runtime.
const STAGE_SIZE := Vector2i(960, 540)
const BASELINE_PATH := "res://runtime/%s/baseline.dsl.json"

var _run: Node
var _running := false
var _paused := false
var _play_seconds := 0.0
var _last_score := 0
var _runtime_ref := ""
## The effective DSL of the live run and the vitals it started with, kept for the HUD fields snapshot() derives from them.
var _dsl: Dictionary = {}
var _initial: Dictionary = {}

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

## Payload that starts the built-in baseline of a runtime, e.g. baseline_payload("survivor@1.0.0"). Returns {} when the runtime ships no baseline, so hosts never read runtime files themselves.
static func baseline_payload(runtime_ref: String) -> Dictionary:
	var runtime_name := runtime_ref.split("@")[0]
	var path := BASELINE_PATH % runtime_name
	if not runtime_name.is_valid_identifier() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	return {"runtime": runtime_ref, "mod": parsed}

## Start a live run: the runtime stays mounted under this node and keeps simulating until it clears, is defeated, runs out of time, or the host calls end_run. Same payload forms as start_game.
## Returns false after emitting game_error when the run cannot start.
func start_run(payload: Dictionary) -> bool:
	_drop_run()
	var runtime_ref: String = str(payload.get("runtime", ""))
	var dsl: Dictionary = _resolve_dsl(payload)
	if dsl.is_empty():
		game_error.emit({"code": "DSL_INVALID", "msg": "payload 缺 mod / baseline"})
		return false
	var loader := RuntimeLoaderScript.new()
	# Deep-copied so a runtime that mutates its configuration never changes the caller's DSL between runs.
	var run := loader.load_from_dsl(runtime_ref, dsl.duplicate(true))
	if run == null:
		game_error.emit(loader.last_error)
		return false
	_run = run
	_runtime_ref = runtime_ref
	_dsl = dsl
	_initial = {}
	_running = true
	_paused = false
	_play_seconds = 0.0
	_last_score = 0
	if run is Node2D:
		(run as Node2D).position = Vector2(STAGE_SIZE) / 2.0
	add_child(run)
	var first := snapshot()
	_initial = {"hp": int(first.get("hp", 0)), "base_hp": int(first.get("base_hp", 0))}
	game_started.emit({"runtime": runtime_ref, "stage_size": STAGE_SIZE})
	return true

func is_running() -> bool:
	return _running

func is_paused() -> bool:
	return _paused

## Freeze or resume the simulation. Paused time does not count as play time.
func set_paused(paused: bool) -> void:
	if not _running or paused == _paused:
		return
	_paused = paused
	_run.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	paused_changed.emit(paused)

## Current state of the live run for a HUD: the runtime's own summary (score, cleared, defeated and runtime-specific fields such as kills, level, gold, base_hp, time_left) plus play_seconds and hp where the runtime has a player. Empty when nothing is mounted.
## Also carries what the runtime keeps on its nodes rather than in its summary: max_hp next to hp, base_hp_max next to base_hp, shield_hits and boost for a runtime with a shield, boss_hp / boss_max_hp while a boss is alive, and `towers` ([{ id, type, cost, damage, range, cooldown }], in tower_ids order) for a runtime that places towers.
func snapshot() -> Dictionary:
	if not is_instance_valid(_run):
		return {}
	var summary: Dictionary = (_run.get_meta("summary", {}) as Dictionary).duplicate(true)
	if _run.has_meta("score"):
		summary["score"] = int(_run.get_meta("score"))
	summary["score"] = int(summary.get("score", 0))
	summary["play_seconds"] = _play_seconds
	summary["timed_out"] = bool(_run.get_meta("time_up", false))
	for actor_name in ["Player", "Hero"]:
		var actor := _run.get_node_or_null(actor_name)
		if actor != null and actor.has_meta("hp"):
			summary["hp"] = int(actor.get_meta("hp"))
			break
	if _run.has_method("tower_ids"):
		summary["tower_ids"] = Array(_run.call("tower_ids"))
	_add_node_fields(summary)
	return summary

func _add_node_fields(summary: Dictionary) -> void:
	if summary.has("hp"):
		summary["max_hp"] = maxi(int(_initial.get("hp", 0)), int(summary["hp"]))
	if summary.has("base_hp"):
		summary["base_hp_max"] = maxi(int(_initial.get("base_hp", 0)), int(summary["base_hp"]))
	var player := _run.get_node_or_null("Player")
	if player != null and _run.has_method("grant_shield"):
		summary["shield_hits"] = int(player.get_meta("shield_hits", 0))
		summary["boost"] = bool(player.get_meta("boost", false))
	var boss := _run.get_node_or_null("Boss")
	if boss != null and not boss.is_queued_for_deletion() and boss.has_meta("hp"):
		summary["boss_hp"] = int(boss.get_meta("hp"))
		summary["boss_max_hp"] = int(boss.get_meta("max_hp", boss.get_meta("hp")))
	if summary.has("tower_ids"):
		var specs: Dictionary = _dsl.get("towers", {}) if _dsl.get("towers") is Dictionary else {}
		var towers: Array = []
		for id: String in summary["tower_ids"]:
			var spec: Dictionary = specs.get(id, {}) if specs.get(id) is Dictionary else {}
			towers.append({"id": id, "type": str(spec.get("type", id)), "cost": maxi(0, int(spec.get("cost", 0))), "damage": int(spec.get("damage", 0)), "range": float(spec.get("range", 0.0)), "cooldown": float(spec.get("cooldown", 0.0))})
		summary["towers"] = towers

## Host-initiated end (the player quits). Emits game_ended with aborted = true; does nothing when no run is live.
func end_run() -> void:
	if _running:
		_finish(true)

## Commands a host may send to the live run. Returns false when the run is not live or the runtime does not support the action.
##   "move"        { "axis": Vector2 }                      extra movement input (touch pad, on-screen stick)
##   "boost"       { "on": bool }                            shooter: hold-to-boost
##   "shield"      {}                                        shooter: grant one shield hit
##   "place_tower" { "tower": id, "position": Vector2 }      tower_defense: stage coordinates inside STAGE_SIZE
func perform(action: String, args: Dictionary = {}) -> bool:
	if not _running or _paused:
		return false
	match action:
		"move":
			var axis: Variant = args.get("axis", Vector2.ZERO)
			_run.set_meta("touch_move", (axis as Vector2).limit_length(1.0) if axis is Vector2 else Vector2.ZERO)
			return true
		"boost":
			if _run.has_method("set_boost"):
				_run.call("set_boost", bool(args.get("on", false)))
				return true
		"shield":
			if _run.has_method("grant_shield"):
				_run.call("grant_shield")
				return true
		"place_tower":
			var at: Variant = args.get("position")
			if _run.has_method("place_tower") and at is Vector2:
				var local: Vector2 = (at as Vector2) - Vector2(STAGE_SIZE) / 2.0
				return bool(_run.call("place_tower", "host_%d" % Time.get_ticks_usec(), {"tower": str(args.get("tower", "")), "position": [local.x, local.y]}))
	return false

func _process(delta: float) -> void:
	if not _running or _paused or not is_instance_valid(_run):
		return
	_play_seconds += delta
	var state := snapshot()
	var score := int(state.get("score", 0))
	if score != _last_score:
		_last_score = score
		score_changed.emit(score)
	if bool(state.get("cleared", false)) or bool(state.get("defeated", false)) or bool(state.get("timed_out", false)):
		_finish(false)

## The finished run stays mounted and frozen so the host can keep showing its last frame; the next start_run or clear_run removes it.
func _finish(aborted: bool) -> void:
	var result := snapshot()
	result["runtime_ref"] = _runtime_ref
	result["aborted"] = aborted
	_running = false
	_paused = false
	_run.process_mode = Node.PROCESS_MODE_DISABLED
	game_ended.emit(result)

## Remove the mounted run without emitting anything. Ends a live run silently, so call end_run first when the result matters.
func clear_run() -> void:
	_drop_run()

func _drop_run() -> void:
	_running = false
	_paused = false
	if is_instance_valid(_run):
		if _run.get_parent() == self:
			remove_child(_run)
		_run.queue_free()
	_run = null
	_dsl = {}
	_initial = {}

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
