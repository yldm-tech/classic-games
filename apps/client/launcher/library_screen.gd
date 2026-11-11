class_name LauncherLibraryScreen
extends LauncherScreen

## Library: every game as a cover grid, with category tabs, sorting, search, and a detail strip for the focused game.
##
## Categories are only the ones real data backs: all games, recently played (LauncherStore.recents), favourites, and one tab per genre found in the catalog. The detail strip and the bar along each cover come from LauncherStore; a game that was never played says so.
##
## Buttons: LB/RB switch the category (LT/RT stay with the shell and switch the top-level tab), A starts the focused game, Y toggles its favourite, Menu opens its game menu, X opens the search. Sorting has no button of its own: Up from the first row of covers reaches the toolbar, where A on the sort chip cycles the order and A on the search chip opens the search.
##
## Search matches pinyin initials (LauncherCatalog.matches) or the start of a word of the English name. The search layer is an on-screen keyboard driven by the same actions as everything else; while it is open it also takes letters and Backspace straight from a physical keyboard, which is the one place in the launcher where a key is read as text rather than as an action.

const ZONE_GRID := &"grid"
const ZONE_TOOLBAR := &"toolbar"
const ZONE_SEARCH := &"search"

const TAB_ALL := "all"
const TAB_RECENT := "recent"
const TAB_FAVORITES := "favorites"
const GENRE_PREFIX := "genre:"

const SORT_NAME := &"name"
const SORT_RECENT := &"recent"
const SORT_TIME := &"time"
const SORTS: Array[StringName] = [SORT_NAME, SORT_RECENT, SORT_TIME]

const TOOL_SORT := 0
const TOOL_SEARCH := 1

const COLUMNS := 4
const VISIBLE_ROWS := 2
const TABS_TOP := 124.0
const TABS_HEIGHT := 56.0
const TAB_GAP := 8.0
const RULE_TOP := 196.0
const GRID_TOP := 248.0
const DETAIL_BOTTOM := 116.0
const DETAIL_TITLE_WIDTH := 520.0
const COVER_NAME_GAP := 14.0
const COVER_NAME_HEIGHT := 28.0

const QUERY_MAX := 8
const KB_BACKSPACE := "backspace"
const KB_CLEAR := "clear"
const KB_DONE := "done"
const KEY_COLUMNS := 10
const KEY_GAP := 8.0
const KEY_HEIGHT := 60.0
const SEARCH_WIDTH := 1080.0
const SEARCH_BOTTOM := 96.0
## The on-screen keyboard, row by row. Backspace and clear are two columns wide and "done" spans the row.
const KEY_ROWS := [
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "z"],
	["x", "c", "v", "b", "n", "m", KB_BACKSPACE, KB_CLEAR],
	[KB_DONE],
]

## The games on offer, in catalog order. build() fills it from LauncherCatalog; set_entries() replaces it.
var entries: Array[Dictionary] = []
var category := TAB_ALL
var sort := SORT_NAME
var query := ""
var focus_id := ""
var zone := ZONE_GRID
var tool_index := TOOL_SORT
var key_row := 0
var key_index := 0

var _bar: HBoxContainer
var _tabs_clip: Control
var _tabs_box: HBoxContainer
var _tools: HBoxContainer
var _tabs: Dictionary = {}
var _sort_chip: _Chip
var _search_chip: _Chip
var _grid: LauncherScrollGrid
var _covers: Dictionary = {}
var _empty: VBoxContainer
var _empty_title: Label
var _empty_body: Label
var _detail: VBoxContainer
var _detail_latin: Label
var _detail_favorite: Control
var _detail_title: Label
var _detail_values: Dictionary = {}
var _backdrop_id := ""
var _search: Control
var _search_field: Label
var _search_count: Label
var _keys: Array = []
var _key_column := 0

func build() -> void:
	entries.assign(LauncherCatalog.all())
	var scrim := ColorRect.new()
	scrim.name = "Dim"
	scrim.color = T.deep(T.A_SCRIM_LIBRARY)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(scrim))
	_build_bar()
	var rule := W.rule(T.fg(0.16))
	rule.position = Vector2(T.MARGIN, RULE_TOP)
	rule.size = Vector2(T.CANVAS.x - T.MARGIN * 2.0, 1)
	add_child(rule)
	_grid = LauncherScrollGrid.new(COLUMNS, T.COVER_SIZE + Vector2(0, COVER_NAME_GAP + COVER_NAME_HEIGHT), T.COVER_GAP, VISIBLE_ROWS)
	_grid.name = "Grid"
	_grid.place_at(Vector2(T.MARGIN, GRID_TOP))
	_grid.wheeled.connect(_on_wheel)
	add_child(_grid)
	_empty = W.vbox(12)
	_empty.name = "Empty"
	_empty.position = Vector2(T.MARGIN, GRID_TOP + 60.0)
	_empty_title = W.text("", T.SIZE_ROW)
	_empty_title.name = "Title"
	_empty.add_child(_empty_title)
	_empty_body = W.text("", T.SIZE_NAV, 400, T.fg(0.7))
	_empty_body.name = "Body"
	_empty.add_child(_empty_body)
	add_child(_empty)
	_build_detail()
	_build_tabs()
	shell.store.changed.connect(_on_store_changed)

