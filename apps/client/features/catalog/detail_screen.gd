class_name DetailScreen
extends ScreenBase

## 游戏详情:封面 + 标题/作者(可进创作者主页)+ 立即开玩/改一版/喜欢/分享/更多
## + 段控(简介/评论/排行/圈子)+ 创作链。
## 评论、排行与圈子只显示服务端数据；未加载或空结果显示空态。
## 排行只展示服务端认证的回放成绩；未配置权威计分解析器时为空。回放查询使用权威 user_id；圈子:发帖 + 热门讨论。

signal play_requested(game: Dictionary)
signal fork_requested(game: Dictionary)
signal creator_opened(handle: String)
signal share_requested(game: Dictionary)
signal more_requested(game: Dictionary)
signal replay_requested(user_id:String,handle: String, game: Dictionary)

var game: Dictionary = {}
var _tab := 0
var _comments: Array = []        # 服务端评论
var _comments_loaded := false    # 服务端是否已返回过评论(区分「未加载」与「加载后确实为空」)
var _local_comments: Array = []  # 乐观回显:发出的评论先本地显示,服务端刷新后清掉
var _local_posts: Array = []     # 圈子本地新发的帖子
var _server_posts: Array = []
var _rating_count := 0
var _rating_average := 0.0
var _rating := 0                 # 我打的星(0=未评)
var _liked := false
var _favorited := false
var _comment_edit: LineEdit
var _leaderboard:Array=[]
var _lineage: Array = []
var community: Variant
var replay_port: Variant
var catalog: Variant

func _init(p_state: Node, p_community: Variant = null, p_replay_port: Variant = null, p_catalog: Variant = null) -> void:
	community = p_community
	replay_port = p_replay_port
	catalog = p_catalog
	if community != null: community.store.changed.connect(_on_community_changed)
	super(p_state)

func set_game(g: Dictionary) -> void:
	game = g
	_tab = 0
	_comments = []
	_comments_loaded = false
	_local_comments = []
	_local_posts = []
	_server_posts = []
	_rating = 0
	_liked = false
	_favorited = false
	_leaderboard=[]
	_lineage = []
	rebuild()
	if is_inside_tree(): refresh()

func refresh() -> void:
	if game.is_empty(): return
	var game_id := str(game.get("id", ""))
	if community != null:
		await community.load_community(game_id)
		await community.load_comments(game_id)
		await community.load_favorites()
	if catalog != null and catalog.has_method("load_game_lineage") and await catalog.load_game_lineage(game_id):
		if str(game.get("id", "")) == game_id:
			_lineage = catalog.store.game_lineage.duplicate(true)
	if replay_port != null and await replay_port.load_replay_leaderboard(game_id):
		if str(game.get("id", "")) == game_id:
			_leaderboard = replay_port.store.replay_leaderboard_by_game.get(game_id, [])
	rebuild()

func _on_community_changed() -> void:
	var game_id := str(game.get("id", ""))
	if game_id == "": return
	if community.store.comments_by_game.has(game_id): bind_comments(community.store.comments_by_game[game_id])
	if community.store.community_by_game.has(game_id):
		var snapshot: Dictionary = community.store.community_by_game[game_id]
		_rating = int(snapshot.get("my_rating", 0)); _rating_count = int(snapshot.get("count", 0)); _rating_average = float(snapshot.get("average", 0.0))
		_server_posts = snapshot.get("posts", []).duplicate(true)
	_liked = bool(community.store.liked_by_game.get(game_id, false))
	_favorited = community.is_favorite(game_id) if community.has_method("is_favorite") else game_id in community.store.favorite_ids
	rebuild.call_deferred()

## 服务端评论列表注入:[{author_id, content, ...}]。服务端为准,清掉乐观回显。
func bind_comments(items: Array) -> void:
	_comments = items
	_comments_loaded = true
	_local_comments = []
	if _tab == 1:
		rebuild()

