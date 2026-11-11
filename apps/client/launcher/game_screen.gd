class_name LauncherGameScreen
extends LauncherScreen

## The minimal in-game screen: it asks LauncherGameHost to run the selected game, shows the live score, time and status over the stage, and a result panel when the run ends. B / Esc quits back to Home; the run is recorded either way.
##
## This is the hook the full game HUD and the pause screen build on. Everything it knows about the run comes from shell.game_host (snapshot(), run_finished, score_changed, paused_changed); it never reaches the runtime. To add a real pause screen, register it under LauncherRoot.PAUSE and replace _toggle_pause with `shell.go(LauncherRoot.PAUSE)`: the host keeps the stage mounted and paused while the screens swap.

const PHASE_PLAYING := &"playing"
const PHASE_RESULT := &"result"
## Stage pixels the tower-defense placement cursor moves per press.
const CURSOR_STEP := 20.0

var game_id := ""
var phase := PHASE_PLAYING
var result_row := 0

var _title: Label
var _score: Label
var _time: Label
var _status: Label
var _paused: Label
var _cursor: _Cursor
var _cursor_at := Vector2(GameSession.STAGE_SIZE) / 2.0
var _tower_index := 0
var _result: Control
var _result_rows: Array[LauncherControls.FocusRow] = []
var _stage_click: LauncherControls.Pressable
var _leaving := false

func build() -> void:
	var top := C.GradientRect.new([[0.0, T.deep(0.7)], [1.0, T.deep(0.0)]])
	top.size = Vector2(T.CANVAS.x, 180)
	add_child(top)
	_stage_click = C.Pressable.new()
	_stage_click.name = "StageClick"
	_stage_click.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_stage_click.activated.connect(func() -> void:
		_cursor_at = shell.game_host.to_stage(get_local_mouse_position())
		_place_tower())
	add_child(W.fill(_stage_click))

	var hud := W.vbox(4)
	hud.name = "Hud"
	hud.position = Vector2(T.MARGIN, 44)
	add_child(hud)
	_title = W.text("", T.SIZE_BODY, 500, T.fg(0.85), 4)
	_title.name = "Title"
	hud.add_child(_title)
	var line := W.hbox(28)
	hud.add_child(line)
	_score = W.text("0", 38, 800, T.FG, 3, true)
	_score.name = "Score"
	line.add_child(_score)
	_time = W.text("00:00", 38, 800, T.fg(T.A_MUTED), 3, true)
	_time.name = "Time"
	line.add_child(_time)
	_status = W.text("", T.SIZE_SUB, 400, T.fg(T.A_BODY), 1)
	_status.name = "Status"
	hud.add_child(_status)

	_paused = W.text(t("launcher.game.paused"), T.SIZE_PANEL_TITLE, 900, T.FG, 4)
	_paused.name = "Paused"
	_paused.visible = false
	_paused.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_paused.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_paused.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_paused)

	_cursor = _Cursor.new()
	_cursor.name = "Cursor"
	_cursor.visible = false
	add_child(_cursor)

	var host := shell.game_host
	host.run_finished.connect(_on_run_finished)
	host.paused_changed.connect(func(paused: bool) -> void:
		_paused.visible = paused
		_sync_footer())

func shows_nav() -> bool:
	return false

func backdrop() -> Dictionary:
	return {"layer": &"game", "game": game_id}

func on_enter(args: Dictionary) -> void:
	var requested := str(args.get("game", game_id))
	if args.has("game") or not shell.game_host.is_running():
		_start(requested)

func on_exit() -> void:
	# Leaving by any route ends the run, so play time is never lost and the stage never keeps simulating unseen.
	_leaving = true
	shell.game_host.quit()
	_leaving = false
	_close_result()

