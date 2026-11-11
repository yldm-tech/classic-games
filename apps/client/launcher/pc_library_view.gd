class_name LauncherPcLibraryView
extends Control

## PC mode's library: a title with the number of games shown, the sort and layout controls, the genre chips, and the games as a grid of cards or a list of rows inside a scroll area. The grid takes as many columns as fit, so it reflows with the width it is given.
##
## Like the detail view it only draws what LauncherPcMode hands it (`show_list`) and reports clicks. A click selects a game, a double click starts it, a right click asks for its menu.

signal game_picked(game_id: String)
signal game_played(game_id: String)
signal game_context(game_id: String)
signal favorite_pressed(game_id: String)
signal sort_pressed
signal layout_picked(layout: StringName)
signal genre_picked(key: String)
signal clear_pressed

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")
const P := preload("res://launcher/pc_tokens.gd")
const PC := preload("res://launcher/pc_controls.gd")

const LAYOUT_GRID := &"grid"
const LAYOUT_LIST := &"list"

var shell: LauncherRoot

var _title: Label
var _count: Label
var _sort: LauncherPcControls.Pill
var _grid_button: LauncherPcControls.IconButton
var _list_button: LauncherPcControls.IconButton
var _chips_row: HBoxContainer
## Untyped so that focus_rows() hands LauncherPcMode plain arrays of widgets.
var _chips: Array = []
var _clear: LauncherPcControls.Pill
var _scroll: ScrollContainer
var _body: VBoxContainer
var _flow: LauncherPcControls.Flow
var _items: Dictionary = {}
var _order: Array[String] = []
var _signature := ""
var _chip_signature := ""
var _empty_clear: LauncherPcControls.Pill

func setup(p_shell: LauncherRoot) -> void:
	shell = p_shell
	name = "Library"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := W.vbox(0)
	add_child(W.fill(column))

	var head := MarginContainer.new()
	head.name = "Toolbar"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("margin_left", roundi(P.LIBRARY_PADDING))
	head.add_theme_constant_override("margin_right", roundi(P.LIBRARY_PADDING))
	head.add_theme_constant_override("margin_top", 24)
	head.add_theme_constant_override("margin_bottom", 18)
	column.add_child(head)
	var rows := W.vbox(16)
	head.add_child(rows)

	var top := W.hbox(16)
	rows.add_child(top)
	_title = W.text("", P.SIZE_SHELF_TITLE, 900, T.FG, 3)
	_title.name = "Title"
	top.add_child(_title)
	_count = W.text("", P.SIZE_TEXT, 400, P.TEXT_SOFT, 0, true)
	_count.name = "Count"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_count)
	var sort_caption := W.text(shell.t("launcher.pc.lib.sort"), P.SIZE_TEXT, 400, P.TEXT_SOFT)
	sort_caption.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	sort_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(sort_caption)
	_sort = PC.Pill.new("", PC.Pill.QUIET, P.CONTROL_HEIGHT, P.SIZE_TEXT, 12.0)
	_sort.name = "Sort"
	_sort.add_trailing_icon("chevron")
	_sort.activated.connect(func() -> void: sort_pressed.emit())
	top.add_child(_sort)
	var toggle := PanelContainer.new()
	toggle.name = "Layout"
	toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var switch_style := PC.Paint.box(Color(0, 0, 0, 0), P.BORDER_STRONG, 1)
	switch_style.set_content_margin_all(1)
	toggle.add_theme_stylebox_override("panel", switch_style)
	var halves := W.hbox(0)
	toggle.add_child(halves)
	top.add_child(toggle)
	_grid_button = PC.IconButton.new("grid", P.CONTROL_HEIGHT - 2.0, 16.0, PC.IconButton.SEGMENT)
	_grid_button.name = "GridLayout"
	_grid_button.tooltip_text = shell.t("launcher.pc.lib.view_grid")
	_grid_button.activated.connect(func() -> void: layout_picked.emit(LAYOUT_GRID))
	halves.add_child(_grid_button)
	_list_button = PC.IconButton.new("list", P.CONTROL_HEIGHT - 2.0, 16.0, PC.IconButton.SEGMENT)
	_list_button.name = "ListLayout"
	_list_button.tooltip_text = shell.t("launcher.pc.lib.view_list")
	_list_button.activated.connect(func() -> void: layout_picked.emit(LAYOUT_LIST))
	halves.add_child(_list_button)

	_chips_row = W.hbox(8)
	_chips_row.name = "Genres"
	rows.add_child(_chips_row)

	column.add_child(W.rule(P.LINE))
	_scroll = PC.Paint.scroll()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", roundi(P.LIBRARY_PADDING))
	margin.add_theme_constant_override("margin_right", roundi(P.LIBRARY_PADDING))
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 32)
	_scroll.add_child(margin)
	_body = W.vbox(0)
	_body.name = "Body"
	margin.add_child(_body)

# ---- rendering ----

## `state` is { title, models, layout, sort_label, genres: [{ key, label, count }], genre, total, query, filtered }. `models` are the game models LauncherPcMode builds, already filtered and sorted.
func show_list(state: Dictionary) -> void:
	var models: Array = state["models"]
	var layout: StringName = state["layout"]
	_title.text = str(state["title"])
	_count.text = shell.tf("launcher.pc.lib.count_fmt", [models.size()])
	_sort.set_caption(str(state["sort_label"]))
	_grid_button.set_on(layout == LAYOUT_GRID)
	_list_button.set_on(layout == LAYOUT_LIST)
	_sync_chips(state)

	var ids: Array[String] = []
	for model: Dictionary in models:
		ids.append(str(model["id"]))
	var signature := "%s|%s|%s" % [layout, shell.locale, ",".join(ids)]
	if signature != _signature:
		_signature = signature
		_order = ids
		_rebuild(models, layout, state)
	for model: Dictionary in models:
		(_items[str(model["id"])] as Control).call("update", model)

