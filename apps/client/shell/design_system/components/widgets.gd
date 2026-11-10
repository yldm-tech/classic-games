class_name Widgets
extends RefCounted

## 设计系统组件工厂(docs/16 的 components 层:纯展示 + 受控,无业务)。
## 从 Control 基元搭,对照原型组件(按钮/卡片/chip/段控/标题),颜色字号全走 Tokens。
## 屏幕层只组合这里的件,不自配色——主题切换才能整体生效。

const Tokens := preload("res://shell/design_system/theme/tokens.gd")

# ── 文本 ──────────────────────────────────────────────────
static func heading(text: String, level: int, theme: String) -> Label:
	var sizes := {1: Tokens.FONT_H1, 2: Tokens.FONT_H2, 3: Tokens.FONT_H3, 4: Tokens.FONT_H4, 5: Tokens.FONT_H5}
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sizes.get(level, Tokens.FONT_H3))
	l.add_theme_color_override("font_color", Tokens.color(&"text_primary", theme))
	return l

static func body(text: String, theme: String, color_token: StringName = &"text_primary") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	l.add_theme_color_override("font_color", Tokens.color(color_token, theme))
	return l

static func caption(text: String, theme: String, color_token: StringName = &"text_muted") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	l.add_theme_color_override("font_color", Tokens.color(color_token, theme))
	return l

## 大数字(display 字体位,如身份卡统计、结算分数)。单行不换行(docs/19 排版要点)。
static func big_number(text: String, theme: String, size: int = Tokens.FONT_H2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Tokens.color(&"text_primary", theme))
	return l

## 双色品牌 logo:Classic(主文字色)+ Games(熔炉橙红),对照原型 .fp-logo。
static func brand_logo(theme: String, size: int = Tokens.FONT_H3) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var forge_part := Label.new()
	forge_part.text = "Classic "
	forge_part.add_theme_font_size_override("font_size", size)
	forge_part.add_theme_color_override("font_color", Tokens.color(&"text_primary", theme))
	box.add_child(forge_part)
	var play_part := Label.new()
	play_part.text = "Games"
	play_part.add_theme_font_size_override("font_size", size)
	play_part.add_theme_color_override("font_color", Tokens.color(&"accent_primary", theme))
	box.add_child(play_part)
	return box

# ── 面板 / 卡片 ────────────────────────────────────────────
static func card_style(theme: String, fill_token: StringName = &"surface_card", radius: int = Tokens.RADIUS_LG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(fill_token, theme)
	sb.set_corner_radius_all(radius)
	sb.border_color = Tokens.color(&"border_subtle", theme)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(Tokens.SPACE_4)
	return sb

static func card(theme: String, fill_token: StringName = &"surface_card") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(theme, fill_token))
	return p

static func divider(theme: String) -> ColorRect:
	var r := ColorRect.new()
	r.color = Tokens.color(&"border_subtle", theme)
	r.custom_minimum_size = Vector2(0, 1)
	return r

# ── 按钮 ──────────────────────────────────────────────────
static func _button_style(fill: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = Tokens.SPACE_4
	sb.content_margin_right = Tokens.SPACE_4
	sb.content_margin_top = Tokens.SPACE_2
	sb.content_margin_bottom = Tokens.SPACE_2
	return sb

static func _make_button(text: String, fill: StringName, hover: StringName, press: StringName, font: StringName, theme: String, radius: int = Tokens.RADIUS_MD) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, Tokens.HIT_MIN)
	b.add_theme_stylebox_override("normal", _button_style(Tokens.color(fill, theme), radius))
	b.add_theme_stylebox_override("hover", _button_style(Tokens.color(hover, theme), radius))
	b.add_theme_stylebox_override("pressed", _button_style(Tokens.color(press, theme), radius))
	# disabled:同形降透明,可感知不可点
	b.add_theme_stylebox_override("disabled", _button_style(Color(Tokens.color(fill, theme), 0.4), radius))
	b.add_theme_color_override("font_color", Tokens.color(font, theme))
	b.add_theme_color_override("font_hover_color", Tokens.color(font, theme))
	b.add_theme_color_override("font_pressed_color", Tokens.color(font, theme))
	b.add_theme_color_override("font_disabled_color", Color(Tokens.color(font, theme), 0.5))
	b.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	return b

## 主按钮(熔炉橙红,CTA)。
static func primary_button(text: String, theme: String) -> Button:
	return _make_button(text, &"accent_primary", &"accent_primary_hover", &"accent_primary_press", &"text_on_primary", theme)

