class_name HelpScreen
extends ScreenBase

## Operations-owned 帮助与反馈屏：FAQ + 反馈提交。

var _expanded: Dictionary = {}
var operations:OperationsCoordinator
func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

func _build() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "FaqList"
	var faqs: Array = txt("faqs")
	for i in faqs.size():
		var card := Widgets.card(theme_name())
		var col := Widgets.vbox(Tokens.SPACE_2)
		card.add_child(col)
		col.add_child(Widgets.body(faqs[i][0], theme_name()))
		if _expanded.has(i):
			col.add_child(Widgets.caption(faqs[i][1], theme_name(), &"text_secondary"))
		var idx := i
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if _expanded.has(idx):
					_expanded.erase(idx)
				else:
					_expanded[idx] = true
				rebuild())
		list.add_child(card)
	content.add_child(list)

	var fb := TextEdit.new()
	fb.name = "FeedbackEdit"
	fb.placeholder_text = txt("feedback_ph")
	fb.custom_minimum_size = Vector2(0, 72)
	content.add_child(fb)
	var send := Widgets.primary_button(txt("comment_send"), theme_name())
	send.name = "SendButton"
	send.pressed.connect(func() -> void:
		var text := fb.text.strip_edges()
		if text == "": return
		if operations == null: _toast(txt("request_failed")); return
		send.disabled = true
		var submitted:=await operations.submit_feedback(text)
		send.disabled = false
		if submitted:
			fb.text = ""
			_toast(txt("toast_feedback"))
		else: _toast(txt("request_failed")))
	content.add_child(send)
