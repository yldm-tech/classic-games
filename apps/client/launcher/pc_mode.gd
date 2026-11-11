class_name LauncherPcMode
extends Control

## PC mode: the mouse-and-keyboard layout that takes the console screens' place when the player presses F11 or holds View. LauncherRoot mounts it through register_pc_mode / toggle_pc_mode, calls setup(shell) once and hands it every LauncherInput action through handle_action while the mode is on.
##
## Layout: a title strip with the way back to console mode, a sidebar (search, categories, the library entry, the game list, the settings entry), the main area showing either the selected game's page (LauncherPcDetailView) or the library (LauncherPcLibraryView), and a status line. The application runs in a real OS window, so the strip draws no minimise / maximise / close buttons of its own.
##
## It is a second view of the same data as the console screens: games come from LauncherCatalog, everything about the player from shell.store, and a game is started exactly as Home starts one, by showing LauncherRoot.GAME. Because the console layers are hidden while PC mode is on, anything that needs a console screen (a running game, the game menu, the full achievements screen, Settings) is an excursion: PC mode switches to console mode, opens that screen, and comes back when the excursion is over (see _on_screen_changed for the one rule that decides that).
##
## Pointer: hover and pressed states live in the widgets; a click selects, a double click starts a game, a right click opens the game's menu, the wheel scrolls. Keyboard and gamepad: focus is a zone (search, sidebar, main) plus a position in that zone's rows of widgets. Tab / Shift+Tab change zone, the arrows move inside it and across its edges, Enter activates (on a game: starts it), Ctrl+F or "/" jump to the search field, Esc clears the search, Y toggles the favourite, M opens the game's menu, Q / E switch between the game page and the library, PageUp / PageDown scroll.

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")
const In := preload("res://launcher/launcher_input.gd")
const P := preload("res://launcher/pc_tokens.gd")
const PC := preload("res://launcher/pc_controls.gd")
const Lib := preload("res://launcher/pc_library.gd")
const DetailView := preload("res://launcher/pc_detail_view.gd")
const LibraryView := preload("res://launcher/pc_library_view.gd")

const VIEW_DETAIL := &"detail"
const VIEW_LIBRARY := &"library"
const LAYOUT_GRID := &"grid"
const LAYOUT_LIST := &"list"
const ZONE_SEARCH := &"search"
const ZONE_SIDEBAR := &"sidebar"
const ZONE_MAIN := &"main"
const ZONES: Array[StringName] = [ZONE_SEARCH, ZONE_SIDEBAR, ZONE_MAIN]

## Store settings PC mode remembers between sessions.
const SETTING_SORT := "pc_sort"
const SETTING_LAYOUT := "pc_layout"

var shell: LauncherRoot
var view := VIEW_DETAIL
## Id of the selected game. It follows Home's hero when PC mode is entered and is handed back to Home when it is left.
var selected := ""
var query := ""
var category := Lib.CAT_ALL
## Genre filter key (LauncherPcLibrary.genre_key), "" for every genre.
var genre := ""
var sort := Lib.SORT_NAME
var layout := LAYOUT_GRID
var tab := DetailView.TAB_OVERVIEW
var only_locked := false
var zone := ZONE_SIDEBAR
## Whether the keyboard focus ring is drawn. A key or gamepad press turns it on, a mouse press turns it off.
var focus_visible := false
## Opens a folder in the system file manager. Tests replace it.
var folder_opener := func(path: String) -> void: OS.shell_open(path)

var _entries: Array[Dictionary] = LauncherCatalog.all()
var _results: Array[Dictionary] = []
var _focus := {ZONE_SIDEBAR: Vector2i.ZERO, ZONE_MAIN: Vector2i.ZERO}
var _ringed: LauncherPcControls.Clickable
var _excursion := &""
var _built_locale := ""
var _search: LauncherPcControls.SearchField
var _category_rows: Dictionary = {}
var _library_row: LauncherPcControls.SideRow
var _list_title: Label
var _list_scroll: ScrollContainer
var _list_box: VBoxContainer
var _game_rows: Dictionary = {}
var _list_signature := ""
var _settings: LauncherPcControls.IconButton
var _console: LauncherPcControls.Pill
var _main: Control
var _detail: LauncherPcDetailView
var _library: LauncherPcLibraryView
var _status_dot: Control
var _status: Label
var _overlay: Control
var _menu: LauncherPcControls.Menu
var _menu_actions: Array = []
## Where the pointer last was, in this control's coordinates. Taken from the mouse events themselves, so a menu opens exactly where the click that asked for it happened.
var _pointer := Vector2.ZERO

