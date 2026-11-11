class_name LauncherMenuScreen
extends LauncherScreen

## The menu of one game, over its key art: start, how to play and controls, records, achievements, the start options its runtime really has, favourite, back. The focused row decides what the pane on the right shows.
##
## Opened with { "game": id }. Records come from LauncherStore.stats, achievements from the catalog and the store, the how-to text, the controls and the options from LauncherGameGuide. A game that was never played says so instead of showing zeros dressed up as records.

const G := preload("res://launcher/launcher_game_widgets.gd")
const Guide := preload("res://launcher/launcher_game_guide.gd")

const ROW_START := &"start"
const ROW_HOW := &"how"
const ROW_RECORDS := &"records"
const ROW_ACHIEVEMENTS := &"achievements"
const ROW_FAVORITE := &"favorite"
const ROW_BACK := &"back"
## A start option's row id is this prefix plus the option id.
const ROW_OPTION := "option:"

const PANE_WIDTH := 600.0
const TITLE_HEIGHT := 112.0

var game_id := ""
var row := 0

var _crumb: Label
var _eyebrow: HBoxContainer
var _title: LauncherGameWidgets.GameTitle
var _latin: Label
var _latin_gap: Control
var _menu: VBoxContainer
var _row_ids: Array[StringName] = []
var _rows: Array[LauncherControls.FocusRow] = []
var _pane: VBoxContainer
var _pane_for := &""

func build() -> void:
	# The key art shows through the middle; the right third is darkened earlier than on Home because the pane carries small text. The ramp into it eases out over several stops: a single straight ramp ends in a visible vertical edge on bright art.
	add_child(W.fill(C.GradientRect.new([[0.0, T.BG], [0.16, T.BG], [0.28, T.bg(0.82)], [0.42, T.bg(0.12)], [0.5, T.bg(0.16)], [0.55, T.bg(0.44)], [0.6, T.bg(0.7)], [0.66, T.bg(0.86)], [1.0, T.bg(0.94)]], true)))
	var bottom := C.GradientRect.new([[0.0, T.deep(0.0)], [1.0, T.deep(0.9)]])
	bottom.position = Vector2(0, T.CANVAS.y - 260)
	bottom.size = Vector2(T.CANVAS.x, 260)
	add_child(bottom)

	var header := W.hbox(18)
	header.name = "Header"
	header.position = Vector2(T.MARGIN, T.SUBHEADER_TOP)
	add_child(header)
	var back := G.BackLink.new(t("launcher.common.back"))
	back.name = "BackLink"
	back.activated.connect(func() -> void: shell.dispatch(In.BACK))
	header.add_child(back)
	var divider := W.rule(T.fg(0.35), 1.0, true)
	divider.custom_minimum_size = Vector2(1, 16)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(divider)
	_crumb = W.text("", T.SIZE_BODY, 400, T.FG, 3)
	_crumb.name = "Crumb"
	_crumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_crumb)

	var column := W.vbox(0)
	column.name = "Column"
	column.position = Vector2(T.MARGIN, T.MENU_COLUMN_TOP)
	column.custom_minimum_size = Vector2(T.MENU_COLUMN_WIDTH, 0)
	add_child(column)
	_eyebrow = G.eyebrow("")
	column.add_child(_eyebrow)
	column.add_child(G.gap(20))
	_title = G.GameTitle.new(T.MENU_COLUMN_WIDTH, TITLE_HEIGHT)
	_title.name = "TitleBox"
	column.add_child(_title)
	_latin_gap = G.gap(16)
	column.add_child(_latin_gap)
	_latin = W.text("", T.SIZE_MENU_LATIN, 800, T.FG, 14, true)
	_latin.name = "LatinName"
	column.add_child(_latin)
	column.add_child(G.gap(48))
	_menu = W.vbox(2)
	_menu.name = "Menu"
	_menu.custom_minimum_size = Vector2(T.MENU_ROWS_WIDTH, 0)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_menu)

	_pane = W.vbox(0)
	_pane.name = "Pane"
	_pane.position = Vector2(T.CANVAS.x - T.MARGIN - PANE_WIDTH, T.MENU_PANE_TOP)
	_pane.custom_minimum_size = Vector2(PANE_WIDTH, 0)
	add_child(_pane)

	shell.store.changed.connect(func(_section: StringName) -> void:
		if visible:
			_refresh())