func _start(id: String) -> void:
	game_id = id
	phase = PHASE_PLAYING
	_close_result()
	_cursor_at = Vector2(GameSession.STAGE_SIZE) / 2.0
	_tower_index = 0
	_paused.visible = false
	var entry := LauncherCatalog.by_id(id)
	_title.text = LauncherCatalog.text(entry, "name", shell.locale)
	if not shell.game_host.launch(id):
		shell.toast(tf("launcher.game.error_fmt", [_title.text if _title.text != "" else id]))
		shell.go_back.call_deferred()
		return
	_sync_hud()
	_sync_footer()

func _process(_delta: float) -> void:
	if visible and phase == PHASE_PLAYING:
		_sync_hud()

func _sync_hud() -> void:
	var state := shell.game_host.snapshot()
	_score.text = LauncherFormat.score(int(state.get("score", 0)))
	_time.text = LauncherFormat.clock(float(state.get("play_seconds", 0.0)))
	var parts := PackedStringArray()
	if state.has("hp"):
		parts.append("%s %d" % [t("launcher.game.hp"), int(state["hp"])])
	if state.has("gold"):
		parts.append("%s %d" % [t("launcher.game.gold"), int(state["gold"])])
	if state.has("base_hp"):
		parts.append("%s %d" % [t("launcher.game.base"), int(state["base_hp"])])
	var towers := _towers(state)
	if not towers.is_empty():
		parts.append(tf("launcher.game.tower_fmt", [towers[_tower_index % towers.size()]]))
	_status.text = " · ".join(parts)
	_cursor.visible = not towers.is_empty() and phase == PHASE_PLAYING
	_cursor.position = shell.game_host.to_canvas(_cursor_at)

func _towers(state: Dictionary) -> Array:
	return state.get("tower_ids", []) if state.get("tower_ids") is Array else []

func _sync_footer() -> void:
	if phase == PHASE_RESULT:
		set_footer([[In.ACCEPT, t("launcher.game.play_again")], [In.BACK, t("launcher.game.back_home")]])
		return
	var hints: Array = []
	if not _towers(shell.game_host.snapshot()).is_empty():
		hints.append([In.ACCEPT, t("launcher.game.hint_place")])
		hints.append([In.X, t("launcher.game.hint_next_tower")])
	hints.append([In.MENU, t("launcher.game.hint_pause")])
	hints.append([In.BACK, t("launcher.game.hint_exit")])
	set_footer(hints)

# ---- input ----

func handle_action(action: StringName) -> bool:
	if phase == PHASE_RESULT:
		return _result_action(action)
	var towers := _towers(shell.game_host.snapshot())
	match action:
		In.BACK:
			# quit() records the run; run_finished then sees an aborted result and returns Home.
			shell.game_host.quit()
		In.MENU:
			_toggle_pause()
		In.ACCEPT:
			if shell.game_host.is_paused():
				_toggle_pause()
			else:
				_place_tower()
		In.X:
			if not towers.is_empty():
				_tower_index = (_tower_index + 1) % towers.size()
		In.UP, In.DOWN, In.LEFT, In.RIGHT:
			if not towers.is_empty():
				var step: Vector2 = {In.UP: Vector2.UP, In.DOWN: Vector2.DOWN, In.LEFT: Vector2.LEFT, In.RIGHT: Vector2.RIGHT}[action]
				_cursor_at = (_cursor_at + step * CURSOR_STEP).clamp(Vector2.ZERO, Vector2(GameSession.STAGE_SIZE))
	# The game owns every button while a run is live, so none of them falls through to tab switching.
	return true

func _toggle_pause() -> void:
	shell.game_host.set_paused(not shell.game_host.is_paused())

func _place_tower() -> void:
	var towers := _towers(shell.game_host.snapshot())
	if towers.is_empty() or phase != PHASE_PLAYING:
		return
	shell.game_host.perform("place_tower", {"tower": str(towers[_tower_index % towers.size()]), "position": _cursor_at})

# ---- result ----

