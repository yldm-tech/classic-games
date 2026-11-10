class_name LiveScreen
extends ScreenBase

## 直播间:头图 + 弹幕流(滚动追加)+ 发弹幕 + 送礼/关注。
## 直播关注、用户弹幕与礼物均走真实后端；不生成观众弹幕。

signal closed

var live: Array = []   # [handle, 标题, 观看数, 游戏id]
var danmu: Array = []
var community: CommunityCoordinator
var engagement: EngagementCoordinator

func _init(p_state: Node, p_engagement: EngagementCoordinator = null, p_community: CommunityCoordinator = null) -> void:
	engagement = p_engagement
	community = p_community
	super(p_state)

func set_live(entry: Array) -> void:
	live = entry
	danmu = []
	rebuild()
	if is_inside_tree() and community != null:
		refresh()

func refresh() -> void:
	if community == null or live.size() < 4:
		return
	var game_id := str(live[3])
	if not await community.load_community(game_id):
		return
	var snapshot: Dictionary = community.store.community_by_game.get(game_id, {})
	var posts: Array = snapshot.get("posts", [])
	danmu = []
	for post in posts:
		if not (post is Dictionary):
			continue
		var text := str(post.get("content", ""))
		if text == "":
			continue
		danmu.append(text)
		if danmu.size() >= 6:
			break
	rebuild()

func push_danmu(text: String = "") -> void:
	if text.is_empty(): return
	danmu.append(text)
	if danmu.size() > 6:
		danmu.pop_front()
	rebuild()

func _build() -> void:
	if live.is_empty():
		return
	var i18n := preload("res://i18n/i18n.gd")
	content.add_child(GameCard.cover(Catalog.by_id(live[3]), 140))
	var head := Widgets.hbox(Tokens.SPACE_2)
	head.add_child(Widgets.badge(txt("live_tag"), theme_name()))
	var title := Widgets.body("%s · %s" % [live[0], live[1]], theme_name())
	title.name = "LiveTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Widgets.caption(txt_fmt("watching_fmt", [i18n.format_number(int(live[2]), state.locale)]), theme_name()))
	content.add_child(head)

	var follow := Widgets.secondary_button(txt("follow"), theme_name())
	follow.name = "FollowButton"
	follow.pressed.connect(func() -> void:
		if community == null: _toast(txt("request_failed")); return
		follow.disabled = true
		if await community.set_follow(str(live[0]), true): _toast(txt("live_follow_toast"))
		else: follow.disabled = false; _toast(txt("request_failed")))
	content.add_child(follow)

	var list := Widgets.vbox(Tokens.SPACE_1)
	list.name = "DanmuList"
	for d: String in danmu:
		list.add_child(Widgets.caption(d, theme_name(), &"text_secondary"))
	content.add_child(list)

	var row := Widgets.hbox(Tokens.SPACE_2)
	var input := LineEdit.new()
	input.name = "DanmuEdit"
	input.placeholder_text = txt("live_danmu_ph")
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var send := Widgets.secondary_button(txt("live_send"), theme_name())
	send.name = "SendButton"
	send.pressed.connect(func() -> void:
		var text := input.text.strip_edges()
		if text == "": return
		if community == null: _toast(txt("request_failed")); return
		send.disabled = true
		if await community.create_post(str(live[3]), text): push_danmu(text)
		else: send.disabled = false; _toast(txt("request_failed")))
	row.add_child(send)
	var gift := Widgets.primary_button(txt("live_gift"), theme_name())
	gift.name = "GiftButton"
	gift.pressed.connect(func() -> void:
		if engagement == null: _toast(txt("request_failed")); return
		gift.disabled = true
		if await engagement.send_live_gift(str(live[3])):
			state.points = engagement.store.balance; state.points_changed.emit(state.points)
			_toast(txt("live_gift_toast")); gift.disabled = false
		else: gift.disabled = false; _toast(txt("request_failed")))
	row.add_child(gift)
	content.add_child(row)

	var close := Widgets.secondary_button(txt("rep_close"), theme_name())
	close.name = "CloseButton"
	close.pressed.connect(func() -> void: closed.emit())
	content.add_child(close)
