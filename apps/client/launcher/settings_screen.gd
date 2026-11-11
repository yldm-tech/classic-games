class_name LauncherSettingsScreen
extends LauncherScreen

## Settings: six categories on the left, the rows of the selected category in the middle, and what the focused row does on the right.
##
## Every row is backed by something real. A value row reads and writes one LauncherSettings key through LauncherStore.set_setting and applies it at once (LauncherSettings.apply, LauncherRoot.set_locale, LauncherRoot.refresh_clock); the same keys are applied again at the next start by LauncherRoot. The controls rows rebind the keyboard keys of the launcher actions through the store's bindings and LauncherInput. The saves rows read totals from the store and export, import or wipe the profile. The about rows are read-only facts.
##
## Focus: `zone` is &"categories", &"rows", &"dialog" (a modal dialog is open) or &"capture" (waiting for the key of a rebinding). In the rows zone Left/Right change the focused value and B returns to the categories; from the categories B leaves the screen.

const S := preload("res://launcher/launcher_settings.gd")
const SC := preload("res://launcher/settings_controls.gd")

const ZONE_CATEGORIES := &"categories"
const ZONE_ROWS := &"rows"
const ZONE_DIALOG := &"dialog"
const ZONE_CAPTURE := &"capture"

const GENERAL := &"general"
const DISPLAY := &"display"
const AUDIO := &"audio"
const CONTROLS := &"controls"
const PLAYERS := &"players"
const SAVES := &"saves"
const ABOUT := &"about"
const CATEGORIES: Array[StringName] = [GENERAL, DISPLAY, AUDIO, CONTROLS, PLAYERS, SAVES, ABOUT]
## The LauncherSettings keys each category edits; "restore this page's defaults" resets exactly these.
const CATEGORY_KEYS := {
	GENERAL: [S.LANG, S.CLOCK_24H, S.DEFAULT_MODE],
	DISPLAY: [S.WINDOW_MODE, S.VSYNC, S.MAX_FPS],
	AUDIO: [S.VOLUME_MASTER, S.VOLUME_MUSIC, S.VOLUME_SFX, S.AUDIO_MUTE],
}

const TOP := 160.0
const NAV_WIDTH := 320.0
const SECTION_LEFT := 520.0
const SECTION_WIDTH := 820.0
const HELP_TOP := 240.0
const HELP_WIDTH := 380.0
const VISIBLE_ROWS := 10
const EXPORT_PREFIX := "classic-games-profile-"
const MAX_IMPORT_CHOICES := 5
const REPOSITORY := "github.com/yldm-tech/classic-games"
## Keys that cannot be bound: modifiers on their own never arrive as a launcher press. Escape is not listed because it cancels the capture before it gets here.
const UNBINDABLE: Array[int] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]

## Where the screen was (category, row, zone) when it changed the language. LauncherRoot.set_locale rebuilds every screen, so the new instance picks its place up from here.
static var _resume: Dictionary = {}

var zone := ZONE_CATEGORIES
var category := 0
var row := 0
## Folder that exports are written to and imports are listed from. Tests point it at user://.
var export_dir := ""

var _category_rows: Array[LauncherControls.FocusRow] = []
var _title: Label
var _list: LauncherSettingsControls.RowList
var _rows: Array[Dictionary] = []
var _widgets: Array[LauncherSettingsControls.SettingRow] = []
var _help_title: Label
var _help_body: Label
var _dialog: Control
var _dialog_items: Array[Control] = []
var _dialog_actions: Array[Callable] = []
var _dialog_focus := 0
var _capturing := &""

