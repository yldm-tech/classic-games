class_name ReportScreen
extends ScreenBase

## 更多操作:举报(理由单选,真接 /report)+ 屏蔽作者(/block)+ 不感兴趣。

signal action_completed(action:String)

var target: Dictionary = {}
var _reason := -1
var _action_pending:=false
var operations:OperationsCoordinator
func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

func set_target(game: Dictionary) -> void:
	target = game
	_reason = -1
	_action_pending=false
	rebuild()

func invalidate_session()->void:
	target={};_reason=-1;_action_pending=false;super.invalidate_session()

func _build() -> void:
	content.add_child(Widgets.heading(txt("report_title"), 3, theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "ReasonList"
	var reasons: Array = txt("report_reasons")
	for i in reasons.size():
		var card := Widgets.card(theme_name(), &"tint_ember" if i == _reason else &"surface_card")
		card.add_child(Widgets.body(reasons[i], theme_name()))
		var idx := i
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_reason = idx
				rebuild())
		list.add_child(card)
	content.add_child(list)

	var submit := Widgets.primary_button(txt("report_submit"), theme_name())
	submit.name = "SubmitButton"
	submit.disabled = _reason < 0 or _action_pending
	submit.pressed.connect(func() -> void:
		if _action_pending:return
		_action_pending=true;rebuild()
		var reason:=str(txt("report_reasons")[_reason])
		if operations!=null and await operations.report("game",str(target.get("id","")),reason):action_completed.emit("report")
		else:_action_pending=false;_toast(txt("request_failed"));rebuild())
	content.add_child(submit)

	content.add_child(Widgets.divider(theme_name()))
	var block := Widgets.danger_button(txt("block_user"), theme_name())
	block.name = "BlockButton"
	block.disabled=_action_pending
	block.pressed.connect(func() -> void:
		if _action_pending:return
		_action_pending=true;rebuild()
		var author:=str(target.get("author_id",""))
		if author=="":author=str(target.get("by",""))
		if operations!=null and await operations.block_user(author):action_completed.emit("block")
		else:_action_pending=false;_toast(txt("request_failed"));rebuild())
	content.add_child(block)
	var ni := Widgets.secondary_button(txt("not_interested"), theme_name())
	ni.name = "NotInterestedButton"
	ni.disabled=_action_pending
	ni.pressed.connect(func() -> void:
		if _action_pending:return
		_action_pending=true;rebuild()
		if operations!=null and await operations.not_interested(str(target.get("id",""))):action_completed.emit("not_interested")
		else:_action_pending=false;_toast(txt("request_failed"));rebuild())
	content.add_child(ni)
