class_name LauncherAchievementsScreen
extends LauncherScreen

## Achievements: the overall count, a game switcher on the left, the achievements of the chosen game (or of every game) in the middle, and the details of the picked one on the right.
##
## Definitions come from LauncherCatalog and the unlocked state and time from LauncherStore, which only LauncherGameHost writes after a real run. An unlock the catalog no longer defines is not counted. There are no rarity figures and no leaderboards, because nothing local could back them.
##
## Focus: two zones. In `games` Up/Down choose the game and Right (or A) steps into the list; in `list` the stick walks the two-column grid, Left from the first column returns to the games, and A opens the game menu of the picked achievement's game. LB/RB switch the all / unlocked / locked filter from either zone (LT/RT stay with the shell).

const ZONE_GAMES := &"games"
const ZONE_LIST := &"list"

## The "all games" entry of the switcher.
const GAME_ALL := ""

const FILTER_ALL := 0
const FILTER_UNLOCKED := 1
const FILTER_LOCKED := 2
const FILTERS := ["all", "unlocked", "locked"]

const TOP := 150.0
const NAV_WIDTH := 340.0
const LIST_LEFT := 520.0
const LIST_WIDTH := 720.0
const FILTER_HEIGHT := 52.0
const COLUMNS := 2
const VISIBLE_ROWS := 6
const TILE_SIZE := Vector2(355, 112)
const TILE_GAP := Vector2(10, 10)
const ASIDE_WIDTH := 480.0

var game := GAME_ALL
var filter := FILTER_ALL
## Key ("game/achievement") of the achievement shown in the detail panel.
var pick := ""
var zone := ZONE_LIST

var _total: Label
var _total_all: Label
var _total_bar: ColorRect
var _game_rows: Dictionary = {}
var _filter_tabs: Array[LauncherControls.Tab] = []
var _grid: LauncherScrollGrid
var _tiles: Dictionary = {}
var _empty: VBoxContainer
var _empty_title: Label
var _empty_body: Label
var _aside: PanelContainer
var _aside_disc: _Disc
var _aside_game: Label
var _aside_title: Label
var _aside_desc: Label
var _aside_state: Label
var _aside_when_column: Control
var _aside_when: Label
var _aside_button: _Button

func build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Dim"
	scrim.color = T.deep(T.A_SCRIM_ACHIEVEMENTS)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(scrim))
	_build_nav()
	_build_list()
	_build_aside()
	shell.store.changed.connect(_on_store_changed)

func _build_nav() -> void:
	var nav := W.vbox(4)
	nav.name = "Games"
	nav.position = Vector2(T.MARGIN, TOP)
	nav.custom_minimum_size = Vector2(NAV_WIDTH, 0)
	nav.size = Vector2(NAV_WIDTH, 0)
	add_child(nav)
	var summary := W.vbox(6)
	summary.name = "Summary"
	nav.add_child(summary)
	summary.add_child(W.text(t("launcher.achievements.eyebrow"), T.SIZE_SMALL, 600, T.fg(T.A_MUTED), 5, true))
	var figures := W.hbox(12)
	summary.add_child(figures)
	_total = W.text("", T.SIZE_TOTAL, 800, T.FG, 0, true)
	_total.name = "Unlocked"
	figures.add_child(_total)
	_total_all = W.text("", T.SIZE_TAGLINE, 400, T.fg(T.A_MUTED), 0, true)
	_total_all.name = "Defined"
	_total_all.size_flags_vertical = Control.SIZE_SHRINK_END
	var lift := MarginContainer.new()
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lift.size_flags_vertical = Control.SIZE_SHRINK_END
	lift.add_theme_constant_override("margin_bottom", 10)
	lift.add_child(_total_all)
	figures.add_child(lift)
	var track := ColorRect.new()
	track.name = "Track"
	track.color = T.fg(0.15)
	track.custom_minimum_size = Vector2(NAV_WIDTH, 4)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(track)
	_total_bar = ColorRect.new()
	_total_bar.name = "Fill"
	_total_bar.color = T.FG
	_total_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_total_bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(gap)
	for id in game_ids():
		var title := t("launcher.achievements.all_games") if id == GAME_ALL else LauncherCatalog.text(LauncherCatalog.by_id(id), "name", shell.locale)
		var row := _GameRow.new(title)
		row.name = "Game_%s" % (id if id != GAME_ALL else "all")
		row.hovered.connect(func() -> void: _point_game(id))
		row.activated.connect(func() -> void: _point_game(id))
		nav.add_child(row)
		_game_rows[id] = row

