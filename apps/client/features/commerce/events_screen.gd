class_name EventsScreen
extends ScreenBase

## 活动中心:限时活动卡 + 报名。

var joined: Dictionary = {}
## /events 注入的活动列表(为空则回退 i18n 种子)。
var _data: Dictionary = {}
var commerce:CommerceCoordinator
func _init(p_state:Node,p_commerce:CommerceCoordinator=null)->void:commerce=p_commerce;super(p_state)

## 首次展示拉限时活动列表。
func refresh() -> void:
	if commerce!=null and await commerce.load_events(state.locale):
		_data={"items":commerce.store.events}
		joined.clear()
		for id in commerce.store.joined_event_ids: joined[str(id)] = true
	rebuild()

## 活动归一为 [{title,desc,ends_in,tone}](后端 items 对象 或 种子 [title,desc,ends_in,tone])。
func _events() -> Array:
	if not _data.is_empty() and _data.get("items") is Array:
		var out: Array = []
		for e: Dictionary in _data["items"]:
			out.append({"id": str(e.get("id", "")), "title": str(e.get("title", "")), "desc": str(e.get("desc", "")),
				"ends_in": str(e.get("ends_in", "")), "tone": str(e.get("tone", ""))})
		return out
	return []

func _build() -> void:
	var list := Widgets.vbox(Tokens.SPACE_3)
	list.name = "EventList"
	var items: Array = _events()
	if items.is_empty():
		list.add_child(empty_note(txt("his_empty")))
	for i in items.size():
		var e: Dictionary = items[i]
		var card := Widgets.card(theme_name())
		var col := Widgets.vbox(Tokens.SPACE_2)
		card.add_child(col)
		var head := Widgets.hbox(Tokens.SPACE_2)
		head.add_child(Widgets.badge(txt("ev_banner_tag"), theme_name()))
		head.add_child(Widgets.spacer())
		head.add_child(Widgets.caption(txt_fmt("ev_ends_fmt", [e["ends_in"]]), theme_name()))
		col.add_child(head)
		col.add_child(Widgets.heading(e["title"], 3, theme_name()))
		col.add_child(Widgets.caption(e["desc"], theme_name(), &"text_secondary"))
		var idx := i
		var event_id := str(e.get("id", ""))
		var btn := Widgets.secondary_button(txt("ev_joined"), theme_name()) if joined.has(event_id) \
			else Widgets.primary_button(txt("ev_join"), theme_name())
		btn.disabled = joined.has(event_id)
		btn.pressed.connect(func() -> void:
			if commerce == null or event_id == "": _toast(txt("request_failed")); return
			btn.disabled = true
			if await commerce.join_event(event_id): joined[event_id] = true; _toast(txt("ev_joined_toast")); rebuild()
			else: btn.disabled = false; _toast(txt("request_failed")))
		col.add_child(btn)
		list.add_child(card)
	content.add_child(list)
