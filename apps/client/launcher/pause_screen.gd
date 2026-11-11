class_name LauncherPauseScreen
extends LauncherScreen

## Pause: shown over the frozen, dimmed game. Resume, restart, master volume, quit to the game menu on the left; the controls of the paused game on the right.
##
## The run stays alive and paused under this screen (LauncherGameScreen opened it without ending anything). Resume and restart go back to the game screen and keep a run on the stage; every other way out ends the run, which is when the host records it. Restart and quit both ask first, and the question starts on cancel.
##
## Master volume is the one quick setting because it is the one that is real: it is stored under LauncherGameGuide.SETTING_MASTER_VOLUME and applied to the Master audio bus as it changes.

const G := preload("res://launcher/launcher_game_widgets.gd")
const Guide := preload("res://launcher/launcher_game_guide.gd")

const ZONE_MENU := &"menu"
const ZONE_DIALOG := &"dialog"

const ROW_RESUME := 0
const ROW_RESTART := 1
const ROW_VOLUME := 2
const ROW_QUIT := 3

const ASK_RESTART := &"restart"
const ASK_QUIT := &"quit"

var game_id := ""
var zone := ZONE_MENU
var row := ROW_RESUME
## What the open dialog is asking about, &"" when none is open.
var asking := &""

var _name: Label
var _caption: Label
var _score: Label
var _header: Control
var _rows: Array[LauncherControls.FocusRow] = []
var _volume: LauncherGameWidgets.SliderRow
var _pane: VBoxContainer
var _played: Label
var _dialog: LauncherGameWidgets.ConfirmDialog
var _keep_run := false

func build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = T.deep(T.A_SCRIM_PAUSE)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(scrim))
	add_child(W.fill(C.GradientRect.new([[0.0, T.deep(0.7)], [0.45, T.deep(0.0)], [1.0, T.deep(0.0)]], true)))

	var header := W.hbox(18)
	header.name = "Header"
	header.position = Vector2(T.MARGIN, T.SUBHEADER_TOP)
	header.size = Vector2(T.CANVAS.x - T.MARGIN * 2.0, 44)
	add_child(header)
	_header = header
	_name = W.text("", T.SIZE_BODY, 400, T.FG, 3)
	_name.name = "GameName"
	header.add_child(_name)
	var divider := W.rule(T.fg(0.35), 1.0, true)
	divider.custom_minimum_size = Vector2(1, 16)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(divider)
	_caption = W.text("", T.SIZE_BODY, 400, T.fg(T.A_BODY), 3)
	_caption.name = "RunClock"
	header.add_child(_caption)
	var score := W.hbox(10)
	score.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	header.add_child(score)
	var square := W.rule(T.PLAYER_ONE)
	square.custom_minimum_size = Vector2(10, 10)
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score.add_child(square)
	score.add_child(W.text(t("launcher.game.score"), T.SIZE_BODY, 400, T.fg(0.85), 2))
	_score = W.text("0", T.SIZE_BODY, 700, T.FG, 2, true)
	_score.name = "Score"
	score.add_child(_score)

	var column := W.vbox(0)
	column.name = "Column"
	column.position = Vector2(T.MARGIN, T.PAUSE_COLUMN_TOP)
	column.custom_minimum_size = Vector2(T.PAUSE_COLUMN_WIDTH, 0)
	add_child(column)
	column.add_child(G.eyebrow("PAUSED"))
	column.add_child(G.gap(18))
	var heading := W.text(t("launcher.game.paused"), T.SIZE_PAUSE_TITLE, 900, T.FG, 8)
	heading.name = "Heading"
	column.add_child(heading)
	column.add_child(G.gap(40))
	var rows := W.vbox(2)
	rows.name = "Rows"
	column.add_child(rows)
	_volume = G.SliderRow.new(t("launcher.pause.volume"), Guide.VOLUME_STEPS, T.SIZE_PAUSE_ROW, T.PAUSE_ROW_HEIGHT)
	_volume.value_picked.connect(_set_volume)
	var items: Array[LauncherControls.FocusRow] = [
		C.FocusRow.new(t("launcher.pause.resume"), "", T.SIZE_PAUSE_ROW, T.PAUSE_ROW_HEIGHT),
		C.FocusRow.new(t("launcher.pause.restart"), "", T.SIZE_PAUSE_ROW, T.PAUSE_ROW_HEIGHT),
		_volume,
		C.FocusRow.new(t("launcher.pause.quit"), "", T.SIZE_PAUSE_ROW, T.PAUSE_ROW_HEIGHT),
	]
	items[ROW_RESUME].set_trailing("B · ESC")
	for index in items.size():
		var item := items[index]
		item.name = "Row%d" % index
		item.hovered.connect(func() -> void: _focus_row(index))
		item.activated.connect(func() -> void:
			_focus_row(index)
			_activate())
		rows.add_child(item)
		_rows.append(item)

	_pane = W.vbox(0)
	_pane.name = "Pane"
	_pane.position = Vector2(T.CANVAS.x - T.MARGIN - T.PAUSE_PANE_WIDTH, T.PAUSE_COLUMN_TOP)
	_pane.custom_minimum_size = Vector2(T.PAUSE_PANE_WIDTH, 0)
	add_child(_pane)

	_played = W.text("", T.SIZE_SMALL, 400, T.fg(0.45), 3)
	_played.name = "Played"
	_played.position = Vector2(T.MARGIN, T.CANVAS.y - T.FOOTER_BOTTOM - T.FOOTER_HEIGHT)
	_played.size = Vector2(600, T.FOOTER_HEIGHT)
	_played.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_played)