func _build_list() -> void:
	var filters := W.hbox(8)
	filters.name = "Filters"
	filters.position = Vector2(LIST_LEFT, TOP)
	filters.size = Vector2(LIST_WIDTH, FILTER_HEIGHT)
	add_child(filters)
	for index in FILTERS.size():
		var tab := C.Tab.new(t("launcher.achievements.filter_%s" % FILTERS[index]), T.SIZE_COVER_NAME, FILTER_HEIGHT)
		tab.name = "Filter_%s" % FILTERS[index]
		tab.idle_alpha = T.A_FAINT
		tab.set_padding(20)
		tab.activated.connect(func() -> void: set_filter(index))
		filters.add_child(tab)
		_filter_tabs.append(tab)
	var shoulders := W.hbox(8)
	shoulders.name = "Shoulders"
	shoulders.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	filters.add_child(shoulders)
	for action: StringName in [In.LB, In.RB]:
		var button := C.Pressable.new()
		button.name = "Glyph_%s" % String(action).trim_prefix("launcher_")
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_child(C.Glyph.new(action))
		button.activated.connect(func() -> void: shell.dispatch(action))
		shoulders.add_child(button)
	var rule := W.rule(T.fg(0.16))
	rule.position = Vector2(LIST_LEFT, TOP + FILTER_HEIGHT)
	rule.size = Vector2(LIST_WIDTH, 1)
	add_child(rule)
	_grid = LauncherScrollGrid.new(COLUMNS, TILE_SIZE, TILE_GAP, VISIBLE_ROWS)
	_grid.name = "List"
	_grid.place_at(Vector2(LIST_LEFT, TOP + FILTER_HEIGHT + 18.0))
	_grid.wheeled.connect(_on_wheel)
	add_child(_grid)
	for game_entry in LauncherCatalog.all():
		for definition: Dictionary in game_entry["achievements"]:
			var key := "%s/%s" % [game_entry["id"], definition["id"]]
			var tile := _Tile.new()
			tile.name = "Tile_%s" % key.replace("/", "_")
			tile.pointed.connect(func() -> void: _point_tile(key))
			tile.activated.connect(func() -> void:
				_point_tile(key)
				open_game())
			_grid.add_cell(tile)
			_tiles[key] = tile
	_empty = W.vbox(10)
	_empty.name = "Empty"
	_empty.position = Vector2(LIST_LEFT, TOP + FILTER_HEIGHT + 58.0)
	_empty_title = W.text("", T.SIZE_ROW)
	_empty_title.name = "Title"
	_empty.add_child(_empty_title)
	_empty_body = W.text("", T.SIZE_NAV, 400, T.fg(T.A_MUTED))
	_empty_body.name = "Body"
	_empty.add_child(_empty_body)
	add_child(_empty)

func _build_aside() -> void:
	_aside = PanelContainer.new()
	_aside.name = "Detail"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(T.PANEL, 0.75)
	style.border_color = T.fg(T.A_HAIRLINE)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(T.RADIUS))
	style.set_content_margin_all(36)
	_aside.add_theme_stylebox_override("panel", style)
	_aside.position = Vector2(T.CANVAS.x - T.MARGIN - ASIDE_WIDTH, TOP)
	_aside.custom_minimum_size = Vector2(ASIDE_WIDTH, 0)
	add_child(_aside)
	var column := W.vbox(18)
	_aside.add_child(column)
	_aside_disc = _Disc.new(120.0, 56.0)
	_aside_disc.name = "Icon"
	_aside_disc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_aside_disc)
	_aside_game = W.text("", T.SIZE_SMALL, 600, T.fg(T.A_MUTED), 4)
	_aside_game.name = "Game"
	column.add_child(_aside_game)
	_aside_title = W.text("", T.SIZE_ACHIEVEMENT_TITLE, 900, T.FG, 3)
	_aside_title.name = "Title"
	_aside_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_aside_title)
	_aside_desc = W.text("", T.SIZE_ACHIEVEMENT_NAME, 400, T.fg(0.85))
	_aside_desc.name = "Description"
	_aside_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aside_desc.label_settings.line_spacing = 8
	column.add_child(_aside_desc)
	column.add_child(W.rule(T.fg(0.14)))
	var facts := W.hbox(36)
	column.add_child(facts)
	var state_column := W.vbox(6)
	state_column.add_child(W.text(t("launcher.achievements.state"), T.SIZE_SMALL, 400, T.fg(T.A_MUTED), 3))
	_aside_state = W.text("", T.SIZE_NAV)
	_aside_state.name = "State"
	state_column.add_child(_aside_state)
	facts.add_child(state_column)
	var when_column := W.vbox(6)
	when_column.add_child(W.text(t("launcher.achievements.unlocked_at"), T.SIZE_SMALL, 400, T.fg(T.A_MUTED), 3))
	_aside_when = W.text("", T.SIZE_NAV)
	_aside_when.name = "When"
	when_column.add_child(_aside_when)
	facts.add_child(when_column)
	_aside_when_column = when_column
	_aside_button = _Button.new()
	_aside_button.name = "Open"
	_aside_button.activated.connect(open_game)
	column.add_child(_aside_button)