func shows_nav() -> bool:
	return false

func backdrop() -> Dictionary:
	return {"layer": &"hero", "game": game_id}

# ---- life cycle ----

func on_enter(args: Dictionary) -> void:
	if args.has("game") and LauncherCatalog.has(str(args["game"])):
		game_id = str(args["game"])
	if not LauncherCatalog.has(game_id):
		game_id = LauncherCatalog.ids()[0]
	row = 0
	_build_rows()
	_refresh(false)

func _build_rows() -> void:
	W.clear(_menu)
	_rows.clear()
	_row_ids = [ROW_START, ROW_HOW, ROW_RECORDS, ROW_ACHIEVEMENTS]
	for option: Dictionary in Guide.options(game_id):
		_row_ids.append(StringName(ROW_OPTION + str(option["id"])))
	_row_ids.append(ROW_FAVORITE)
	_row_ids.append(ROW_BACK)
	for index in _row_ids.size():
		var item := C.FocusRow.new("")
		item.name = "Row_%s" % String(_row_ids[index]).replace(":", "_")
		item.hovered.connect(func() -> void: _focus_row(index))
		item.activated.connect(func() -> void:
			_focus_row(index)
			_activate())
		_menu.add_child(item)
		_rows.append(item)

# ---- data ----

func row_id() -> StringName:
	return _row_ids[row] if row < _row_ids.size() else &""

func row_ids() -> Array[StringName]:
	return _row_ids

func _option(id: StringName) -> Dictionary:
	for option: Dictionary in Guide.options(game_id):
		if ROW_OPTION + str(option["id"]) == String(id):
			return option
	return {}

func _unlocked_count() -> int:
	var unlocked := shell.store.achievements(game_id)
	var count := 0
	for achievement: Dictionary in LauncherCatalog.by_id(game_id).get("achievements", []):
		if unlocked.has(achievement["id"]):
			count += 1
	return count

func _achievement_total() -> int:
	return (LauncherCatalog.by_id(game_id).get("achievements", []) as Array).size()

func _record_line() -> String:
	var stats := shell.store.stats(game_id)
	if int(stats["runs"]) == 0:
		return t("launcher.menu.never_played")
	return tf("launcher.menu.last_played_fmt", [LauncherFormat.when_time(int(stats["last_played"]), shell.now(), shell.locale), LauncherFormat.score(int(stats["best_score"]))])

# ---- rendering ----

func _refresh(animate: bool = true) -> void:
	var entry := LauncherCatalog.by_id(game_id)
	var favorite := shell.store.is_favorite(game_id)
	_crumb.text = LauncherCatalog.text(entry, "name", shell.locale)
	(_eyebrow.get_node("Meta") as Label).text = "%s · %s" % [LauncherCatalog.text(entry, "genre", "en"), LauncherCatalog.players_label(entry)]
	_title.show_title(LauncherCatalog.text(entry, "name", shell.locale), LauncherCatalog.color(entry, "colors", "title"), LauncherCatalog.color(entry, "colors", "shadow", Color.BLACK), LauncherCatalog.color(entry, "colors", "glow"), T.SIZE_MENU_TITLE)
	_latin.text = LauncherCatalog.text(entry, "name", "en")
	W.restyle(_latin, 800, LauncherCatalog.color(entry, "colors", "title"), 14, true)
	# In English the title already is the Latin name.
	_latin.visible = shell.locale != "en"
	_latin_gap.visible = _latin.visible

	var options := Guide.stored_options(game_id, shell.store)
	for index in _row_ids.size():
		var id := _row_ids[index]
		var item := _rows[index]
		match id:
			ROW_START:
				item.set_text(t("launcher.menu.start"), _record_line())
			ROW_HOW:
				item.set_text(t("launcher.menu.how"))
			ROW_RECORDS:
				item.set_text(t("launcher.menu.records"))
			ROW_ACHIEVEMENTS:
				item.set_text(t("launcher.menu.achievements"), tf("launcher.menu.unlocked_fmt", [_unlocked_count(), _achievement_total()]))
			ROW_FAVORITE:
				item.set_text(t("launcher.menu.remove_favorite" if favorite else "launcher.menu.add_favorite"))
			ROW_BACK:
				item.set_text(t("launcher.common.back"))
			_:
				var option := _option(id)
				item.set_text(Guide.text(option, "name", shell.locale), tf("launcher.menu.option_value_fmt", [int(options[option["id"]]), (option["values"] as Array).size()]))
		item.set_focused(index == row, animate)
	_build_pane()
	_sync_footer()
	shell.refresh_backdrop()

