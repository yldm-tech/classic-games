class_name LauncherPauseScreen
extends LauncherScreen

## Pause: shown over the frozen, dimmed game. Resume, restart, master volume, quit to the game menu on the left; the controls of the paused game on the right.
##
## The run stays alive and paused under this screen (LauncherGameScreen opened it without ending anything). Resume and restart go back to the game screen and keep a run on the stage; every other way out ends the run, which is when the host records it. Restart and quit both ask first, and the question starts on cancel.
##
## A game module that two can play adds rows between the volume and quit: add or remove player two (when its manifest allows joining in progress) and, with two players, the input device of each. The pause belongs to the player who opened it (host.pause_owner): input from the other player's device is ignored, with a toast that says whose pause it is, until the owner resumes. A pause nobody owns (focus loss, an unplugged gamepad) and a one-player run take input from anywhere.
##
## Master volume is the one quick setting because it is the one that is real: it is stored under LauncherGameGuide.SETTING_MASTER_VOLUME and applied to the Master audio bus as it changes.

const G := preload("res://launcher/launcher_game_widgets.gd")
const Guide := preload("res://launcher/launcher_game_guide.gd")

const ZONE_MENU := &"menu"
const ZONE_DIALOG := &"dialog"

const ROW_RESUME := &"resume"
const ROW_RESTART := &"restart"
const ROW_VOLUME := &"volume"
const ROW_JOIN := &"join"
const ROW_DEVICE_ONE := &"device0"
const ROW_DEVICE_TWO := &"device1"
const ROW_QUIT := &"quit"

const ASK_RESTART := &"restart"
const ASK_QUIT := &"quit"

var game_id := ""
var zone := ZONE_MENU
var row := 0
## What the open dialog is asking about, &"" when none is open.
var asking := &""

var _name: Label
var _caption: Label
var _score: Label
var _header: Control
var _rows: Array[LauncherControls.FocusRow] = []
var _row_ids: Array[StringName] = []
var _rows_box: VBoxContainer
var _eyebrow: HBoxContainer
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
	# Darker on the left under the menu, as in the design, and again on the right, where the controls table is small text over the frozen stage.
	add_child(W.fill(C.GradientRect.new([[0.0, T.deep(0.7)], [0.45, T.deep(0.0)], [0.5, T.deep(0.0)], [0.6, T.deep(0.6)], [1.0, T.deep(0.6)]], true)))

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
	_eyebrow = G.eyebrow("PAUSED")
	column.add_child(_eyebrow)
	column.add_child(G.gap(18))
	var heading := W.text(t("launcher.game.paused"), T.SIZE_PAUSE_TITLE, 900, T.FG, 8)
	heading.name = "Heading"
	column.add_child(heading)
	column.add_child(G.gap(40))
	var rows := W.vbox(2)
	rows.name = "Rows"
	column.add_child(rows)
	_rows_box = rows

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

## The rows this pause offers, top to bottom. The first three and the last are always there; the ones between depend on the game and on who is playing.
func _wanted_rows() -> Array[StringName]:
	var out: Array[StringName] = [ROW_RESUME, ROW_RESTART, ROW_VOLUME]
	var host := shell.game_host
	if host.is_running() and host.is_module():
		if Guide.joins_in_progress(game_id):
			out.append(ROW_JOIN)
		if host.active_players().size() >= 2:
			out.append(ROW_DEVICE_ONE)
			out.append(ROW_DEVICE_TWO)
	out.append(ROW_QUIT)
	return out

func _build_rows() -> void:
	W.clear(_rows_box)
	_rows.clear()
	_row_ids = _wanted_rows()
	for index in _row_ids.size():
		var id := _row_ids[index]
		var item: LauncherControls.FocusRow
		if id == ROW_VOLUME:
			_volume = G.SliderRow.new(t("launcher.pause.volume"), Guide.VOLUME_STEPS, T.SIZE_PAUSE_ROW, T.PAUSE_ROW_HEIGHT)
			_volume.value_picked.connect(_set_volume)
			item = _volume
		else:
			item = C.FocusRow.new("", "", T.SIZE_PAUSE_ROW, T.PAUSE_ROW_HEIGHT)
		item.name = "Row%d" % index
		item.hovered.connect(func() -> void: _focus_row(index))
		item.activated.connect(func() -> void:
			if _may_act():
				_focus_row(index)
				_activate())
		_rows_box.add_child(item)
		_rows.append(item)
	_sync_rows()

func _sync_rows() -> void:
	var host := shell.game_host
	for index in _row_ids.size():
		var item := _rows[index]
		match _row_ids[index]:
			ROW_RESUME:
				item.set_text(t("launcher.pause.resume"))
				item.set_trailing("B · ESC")
			ROW_RESTART:
				item.set_text(t("launcher.pause.restart"))
			ROW_JOIN:
				item.set_text(t("launcher.pause.remove_player" if host.active_players().size() >= 2 else "launcher.pause.add_player"))
			ROW_DEVICE_ONE:
				item.set_text(tf("launcher.pause.device_fmt", [1]), device_label(host.players.device(0)))
			ROW_DEVICE_TWO:
				item.set_text(tf("launcher.pause.device_fmt", [2]), device_label(host.players.device(1)))
			ROW_QUIT:
				item.set_text(t("launcher.pause.quit"))

