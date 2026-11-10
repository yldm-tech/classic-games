class_name ProfileScreen
extends ScreenBase

## 我的 = 「我的东西在哪?」(docs/16):身份卡 → 数据 → 等级 → 作品段控 → 分组目录。
## 本增量目录只放有真实落点的行(设置);创作中心/福利等子页落地后再加行,不放死控件。

signal game_opened(game: Dictionary)
signal settings_requested
signal edit_requested
signal follow_requested(tab: int)
signal points_requested
signal entry_selected(key: String)  # studio/earnings/membership/avatar/welfare/achievements/shop/downloads/history

var _seg := 0
var catalog: CatalogCoordinator

var _segment_games: Array = [[], [], []]

## 服务端 /users/:id/profile 的数值(plays/forks/follows/level/points/works/joined)；
## 无服务端数据时数值为 0 / 空态，不回退演示账号。
var _server: Dictionary = {}

func _init(p_state: Node, p_catalog: CatalogCoordinator = null) -> void:
	catalog = p_catalog
	super(p_state)

## 首次展示时按当前登录 user id 拉资料。
func refresh() -> void:
	if catalog == null:
		return
	var user_key := str(state.profile.get("id", state.profile.get("name", "")))
	if user_key.is_empty(): return
	if not await catalog.load_profile(user_key, state.locale):
		return
	_server = catalog.store.profile.duplicate(true)
	for i in 3:
		var kind: String = ["works", "forks", "liked"][i]
		if await catalog.load_user_games(user_key, kind, state.locale):
			_segment_games[i] = catalog.store.profile_games.duplicate(true)
	rebuild()

func _build() -> void:
	_build_identity()
	_build_stats()
	_build_level()
	_build_works()
	_build_directory()

func _build_identity() -> void:
	var card := Widgets.card(theme_name())
	card.name = "IdentityCard"
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	row.add_child(Widgets.avatar(str(state.profile["name"]), theme_name(), 56))
	var col := Widgets.vbox(Tokens.SPACE_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Widgets.heading(state.profile["name"], 2, theme_name())
	name_lbl.name = "ProfileName"
	col.add_child(name_lbl)
	var server_bio: String = _server.get("bio", "")
	var local_bio: String = str(state.profile.get("bio", ""))
	var bio: String = server_bio if server_bio != "" else local_bio
	if bio == "":
		bio = txt("default_bio")
	col.add_child(Widgets.caption(bio, theme_name()))
	var joined := int(_server.get("joined", 0))
	var works := int(_server.get("works", 0))
	var meta: String = txt("profile_meta_empty") if joined <= 0 else txt_fmt("profile_meta_fmt", [joined, works])
	col.add_child(Widgets.caption(meta, theme_name()))
	row.add_child(col)
	# 整卡可点进编辑资料,右侧只留轻提示(原型设计评审结论:不放突兀小按钮)
	var hint := Widgets.caption("%s ›" % txt("edit_profile"), theme_name())
	hint.name = "EditHint"
	row.add_child(hint)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			edit_requested.emit())
	content.add_child(card)

func _build_stats() -> void:
	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	var i18n := preload("res://i18n/i18n.gd")
	var stats: Array = txt("profile_stats")
	# 标签来自 i18n;数值有服务端则用 plays/forks/follows 覆盖种子。
	var values: Array = [int(_server.get("plays", 0)), int(_server.get("forks", 0)), int(_server.get("follows", 0))]
	for i in stats.size():
		var stat: Array = stats[i]
		var card := Widgets.kpi_card(i18n.format_number(values[i], state.locale), String(stat[1]) + (" ›" if i == 2 else ""), theme_name())
		if i == 2:  # 「关注」格可点进关注/粉丝列表
			card.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					follow_requested.emit(0))
		grid.add_child(card)
	content.add_child(grid)

func _build_level() -> void:
	var card := Widgets.card(theme_name(), &"surface_raised")
	card.name = "LevelCard"
	var col := Widgets.vbox(Tokens.SPACE_2)
	card.add_child(col)
	var row := Widgets.hbox()
	# 等级标签:有服务端则套本地化模板带入 level,否则用种子整句。
	var lvl_text: String = txt_fmt("creator_lv_fmt", [int(_server.get("level", 0))])
	var lvl := Widgets.body(lvl_text, theme_name())
	lvl.autowrap_mode = TextServer.AUTOWRAP_OFF  # 行内短标题不换行(否则在 HBox 里被挤成一列竖排)
	row.add_child(lvl)
	row.add_child(Widgets.spacer())
	var pts: int = int(_server.get("points", state.points)) if not _server.is_empty() else state.points
	row.add_child(Widgets.caption("%d %s ›" % [pts, txt("points_label")], theme_name()))
	col.add_child(row)
	var bar := ProgressBar.new()
	bar.max_value = 1000
	bar.value = pts % 1000
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	col.add_child(bar)
	col.add_child(Widgets.caption(txt_fmt("to_next_fmt", [1000 - (pts % 1000)]), theme_name()))
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			points_requested.emit())
	content.add_child(card)

func _build_works() -> void:
	var seg := Widgets.segment(txt("segs"), _seg, theme_name(), func(i: int) -> void:
		_seg = i
		rebuild())
	seg.name = "WorksSeg"
	content.add_child(seg)
	var grid := GridContainer.new()
	grid.name = "WorksGrid"
	grid.columns = card_cols
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_3)
	for game: Dictionary in _segment_games[_seg]:
		grid.add_child(GameCard.build(game, state.locale, theme_name(), func(g: Dictionary) -> void: game_opened.emit(g)))
	if _segment_games[_seg].is_empty():
		grid.add_child(empty_note(txt("works_empty")))
	content.add_child(grid)

## 目录三分组:创作 / 福利 / 更多(docs/16「整理杂物间」后的信息架构)。
func _build_directory() -> void:
	var groups := [
		[txt("grp_create"), [["studio", txt("ql_studio")], ["earnings", txt("ql_earnings")]]],
		[txt("grp_welfare"), [["membership", txt("mem_title")], ["avatar", txt("av_title")],
			["welfare", txt("welfare_title")], ["achievements", txt("ach_page_title")], ["shop", txt("ql_shop")]]],
		[txt("grp_more"), [["downloads", txt("ql_downloads")], ["history", txt("ql_history")]]],
	]
	for group: Array in groups:
		content.add_child(Widgets.caption(group[0], theme_name()))
		var box := Widgets.vbox(Tokens.SPACE_2)
		for entry: Array in group[1]:
			var key: String = entry[0]
			var row := nav_row(entry[1], "", func() -> void: entry_selected.emit(key))
			row.name = "Entry_%s" % key
			box.add_child(row)
		content.add_child(box)
	var settings_row := nav_row(txt("set_title"), "", func() -> void: settings_requested.emit())
	settings_row.name = "SettingsRow"
	content.add_child(settings_row)
