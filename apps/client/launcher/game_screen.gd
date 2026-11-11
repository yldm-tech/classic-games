class_name LauncherGameScreen
extends LauncherScreen

## The in-game screen: the live stage fills the canvas and this screen draws the HUD over it (score and the game's vital bar top left, name and clock top centre, the game's own counters top right, its tools bottom left, hide-HUD and pause bottom right), turns launcher actions into the game's commands, and shows the result when the run ends.
##
## Everything it knows about the run comes from shell.game_host: snapshot() every frame for the HUD, perform() for commands, run_started / run_finished for the life cycle. What each game shows and which button does what is data in LauncherGameGuide, not code here.
##
## Input. Presses arrive through handle_action like on every screen. Two things a press cannot express are polled from the same launcher actions instead: a held button (the shooter's boost) and a direction held at an analogue strength (the tower-defense cursor). Movement of the ship and the hero is read by the runtimes themselves from Godot's ui_* actions.
##
## Life cycle of a run. Opening the pause screen keeps the run alive and paused; leaving this screen by any other route ends it. The host records a run when it ends and at no other time, so quit, restart, finish and closing the window each record it exactly once.

const G := preload("res://launcher/launcher_game_widgets.gd")
const Guide := preload("res://launcher/launcher_game_guide.gd")

const PHASE_PLAYING := &"playing"
const PHASE_RESULT := &"result"
## Stage pixels per second the tower-defense cursor travels with the stick fully tilted.
const CURSOR_SPEED := 260.0
const VITAL_WIDTH := 220.0
const BOSS_WIDTH := 260.0

const RESULT_RETRY := 0
const RESULT_MENU := 1
const RESULT_HOME := 2

var game_id := ""
var phase := PHASE_PLAYING
var result_row := RESULT_RETRY
var hud_visible := true
var tower_index := 0
## Where the next tower goes, in stage coordinates.
var cursor_at := Vector2(GameSession.STAGE_SIZE) / 2.0

var _hud: Control
var _hud_off: Control
var _score: Label
var _vital_label: Label
var _vital_meter: LauncherGameWidgets.Meter
var _vital_value: Label
var _title: Label
var _clock: Label
var _stats: HBoxContainer
var _stat_values: Array[Label] = []
var _boss: Control
var _boss_meter: LauncherGameWidgets.Meter
var _tools: HBoxContainer
var _tool_note: Label
var _tower_chips: Array[LauncherGameWidgets.HudChip] = []
var _boost_chip: LauncherGameWidgets.HudChip
var _shield_chip: LauncherGameWidgets.HudChip
var _cursor: _Cursor
var _stage_click: LauncherControls.Pressable
var _result: Control
var _result_rows: Array[LauncherControls.FocusRow] = []

var _guide: Dictionary = {}
var _prepared_for := ""
var _pausing := false
var _boost_sent := false
var _shield_was_up := false
var _shield_ready_at := 0.0
var _last_mouse := Vector2.ZERO