func _build_bar() -> void:
	var bar := W.hbox(8)
	bar.name = "Bar"
	bar.position = Vector2(T.MARGIN, TABS_TOP)
	bar.size = Vector2(T.CANVAS.x - T.MARGIN * 2.0, TABS_HEIGHT)
	add_child(bar)
	_bar = bar
	bar.add_child(_shoulder(In.LB, 0, 18))
	# The tabs sit in a clipped strip that is only as wide as the bar can spare, so a long row of genres slides under the shoulder glyphs instead of pushing the toolbar off the canvas.
	_tabs_clip = Control.new()
	_tabs_clip.name = "TabStrip"
	_tabs_clip.clip_contents = true
	_tabs_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_tabs_clip)
	_tabs_box = W.hbox(TAB_GAP)
	_tabs_box.name = "Tabs"
	_tabs_clip.add_child(_tabs_box)
	bar.add_child(_shoulder(In.RB, 18, 0))
	var tools := W.hbox(8)
	tools.name = "Tools"
	tools.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	bar.add_child(tools)
	_tools = tools
	_sort_chip = _Chip.new(&"")
	_sort_chip.name = "Sort"
	_sort_chip.hovered.connect(func() -> void: _focus_tool(TOOL_SORT))
	_sort_chip.activated.connect(func() -> void:
		_focus_tool(TOOL_SORT)
		cycle_sort())
	tools.add_child(_sort_chip)
	_search_chip = _Chip.new(In.X)
	_search_chip.name = "Search"
	_search_chip.hovered.connect(func() -> void: _focus_tool(TOOL_SEARCH))
	_search_chip.activated.connect(open_search)
	tools.add_child(_search_chip)

func _shoulder(action: StringName, left: int, right: int) -> Control:
	var button := C.Pressable.new()
	button.name = "Glyph_%s" % String(action).trim_prefix("launcher_")
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_constant_override("margin_left", left)
	button.add_theme_constant_override("margin_right", right)
	button.add_child(C.Glyph.new(action))
	button.activated.connect(func() -> void: shell.dispatch(action))
	return button

func _build_tabs() -> void:
	W.clear(_tabs_box)
	_tabs.clear()
	for key in categories():
		var tab := C.Tab.new(category_label(key), T.SIZE_CATEGORY_TAB, TABS_HEIGHT)
		tab.name = "Tab_%s" % key.replace(":", "_").replace(" ", "_")
		tab.idle_alpha = T.A_FAINT
		tab.set_padding(22)
		tab.activated.connect(func() -> void: set_category(key))
		_tabs_box.add_child(tab)
		_tabs[key] = tab

func _build_detail() -> void:
	_detail = W.vbox(28)
	_detail.name = "Detail"
	_detail.anchor_top = 1.0
	_detail.anchor_bottom = 1.0
	_detail.offset_left = T.MARGIN
	_detail.offset_right = T.CANVAS.x - T.MARGIN - 80.0
	_detail.offset_top = -DETAIL_BOTTOM
	_detail.offset_bottom = -DETAIL_BOTTOM
	_detail.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_detail)
	_detail.add_child(W.rule(T.fg(0.16)))
	var row := W.hbox(48)
	_detail.add_child(row)
	var heading := W.vbox(10)
	heading.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(heading)
	var eyebrow := W.hbox(14)
	# A fixed height, so the strip does not jump when a game has neither a Latin subtitle nor the favourite tag.
	eyebrow.custom_minimum_size = Vector2(0, 18)
	heading.add_child(eyebrow)
	_detail_latin = W.text("", T.SIZE_SMALL, 600, T.fg(0.7), 5, true)
	_detail_latin.name = "LatinName"
	eyebrow.add_child(_detail_latin)
	var tag := W.hbox(6)
	tag.name = "FavoriteTag"
	tag.add_child(C.Icon.new("heart", 14.0, T.FAVORITE))
	tag.add_child(W.text(t("launcher.common.favorite"), T.SIZE_SMALL, 600, T.FAVORITE, 3, true))
	_detail_favorite = tag
	eyebrow.add_child(tag)
	_detail_title = W.text("", T.SIZE_DETAIL_TITLE, 900, T.FG, 4)
	_detail_title.name = "Title"
	heading.add_child(_detail_title)
	var stats := W.hbox(40)
	stats.name = "Stats"
	stats.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(stats)
	for field in ["genre", "players", "time", "last", "best", "runs", "achievements"]:
		var column := W.vbox(6)
		column.add_child(W.text(t("launcher.library.stat_%s" % field), T.SIZE_STAT_LABEL, 400, T.fg(T.A_MUTED), 3))
		var value := W.text("", T.SIZE_STAT_VALUE)
		value.name = "Value_%s" % field
		column.add_child(value)
		stats.add_child(column)
		_detail_values[field] = value

# ---- lifecycle ----

## Replace the games on offer (catalog entries, in display order) and rebuild the tabs and covers for them.
func set_entries(p_entries: Array[Dictionary]) -> void:
	entries = p_entries
	for id: String in _covers:
		(_covers[id] as Node).queue_free()
	_covers.clear()
	var none: Array[Control] = []
	_grid.layout(none)
	if not categories().has(category):
		category = TAB_ALL
	_build_tabs()
	if visible:
		_refresh(false)