func setup(p_shell: LauncherRoot) -> void:
	shell = p_shell
	name = "PcMode"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stored_sort := StringName(str(shell.store.setting(SETTING_SORT, Lib.SORT_NAME)))
	sort = stored_sort if stored_sort in Lib.SORTS else Lib.SORT_NAME
	layout = LAYOUT_LIST if str(shell.store.setting(SETTING_LAYOUT, LAYOUT_GRID)) == LAYOUT_LIST else LAYOUT_GRID
	_build()
	shell.store.changed.connect(_on_store_changed)
	shell.mode_changed.connect(_on_mode_changed)
	shell.screen_changed.connect(_on_screen_changed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)

func t(key: String) -> String:
	return shell.t(key)

func tf(key: String, args: Array) -> String:
	return shell.tf(key, args)

# ---- data ----

## The games PC mode offers: the catalog. Tests and the screenshot tool replace it to try the layout with many more games than the catalog has; entries the catalog does not know are listed but cannot be started.
func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries
	_refresh()

func entry(game_id: String) -> Dictionary:
	for item in _entries:
		if item["id"] == game_id:
			return item
	return {}

## The games that pass the category, the search text and the genre, in the current order.
func results() -> Array[Dictionary]:
	return _results

func result_ids() -> Array[String]:
	var out: Array[String] = []
	for item in _results:
		out.append(str(item["id"]))
	return out

func is_filtered() -> bool:
	return category != Lib.CAT_ALL or genre != "" or query.strip_edges() != ""

func _game_model(item: Dictionary) -> Dictionary:
	var id := str(item["id"])
	var stats := shell.store.stats(id)
	var played := int(stats["runs"]) > 0
	var day := LauncherFormat.when_day(int(stats["last_played"]), shell.now(), shell.locale)
	var genre_label := LauncherCatalog.text(item, "genre", shell.locale)
	var players := LauncherCatalog.players_label(item)
	return {
		"id": id,
		"name": LauncherCatalog.text(item, "name", shell.locale),
		"genre": genre_label,
		"players": players,
		"status": tf("launcher.pc.last_played_fmt", [day]) if played else t("launcher.home.never_played"),
		"meta": "%s · %s · %s" % [genre_label, players, day],
		"time": LauncherFormat.play_time(float(stats["play_seconds"]), shell.locale) if played else t("launcher.pc.stat.none"),
		"ratio": Lib.achievement_ratio(item, shell.store),
		"favorite": shell.store.is_favorite(id),
		"selected": id == selected,
	}

# ---- construction ----

func _build() -> void:
	W.clear(self)
	_ringed = null
	_menu = null
	_category_rows.clear()
	_game_rows.clear()
	# The rows of the old results are gone with the old tree; the next refresh lists them again.
	_results = []
	_list_signature = ""
	_built_locale = shell.locale

	var background := ColorRect.new()
	background.name = "Background"
	background.color = P.WINDOW_BG
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(W.fill(background))
	var frame := W.vbox(0)
	frame.name = "Frame"
	add_child(W.fill(frame))
	frame.add_child(_build_title())
	var body := W.hbox(0)
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(body)
	body.add_child(_build_sidebar())
	_main = Control.new()
	_main.name = "Main"
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main.clip_contents = true
	body.add_child(_main)
	_detail = DetailView.new()
	_detail.setup(shell)
	_main.add_child(W.fill(_detail))
	_detail.play_pressed.connect(func() -> void: play(selected))
	_detail.menu_pressed.connect(func() -> void: open_console(LauncherRoot.MENU, {"game": selected}))
	_detail.favorite_pressed.connect(func() -> void: toggle_favorite(selected))
	_detail.more_pressed.connect(func() -> void: open_game_menu(selected, _detail.more_button(), true))
	_detail.tab_picked.connect(set_tab)
	_detail.only_locked_toggled.connect(func() -> void:
		only_locked = not only_locked
		_refresh())
	_detail.all_achievements_pressed.connect(func() -> void: open_console(LauncherRoot.ACHIEVEMENTS, {"game": selected}))
	_library = LibraryView.new()
	_library.setup(shell)
	_main.add_child(W.fill(_library))
	_library.game_picked.connect(select)
	_library.game_played.connect(play)
	_library.game_context.connect(func(id: String) -> void:
		select(id)
		open_game_menu(id))
	_library.favorite_pressed.connect(toggle_favorite)
	_library.sort_pressed.connect(open_sort_menu)
	_library.layout_picked.connect(set_layout)
	_library.genre_picked.connect(set_genre)
	_library.clear_pressed.connect(clear_filters)
	frame.add_child(_build_status())
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_overlay))

