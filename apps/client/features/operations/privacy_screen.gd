class_name PrivacyScreen
extends ScreenBase

## 隐私设置:可见范围/私信权限(段控)+ 在线状态/二创授权/个性化推荐(开关)。
## 说明/条目/默认值来自 /prefs/privacy。无数据时空态。

var choices: Dictionary = {}
## 服务端拉到的结构。
var _data: Dictionary = {}
var operations:OperationsCoordinator
func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

func refresh() -> void:
	if operations == null:
		return
	if await operations.load_privacy(state.locale):
		_data = operations.store.privacy
		choices.clear()
		rebuild()

func invalidate_session()->void:
	choices.clear();_data={};super.invalidate_session()

func _build() -> void:
	if _data.is_empty():
		content.add_child(empty_note(txt("his_empty")))
		return
	var note: String = _data.get("note", txt("pv_note"))
	content.add_child(Widgets.caption(note, theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "PrefList"
	for item: Dictionary in _items():
		var key: String = item["key"]
		var card := Widgets.card(theme_name())
		var col := Widgets.vbox(Tokens.SPACE_2)
		card.add_child(col)
		if item["kind"] == "segment":
			if not choices.has(key):
				choices[key] = int(item.get("default_index", 0))  # 缺字段降级为 0,不因取键缺失报错
			col.add_child(Widgets.body(item["label"], theme_name()))
			col.add_child(Widgets.segment(item["options"], choices[key], theme_name(), func(idx: int) -> void:
				_save_choice(key,idx)))
		else:
			if not choices.has(key):
				choices[key] = bool(item.get("default", false))
			var row := Widgets.hbox()
			var l := Widgets.body(item["label"], theme_name())
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var t := Widgets.switch(choices[key], theme_name(), func(on: bool) -> void: _save_choice(key,on))
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(t)
			col.add_child(row)
		list.add_child(card)
	content.add_child(list)

## 归一化条目:服务端 items → [{kind,key,label,...}];
## 无数据时把种子 pv_items([[label,"seg",idx,opts] | [label,"toggle",def]]) 拍成同形,key 用 label 兜底。
func _items() -> Array:
	if _data.has("items"):
		return _data["items"]
	return []

func _save_choice(key:String,value:Variant)->void:
	if operations==null:_toast(txt("request_failed"));rebuild();return
	if not await operations.set_privacy(key,value):rebuild();return
	choices[key]=value;rebuild()