# ---- lifecycle ----

func on_enter(args: Dictionary) -> void:
	if args.has("game") and LauncherCatalog.has(str(args["game"])):
		game = str(args["game"])
		filter = FILTER_ALL
		pick = ""
	zone = ZONE_LIST
	_refresh(false)

func backdrop() -> Dictionary:
	var shown := game
	if shown == GAME_ALL:
		shown = pick.get_slice("/", 0) if pick != "" else LauncherCatalog.ids()[0]
	return {"layer": &"blur", "game": shown}

func _on_store_changed(_section: StringName) -> void:
	if visible:
		_refresh()

# ---- data ----

## The switcher's entries: "all games" first, then the catalog in its own order.
func game_ids() -> Array[String]:
	var out: Array[String] = [GAME_ALL]
	out.append_array(LauncherCatalog.ids())
	return out

## Every defined achievement of a game (or of all games) with its unlock time: { key, game, definition, at } where `at` is unix seconds, 0 while locked.
func pool(game_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in LauncherCatalog.all():
		var id := str(entry["id"])
		if game_id != GAME_ALL and id != game_id:
			continue
		var unlocked := shell.store.achievements(id)
		for definition: Dictionary in entry["achievements"]:
			out.append({"key": "%s/%s" % [id, definition["id"]], "game": id, "definition": definition, "at": int(unlocked.get(definition["id"], 0))})
	return out

static func _passes(item: Dictionary, p_filter: int) -> bool:
	return p_filter == FILTER_ALL or (int(item["at"]) > 0) == (p_filter == FILTER_UNLOCKED)

## The achievements the list shows: the chosen game's, narrowed by the filter.
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in pool(game):
		if _passes(item, filter):
			out.append(item)
	return out

func count(game_id: String, p_filter: int) -> int:
	var total := 0
	for item in pool(game_id):
		if _passes(item, p_filter):
			total += 1
	return total

func _index_of(list: Array[Dictionary], key: String) -> int:
	for index in list.size():
		if list[index]["key"] == key:
			return index
	return -1

# ---- rendering ----

func _refresh(animate: bool = true) -> void:
	var list := items()
	if _index_of(list, pick) < 0:
		pick = str(list[0]["key"]) if not list.is_empty() else ""
	if list.is_empty():
		zone = ZONE_GAMES

	var unlocked := count(GAME_ALL, FILTER_UNLOCKED)
	var defined := count(GAME_ALL, FILTER_ALL)
	_total.text = str(unlocked)
	_total_all.text = "/ %d" % defined
	_total_bar.size = Vector2(NAV_WIDTH * (float(unlocked) / float(defined) if defined > 0 else 0.0), 4)
	for id: String in _game_rows:
		var row: _GameRow = _game_rows[id]
		row.set_count(count(id, FILTER_UNLOCKED), count(id, FILTER_ALL))
		row.set_state(id == game, id == game and zone == ZONE_GAMES, animate)
	for index in _filter_tabs.size():
		_filter_tabs[index].set_selected(index == filter)
		_filter_tabs[index].set_count(count(game, index))

	var cells: Array[Control] = []
	for item in list:
		var tile: _Tile = _tiles[item["key"]]
		var definition: Dictionary = item["definition"]
		var at := int(item["at"])
		var status := tf("launcher.achievements.unlocked_when_fmt", [LauncherFormat.when_day(at, shell.now(), shell.locale)]) if at > 0 else t("launcher.achievements.locked")
		tile.set_content(str(definition["icon"]), LauncherCatalog.text(definition, "name", shell.locale), LauncherCatalog.text(definition, "desc", shell.locale), status, at > 0)
		tile.set_state(item["key"] == pick, zone == ZONE_LIST)
		cells.append(tile)
	_grid.layout(cells)
	_grid.ensure_visible(_index_of(list, pick), animate)

	_empty.visible = list.is_empty()
	if list.is_empty():
		var reason := "locked" if filter == FILTER_LOCKED else "unlocked"
		_empty_title.text = t("launcher.achievements.empty_%s_title" % reason)
		_empty_body.text = t("launcher.achievements.empty_%s_body" % reason)
	_refresh_aside(list)
	_refresh_footer(list)
	shell.refresh_backdrop()

func _refresh_aside(list: Array[Dictionary]) -> void:
	var index := _index_of(list, pick)
	_aside.visible = index >= 0
	if index < 0:
		return
	var item := list[index]
	var definition: Dictionary = item["definition"]
	var at := int(item["at"])
	_aside_disc.set_icon(str(definition["icon"]), at > 0)
	_aside_game.text = LauncherCatalog.text(LauncherCatalog.by_id(str(item["game"])), "name", shell.locale)
	_aside_title.text = LauncherCatalog.text(definition, "name", shell.locale)
	_aside_desc.text = LauncherCatalog.text(definition, "desc", shell.locale)
	_aside_state.text = t("launcher.achievements.unlocked" if at > 0 else "launcher.achievements.locked")
	_aside_when_column.visible = at > 0
	_aside_when.text = LauncherFormat.when_time(at, shell.now(), shell.locale)
	_aside_button.set_text(_open_caption(at > 0))
	# The panel hugs its content: let it shrink again after a longer description.
	_aside.set_deferred("size", Vector2(ASIDE_WIDTH, 0))

func _open_caption(unlocked: bool) -> String:
	return t("launcher.achievements.open_game" if unlocked else "launcher.achievements.challenge")

func _refresh_footer(list: Array[Dictionary]) -> void:
	var hints: Array = []
	var index := _index_of(list, pick)
	if zone == ZONE_LIST and index >= 0:
		hints.append([In.ACCEPT, _open_caption(int(list[index]["at"]) > 0)])
	elif zone == ZONE_GAMES and not list.is_empty():
		hints.append([In.ACCEPT, t("launcher.achievements.hint_view")])
	hints.append([In.BACK, t("launcher.common.back")])
	set_footer(hints)

func empty_title() -> String:
	return _empty_title.text if _empty.visible else ""

## Keys of the achievements on the list, in order.
func shown_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for item in items():
		out.append(str(item["key"]))
	return out

# ---- focus and actions ----

func handle_action(action: StringName) -> bool:
	match action:
		In.LB:
			set_filter(posmod(filter - 1, FILTERS.size()))
			return true
		In.RB:
			set_filter(posmod(filter + 1, FILTERS.size()))
			return true
		In.UP, In.DOWN, In.LEFT, In.RIGHT:
			if zone == ZONE_GAMES:
				_move_game(action)
			else:
				_move_tile(action)
			return true
		In.ACCEPT:
			if zone == ZONE_GAMES:
				_enter_list()
			else:
				open_game()
			return true
	return false

func _move_game(action: StringName) -> void:
	var ids := game_ids()
	var index := ids.find(game)
	match action:
		In.UP:
			set_game(ids[maxi(0, index - 1)])
		In.DOWN:
			set_game(ids[mini(ids.size() - 1, index + 1)])
		In.RIGHT:
			_enter_list()

func _enter_list() -> void:
	if not items().is_empty():
		zone = ZONE_LIST
		_refresh()

func _move_tile(action: StringName) -> void:
	var list := items()
	var target := LauncherScrollGrid.step(_index_of(list, pick), list.size(), COLUMNS, action)
	if target >= 0:
		pick = str(list[target]["key"])
	elif action == In.LEFT:
		zone = ZONE_GAMES
	_refresh()

## Choose which game's achievements are listed (GAME_ALL for every game). Focus moves to the switcher.
func set_game(id: String) -> void:
	if not _game_rows.has(id):
		return
	if id != game:
		game = id
		pick = ""
	zone = ZONE_GAMES
	_refresh()

func set_filter(index: int) -> void:
	filter = clampi(index, 0, FILTERS.size() - 1)
	_refresh(false)

func _point_game(id: String) -> void:
	if id == game and zone == ZONE_GAMES:
		return
	set_game(id)

## The mouse moved over an achievement: it becomes the picked one.
func _point_tile(key: String) -> void:
	if zone == ZONE_LIST and pick == key:
		return
	zone = ZONE_LIST
	pick = key
	_refresh()

func _on_wheel(step: int) -> void:
	if items().is_empty():
		return
	zone = ZONE_LIST
	_move_tile(In.UP if step < 0 else In.DOWN)

## Open the game menu of the picked achievement's game: the place to go and earn it.
func open_game() -> void:
	if pick != "":
		shell.go(LauncherRoot.MENU, {"game": pick.get_slice("/", 0)})

# ---- widgets ----

## One entry of the game switcher: name and "unlocked / defined". Focused = the 4px bar and the fading gradient; selected while the focus is in the list = a dimmed bar and bold name only.
class _GameRow:
	extends LauncherControls.Pressable

	var selected := false
	var focused := false

	var _label: Label
	var _count: Label
	var _fill := 0.0
	var _tween: Tween

	func _init(title: String) -> void:
		super()
		custom_minimum_size = Vector2(0, LauncherTokens.ROW_HEIGHT)
		set_padding(16)
		var row := LauncherWidgets.hbox(14)
		add_child(row)
		_label = LauncherWidgets.text(title, LauncherTokens.SIZE_COVER_NAME, 400, LauncherTokens.fg(0.7), 2)
		_label.name = "Label"
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label.clip_text = true
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(_label)
		_count = LauncherWidgets.text("", LauncherTokens.SIZE_SUB, 400, LauncherTokens.fg(LauncherTokens.A_MUTED), 0, true)
		_count.name = "Count"
		_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_count)

	func set_count(unlocked: int, defined: int) -> void:
		_count.text = "%d / %d" % [unlocked, defined]

	func count_text() -> String:
		return _count.text

	func set_state(p_selected: bool, p_focused: bool, animate: bool = true) -> void:
		selected = p_selected
		focused = p_focused
		LauncherWidgets.restyle(_label, 700 if selected else 400, LauncherTokens.FG if selected else LauncherTokens.fg(0.7), 2)
		if _tween != null:
			_tween.kill()
			_tween = null
		var target := 1.0 if focused else 0.0
		if animate and is_inside_tree() and not is_equal_approx(_fill, target):
			_tween = create_tween()
			_tween.tween_method(_set_fill, _fill, target, LauncherTokens.FADE_ROW)
			_tween.finished.connect(func() -> void: _tween = null)
		else:
			_set_fill(target)

	func _set_fill(value: float) -> void:
		_fill = value
		queue_redraw()

	func _draw() -> void:
		if _fill > 0.0:
			draw_polygon(
				PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
				PackedColorArray([LauncherTokens.fg(0.14 * _fill), LauncherTokens.fg(0.0), LauncherTokens.fg(0.0), LauncherTokens.fg(0.14 * _fill)]))
		if selected:
			draw_rect(Rect2(0, 0, LauncherTokens.FOCUS_BAR, size.y), LauncherTokens.fg(lerpf(0.4, 1.0, _fill)))