## A chrome band (title strip, sidebar, status line): the darker background with a hairline on one side. `pad` is the content margin, x horizontal and y vertical.
func _strip(border_side: Side, height: float, pad: Vector2 = Vector2.ZERO) -> PanelContainer:
	var strip := PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.custom_minimum_size = Vector2(0, height)
	var style := StyleBoxFlat.new()
	style.bg_color = T.BG
	style.border_color = P.LINE
	style.set_border_width(border_side, 1)
	style.content_margin_left = pad.x
	style.content_margin_right = pad.x
	style.content_margin_top = pad.y
	style.content_margin_bottom = pad.y
	strip.add_theme_stylebox_override("panel", style)
	return strip

func _build_title() -> Control:
	var strip := _strip(SIDE_BOTTOM, P.TITLE_HEIGHT)
	strip.name = "TitleStrip"
	var row := W.hbox(10)
	strip.add_child(row)
	var inset := Control.new()
	inset.custom_minimum_size = Vector2(6, 0)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(inset)
	row.add_child(PC.Symbol.new("pad", 16.0))
	var brand := W.text(t("launcher.brand"), P.SIZE_TEXT, 700, T.FG, 3)
	brand.name = "Brand"
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)
	_console = PC.Pill.new(t("launcher.pc.console_mode"), PC.Pill.QUIET, 28.0, P.SIZE_NOTE, 12.0, "pad", 1.0)
	_console.name = "ConsoleMode"
	_console.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_console.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_console.add_keycap("F11")
	_console.activated.connect(func() -> void: shell.toggle_pc_mode())
	row.add_child(_console)
	var outset := Control.new()
	outset.custom_minimum_size = Vector2(2, 0)
	outset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(outset)
	return strip

func _build_sidebar() -> Control:
	var panel := _strip(SIDE_RIGHT, 0.0, P.SIDEBAR_PADDING)
	panel.name = "Sidebar"
	panel.custom_minimum_size = Vector2(P.SIDEBAR_WIDTH, 0)
	var column := W.vbox(0)
	panel.add_child(column)

	_search = PC.SearchField.new(t("launcher.pc.search.placeholder"))
	_search.name = "Search"
	_search.edit.text = query
	_search.edit.text_changed.connect(_on_query_typed)
	_search.edit.gui_input.connect(_on_search_input)
	_search.edit.focus_entered.connect(func() -> void: zone = ZONE_SEARCH)
	_search.clear_pressed.connect(func() -> void: set_query(""))
	column.add_child(_search)
	column.add_child(_gap(18))

	var categories := W.vbox(1)
	categories.name = "Categories"
	column.add_child(categories)
	for id in Lib.CATEGORIES:
		var row := PC.SideRow.new(t("launcher.pc.cat.%s" % id))
		row.name = "Category_%s" % id
		row.activated.connect(func() -> void: set_category(id))
		categories.add_child(row)
		_category_rows[id] = row
	_library_row = PC.SideRow.new(t("launcher.pc.open_library"), true)
	_library_row.name = "OpenLibrary"
	_library_row.activated.connect(func() -> void: set_view(VIEW_LIBRARY))
	categories.add_child(_library_row)

	var heading := MarginContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("margin_left", 12)
	heading.add_theme_constant_override("margin_top", 18)
	heading.add_theme_constant_override("margin_bottom", 8)
	_list_title = W.text("", P.SIZE_LABEL, 600, P.TEXT_MUTED, 3, true)
	_list_title.name = "ListTitle"
	heading.add_child(_list_title)
	column.add_child(heading)
	_list_scroll = PC.Paint.scroll()
	_list_scroll.name = "GameList"
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_list_scroll)
	_list_box = W.vbox(2)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list_box)

	column.add_child(_gap(12))
	column.add_child(W.rule(P.LINE))
	column.add_child(_gap(12))
	var footer := W.hbox(10)
	footer.name = "Footer"
	column.add_child(footer)
	var edge := Control.new()
	edge.custom_minimum_size = Vector2(0, 0)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(edge)
	footer.add_child(_PlayerBadge.new())
	var player := W.text(t("launcher.pc.local_player"), P.SIZE_TEXT)
	player.name = "Player"
	player.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(player)
	_settings = PC.IconButton.new("sliders", 36.0, 18.0, PC.IconButton.PLAIN)
	_settings.name = "Settings"
	_settings.tooltip_text = t("launcher.nav.settings")
	_settings.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_settings.activated.connect(func() -> void: open_console(LauncherRoot.SETTINGS))
	footer.add_child(_settings)
	return panel

func _build_status() -> Control:
	var strip := _strip(SIDE_TOP, P.STATUS_HEIGHT, Vector2(16, 0))
	strip.name = "StatusLine"
	var row := W.hbox(8)
	strip.add_child(row)
	_status_dot = Control.new()
	_status_dot.custom_minimum_size = Vector2(7, 7)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_dot.draw.connect(func() -> void: _status_dot.draw_circle(_status_dot.size / 2.0, 3.5, P.OK if _gamepads() > 0 else P.TEXT_MUTED, true, -1.0, true))
	row.add_child(_status_dot)
	_status = W.text("", P.SIZE_NOTE, 400, P.TEXT_MUTED)
	_status.name = "Status"
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status)
	var version := W.text(tf("launcher.pc.status.local_fmt", [str(ProjectSettings.get_setting("application/config/version", ""))]), P.SIZE_NOTE, 400, P.TEXT_MUTED, 1)
	version.name = "Version"
	version.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(version)
	return strip