func build() -> void:
	var top := C.GradientRect.new([[0.0, T.deep(0.65)], [1.0, T.deep(0.0)]])
	top.size = Vector2(T.CANVAS.x, 160)
	add_child(top)
	_stage_click = C.Pressable.new()
	_stage_click.name = "StageClick"
	_stage_click.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_stage_click.activated.connect(func() -> void:
		if _has_towers():
			cursor_at = shell.game_host.to_stage(get_local_mouse_position())
			_place_tower())
	add_child(W.fill(_stage_click))
	_cursor = _Cursor.new()
	_cursor.name = "Cursor"
	_cursor.visible = false
	add_child(_cursor)
	_build_hud()

	var host := shell.game_host
	host.run_started.connect(_on_run_started)
	host.run_finished.connect(_on_run_finished)
	shell.mode_changed.connect(func(mode: StringName) -> void:
		if mode == LauncherRoot.MODE_PC:
			open_pause())

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_hud))

	var left := W.vbox(8)
	left.name = "Player"
	left.position = Vector2(T.HUD_MARGIN, T.HUD_TOP)
	_hud.add_child(left)
	var tag := W.hbox(12)
	var square := W.rule(T.PLAYER_ONE)
	square.custom_minimum_size = Vector2(10, 10)
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(square)
	tag.add_child(W.text(t("launcher.game.score"), T.SIZE_SUB, 800, T.PLAYER_ONE, 3))
	left.add_child(tag)
	_score = W.text("0", T.SIZE_HUD_SCORE, 900, T.FG, 2, true)
	_score.name = "Score"
	_shadow(_score)
	left.add_child(_score)
	var vital := W.hbox(12)
	vital.name = "Vital"
	left.add_child(vital)
	_vital_label = W.text("", T.SIZE_SUB, 700, T.FAVORITE, 2)
	_vital_label.name = "VitalLabel"
	vital.add_child(_vital_label)
	_vital_meter = G.Meter.new(VITAL_WIDTH, T.FAVORITE)
	_vital_meter.name = "VitalMeter"
	vital.add_child(_vital_meter)
	_vital_value = W.text("", T.SIZE_SUB, 700, T.FG, 1, true)
	_vital_value.name = "VitalValue"
	vital.add_child(_vital_value)

	var centre := W.vbox(6)
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	centre.offset_top = 36
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.add_child(centre)
	_title = W.text("", T.SIZE_BODY, 400, T.fg(0.85), 4)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_title)
	_clock = W.text("00:00", T.SIZE_HUD_CLOCK, 800, T.FG, 3, true)
	_clock.name = "Time"
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow(_clock)
	centre.add_child(_clock)

	var right := W.vbox(14)
	right.name = "Status"
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_right = -T.HUD_MARGIN
	right.offset_left = -T.HUD_MARGIN
	right.offset_top = T.HUD_TOP
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud.add_child(right)
	_stats = W.hbox(36)
	_stats.name = "Stats"
	_stats.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(_stats)
	var boss := W.hbox(12)
	boss.name = "Boss"
	boss.alignment = BoxContainer.ALIGNMENT_END
	boss.add_child(W.text(t("launcher.game.boss"), T.SIZE_SUB, 700, T.FAVORITE, 2))
	_boss_meter = G.Meter.new(BOSS_WIDTH, T.FAVORITE)
	_boss_meter.name = "BossMeter"
	boss.add_child(_boss_meter)
	boss.visible = false
	_boss = boss
	right.add_child(boss)

	_tools = W.hbox(10)
	_tools.name = "Tools"
	_tools.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_tools.offset_left = T.HUD_MARGIN
	_tools.offset_bottom = -T.HUD_BOTTOM
	_tools.offset_top = -T.HUD_BOTTOM
	_tools.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud.add_child(_tools)

	_tool_note = W.text("", T.SIZE_SUB, 400, T.fg(T.A_BODY), 2)
	_tool_note.name = "ToolNote"
	_tool_note.position = Vector2(T.HUD_MARGIN, T.CANVAS.y - T.HUD_BOTTOM - T.HUD_CHIP_HEIGHT - 34.0)
	_shadow(_tool_note)
	_hud.add_child(_tool_note)

	var corner := W.hbox(10)
	corner.name = "Corner"
	_hud.add_child(_bottom_right(corner))
	var hide := G.HudChip.new(t("launcher.game.hide_hud"), "", In.Y)
	hide.name = "HideHud"
	hide.activated.connect(func() -> void: shell.dispatch(In.Y))
	corner.add_child(hide)
	var pause := G.HudChip.new(t("launcher.game.hint_pause"), "ESC", In.MENU)
	pause.name = "PauseButton"
	pause.activated.connect(func() -> void: shell.dispatch(In.MENU))
	corner.add_child(pause)

	var show := G.HudChip.new(t("launcher.game.show_hud"), "", In.Y)
	show.name = "ShowHud"
	show.activated.connect(func() -> void: shell.dispatch(In.Y))
	var holder := W.hbox(0)
	holder.add_child(show)
	_hud_off = _bottom_right(holder)
	_hud_off.name = "HudOff"
	_hud_off.visible = false
	add_child(_hud_off)

func _bottom_right(box: Control) -> Control:
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_right = -T.HUD_MARGIN
	box.offset_left = -T.HUD_MARGIN
	box.offset_bottom = -T.HUD_BOTTOM
	box.offset_top = -T.HUD_BOTTOM
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return box

## HUD text sits directly on the game, so it carries a soft dark shadow to stay readable on any stage colour.
func _shadow(label: Label) -> void:
	label.label_settings.shadow_color = Color(0, 0, 0, 0.5)
	label.label_settings.shadow_size = 10
	label.label_settings.shadow_offset = Vector2(0, 2)

