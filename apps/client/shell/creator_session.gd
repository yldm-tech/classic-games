class_name CreatorSession
extends RefCounted

## 创作流的状态模型(「改一版」的核心 UX 逻辑,可 headless 断言)。
## 持有当前生效 DSL,把 AI 返回的 6902 补丁 apply 上去预览,支持撤销/重做。
## 输入框与预览由 UI 层负责；EditorScreen 和 PlayView 都读取此处的同一份生效 DSL。
##
## 典型流:from_baseline → apply_patch(AI 改一版)→ preview current() 喂 GameSession →
## 不满意 undo → 满意则 publish(把 current() 发布)。

const JsonPatch := preload("res://runtime/json_patch.gd")

var _baseline: Dictionary
var _history: Array = []   # 已应用的 patch 列表(每个是 6902 ops 数组)
var _redo: Array = []      # 撤销后可重做的 patch

func _init(baseline: Dictionary) -> void:
	_baseline = baseline.duplicate(true)

## 应用一次补丁(AI 返回的 ops)。成功返回 true 并清空 redo 栈;失败返回 false 不改状态。
func apply_patch(ops: Array) -> bool:
	if ops.is_empty():
		push_warning("apply_patch 拒绝空补丁")
		return false
	# 先在「当前生效 DSL」上试 apply,确保合法再入历史
	var res := JsonPatch.apply(current(), ops)
	if not res["ok"]:
		push_warning("apply_patch 失败: %s" % res["error"])
		return false
	_history.append(ops)
	_redo.clear()
	return true

## 把完整 DSL 文档转换成一组顶层 RFC 6902 操作后纳入同一历史栈。
## JsonPatch 出于安全拒绝根路径替换，因此按顶层 key 生成 add/remove/replace；
## 这样手工编辑与 AI 修改共享撤销/重做和发布数据源。
func apply_document(next: Dictionary) -> bool:
	var prev := current()
	var ops: Array = []
	for key in prev.keys():
		if not next.has(key):
			ops.append({"op": "remove", "path": "/%s" % _escape_pointer(str(key))})
	for key in next.keys():
		var path := "/%s" % _escape_pointer(str(key))
		if not prev.has(key):
			ops.append({"op": "add", "path": path, "value": next[key]})
		elif prev[key] != next[key]:
			ops.append({"op": "replace", "path": path, "value": next[key]})
	if ops.is_empty():
		return true
	return apply_patch(ops)

func _escape_pointer(key: String) -> String:
	return key.replace("~", "~0").replace("/", "~1")

## 当前生效 DSL = 基线 + 历史补丁逐层 apply。
## 每步入历史前都已对当时的 current() 校验过,正常重放必成功;但仍检查 ok,
## 万一某步失败(防御),停在最后一个合法状态而非返回 null,避免向下游传 null DSL。
func current() -> Dictionary:
	var dsl: Variant = _baseline.duplicate(true)
	for ops in _history:
		var res := JsonPatch.apply(dsl, ops)
		if not res["ok"]:
			push_error("current() 重放补丁失败: %s" % res["error"])
			break
		dsl = res["result"]
	return dsl

func can_undo() -> bool:
	return not _history.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func undo() -> void:
	if can_undo():
		_redo.append(_history.pop_back())

func redo() -> void:
	if can_redo():
		_history.append(_redo.pop_back())

## 是否相对基线有改动(决定「发布」按钮是否可用)。
func is_dirty() -> bool:
	return not _history.is_empty()

## 编辑步数(给 UI 显示「已改 N 处」)。
func step_count() -> int:
	return _history.size()