func _gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

func _gamepads() -> int:
	return Input.get_connected_joypads().size()

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_sync_status()

func _sync_status() -> void:
	var count := _gamepads()
	_status.text = tf("launcher.pc.status.pads_fmt", [count]) if count > 0 else t("launcher.pc.status.no_pads")
	_status_dot.queue_redraw()

# ---- rendering ----

func _refresh() -> void:
	if shell == null or _detail == null:
		return
	if entry(selected).is_empty() and not _entries.is_empty():
		selected = str(_entries[0]["id"])
	# Keyboard focus that sits on a game follows that game when the list around it changes.
	var focused := focused_widget() if zone != ZONE_SEARCH else null
	var on_game := focused != null and is_instance_valid(focused) and focused.get("game_id") is String
	_results = Lib.visible(_entries, shell.store, category, query, genre, sort, shell.locale)
	for id: StringName in _category_rows:
		var row: LauncherPcControls.SideRow = _category_rows[id]
		row.set_selected(id == category)
		row.set_count(Lib.count_in(_entries, id, shell.store))
	_library_row.set_selected(view == VIEW_LIBRARY)
	_list_title.text = tf("launcher.pc.list.results_fmt", [_results.size()]) if is_filtered() else t("launcher.pc.list.games")
	_sync_game_rows()
	_detail.visible = view == VIEW_DETAIL
	_library.visible = view == VIEW_LIBRARY
	if view == VIEW_DETAIL:
		_detail.show_game(entry(selected), tab, only_locked)
	else:
		var models: Array = []
		for item in _results:
			models.append(_game_model(item))
		_library.show_list({
			"title": t("launcher.pc.cat.%s" % category),
			"models": models,
			"layout": layout,
			"sort_label": t("launcher.pc.sort.%s" % sort),
			"genres": Lib.genres(_entries, shell.locale),
			"genre": genre,
			"total": _entries.size(),
			"query": query,
			"filtered": is_filtered(),
		})
	_sync_status()
	if on_game:
		var at := _position_in(zone, _game_widget(selected, zone))
		if at.x >= 0:
			_focus[zone] = at
	_apply_focus()

func _sync_game_rows() -> void:
	var ids := result_ids()
	var signature := ",".join(ids)
	if signature != _list_signature or _list_box.get_child_count() == 0:
		_list_signature = signature
		W.clear(_list_box)
		_game_rows.clear()
		_ringed = null
		for id in ids:
			var row := PC.GameRow.new(id)
			row.name = "Row_%s" % id
			row.activated.connect(func() -> void:
				select(id)
				set_view(VIEW_DETAIL))
			row.double_clicked.connect(func() -> void: play(id))
			row.context_requested.connect(func() -> void:
				select(id)
				open_game_menu(id))
			_list_box.add_child(row)
			_game_rows[id] = row
		if ids.is_empty():
			var empty := W.text(t("launcher.pc.list.empty"), P.SIZE_TEXT, 400, P.TEXT_MUTED)
			empty.name = "ListEmpty"
			var holder := MarginContainer.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_theme_constant_override("margin_left", 12)
			holder.add_theme_constant_override("margin_top", 12)
			holder.add_child(empty)
			_list_box.add_child(holder)
	for item in _results:
		(_game_rows[str(item["id"])] as LauncherPcControls.GameRow).update(_game_model(item))

func _on_store_changed(_section: StringName) -> void:
	if visible:
		_refresh()

# ---- state changes ----

func select(game_id: String) -> void:
	if entry(game_id).is_empty():
		return
	selected = game_id
	if zone != ZONE_SEARCH:
		_focus_on(_game_widget(game_id, zone))
	_refresh()

func set_view(value: StringName) -> void:
	view = value
	_refresh()
	if zone == ZONE_MAIN:
		_enter_zone(ZONE_MAIN)

func set_category(value: StringName) -> void:
	category = value
	_refresh()

func set_genre(key: String) -> void:
	genre = key
	_refresh()

func set_sort(value: StringName) -> void:
	sort = value
	shell.store.set_setting(SETTING_SORT, String(value))
	_refresh()

func set_layout(value: StringName) -> void:
	layout = value
	shell.store.set_setting(SETTING_LAYOUT, String(value))
	_refresh()

func set_tab(index: int) -> void:
	tab = index
	_refresh()

## Replace the search text, as typing it would.
func set_query(text: String) -> void:
	query = text
	_search.set_text(text)
	_refresh()

