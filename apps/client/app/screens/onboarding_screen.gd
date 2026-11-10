class_name OnboardingScreen
extends ScreenBase

## Application-owned 新手引导：欢迎、兴趣与通知授权。

signal done

var step := 0
var picked: Dictionary = {}

func _build() -> void:
	_build_step_dots()
	match step:
		0: _step_welcome()
		1: _step_interests()
		2: _step_notify()

func _build_step_dots() -> void:
	var row := Widgets.hbox(Tokens.SPACE_2)
	row.name = "StepDots"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(8 if i != step else 22, 8)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Tokens.color(&"accent_primary" if i == step else &"border_default", theme_name())
		sb.set_corner_radius_all(Tokens.RADIUS_PILL)
		dot.add_theme_stylebox_override("panel", sb)
		row.add_child(dot)
	var wrap := CenterContainer.new()
	wrap.add_child(row)
	content.add_child(wrap)
	content.add_child(Widgets.caption(txt_fmt("step_fmt", [step + 1, 3]), theme_name()))

func _next() -> void:
	step += 1
	rebuild()

func _step_welcome() -> void:
	content.add_child(Widgets.heading(txt("ob_title1"), 1, theme_name()))
	content.add_child(Widgets.body(txt("ob_sub1"), theme_name(), &"text_secondary"))
	var next := Widgets.primary_button(txt("ob_next"), theme_name())
	next.name = "NextButton"
	next.pressed.connect(_next)
	content.add_child(next)

func _step_interests() -> void:
	content.add_child(Widgets.heading(txt("ob_title2"), 2, theme_name()))
	content.add_child(Widgets.caption(txt("ob_sub2"), theme_name()))
	var flow := HFlowContainer.new()
	flow.name = "TagFlow"
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	var tags: Array = txt("ob_tags")
	for i in tags.size():
		var c := Widgets.chip(tags[i], picked.has(i), theme_name())
		var idx := i
		c.pressed.connect(func() -> void:
			if picked.has(idx):
				picked.erase(idx)
			else:
				picked[idx] = true
			rebuild())
		flow.add_child(c)
	content.add_child(flow)
	var next := Widgets.primary_button(txt("ob_next"), theme_name())
	next.name = "NextButton"
	next.disabled = picked.size() < 3  # 至少选 3 个
	next.pressed.connect(_next)
	content.add_child(next)

func _step_notify() -> void:
	content.add_child(Widgets.heading(txt("ob_title3"), 2, theme_name()))
	content.add_child(Widgets.body(txt("ob_sub3"), theme_name(), &"text_secondary"))
	var allow := Widgets.primary_button(txt("ob_allow"), theme_name())
	allow.name = "AllowButton"
	allow.pressed.connect(func() -> void: done.emit())
	content.add_child(allow)
	var skip := Widgets.secondary_button(txt("ob_skip"), theme_name())
	skip.name = "SkipButton"
	skip.pressed.connect(func() -> void: done.emit())
	content.add_child(skip)
