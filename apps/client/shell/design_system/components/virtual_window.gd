class_name VirtualWindow
extends RefCounted

## 虚拟列表的窗口计算(纯逻辑,可 headless 断言)。
## 评审把虚拟列表列为「长期 bug 来源」——核心 bug 面是「给定滚动位置该渲染哪些 item、
## 节点池如何映射」。本类把这块数学独立出来单测;实际 Control 渲染/滚动手感需真机验证。
##
## window(scroll_offset) 返回应渲染区间 {first, count}(含上下 buffer、夹到边界),
## 列表只为这区间维护 count 个复用节点,放到 item_y(i) 处。

var item_height: float
var viewport_height: float
var total: int
var buffer: int

func _init(p_item_height: float, p_viewport_height: float, p_total: int, p_buffer: int = 2) -> void:
	item_height = max(1.0, p_item_height)
	viewport_height = max(0.0, p_viewport_height)
	total = max(0, p_total)
	buffer = max(0, p_buffer)

## 应渲染的 item 区间(含上下 buffer,夹到 [0, total))。
func window(scroll_offset: float) -> Dictionary:
	if total == 0:
		return {"first": 0, "count": 0}
	var visible := int(ceil(viewport_height / item_height)) + buffer * 2
	var first := int(floor(scroll_offset / item_height)) - buffer
	# first 上界夹到 total-visible,保证滚到底/过滚时仍渲染满一屏(否则底部只剩 1 行)。
	first = clampi(first, 0, max(0, total - visible))
	var count := clampi(visible, 0, total - first)
	return {"first": first, "count": count}

## 内容总高(撑滚动条用)。
func content_height() -> float:
	return total * item_height

## 第 index 项的 y 坐标。
func item_y(index: int) -> float:
	return index * item_height

## 同时可见的项数上限(含 buffer),估算节点池大小。
func pool_size() -> int:
	return int(ceil(viewport_height / item_height)) + buffer * 2