func _on_query_typed(text: String) -> void:
	query = text
	_refresh()

func clear_filters() -> void:
	category = Lib.CAT_ALL
	genre = ""
	set_query("")

func toggle_favorite(game_id: String) -> void:
	var was := shell.store.is_favorite(game_id)
	var title := LauncherCatalog.text(entry(game_id), "name", shell.locale)
	shell.store.set_favorite(game_id, not was)
	shell.toast(tf("launcher.home.unfavorited_fmt" if was else "launcher.home.favorited_fmt", [title]), func() -> void: shell.store.set_favorite(game_id, was))

func remove_recent(game_id: String) -> void:
	var index := shell.store.remove_recent(game_id)
	if index < 0:
		return
	var title := LauncherCatalog.text(entry(game_id), "name", shell.locale)
	shell.toast(tf("launcher.home.removed_recent_fmt", [title]), func() -> void: shell.store.restore_recent(game_id, index))

# ---- leaving for a console screen ----

## Start a game the way Home does: through the GAME screen, which runs it on the shell's game host. PC mode steps aside for the run and returns when the player leaves it.
func play(game_id: String) -> void:
	if entry(game_id).is_empty():
		return
	selected = game_id
	if not LauncherCatalog.has(game_id):
		shell.toast(tf("launcher.game.error_fmt", [LauncherCatalog.text(entry(game_id), "name", shell.locale)]))
		return
	open_console(LauncherRoot.GAME, {"game": game_id})

## Show a console screen from PC mode: switch to console mode, open the screen, and remember to come back. _on_screen_changed decides when the excursion is over.
func open_console(screen_id: StringName, args: Dictionary = {}) -> void:
	close_menu()
	# Every excursion starts from Home, whatever console screen PC mode was entered from, so backing out of the borrowed screen always arrives at Home.
	if shell.current_id() != LauncherRoot.HOME:
		shell.go(LauncherRoot.HOME)
	_excursion = screen_id
	shell.toggle_pc_mode()
	shell.go(screen_id, args)

## Id of the console screen PC mode stepped aside for, &"" when there is none.
func excursion() -> StringName:
	return _excursion

## The one rule for coming back from an excursion: it is over when the console shell arrives at Home, and PC mode takes the canvas back at that moment. Backing out of the borrowed screen, "home" on a result and a launch that failed all arrive there by themselves.
## An excursion that went straight into a game has one more exit. The game flow leaves a run that is over for that game's menu (quit confirmed on the pause screen, "game menu" or B on the result); the player never opened that menu, so the shell is sent on to Home, which ends the excursion. Opened from the menu excursion instead, the same exits stay on the menu the player came from.
## The player toggling the mode himself also ends the excursion (see _on_mode_changed).
func _on_screen_changed(id: StringName) -> void:
	if _excursion == &"" or shell.mode == LauncherRoot.MODE_PC:
		return
	if id == LauncherRoot.HOME:
		shell.toggle_pc_mode()
	elif id == LauncherRoot.MENU and _excursion == LauncherRoot.GAME:
		shell.go(LauncherRoot.HOME)

func _on_mode_changed(mode: StringName) -> void:
	var home := shell.screen(LauncherRoot.HOME)
	if mode == LauncherRoot.MODE_PC:
		# Coming back from an excursion keeps the game PC mode had selected: the borrowed screens were about that game. Only when the player was in console mode on his own does the selection follow what he looked at there.
		var returning := _excursion != &""
		_excursion = &""
		var from_console := str(home.get("hero_id"))
		if shell.current_id() == LauncherRoot.GAME and not entry(shell.game_host.game_id()).is_empty():
			from_console = shell.game_host.game_id()
		if not returning and not entry(from_console).is_empty():
			selected = from_console
		if _built_locale != shell.locale:
			_build()
		focus_visible = false
		_refresh()
		return
	close_menu()
	_release_search()
	if not LauncherCatalog.has(selected):
		return
	# Home shows the game that was selected here. While another console screen is being opened from PC mode only the value is handed over; Home reads it the next time it is entered.
	if _excursion == &"" and shell.current_id() == LauncherRoot.HOME:
		shell.go(LauncherRoot.HOME, {"game": selected})
	else:
		home.set("hero_id", selected)

# ---- menus ----

func is_menu_open() -> bool:
	return _menu != null

func menu_labels() -> PackedStringArray:
	return _menu.labels() if _menu != null else PackedStringArray()