func _on_run_finished(_id: String, result: Dictionary, record: Dictionary) -> void:
	if _leaving or shell.current_screen() != self:
		return
	if bool(result.get("aborted", false)):
		shell.go(LauncherRoot.HOME, {"game": game_id})
		return
	phase = PHASE_RESULT
	_cursor.visible = false
	_sync_hud()
	_show_result(result, record)
	_sync_footer()

func _show_result(result: Dictionary, record: Dictionary) -> void:
	_close_result()
	_result = Control.new()
	_result.name = "Result"
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_result))
	move_child(_result, _footer.get_index() if _footer != null else -1)
	var scrim := ColorRect.new()
	scrim.color = T.deep(0.78)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result.add_child(W.fill(scrim))
	var column := W.vbox(10)
	column.position = Vector2(T.MARGIN, 260)
	column.custom_minimum_size = Vector2(620, 0)
	_result.add_child(column)
	var outcome := "launcher.game.cleared" if bool(result.get("cleared", false)) else ("launcher.game.defeated" if bool(result.get("defeated", false)) else "launcher.game.timed_out")
	var heading := W.text(t(outcome), 72, 900, T.FG, 6)
	heading.name = "Outcome"
	column.add_child(heading)
	var score_line := W.hbox(16)
	column.add_child(score_line)
	var score := W.text(LauncherFormat.score(int(result.get("score", 0))), 38, 800, T.FG, 3, true)
	score.name = "FinalScore"
	score_line.add_child(score)
	if bool(record.get("new_best", false)):
		var best := W.text(t("launcher.game.new_best"), T.SIZE_BODY, 700, T.FAVORITE, 3)
		best.name = "NewBest"
		best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		score_line.add_child(best)
	var entry := LauncherCatalog.by_id(game_id)
	for achievement: Dictionary in entry.get("achievements", []):
		if achievement["id"] in (record.get("unlocked", []) as Array):
			column.add_child(W.text(tf("launcher.game.unlocked_fmt", [LauncherCatalog.text(achievement, "name", shell.locale)]), T.SIZE_TOAST, 400, T.fg(T.A_STRONG), 1))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	column.add_child(spacer)
	_result_rows.clear()
	var labels := [t("launcher.game.play_again"), t("launcher.game.back_home")]
	for index in labels.size():
		var item := C.FocusRow.new(labels[index])
		item.name = "ResultRow%d" % index
		item.hovered.connect(func() -> void:
			result_row = index
			_sync_result_focus())
		item.activated.connect(func() -> void:
			result_row = index
			_activate_result())
		column.add_child(item)
		_result_rows.append(item)
	result_row = 0
	_sync_result_focus()

func _close_result() -> void:
	if _result != null:
		remove_child(_result)
		_result.queue_free()
		_result = null
	_result_rows.clear()

func _sync_result_focus() -> void:
	for index in _result_rows.size():
		_result_rows[index].set_focused(index == result_row)

func _result_action(action: StringName) -> bool:
	match action:
		In.UP, In.DOWN:
			result_row = 1 - result_row
			_sync_result_focus()
		In.ACCEPT:
			_activate_result()
		In.BACK:
			shell.go(LauncherRoot.HOME, {"game": game_id})
	return true

func _activate_result() -> void:
	if result_row == 0:
		_start(game_id)
	else:
		shell.go(LauncherRoot.HOME, {"game": game_id})

## Crosshair marking where the next tower goes.
class _Cursor:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 40, LauncherTokens.FG, 2.0, true)
		draw_line(Vector2(-28, 0), Vector2(-8, 0), LauncherTokens.FG, 2.0)
		draw_line(Vector2(8, 0), Vector2(28, 0), LauncherTokens.FG, 2.0)
		draw_line(Vector2(0, -28), Vector2(0, -8), LauncherTokens.FG, 2.0)
		draw_line(Vector2(0, 8), Vector2(0, 28), LauncherTokens.FG, 2.0)