func on_enter(args: Dictionary) -> void:
	_close_search()
	zone = ZONE_GRID
	var wanted := str(args.get("game", ""))
	if wanted != "" and not _entry(wanted).is_empty():
		# The requested game must be on the grid, so a category or search that hides it gives way.
		if not shown_ids().has(wanted):
			category = TAB_ALL
			query = ""
		focus_id = wanted
	_refresh(false)

func on_exit() -> void:
	_close_search()

func backdrop() -> Dictionary:
	return {"layer": &"blur", "game": _backdrop_id}

func _on_store_changed(_section: StringName) -> void:
	if visible:
		_refresh()

# ---- data ----

func _entry(id: String) -> Dictionary:
	for entry in entries:
		if entry["id"] == id:
			return entry
	return {}

## Category keys in tab order: all, recently played, favourites, then one per genre in catalog order.
func categories() -> Array[String]:
	var out: Array[String] = [TAB_ALL, TAB_RECENT, TAB_FAVORITES]
	for entry in entries:
		var key := GENRE_PREFIX + LauncherCatalog.text(entry, "genre", "en")
		if not out.has(key):
			out.append(key)
	return out

func category_label(key: String) -> String:
	if not key.begins_with(GENRE_PREFIX):
		return t("launcher.library.tab_%s" % key)
	for entry in entries:
		if GENRE_PREFIX + LauncherCatalog.text(entry, "genre", "en") == key:
			return LauncherCatalog.text(entry, "genre", shell.locale)
	return key.trim_prefix(GENRE_PREFIX)

## Ids of the games in a category, before search and sorting.
func ids_in(key: String) -> Array[String]:
	var out: Array[String] = []
	if key == TAB_RECENT:
		for id in shell.store.recents():
			if not _entry(id).is_empty():
				out.append(id)
		return out
	for entry in entries:
		var id := str(entry["id"])
		if key == TAB_ALL or (key == TAB_FAVORITES and shell.store.is_favorite(id)) or key == GENRE_PREFIX + LauncherCatalog.text(entry, "genre", "en"):
			out.append(id)
	return out

## Whether a game matches the search text: by pinyin initials, or by the start of any word of its English name.
static func matches(entry: Dictionary, text: String) -> bool:
	var q := text.strip_edges().to_lower()
	if q == "" or LauncherCatalog.matches(entry, q):
		return true
	var latin := LauncherCatalog.text(entry, "name", "en").to_lower()
	if latin.replace(" ", "").begins_with(q):
		return true
	for word in latin.split(" ", false):
		if word.begins_with(q):
			return true
	return false

## What the grid shows: the current category, filtered by the search, in the current order.
func shown_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ids_in(category):
		if matches(_entry(id), query):
			out.append(id)
	out.sort_custom(_before)
	return out

func _name_key(id: String) -> String:
	var entry := _entry(id)
	if shell.locale == "en":
		return LauncherCatalog.text(entry, "name", "en").to_lower()
	# Chinese names sort the way they are searched: by pinyin initials.
	return str(entry.get("initials", LauncherCatalog.text(entry, "name", "en").to_lower()))

func _before(a: String, b: String) -> bool:
	if sort == SORT_RECENT:
		var last_a := int(shell.store.stats(a)["last_played"])
		var last_b := int(shell.store.stats(b)["last_played"])
		if last_a != last_b:
			return last_a > last_b
	elif sort == SORT_TIME:
		var time_a := float(shell.store.stats(a)["play_seconds"])
		var time_b := float(shell.store.stats(b)["play_seconds"])
		if not is_equal_approx(time_a, time_b):
			return time_a > time_b
	var name_a := _name_key(a)
	var name_b := _name_key(b)
	return name_a < name_b if name_a != name_b else a < b

## [unlocked, defined] achievements of a game, counting only ones the catalog still defines.
func achievement_counts(id: String) -> Array[int]:
	var defined: Array = _entry(id).get("achievements", [])
	var unlocked := shell.store.achievements(id)
	var count := 0
	for achievement: Dictionary in defined:
		if unlocked.has(achievement["id"]):
			count += 1
	return [count, defined.size()]

# ---- rendering ----

func _cover(id: String) -> _Cover:
	if not _covers.has(id):
		var cover := _Cover.new(id)
		cover.name = "Cover_%s" % id
		cover.pointed.connect(func() -> void: _point(id))
		cover.activated.connect(func() -> void:
			_point(id)
			start_game())
		_grid.add_cell(cover)
		_covers[id] = cover
	return _covers[id]