## The round icon of an achievement: white with a dark icon once unlocked (with a soft glow when `glow` is set), a faint disc with a dim icon while locked.
class _Disc:
	extends Control

	var unlocked := false
	var glow := false

	var _icon: LauncherControls.Icon

	func _init(extent: float, icon_extent: float) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(extent, extent)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		glow = extent > 100.0
		_icon = LauncherControls.Icon.new("", icon_extent)
		_icon.position = Vector2.ONE * (extent - icon_extent) / 2.0
		_icon.size = Vector2(icon_extent, icon_extent)
		add_child(_icon)

	func set_icon(kind: String, p_unlocked: bool) -> void:
		unlocked = p_unlocked
		_icon.kind = kind
		_icon.color = LauncherTokens.BG if unlocked else LauncherTokens.fg(0.5)
		_icon.queue_redraw()
		queue_redraw()

	func icon_kind() -> String:
		return _icon.kind

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0
		if unlocked and glow:
			var inner := LauncherTokens.fg(0.3)
			var outer := LauncherTokens.fg(0.0)
			var reach := radius + 40.0
			var segments := 48
			for i in segments:
				var a := Vector2.from_angle(TAU * float(i) / segments) * reach
				var b := Vector2.from_angle(TAU * float(i + 1) / segments) * reach
				draw_polygon(PackedVector2Array([center, center + a, center + b]), PackedColorArray([inner, outer, outer]))
		draw_circle(center, radius, LauncherTokens.FG if unlocked else LauncherTokens.fg(0.08), true, -1.0, true)

