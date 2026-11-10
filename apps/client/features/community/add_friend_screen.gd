class_name AddFriendScreen
extends ScreenBase

## 加好友:ID 搜索(过滤推荐人)+ 我的二维码 + 扫一扫 + 推荐人。

var _query := ""
var _sent: Dictionary = {}
var coordinator: CommunityCoordinator
const QrCode := preload("res://vendor/qrcode/qr_code.gd")
const PlatformBridge := preload("res://platform/platform.gd")

func _init(p_state: Node, p_coordinator: CommunityCoordinator = null) -> void:
	coordinator = p_coordinator
	super(p_state)

func _build() -> void:
	var row := Widgets.hbox(Tokens.SPACE_2)
	var input := LineEdit.new()
	input.name = "SearchEdit"
	input.placeholder_text = txt("af_search_ph")
	input.text = _query
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_changed.connect(func(t: String) -> void:
		_query = t
		rebuild())
	row.add_child(input)
	var scan := Widgets.secondary_button(txt("af_scan"), theme_name())
	scan.name = "ScanButton"
	var can_scan: bool = bool(PlatformBridge.capabilities()["qr_scan"])
	scan.disabled = not can_scan
	scan.tooltip_text = "" if can_scan else txt("af_scan_unavailable")
	scan.pressed.connect(func() -> void:
		var handle := _handle_from_qr(PlatformBridge.scan_qr())
		if handle == "" or coordinator == null: _toast(txt("af_scan_invalid")); return
		scan.disabled = true
		if await coordinator.add_friend(handle): _sent[handle] = true; _toast(txt("fr_added_toast")); rebuild()
		else: scan.disabled = false; _toast(txt("request_failed")))
	row.add_child(scan)
	content.add_child(row)

	# 我的二维码：编码稳定的公开个人主页 URL，可由标准扫码器直接打开。
	var qr_card := Widgets.card(theme_name())
	qr_card.name = "QrCard"
	var qr_col := Widgets.vbox(Tokens.SPACE_2)
	qr_card.add_child(qr_col)
	var profile_handle := str(state.profile.get("name", "@guest"))
	var profile_url := CommunityLinks.profile_url(profile_handle)
	var encoder := QrCode.new()
	encoder.error_correct_level = QrCode.ErrorCorrectionLevel.MEDIUM
	var qr := TextureRect.new()
	qr.name = "QrImage"
	qr.texture = encoder.get_texture(profile_url)
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.custom_minimum_size = Vector2(232, 232)
	qr.tooltip_text = profile_url
	encoder.free()
	qr_col.add_child(qr)
	qr_col.add_child(Widgets.caption(txt("af_qr_note"), theme_name()))
	content.add_child(qr_card)

	var handle := _query.strip_edges()
	if not _valid_handle(handle):
		content.add_child(empty_note(txt_fmt("af_empty_fmt", [_query])))
		return
	content.add_child(Widgets.caption(txt("fr_sug_title"), theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "SugList"
	var card := Widgets.card(theme_name())
	var r := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(r)
	var label := Widgets.body(handle, theme_name())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(label)
	var add := Widgets.secondary_button(txt("fr_added_short") if _sent.has(handle) else txt("fr_add"), theme_name())
	add.name = "AddHandleButton"
	add.disabled = _sent.has(handle)
	add.pressed.connect(func() -> void:
		if coordinator == null or not await coordinator.add_friend(handle): _toast(txt("request_failed")); return
		_sent[handle] = true
		_toast(txt("fr_added_toast"))
		rebuild())
	r.add_child(add)
	list.add_child(card)
	content.add_child(list)

func _handle_from_qr(content: String) -> String:
	content = content.strip_edges()
	if _valid_handle(content): return content
	var handle := CommunityLinks.profile_handle(content)
	return handle if _valid_handle(handle) else ""

func _valid_handle(handle: String) -> bool:
	var pattern := RegEx.new()
	if pattern.compile("^@[A-Za-z0-9_]{1,30}$") != OK: return false
	return pattern.search(handle) != null