func _refresh(animate: bool = true) -> void:
	var shown := shown_ids()
	if not shown.has(focus_id):
		focus_id = shown[0] if not shown.is_empty() else ""
	if focus_id != "":
		_backdrop_id = focus_id
	elif _entry(_backdrop_id).is_empty():
		_backdrop_id = str(entries[0]["id"]) if not entries.is_empty() else ""

	for key: String in _tabs:
		var tab: LauncherControls.Tab = _tabs[key]
		tab.set_selected(key == category)
		tab.set_count(ids_in(key).size())
	_sort_chip.set_text(tf("launcher.library.sort_fmt", [t("launcher.library.sort_%s" % sort)]))
	_sort_chip.set_focused(zone == ZONE_TOOLBAR and tool_index == TOOL_SORT)
	_search_chip.set_text(t("launcher.library.search") if query == "" else tf("launcher.library.search_fmt", [query.to_upper()]))
	_search_chip.set_active(query != "")
	_search_chip.set_focused(zone == ZONE_TOOLBAR and tool_index == TOOL_SEARCH)

	_fit_tabs()

	var cells: Array[Control] = []
	for id in shown:
		var cover := _cover(id)
		var counts := achievement_counts(id)
		cover.set_title(LauncherCatalog.text(_entry(id), "name", shell.locale))
		cover.set_progress(float(counts[0]) / float(counts[1]) if counts[1] > 0 else 0.0)
		cover.set_favorite(shell.store.is_favorite(id))
		cover.set_selected(id == focus_id and zone != ZONE_TOOLBAR, animate)
		cells.append(cover)
	_grid.layout(cells)
	_grid.ensure_visible(shown.find(focus_id), animate)

	_empty.visible = shown.is_empty()
	if shown.is_empty():
		var reason := "search" if query != "" else ("favorites" if category == TAB_FAVORITES else "recent")
		_empty_title.text = t("launcher.library.empty_%s_title" % reason)
		_empty_body.text = t("launcher.library.empty_%s_body" % reason)
	_refresh_detail()
	_refresh_footer()
	_refresh_search()
	shell.refresh_backdrop()

## Size the tab strip to what the bar can spare and slide the tabs so the selected one is inside it.
func _fit_tabs() -> void:
	var fixed := _tools.get_combined_minimum_size().x
	for child in _bar.get_children():
		if child != _tabs_clip and child != _tools:
			fixed += (child as Control).get_combined_minimum_size().x
	var spare := _bar.size.x - fixed - _bar.get_theme_constant("separation") * (_bar.get_child_count() - 1) - 24.0
	var total := 0.0
	var selected_from := 0.0
	var selected_to := 0.0
	for key: String in _tabs:
		var tab_width := (_tabs[key] as Control).get_combined_minimum_size().x
		if key == category:
			selected_from = total
			selected_to = total + tab_width
		total += tab_width + TAB_GAP
	total -= TAB_GAP
	var strip := minf(total, spare)
	_tabs_clip.custom_minimum_size = Vector2(strip, TABS_HEIGHT)
	_tabs_box.size = Vector2(total, TABS_HEIGHT)
	var offset := clampf(-_tabs_box.position.x, selected_to - strip, selected_from)
	_tabs_box.position = Vector2(-clampf(offset, 0.0, maxf(0.0, total - strip)), 0)

## Whether the tab of a category is fully inside the visible part of the tab strip.
func is_tab_in_view(key: String) -> bool:
	var from := 0.0
	for other: String in _tabs:
		var width := (_tabs[other] as Control).get_combined_minimum_size().x
		if other == key:
			return from + _tabs_box.position.x >= -0.5 and from + width + _tabs_box.position.x <= _tabs_clip.custom_minimum_size.x + 0.5
		from += width + TAB_GAP
	return false

func _refresh_detail() -> void:
	_detail.visible = focus_id != ""
	if focus_id == "":
		return
	var entry := _entry(focus_id)
	var stats := shell.store.stats(focus_id)
	var played := int(stats["runs"]) > 0
	var counts := achievement_counts(focus_id)
	_detail_latin.text = LauncherCatalog.text(entry, "name", "en")
	# In English the title already is the Latin name.
	_detail_latin.visible = shell.locale != "en"
	_detail_favorite.visible = shell.store.is_favorite(focus_id)
	var title := LauncherCatalog.text(entry, "name", shell.locale)
	var font_size := T.SIZE_DETAIL_TITLE
	var settings := T.label_settings(font_size, 900, T.FG, 4)
	# A long name is scaled down so the figures beside it keep their room.
	while font_size > 28 and settings.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > DETAIL_TITLE_WIDTH:
		font_size -= 2
	settings.font_size = font_size
	_detail_title.label_settings = settings
	_detail_title.text = title
	var none := t("launcher.library.none")
	_value("genre").text = LauncherCatalog.text(entry, "genre", shell.locale)
	_value("players").text = LauncherCatalog.players_label(entry)
	_value("time").text = LauncherFormat.play_time(float(stats["play_seconds"]), shell.locale) if played else none
	_value("last").text = LauncherFormat.when_time(int(stats["last_played"]), shell.now(), shell.locale) if played else t("launcher.home.never_played")
	_value("best").text = LauncherFormat.score(int(stats["best_score"])) if played else none
	_value("runs").text = str(int(stats["runs"]))
	_value("achievements").text = "%d / %d" % counts

func _value(field: String) -> Label:
	return _detail_values[field]

## Text of one figure in the detail strip: genre, players, time, last, best, runs, achievements.
func detail_value(field: String) -> String:
	return _value(field).text