## The menu of one game (right click, the "more" button, the Menu button): start, open its page, favourite, the console game menu, its achievements, take it off the recents, open the folder the profile is saved in. Without an `anchor` it opens at the pointer; with one it opens over that widget, or above it when `upward` is set.
func open_game_menu(game_id: String, anchor: Control = null, upward: bool = false) -> void:
	var item := entry(game_id)
	if item.is_empty():
		return
	var favorite := shell.store.is_favorite(game_id)
	var items: Array = [{"label": t("launcher.home.start"), "run": func() -> void: play(game_id)}]
	if view == VIEW_LIBRARY:
		items.append({"label": t("launcher.pc.menu.details"), "run": func() -> void:
			select(game_id)
			set_view(VIEW_DETAIL)})
	items.append({"label": t("launcher.home.remove_favorite" if favorite else "launcher.home.add_favorite"), "run": func() -> void: toggle_favorite(game_id)})
	if LauncherCatalog.has(game_id):
		items.append({"label": t("launcher.home.menu"), "run": func() -> void:
			selected = game_id
			open_console(LauncherRoot.MENU, {"game": game_id})})
	items.append({"label": t("launcher.home.view_achievements"), "run": func() -> void:
		select(game_id)
		tab = DetailView.TAB_ACHIEVEMENTS
		set_view(VIEW_DETAIL)})
	if shell.store.recents().has(game_id):
		items.append({"label": t("launcher.home.remove_recent"), "run": func() -> void: remove_recent(game_id)})
	items.append(null)
	items.append({"label": t("launcher.pc.menu.open_saves"), "run": func() -> void: folder_opener.call(ProjectSettings.globalize_path(shell.store.path.get_base_dir()))})
	if anchor == null or not anchor.is_inside_tree():
		_open_menu(items, _pointer)
	elif upward:
		_open_menu(items, anchor.global_position - global_position - Vector2(0, 8), true)
	else:
		_open_menu(items, anchor.global_position - global_position + Vector2(24, 24))

func open_sort_menu() -> void:
	var items: Array = []
	for id in Lib.SORTS:
		items.append({"label": t("launcher.pc.sort.%s" % id), "checked": id == sort, "run": func() -> void: set_sort(id)})
	var button := _library.sort_button()
	_open_menu(items, button.global_position - global_position + Vector2(0, button.size.y + 8.0))

## Show a menu with its top-left corner at `at` (its bottom-left when `upward`), kept inside the canvas. Each item is { label, run, checked? }; null is a separator.
func _open_menu(items: Array, at: Vector2, upward: bool = false) -> void:
	close_menu()
	_menu_actions = items
	var scrim := PC.Clickable.new()
	scrim.name = "Scrim"
	scrim.mouse_default_cursor_shape = Control.CURSOR_ARROW
	scrim.activated.connect(close_menu)
	scrim.context_requested.connect(close_menu)
	_overlay.add_child(W.fill(scrim))
	_menu = PC.Menu.new(items)
	_menu.name = "Menu"
	_menu.picked.connect(_on_menu_picked)
	_overlay.add_child(_menu)
	_menu.reset_size()
	if upward:
		at.y -= _menu.size.y
	var limit := (size - _menu.size - Vector2(8, 8)).max(Vector2(8, 8))
	_menu.position = at.clamp(Vector2(8, 8), limit)

func close_menu() -> void:
	if _menu == null:
		return
	_menu = null
	_menu_actions = []
	W.clear(_overlay)

func _on_menu_picked(item: int) -> void:
	var action: Callable = _menu_actions[item]["run"]
	close_menu()
	action.call()

# ---- focus ----

## The widgets of a zone that keyboard focus can visit, as rows from the top.
func focus_rows(of_zone: StringName) -> Array:
	if of_zone == ZONE_SIDEBAR:
		var rows: Array = []
		for id in Lib.CATEGORIES:
			rows.append([_category_rows[id]])
		rows.append([_library_row])
		for id in result_ids():
			rows.append([_game_rows[id]])
		rows.append([_settings])
		return rows
	if of_zone == ZONE_MAIN:
		return _detail.focus_rows() if view == VIEW_DETAIL else _library.focus_rows()
	return []

## The widget under keyboard focus, or null (the search field has Godot's own focus instead).
func focused_widget() -> Control:
	var rows := focus_rows(zone)
	if rows.is_empty():
		return null
	var at: Vector2i = _focus[zone]
	var row: Array = rows[clampi(at.y, 0, rows.size() - 1)]
	return row[clampi(at.x, 0, row.size() - 1)]

## The widget that stands for a game in a zone: its card or row in the library, its row in the sidebar list. Null when the game is not listed there.
func _game_widget(game_id: String, in_zone: StringName) -> Control:
	if in_zone == ZONE_MAIN:
		return _library.item(game_id) if view == VIEW_LIBRARY else null
	return _game_rows.get(game_id)

## Where `widget` sits in a zone's rows (x = column, y = row), or (-1, -1).
func _position_in(of_zone: StringName, widget: Control) -> Vector2i:
	var rows := focus_rows(of_zone)
	for y in rows.size():
		var x := (rows[y] as Array).find(widget)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)

