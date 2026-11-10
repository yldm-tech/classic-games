class_name MessagesScreen
extends ScreenBase

const AsyncContentScript:=preload("res://ui/patterns/async_content.gd")

## 消息 = 「谁找我?」(docs/16):通知 / 私信 / 好友 三段合一。
## 通知、私信和好友以 inbox API 为权威，不用本地种子伪造用户内容。

signal chat_opened(conversation: Dictionary)
signal add_friend_requested

var seg := 0
var accepted: Dictionary = {}
var added: Dictionary = {}
## 服务端 /activity 注入的通知。每项 {index,icon,title,body,time}。
var _activity: Array = []
var _chats: Array = []
var coordinator: CommunityCoordinator
var _inbox_revision := 0
var _async_state:="ready"
var _refresh_generation:=0

func _init(p_state: Node, p_coordinator: CommunityCoordinator = null) -> void:
	coordinator = p_coordinator
	if coordinator != null: coordinator.store.changed.connect(_on_store_changed)
	super(p_state)

## 首次展示时拉通知和真实好友会话；拿不到保持空态。
func refresh() -> void:
	if coordinator==null:return
	_refresh_generation+=1;var generation:=_refresh_generation
	_async_state="loading";rebuild()
	var success:=await coordinator.load_inbox(state.locale)
	if generation!=_refresh_generation:return
	if success:
		await coordinator.load_suggestions(state.locale)
		if generation!=_refresh_generation:return
		_async_state="ready"
	else:_async_state="offline" if coordinator.store.status=="offline" else "error"
	rebuild()

func _on_store_changed() -> void:
	if coordinator.store.inbox_revision == _inbox_revision: return
	_inbox_revision = coordinator.store.inbox_revision
	_activity = coordinator.store.activity.duplicate(true)
	_chats = coordinator.store.conversations.duplicate(true)
	state.set_activity_total(_activity.size())
	rebuild.call_deferred()

func _build() -> void:
	if _async_state!="ready":
		var async_view=AsyncContentScript.new();async_view.present(_async_state,"",theme_name(),txt("off_retry"));async_view.retry_requested.connect(refresh);content.add_child(async_view);return
	var seg_ctrl := Widgets.segment(txt("msg_segs"), seg, theme_name(), func(i: int) -> void:
		seg = i
		rebuild())
	seg_ctrl.name = "MsgSeg"
	content.add_child(seg_ctrl)
	match seg:
		0: _build_alerts()
		1: _build_chats()
		2: _build_friends()

func _build_alerts() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "ActivityList"
	if not _activity.is_empty():
		for i in _activity.size():
			var it: Dictionary = _activity[i]
			# index 用于已读追踪;后端给则用,缺则回退行序。
			var idx: int = int(it.get("index", i))
			list.add_child(_activity_row(idx, str(it.get("title", "")), str(it.get("body", "")), str(it.get("time", ""))))
	else:
		list.add_child(empty_note(txt("his_empty")))
	content.add_child(list)

func _activity_row(index: int, title: String, body_text: String, time: String) -> Control:
	var is_read: bool = state.is_read(index)
	var card := Widgets.card(theme_name(), &"surface_card" if not is_read else &"bg_app")
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	var col := Widgets.vbox(Tokens.SPACE_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Widgets.body(title, theme_name(), &"text_primary" if not is_read else &"text_secondary"))
	col.add_child(Widgets.caption(body_text, theme_name()))
	row.add_child(col)
	row.add_child(Widgets.caption(time, theme_name()))
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			state.mark_read(index)
			rebuild())
	return card

func _build_chats() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "ChatList"
	for conversation: Dictionary in _chats:
		var card := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		card.add_child(row)
		row.add_child(Widgets.avatar(str(conversation.get("handle", "")), theme_name(), 40))
		var col := Widgets.vbox(Tokens.SPACE_1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := Widgets.hbox(Tokens.SPACE_2)
		head.add_child(Widgets.body(str(conversation.get("handle", "")), theme_name()))
		if bool(conversation.get("online", false)):
			head.add_child(Widgets.badge(txt("online"), theme_name()))
		col.add_child(head)
		var last := Widgets.caption(str(conversation.get("last_message", "")), theme_name())
		last.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(last)
		row.add_child(col)
		var meta := Widgets.vbox(Tokens.SPACE_1)
		meta.add_child(Widgets.caption(str(conversation.get("time", "")), theme_name()))
		if int(conversation.get("unread", 0)) > 0:
			var dot := Widgets.badge(str(conversation.get("unread", 0)), theme_name())
			meta.add_child(dot)
		row.add_child(meta)
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				chat_opened.emit(conversation))
		list.add_child(card)
	if _chats.is_empty():
		list.add_child(empty_note(txt("chats_empty")))
	content.add_child(list)

func _build_friends() -> void:
	var head := Widgets.hbox()
	head.add_child(Widgets.spacer())
	var add := Widgets.secondary_button(txt("af_title"), theme_name())
	add.name = "AddFriendButton"
	add.pressed.connect(func() -> void: add_friend_requested.emit())
	head.add_child(add)
	content.add_child(head)

	content.add_child(Widgets.caption(txt("fr_req_title"), theme_name()))
	var reqs := Widgets.vbox(Tokens.SPACE_2)
	reqs.name = "RequestList"
	reqs.add_child(_friend_empty())
	content.add_child(reqs)

	content.add_child(Widgets.caption(txt("fr_sug_title"), theme_name()))
	var sugs := Widgets.vbox(Tokens.SPACE_2)
	sugs.name = "SugList"
	var suggestions: Array = coordinator.store.suggestions if coordinator != null else []
	for person: Dictionary in suggestions:
		sugs.add_child(_suggestion_row(str(person.get("handle", ""))))
	if suggestions.is_empty():
		sugs.add_child(empty_note(txt("suggestions_empty")))
	content.add_child(sugs)

func _friend_empty() -> Control:
	return empty_note(txt("friends_empty"))

func _suggestion_row(handle: String) -> Control:
	var card := Widgets.card(theme_name())
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	row.add_child(Widgets.avatar(handle, theme_name(), 36))
	var label := Widgets.body(handle, theme_name())
	label.name = "SugHandle"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var add := Widgets.secondary_button(txt("fr_added_short") if added.has(handle) else txt("fr_add"), theme_name())
	add.disabled = added.has(handle) or coordinator == null
	add.pressed.connect(func() -> void:
		if coordinator == null or not await coordinator.add_friend(handle):
			_toast(txt("request_failed")); return
		added[handle] = true
		_toast(txt("fr_added_toast"))
		rebuild())
	row.add_child(add)
	return card
