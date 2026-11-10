class_name ChatScreen
extends ScreenBase

## 私聊:气泡对话、发消息、「一起玩」入口；消息只展示服务端持久化内容。

signal room_requested

var conversation: Dictionary = {}
var bubbles: Array = []  # [文本, 是否自己发的]
var coordinator: CommunityCoordinator

func _init(p_state: Node, p_coordinator: CommunityCoordinator = null) -> void:
	coordinator = p_coordinator
	if coordinator != null: coordinator.store.changed.connect(_on_store_changed)
	super(p_state)

func set_conversation(value: Dictionary) -> void:
	conversation = value.duplicate(true)
	bubbles = []
	rebuild()
	if coordinator != null and not _handle().is_empty(): coordinator.open_conversation(_handle())

func _handle() -> String:
	return str(conversation.get("handle", ""))

## Load the active conversation from the server; empty until messages arrive.
func refresh() -> void:
	if coordinator != null: await coordinator.open_conversation(_handle())

## 拉 friend_idx 对应的消息,成功则用 {text,mine} 重建气泡列表。
func _fetch_messages() -> void:
	if coordinator != null: await coordinator.open_conversation(_handle())

func _on_store_changed() -> void:
	if coordinator.store.active_handle != _handle() or not coordinator.store.messages_by_handle.has(_handle()): return
	var fetched: Array = []
	for item: Dictionary in coordinator.store.messages_by_handle[_handle()]:
		fetched.append([str(item.get("text", "")), bool(item.get("mine", false))])
	bubbles = fetched
	rebuild.call_deferred()

func _build() -> void:
	var head := Widgets.hbox(Tokens.SPACE_2)
	head.add_child(Widgets.avatar(_handle(), theme_name(), 36))
	var name_lbl := Widgets.heading(_handle(), 3, theme_name())
	name_lbl.name = "FriendName"
	head.add_child(name_lbl)
	if bool(conversation.get("online", false)):
		head.add_child(Widgets.badge(txt("online"), theme_name()))
	head.add_child(Widgets.spacer())
	var room := Widgets.secondary_button(txt("play_together"), theme_name())
	room.name = "RoomButton"
	room.pressed.connect(func() -> void: room_requested.emit())
	head.add_child(room)
	content.add_child(head)

	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "BubbleList"
	if bubbles.is_empty():
		list.add_child(empty_note(txt("chats_empty")))
	for b: Array in bubbles:
		var card := Widgets.card(theme_name(), &"tint_ember" if b[1] else &"surface_card")
		var l := Widgets.body(b[0], theme_name())
		l.autowrap_mode = TextServer.AUTOWRAP_OFF  # 气泡按文字宽度收紧;否则 shrink 容器把它挤成竖排
		card.add_child(l)
		card.size_flags_horizontal = Control.SIZE_SHRINK_END if b[1] else Control.SIZE_SHRINK_BEGIN
		list.add_child(card)
	content.add_child(list)

	var row := Widgets.hbox(Tokens.SPACE_2)
	var input := LineEdit.new()
	input.name = "MsgEdit"
	input.placeholder_text = txt("chat_ph")
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var send := Widgets.primary_button(txt("comment_send"), theme_name())
	send.name = "SendButton"
	send.disabled = coordinator != null and bool(coordinator.store.send_pending_by_handle.get(_handle(), false))
	send.pressed.connect(func() -> void:
		var text := input.text.strip_edges()
		if text == "":
			return
		if coordinator == null or not await coordinator.send_message(_handle(), text): _toast(txt("request_failed")))
	row.add_child(send)
	content.add_child(row)