func shows_nav() -> bool:
	return false

func backdrop() -> Dictionary:
	return {"layer": &"game", "game": game_id}

# ---- life cycle ----

func on_enter(args: Dictionary) -> void:
	_pausing = false
	var host := shell.game_host
	if args.has("game") or not host.is_running():
		_start(str(args.get("game", game_id)))
		return
	# Back from the pause screen: the same run resumed, or a new one it started with "restart".
	if _prepared_for != host.game_id():
		_prepare(host.game_id())
	host.set_paused(false)
	_sync_hud()

func on_exit() -> void:
	if _pausing:
		return
	# Leaving by any route other than the pause screen ends the run, so play time is never lost and the stage never keeps simulating unseen.
	_close_result()
	shell.game_host.clear_stage()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and shell != null:
		open_pause()

func _start(id: String) -> void:
	game_id = id
	var entry := LauncherCatalog.by_id(id)
	var title := LauncherCatalog.text(entry, "name", shell.locale)
	if not shell.game_host.launch(id, Guide.stored_options(id, shell.store)):
		shell.toast(tf("launcher.game.error_fmt", [title if title != "" else id]))
		shell.go_back.call_deferred()
		return
	_sync_hud()

func _on_run_started(id: String) -> void:
	_prepare(id)

## Reset everything that belongs to one run and build the HUD parts that depend on the game.
func _prepare(id: String) -> void:
	game_id = id
	_prepared_for = id
	_guide = Guide.of(id)
	phase = PHASE_PLAYING
	_close_result()
	cursor_at = Vector2(GameSession.STAGE_SIZE) / 2.0
	tower_index = 0
	_boost_sent = false
	_shield_was_up = false
	_shield_ready_at = 0.0
	_last_mouse = get_local_mouse_position()
	set_footer([])
	_set_hud_visible(hud_visible)

	var vital: Dictionary = _guide.get("vital", {})
	_vital_label.text = t(str(vital["label"])) if vital.has("label") else ""
	_vital_label.get_parent().visible = not vital.is_empty()
	W.clear(_stats)
	_stat_values.clear()
	for stat: Dictionary in _guide.get("stats", []):
		var cell := G.stat_cell(t(str(stat["label"])), "0", true)
		cell.name = "Stat_%s" % str(stat["fields"][0])
		_shadow(cell.get_node("Value"))
		_stats.add_child(cell)
		_stat_values.append(cell.get_node("Value"))
	_boss.visible = false

	W.clear(_tools)
	_tower_chips.clear()
	_boost_chip = null
	_shield_chip = null
	_tool_note.text = ""
	var state := shell.game_host.snapshot()
	var towers := _towers(state)
	for index in towers.size():
		var tower: Dictionary = towers[index]
		var chip := G.HudChip.new(Guide.tower_name(id, str(tower["type"]), shell.locale), str(int(tower["cost"])))
		chip.name = "Tower_%s" % tower["id"]
		chip.activated.connect(func() -> void: select_tower(index))
		_tools.add_child(chip)
		_tower_chips.append(chip)
	if not Guide.control_for(id, "boost").is_empty():
		_boost_chip = G.HudChip.new(t("launcher.game.boost"), "", In.ACCEPT)
		_boost_chip.name = "Boost"
		_boost_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tools.add_child(_boost_chip)
	if not Guide.control_for(id, "shield").is_empty():
		_shield_chip = G.HudChip.new(t("launcher.game.shield"), t("launcher.game.ready"), In.X)
		_shield_chip.name = "Shield"
		_shield_chip.activated.connect(func() -> void: shell.dispatch(In.X))
		_tools.add_child(_shield_chip)

# ---- HUD ----

func _process(delta: float) -> void:
	if not visible or phase != PHASE_PLAYING or shell.current_screen() != self:
		return
	_poll_held(delta)
	_sync_hud()

func _towers(state: Dictionary) -> Array:
	return state.get("towers", []) if state.get("towers") is Array else []

func _has_towers() -> bool:
	return not _tower_chips.is_empty()

func _selected_tower(state: Dictionary) -> Dictionary:
	var towers := _towers(state)
	return towers[tower_index % towers.size()] if not towers.is_empty() else {}

