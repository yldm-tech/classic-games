class_name ReviewScreen
extends ScreenBase

## 审核进度:提交→审核→上线时间线 + 驳回卡(理由/去修改/重新提交)。
## 服务端 games 状态机已有 in_review/rejected;状态由 AppRoot 经 set_review_state 注入。

signal fix_requested

var rejected := false
var resubmitted := false
var game_id := ""
var coordinator: CreationCoordinator

func _init(p_state: Node, p_coordinator: CreationCoordinator = null) -> void:
	coordinator = p_coordinator
	super(p_state)

func set_review_state(p_rejected: bool, p_game_id: String = "") -> void:
	rejected = p_rejected
	game_id = p_game_id
	resubmitted = false
	rebuild()

func _build() -> void:
	var steps: Array = txt("rev_steps")
	var timeline := Widgets.vbox(Tokens.SPACE_2)
	timeline.name = "Timeline"
	for i in steps.size():
		var card := Widgets.card(theme_name(), &"tint_ember" if i == 1 else &"surface_card")
		var col := Widgets.vbox(Tokens.SPACE_1)
		card.add_child(col)
		var row := Widgets.hbox(Tokens.SPACE_2)
		var dot := Label.new()
		dot.text = "✓" if i == 0 else "●" if i == 1 else "○"
		dot.add_theme_color_override("font_color",
			Tokens.color(&"status_success" if i == 0 else &"accent_primary" if i == 1 else &"text_muted", theme_name()))
		row.add_child(dot)
		var step_title := Widgets.body(steps[i][0], theme_name())
		step_title.autowrap_mode = TextServer.AUTOWRAP_OFF  # 行内短标题不换行(否则在 HBox 里竖排)
		row.add_child(step_title)
		row.add_child(Widgets.spacer())
		if i == 1:
			row.add_child(Widgets.caption(txt("rev_eta"), theme_name()))
		col.add_child(row)
		col.add_child(Widgets.caption(steps[i][1], theme_name(), &"text_secondary"))
		timeline.add_child(card)
	content.add_child(timeline)

	if not rejected:
		return
	content.add_child(Widgets.caption(txt("rev_rej_head"), theme_name()))
	var rej := Widgets.card(theme_name(), &"tint_danger")
	rej.name = "RejectedCard"
	var col := Widgets.vbox(Tokens.SPACE_2)
	rej.add_child(col)
	col.add_child(Widgets.badge(txt("rev_rejected"), theme_name()))
	col.add_child(Widgets.body(txt("rev_reason"), theme_name(), &"text_secondary"))
	var actions := Widgets.hbox(Tokens.SPACE_2)
	var fix := Widgets.secondary_button(txt("rev_fix"), theme_name())
	fix.name = "FixButton"
	fix.pressed.connect(func() -> void: fix_requested.emit())
	actions.add_child(fix)
	var re := Widgets.primary_button(txt("rev_resubmit"), theme_name())
	re.name = "ResubmitButton"
	re.disabled = resubmitted
	re.pressed.connect(func() -> void:
		if coordinator == null or game_id == "": _toast(txt("request_failed")); return
		re.disabled = true
		if await coordinator.resubmit(game_id):
			resubmitted = true
			_toast(txt("rev_resubmit_toast"))
			rebuild()
		else:
			re.disabled = false
			_toast(txt("request_failed")))
	actions.add_child(re)
	col.add_child(actions)
	content.add_child(rej)
