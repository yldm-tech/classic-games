class_name ExploreScreen
extends ScreenBase

const PagedListScript:=preload("res://ui/patterns/paged_list.gd")

## 发现 = 公域发现,「找个新游戏」(docs/16):榜单(热门/飙升/新作)→ 全部游戏(分类筛选 + AI 过滤)。
## 数据:AppRoot 在服务端可达时调 bind_ranking/bind_games 注入 /ranking、/games 真实数据;
## 注入前展示空态；游戏、榜单与直播只渲染服务端结果。

signal game_opened(game: Dictionary)
signal live_opened(live: Array)

var catalog: CatalogCoordinator

var _rank_tab := 0
var _cat := "All"
var _ai_only := false
# 服务端注入的数据；榜单按 rank_tabs 下标缓存。
var _server_ranking: Dictionary = {}
var _server_games: Array = []
var _server_live: Array = []
## 榜单专页模式:只渲染单个榜单列表(侧栏「飙升榜」用,与发现 tab 区分开)。
var ranking_only := false
var _pages:=PagedListScript.new()
var _page_query:Dictionary={}
var _page_generation:=0

const RANK_KINDS := ["hot", "rising", "new"]  # 服务端 /ranking?type= 取值

func _init(p_state: Node, p_catalog: CatalogCoordinator = null) -> void:
	catalog = p_catalog
	_pages.next_requested.connect(func(_cursor:String):_load_next_page())
	super(p_state)

func refresh() -> void:
	if catalog == null:
		return
	if not ranking_only:
		_page_generation+=1;var generation:=_page_generation
		var page:Dictionary=await catalog.fetch_collection(_collection_query())
		if generation!=_page_generation:return
		if page.ok:bind_games(page.items,page.next_cursor)
	var tabs: Array = [_rank_tab] if ranking_only else range(RANK_KINDS.size())
	for tab: int in tabs:
		if await catalog.load_ranking(RANK_KINDS[tab], {"lang": state.locale}):
			bind_ranking(tab, catalog.store.ranking)

## 配置为「飙升榜」独立专页:只放飙升榜单,无段控/直播/全部游戏。
func configure_ranking_page(rank: int) -> void:
	ranking_only = true
	_rank_tab = clampi(rank, 0, RANK_KINDS.size() - 1)
	rebuild()

func bind_ranking(tab_index: int, items: Array) -> void:
	_server_ranking[tab_index] = items
	rebuild()

func bind_games(items: Array,next_cursor:String="") -> void:
	_page_generation+=1;_page_query=_collection_query();_pages.replace(items,next_cursor);_server_games=_pages.items
	rebuild()

func _collection_query() -> Dictionary:
	var query := {"lang": state.locale}
	if _cat != "All":
		query["category"] = _cat.to_lower()
	if _ai_only:
		query["ai"] = "true"
	return query

func _apply_filters() -> void:
	rebuild()
	_reload_filtered_games()

func _reload_filtered_games() -> void:
	if catalog == null:
		return
	_page_generation += 1
	var generation := _page_generation
	var page: Dictionary = await catalog.fetch_collection(_collection_query())
	if generation != _page_generation:
		return
	if page.ok:
		bind_games(page.items, page.next_cursor)

func _load_next_page()->void:
	if catalog==null:_pages.fail_next();return
	var generation:=_page_generation;var page:Dictionary=await catalog.load_page(_page_query,_pages.cursor)
	if generation!=_page_generation:return
	if page.ok:_pages.append(page.items,page.next_cursor);_server_games=_pages.items;rebuild()
	else:_pages.fail_next();rebuild()

func bind_live(items: Array) -> void:
	_server_live = items
	rebuild()

func _build() -> void:
	if ranking_only:
		_build_rank_list()  # 飙升榜专页:只放榜单列表
		return
	_build_ranking()
	content.add_child(Widgets.divider(theme_name()))
	_build_live()
	content.add_child(Widgets.divider(theme_name()))
	_build_all_games()

## 正在直播(榜单在前、直播居中、全集垫底,docs/16 信息架构)。
func _build_live() -> void:
	content.add_child(Widgets.heading(txt("live_sec_title"), 3, theme_name()))
	var i18n := preload("res://i18n/i18n.gd")
	var row := Widgets.hbox(Tokens.SPACE_3)
	row.name = "LiveRow"
	for item: Dictionary in _server_live:
		var game: Dictionary = item.get("game", {})
		var card := Widgets.card(theme_name())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := Widgets.vbox(Tokens.SPACE_2)
		card.add_child(col)
		col.add_child(GameCard.cover(game, 64))
		var head := Widgets.hbox(Tokens.SPACE_2)
		head.add_child(Widgets.badge(txt("live_tag"), theme_name()))
		head.add_child(Widgets.caption(txt_fmt("watching_fmt", [i18n.format_number(int(item.get("viewers", 0)), state.locale)]), theme_name()))
		col.add_child(head)
		var title := Widgets.caption("%s · %s" % [str(item.get("streamer", "")), str(item.get("title", ""))], theme_name(), &"text_secondary")
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(title)
		var live := [item.get("streamer", ""), item.get("title", ""), item.get("viewers", 0), game.get("id", "")]
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				live_opened.emit(live))
		row.add_child(card)
	if _server_live.is_empty():
		row.add_child(empty_note(txt("live_empty")))
	content.add_child(row)

