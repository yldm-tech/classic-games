class_name RoomScreen
extends ScreenBase

## 组队房间:4 槽位、房间码、准备状态、全员就绪才能开始。
## 成员、准备与开局状态全部由服务端权威维护。

signal start_requested(room: Dictionary)

var ready_me := false
var room: Dictionary = {}
var _poll_elapsed := 0.0
var _polling := false
var _start_emitted := false
var engagement: EngagementCoordinator

func _init(p_state: Node, p_engagement: EngagementCoordinator = null) -> void:
	engagement = p_engagement
	super(p_state)

func refresh() -> void:
	if engagement == null: return
	var accepted := await engagement.create_room() if room.is_empty() else await engagement.open_room(str(room.get("id", "")))
	if accepted: _accept_room(engagement.store.room)

func _process(delta: float) -> void:
	if engagement == null or room.is_empty() or _polling or not is_visible_in_tree():
		return
	if str(room.get("status", "waiting")) != "waiting":
		return
	_poll_elapsed += delta
	if _poll_elapsed >= 1.0:
		_poll_elapsed = 0.0
		_poll_room()

func _poll_room() -> void:
	_polling = true
	var accepted := await engagement.poll_room()
	_polling = false
	if accepted: _accept_room(engagement.store.room)

func _user_id() -> String:
	return str(state.profile.get("id", ""))

func _accept_room(value: Dictionary) -> void:
	room = value
	ready_me = false
	for member: Dictionary in room.get("members", []):
		if str(member.get("user_id", "")) == _user_id():
			ready_me = bool(member.get("ready", false))
			break
	if str(room.get("status", "")) == "started" and not _start_emitted:
		_start_emitted = true
		start_requested.emit(room)
	else:
		rebuild()

func _build() -> void:
	var join_row := Widgets.hbox(Tokens.SPACE_2)
	var join_code := LineEdit.new()
	join_code.name = "JoinCodeEdit"
	join_code.placeholder_text = txt("room_join_placeholder")
	join_code.max_length = 6
	join_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(join_code)
	var join_button := Widgets.secondary_button(txt("room_join"), theme_name())
	join_button.name = "JoinRoomButton"
	join_button.pressed.connect(func() -> void:
		var code := join_code.text.strip_edges()
		if engagement == null or code == "": _toast(txt("request_failed")); return
		join_button.disabled = true
		if await engagement.join_room(code): _start_emitted = false; _accept_room(engagement.store.room)
		else: join_button.disabled = false; _toast(txt("request_failed")))
	join_row.add_child(join_button)
	content.add_child(join_row)

	var head := Widgets.hbox()
	head.add_child(Widgets.caption("%s  %s" % [txt("room_code_label"), str(room.get("code", "—"))], theme_name()))
	head.add_child(Widgets.spacer())
	var invite := Widgets.secondary_button(txt("room_invite"), theme_name())
	invite.name = "InviteButton"
	invite.pressed.connect(func() -> void:
		var code := str(room.get("code", "")); if code == "": return
		DisplayServer.clipboard_set(code); _toast(txt("room_invite_toast")))
	head.add_child(invite)
	content.add_child(head)

	var grid := GridContainer.new()
	grid.name = "SlotGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_3)
	var slots: Array = []
	for member: Dictionary in room.get("members", []):
		slots.append([member.get("user_id", ""), txt("room_host") if member.get("user_id") == room.get("host_id") else txt("room_ready_tag") if member.get("ready", false) else "", member.get("ready", false)])
	while slots.size() < 4: slots.append(["", txt("room_empty"), false])
	for s: Array in slots:
		var card := Widgets.card(theme_name(), &"tint_ember" if s[2] and s[0] != "" else &"surface_card")
		var col := Widgets.vbox(Tokens.SPACE_1)
		card.add_child(col)
		col.add_child(Widgets.body(s[0] if s[0] != "" else "—", theme_name()))
		col.add_child(Widgets.caption(s[1], theme_name()))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
	content.add_child(grid)

	var ready_btn := Widgets.secondary_button(txt("room_cancel_ready") if ready_me else txt("room_ready"), theme_name())
	ready_btn.name = "ReadyButton"
	ready_btn.disabled = room.is_empty() or str(room.get("status", "waiting")) != "waiting"
	ready_btn.pressed.connect(func() -> void:
		if engagement == null or room.is_empty(): _toast(txt("request_failed")); return
		ready_btn.disabled = true
		if await engagement.set_room_ready(not ready_me): _accept_room(engagement.store.room)
		else: ready_btn.disabled = false; _toast(txt("request_failed")))
	content.add_child(ready_btn)

	var all_ready: bool = not (room.get("members", []) as Array).is_empty()
	for member: Dictionary in room.get("members", []): all_ready = all_ready and bool(member.get("ready", false))
	var start := Widgets.primary_button(txt("room_start"), theme_name())
	start.name = "StartButton"
	start.disabled = not all_ready or _user_id() == "" or _user_id() != str(room.get("host_id", ""))
	start.pressed.connect(func() -> void:
		if engagement == null: return
		start.disabled = true
		if await engagement.start_room(): _accept_room(engagement.store.room)
		else: start.disabled = false; _toast(txt("request_failed")))
	content.add_child(start)
	if not all_ready:
		content.add_child(Widgets.caption(txt("room_need"), theme_name()))