func build() -> void:
	var scrim := ColorRect.new()
	scrim.color = T.deep(0.86)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(scrim))

	var nav := W.vbox(4)
	nav.name = "Categories"
	nav.position = Vector2(T.MARGIN, TOP)
	nav.size = Vector2(NAV_WIDTH, 0)
	add_child(nav)
	var eyebrow := W.text(t("launcher.settings.eyebrow"), T.SIZE_SMALL, 600, T.fg(T.A_MUTED), 5, true)
	nav.add_child(eyebrow)
	nav.add_child(_gap(14))
	for index in CATEGORIES.size():
		var item := C.FocusRow.new(t("launcher.settings.cat.%s" % CATEGORIES[index]), "", T.SIZE_PANEL_ROW, T.ROW_HEIGHT)
		item.name = "Category_%s" % CATEGORIES[index]
		item.hovered.connect(func() -> void: _hover_category(index))
		item.activated.connect(func() -> void: _pick_category(index))
		nav.add_child(item)
		_category_rows.append(item)

	var section := W.vbox(0)
	section.name = "Section"
	section.position = Vector2(SECTION_LEFT, TOP)
	section.size = Vector2(SECTION_WIDTH, 0)
	add_child(section)
	_title = W.text("", T.SIZE_PANEL_TITLE, 900, T.FG, 4)
	_title.name = "Title"
	section.add_child(_title)
	section.add_child(_gap(22))
	section.add_child(W.rule(T.fg(LauncherSettingsControls.A_ROW_RULE)))
	_list = SC.RowList.new(VISIBLE_ROWS)
	_list.name = "Rows"
	_list.custom_minimum_size = Vector2(SECTION_WIDTH, VISIBLE_ROWS * T.SETTING_ROW_HEIGHT)
	_list.wheel.connect(func(direction: int) -> void: _list.scroll_to(_list.first_visible + direction))
	section.add_child(_list)

	var help := W.hbox(32)
	help.name = "Help"
	help.position = Vector2(T.CANVAS.x - T.MARGIN - HELP_WIDTH, HELP_TOP)
	help.size = Vector2(HELP_WIDTH, 0)
	add_child(help)
	help.add_child(W.rule(T.fg(0.16), 1.0, true))
	var column := W.vbox(14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.add_child(column)
	column.add_child(W.text(t("launcher.settings.help_label"), T.SIZE_SMALL, 600, T.fg(T.A_MUTED), 4, true))
	_help_title = W.text("", T.SIZE_HELP_TITLE, 700, T.FG, 2)
	_help_title.name = "HelpTitle"
	_help_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_help_title)
	_help_body = W.text("", T.SIZE_HELP, 400, T.fg(0.8))
	_help_body.name = "HelpBody"
	_help_body.label_settings.line_spacing = 8.0
	_help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_body.custom_minimum_size = Vector2(HELP_WIDTH - 33.0, 0)
	column.add_child(_help_body)

	if export_dir == "":
		export_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if export_dir == "":
		export_dir = OS.get_user_data_dir()
	shell.store.changed.connect(_on_store_changed)

func _gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

# ---- lifecycle ----

func on_enter(args: Dictionary) -> void:
	_close_overlay()
	zone = ZONE_CATEGORIES
	row = 0
	if not _resume.is_empty():
		category = int(_resume.get("category", 0))
		row = int(_resume.get("row", 0))
		zone = _resume.get("zone", ZONE_CATEGORIES)
		_resume = {}
	elif args.has("category") and CATEGORIES.has(StringName(str(args["category"]))):
		category = CATEGORIES.find(StringName(str(args["category"])))
	_build_rows()
	_sync(false)

func on_exit() -> void:
	_close_overlay()
	zone = ZONE_CATEGORIES

func backdrop() -> Dictionary:
	var recents := shell.store.recents()
	var game: String = recents[0] if not recents.is_empty() and LauncherCatalog.has(recents[0]) else LauncherCatalog.ids()[0]
	return {"layer": &"blur", "game": game}

func _on_store_changed(section: StringName) -> void:
	# Settings are written by this screen, which refreshes itself; progress can change underneath it (wipe, import, undo).
	if visible and section != LauncherStore.SECTION_SETTINGS and section != LauncherStore.SECTION_BINDINGS:
		_sync_values()

# ---- row model ----

func category_id() -> StringName:
	return CATEGORIES[category]