func shows_nav() -> bool:
	return false

func backdrop() -> Dictionary:
	return {"layer": &"game", "game": game_id}

# ---- life cycle ----

func on_enter(_args: Dictionary) -> void:
	_keep_run = false
	_close_dialog()
	zone = ZONE_MENU
	row = ROW_RESUME
	var host := shell.game_host
	game_id = host.game_id()
	host.set_paused(true)
	var state := host.snapshot()
	var entry := LauncherCatalog.by_id(game_id)
	_header.visible = not entry.is_empty()
	_name.text = LauncherCatalog.text(entry, "name", shell.locale)
	_caption.text = "%s %s" % [t("launcher.game.time_left" if Guide.is_countdown(game_id) else "launcher.game.time"), Guide.clock_text(game_id, state)]
	_score.text = LauncherFormat.score(int(state.get("score", 0)))
	_played.text = tf("launcher.pause.played_fmt", [LauncherFormat.clock(float(state.get("play_seconds", 0.0)))]) if host.is_running() else ""
	_volume.set_value(Guide.stored_volume(shell.store))
	W.clear(_pane)
	if not entry.is_empty():
		_pane.add_child(W.section_header(t("launcher.pause.controls")))
		_pane.add_child(G.gap(14))
		_pane.add_child(G.controls_table(game_id, shell.locale))
	_sync_focus(false)
	set_footer([[In.ACCEPT, t("launcher.game.confirm")], [In.BACK, t("launcher.pause.resume")]])

func on_exit() -> void:
	_close_dialog()
	if not _keep_run:
		# Any way out other than resume and restart is the end of the run.
		shell.game_host.clear_stage()

# ---- focus and actions ----

func handle_action(action: StringName) -> bool:
	if zone == ZONE_DIALOG:
		return _dialog.handle_action(action)
	match action:
		In.UP:
			row = maxi(0, row - 1)
			_sync_focus()
		In.DOWN:
			row = mini(_rows.size() - 1, row + 1)
			_sync_focus()
		In.LEFT:
			if row == ROW_VOLUME:
				_set_volume(_volume.value - 1)
		In.RIGHT:
			if row == ROW_VOLUME:
				_set_volume(_volume.value + 1)
		In.ACCEPT:
			_activate()
		In.BACK, In.MENU:
			resume()
	# Pause is modal: nothing falls through to the shell.
	return true

func _focus_row(index: int) -> void:
	if zone != ZONE_MENU or row == index:
		return
	row = index
	_sync_focus()

func _sync_focus(animate: bool = true) -> void:
	for index in _rows.size():
		_rows[index].set_focused(index == row, animate)

func _activate() -> void:
	match row:
		ROW_RESUME:
			resume()
		ROW_RESTART:
			_ask(ASK_RESTART)
		ROW_QUIT:
			_ask(ASK_QUIT)

func _set_volume(steps: int) -> void:
	var value := clampi(steps, 0, Guide.VOLUME_STEPS)
	_volume.set_value(value)
	shell.store.set_setting(Guide.SETTING_MASTER_VOLUME, value)
	Guide.apply_volume(value)

## Back to the game, which resumes the run.
func resume() -> void:
	_keep_run = true
	shell.go_back()

func _restart() -> void:
	_keep_run = shell.game_host.restart()
	shell.go_back()

func _quit() -> void:
	var id := game_id
	shell.game_host.clear_stage()
	shell.close_to(LauncherRoot.MENU, {"game": id}, [LauncherRoot.GAME, LauncherRoot.PAUSE])

# ---- confirmation ----

func is_asking() -> bool:
	return _dialog != null

func _ask(what: StringName) -> void:
	_close_dialog()
	asking = what
	zone = ZONE_DIALOG
	_dialog = G.ConfirmDialog.new(t("launcher.pause.%s_title" % what), t("launcher.pause.%s_body" % what), t("launcher.pause.%s_confirm" % what), t("launcher.pause.cancel"))
	_dialog.confirmed.connect(func() -> void:
		_close_dialog()
		if what == ASK_RESTART:
			_restart()
		else:
			_quit())
	_dialog.cancelled.connect(_close_dialog)
	shell.show_overlay(_dialog)

func _close_dialog() -> void:
	if _dialog != null:
		_dialog = null
		shell.hide_overlay()
	asking = &""
	zone = ZONE_MENU