func _sync_footer() -> void:
	var hints: Array = []
	match row_id():
		ROW_START:
			hints.append([In.ACCEPT, t("launcher.menu.hint_start")])
		ROW_ACHIEVEMENTS:
			hints.append([In.ACCEPT, t("launcher.menu.hint_all_achievements")])
		ROW_FAVORITE, ROW_BACK:
			hints.append([In.ACCEPT, t("launcher.game.confirm")])
		ROW_HOW, ROW_RECORDS:
			pass
		_:
			hints.append([In.ACCEPT, t("launcher.menu.hint_change")])
	hints.append([In.Y, t("launcher.menu.remove_favorite" if shell.store.is_favorite(game_id) else "launcher.menu.add_favorite")])
	hints.append([In.BACK, t("launcher.common.back")])
	set_footer(hints)

func _build_pane() -> void:
	W.clear(_pane)
	_pane_for = row_id()
	var entry := LauncherCatalog.by_id(game_id)
	match _pane_for:
		ROW_HOW:
			_pane_header(t("launcher.menu.how"))
			_pane.add_child(_paragraph(Guide.text(Guide.of(game_id), "how", shell.locale)))
			_pane.add_child(G.gap(22))
			_pane.add_child(G.controls_table(game_id, shell.locale, 52.0))
		ROW_RECORDS:
			_pane_header(t("launcher.menu.records"))
			_build_records()
		ROW_ACHIEVEMENTS:
			_pane_header("%s  %d / %d" % [t("launcher.menu.achievements"), _unlocked_count(), _achievement_total()])
			var unlocked := shell.store.achievements(game_id)
			for achievement: Dictionary in entry.get("achievements", []):
				var done := unlocked.has(achievement["id"])
				var state := LauncherFormat.when_time(int(unlocked[achievement["id"]]), shell.now(), shell.locale) if done else t("launcher.menu.locked")
				var item := G.AchievementRow.new(LauncherCatalog.text(achievement, "name", shell.locale), LauncherCatalog.text(achievement, "desc", shell.locale), state, done)
				item.name = "Achievement_%s" % achievement["id"]
				_pane.add_child(item)
				_pane.add_child(W.rule(T.fg(T.A_HAIRLINE)))
		ROW_START, ROW_FAVORITE, ROW_BACK:
			_pane_header(t("launcher.menu.overview"))
			var tagline := _paragraph(LauncherCatalog.text(entry, "tagline", shell.locale))
			tagline.name = "Tagline"
			_pane.add_child(tagline)
			_pane.add_child(G.gap(22))
			_pane.add_child(W.rule(T.fg(0.2)))
			_pane.add_child(G.gap(18))
			var stats := shell.store.stats(game_id)
			var played := int(stats["runs"]) > 0
			_pane.add_child(_grid([
				["best", t("launcher.game.best"), LauncherFormat.score(int(stats["best_score"])) if played else t("launcher.menu.none")],
				["time", t("launcher.menu.play_time"), LauncherFormat.play_time(float(stats["play_seconds"]), shell.locale) if played else t("launcher.menu.none")],
				["achievements", t("launcher.menu.achievements"), "%d / %d" % [_unlocked_count(), _achievement_total()]],
			]))
		_:
			var option := _option(_pane_for)
			_pane_header(Guide.text(option, "name", shell.locale))
			_pane.add_child(_paragraph(Guide.text(option, "note", shell.locale)))
			_pane.add_child(G.gap(22))
			var values: Array = option["values"]
			var current := int(Guide.stored_options(game_id, shell.store)[option["id"]])
			var chips := W.hbox(10)
			chips.name = "OptionValues"
			for value: int in values:
				var chip := G.HudChip.new(str(value), t("launcher.menu.default") if value == int(option["default"]) else "")
				chip.name = "Value_%d" % value
				chip.set_state(value == current)
				chip.activated.connect(func() -> void: _set_option(option, value))
				chips.add_child(chip)
			_pane.add_child(chips)