## Put keyboard focus on `widget` when it is one of the focusable ones (used after a click, so the arrows continue from where the pointer was).
func _focus_on(widget: Control) -> bool:
	if widget == null:
		return false
	for candidate: StringName in [ZONE_SIDEBAR, ZONE_MAIN]:
		var at := _position_in(candidate, widget)
		if at.x >= 0:
			_release_search()
			zone = candidate
			_focus[candidate] = at
			return true
	return false

## Move keyboard focus into a zone: onto the selected game when the zone lists it, else onto the zone's natural start (the current category, the first control of the page).
func _enter_zone(target: StringName) -> void:
	if target == ZONE_SEARCH:
		focus_search()
		return
	_release_search()
	zone = target
	var landing := _game_widget(selected, target)
	if landing == null and target == ZONE_SIDEBAR:
		landing = _category_rows[category]
	var at := _position_in(target, landing) if landing != null else Vector2i(-1, -1)
	_focus[target] = at if at.x >= 0 else Vector2i.ZERO
	_apply_focus()

func _cycle_zone(step: int) -> void:
	focus_visible = true
	_enter_zone(ZONES[posmod(ZONES.find(zone) + step, ZONES.size())])

func focus_search() -> void:
	close_menu()
	zone = ZONE_SEARCH
	_search.edit.grab_focus()
	# Focus that arrives while an arrow key is held (Up from the top of the sidebar) would otherwise wait for Enter before accepting text.
	_search.edit.edit()
	_apply_focus()

func _release_search() -> void:
	if _search != null and _search.edit.has_focus():
		_search.edit.release_focus()

## Leave the search field for the first result (or, with none, for the sidebar).
func _search_to_results() -> void:
	focus_visible = true
	_release_search()
	if not _results.is_empty():
		selected = str(_results[0]["id"])
	zone = ZONE_MAIN if view == VIEW_LIBRARY and not _results.is_empty() else ZONE_SIDEBAR
	_refresh()
	_enter_zone(zone)

func _apply_focus() -> void:
	var widget := focused_widget() as LauncherPcControls.Clickable if zone != ZONE_SEARCH else null
	if is_instance_valid(_ringed) and _ringed != widget:
		_ringed.set_focus_ring(false)
	_ringed = widget
	if widget != null:
		widget.set_focus_ring(focus_visible)
		if focus_visible:
			_reveal.call_deferred(widget)

func _reveal(widget: Control) -> void:
	if not is_instance_valid(widget) or not widget.is_inside_tree():
		return
	var parent := widget.get_parent()
	while parent != null and parent != self:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(widget)
			return
		parent = parent.get_parent()

func _move(step: Vector2i) -> void:
	focus_visible = true
	if zone == ZONE_SEARCH:
		if step.y > 0:
			_search_to_results()
		return
	var rows := focus_rows(zone)
	var at: Vector2i = _focus[zone]
	at.y = clampi(at.y, 0, rows.size() - 1)
	at.x = clampi(at.x, 0, (rows[at.y] as Array).size() - 1)
	if step.x != 0:
		var x := at.x + step.x
		if x < 0:
			if zone == ZONE_MAIN:
				_enter_zone(ZONE_SIDEBAR)
			return
		if x >= (rows[at.y] as Array).size():
			if zone == ZONE_SIDEBAR:
				_enter_zone(ZONE_MAIN)
			return
		at.x = x
	if step.y != 0:
		var y := at.y + step.y
		if y < 0:
			if zone == ZONE_SIDEBAR:
				focus_search()
			return
		if y >= rows.size():
			return
		at = Vector2i(_nearest(rows[y], rows[at.y][at.x]), y)
	_focus[zone] = at
	var widget: Control = rows[at.y][at.x]
	var id: Variant = widget.get("game_id")
	if id is String and id != selected:
		selected = id
		_refresh()
	else:
		_apply_focus()

## Index of the widget in `row` whose centre is horizontally closest to `from`.
func _nearest(row: Array, from: Control) -> int:
	var x := from.global_position.x + from.size.x / 2.0
	var best := 0
	var best_distance := INF
	for index in row.size():
		var candidate: Control = row[index]
		var distance := absf(candidate.global_position.x + candidate.size.x / 2.0 - x)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best

func _activate() -> void:
	focus_visible = true
	var widget := focused_widget()
	if widget == null:
		return
	var id: Variant = widget.get("game_id")
	if id is String:
		play(id)
	else:
		(widget as LauncherPcControls.Clickable).activated.emit()