func _sync_chips(state: Dictionary) -> void:
	var genres: Array = state["genres"]
	var keys := PackedStringArray()
	for item: Dictionary in genres:
		keys.append("%s=%d" % [item["key"], item["count"]])
	var signature := "%s|%d|%s" % [shell.locale, int(state["total"]), ",".join(keys)]
	if signature != _chip_signature:
		_chip_signature = signature
		W.clear(_chips_row)
		_chips.clear()
		var caption := W.text(shell.t("launcher.pc.lib.genre"), P.SIZE_NOTE, 400, P.TEXT_MUTED, 2)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chips_row.add_child(caption)
		_add_chip("", shell.t("launcher.pc.lib.genre_all"), int(state["total"]))
		for item: Dictionary in genres:
			_add_chip(str(item["key"]), str(item["label"]), int(item["count"]))
		_clear = PC.Pill.new(shell.t("launcher.pc.lib.clear"), PC.Pill.LINK, P.CHIP_HEIGHT, P.SIZE_TEXT, 10.0)
		_clear.name = "ClearFilters"
		_clear.activated.connect(func() -> void: clear_pressed.emit())
		_chips_row.add_child(_clear)
	for chip: LauncherPcControls.Pill in _chips:
		chip.set_on(str(chip.get_meta("genre")) == str(state["genre"]))
	_clear.visible = bool(state["filtered"])

func _add_chip(key: String, label: String, count: int) -> void:
	var chip := PC.Pill.new(label, PC.Pill.CHIP, P.CHIP_HEIGHT, P.SIZE_TEXT, 14.0)
	chip.name = "Genre_%d" % _chips.size()
	chip.set_meta("genre", key)
	chip.set_note(str(count))
	chip.activated.connect(func() -> void: genre_picked.emit(key))
	_chips_row.add_child(chip)
	_chips.append(chip)

func _rebuild(models: Array, layout: StringName, state: Dictionary) -> void:
	W.clear(_body)
	_items.clear()
	_flow = null
	_empty_clear = null
	if models.is_empty():
		_build_empty(state)
		return
	if layout == LAYOUT_LIST:
		_flow = PC.Flow.new(P.CARD_MIN_WIDTH, 0.0, P.LIST_GAP, P.LIST_ROW_HEIGHT, 1)
	else:
		_flow = PC.Flow.new()
	_flow.name = "Items"
	_body.add_child(_flow)
	for model: Dictionary in models:
		var id := str(model["id"])
		var item: LauncherPcControls.Clickable = PC.ListRow.new(id) if layout == LAYOUT_LIST else PC.LibraryCard.new(id)
		item.name = "Game_%s" % id
		item.activated.connect(func() -> void: game_picked.emit(id))
		item.double_clicked.connect(func() -> void: game_played.emit(id))
		item.context_requested.connect(func() -> void: game_context.emit(id))
		item.connect("favorite_pressed", func() -> void: favorite_pressed.emit(id))
		_flow.add_child(item)
		_items[id] = item

func _build_empty(state: Dictionary) -> void:
	var box := W.vbox(12)
	box.name = "Empty"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(0, 320)
	_body.add_child(box)
	var query := str(state["query"]).strip_edges()
	var title := W.text(shell.tf("launcher.pc.lib.empty_query_fmt", [query]) if query != "" else shell.t("launcher.pc.lib.empty"), 18, 400, T.FG)
	title.name = "EmptyTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	if not bool(state["filtered"]):
		return
	var hint := W.text(shell.t("launcher.pc.lib.empty_hint"), P.SIZE_ROW, 400, P.TEXT_SOFT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_empty_clear = PC.Pill.new(shell.t("launcher.pc.lib.clear_all"), PC.Pill.QUIET, 36.0)
	_empty_clear.name = "ClearAll"
	_empty_clear.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_clear.activated.connect(func() -> void: clear_pressed.emit())
	box.add_child(_empty_clear)

# ---- for LauncherPcMode ----

## The controls keyboard focus can visit, row by row: the sort and layout controls, the chips, then the games in the rows the layout really has.
func focus_rows() -> Array:
	var rows: Array = [[_sort, _grid_button, _list_button]]
	var chips: Array = _chips.duplicate()
	if _clear != null and _clear.visible:
		chips.append(_clear)
	rows.append(chips)
	if _empty_clear != null:
		rows.append([_empty_clear])
	var per_row := columns()
	var line: Array = []
	for id in _order:
		line.append(_items[id])
		if line.size() == per_row:
			rows.append(line)
			line = []
	if not line.is_empty():
		rows.append(line)
	return rows

## Index in focus_rows() of the first row of games.
func first_game_row() -> int:
	return 2

func columns() -> int:
	return _flow.columns if _flow != null else 1

func item(game_id: String) -> Control:
	return _items.get(game_id)

func order() -> Array[String]:
	return _order

func sort_button() -> Control:
	return _sort

func scroll_area() -> ScrollContainer:
	return _scroll