func _build_records() -> void:
	var stats := shell.store.stats(game_id)
	if int(stats["runs"]) == 0:
		var empty := _paragraph(t("launcher.menu.records_empty"))
		empty.name = "RecordsEmpty"
		_pane.add_child(empty)
		return
	_pane.add_child(_grid([
		["best", t("launcher.game.best"), LauncherFormat.score(int(stats["best_score"]))],
		["runs", t("launcher.menu.runs"), LauncherFormat.score(int(stats["runs"]))],
		["clears", t("launcher.menu.clears"), LauncherFormat.score(int(stats["clears"]))],
	]))
	_pane.add_child(G.gap(26))
	_pane.add_child(_grid([
		["time", t("launcher.menu.play_time"), LauncherFormat.play_time(float(stats["play_seconds"]), shell.locale)],
		["last", t("launcher.menu.last_played"), LauncherFormat.when_time(int(stats["last_played"]), shell.now(), shell.locale)],
	]))

func _pane_header(title: String) -> void:
	var header := W.section_header(title)
	header.name = "PaneHeader"
	_pane.add_child(header)
	_pane.add_child(G.gap(18))

func _paragraph(content: String) -> Label:
	var label := W.text(content, T.SIZE_DIALOG_BODY, 400, T.fg(0.88), 1)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(PANE_WIDTH, 0)
	label.label_settings.line_spacing = 9
	return label

## A row of stat cells of equal width. Each cell is [name, caption, value].
func _grid(cells: Array) -> HBoxContainer:
	var grid := W.hbox(0)
	for cell: Array in cells:
		var item := G.stat_cell(str(cell[1]), str(cell[2]))
		item.name = "Stat_%s" % cell[0]
		item.custom_minimum_size = Vector2(PANE_WIDTH / 3.0, 0)
		grid.add_child(item)
	return grid

# ---- focus and actions ----

func handle_action(action: StringName) -> bool:
	match action:
		In.UP:
			_move(-1)
		In.DOWN:
			_move(1)
		In.LEFT:
			_step_option(-1)
		In.RIGHT:
			_step_option(1)
		In.ACCEPT:
			_activate()
		In.Y:
			_toggle_favorite()
		_:
			return false
	return true

func _move(step: int) -> void:
	var next := clampi(row + step, 0, _rows.size() - 1)
	if next != row:
		row = next
		_refresh()

func _focus_row(index: int) -> void:
	if row != index:
		row = index
		_refresh()

func _activate() -> void:
	match row_id():
		ROW_START:
			shell.go(LauncherRoot.GAME, {"game": game_id})
		ROW_ACHIEVEMENTS:
			shell.go(LauncherRoot.ACHIEVEMENTS, {"game": game_id})
		ROW_FAVORITE:
			_toggle_favorite()
		ROW_BACK:
			shell.go_back()
		ROW_HOW, ROW_RECORDS:
			pass
		_:
			# Accept walks through the values and wraps, so the option is fully usable with one button.
			var option := _option(row_id())
			var values: Array = option["values"]
			var current := int(Guide.stored_options(game_id, shell.store)[option["id"]])
			_set_option(option, int(values[(values.find(current) + 1) % values.size()]))

func _step_option(step: int) -> void:
	var option := _option(row_id())
	if option.is_empty():
		return
	var values: Array = option["values"]
	var current := int(Guide.stored_options(game_id, shell.store)[option["id"]])
	_set_option(option, int(values[clampi(values.find(current) + step, 0, values.size() - 1)]))

func _set_option(option: Dictionary, value: int) -> void:
	# The store announces the change and the screen refreshes from that.
	shell.store.set_setting(Guide.option_key(game_id, str(option["id"])), value)

func _toggle_favorite() -> void:
	var id := game_id
	var was := shell.store.is_favorite(id)
	var title := LauncherCatalog.text(LauncherCatalog.by_id(id), "name", shell.locale)
	shell.store.set_favorite(id, not was)
	shell.toast(tf("launcher.menu.unfavorited_fmt" if was else "launcher.menu.favorited_fmt", [title]), func() -> void: shell.store.set_favorite(id, was))