## One achievement on the list: icon, name, one line of description, and when it was unlocked (or that it is locked). `pointed` fires on real mouse movement, see the library's cover.
class _Tile:
	extends LauncherControls.Pressable

	signal pointed

	var picked := false
	var focused := false
	var unlocked := false

	var _disc: _Disc
	var _name: Label
	var _desc: Label
	var _status: Label
	var _lock: Control

	func _init() -> void:
		super()
		set_padding(20, 0)
		var row := LauncherWidgets.hbox(18)
		add_child(row)
		_disc = _Disc.new(52.0, 24.0)
		_disc.name = "Icon"
		row.add_child(_disc)
		var column := LauncherWidgets.vbox(4)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(column)
		_name = LauncherWidgets.text("", LauncherTokens.SIZE_ACHIEVEMENT_NAME, 700, LauncherTokens.FG, 1)
		_name.name = "Name"
		_desc = LauncherWidgets.text("", LauncherTokens.SIZE_STAT_LABEL, 400, LauncherTokens.fg(LauncherTokens.A_MUTED))
		_desc.name = "Description"
		for label: Label in [_name, _desc]:
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			column.add_child(label)
		var state := LauncherWidgets.hbox(6)
		column.add_child(state)
		_lock = LauncherControls.Icon.new("lock", 14.0, LauncherTokens.fg(0.55))
		state.add_child(_lock)
		_status = LauncherWidgets.text("", LauncherTokens.SIZE_SMALL, 400, LauncherTokens.fg(0.45), 1)
		_status.name = "Status"
		state.add_child(_status)

	func set_content(icon: String, title: String, description: String, status: String, p_unlocked: bool) -> void:
		unlocked = p_unlocked
		_disc.set_icon(icon, unlocked)
		_name.text = title
		_desc.text = description
		_status.text = status
		_lock.visible = not unlocked
		LauncherWidgets.restyle(_status, 400, LauncherTokens.fg(LauncherTokens.A_BODY if unlocked else 0.45), 1)

	func title_text() -> String:
		return _name.text

	func status_text() -> String:
		return _status.text

	func icon_kind() -> String:
		return _disc.icon_kind()

	## `p_picked` marks the achievement the detail panel shows; `list_focused` says whether the focus is in the list, which is when that mark is the full white outline.
	func set_state(p_picked: bool, list_focused: bool) -> void:
		picked = p_picked
		focused = p_picked and list_focused
		modulate.a = 1.0 if unlocked or picked else 0.75
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = LauncherTokens.fg(0.1) if focused else Color(LauncherTokens.PANEL, 0.5)
		box.border_color = LauncherTokens.FG if focused else LauncherTokens.fg(0.4 if picked else LauncherTokens.A_HAIRLINE)
		box.set_border_width_all(1)
		box.set_corner_radius_all(roundi(LauncherTokens.RADIUS))
		draw_style_box(box, Rect2(Vector2.ZERO, size))

	func _gui_input(event: InputEvent) -> void:
		super(event)
		if event is InputEventMouseMotion:
			pointed.emit()

## The filled white button at the bottom of the detail panel.
class _Button:
	extends LauncherControls.Pressable

	var _label: Label

	func _init() -> void:
		super()
		custom_minimum_size = Vector2(0, 52)
		_label = LauncherWidgets.text("", LauncherTokens.SIZE_ACHIEVEMENT_NAME, 700, LauncherTokens.BG, 2)
		_label.name = "Label"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)

	func set_text(caption: String) -> void:
		_label.text = caption

	func text() -> String:
		return _label.text

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = LauncherTokens.FG
		box.set_corner_radius_all(roundi(LauncherTokens.RADIUS))
		draw_style_box(box, Rect2(Vector2.ZERO, size))