func _build_ranking() -> void:
	var seg := Widgets.segment(txt("rank_tabs"), _rank_tab, theme_name(), func(i: int) -> void:
		_rank_tab = i
		rebuild())
	seg.name = "RankSeg"
	content.add_child(seg)
	_build_rank_list()

func _build_rank_list() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "RankList"
	if _server_ranking.has(_rank_tab):
		var rank := 0
		for item: Dictionary in _server_ranking[_rank_tab]:
			rank += 1
			list.add_child(_rank_row(item, item.get("rank", rank), ""))
	else:
		list.add_child(empty_note(txt("ranking_empty")))
	content.add_child(list)

func _rank_row(entry: Dictionary, fallback_rank: int, delta: String) -> Control:
	var game: Dictionary = entry.get("game", entry)
	var rank := int(entry.get("rank", fallback_rank))
	var card := Widgets.card(theme_name())
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	var num := Widgets.big_number(str(rank), theme_name(), Tokens.FONT_H3)
	num.add_theme_color_override("font_color",
		Tokens.color(&"accent_primary" if rank <= 3 else &"text_muted", theme_name()))
	num.custom_minimum_size = Vector2(24, 0)
	row.add_child(num)
	var cov := GameCard.cover(game, 44)
	cov.custom_minimum_size = Vector2(44, 44)
	row.add_child(cov)
	var col := Widgets.vbox(Tokens.SPACE_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Widgets.body(GameCard.title_of(game, state.locale), theme_name()))
	var by: String = game.get("by", game.get("author_id", ""))
	var meta := txt_fmt("by_fmt", [by]) if by != "" else ""
	var stats := GameCard.stats_line(game, state.locale)
	if stats != "":
		meta = "%s · %s" % [meta, stats] if meta != "" else stats
	col.add_child(Widgets.caption(meta, theme_name()))
	row.add_child(col)
	if delta != "":
		var d := Label.new()
		d.text = txt("new_tag") if delta == "new" else delta
		d.add_theme_font_size_override("font_size", Tokens.FONT_MONO_SM)
		var tone: StringName = &"accent_ai" if delta == "new" \
			else &"status_success" if delta.begins_with("↑") \
			else &"status_danger" if delta.begins_with("↓") else &"text_muted"
		d.add_theme_color_override("font_color", Tokens.color(tone, theme_name()))
		row.add_child(d)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game_opened.emit(game))
	return card

func _build_all_games() -> void:
	content.add_child(Widgets.heading(txt("all_games"), 3, theme_name()))

	var chips := HFlowContainer.new()
	chips.name = "CatChips"
	chips.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	chips.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	var cats: Dictionary = txt("cats")
	for key: String in Catalog.CAT_KEYS:
		var c := Widgets.chip(cats[key], key == _cat, theme_name())
		var k := key
		c.pressed.connect(func() -> void:
			_cat = k
			_apply_filters())
		chips.add_child(c)
	var ai_chip := Widgets.chip(txt("ai_made"), _ai_only, theme_name(), true)
	ai_chip.pressed.connect(func() -> void:
		_ai_only = not _ai_only
		_apply_filters())
	chips.add_child(ai_chip)
	content.add_child(chips)

	var games: Array = _server_games
	var shown: Array = games.filter(func(g: Dictionary) -> bool:
		var cat_ok: bool = _cat == "All" or g.get("cat", "") == _cat or _cat in g.get("tags", [])
		var ai_ok: bool = not _ai_only or g.get("badge", "") == "ai" or g.get("ai_generated", false)
		return cat_ok and ai_ok)

	if shown.is_empty():
		content.add_child(empty_note(txt_fmt("no_results",[cats[_cat]])))
		return

	var grid := GridContainer.new()
	grid.name = "GamesGrid"
	grid.columns = card_cols
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_3)
	for g: Dictionary in shown:
		grid.add_child(GameCard.build(g, state.locale, theme_name(), func(gg: Dictionary) -> void: game_opened.emit(gg)))
	content.add_child(grid)
	if _pages.cursor!="":
		var more:=Widgets.secondary_button(txt("grp_more"),theme_name());more.name="LoadMoreButton";more.disabled=_pages.pending;more.pressed.connect(func():_pages.request_next();more.disabled=_pages.pending);content.add_child(more)
