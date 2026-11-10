class_name NotifPrefScreen
extends ScreenBase

## 通知设置:总开关 + 互动/系统分组细分(总开关关闭时分组禁用)。
## 文案/分组/默认值来自 /prefs/notifications。无数据时空态。

var master := true
var prefs: Dictionary = {}
## 服务端拉到的偏好结构。
var _data: Dictionary = {}
var operations:OperationsCoordinator
func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

func refresh() -> void:
	if operations == null:
		return
	if await operations.load_notifications(state.locale):
		_data = operations.store.notifications
		if _data.has("master_default"):
			master = bool(_data["master_default"])
		prefs.clear()
		rebuild()

func invalidate_session()->void:
	master=true;prefs.clear();_data={};super.invalidate_session()

func _build() -> void:
	if _data.is_empty():
		content.add_child(empty_note(txt("his_empty")))
		return
	var master_label: String = _data.get("master_label", txt("np_master"))
	var master_sub: String = _data.get("master_sub", txt("np_master_sub"))

	var card := Widgets.card(theme_name())
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	var col := Widgets.vbox(Tokens.SPACE_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Widgets.body(master_label, theme_name()))
	col.add_child(Widgets.caption(master_sub, theme_name()))
	row.add_child(col)
	var sw := Widgets.switch(master, theme_name(), func(on: bool) -> void:
		_save_notification(str(_data.get("master_key","push_master")),on,true))
	sw.name = "MasterSwitch"
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	content.add_child(card)

	for group: Dictionary in _groups():
		content.add_child(Widgets.caption(group["label"], theme_name()))
		var box := Widgets.vbox(Tokens.SPACE_2)
		for item: Dictionary in group["items"]:
			var key: String = item["key"]
			if not prefs.has(key):
				prefs[key] = bool(item["default"])
			var c := Widgets.card(theme_name())
			var r := Widgets.hbox()
			c.add_child(r)
			var l := Widgets.body(item["label"], theme_name(), &"text_primary" if master else &"text_muted")
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(l)
			var t := Widgets.switch(prefs[key], theme_name(), func(on: bool) -> void: _save_notification(key,on,false), master)
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(t)
			box.add_child(c)
		content.add_child(box)

## 归一化分组:服务端 groups → [{label, items:[{key,default,label}]}];
## 无数据时把种子 np_items([[label,[[label,default],...]]]) 拍成同形,key 用 label 兜底。
func _groups() -> Array:
	if _data.has("groups"):
		return _data["groups"]
	return []

func _save_notification(key:String,on:bool,is_master:bool)->void:
	if operations==null:_toast(txt("request_failed"));rebuild();return
	if not await operations.set_notification(key,on):rebuild();return
	if is_master:master=on
	else:prefs[key]=on
	rebuild()
