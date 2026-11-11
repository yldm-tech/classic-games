class_name LauncherGameScreen
extends LauncherScreen

## The in-game screen: the live stage fills the canvas and this screen draws the HUD over it (score and the game's vital bar top left, name and clock top centre, the game's own counters top right, its tools bottom left, hide-HUD and pause bottom right), turns launcher actions into the game's commands, and shows the result when the run ends.
##
## Everything it knows about the run comes from shell.game_host: snapshot() every frame for the HUD, perform() for commands, run_started / run_finished for the life cycle. What each game shows and which button does what is data in LauncherGameGuide, not code here.
##
## Two kinds of game run here. A DSL game is driven by this screen: it turns launcher actions into the runtime's commands. A game module is driven by its players directly (LauncherGameHost.feed_event passes every input event to the player it belongs to), so for a module this screen only draws the HUD and opens the pause: Menu from anyone, Esc from the keyboard. A module's HUD has a corner for each player; the second one is top right, above the shared counters.
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
## Whether the run pauses when the window loses focus. The screenshot tool turns it off, because its window is never the focused one for long.
var pause_on_focus_loss := true
var tower_index := 0
## Where the next tower goes, in stage coordinates.
var cursor_at := Vector2(GameSession.STAGE_SIZE) / 2.0

var _hud: Control
var _hud_off: Control
var _hide_chip: LauncherGameWidgets.HudChip
## One HUD corner per player slot: { root, tag, score, vital, vital_label, vital_meter, vital_value, stats, stat_values, hint }.
var _blocks: Array[Dictionary] = []
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
var _module := false
var _prepared_for := ""
var _pausing := false
var _boost_sent := false
var _shield_was_up := false
var _shield_ready_at := 0.0
var _last_mouse := Vector2.ZERO

func build() -> void:
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
	host.player_device_lost.connect(_on_device_lost)

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_hud))
	var top := C.GradientRect.new([[0.0, T.deep(0.65)], [1.0, T.deep(0.0)]])
	top.size = Vector2(T.CANVAS.x, 160)
	_hud.add_child(top)

	_blocks.clear()
	var left := _build_player_block(0)
	left.position = Vector2(T.HUD_MARGIN, T.HUD_TOP)
	_hud.add_child(left)

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
	var second := _build_player_block(1)
	second.size_flags_horizontal = Control.SIZE_SHRINK_END
	second.visible = false
	right.add_child(second)
	_stats = W.hbox(36)
	_stats.name = "Stats"
	_stats.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(_stats)
	var boss := W.hbox(12)
	boss.name = "Boss"
	boss.alignment = BoxContainer.ALIGNMENT_END
	var boss_label := W.text(t("launcher.game.boss"), T.SIZE_SUB, 700, T.FAVORITE, 2)
	boss_label.name = "BossLabel"
	_shadow(boss_label)
	boss.add_child(boss_label)
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
	_hide_chip = hide
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

## The HUD corner of one player: a coloured tag, the score, the game's vital bar and the game's per-player counters. Player two's is right-aligned and carries a line for when the seat is empty.
func _build_player_block(slot: int) -> VBoxContainer:
	var suffix := "" if slot == 0 else str(slot + 1)
	var color := T.PLAYER_ONE if slot == 0 else T.PLAYER_TWO
	var end := slot == 1
	var box := W.vbox(8)
	box.name = "Player" + suffix
	var tag := W.hbox(12)
	tag.alignment = BoxContainer.ALIGNMENT_END if end else BoxContainer.ALIGNMENT_BEGIN
	var square := W.rule(color)
	square.custom_minimum_size = Vector2(10, 10)
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(square)
	var tag_label := W.text(t("launcher.game.score"), T.SIZE_SUB, 800, color, 3)
	tag_label.name = "Tag" + suffix
	_shadow(tag_label)
	tag.add_child(tag_label)
	box.add_child(tag)
	var score := W.text("0", T.SIZE_HUD_SCORE, 900, T.FG, 2, true)
	score.name = "Score" + suffix
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if end else HORIZONTAL_ALIGNMENT_LEFT
	_shadow(score)
	box.add_child(score)
	var vital := W.hbox(12)
	vital.name = "Vital" + suffix
	vital.alignment = BoxContainer.ALIGNMENT_END if end else BoxContainer.ALIGNMENT_BEGIN
	box.add_child(vital)
	var vital_label := W.text("", T.SIZE_SUB, 700, T.FAVORITE, 2)
	vital_label.name = "VitalLabel" + suffix
	vital.add_child(vital_label)
	var vital_meter := G.Meter.new(VITAL_WIDTH, T.FAVORITE)
	vital_meter.name = "VitalMeter" + suffix
	vital.add_child(vital_meter)
	var vital_value := W.text("", T.SIZE_SUB, 700, T.FG, 1, true)
	vital_value.name = "VitalValue" + suffix
	vital.add_child(vital_value)
	var stats := W.hbox(28)
	stats.name = "PlayerStats" + suffix
	stats.alignment = BoxContainer.ALIGNMENT_END if end else BoxContainer.ALIGNMENT_BEGIN
	box.add_child(stats)
	var hint := W.text("", T.SIZE_SUB, 400, T.fg(T.A_BODY), 2)
	hint.name = "Hint" + suffix
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if end else HORIZONTAL_ALIGNMENT_LEFT
	hint.visible = false
	_shadow(hint)
	box.add_child(hint)
	_blocks.append({"root": box, "tag": tag_label, "score": score, "vital": vital, "vital_label": vital_label, "vital_meter": vital_meter, "vital_value": vital_value, "stats": stats, "stat_values": [], "hint": hint})
	return box

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
		_start(str(args.get("game", game_id)), int(args.get("players", 0)))
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
	# The notification is propagated through the whole tree, which cannot be changed while that is going on, so the pause screen is opened right after it.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and shell != null and pause_on_focus_loss:
		open_pause.call_deferred()

