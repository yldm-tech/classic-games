class_name PublishScreen
extends ScreenBase

## 发布流程:封面色调 → 名称 → 一句话简介 → 标签(≤3)→ 定价 → 提交审核。
## 提交经 submitted 信号交 AppRoot 走 /mods + /games 真实发布。

signal submitted(title: String)

var _tone := "ember"
var _tags: Dictionary = {}
var _price := 0
var _name_edit: LineEdit
var _desc_edit: LineEdit
var coordinator: CreationCoordinator

func _init(p_state: Node, p_coordinator: CreationCoordinator = null) -> void:
	coordinator = p_coordinator
	super(p_state)

func _build() -> void:
	content.add_child(Widgets.caption(txt("pb_cover"), theme_name()))
	var tones := Widgets.hbox(Tokens.SPACE_2)
	tones.name = "ToneRow"
	for tone: String in GameCard.TONES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = GameCard.TONES[tone]
		sb.set_corner_radius_all(Tokens.RADIUS_SM)
		if tone == _tone:
			sb.border_color = Tokens.color(&"accent_primary", theme_name())
			sb.set_border_width_all(2)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		var t := tone
		b.pressed.connect(func() -> void:
			_tone = t
			rebuild())
		tones.add_child(b)
	content.add_child(tones)

	content.add_child(Widgets.caption(txt("pb_name"), theme_name()))
	_name_edit = LineEdit.new()
	_name_edit.name = "TitleEdit"
	_name_edit.placeholder_text = txt("pb_name_ph")
	content.add_child(_name_edit)

	content.add_child(Widgets.caption(txt("pb_desc"), theme_name()))
	_desc_edit = LineEdit.new()
	_desc_edit.name = "DescEdit"
	_desc_edit.placeholder_text = txt("pb_desc_ph")
	content.add_child(_desc_edit)

	content.add_child(Widgets.caption(txt("pb_tags"), theme_name()))
	var flow := HFlowContainer.new()
	flow.name = "TagFlow"
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	var cats: Dictionary = txt("cats")
	for key: String in Catalog.CAT_KEYS.slice(1):
		var on := _tags.has(key)
		var c := Widgets.chip(cats[key], on, theme_name())
		var k := key
		c.pressed.connect(func() -> void:
			if _tags.has(k):
				_tags.erase(k)
			elif _tags.size() < 3:  # 最多 3 个
				_tags[k] = true
			rebuild())
		flow.add_child(c)
	content.add_child(flow)

	content.add_child(Widgets.caption(txt("pb_price"), theme_name()))
	var seg := Widgets.segment(txt("pb_prices"), _price, theme_name(), func(i: int) -> void:
		_price = i
		rebuild())
	seg.name = "PriceSeg"
	content.add_child(seg)

	var submit := Widgets.primary_button(txt("pb_submit"), theme_name())
	submit.name = "SubmitButton"
	submit.pressed.connect(_submit)
	content.add_child(submit)

func _submit() -> void:
	var title := _name_edit.text.strip_edges()
	if title == "" or coordinator == null: return
	var tags: Array = _tags.keys()
	var category := str(tags[0]) if not tags.is_empty() else ""
	if await coordinator.submit_for_review(title, _desc_edit.text.strip_edges(), tags, category, coordinator.store.runtime_ref):
		_toast(txt("pb_submitted_toast"))
		submitted.emit(title)
	else:
		_toast(txt("rev_rejected"))