func _sync_hud() -> void:
	var state := shell.game_host.snapshot()
	var entry := LauncherCatalog.by_id(game_id)
	_title.text = "%s · %s" % [LauncherCatalog.text(entry, "name", shell.locale), t("launcher.game.time_left" if Guide.is_countdown(game_id) else "launcher.game.time")]
	_score.text = LauncherFormat.score(int(state.get("score", 0)))
	_clock.text = Guide.clock_text(game_id, state)

	var vital: Dictionary = _guide.get("vital", {})
	if not vital.is_empty():
		var now := int(state.get(str(vital["field"]), 0))
		var full := maxi(1, int(state.get(str(vital["max"]), now)))
		_vital_meter.ratio = float(now) / float(full)
		_vital_value.text = "%d / %d" % [now, full]
	var stats: Array = _guide.get("stats", [])
	for index in mini(stats.size(), _stat_values.size()):
		_stat_values[index].text = Guide.stat_text(stats[index], state)
	_boss.visible = state.has("boss_hp")
	if _boss.visible:
		_boss_meter.ratio = float(state["boss_hp"]) / maxf(1.0, float(state.get("boss_max_hp", 1)))

	var towers := _towers(state)
	var gold := int(state.get("gold", 0))
	for index in mini(towers.size(), _tower_chips.size()):
		_tower_chips[index].set_state(index == tower_index, gold < int(towers[index]["cost"]))
	var selected := _selected_tower(state)
	if not selected.is_empty():
		_tool_note.text = tf("launcher.game.tower_note_fmt", [Guide.tower_name(game_id, str(selected["type"]), shell.locale), Guide.tower_note(game_id, str(selected["type"]), shell.locale), int(selected["damage"]), int(selected["range"])])
	_cursor.visible = not selected.is_empty() and phase == PHASE_PLAYING
	if _cursor.visible:
		_cursor.position = shell.game_host.to_canvas(cursor_at)
		_cursor.show_range(float(selected["range"]) * T.CANVAS.x / float(GameSession.STAGE_SIZE.x), gold >= int(selected["cost"]))

	if _boost_chip != null:
		_boost_chip.set_state(bool(state.get("boost", false)))
	if _shield_chip != null:
		_sync_shield(state)

func _sync_shield(state: Dictionary) -> void:
	var up := int(state.get("shield_hits", 0)) > 0
	var played := float(state.get("play_seconds", 0.0))
	# The recharge starts when the shield is spent, not when it is raised.
	if _shield_was_up and not up:
		_shield_ready_at = played + Guide.SHIELD_COOLDOWN
	_shield_was_up = up
	var wait := _shield_ready_at - played
	if up:
		_shield_chip.set_note(t("launcher.game.shield_up"))
	elif wait > 0.0:
		_shield_chip.set_note(tf("launcher.game.seconds_fmt", [ceili(wait)]))
	else:
		_shield_chip.set_note(t("launcher.game.ready"))
	_shield_chip.set_state(up, not up and wait > 0.0)

func _set_hud_visible(on: bool) -> void:
	hud_visible = on
	_hud.visible = on and phase == PHASE_PLAYING
	_hud_off.visible = not on and phase == PHASE_PLAYING

# ---- input ----

func handle_action(action: StringName) -> bool:
	if phase == PHASE_RESULT:
		return _result_action(action)
	match action:
		In.MENU, In.BACK:
			open_pause()
		In.Y:
			_set_hud_visible(not hud_visible)
		In.ACCEPT:
			_place_tower()
		In.X:
			if _shield_chip != null:
				_use_shield()
			else:
				select_tower(tower_index + 1)
		In.RB:
			select_tower(tower_index + 1)
		In.LB:
			select_tower(tower_index - 1)
	# The game owns every button while a run is live, so none of them falls through to tab switching.
	return true

func _poll_held(delta: float) -> void:
	var host := shell.game_host
	if not host.is_running() or host.is_paused():
		return
	if _boost_chip != null:
		var held := Input.is_action_pressed(In.ACCEPT)
		if held != _boost_sent and host.perform("boost", {"on": held}):
			_boost_sent = held
	if _has_towers():
		move_cursor(Input.get_vector(In.LEFT, In.RIGHT, In.UP, In.DOWN) * CURSOR_SPEED * delta)
		var mouse := get_local_mouse_position()
		if mouse != _last_mouse:
			_last_mouse = mouse
			if Rect2(Vector2.ZERO, T.CANVAS).has_point(mouse):
				cursor_at = host.to_stage(mouse)

