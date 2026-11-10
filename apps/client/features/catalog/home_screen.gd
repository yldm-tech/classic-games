class_name HomeScreen
extends ScreenBase

## 首页 = 个人化,「今天玩什么?」(docs/16 信息架构):
## 本周精选 hero → 继续玩(带进度)→ 热门二创(4 个,入口指向发现)。

signal game_opened(game: Dictionary)
signal play_requested(game: Dictionary)
signal explore_requested
signal events_requested
signal trending_loaded(items: Array)

var catalog: CatalogCoordinator

## 首载骨架屏(原型 HomeSkeleton):AppRoot 在 _ready 触发,0.7s 后换内容。
var skeleton := false
## 服务端榜单注入的热门二创。
var _trending: Array = []
var _hero: Dictionary = {}
var _continue: Array = []
var _events: Array = []

func _init(p_state: Node, p_catalog: CatalogCoordinator = null) -> void:
	catalog = p_catalog
	super(p_state)

func refresh() -> void:
	if catalog == null:
		return
	if await catalog.load_games({"lang": state.locale}):
		bind_games(catalog.store.items)
	if await catalog.load_ranking("hot", {"lang": state.locale}):
		bind_trending(catalog.store.ranking)
		trending_loaded.emit(_trending)

func bind_games(items: Array) -> void:
	_hero = items[0] if not items.is_empty() else {}
	if not skeleton: rebuild()

func bind_history(groups: Array) -> void:
	_continue = []
	for group: Dictionary in groups:
		for item: Dictionary in group.get("items", []):
			var game: Dictionary = item.get("game", {})
			if not game.is_empty():
				game = game.duplicate(true)
				game["minutes_played"] = int(item.get("minutes_played", 0))
				_continue.append(game)
	if not skeleton: rebuild()

func bind_events(items: Array) -> void:
	_events = items
	if not skeleton: rebuild()

## AppRoot 拉到 /ranking 后注入首页热门二创。
func bind_trending(items: Array) -> void:
	_trending = []
	for entry: Dictionary in items:
		var game: Dictionary = entry.get("game", entry).duplicate(true)
		if entry.has("rank"):
			game["rank"] = entry.rank
		_trending.append(game)
	if not skeleton:
		rebuild()

func show_skeleton() -> void:
	skeleton = true
	rebuild()

func finish_loading() -> void:
	skeleton = false
	rebuild()

func _build() -> void:
	if skeleton:
		_build_skeleton()
		return
	if _hero.is_empty() and _continue.is_empty() and _events.is_empty() and _trending.is_empty():
		var empty := empty_note(txt("his_empty"), txt("empty_go_explore"), func() -> void: explore_requested.emit())
		empty.name = "HomeEmpty"
		content.add_child(empty)
		return
	if not _hero.is_empty(): _build_hero()
	if not _continue.is_empty(): _build_continue()
	if not _events.is_empty(): _build_event_banner()
	_build_trending()

func _build_skeleton() -> void:
	var box := Widgets.vbox(Tokens.SPACE_3)
	box.name = "SkeletonBlocks"
	for h in [150, 56, 56, 48]:
		box.add_child(Widgets.skeleton_block(h, theme_name()))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_3)
	for i in 4:
		grid.add_child(Widgets.skeleton_block(120, theme_name()))
	box.add_child(grid)
	content.add_child(box)

## 一条活动横幅(运营位只留一条,docs/16「整理杂物间」),点击进活动中心。
func _build_event_banner() -> void:
	var e: Dictionary = _events[0]
	var card := Widgets.card(theme_name(), &"surface_raised")
	card.name = "EventBanner"
	var row := Widgets.hbox(Tokens.SPACE_2)
	card.add_child(row)
	row.add_child(Widgets.badge(txt("ev_banner_tag"), theme_name()))
	var title := Widgets.caption(str(e.get("title", "")), theme_name(), &"text_secondary")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)
	row.add_child(Widgets.caption(txt_fmt("ev_ends_fmt", [str(e.get("ends_in", ""))]), theme_name()))
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			events_requested.emit())
	content.add_child(card)