func _build() -> void:
	if game.is_empty():
		return
	_build_header()
	var tabs: Array = (txt("detail_tabs") as Array).duplicate()
	tabs.append(txt("cir_tab"))
	var seg := Widgets.segment(tabs, _tab, theme_name(), func(i: int) -> void:
		_tab = i
		rebuild())
	seg.name = "DetailSeg"
	content.add_child(seg)
	match _tab:
		0: _build_about()
		1: _build_comments()
		2: _build_scores()
		3: _build_circle()

func _build_header() -> void:
	# 详情封面是定高 banner(对照原型:桌面 240 / 手机 290);card_cols<=2 视为手机
	content.add_child(GameCard.cover(game, 290.0 if card_cols <= 2 else 240.0))
	var title_row := Widgets.hbox(Tokens.SPACE_2)
	var title := Widgets.heading(GameCard.title_of(game, state.locale), 1, theme_name())
	title.name = "DetailTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if game.get("badge", "") == "ai" or game.get("ai_generated", false):
		title_row.add_child(Widgets.badge(txt("forged_badge"), theme_name(), true))
	var more := Widgets.secondary_button("⋯", theme_name())
	more.name = "MoreButton"
	more.custom_minimum_size = Vector2(Tokens.HIT_MIN, 36)
	more.pressed.connect(func() -> void: more_requested.emit(game))
	title_row.add_child(more)
	content.add_child(title_row)

	var by: String = game.get("by", game.get("author_id", ""))
	if by != "":
		var by_row := Widgets.hbox(Tokens.SPACE_2)
		var by_lbl := Widgets.caption("%s ›" % txt_fmt("by_fmt", [by]), theme_name(), &"text_secondary")
		by_lbl.name = "ByLabel"
		by_row.add_child(by_lbl)
		var stats := GameCard.stats_line(game, state.locale)
		if stats != "":
			by_row.add_child(Widgets.caption("· " + stats, theme_name()))
		var handle := by
		by_row.mouse_filter = Control.MOUSE_FILTER_STOP
		by_row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				creator_opened.emit(handle))
		content.add_child(by_row)

	var actions := Widgets.hbox(Tokens.SPACE_2)
	var play := Widgets.primary_button(txt("play_now"), theme_name())
	play.name = "PlayButton"
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(func() -> void: play_requested.emit(game))
	actions.add_child(play)
	if GameCard.forkable(game):
		var fork := Widgets.secondary_button(txt("fork"), theme_name())
		fork.name = "ForkButton"
		fork.pressed.connect(func() -> void: fork_requested.emit(game))
		actions.add_child(fork)
	# 点赞:本地即时反馈(着色 + 计数),与后端幂等切换语义一致
	var like := Widgets.secondary_button("♥ %s" % preload("res://i18n/i18n.gd").format_number(
		int(game.get("likes", 0)) + (1 if _liked else 0), state.locale), theme_name())
	like.name = "LikeButton"
	like.disabled = community != null and bool(community.store.like_pending_by_game.get(str(game.get("id", "")), false))
	like.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
	if _liked:
		like.add_theme_color_override("font_color", Tokens.color(&"accent_primary", theme_name()))
	like.pressed.connect(func() -> void:
		if community == null:
			_toast(txt("request_failed"))
			return
		var next_liked := not _liked
		if next_liked:
			_toast(txt("toast_liked"))
		await community.set_like(str(game.get("id", "")), next_liked))
	actions.add_child(like)
	var favorite := Widgets.secondary_button("★" if _favorited else "☆", theme_name())
	favorite.name = "FavoriteButton"
	favorite.disabled = community != null and bool(community.store.favorite_pending_by_game.get(str(game.get("id", "")), false))
	favorite.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
	if _favorited:
		favorite.add_theme_color_override("font_color", Tokens.color(&"status_warning", theme_name()))
	favorite.pressed.connect(func() -> void:
		if community == null:
			_toast(txt("request_failed"))
			return
		var next_favorite := not _favorited
		_toast(txt("toast_favorited") if next_favorite else txt("toast_unfavorited"))
		await community.set_favorite(str(game.get("id", "")), next_favorite))
	actions.add_child(favorite)
	var share := Widgets.secondary_button("⇪", theme_name())
	share.name = "ShareButton"
	share.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
	share.pressed.connect(func() -> void: share_requested.emit(game))
	actions.add_child(share)
	content.add_child(actions)