func _refresh_footer() -> void:
	if zone == ZONE_TOOLBAR:
		set_footer([[In.ACCEPT, t("launcher.library.hint_select")], [In.BACK, t("launcher.common.back")]])
	elif focus_id == "":
		set_footer([[In.BACK, t("launcher.common.back")]])
	else:
		set_footer([
			[In.ACCEPT, t("launcher.library.hint_start")],
			[In.Y, t("launcher.home.remove_favorite" if shell.store.is_favorite(focus_id) else "launcher.home.add_favorite")],
			[In.MENU, t("launcher.library.hint_menu")],
			[In.BACK, t("launcher.common.back")],
		])

## Index of the first row of covers in view.
func first_visible_row() -> int:
	return _grid.first_row

func empty_title() -> String:
	return _empty_title.text if _empty.visible else ""

# ---- focus and actions ----

func handle_action(action: StringName) -> bool:
	if zone == ZONE_SEARCH:
		return _search_action(action)
	match action:
		In.LB:
			_cycle_category(-1)
			return true
		In.RB:
			_cycle_category(1)
			return true
		In.X:
			open_search()
			return true
	if zone == ZONE_TOOLBAR:
		return _toolbar_action(action)
	match action:
		In.UP, In.DOWN, In.LEFT, In.RIGHT:
			_move(action)
		In.ACCEPT:
			start_game()
		In.Y:
			toggle_favorite()
		In.MENU:
			open_menu()
		_:
			return false
	return true

func _move(action: StringName) -> void:
	var shown := shown_ids()
	var target := LauncherScrollGrid.step(shown.find(focus_id), shown.size(), COLUMNS, action)
	if target >= 0:
		focus_id = shown[target]
	elif action == In.UP:
		# Above the first row is the toolbar.
		zone = ZONE_TOOLBAR
	_refresh()

func _toolbar_action(action: StringName) -> bool:
	match action:
		In.LEFT:
			tool_index = TOOL_SORT
		In.RIGHT:
			tool_index = TOOL_SEARCH
		In.DOWN:
			zone = ZONE_GRID
		In.ACCEPT:
			if tool_index == TOOL_SORT:
				cycle_sort()
			else:
				open_search()
			return true
		In.UP, In.Y, In.MENU:
			return true
		_:
			return false
	_refresh()
	return true

func _focus_tool(index: int) -> void:
	if zone == ZONE_SEARCH or (zone == ZONE_TOOLBAR and tool_index == index):
		return
	zone = ZONE_TOOLBAR
	tool_index = index
	_refresh()

## The mouse moved over a cover: it takes the focus, the same as walking there with the stick.
func _point(id: String) -> void:
	if zone == ZONE_SEARCH or (zone == ZONE_GRID and focus_id == id):
		return
	zone = ZONE_GRID
	focus_id = id
	_refresh()

func _on_wheel(step: int) -> void:
	if zone == ZONE_SEARCH:
		return
	zone = ZONE_GRID
	_move(In.UP if step < 0 else In.DOWN)

func set_category(key: String) -> void:
	if not _tabs.has(key):
		return
	category = key
	if zone == ZONE_TOOLBAR:
		zone = ZONE_GRID
	_refresh(false)

func _cycle_category(step: int) -> void:
	var keys := categories()
	set_category(keys[posmod(keys.find(category) + step, keys.size())])

func cycle_sort() -> void:
	sort = SORTS[(SORTS.find(sort) + 1) % SORTS.size()]
	_refresh(false)

## Launch the focused game, the same way Home does.
func start_game() -> void:
	if focus_id != "":
		shell.go(LauncherRoot.GAME, {"game": focus_id})

func open_menu() -> void:
	if focus_id != "":
		shell.go(LauncherRoot.MENU, {"game": focus_id})

func toggle_favorite() -> void:
	if focus_id == "":
		return
	var game_id := focus_id
	var was := shell.store.is_favorite(game_id)
	var title := LauncherCatalog.text(_entry(game_id), "name", shell.locale)
	shell.store.set_favorite(game_id, not was)
	shell.toast(tf("launcher.home.unfavorited_fmt" if was else "launcher.home.favorited_fmt", [title]), func() -> void:
		shell.store.set_favorite(game_id, was)
		# Undoing a removal on the favourites tab brings the cover back; put the focus back on it too.
		if visible and shown_ids().has(game_id):
			focus_id = game_id
			_refresh())

# ---- search ----

func is_search_open() -> bool:
	return _search != null

func open_search() -> void:
	if _search != null:
		return
	zone = ZONE_SEARCH
	key_row = 0
	key_index = 0
	_key_column = 0
	_build_search()
	_refresh()

func close_search() -> void:
	_close_search()
	_refresh()

func _close_search() -> void:
	if _search != null:
		shell.hide_overlay()
		_search = null
	_keys.clear()
	_search_field = null
	_search_count = null
	if zone == ZONE_SEARCH:
		zone = ZONE_GRID

func type_letter(letter: String) -> void:
	set_query(query + letter.to_lower())

func backspace() -> void:
	set_query(query.left(query.length() - 1))

func set_query(value: String) -> void:
	query = value.left(QUERY_MAX)
	_refresh(false)

func _search_action(action: StringName) -> bool:
	match action:
		In.UP, In.DOWN, In.LEFT, In.RIGHT:
			_move_key(action)
		In.ACCEPT:
			_press_key(str(KEY_ROWS[key_row][key_index]))
		In.X:
			backspace()
		In.Y:
			set_query("")
		In.BACK, In.MENU:
			close_search()
	# The search layer is modal: nothing falls through to the shell while it is open.
	return true