## Move the placement cursor by this many stage pixels, staying on the stage.
func move_cursor(offset: Vector2) -> void:
	cursor_at = (cursor_at + offset).clamp(Vector2.ZERO, Vector2(GameSession.STAGE_SIZE))

func select_tower(index: int) -> void:
	if _has_towers() and phase == PHASE_PLAYING:
		tower_index = posmod(index, _tower_chips.size())

func _place_tower() -> void:
	var selected := _selected_tower(shell.game_host.snapshot())
	if selected.is_empty() or phase != PHASE_PLAYING:
		return
	if not shell.game_host.perform("place_tower", {"tower": str(selected["id"]), "position": cursor_at}):
		shell.toast(t("launcher.game.no_gold"))

func _use_shield() -> void:
	var state := shell.game_host.snapshot()
	if int(state.get("shield_hits", 0)) > 0 or float(state.get("play_seconds", 0.0)) < _shield_ready_at:
		return
	shell.game_host.perform("shield")

## Freeze the run and open the pause screen over it. Does nothing unless a run is being played on this screen.
func open_pause() -> void:
	var host := shell.game_host
	if shell.current_screen() != self or phase != PHASE_PLAYING or not host.is_running() or _pausing:
		return
	if _boost_sent:
		host.perform("boost", {"on": false})
		_boost_sent = false
	host.set_paused(true)
	_pausing = true
	shell.go(LauncherRoot.PAUSE)

# ---- result ----

func _on_run_finished(_id: String, result: Dictionary, record: Dictionary) -> void:
	# An aborted run was ended by a quit or a restart; whoever asked for that decides where to go next.
	if shell.current_screen() != self or bool(result.get("aborted", false)):
		return
	_sync_hud()
	phase = PHASE_RESULT
	_cursor.visible = false
	_set_hud_visible(hud_visible)
	_show_result(result, record)
	set_footer([[In.ACCEPT, t("launcher.game.confirm")], [In.BACK, t("launcher.game.to_menu")]])

func _show_result(result: Dictionary, record: Dictionary) -> void:
	_close_result()
	_result = Control.new()
	_result.name = "Result"
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_result))
	if _footer != null:
		move_child(_result, _footer.get_index())
	var scrim := ColorRect.new()
	scrim.color = T.deep(T.A_SCRIM_PAUSE)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result.add_child(W.fill(scrim))
	_result.add_child(W.fill(C.GradientRect.new([[0.0, T.deep(0.7)], [0.45, T.deep(0.0)], [1.0, T.deep(0.0)]], true)))

	var column := W.vbox(0)
	column.position = Vector2(T.MARGIN, T.PAUSE_COLUMN_TOP - 40.0)
	column.custom_minimum_size = Vector2(T.PAUSE_COLUMN_WIDTH, 0)
	_result.add_child(column)
	var entry := LauncherCatalog.by_id(game_id)
	column.add_child(G.eyebrow("%s · RESULT" % LauncherCatalog.text(entry, "name", "en")))
	column.add_child(G.gap(18))
	var outcome := "launcher.game.cleared" if bool(result.get("cleared", false)) else ("launcher.game.defeated" if bool(result.get("defeated", false)) else "launcher.game.timed_out")
	var heading := W.text(t(outcome), T.SIZE_PAUSE_TITLE, 900, T.FG, 8)
	heading.name = "Outcome"
	column.add_child(heading)
	column.add_child(G.gap(28))

	var score_line := W.hbox(18)
	column.add_child(score_line)
	var score := W.text(LauncherFormat.score(int(result.get("score", 0))), T.SIZE_HUD_SCORE, 900, T.FG, 2, true)
	score.name = "FinalScore"
	score_line.add_child(score)
	var new_best := bool(record.get("new_best", false))
	if new_best:
		var best := W.text(t("launcher.game.new_best"), T.SIZE_BODY, 700, T.FAVORITE, 3)
		best.name = "NewBest"
		best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		score_line.add_child(best)
	column.add_child(G.gap(6))
	var previous := int(record.get("previous_best", 0))
	var best_line := ""
	if new_best and previous > 0:
		best_line = tf("launcher.game.previous_best_fmt", [LauncherFormat.score(previous)])
	elif not new_best:
		best_line = tf("launcher.game.best_fmt", [LauncherFormat.score(previous)])
	var best_label := W.text(best_line, T.SIZE_SUB, 400, T.fg(T.A_MUTED), 1)
	best_label.name = "BestLine"
	column.add_child(best_label)
	column.add_child(G.gap(24))

	var cells := W.hbox(44)
	cells.name = "ResultStats"
	column.add_child(cells)
	cells.add_child(G.stat_cell(t("launcher.game.play_time"), LauncherFormat.clock(float(result.get("play_seconds", 0.0)))))
	for stat: Dictionary in _guide.get("stats", []):
		cells.add_child(G.stat_cell(t(str(stat["label"])), Guide.stat_text(stat, result)))
	column.add_child(G.gap(36))

	_result_rows.clear()
	var labels := [t("launcher.game.play_again"), t("launcher.game.to_menu"), t("launcher.game.back_home")]
	var rows := W.vbox(2)
	column.add_child(rows)
	for index in labels.size():
		var item := C.FocusRow.new(labels[index], "", T.SIZE_PAUSE_ROW, T.PAUSE_ROW_HEIGHT)
		item.name = "ResultRow%d" % index
		item.hovered.connect(func() -> void:
			result_row = index
			_sync_result_focus())
		item.activated.connect(func() -> void:
			result_row = index
			_activate_result())
		rows.add_child(item)
		_result_rows.append(item)
	result_row = RESULT_RETRY
	_sync_result_focus(false)

	var unlocked: Array = record.get("unlocked", [])
	if unlocked.is_empty():
		return
	var aside := W.vbox(6)
	aside.name = "Unlocked"
	aside.position = Vector2(T.CANVAS.x - T.MARGIN - T.SIDE_PANEL_WIDTH, T.PAUSE_COLUMN_TOP)
	aside.custom_minimum_size = Vector2(T.SIDE_PANEL_WIDTH, 0)
	_result.add_child(aside)
	aside.add_child(W.section_header(t("launcher.game.unlocked_title")))
	aside.add_child(G.gap(8))
	for achievement: Dictionary in entry.get("achievements", []):
		if achievement["id"] in unlocked:
			var item := G.AchievementRow.new(LauncherCatalog.text(achievement, "name", shell.locale), LauncherCatalog.text(achievement, "desc", shell.locale), t("launcher.game.unlocked_now"), true)
			item.name = "Unlocked_%s" % achievement["id"]
			aside.add_child(item)

