class_name TeenScreen
extends ScreenBase

## 青少年模式(合规,docs/14):独立数字密码、每日时长/宵禁/内容过滤说明、开关。
## 标题/说明/规则/密码位数来自 /prefs/teen。无数据时空态。

var enabled := false
var _pin: LineEdit
## 服务端拉到的结构。
var _data: Dictionary = {}
var operations:OperationsCoordinator
func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

func refresh() -> void:
	if operations == null:
		return
	if await operations.load_teen(state.locale):
		_data = operations.store.teen
		if _data.has("default_enabled"):
			enabled = bool(_data["default_enabled"])
		rebuild()

func invalidate_session()->void:
	enabled=false;_data={};_pin=null;super.invalidate_session()

## 开启所需密码位数(服务端 pin_length,缺省 4)。
func _pin_length() -> int:
	return int(_data.get("pin_length", 4))

func _build() -> void:
	if _data.is_empty():
		content.add_child(empty_note(txt("his_empty")))
		return
	var title: String = _data.get("title", txt("teen_title"))
	var description: String = _data.get("description", txt("teen_desc"))
	var state_on: String = _data.get("state_on", txt("teen_state_on"))
	var state_off: String = _data.get("state_off", txt("teen_state_off"))
	var pin_label: String = _data.get("pin_label", txt("teen_pin"))
	var pin_placeholder: String = _data.get("pin_placeholder", txt("teen_pin_ph"))
	var rules: Array = _data.get("rules", txt("teen_rules"))
	var pin_len := _pin_length()

	var status := Widgets.card(theme_name(), &"tint_ember" if enabled else &"surface_card")
	status.name = "StatusCard"
	var srow := Widgets.hbox()
	status.add_child(srow)
	var s := Widgets.body(title, theme_name())
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(s)
	var tag := Widgets.caption(state_on if enabled else state_off, theme_name(),
		&"accent_primary" if enabled else &"text_muted")
	tag.name = "StateTag"
	srow.add_child(tag)
	content.add_child(status)

	content.add_child(Widgets.body(description, theme_name(), &"text_secondary"))
	var rule_list := Widgets.vbox(Tokens.SPACE_2)
	rule_list.name = "RuleList"
	for rule: String in rules:
		var card := Widgets.card(theme_name())
		card.add_child(Widgets.caption(rule, theme_name(), &"text_secondary"))
		rule_list.add_child(card)
	content.add_child(rule_list)

	content.add_child(Widgets.caption(pin_label, theme_name()))
	_pin = LineEdit.new()
	_pin.name = "PinEdit"
	_pin.placeholder_text = pin_placeholder
	_pin.max_length = pin_len
	content.add_child(_pin)

	var toggle := Widgets.primary_button(txt("teen_off_btn") if enabled else txt("teen_on_btn"), theme_name())
	toggle.name = "ToggleButton"
	toggle.pressed.connect(func() -> void:
		if _pin.text.length() != pin_len:
			return  # 开启与关闭都必须提交完整 PIN
		var next:=not enabled
		if operations==null:_toast(txt("request_failed"));return
		if not await operations.set_teen(next,_pin.text):return
		enabled = next
		state.set_teen_enabled(enabled)
		_toast(txt("teen_on_toast") if enabled else txt("teen_off_toast"))
		rebuild())
	content.add_child(toggle)