static func _key_span(key: String) -> int:
	if key == KB_DONE:
		return KEY_COLUMNS
	return 2 if key == KB_BACKSPACE or key == KB_CLEAR else 1

static func _key_start(row: int, index: int) -> int:
	var column := 0
	for i in index:
		column += _key_span(str(KEY_ROWS[row][i]))
	return column

## Index of the key in `row` that covers `column`.
static func _key_at(row: int, column: int) -> int:
	var start := 0
	for i in (KEY_ROWS[row] as Array).size():
		start += _key_span(str(KEY_ROWS[row][i]))
		if column < start:
			return i
	return (KEY_ROWS[row] as Array).size() - 1

func _move_key(action: StringName) -> void:
	match action:
		In.LEFT:
			key_index = maxi(0, key_index - 1)
			_key_column = _key_start(key_row, key_index)
		In.RIGHT:
			key_index = mini((KEY_ROWS[key_row] as Array).size() - 1, key_index + 1)
			_key_column = _key_start(key_row, key_index)
		In.UP, In.DOWN:
			# Moving between rows keeps the column the focus was last put in, so going down onto a wide key and up again returns to the same letter.
			key_row = clampi(key_row + (-1 if action == In.UP else 1), 0, KEY_ROWS.size() - 1)
			key_index = _key_at(key_row, _key_column)
	_sync_keys()

func _focus_key(row: int, index: int) -> void:
	key_row = row
	key_index = index
	_key_column = _key_start(row, index)
	_sync_keys()

func _press_key(key: String) -> void:
	match key:
		KB_BACKSPACE:
			backspace()
		KB_CLEAR:
			set_query("")
		KB_DONE:
			close_search()
		_:
			type_letter(key)

## A physical key pressed while the search is open. Letters are typed and Backspace deletes; returns whether the key was used, so everything else still reaches the launcher as an action.
func handle_search_key(event: InputEventKey) -> bool:
	if _search == null or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	var code := event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	if code == KEY_BACKSPACE:
		backspace()
		return true
	var letter := char(event.unicode).to_lower() if event.unicode != 0 else (char(code).to_lower() if code >= KEY_A and code <= KEY_Z else "")
	if letter.length() != 1 or letter < "a" or letter > "z":
		return false
	# Typing parks the focus on "done", so Enter closes the search instead of adding whatever key had focus.
	key_row = KEY_ROWS.size() - 1
	key_index = 0
	type_letter(letter)
	return true

func _refresh_search() -> void:
	if _search == null:
		return
	_search_field.text = query.to_upper() if query != "" else "_"
	_search_count.text = tf("launcher.library.search_count_fmt", [shown_ids().size()])
	_sync_keys()

func _sync_keys() -> void:
	for row in _keys.size():
		for index in (_keys[row] as Array).size():
			(_keys[row][index] as _Key).set_focused(row == key_row and index == key_index)

func _build_search() -> void:
	var layer := _SearchLayer.new()
	layer.name = "SearchLayer"
	layer.on_key = handle_search_key
	_search = layer
	# On the shell's overlay layer, so the scrim also covers the top navigation.
	shell.show_overlay(layer)
	var scrim := _Scrim.new()
	scrim.name = "SearchScrim"
	scrim.activated.connect(close_search)
	layer.add_child(W.fill(scrim))

	var dialog := PanelContainer.new()
	dialog.name = "Dialog"
	var style := StyleBoxFlat.new()
	style.bg_color = T.CARD_BG
	style.border_color = T.fg(0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(T.RADIUS))
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 80
	style.shadow_offset = Vector2(0, 30)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	dialog.add_theme_stylebox_override("panel", style)
	dialog.custom_minimum_size = Vector2(SEARCH_WIDTH, 0)
	layer.add_child(dialog)
	var column := W.vbox(20)
	dialog.add_child(column)

	var header := W.hbox(16)
	column.add_child(header)
	var caption := W.text(t("launcher.library.search_title"), T.SIZE_SUB, 400, T.fg(T.A_MUTED), 3)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(caption)
	var field := _Field.new()
	field.name = "Field"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(field)
	_search_field = W.text("", T.SIZE_SEARCH_FIELD, 700, T.FG, 6, true)
	_search_field.name = "Query"
	_search_field.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	field.add_child(_search_field)
	_search_count = W.text("", T.SIZE_BODY, 400, T.fg(T.A_BODY))
	_search_count.name = "Count"
	_search_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_search_count)

	var unit := (SEARCH_WIDTH - 72.0 - KEY_GAP * (KEY_COLUMNS - 1)) / KEY_COLUMNS
	var board := W.vbox(KEY_GAP)
	board.name = "Keys"
	column.add_child(board)
	_keys.clear()
	for row in KEY_ROWS.size() - 1:
		var line := W.hbox(KEY_GAP)
		board.add_child(line)
		var widgets: Array = []
		for index in (KEY_ROWS[row] as Array).size():
			var key := str(KEY_ROWS[row][index])
			var span := _key_span(key)
			var widget := _Key.new(key.to_upper() if span == 1 else t("launcher.library.key_%s" % key), span == 1)
			widget.name = "Key_%s" % key
			widget.custom_minimum_size = Vector2(unit * span + KEY_GAP * (span - 1), KEY_HEIGHT)
			_wire_key(widget, row, index)
			line.add_child(widget)
			widgets.append(widget)
		_keys.append(widgets)

	var bottom := W.hbox(4)
	column.add_child(bottom)
	var note := W.text(t("launcher.library.search_note"), T.SIZE_STAT_LABEL, 400, T.fg(0.5))
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(note)
	for hint: Array in [[In.X, "launcher.library.key_backspace"], [In.Y, "launcher.library.key_clear"], [In.BACK, "launcher.library.key_done"]]:
		var action: StringName = hint[0]
		var widget := C.GlyphHint.new(action, t(str(hint[1])))
		widget.name = "Hint_" + String(action).trim_prefix("launcher_")
		widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		widget.activated.connect(func() -> void: shell.dispatch(action))
		bottom.add_child(widget)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(gap)
	var done := _Key.new(t("launcher.library.key_done"), false, true)
	done.name = "Key_done"
	done.custom_minimum_size = Vector2(132, 52)
	_wire_key(done, KEY_ROWS.size() - 1, 0)
	bottom.add_child(done)
	_keys.append([done])

	dialog.reset_size()
	dialog.position = Vector2((T.CANVAS.x - dialog.size.x) / 2.0, T.CANVAS.y - SEARCH_BOTTOM - dialog.size.y)