func device_label(device: String) -> String:
	return Guide.device_label(device, shell.game_host.players, shell.locale)

func row_id() -> StringName:
	return _row_ids[row] if row < _row_ids.size() else &""

func row_ids() -> Array[StringName]:
	return _row_ids

## Whether the action being handled comes from someone allowed to drive this pause.
func _may_act() -> bool:
	var host := shell.game_host
	if host.players.source_controls(shell.action_source(), host.pause_owner):
		return true
	shell.toast(tf("launcher.pause.owned_fmt", [host.pause_owner + 1]))
	return false

func shows_nav() -> bool:
	return false

func backdrop() -> Dictionary:
	return {"layer": &"game", "game": game_id}

# ---- life cycle ----

func on_enter(_args: Dictionary) -> void:
	_keep_run = false
	_close_dialog()
	zone = ZONE_MENU
	row = 0
	var host := shell.game_host
	game_id = host.game_id()
	# set_paused(false) clears the owner, so it is kept across the call that makes sure the run is frozen.
	var owner_slot := host.pause_owner
	host.set_paused(true)
	host.pause_owner = owner_slot
	_build_rows()
	var owned := owner_slot >= 0 and host.active_players().size() >= 2
	(_eyebrow.get_node("Meta") as Label).text = "PAUSED · P%d" % (owner_slot + 1) if owned else "PAUSED"
	var state := host.snapshot()
	var entry := LauncherCatalog.by_id(game_id)
	_header.visible = not entry.is_empty()
	_name.text = LauncherCatalog.text(entry, "name", shell.locale)
	_caption.text = "%s %s" % [t("launcher.game.time_left" if Guide.is_countdown(game_id) else "launcher.game.time"), Guide.clock_text(game_id, state)]
	_score.text = LauncherFormat.score(int(state.get("score", 0)))
	_played.text = tf("launcher.pause.played_fmt", [LauncherFormat.clock(float(state.get("play_seconds", 0.0)))]) if host.is_running() else ""
	_volume.set_value(Guide.stored_volume(shell.store))
	_build_pane()
	_sync_focus(false)
	set_footer([[In.ACCEPT, t("launcher.game.confirm")], [In.BACK, t("launcher.pause.resume")]])

## The controls of the paused game. With two players each gets a table of their own keys under their device's name.
func _build_pane() -> void:
	W.clear(_pane)
	if not LauncherCatalog.has(game_id):
		return
	var host := shell.game_host
	_pane.add_child(W.section_header(t("launcher.pause.controls")))
	_pane.add_child(G.gap(14))
	if not host.is_module() or host.active_players().size() < 2:
		_pane.add_child(G.controls_table(game_id, shell.locale))
		return
	for slot in host.active_players():
		var device := host.players.device(slot)
		var caption := W.text(tf("launcher.pause.player_device_fmt", [slot + 1, device_label(device)]), T.SIZE_SUB, 700, T.PLAYER_ONE if slot == 0 else T.PLAYER_TWO, 2)
		caption.name = "PlayerCaption%d" % slot
		_pane.add_child(caption)
		_pane.add_child(G.gap(8))
		var table := G.controls_table(game_id, shell.locale, T.PANE_ROW_COMPACT, 2 if device == LauncherPlayers.KEYBOARD_2 else 1)
		table.name = "Controls%d" % slot
		_pane.add_child(table)
		_pane.add_child(G.gap(18))

func on_exit() -> void:
	_close_dialog()
	if not _keep_run:
		# Any way out other than resume and restart is the end of the run.
		shell.game_host.clear_stage()

# ---- focus and actions ----

func handle_action(action: StringName) -> bool:
	if not _may_act():
		return true
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
			_step_row(-1)
		In.RIGHT:
			_step_row(1)
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
	match row_id():
		ROW_RESUME:
			resume()
		ROW_RESTART:
			_ask(ASK_RESTART)
		ROW_JOIN:
			_toggle_player()
		ROW_DEVICE_ONE, ROW_DEVICE_TWO:
			_step_row(1)
		ROW_QUIT:
			_ask(ASK_QUIT)

## Left / Right on a row that holds a value: the volume, or a player's device.
func _step_row(step: int) -> void:
	match row_id():
		ROW_VOLUME:
			_set_volume(_volume.value + step)
		ROW_DEVICE_ONE, ROW_DEVICE_TWO:
			shell.game_host.players.cycle_device(0 if row_id() == ROW_DEVICE_ONE else 1, step)
			# The seats are being rearranged, and the owner's device may just have been handed to the other player: from here the pause is anyone's, so nobody is locked out of it.
			shell.game_host.pause_owner = -1
			(_eyebrow.get_node("Meta") as Label).text = "PAUSED"
			_sync_rows()
			_build_pane()

## Add player two to the paused run, or take them out. The rows change with it, so they are rebuilt with the focus kept on this one.
func _toggle_player() -> void:
	var host := shell.game_host
	var joined := host.active_players().size() < 2
	if not (host.add_player() if joined else host.remove_player()):
		return
	_build_rows()
	row = maxi(0, _row_ids.find(ROW_JOIN))
	_build_pane()
	_sync_focus(false)
	shell.toast(t("launcher.pause.player_added" if joined else "launcher.pause.player_removed"))

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