func _close_result() -> void:
	if _result != null:
		remove_child(_result)
		_result.queue_free()
		_result = null
	_result_rows.clear()

func _sync_result_focus(animate: bool = true) -> void:
	for index in _result_rows.size():
		_result_rows[index].set_focused(index == result_row, animate)

func _result_action(action: StringName) -> bool:
	match action:
		In.UP:
			result_row = maxi(0, result_row - 1)
			_sync_result_focus()
		In.DOWN:
			result_row = mini(_result_rows.size() - 1, result_row + 1)
			_sync_result_focus()
		In.ACCEPT:
			_activate_result()
		In.BACK:
			result_row = RESULT_MENU
			_activate_result()
	return true

func _activate_result() -> void:
	match result_row:
		RESULT_RETRY:
			_start(game_id)
		RESULT_MENU:
			shell.close_to(LauncherRoot.MENU, {"game": game_id}, [LauncherRoot.GAME, LauncherRoot.PAUSE])
		RESULT_HOME:
			shell.go(LauncherRoot.HOME, {"game": game_id})

## Crosshair marking where the next tower goes, with the tower's range around it.
class _Cursor:
	extends Control

	var reach := 0.0
	var affordable := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_range(p_reach: float, p_affordable: bool) -> void:
		if is_equal_approx(p_reach, reach) and p_affordable == affordable:
			return
		reach = p_reach
		affordable = p_affordable
		queue_redraw()

	func _draw() -> void:
		var color := LauncherTokens.FG if affordable else LauncherTokens.DANGER
		if reach > 0.0:
			draw_circle(Vector2.ZERO, reach, Color(color, 0.06))
			draw_arc(Vector2.ZERO, reach, 0.0, TAU, 96, Color(color, 0.45), 1.5, true)
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 40, color, 2.0, true)
		draw_line(Vector2(-28, 0), Vector2(-8, 0), color, 2.0)
		draw_line(Vector2(8, 0), Vector2(28, 0), color, 2.0)
		draw_line(Vector2(0, -28), Vector2(0, -8), color, 2.0)
		draw_line(Vector2(0, 8), Vector2(0, 28), color, 2.0)