func _wire_key(widget: _Key, row: int, index: int) -> void:
	widget.hovered.connect(func() -> void: _focus_key(row, index))
	widget.activated.connect(func() -> void:
		_focus_key(row, index)
		_press_key(str(KEY_ROWS[row][index])))

# ---- widgets ----

## A cover on the grid: 16:9 key art with the achievement bar along its bottom edge and a favourite badge, the name underneath. Selected = ring, slight scale, full opacity. `pointed` fires when the mouse really moves over it; unlike `hovered` it stays silent when the grid scrolls a cover under a resting pointer.
class _Cover:
	extends LauncherControls.Pressable

	signal pointed

	var game_id := ""
	var selected := false

	var _frame: Control
	var _progress: ColorRect
	var _badge: Control
	var _ring: Control
	var _name: Label
	var _tween: Tween

	func _init(p_game_id: String) -> void:
		super()
		game_id = p_game_id
		modulate.a = LauncherTokens.A_COVER_IDLE
		var column := LauncherWidgets.vbox(14)
		add_child(column)
		_frame = Control.new()
		_frame.name = "Frame"
		_frame.custom_minimum_size = LauncherTokens.COVER_SIZE
		_frame.pivot_offset = LauncherTokens.COVER_SIZE / 2.0
		_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_frame)
		var shadow := Panel.new()
		var shadow_style := StyleBoxFlat.new()
		shadow_style.bg_color = LauncherTokens.CARD_BG
		shadow_style.set_corner_radius_all(roundi(LauncherTokens.RADIUS))
		shadow_style.shadow_color = Color(0, 0, 0, 0.55)
		shadow_style.shadow_size = 36
		shadow_style.shadow_offset = Vector2(0, 18)
		shadow.add_theme_stylebox_override("panel", shadow_style)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(LauncherWidgets.fill(shadow))
		var clip := Panel.new()
		var clip_style := StyleBoxFlat.new()
		clip_style.bg_color = LauncherTokens.CARD_BG
		clip_style.set_corner_radius_all(roundi(LauncherTokens.RADIUS))
		clip.add_theme_stylebox_override("panel", clip_style)
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(LauncherWidgets.fill(clip))
		var art := LauncherKeyArt.new(p_game_id)
		art.name = "Art"
		clip.add_child(LauncherWidgets.fill(art))
		var track := ColorRect.new()
		track.color = Color(0, 0, 0, 0.5)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		track.offset_top = -5
		clip.add_child(track)
		_progress = ColorRect.new()
		_progress.name = "Progress"
		_progress.color = LauncherTokens.FG
		_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress.anchor_top = 1.0
		_progress.anchor_bottom = 1.0
		_progress.anchor_right = 0.0
		_progress.offset_top = -5
		clip.add_child(_progress)
		_badge = _Badge.new()
		_badge.name = "Favorite"
		_badge.visible = false
		_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_badge.offset_left = -42
		_badge.offset_right = -12
		_badge.offset_top = 12
		_badge.offset_bottom = 42
		clip.add_child(_badge)
		_ring = _Outline.new()
		_ring.visible = false
		_frame.add_child(LauncherWidgets.fill(_ring))
		_name = LauncherWidgets.text("", LauncherTokens.SIZE_COVER_NAME, 700, LauncherTokens.FG, 2)
		_name.name = "Name"
		_name.clip_text = true
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(_name)

	func set_title(title: String) -> void:
		_name.text = title

	func title_text() -> String:
		return _name.text

	## Fill of the bar along the bottom of the art, 0..1.
	func set_progress(ratio: float) -> void:
		_progress.anchor_right = clampf(ratio, 0.0, 1.0)

	func progress() -> float:
		return _progress.anchor_right

	func set_favorite(on: bool) -> void:
		_badge.visible = on

	func is_favorite_shown() -> bool:
		return _badge.visible

	func set_selected(on: bool, animate: bool = true) -> void:
		if on == selected and _tween == null:
			return
		selected = on
		var extent := Vector2.ONE * (LauncherTokens.COVER_SCALE if on else 1.0)
		var alpha := 1.0 if on else LauncherTokens.A_COVER_IDLE
		if _tween != null:
			_tween.kill()
			_tween = null
		if animate and is_inside_tree() and is_visible_in_tree():
			_tween = create_tween().set_parallel(true)
			_tween.tween_property(_frame, "scale", extent, LauncherTokens.FADE_COVER)
			_tween.tween_property(self, "modulate:a", alpha, LauncherTokens.FADE_COVER)
			_tween.finished.connect(func() -> void: _tween = null)
		else:
			_frame.scale = extent
			modulate.a = alpha
		_ring.visible = on

	func _gui_input(event: InputEvent) -> void:
		super(event)
		if event is InputEventMouseMotion:
			pointed.emit()