## 次按钮(浮起表面)。
static func secondary_button(text: String, theme: String) -> Button:
	return _make_button(text, &"surface_raised", &"surface_raised", &"surface_input", &"text_primary", theme)

## AI 按钮(volt 荧光绿,生成类动作)。
static func ai_button(text: String, theme: String) -> Button:
	return _make_button(text, &"accent_ai", &"accent_ai_hover", &"accent_ai_press", &"text_on_volt", theme)

## 危险操作(退出登录/删除)。
static func danger_button(text: String, theme: String) -> Button:
	return _make_button(text, &"tint_danger", &"tint_danger", &"tint_danger", &"status_danger", theme)

## 幽灵按钮(无底、强调色文字):取消、查看全部、次要导航。
static func ghost_button(text: String, theme: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(0, Tokens.HIT_MIN)
	b.add_theme_color_override("font_color", Tokens.color(&"accent_primary", theme))
	b.add_theme_color_override("font_hover_color", Tokens.color(&"accent_primary_hover", theme))
	b.add_theme_color_override("font_pressed_color", Tokens.color(&"accent_primary_press", theme))
	b.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	return b

## 方形图标按钮(⋯ / 分享 / 播放)。
static func icon_button(glyph: String, theme: String) -> Button:
	var b := secondary_button(glyph, theme)
	b.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

## 圆形首字母头像(对照原型 .fp-avatar)。
static func avatar(letter: String, theme: String, size: int = 40) -> PanelContainer:
	var av := PanelContainer.new()
	av.name = "Avatar"
	av.custom_minimum_size = Vector2(size, size)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"accent_primary", theme)
	sb.set_corner_radius_all(Tokens.RADIUS_PILL)
	av.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	var glyph := letter.strip_edges().trim_prefix("@").left(1).to_upper()
	l.text = glyph if glyph != "" else "?"
	l.add_theme_font_size_override("font_size", maxi(Tokens.FONT_CAPTION, int(size / 2.2)))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(l)
	return av

## KPI 卡(身份/创作者统计):大数字 + 标签,居中。
static func kpi_card(value: String, label: String, theme: String) -> PanelContainer:
	var p := card(theme)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := vbox(Tokens.SPACE_1)
	p.add_child(col)
	var n := big_number(value, theme, Tokens.FONT_H3)
	n.name = "KpiValue"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var l := caption(label, theme)
	l.name = "KpiLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return p

## 圆角骨架块(首载占位)。
static func skeleton_block(height: float, theme: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, height)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"surface_card", theme)
	sb.set_corner_radius_all(Tokens.RADIUS_MD)
	p.add_theme_stylebox_override("panel", sb)
	return p

## 分区标题 + 可选操作。
static func section_header(title: String, theme: String, action: String = "", on_action: Callable = Callable()) -> HBoxContainer:
	var head := hbox()
	head.add_child(heading(title, 3, theme))
	head.add_child(spacer())
	if action != "":
		var b := ghost_button(action, theme)
		b.name = "SectionAction"
		b.custom_minimum_size = Vector2(0, 32)
		if on_action.is_valid():
			b.pressed.connect(on_action)
		head.add_child(b)
	return head

## 开关(对照原型 .fp-switch):胶囊轨道 + 白色圆点。on=accent 轨道、点靠右;off=描边轨道、点靠左。
## 替代 Godot 原生 CheckButton(深色下 off 态轨道几乎不可见)。受控:翻转即回调 on_toggled(new) 并自刷新。
static func switch(on: bool, theme: String, on_toggled: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(46, 26)
	b.modulate = Color(1, 1, 1, 1.0 if enabled else 0.45)
	var knob := Panel.new()
	knob.custom_minimum_size = Vector2(20, 20)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kb := StyleBoxFlat.new()
	kb.bg_color = Color.WHITE
	kb.set_corner_radius_all(Tokens.RADIUS_PILL)
	knob.add_theme_stylebox_override("panel", kb)
	b.add_child(knob)
	var refresh := func(state: bool) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Tokens.color(&"accent_primary" if state else &"surface_input", theme)
		sb.set_corner_radius_all(Tokens.RADIUS_PILL)
		if not state:
			sb.border_color = Tokens.color(&"border_default", theme)
			sb.set_border_width_all(1)
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, sb)
		knob.anchor_top = 0.5
		knob.anchor_bottom = 0.5
		knob.offset_top = -10
		knob.offset_bottom = 10
		knob.anchor_left = 1.0 if state else 0.0
		knob.anchor_right = 1.0 if state else 0.0
		knob.offset_left = -23 if state else 3
		knob.offset_right = -3 if state else 23
	refresh.call(on)
	b.toggled.connect(func(v: bool) -> void:
		refresh.call(v)
		on_toggled.call(v))
	return b