## The Menu button has no pointer to open at: the menu opens over the selected game where the current zone shows it, else above the page's "more" button, else under the library's sort control.
func _open_menu_from_keyboard() -> void:
	var anchor := _game_widget(selected, zone) if zone != ZONE_SEARCH else null
	if anchor != null:
		open_game_menu(selected, anchor)
	elif view == VIEW_DETAIL:
		open_game_menu(selected, _detail.more_button(), true)
	else:
		open_game_menu(selected, _library.sort_button())

func _scroll_page(step: int) -> void:
	var area := _detail.scroll_area() if view == VIEW_DETAIL else _library.scroll_area()
	area.scroll_vertical += roundi(step * area.size.y * 0.9)

# ---- input ----

## Every LauncherInput action while PC mode is on. It uses all of them: nothing falls through to the console shell.
func handle_action(action: StringName) -> bool:
	if _menu != null:
		match action:
			In.UP:
				_menu.move(-1)
			In.DOWN:
				_menu.move(1)
			In.ACCEPT:
				_menu.pick_current()
			In.BACK, In.MENU:
				close_menu()
		return true
	match action:
		In.UP:
			_move(Vector2i.UP)
		In.DOWN:
			_move(Vector2i.DOWN)
		In.LEFT:
			_move(Vector2i.LEFT)
		In.RIGHT:
			_move(Vector2i.RIGHT)
		In.VIEW:
			_cycle_zone(1)
		In.ACCEPT:
			_activate()
		In.BACK:
			if query != "":
				set_query("")
		In.Y:
			toggle_favorite(selected)
		In.X:
			if shell.can_undo():
				shell.undo()
			elif view == VIEW_LIBRARY:
				set_view(VIEW_DETAIL)
		In.MENU:
			_open_menu_from_keyboard()
		In.LB, In.RB:
			set_view(VIEW_LIBRARY if view == VIEW_DETAIL else VIEW_DETAIL)
		In.LT:
			_scroll_page(-1)
		In.RT:
			_scroll_page(1)
	return true

## Keys that are not launcher actions: Ctrl+F (Cmd+F) and "/" jump to the search field, Shift+Tab goes to the previous zone. Returns true when the key was used.
func handle_key(key: InputEventKey) -> bool:
	if not key.pressed or key.echo or _menu != null:
		return false
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	var command := key.ctrl_pressed or key.meta_pressed
	if (code == KEY_F and command) or (code == KEY_SLASH and not command and not key.alt_pressed and not key.shift_pressed):
		focus_search()
		return true
	if code == KEY_TAB and key.shift_pressed:
		_cycle_zone(-1)
		return true
	return false

func _unhandled_key_input(event: InputEvent) -> void:
	if shell == null or shell.mode != LauncherRoot.MODE_PC:
		return
	if event is InputEventKey and handle_key(event):
		get_viewport().set_input_as_handled()

## Keys pressed while the search field has focus. The field keeps everything it needs for typing; Esc clears the text (or leaves the field when it is empty), Enter and Down go to the results, Tab changes zone.
func _on_search_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	match code:
		KEY_ESCAPE:
			if query != "":
				set_query("")
			else:
				_enter_zone(ZONE_SIDEBAR)
		KEY_ENTER, KEY_KP_ENTER, KEY_DOWN:
			_search_to_results()
		KEY_TAB:
			_cycle_zone(-1 if key.shift_pressed else 1)
		_:
			return
	_search.edit.accept_event()

func _input(event: InputEvent) -> void:
	if shell == null or shell.mode != LauncherRoot.MODE_PC or not is_visible_in_tree():
		return
	if event is InputEventMouse:
		_pointer = (make_input_local(event) as InputEventMouse).position
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or not (button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		return
	# A mouse press hides the keyboard focus ring, takes typing focus off the search field unless the press is on it, and moves keyboard focus to the pressed widget.
	focus_visible = false
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or not (hovered == _search or _search.is_ancestor_of(hovered)):
		_release_search()
		if zone == ZONE_SEARCH:
			zone = ZONE_SIDEBAR
	while hovered != null and hovered != self and not _focus_on(hovered):
		hovered = hovered.get_parent() as Control
	_apply_focus()

## The ringed "P1" mark of the local profile.
class _PlayerBadge:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(32, 32)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_arc(size / 2.0, 15.0, 0.0, TAU, 48, LauncherTokens.FG, 2.0, true)
		var face := LauncherTokens.font(800, 0, true)
		var extent := face.get_string_size("P1", HORIZONTAL_ALIGNMENT_LEFT, -1, LauncherPcTokens.SIZE_LABEL)
		var baseline := (size.y - face.get_height(LauncherPcTokens.SIZE_LABEL)) / 2.0 + face.get_ascent(LauncherPcTokens.SIZE_LABEL)
		draw_string(face, Vector2((size.x - extent.x) / 2.0, baseline), "P1", HORIZONTAL_ALIGNMENT_LEFT, -1, LauncherPcTokens.SIZE_LABEL, LauncherTokens.FG)