## Start a run of a game. `players` is the player count; 0 means the one last chosen in the game's menu.
func _start(id: String, players: int = 0) -> void:
	game_id = id
	var entry := LauncherCatalog.by_id(id)
	var title := LauncherCatalog.text(entry, "name", shell.locale)
	if not shell.game_host.launch(id, Guide.stored_options(id, shell.store), players if players > 0 else Guide.stored_players(id, shell.store)):
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
	_module = Guide.is_module(id)
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

	# A module's buttons all belong to its players, so the HUD cannot be hidden from a button there.
	_hide_chip.visible = not _module
	var vital: Dictionary = _guide.get("vital", {})
	for block in _blocks:
		(block["vital_label"] as Label).text = Guide.text(vital, "label", shell.locale)
		(block["vital"] as Control).visible = not vital.is_empty()
		W.clear(block["stats"])
		var values: Array = []
		for stat: Dictionary in _guide.get("player_stats", []):
			var cell := G.stat_cell(Guide.text(stat, "label", shell.locale), "0", true)
			cell.name = "PlayerStat_%s" % str(stat["fields"][0])
			_shadow(cell.get_node("Value"))
			(block["stats"] as Control).add_child(cell)
			values.append(cell.get_node("Value"))
		block["stat_values"] = values
	var boss: Dictionary = _guide.get("boss", {})
	(_boss.get_node("BossLabel") as Label).text = Guide.text(boss, "label", shell.locale) if boss.has("label") else t("launcher.game.boss")
	W.clear(_stats)
	_stat_values.clear()
	for stat: Dictionary in _guide.get("stats", []):
		var cell := G.stat_cell(Guide.text(stat, "label", shell.locale), "0", true)
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
	var timed := Guide.has_clock(game_id)
	_title.text = "%s · %s" % [LauncherCatalog.text(entry, "name", shell.locale), t("launcher.game.time_left" if Guide.is_countdown(game_id) else "launcher.game.time")] if timed else LauncherCatalog.text(entry, "name", shell.locale)
	_clock.visible = timed
	_clock.text = Guide.clock_text(game_id, state)
	for slot in _blocks.size():
		_sync_block(slot, state)

	var stats: Array = _guide.get("stats", [])
	for index in mini(stats.size(), _stat_values.size()):
		_stat_values[index].text = Guide.stat_text(stats[index], state)
	# A game names its boss fields in its manifest; one that does not still gets the bar from the conventional pair.
	var boss: Dictionary = _guide.get("boss", {"field": "boss_hp", "max": "boss_max_hp"})
	_boss.visible = state.has(str(boss["field"]))
	if _boss.visible:
		_boss_meter.ratio = float(state[str(boss["field"])]) / maxf(1.0, float(state.get(str(boss["max"]), 1)))

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

## The fields that belong to one player: the snapshot's `players` entry for that slot when the game reports per-player state, nothing otherwise.
func _player_state(state: Dictionary, slot: int) -> Dictionary:
	var players: Variant = state.get("players")
	if players is Array and slot < (players as Array).size() and players[slot] is Dictionary:
		return players[slot]
	return {}

## Whether the game on the stage can seat a second player, which is what makes the second HUD corner exist at all.
func _seats_two() -> bool:
	return _module and Guide.player_range(game_id).y >= 2