# ── Chip(筛选/标签,胶囊形,可选中) ─────────────────────────
static func chip(text: String, on: bool, theme: String, volt: bool = false) -> Button:
	var fill: StringName = (&"tint_volt" if volt else &"tint_ember") if on else &"surface_raised"
	var font: StringName = (&"accent_ai" if volt else &"accent_primary") if on else &"text_secondary"
	var b := _make_button(text, fill, fill, fill, font, theme, Tokens.RADIUS_PILL)
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", Tokens.FONT_BODY_SM)
	return b

# ── 段控(segment,如 热门榜/飙升榜/新作榜) ───────────────────
## 返回 HBoxContainer,内部为可点的段;选中段着色。on_select.call(index) 由调用方接行为。
static func segment(options: Array, active: int, theme: String, on_select: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", Tokens.SPACE_1)
	for i in options.size():
		var on := i == active
		var b := _make_button(str(options[i]), &"surface_raised" if on else &"surface_input", &"surface_raised", &"surface_raised", &"text_primary" if on else &"text_muted", theme, Tokens.RADIUS_SM)
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", Tokens.FONT_BODY_SM)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func() -> void: on_select.call(idx))
		box.add_child(b)
	return box

# ── 徽章(已上线/AI 出品等,单行不换行) ───────────────────────
static func badge(text: String, theme: String, volt: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"tint_volt" if volt else &"tint_ember", theme)
	sb.set_corner_radius_all(Tokens.RADIUS_XS)
	sb.content_margin_left = Tokens.SPACE_2
	sb.content_margin_right = Tokens.SPACE_2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	l.add_theme_color_override("font_color", Tokens.color(&"accent_ai" if volt else &"accent_primary", theme))
	p.add_child(l)
	return p

## 全局 Theme(级联):统一 LineEdit/TextEdit/ProgressBar 的设计系统样式,
## 替代 Godot 默认主题(灰底蓝条)。赋给 AppRoot.theme 即对全树生效。
static func app_theme(theme: String) -> Theme:
	var t := Theme.new()
	var input_sb := StyleBoxFlat.new()
	input_sb.bg_color = Tokens.color(&"surface_input", theme)
	input_sb.set_corner_radius_all(Tokens.RADIUS_SM)
	input_sb.border_color = Tokens.color(&"border_default", theme)
	input_sb.set_border_width_all(1)
	input_sb.set_content_margin_all(Tokens.SPACE_3)
	var focus_sb := input_sb.duplicate()
	focus_sb.border_color = Tokens.color(&"border_focus", theme)
	focus_sb.set_border_width_all(2)
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, input_sb)
		t.set_stylebox("focus", cls, focus_sb)
		t.set_color("font_color", cls, Tokens.color(&"text_primary", theme))
		t.set_color("font_placeholder_color", cls, Tokens.color(&"text_muted", theme))
		t.set_color("caret_color", cls, Tokens.color(&"accent_primary", theme))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Tokens.color(&"border_subtle", theme)
	bar_bg.set_corner_radius_all(Tokens.RADIUS_PILL)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Tokens.color(&"accent_primary", theme)
	bar_fill.set_corner_radius_all(Tokens.RADIUS_PILL)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t

## 封面压暗渐变(--scrim-media):上透明 → 下近黑,保证叠图文字可读。
static func scrim() -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.06, 0.05, 0.055, 0.0), Color(0.06, 0.05, 0.055, 0.88)])
	grad.offsets = PackedFloat32Array([0.4, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## 未读红点(TabBar/列表角标):danger 底胶囊 + micro 数字。
static func unread_dot(count: int, theme: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "UnreadDot"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"status_danger", theme)
	sb.set_corner_radius_all(Tokens.RADIUS_PILL)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = str(count)
	l.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# ── 行容器快捷 ─────────────────────────────────────────────
static func vbox(separation: int = Tokens.SPACE_3) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func hbox(separation: int = Tokens.SPACE_3) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