## 本周精选 hero:标题/作者叠在封面上(scrim 压暗保可读,原型 HeroCard 结构)。
## 叠图文字固定浅色,不随主题(图上永远是深底)。
func _build_hero() -> void:
	var hero := Control.new()
	hero.name = "Hero"
	hero.custom_minimum_size = Vector2(0, 190)
	hero.clip_contents = true
	var cover := GameCard.cover(_hero, 190)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero.add_child(cover)
	hero.add_child(Widgets.scrim())

	# 底部一行:左 标题/作者(撑开),右 立即开玩。整行底对齐贴在封面底部。
	var bottom := Widgets.hbox(Tokens.SPACE_3)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = Tokens.SPACE_4
	bottom.offset_right = -Tokens.SPACE_4
	bottom.offset_bottom = -Tokens.SPACE_4
	bottom.add_theme_constant_override("separation", Tokens.SPACE_4)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info := Widgets.vbox(Tokens.SPACE_2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_row := Widgets.hbox()
	badge_row.add_child(Widgets.badge(txt("featured"), theme_name()))
	badge_row.add_child(Widgets.spacer())
	info.add_child(badge_row)
	var title := Widgets.heading(GameCard.title_of(_hero, state.locale), 2, theme_name())
	title.name = "HeroTitle"
	title.add_theme_color_override("font_color", Color("#F2EDEC"))
	info.add_child(title)
	var i18n := preload("res://i18n/i18n.gd")
	var meta := Widgets.caption("%s · %s" % [
		txt_fmt("by_fmt", [str(_hero.get("by", _hero.get("author_id", "")))]),
		txt_fmt("forks_this_week", [i18n.format_number(int(_hero.get("forks", 0)), state.locale)]),
	], theme_name())
	meta.add_theme_color_override("font_color", Color(Color("#F2EDEC"), 0.75))
	info.add_child(meta)
	bottom.add_child(info)
	var play_btn := Widgets.primary_button(txt("play_now"), theme_name())
	play_btn.name = "HeroPlay"
	play_btn.size_flags_vertical = Control.SIZE_SHRINK_END  # 取 HIT_MIN 高、底对齐,不被行高拉伸/压扁
	play_btn.pressed.connect(func() -> void: play_requested.emit(_hero))
	bottom.add_child(play_btn)
	hero.add_child(bottom)

	hero.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game_opened.emit(_hero))
	content.add_child(hero)

func _build_continue() -> void:
	content.add_child(Widgets.heading(txt("continue_title"), 3, theme_name()))
	for game: Dictionary in _continue:
		var card := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		card.add_child(row)
		var cov := GameCard.cover(game, 56)
		cov.custom_minimum_size = Vector2(56, 56)
		row.add_child(cov)
		var col := Widgets.vbox(Tokens.SPACE_1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Widgets.body(GameCard.title_of(game, state.locale), theme_name()))
		col.add_child(Widgets.caption(txt_fmt("played_fmt", [int(game.get("minutes_played", 0))]), theme_name()))
		row.add_child(col)
		var play_btn := Widgets.primary_button("▶", theme_name())
		play_btn.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
		play_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # 否则被行高纵向拉成竖条
		play_btn.pressed.connect(func() -> void: play_requested.emit(game))
		row.add_child(play_btn)
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				game_opened.emit(game))
		content.add_child(card)

func _build_trending() -> void:
	var head := Widgets.section_header(txt("trending"), theme_name(), txt("see_all"), func() -> void: explore_requested.emit())
	var see_all := head.find_child("SectionAction", true, false)
	if see_all != null:
		see_all.name = "SeeAll"
	content.add_child(head)

	var grid := GridContainer.new()
	grid.name = "TrendingGrid"
	grid.columns = card_cols
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_3)
	var games: Array = _trending.slice(0, 4)
	for game: Dictionary in games:
		grid.add_child(GameCard.build(game, state.locale, theme_name(), func(g: Dictionary) -> void: game_opened.emit(g)))
	if games.is_empty():
		grid.add_child(empty_note(txt("his_empty")))
	content.add_child(grid)