func _build_about() -> void:
	var desc := Widgets.body(GameCard.desc_of(game, state.locale), theme_name(), &"text_secondary")
	desc.name = "DetailDesc"
	content.add_child(desc)
	# 创作链(Fork 谱系,核心卖点;原型 lineage 区块)
	var card := Widgets.card(theme_name())
	card.name = "LineageCard"
	var col := Widgets.vbox(Tokens.SPACE_2)
	card.add_child(col)
	col.add_child(Widgets.caption(txt("lineage"), theme_name()))
	if _lineage.is_empty():
		col.add_child(empty_note(txt("lineage_empty")))
	else:
		var labels: PackedStringArray = PackedStringArray()
		for item: Variant in _lineage:
			if item is Dictionary:
				var label := str(item.get("title", item.get("id", "")))
				if label != "":
					labels.append(label)
			elif str(item) != "":
				labels.append(str(item))
		var chain_lbl := Widgets.body(" → ".join(labels), theme_name())
		chain_lbl.name = "LineageChain"
		col.add_child(chain_lbl)
	var i18n := preload("res://i18n/i18n.gd")
	col.add_child(Widgets.caption(txt_fmt("lineage_meta", [
		i18n.format_number(int(game.get("forks", 0)), state.locale),
		GameCard.title_of(game, state.locale),
	]), theme_name()))
	content.add_child(card)
	_build_rating()

## 评分卡:5 星可点,服务端确认后星着色并反馈。
func _build_rating() -> void:
	var card := Widgets.card(theme_name())
	card.name = "RateCard"
	var col := Widgets.vbox(Tokens.SPACE_2)
	card.add_child(col)
	var head := Widgets.hbox(Tokens.SPACE_2)
	head.add_child(Widgets.caption(txt("rate_title"), theme_name()))
	head.add_child(Widgets.spacer())
	var i18n := preload("res://i18n/i18n.gd")
	head.add_child(Widgets.caption("%.1f · %s" % [_rating_average, txt_fmt("rate_count_fmt", [i18n.format_number(_rating_count, state.locale)])], theme_name()))
	col.add_child(head)
	var stars := Widgets.hbox(Tokens.SPACE_1)
	stars.name = "StarRow"
	for i in 5:
		var b := Button.new()
		b.text = "★"
		b.flat = true
		b.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
		b.add_theme_font_size_override("font_size", Tokens.FONT_H2)
		b.add_theme_color_override("font_color",
			Tokens.color(&"status_warning" if i < _rating else &"text_muted", theme_name()))
		var n := i + 1
		b.pressed.connect(func() -> void:
			if community == null: _toast(txt("request_failed")); return
			b.disabled = true
			if await community.rate_game(str(game.get("id", "")), n):
				_toast(txt_fmt("rate_done_fmt", [n]))
			else: b.disabled = false; _toast(txt("request_failed")))
		stars.add_child(b)
	col.add_child(stars)
	content.add_child(card)

func _build_comments() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "CommentList"
	if not _comments.is_empty():
		for c: Dictionary in _comments:
			list.add_child(_comment_card(c.get("author_id", ""), "", c.get("content", ""), -1))
	else:
		# 未加载或服务端确认无评论:明确空态,不回落到种子评论。
		list.add_child(empty_note(txt("comments_empty")))
	for c: Dictionary in _local_comments:
		list.add_child(_comment_card(c["author_id"], "", c["content"], -1))
	content.add_child(list)
	var row := Widgets.hbox(Tokens.SPACE_2)
	_comment_edit = LineEdit.new()
	_comment_edit.name = "CommentEdit"
	_comment_edit.placeholder_text = txt("comment_ph")
	_comment_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_comment_edit)
	_comment_edit.text_submitted.connect(func(_t: String) -> void: _send_comment())
	var send := Widgets.primary_button(txt("comment_send"), theme_name())
	send.name = "CommentSend"
	send.pressed.connect(_send_comment)
	row.add_child(send)
	content.add_child(row)

