class_name SearchScreen
extends ScreenBase

const AsyncContentScript:=preload("res://ui/patterns/async_content.gd")
const PagedListScript:=preload("res://ui/patterns/paged_list.gd")

## 全局搜索:实时过滤已加载目录、最近搜过、服务端热搜(无数据则隐藏)、空态。

signal game_opened(game: Dictionary)
signal closed

var catalog: CatalogCoordinator

var _query := ""
var _recent: Array = []
var _hot: Array = []
var _server_games: Array = []
var _search_results: Array = []
var _search_loaded := false
var _input: LineEdit
var _async_state:="ready"
var _pages:=PagedListScript.new()
var _search_generation:=0
var _base_generation:=0
var _page_query:Dictionary={}

func _init(p_state: Node, p_catalog: CatalogCoordinator = null) -> void:
	catalog = p_catalog
	_pages.next_requested.connect(func(_cursor:String):_load_next_page())
	super(p_state)

func refresh() -> void:
	if catalog!=null:
		_base_generation+=1;var generation:=_base_generation
		var page:Dictionary=await catalog.fetch_collection({"lang":state.locale})
		if generation!=_base_generation:return
		if page.ok:bind_games(page.items)

func retry_current() -> void:
	if _query.strip_edges().is_empty():
		await refresh()
	else:
		await _request_search(_query)

func _request_search(raw_query: String) -> void:
	var query := raw_query.strip_edges()
	if catalog == null or query.is_empty():
		return
	_search_generation+=1;var generation:=_search_generation
	_async_state="loading";rebuild()
	var page:Dictionary=await catalog.fetch_collection({"q":query,"lang":state.locale});var success:=bool(page.ok)
	if generation!=_search_generation:return
	if success:
		bind_search_results(query,page.items,page.next_cursor)
		_async_state="ready";rebuild()
	else:
		_async_state="offline" if str(page.get("kind",""))=="offline" else "error";rebuild()

## 进入搜索即聚焦输入框(AppRoot 切屏后调用)。
func focus_input() -> void:
	if _input != null and is_instance_valid(_input):
		_input.grab_focus()

func bind_games(items: Array) -> void:
	_base_generation+=1
	_server_games = items
	rebuild()

## Trending queries come from the server. i18n hot_list is copy, not traffic.
func bind_hot(items: Array) -> void:
	_hot = []
	for item in items:
		var q := str(item).strip_edges()
		if q != "":
			_hot.append(q)
	rebuild()

func bind_search_results(query: String, items: Array,next_cursor:String="") -> void:
	if query.strip_edges().to_lower() != _query.strip_edges().to_lower(): return
	_page_query={"q":query.strip_edges(),"lang":state.locale};_pages.replace(items,next_cursor);_search_results=_pages.items
	_search_loaded = true
	rebuild()

func _load_next_page()->void:
	if catalog==null:_pages.fail_next();return
	var generation:=_search_generation;var page:Dictionary=await catalog.load_page(_page_query,_pages.cursor)
	if generation!=_search_generation:return
	if page.ok:_pages.append(page.items,page.next_cursor);_search_results=_pages.items;rebuild()
	else:_pages.fail_next();rebuild()

func _build() -> void:
	var row := Widgets.hbox(Tokens.SPACE_2)
	_input = LineEdit.new()
	_input.name = "SearchInput"
	_input.placeholder_text = txt("search")
	_input.text = _query
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_changed.connect(func(t: String) -> void:
		_query = t
		_search_loaded = false
		rebuild()
		_input.grab_focus()
		_input.caret_column = _query.length()
		if not _query.strip_edges().is_empty(): _request_search(_query))
	row.add_child(_input)
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = txt("cancel")
	cancel.flat = true
	cancel.add_theme_color_override("font_color", Tokens.color(&"accent_primary", theme_name()))
	cancel.pressed.connect(func() -> void: closed.emit())
	row.add_child(cancel)
	content.add_child(row)
	if _async_state!="ready":
		var async_view=AsyncContentScript.new();async_view.present(_async_state,"",theme_name(),txt("off_retry"));async_view.retry_requested.connect(retry_current);content.add_child(async_view);return

	if _query.strip_edges() == "":
		_build_idle()
		return
	_build_results()

func _build_idle() -> void:
	_recent = state.search_recents.duplicate() if state != null else _recent
	if not _recent.is_empty():
		var recent_head := Widgets.section_header(txt("search_recent"), theme_name(), txt("search_clear_recent"), func() -> void:
			state.clear_search_recents(); _recent = []; rebuild())
		content.add_child(recent_head)
		var flow := HFlowContainer.new()
		flow.name = "RecentFlow"
		flow.add_theme_constant_override("h_separation", Tokens.SPACE_2)
		for q: String in _recent:
			var c := Widgets.chip(q, false, theme_name())
			var qq := q
			c.pressed.connect(func() -> void:
				_query = qq
				_search_loaded = false
				rebuild()
				_request_search(_query))
			flow.add_child(c)
		content.add_child(flow)
	if _hot.is_empty():
		return
	content.add_child(Widgets.caption(txt("hot_search"), theme_name()))
	var hot := HFlowContainer.new()
	hot.name = "HotFlow"
	hot.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	hot.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	for q: String in _hot:
		var c := Widgets.chip(q, false, theme_name())
		var qq := q
		c.pressed.connect(func() -> void:
			_query = qq
			_search_loaded = false
			rebuild()
			_request_search(_query))
		hot.add_child(c)
	content.add_child(hot)

## 服务端搜索结果到达前,只用已加载的真实游戏列表(bind_games 注入,与发现页同源)本地预筛,
## 不再混入 Catalog 硬编码演示游戏充数——那批数据不是真实搜索结果,会让用户以为搜到了东西。
func _matches() -> Array:
	if _search_loaded: return _search_results
	var q := _query.strip_edges().to_lower()
	return _server_games.filter(func(g: Dictionary) -> bool:
		var title := GameCard.title_of(g, state.locale).to_lower()
		var by: String = g.get("by", g.get("author_id", "")).to_lower()
		return q in title or q in by)

func _build_results() -> void:
	var found := _matches()
	if found.is_empty():
		content.add_child(empty_note(txt_fmt("search_empty_fmt",[_query])))
		return
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "ResultList"
	for g: Dictionary in found:
		list.add_child(GameCard.build(g, state.locale, theme_name(), func(gg: Dictionary) -> void:
			state.remember_search(_query)
			_recent = state.search_recents.duplicate()
			game_opened.emit(gg)))
	content.add_child(list)
	if _pages.cursor!="":
		var more:=Widgets.secondary_button(txt("grp_more"),theme_name());more.name="LoadMoreButton";more.disabled=_pages.pending;more.pressed.connect(func():_pages.request_next();more.disabled=_pages.pending);content.add_child(more)