## The rows of a category. Each is { id, kind, label, help } plus what its kind needs: `key` and `options` ([value, text] pairs) for a choice, `key` for a toggle or slider, `button` and `run` (and optionally `danger`, `action`) for an action, and `value` (a Callable returning the text) for an info row or an action row's note.
func _rows_for(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match id:
		GENERAL:
			out.append(_choice(S.LANG, [["zh", t("launcher.settings.lang_zh")], ["en", t("launcher.settings.lang_en")]]))
			out.append(_toggle(S.CLOCK_24H))
			out.append(_choice(S.DEFAULT_MODE, [["console", t("launcher.settings.mode_console")], ["pc", t("launcher.settings.mode_pc")]]))
		DISPLAY:
			out.append(_choice(S.WINDOW_MODE, [["windowed", t("launcher.settings.window_windowed")], ["fullscreen", t("launcher.settings.window_fullscreen")], ["exclusive", t("launcher.settings.window_exclusive")]]))
			out.append(_toggle(S.VSYNC))
			var rates: Array = []
			for rate: int in S.CHOICES[S.MAX_FPS]:
				rates.append([rate, t("launcher.settings.fps_unlimited") if rate == 0 else str(rate)])
			out.append(_choice(S.MAX_FPS, rates))
		AUDIO:
			out.append(_row(S.VOLUME_MASTER, SC.KIND_SLIDER, {"key": S.VOLUME_MASTER}))
			out.append(_row(S.VOLUME_MUSIC, SC.KIND_SLIDER, {"key": S.VOLUME_MUSIC}))
			out.append(_row(S.VOLUME_SFX, SC.KIND_SLIDER, {"key": S.VOLUME_SFX}))
			out.append(_toggle(S.AUDIO_MUTE))
		CONTROLS:
			for action in In.ALL:
				var name := String(action).trim_prefix("launcher_")
				out.append({
					"id": "bind_" + name, "kind": SC.KIND_ACTION, "action": action,
					"label": t("launcher.settings.action.%s" % name),
					"help": func() -> String: return tf("launcher.settings.binding_help_fmt", [key_names(In.keycodes(action)), pad_names(action)]),
					"button": t("launcher.settings.rebind"),
					"value": func() -> String: return key_names(In.keycodes(action)),
					"run": func() -> void: begin_capture(action),
				})
		PLAYERS:
			for action in In.all_game_actions():
				out.append({
					"id": "bind_" + String(action), "kind": SC.KIND_ACTION, "action": action,
					"label": action_label(action),
					"help": func() -> String: return tf("launcher.settings.game_binding_help_fmt", [key_names(In.keycodes(action)), pad_names(action)]),
					"button": t("launcher.settings.rebind"),
					"value": func() -> String: return key_names(In.keycodes(action)),
					"run": func() -> void: begin_capture(action),
				})
		SAVES:
			out.append(_info("play_time", func() -> String: return LauncherFormat.play_time(float(totals()["play_seconds"]), shell.locale)))
			out.append(_info("runs", func() -> String: return tf("launcher.settings.runs_fmt", [int(totals()["runs"])])))
			out.append(_info("achievements", func() -> String: return tf("launcher.settings.achievements_fmt", [int(totals()["unlocked"]), LauncherCatalog.achievement_total()])))
			out.append(_info("file", func() -> String: return shell.store.path.get_file(), [display_path(ProjectSettings.globalize_path(shell.store.path))]))
			out.append(_action("export", export_profile, false, [display_path(export_dir)]))
			out.append(_action("import", open_import, false, [display_path(export_dir)]))
			out.append(_action("wipe", open_wipe, true))
		ABOUT:
			out.append(_info("version", func() -> String: return str(ProjectSettings.get_setting("application/config/version", ""))))
			out.append(_info("engine", func() -> String: return "Godot %s" % str(Engine.get_version_info()["string"])))
			out.append(_info("license", func() -> String: return "Apache-2.0"))
			out.append(_info("art", func() -> String: return t("launcher.settings.art_value")))
			out.append(_info("repo", func() -> String: return REPOSITORY))
			out.append(_info("games", func() -> String: return tf("launcher.settings.games_fmt", [LauncherCatalog.all().size()])))
			# A game whose manifest is invalid is not in the catalog. It is listed here with what is wrong, so its author can see why.
			for problem in LauncherCatalog.problems():
				var errors: PackedStringArray = problem["errors"]
				out.append({
					"id": "problem_%s" % problem["id"], "kind": SC.KIND_INFO,
					"label": tf("launcher.settings.game_problem_fmt", [problem["id"]]),
					"help": "\n".join(errors),
					"value": func() -> String: return tf("launcher.settings.game_problem_value_fmt", [errors.size()]),
				})
	return out

func _row(id: String, kind: StringName, extra: Dictionary = {}, help_args: Array = []) -> Dictionary:
	var help_key := "launcher.settings.%s_help" % id
	var out := {"id": id, "kind": kind, "label": t("launcher.settings.%s" % id), "help": tf(help_key + "_fmt", help_args) if not help_args.is_empty() else t(help_key)}
	out.merge(extra)
	return out

func _choice(key: String, options: Array) -> Dictionary:
	return _row(key, SC.KIND_CHOICE, {"key": key, "options": options})

func _toggle(key: String) -> Dictionary:
	return _row(key, SC.KIND_TOGGLE, {"key": key})

func _info(id: String, value: Callable, help_args: Array = []) -> Dictionary:
	return _row(id, SC.KIND_INFO, {"value": value}, help_args)

func _action(id: String, run: Callable, danger: bool, help_args: Array = []) -> Dictionary:
	return _row(id, SC.KIND_ACTION, {"button": t("launcher.settings.%s_button" % id), "run": run, "danger": danger}, help_args)

## Sums over the catalog's games: { play_seconds, runs, unlocked }. Unlock ids the catalog no longer defines are not counted.
func totals() -> Dictionary:
	var out := {"play_seconds": 0.0, "runs": 0, "unlocked": 0}
	for game in LauncherCatalog.all():
		var id := str(game["id"])
		var stats := shell.store.stats(id)
		out["play_seconds"] = float(out["play_seconds"]) + float(stats["play_seconds"])
		out["runs"] = int(out["runs"]) + int(stats["runs"])
		var unlocked := shell.store.achievements(id)
		for achievement: Dictionary in game["achievements"]:
			if unlocked.has(achievement["id"]):
				out["unlocked"] = int(out["unlocked"]) + 1
	return out

## An absolute path with the home folder shortened to "~".
static func display_path(path: String) -> String:
	var home := OS.get_environment("HOME")
	return "~" + path.trim_prefix(home) if home != "" and path.begins_with(home) else path

# ---- rendering ----

func _build_rows() -> void:
	_rows = _rows_for(category_id())
	_widgets.clear()
	W.clear(_list.column)
	for index in _rows.size():
		var model := _rows[index]
		var widget := SC.SettingRow.new(model["kind"], str(model["label"]), bool(model.get("danger", false)))
		widget.name = "Row_%s" % model["id"]
		widget.hovered.connect(func() -> void: _hover_row(index))
		widget.activated.connect(func() -> void:
			_focus_row(index)
			_activate())
		widget.stepped.connect(func(direction: int) -> void:
			_focus_row(index)
			_step(direction))
		widget.picked.connect(func(step: int) -> void:
			_focus_row(index)
			_set_value(str(model["key"]), step))
		_list.column.add_child(widget)
		_widgets.append(widget)
	row = clampi(row, 0, _rows.size() - 1)
	_list.scroll_to(0)
	_title.text = t("launcher.settings.cat.%s" % category_id())

## Bring every widget in line with the state: values, focus, the help panel and the footer.
func _sync(animate: bool = true) -> void:
	for index in _category_rows.size():
		_category_rows[index].set_focused(index == category, animate)
	_sync_values()
	for index in _widgets.size():
		_widgets[index].set_focused(zone != ZONE_CATEGORIES and index == row, animate)
	if zone != ZONE_CATEGORIES:
		_list.reveal(row)
	_sync_help()
	_sync_footer()

func _sync_values() -> void:
	for index in _widgets.size():
		var model := _rows[index]
		var widget := _widgets[index]
		match model["kind"]:
			SC.KIND_CHOICE:
				widget.set_value(_option_text(model, S.value(shell.store, str(model["key"]))))
			SC.KIND_TOGGLE:
				var on := bool(S.value(shell.store, str(model["key"])))
				widget.set_on(on)
				widget.set_value(t("launcher.settings.on" if on else "launcher.settings.off"))
			SC.KIND_SLIDER:
				widget.set_step(int(S.value(shell.store, str(model["key"]))))
			SC.KIND_ACTION:
				widget.set_button(str(model["button"]))
				if model.has("value"):
					widget.set_value(str((model["value"] as Callable).call()))
			_:
				widget.set_value(str((model["value"] as Callable).call()))

func _option_text(model: Dictionary, value: Variant) -> String:
	for option: Array in model["options"]:
		if option[0] == value:
			return str(option[1])
	return ""

func _sync_help() -> void:
	if zone == ZONE_CATEGORIES or _rows.is_empty():
		_help_title.text = t("launcher.settings.cat.%s" % category_id())
		_help_body.text = t("launcher.settings.cat_help.%s" % category_id())
		return
	var model := _rows[row]
	_help_title.text = str(model["label"])
	_help_body.text = str((model["help"] as Callable).call()) if model["help"] is Callable else str(model["help"])

func help_text() -> String:
	return _help_body.text

func _sync_footer() -> void:
	if zone == ZONE_CAPTURE:
		set_footer([[In.BACK, t("launcher.settings.cancel")]])
		return
	if zone == ZONE_DIALOG:
		set_footer([[In.ACCEPT, t("launcher.settings.hint_select")], [In.BACK, t("launcher.settings.cancel")]])
		return
	var hints: Array = []
	var accept := _accept_caption()
	if accept != "":
		hints.append([In.ACCEPT, accept])
	if can_reset():
		hints.append([In.X, t("launcher.settings.reset_page")])
	hints.append([In.BACK, t("launcher.common.back")])
	set_footer(hints)

func _accept_caption() -> String:
	if zone == ZONE_CATEGORIES:
		return t("launcher.settings.hint_select")
	match _rows[row]["kind"]:
		SC.KIND_CHOICE:
			return t("launcher.settings.hint_change")
		SC.KIND_TOGGLE:
			return t("launcher.settings.hint_toggle")
		SC.KIND_ACTION:
			return str(_rows[row]["button"])
	return ""

## Switch to another category and build its rows, starting from the first one.
func _show_category(index: int) -> void:
	category = clampi(index, 0, CATEGORIES.size() - 1)
	row = 0
	_build_rows()

# ---- focus and actions ----

func handle_action(action: StringName) -> bool:
	if zone == ZONE_CAPTURE:
		# The keyboard is taken by the capture layer; what arrives here is the gamepad or a footer click.
		if action == In.BACK:
			cancel_capture()
		return true
	if zone == ZONE_DIALOG:
		return _dialog_action(action)
	match action:
		In.UP, In.DOWN:
			var step := -1 if action == In.UP else 1
			if zone == ZONE_CATEGORIES:
				var next := clampi(category + step, 0, CATEGORIES.size() - 1)
				if next != category:
					_show_category(next)
			else:
				row = clampi(row + step, 0, _rows.size() - 1)
		In.LEFT, In.RIGHT:
			if zone == ZONE_CATEGORIES:
				if action == In.RIGHT:
					zone = ZONE_ROWS
			else:
				_step(-1 if action == In.LEFT else 1)
				return true
		In.ACCEPT:
			if zone == ZONE_CATEGORIES:
				zone = ZONE_ROWS
			else:
				_activate()
				return true
		In.X:
			if not can_reset():
				return false
			reset_page()
			return true
		In.BACK:
			if zone == ZONE_CATEGORIES:
				return false
			zone = ZONE_CATEGORIES
		_:
			return false
	_sync()
	return true

func _hover_category(index: int) -> void:
	if zone == ZONE_DIALOG or zone == ZONE_CAPTURE or (zone == ZONE_CATEGORIES and category == index):
		return
	_pick_category(index)

func _pick_category(index: int) -> void:
	if zone == ZONE_DIALOG or zone == ZONE_CAPTURE:
		return
	zone = ZONE_CATEGORIES
	if index != category:
		_show_category(index)
	_sync()

func _hover_row(index: int) -> void:
	if (zone == ZONE_ROWS and row == index) or _list.moved_recently():
		return
	_focus_row(index)

func _focus_row(index: int) -> void:
	if zone == ZONE_DIALOG or zone == ZONE_CAPTURE:
		return
	zone = ZONE_ROWS
	row = index
	_sync()

## Left / Right on the focused row: the previous or next option, off or on, one slider step down or up.
func _step(direction: int) -> void:
	var model := _rows[row]
	match model["kind"]:
		SC.KIND_CHOICE:
			var options: Array = model["options"]
			var current := 0
			for index in options.size():
				if options[index][0] == S.value(shell.store, str(model["key"])):
					current = index
			_set_value(str(model["key"]), options[posmod(current + direction, options.size())][0])
		SC.KIND_TOGGLE:
			_set_value(str(model["key"]), direction > 0)
		SC.KIND_SLIDER:
			_set_value(str(model["key"]), clampi(int(S.value(shell.store, str(model["key"]))) + direction, 0, S.VOLUME_STEPS))

## A on the focused row: the next option, flip the switch, or run the action.
func _activate() -> void:
	var model := _rows[row]
	match model["kind"]:
		SC.KIND_CHOICE:
			_step(1)
		SC.KIND_TOGGLE:
			_set_value(str(model["key"]), not bool(S.value(shell.store, str(model["key"]))))
		SC.KIND_ACTION:
			(model["run"] as Callable).call()

## Store one setting and apply it now.
func _set_value(key: String, value: Variant) -> void:
	if S.value(shell.store, key) == value:
		return
	if key == S.LANG:
		# set_locale stores the value and rebuilds every screen, this one included; nothing may touch this instance afterwards.
		_resume = {"category": category, "row": row, "zone": zone}
		shell.set_locale(str(value))
		return
	_apply_values(shell, {key: value})
	_sync()

## Write settings to the store and apply each of them. Static and free of `self`, because the undo of a reset can run after a language change replaced the screen instance.
static func _apply_values(target: LauncherRoot, values: Dictionary) -> void:
	for key: String in values:
		if key == S.LANG:
			continue
		target.store.set_setting(key, values[key])
		if key == S.CLOCK_24H:
			target.refresh_clock()
		else:
			S.apply(target.store, key, S.drives_window(target))
	if values.has(S.LANG) and str(values[S.LANG]) != target.locale:
		var current := target.current_screen() as LauncherSettingsScreen
		if current != null:
			_resume = {"category": current.category, "row": current.row, "zone": current.zone}
		target.set_locale(str(values[S.LANG]))
	elif target.current_screen() is LauncherSettingsScreen:
		(target.current_screen() as LauncherSettingsScreen)._sync()

# ---- restore defaults ----

func can_reset() -> bool:
	return CATEGORY_KEYS.has(category_id()) or category_id() in [CONTROLS, PLAYERS]

## Put the current category back to its defaults (X). The toast offers an undo that restores what was there.
func reset_page() -> void:
	var target := shell
	if category_id() in [CONTROLS, PLAYERS]:
		# Each of the two pages resets its own keys: the interface's or the players'.
		var previous := shell.store.bindings()
		var kept := {}
		for action: String in previous:
			if In.is_game_action(StringName(action)) != (category_id() == PLAYERS):
				kept[action] = previous[action]
		_replace_bindings(target, kept)
		_sync()
		target.toast(t("launcher.settings.reset_controls_done"), Callable(get_script(), "_replace_bindings").bind(target, previous))
		return
	var before := {}
	var defaults := {}
	for key: String in CATEGORY_KEYS[category_id()]:
		before[key] = S.value(shell.store, key)
		defaults[key] = S.DEFAULTS[key]
	var message := t("launcher.settings.reset_done")
	_apply_values(target, defaults)
	# Bound to the script, not to this instance: a reset that changes the language replaces the instance before the undo can run.
	target.toast(message, Callable(get_script(), "_apply_values").bind(target, before))

static func _replace_bindings(target: LauncherRoot, bindings: Dictionary) -> void:
	for action: String in target.store.bindings():
		if not bindings.has(action):
			target.store.clear_binding(action)
	for action: String in bindings:
		target.store.set_binding(action, bindings[action])
	In.reset_and_apply(target.store.bindings())
	if target.current_screen() is LauncherSettingsScreen:
		(target.current_screen() as LauncherSettingsScreen)._sync()

# ---- key rebinding ----

## The key caps of a list of physical keycodes, e.g. "Enter / Space".
static func key_names(codes: Array) -> String:
	var names := PackedStringArray()
	for code: int in codes:
		var label := code
		# Show the cap of the user's layout where the platform can tell; the headless display server cannot.
		if DisplayServer.get_name() != "headless":
			label = int(DisplayServer.keyboard_get_label_from_physical(code as Key))
		names.append(OS.get_keycode_string((label if label != 0 else code) as Key))
	return " / ".join(names)

## The gamepad inputs of an action as the project defines them, e.g. "A" or "十字键 ↑ / 左摇杆 ↑". They are fixed; this is a reference.
func pad_names(action: StringName) -> String:
	var names := PackedStringArray()
	if In.is_game_action(action):
		# A game control's gamepad side is fixed by position (LauncherPlayers.PAD_BUTTONS and the left stick), whichever gamepad the player holds.
		var control := StringName(String(action).get_slice("_", 2))
		for button: int in LauncherPlayers.PAD_BUTTONS:
			if LauncherPlayers.PAD_BUTTONS[button] == control:
				names.append(_button_name(button as JoyButton))
		match control:
			&"up": names.append(_axis_name(JOY_AXIS_LEFT_Y, -1.0))
			&"down": names.append(_axis_name(JOY_AXIS_LEFT_Y, 1.0))
			&"left": names.append(_axis_name(JOY_AXIS_LEFT_X, -1.0))
			&"right": names.append(_axis_name(JOY_AXIS_LEFT_X, 1.0))
		return " / ".join(names)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			names.append(_button_name((event as InputEventJoypadButton).button_index))
		elif event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			names.append(_axis_name(motion.axis, motion.axis_value))
	# PC mode has no button of its own: the shell toggles it when View is held.
	if action == In.PC_MODE:
		names.append(t("launcher.settings.pad.hold_view"))
	return " / ".join(names) if not names.is_empty() else t("launcher.settings.pad.none")

func _button_name(button: JoyButton) -> String:
	match button:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "View"
		JOY_BUTTON_START: return "Menu"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return tf("launcher.settings.pad.dpad_fmt", ["↑"])
		JOY_BUTTON_DPAD_DOWN: return tf("launcher.settings.pad.dpad_fmt", ["↓"])
		JOY_BUTTON_DPAD_LEFT: return tf("launcher.settings.pad.dpad_fmt", ["←"])
		JOY_BUTTON_DPAD_RIGHT: return tf("launcher.settings.pad.dpad_fmt", ["→"])
	return tf("launcher.settings.pad.button_fmt", [int(button)])

func _axis_name(axis: JoyAxis, direction: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return tf("launcher.settings.pad.stick_fmt", ["←" if direction < 0.0 else "→"])
		JOY_AXIS_LEFT_Y: return tf("launcher.settings.pad.stick_fmt", ["↑" if direction < 0.0 else "↓"])
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return tf("launcher.settings.pad.axis_fmt", [int(axis)])

func action_label(action: StringName) -> String:
	if In.is_game_action(action):
		# "game_p2_up" is player 2's "up".
		var parts := String(action).split("_")
		return tf("launcher.settings.player_action_fmt", [parts[1].trim_prefix("p").to_int(), t("launcher.settings.game_action.%s" % parts[2])])
	return t("launcher.settings.action.%s" % String(action).trim_prefix("launcher_"))

func is_capturing() -> bool:
	return zone == ZONE_CAPTURE

## Start waiting for the new key of `action`. The next key press goes to capture_key; Escape, B and a click outside cancel.
func begin_capture(action: StringName) -> void:
	_close_overlay()
	_capturing = action
	zone = ZONE_CAPTURE
	var capture := SC.KeyCapture.new()
	capture.name = "KeyCapture"
	capture.captured.connect(capture_key)
	capture.cancelled.connect(cancel_capture)
	_mount_dialog(capture, tf("launcher.settings.capture_title_fmt", [action_label(action)]), t("launcher.settings.capture_body"), cancel_capture)
	_sync_footer()

func cancel_capture() -> void:
	if zone != ZONE_CAPTURE:
		return
	_close_overlay()
	zone = ZONE_ROWS
	_sync()

## Handle the key pressed during a capture (a physical keycode). A free key is bound at once; a key another action uses opens the conflict dialog; a key that cannot be bound is refused and the capture goes on.
func capture_key(code: int) -> void:
	if zone != ZONE_CAPTURE:
		return
	if code <= 0 or UNBINDABLE.has(code):
		shell.toast(t("launcher.settings.capture_invalid"))
		return
	var action := _capturing
	# The keys that pause a game and the keys players play with must stay apart, or a player's button would also pause. Neither side may take a key of the other.
	var reserved := reserved_holder(action, code)
	if reserved != &"":
		shell.toast(tf("launcher.settings.capture_reserved_fmt", [key_names([code]), action_label(reserved)]))
		return
	var holder := key_holder(code, action)
	_close_overlay()
	zone = ZONE_ROWS
	if holder == &"" or holder == action:
		_bind(action, code, &"")
		return
	var body := tf("launcher.settings.conflict_body_fmt", [key_names([code]), action_label(holder)])
	var rest := In.keycodes(holder)
	rest.erase(code)
	if rest.is_empty():
		body += tf("launcher.settings.conflict_swap_fmt", [action_label(holder), key_names(In.keycodes(action))])
	else:
		body += tf("launcher.settings.conflict_keep_fmt", [action_label(holder), key_names(rest)])
	var replace := func() -> void:
		_close_dialog()
		_bind(action, code, holder)
	_open_dialog("Conflict", t("launcher.settings.conflict_title"), body, [], [[t("launcher.settings.cancel"), _close_dialog], [t("launcher.settings.replace"), replace]], 0)

## The action whose keyboard keys include `code`, or &"", among the actions that can clash with `for_action`: the launcher's own for a launcher action, both players' for a game action. A launcher key and a game key may be the same key (the arrows move the focus in a menu and a player in a game); they are never live at the same time.
func key_holder(code: int, for_action: StringName = &"") -> StringName:
	var group: Array[StringName] = In.all_game_actions() if In.is_game_action(for_action) else In.ALL
	for action in group:
		if In.keycodes(action).has(code):
			return action
	return &""

## The action on the other side of the pause boundary that already uses `code`, or &"": a pause key (Menu, Back) for a game action, a game action for a pause key.
func reserved_holder(for_action: StringName, code: int) -> StringName:
	var others: Array[StringName] = [In.MENU, In.BACK]
	if for_action in others:
		others = In.all_game_actions()
	elif not In.is_game_action(for_action):
		return &""
	for action in others:
		if In.keycodes(action).has(code):
			return action
	return &""

## Give `action` the single key `code`. When `holder` had it, it loses it; if that was its only key it takes over the keys `action` had, so no action is ever left without one.
func _bind(action: StringName, code: int, holder: StringName) -> void:
	var previous := In.keycodes(action)
	if holder != &"":
		var rest := In.keycodes(holder)
		rest.erase(code)
		_store_binding(holder, rest if not rest.is_empty() else previous)
	_store_binding(action, [code])
	In.reset_and_apply(shell.store.bindings())
	_sync()
	shell.toast(tf("launcher.settings.rebound_fmt", [action_label(action), key_names([code])]))

## Only differences from the project defaults are stored.
func _store_binding(action: StringName, codes: Array) -> void:
	var wanted := codes.duplicate()
	var defaults: Array = In.default_keycodes(action)
	wanted.sort()
	defaults.sort()
	if wanted == defaults:
		shell.store.clear_binding(action)
	else:
		shell.store.set_binding(action, codes)

# ---- saves ----

func _export_name() -> String:
	var local := Time.get_datetime_dict_from_unix_time(shell.now() + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%s%04d%02d%02d-%02d%02d%02d.json" % [EXPORT_PREFIX, int(local["year"]), int(local["month"]), int(local["day"]), int(local["hour"]), int(local["minute"]), int(local["second"])]

## Write the whole profile to a dated file in export_dir and say where it went.
func export_profile() -> void:
	DirAccess.make_dir_recursive_absolute(export_dir)
	var target := export_dir.path_join(_export_name())
	if shell.store.export_to(target):
		shell.toast(tf("launcher.settings.exported_fmt", [display_path(ProjectSettings.globalize_path(target))]))
	else:
		shell.toast(tf("launcher.settings.export_failed_fmt", [display_path(ProjectSettings.globalize_path(export_dir))]))

## Export files in export_dir, newest first.
func export_files() -> PackedStringArray:
	var names: Array[String] = []
	var dir := DirAccess.open(export_dir)
	if dir != null:
		for file in dir.get_files():
			if file.begins_with(EXPORT_PREFIX) and file.ends_with(".json"):
				names.append(file)
	names.sort()
	names.reverse()
	return PackedStringArray(names)

## List the newest exports to import from. Focus starts on Cancel.
func open_import() -> void:
	var files := export_files()
	if files.is_empty():
		shell.toast(tf("launcher.settings.import_none_fmt", [display_path(ProjectSettings.globalize_path(export_dir))]))
		return
	var choices: Array = []
	for index in mini(files.size(), MAX_IMPORT_CHOICES):
		var file := files[index]
		choices.append([file.trim_prefix(EXPORT_PREFIX).trim_suffix(".json"), func() -> void: import_profile(export_dir.path_join(file))])
	_open_dialog("Import", t("launcher.settings.import_title"), t("launcher.settings.import_body"), choices, [[t("launcher.settings.cancel"), _close_dialog]], choices.size())

## Replace the progress with that of an exported file, after the store's own version check and normalisation. Settings and key bindings are not imported. The toast offers an undo.
func import_profile(source: String) -> void:
	_close_dialog()
	var profile := LauncherStore.read_profile(source)
	if profile.is_empty():
		shell.toast(t("launcher.settings.import_invalid"))
		return
	var store := shell.store
	var before := store.progress()
	store.replace_progress(profile)
	shell.toast(t("launcher.settings.imported"), func() -> void: store.replace_progress(before))

## Ask before wiping. Focus starts on Cancel.
func open_wipe() -> void:
	var wipe := func() -> void:
		_close_dialog()
		shell.store.wipe_progress()
		shell.toast(t("launcher.settings.wiped"))
	_open_dialog("Wipe", t("launcher.settings.wipe_title"), t("launcher.settings.wipe_body"), [], [[t("launcher.settings.cancel"), _close_dialog], [t("launcher.settings.wipe_confirm"), wipe, true]], 0)

# ---- dialog ----

func is_dialog_open() -> bool:
	return zone == ZONE_DIALOG

func dialog_focus() -> int:
	return _dialog_focus

## Captions of the open dialog's choices, list rows first, then buttons.
func dialog_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for item in _dialog_items:
		out.append((item as LauncherControls.FocusRow).label_text() if item is LauncherControls.FocusRow else (item as LauncherSettingsControls.OutlineButton).caption())
	return out

## Open a modal dialog. `choices` are listed as rows and `buttons` laid out bottom right; each is [caption, Callable] and a button may add `true` to be the destructive one. Focus runs through the rows and then the buttons; `focus` is where it starts.
func _open_dialog(dialog_name: String, title: String, body: String, choices: Array, buttons: Array, focus: int) -> void:
	_close_overlay()
	zone = ZONE_DIALOG
	_dialog_focus = focus
	var root := Control.new()
	root.name = dialog_name + "Dialog"
	var column := _mount_dialog(root, title, body, _close_dialog)
	if not choices.is_empty():
		var list := W.vbox(2)
		column.add_child(list)
		for choice: Array in choices:
			var index := _dialog_items.size()
			var item := C.FocusRow.new(str(choice[0]), "", T.SIZE_SETTING_ROW, 52)
			item.flat_fill = true
			item.set_focused(false, false)
			item.hovered.connect(func() -> void: _focus_dialog(index))
			item.activated.connect(func() -> void: (choice[1] as Callable).call())
			list.add_child(item)
			_dialog_items.append(item)
			_dialog_actions.append(choice[1])
	var bar := W.hbox(20)
	bar.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_gap(4))
	column.add_child(bar)
	for button: Array in buttons:
		var index := _dialog_items.size()
		var destructive := button.size() > 2 and bool(button[2])
		var item := SC.OutlineButton.new(str(button[0]), T.DIALOG_BUTTON_HEIGHT, T.SIZE_HELP, destructive, destructive)
		item.hovered.connect(func() -> void: _focus_dialog(index))
		item.activated.connect(func() -> void: (button[1] as Callable).call())
		bar.add_child(item)
		_dialog_items.append(item)
		_dialog_actions.append(button[1])
	_focus_dialog(_dialog_focus)
	_sync_footer()

## Mount `root` on the shell's overlay layer with the scrim and the dialog box; returns the box's column for more content. Clicking the scrim calls `dismiss`.
func _mount_dialog(root: Control, title: String, body: String, dismiss: Callable) -> VBoxContainer:
	_dialog = root
	shell.show_overlay(root)
	var scrim := SC.Scrim.new()
	scrim.name = "Scrim"
	scrim.activated.connect(dismiss)
	root.add_child(W.fill(scrim))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(W.fill(center))
	var box := PanelContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(T.DIALOG_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = T.DIALOG_BG
	style.border_color = T.fg(T.A_RULE)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(T.RADIUS))
	style.content_margin_left = 44
	style.content_margin_right = 44
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var column := W.vbox(16)
	box.add_child(column)
	var heading := W.text(title, T.SIZE_DIALOG_TITLE, 900, T.FG, 3)
	heading.name = "DialogTitle"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	var text := W.text(body, T.SIZE_HELP, 400, T.fg(0.8))
	text.name = "DialogBody"
	text.label_settings.line_spacing = 7.0
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(T.DIALOG_WIDTH - 88.0, 0)
	column.add_child(text)
	return column

func _focus_dialog(index: int) -> void:
	_dialog_focus = clampi(index, 0, _dialog_items.size() - 1)
	for item_index in _dialog_items.size():
		_dialog_items[item_index].call("set_focused", item_index == _dialog_focus)

func _dialog_action(action: StringName) -> bool:
	match action:
		In.UP, In.LEFT:
			_focus_dialog(_dialog_focus - 1)
		In.DOWN, In.RIGHT:
			_focus_dialog(_dialog_focus + 1)
		In.ACCEPT:
			_dialog_actions[_dialog_focus].call()
		In.BACK:
			_close_dialog()
	# A dialog is modal: nothing falls through to the shell while it is open.
	return true

func _close_dialog() -> void:
	if zone != ZONE_DIALOG:
		return
	_close_overlay()
	zone = ZONE_ROWS
	_sync()

func _close_overlay() -> void:
	if _dialog != null:
		shell.hide_overlay()
		_dialog = null
	_dialog_items.clear()
	_dialog_actions.clear()
	_capturing = &""