func _send_comment() -> void:
	var text := _comment_edit.text.strip_edges()
	if text == "":
		return
	if community == null:
		_toast(txt("request_failed"))
		return
	if not await community.post_comment(str(game.get("id", "")), text): _toast(txt("request_failed"))

func _comment_card(author: String, when: String, text: String, likes: int) -> Control:
	var card := Widgets.card(theme_name())
	var col := Widgets.vbox(Tokens.SPACE_1)
	card.add_child(col)
	var head := Widgets.hbox(Tokens.SPACE_2)
	head.add_child(Widgets.avatar(str(author), theme_name(), 28))
	head.add_child(Widgets.caption(author, theme_name()))
	head.add_child(Widgets.spacer())
	if when != "":
		head.add_child(Widgets.caption(when, theme_name()))
	col.add_child(head)
	col.add_child(Widgets.body(text, theme_name()))
	if likes >= 0:
		col.add_child(Widgets.caption("♥ %d" % likes, theme_name()))
	return card

## 排行段:好友周榜(YOU 高亮),前三可看回放。
func _build_scores() -> void:
	var head := Widgets.hbox(Tokens.SPACE_2)
	head.add_child(Widgets.caption(txt("week_tag"), theme_name()))
	content.add_child(head)
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "ScoreList"
	var rows: Array = _leaderboard
	if rows.is_empty():
		list.add_child(empty_note(txt("scores_empty")))
	var i18n := preload("res://i18n/i18n.gd")
	for i in rows.size():
		var r: Dictionary = rows[i]
		var display_name:=str(r.get("nickname",r.get("user_id","")))
		var user_id:=str(r.get("user_id",""))
		var my_id := str(state.profile.get("id", ""))
		var is_me: bool = user_id != "" and user_id == my_id
		var card := Widgets.card(theme_name(), &"tint_ember" if is_me else &"surface_card")
		var row := Widgets.hbox(Tokens.SPACE_3)
		card.add_child(row)
		var rank := Widgets.big_number(str(i + 1), theme_name(), Tokens.FONT_H4)
		rank.custom_minimum_size = Vector2(22, 0)
		row.add_child(rank)
		var name_lbl := Widgets.body(txt("you_tag") if is_me else display_name, theme_name())
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		row.add_child(Widgets.caption(i18n.format_number(int(r.get("score",0)), state.locale), theme_name()))
		if i < 3 and not is_me and user_id!="":
			var rep := Widgets.secondary_button(txt("rep_watch"), theme_name())
			rep.name="ReplayButton%d"%i
			var handle: String = display_name
			rep.pressed.connect(func() -> void: replay_requested.emit(user_id,handle, game))
			row.add_child(rep)
		list.add_child(card)
	content.add_child(list)

## 圈子段:发帖 + 热门讨论。
func _build_circle() -> void:
	var row := Widgets.hbox(Tokens.SPACE_2)
	var input := LineEdit.new()
	input.name = "PostEdit"
	input.placeholder_text = txt("cir_ph")
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var post := Widgets.primary_button(txt("cir_post"), theme_name())
	post.name = "PostButton"
	post.pressed.connect(func() -> void:
		var text := input.text.strip_edges()
		if text == "": return
		if community == null: _toast(txt("request_failed")); return
		post.disabled = true
		if await community.create_post(str(game.get("id", "")), text): pass
		else: post.disabled = false; _toast(txt("request_failed")))
	row.add_child(post)
	content.add_child(row)

	content.add_child(Widgets.caption(txt("cir_hot"), theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "PostList"
	for p: Dictionary in _server_posts:
		list.add_child(_comment_card(str(p.get("author_id", "")), "", str(p.get("content", "")), -1))
	if _server_posts.is_empty():
		list.add_child(empty_note(txt("circle_empty")))
	content.add_child(list)