## White outline just outside its parent's rectangle: the selected state of a cover.
class _Outline:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size).grow(LauncherTokens.COVER_RING_OFFSET + LauncherTokens.CARD_RING / 2.0), LauncherTokens.FG, false, LauncherTokens.CARD_RING)

## Heart on a dark disc, top right of a favourite's cover.
class _Badge:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var heart := LauncherControls.Icon.new("heart", 16.0, LauncherTokens.FAVORITE)
		heart.position = Vector2(7, 7)
		heart.size = Vector2(16, 16)
		add_child(heart)

	func _draw() -> void:
		draw_circle(size / 2.0, size.x / 2.0, LauncherTokens.bg(0.7))

## A toolbar button: an optional glyph and a caption. Focused = outlined and tinted; active (a search is applied) = tinted.
class _Chip:
	extends LauncherControls.Pressable

	var focused := false
	var active := false

	var _label: Label

	func _init(action: StringName) -> void:
		super()
		custom_minimum_size = Vector2(0, LauncherTokens.FOOTER_HEIGHT)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		set_padding(12)
		var row := LauncherWidgets.hbox(10)
		add_child(row)
		if action != &"":
			row.add_child(LauncherControls.Glyph.new(action))
		_label = LauncherWidgets.text("", LauncherTokens.SIZE_TOAST, 400, LauncherTokens.fg(LauncherTokens.A_STRONG))
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_label)

	func set_text(caption: String) -> void:
		_label.text = caption

	func text() -> String:
		return _label.text

	func set_focused(on: bool) -> void:
		focused = on
		queue_redraw()

	func set_active(on: bool) -> void:
		active = on
		queue_redraw()

	func _draw() -> void:
		if not focused and not active:
			return
		var box := StyleBoxFlat.new()
		box.bg_color = LauncherTokens.fg(0.16 if focused else 0.12)
		box.set_corner_radius_all(roundi(LauncherTokens.RADIUS))
		if focused:
			box.border_color = LauncherTokens.FG
			box.set_border_width_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))

## One key of the on-screen keyboard. Focused = filled white with dark text. `primary` is the filled "done" button, whose focus is a ring instead.
class _Key:
	extends LauncherControls.Pressable

	var focused := false
	var primary := false

	var _label: Label
	var _latin := false

	func _init(caption: String, latin: bool, p_primary: bool = false) -> void:
		super()
		primary = p_primary
		_latin = latin
		_label = LauncherWidgets.text(caption, LauncherTokens.SIZE_PANEL_ROW if latin else LauncherTokens.SIZE_NAV, 600, LauncherTokens.FG, 0, latin)
		_label.name = "Label"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)
		set_focused(false)

	func set_focused(on: bool) -> void:
		focused = on
		LauncherWidgets.restyle(_label, 700 if primary else 600, LauncherTokens.BG if on or primary else LauncherTokens.FG, 2 if primary else 0, _latin)
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(roundi(LauncherTokens.RADIUS))
		if focused or primary:
			box.bg_color = LauncherTokens.FG
		else:
			box.bg_color = LauncherTokens.fg(0.06)
			box.border_color = LauncherTokens.fg(0.2)
			box.set_border_width_all(1)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		if focused and primary:
			draw_rect(Rect2(Vector2.ZERO, size).grow(LauncherTokens.CARD_RING_OFFSET + LauncherTokens.CARD_RING / 2.0), LauncherTokens.FG, false, LauncherTokens.CARD_RING)

## The search text: large spaced capitals over a 2px line.
class _Field:
	extends MarginContainer

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 56)
		add_theme_constant_override("margin_left", 18)
		add_theme_constant_override("margin_right", 18)

	func _draw() -> void:
		draw_rect(Rect2(0, size.y - 2.0, size.x, 2.0), LauncherTokens.FG)

## Root of the search layer. While it is in the tree it offers every key press to `on_key` before the launcher turns it into an action, so letters can be typed even though several of them are bound to buttons.
class _SearchLayer:
	extends Control

	var on_key: Callable

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and on_key.is_valid() and on_key.call(event):
			get_viewport().set_input_as_handled()

## Dimmed click-away area behind the search dialog.
class _Scrim:
	extends LauncherControls.Pressable

	func _init() -> void:
		super()
		mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), LauncherTokens.deep(0.5))