func _sync_block(slot: int, state: Dictionary) -> void:
	var block := _blocks[slot]
	var active: Array = state.get("active_players", [0]) if state.get("active_players") is Array else [0]
	var playing := slot in active
	var two := _seats_two()
	var hint: Label = block["hint"]
	if slot > 0:
		(block["root"] as Control).visible = two
		if not two:
			return
		hint.visible = not playing
		hint.text = t("launcher.game.p2_join_hint" if Guide.joins_in_progress(game_id) else "launcher.game.p2_empty")
	(block["tag"] as Label).text = tf("launcher.game.player_score_fmt", [slot + 1]) if two else t("launcher.game.score")
	var mine := _player_state(state, slot)
	# Player one's corner falls back to the run's shared fields, which is all a single-player game reports.
	var shared := state if slot == 0 else {}
	var score: Label = block["score"]
	score.visible = playing and (mine.has("score") or slot == 0)
	score.text = LauncherFormat.score(int(mine.get("score", shared.get("score", 0))))
	var vital: Dictionary = _guide.get("vital", {})
	var vital_row: Control = block["vital"]
	var has_vital := playing and not vital.is_empty() and (mine.has(str(vital["field"])) or shared.has(str(vital["field"])))
	vital_row.visible = has_vital
	if has_vital:
		var now := int(mine.get(str(vital["field"]), shared.get(str(vital["field"]), 0)))
		var full := maxi(1, int(mine.get(str(vital["max"]), shared.get(str(vital["max"]), now))))
		(block["vital_meter"] as LauncherGameWidgets.Meter).ratio = float(now) / float(full)
		(block["vital_value"] as Label).text = "%d / %d" % [now, full]
	(block["stats"] as Control).visible = playing
	var cells: Array = _guide.get("player_stats", [])
	var values: Array = block["stat_values"]
	var source := mine if not mine.is_empty() else shared
	for index in mini(cells.size(), values.size()):
		(values[index] as Label).text = Guide.stat_text(cells[index], source)

func _sync_shield(state: Dictionary) -> void:
	var up := int(state.get("shield_hits", 0)) > 0
	var played := float(state.get("play_seconds", 0.0))
	# The recharge starts when the shield is spent, not when it is raised.
	if _shield_was_up and not up:
		_shield_ready_at = played + Guide.tuning(game_id, "shield_cooldown", 0.0)
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
	if _module:
		# Every button but pause belongs to the players. B and Y on a gamepad are game buttons, so only the keyboard's Back (Esc) pauses.
		var source := shell.action_source()
		if action == In.MENU or (action == In.BACK and source == LauncherPlayers.SOURCE_KEYBOARD):
			open_pause(shell.game_host.players.slot_of_source(source))
		return true
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

## Freeze the run and open the pause screen over it. Does nothing unless a run is being played on this screen. `owner_slot` is the player who paused; with two players only that player's device drives the pause screen. -1 leaves it to anyone.
func open_pause(owner_slot: int = -1) -> void:
	var host := shell.game_host
	if shell.current_screen() != self or phase != PHASE_PLAYING or not host.is_running() or _pausing:
		return
	if _boost_sent:
		host.perform("boost", {"on": false})
		_boost_sent = false
	host.set_paused(true)
	host.pause_owner = owner_slot
	_pausing = true
	shell.go(LauncherRoot.PAUSE)

## A playing slot's gamepad was unplugged: freeze the run and say why. The pause belongs to nobody, so whoever is still connected can pick another device there or carry on.
func _on_device_lost(slot: int) -> void:
	if shell.current_screen() != self or phase != PHASE_PLAYING:
		return
	open_pause.call_deferred(-1)
	shell.toast(tf("launcher.game.device_lost_fmt", [slot + 1]))

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
		cells.add_child(G.stat_cell(Guide.text(stat, "label", shell.locale), Guide.stat_text(stat, result)))
	# A two-player run that kept a score for each player shows both next to the total.
	var finishers: Array = result.get("active_players", []) if result.get("active_players") is Array else []
	if finishers.size() >= 2:
		for slot: int in finishers:
			var mine := _player_state(result, slot)
			if mine.has("score"):
				var cell := G.stat_cell(tf("launcher.game.player_score_fmt", [slot + 1]), LauncherFormat.score(int(mine["score"])))
				cell.name = "PlayerScore%d" % (slot + 1)
				cells.add_child(cell)
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
	# The list sits on the right, where the frozen stage is only lightly dimmed; darken that side so the small text stays readable.
	var shade := C.GradientRect.new([[0.0, T.deep(0.0)], [0.55, T.deep(0.0)], [0.68, T.deep(0.6)], [1.0, T.deep(0.6)]], true)
	_result.add_child(W.fill(shade))
	_result.move_child(shade, 2)
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
