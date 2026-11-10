class_name ScreenBase
extends ScrollContainer

## Presentation-only 屏幕基类：持有 AppState，并响应主题/语言变化重建视图。

const Tokens := preload("res://shell/design_system/theme/tokens.gd")
const Strings := preload("res://i18n/strings.gd")
const Widgets := preload("res://shell/design_system/components/widgets.gd")
const EmptyStateScript := preload("res://ui/patterns/empty_state.gd")

var state: Node
var content: VBoxContainer
## Toast 出口由 AppRoot 注入；屏内操作反馈统一走 _toast。
var toaster := Callable()
## 卡片网格列数由 AppRoot 按布局喂入：桌面 4 / iPad 3 / 手机 2。
## 用 shell 驱动而非读 viewport——tab 屏构造期不在树上,读不到窗口宽度。
var card_cols := 2
var _refreshed := false

## 应用装配层在屏幕首次展示时调用；子类只能委托显式注入的 coordinator。
func refresh() -> void:
	pass

## Account-scoped screens override this to clear local read models, then call super.
func invalidate_session()->void:
	_refreshed=false
	rebuild()

func _init(p_state: Node) -> void:
	state = p_state
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	content = Widgets.vbox(Tokens.SPACE_4)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)
	state.theme_changed.connect(func(_t: String) -> void: rebuild())
	state.locale_changed.connect(func(_l: String) -> void: rebuild())
	rebuild()

## 取当前语言文案。
func txt(key: String) -> Variant:
	return Strings.t(state.locale, key)

func txt_fmt(key: String, args: Array) -> String:
	return Strings.fmt(state.locale, key, args)

func theme_name() -> String:
	return state.theme

func _toast(text: String) -> void:
	if toaster.is_valid():
		toaster.call(text)

## 统一空态。名称固定 EmptyNote,结构测试按名查找。
func empty_note(message: String, action: String = "", on_action: Callable = Callable()) -> Control:
	var view = EmptyStateScript.new()
	view.name = "EmptyNote"
	view.configure(message, theme_name(), action)
	if on_action.is_valid():
		view.retry_requested.connect(on_action)
	return view

## 标准行卡(图标位可空):左标题 + 右值 + ›,整行可点。设置/账号/目录类页面复用。
func nav_row(label: String, value: String, on_tap: Callable) -> Control:
	var card := Widgets.card(theme_name())
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	var l := Widgets.body(label, theme_name())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if value != "":
		row.add_child(Widgets.caption(value, theme_name()))
	row.add_child(Widgets.caption("›", theme_name()))
	if on_tap.is_valid():
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				on_tap.call())
	return card

## 整屏重建。旧节点先摘树再延迟释放——rebuild 常由按钮信号触发,
## 立即 free 会砸到正在发信号的按钮(locked object)。
func rebuild() -> void:
	while content.get_child_count() > 0:
		var c := content.get_child(0)
		var was_inside_tree:=c.is_inside_tree()
		content.remove_child(c)
		# 构造期 screen 尚未入树，queue_free() 没有 SceneTree 删除队列可进入，会永久泄漏；
		# 入树后 rebuild 常发生在按钮回调中，则必须延迟释放以避开 signal lock。
		if was_inside_tree: c.queue_free()
		else: c.call_deferred("free")
	_build()

## 子类组装屏幕内容。
func _build() -> void:
	pass
