class_name PlayView
extends ScreenBase

## Application-owned Runtime host + play HUD/result: live score, hold-to-boost,
## shield absorb, pause (resume/fork/quit), and result (new record / play again).
## SubViewport runs the real Runtime; HUD reads HP, XP, gold, time, and score.

signal exited
signal fork_here_requested(game: Dictionary)
signal play_recorded(game_id: String)

const ShooterPlay := preload("res://runtime/shooter/shooter_play.gd")
const RuntimeLoaderScript := preload("res://runtime/runtime_loader.gd")
const NetworkMatchSessionScript := preload("res://runtime/network_match_session.gd")
const NetworkMatchRuntimeScript := preload("res://runtime/network_match_runtime.gd")
const KILL_INTERVAL := 0.5
const LAPS := 3
const KILLS_PER_LAP := 10  # 每圈击杀数;跑满 LAPS 圈自动结算(原型行为)

const DEFAULT_BEST := 0

var game: Dictionary = {}
var play := ShooterPlay.new()
var best_score := DEFAULT_BEST       # 当前游戏的历史最佳
var _best_by_game: Dictionary = {}   # game_id -> 最佳分,跨局保留但按游戏隔离(不再串味)
var _phase := "playing"  # playing | paused | result
var _result: Dictionary = {}
var _accum := 0.0
var _kills := 0
var _score_label: Label
var _status_label: Label
var _lap_label: Label
var _lap_bar: ProgressBar
var _runtime: Node2D
var _runtime_viewport: SubViewport
var _replay_frames: Array = []
var _replay_elapsed_ms := 0
var _replay_sample_ms := 0
var _network_session := NetworkMatchSessionScript.new()
var _network_send_elapsed := 0.0
var _network_touch_move := Vector2.ZERO
var _network_touch_fire := false
var _local_touch_move := Vector2.ZERO
var engagement_runtime: Variant
var _td_tower_id := ""

func _init(p_state: Node, p_engagement_runtime: Variant = null) -> void:
	engagement_runtime = p_engagement_runtime
	super(p_state)

func rebuild() -> void:
	_detach_runtime()
	super.rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_runtime) and _runtime.get_parent() == null:
		_runtime.free()

func set_game(g: Dictionary) -> void:
	game = g
	_network_session.cancel()
	if is_instance_valid(_runtime): _runtime.free()
	var network_room_id := str(g.get("network_room_id", ""))
	if network_room_id != "":
		_runtime = NetworkMatchRuntimeScript.new()
		_runtime.call("configure", _user_id())
		_network_session = NetworkMatchSessionScript.new()
		_network_session.configure(engagement_runtime, network_room_id, _user_id())
		_network_session.snapshot_updated.connect(_apply_network_snapshot)
		_poll_network()
	else:
		_network_session = NetworkMatchSessionScript.new()
		var runtime_ref := str(g.get("runtime", "shooter@1.0.0"))
		var fallback := _load_baseline(runtime_ref)
		var dsl: Dictionary = g.get("dsl", fallback) if g.get("dsl", fallback) is Dictionary else fallback
		var loader := RuntimeLoaderScript.new()
		_runtime = loader.load_from_dsl(runtime_ref, dsl)
		if _runtime == null:
			push_error("Runtime 加载失败: %s" % str(loader.last_error))
			_runtime = loader.load_from_dsl("shooter@1.0.0", _load_baseline("shooter@1.0.0"))
	play = ShooterPlay.new()
	# 最佳分按游戏隔离:换游戏时载入该游戏自己的历史最佳,而非沿用上一局的。
	best_score = _best_by_game.get(_game_key(), DEFAULT_BEST)
	_phase = "playing"
	_result = {}
	_accum = 0.0
	_kills = 0
	_td_tower_id = ""
	_replay_frames=[];_replay_elapsed_ms=0;_replay_sample_ms=0
	_network_send_elapsed = 0.0; _network_touch_move = Vector2.ZERO; _network_touch_fire = false
	_local_touch_move = Vector2.ZERO
	if is_instance_valid(_runtime):
		_runtime.set_meta("touch_move", Vector2.ZERO)
	rebuild()

func _user_id() -> String:
	return str(state.profile.get("id", ""))

func _game_key() -> String:
	return str(game.get("id", ""))

func _runtime_kind() -> String:
	if is_instance_valid(_runtime):
		return str((_runtime.get_meta("summary", {}) as Dictionary).get("runtime", "shooter"))
	return str(game.get("runtime", "shooter")).split("@")[0]

func _process(delta: float) -> void:
	if _phase == "playing":
		_replay_elapsed_ms += int(delta*1000.0)
		if _network_session.active():
			_drive_network(delta)
		else:
			_replay_sample_ms += int(delta*1000.0)
			if _replay_sample_ms>=100:_replay_sample_ms=0;_sample_replay()
		_sync_runtime_hud()
		if is_instance_valid(_runtime):
			var summary: Dictionary = _runtime.get_meta("summary", {})
			if bool(summary.get("cleared", false)) or bool(summary.get("defeated", false)) or bool(_runtime.get_meta("time_up", false)): finish_run()

func _drive_network(delta: float) -> void:
	_network_send_elapsed += delta
	if _network_send_elapsed < 0.1 or _network_session.request_pending:
		return
	_network_send_elapsed = 0.0
	var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var movement := (keyboard + _network_touch_move).limit_length(1.0)
	_send_network_input(movement, Input.is_action_pressed("ui_accept") or _network_touch_fire)

func _send_network_input(movement: Vector2, fire: bool) -> void:
	var accepted: bool = await _network_session.submit_input(movement, fire)
	if not accepted and not _network_session.request_pending:
		await _network_session.poll()

func _poll_network() -> void:
	if _network_session.active():
		await _network_session.poll()

func _apply_network_snapshot(value: Dictionary) -> void:
	if is_instance_valid(_runtime) and _runtime.get_script() == NetworkMatchRuntimeScript:
		_runtime.call("apply_snapshot", value)

func _sync_runtime_hud() -> void:
	if not is_instance_valid(_runtime): return
	var summary: Dictionary = _runtime.get_meta("summary", {})
	play.score = int(_runtime.get_meta("score")) if _runtime.has_meta("score") else int(summary.get("score", play.score))
	var actor:=_runtime.find_child("Player",true,false)
	if actor == null: actor = _runtime.find_child("Hero",true,false)
	if actor!=null: play.hp=maxi(0,int(actor.get_meta("hp",play.hp)))
	_kills = play.score / ShooterPlay.KILL_POINTS
	if _score_label != null and is_instance_valid(_score_label): _score_label.text = str(play.score)
	if _status_label != null and is_instance_valid(_status_label): _status_label.text = _status_text()
	if _lap_label != null and is_instance_valid(_lap_label): _lap_label.text = txt_fmt("lap_fmt", [lap(), LAPS])
	if _lap_bar != null and is_instance_valid(_lap_bar): _lap_bar.set_value_no_signal(_kills % KILLS_PER_LAP)
	var gold_label := find_child("TdGoldLabel", true, false)
	if gold_label is Label:
		(gold_label as Label).text = txt_fmt("td_gold_fmt", [int(summary.get("gold", 0))])

## 当前圈数(1 起,封顶 LAPS)。
func lap() -> int:
	return mini(LAPS, 1 + _kills / KILLS_PER_LAP)

## 推进游玩:按节奏触发击杀计分(加速翻倍由 ShooterPlay 管)、圈数推进,
## 跑满 LAPS 圈自动结算。headless 测试直接调用。
func simulate(delta: float) -> void:
	# Headless test hook：不在真实帧循环调用。
	_accum += delta
	while _accum >= KILL_INTERVAL:
		_accum -= KILL_INTERVAL
		play.on_kill()
		_kills += 1
		if _kills >= LAPS * KILLS_PER_LAP:
			finish_run()
			return
	if _score_label != null and is_instance_valid(_score_label):
		_score_label.text = str(play.score)
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = _status_text()
	if _lap_label != null and is_instance_valid(_lap_label):
		_lap_label.text = txt_fmt("lap_fmt", [lap(), LAPS])
	if _lap_bar != null and is_instance_valid(_lap_bar):
		_lap_bar.set_value_no_signal(_kills % KILLS_PER_LAP)

func finish_run() -> void:
	_sample_replay()
	var summary: Dictionary = _runtime.get_meta("summary", {}) if is_instance_valid(_runtime) else {}
	_detach_runtime()
	if str(summary.get("runtime", "shooter")) == "shooter":
		_result = play.finish(best_score)
		_result["defeated"] = bool(summary.get("defeated", play.hp <= 0))
	else:
		var score := int(summary.get("score", play.score))
		_result = {"score":score, "cleared":bool(summary.get("cleared", not summary.get("defeated", false))), "defeated":bool(summary.get("defeated", false)), "new_record":score > best_score}
	_result["runtime"] = str(summary.get("runtime", _runtime_kind()))
	for key in ["kills", "level", "gold", "base_hp", "last_upgrade"]:
		if summary.has(key):
			_result[key] = summary[key]
	if _result["new_record"]:
		best_score = _result["score"]
		_best_by_game[_game_key()] = best_score  # persist per-game best
	_phase = "result"
	rebuild()
	if engagement_runtime != null and state.authed: _record_play()
	if engagement_runtime != null and state.authed and _replay_frames.size()>=2:_submit_replay()

func _record_play() -> void:
	var recorded = await engagement_runtime.record_play(_game_key(), maxi(0,_replay_elapsed_ms))
	if recorded.ok:
		play_recorded.emit(_game_key())
	else:
		_toast(recorded.message if recorded.message != "" else "PLAY_RECORD_FAILED")

func _sample_replay()->void:
	if not is_instance_valid(_runtime):return
	var actor:=_replay_subject()
	if actor==null:return
	var at:=_replay_elapsed_ms
	if not _replay_frames.is_empty() and int(_replay_frames[-1].get("at_ms",-1))>=at:return
	play.hp=maxi(0,int(actor.get_meta("hp",play.hp)))
	play.score=maxi(0,int(_runtime.get_meta("score",play.score)))
	_replay_frames.append({"at_ms":at,"x":float(actor.position.x),"y":float(actor.position.y),"hp":play.hp,"score":play.score})

func _replay_subject() -> Node2D:
	if not is_instance_valid(_runtime):
		return null
	for node_name in ["Player", "Hero"]:
		var node := _runtime.find_child(node_name, true, false)
		if node is Node2D:
			return node
	return _runtime as Node2D

func _submit_replay()->void:
	var duration:=maxi(1,_replay_elapsed_ms)
	var submitted=await engagement_runtime.submit_replay(_game_key(),duration,_replay_frames)
	if not submitted.ok: _toast(submitted.message if submitted.message != "" else "REPLAY_SUBMIT_FAILED")

func _build() -> void:
	match _phase:
		"playing":
			_build_hud()
		"paused":
			_build_pause()
		"result":
			_build_result()

func _build_hud() -> void:
	var shooter := _runtime_kind() == "shooter"
	var networked := _network_session.active()
	var top := Widgets.hbox(Tokens.SPACE_3)
	var pause_btn := Widgets.secondary_button("II", theme_name())
	pause_btn.name = "PauseButton"
	pause_btn.pressed.connect(func() -> void:
		_detach_runtime()
		_phase = "paused"
		rebuild())
	top.add_child(pause_btn)
	top.add_child(Widgets.spacer())
	if shooter:
		_lap_label = Widgets.caption(txt_fmt("lap_fmt", [lap(), LAPS]), theme_name(), &"text_secondary")
		_lap_label.name = "LapLabel"
		top.add_child(_lap_label)
	top.add_child(Widgets.caption(GameCard.title_of(game, state.locale), theme_name()))
	content.add_child(top)
	# Lap progress for the shooter prototype (kills in the current lap).
	if shooter:
		_lap_bar = ProgressBar.new()
		_lap_bar.name = "LapBar"
		_lap_bar.max_value = KILLS_PER_LAP
		_lap_bar.value = _kills % KILLS_PER_LAP
		_lap_bar.show_percentage = false
		_lap_bar.custom_minimum_size = Vector2(0, 4)
		content.add_child(_lap_bar)
	_status_label = Widgets.caption(_status_text(), theme_name(), &"text_secondary")
	_status_label.name = "RuntimeStatus"
	content.add_child(_status_label)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "RuntimeViewport"
	viewport_container.custom_minimum_size = Vector2(0, 360)
	viewport_container.stretch = true
	_runtime_viewport = SubViewport.new(); _runtime_viewport.size = Vector2i(960, 540); _runtime_viewport.transparent_bg = false
	viewport_container.add_child(_runtime_viewport)
	if is_instance_valid(_runtime):
		_runtime.position = Vector2(480, 270)
		_runtime_viewport.add_child(_runtime)
	viewport_container.gui_input.connect(_on_runtime_gui_input)
	content.add_child(viewport_container)

	var score_card := Widgets.card(theme_name())
	score_card.name = "ScoreCard"
	var col := Widgets.vbox(Tokens.SPACE_1)
	score_card.add_child(col)
	col.add_child(Widgets.caption(txt("score"), theme_name()))
	_score_label = Widgets.big_number(str(play.score), theme_name(), Tokens.FONT_DISPLAY)
	_score_label.name = "ScoreValue"
	col.add_child(_score_label)
	content.add_child(score_card)

	if shooter:
		var controls := Widgets.hbox(Tokens.SPACE_3)
		var boost := Widgets.primary_button(txt("boost"), theme_name())
		boost.name = "BoostButton"
		boost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boost.button_down.connect(func() -> void:
			play.set_boost(true)
			if is_instance_valid(_runtime) and _runtime.has_method("set_boost"):
				_runtime.set_boost(true))
		boost.button_up.connect(func() -> void:
			play.set_boost(false)
			if is_instance_valid(_runtime) and _runtime.has_method("set_boost"):
				_runtime.set_boost(false))
		controls.add_child(boost)
		var shield := Widgets.ai_button(txt("shield"), theme_name())
		shield.name = "ShieldButton"
		shield.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shield.pressed.connect(func() -> void:
			play.activate_shield()
			if is_instance_valid(_runtime) and _runtime.has_method("grant_shield"):
				_runtime.grant_shield())
		controls.add_child(shield)
		content.add_child(controls)
		_build_local_move_pad()
	elif networked:
		var controls := Widgets.hbox(Tokens.SPACE_2)
		controls.name = "NetworkControls"
		controls.add_child(_network_move_button("←", "NetworkLeftButton", Vector2.LEFT))
		controls.add_child(_network_move_button("↑", "NetworkUpButton", Vector2.UP))
		controls.add_child(_network_move_button("↓", "NetworkDownButton", Vector2.DOWN))
		controls.add_child(_network_move_button("→", "NetworkRightButton", Vector2.RIGHT))
		var fire := Widgets.primary_button("●", theme_name())
		fire.name = "NetworkFireButton"
		fire.button_down.connect(func() -> void: _network_touch_fire = true)
		fire.button_up.connect(func() -> void: _network_touch_fire = false)
		controls.add_child(fire)
		content.add_child(controls)
	elif _runtime_kind() == "survivor":
		_build_local_move_pad()
	elif _runtime_kind() == "tower_defense":
		_build_td_controls()

	if not networked:
		var finish := Widgets.secondary_button(txt("finish_run"), theme_name())
		finish.name = "FinishButton"
		finish.pressed.connect(finish_run)
		content.add_child(finish)
	_sync_runtime_hud()

func _network_move_button(label: String, node_name: String, direction: Vector2) -> Button:
	var button := Widgets.secondary_button(label, theme_name())
	button.name = node_name
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.button_down.connect(func() -> void: _network_touch_move += direction)
	button.button_up.connect(func() -> void: _network_touch_move -= direction)
	return button

func _build_local_move_pad() -> void:
	var controls := Widgets.hbox(Tokens.SPACE_2)
	controls.name = "LocalMovePad"
	controls.add_child(_local_move_button("←", "LocalLeftButton", Vector2.LEFT))
	controls.add_child(_local_move_button("↑", "LocalUpButton", Vector2.UP))
	controls.add_child(_local_move_button("↓", "LocalDownButton", Vector2.DOWN))
	controls.add_child(_local_move_button("→", "LocalRightButton", Vector2.RIGHT))
	content.add_child(controls)

func _local_move_button(label: String, node_name: String, direction: Vector2) -> Button:
	var button := Widgets.secondary_button(label, theme_name())
	button.name = node_name
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.button_down.connect(func() -> void:
		_local_touch_move += direction
		_apply_local_touch())
	button.button_up.connect(func() -> void:
		_local_touch_move -= direction
		_apply_local_touch())
	return button

func _apply_local_touch() -> void:
	if is_instance_valid(_runtime):
		_runtime.set_meta("touch_move", _local_touch_move.limit_length(1.0))

func _status_text() -> String:
	if not is_instance_valid(_runtime):
		return ""
	var summary: Dictionary = _runtime.get_meta("summary", {})
	var kind := str(summary.get("runtime", _runtime_kind()))
	var parts: PackedStringArray = []
	match kind:
		"survivor":
			parts.append(txt_fmt("hp_fmt", [play.hp]))
			parts.append(txt_fmt("level_xp_fmt", [int(summary.get("level", 1)), int(summary.get("xp", 0))]))
			var left := maxi(0, ceili(float(summary.get("duration", 0)) - float(summary.get("elapsed", 0))))
			parts.append(txt_fmt("time_left_fmt", [left]))
			var upgrade := str(summary.get("last_upgrade", ""))
			if upgrade != "":
				parts.append(txt_fmt("upgrade_applied_fmt", [_upgrade_label(upgrade)]))
		"tower_defense":
			parts.append(txt_fmt("td_gold_fmt", [int(summary.get("gold", 0))]))
			parts.append(txt_fmt("base_hp_fmt", [int(summary.get("base_hp", 0))]))
			parts.append(txt_fmt("wave_fmt", [int(summary.get("current_wave", 0)), int(summary.get("wave_count", 0))]))
			parts.append(txt_fmt("enemies_left_fmt", [int(summary.get("enemy_active", 0))]))
		_:
			parts.append(txt_fmt("hp_fmt", [play.hp]))
			if summary.has("enemy_left"):
				parts.append(txt_fmt("enemies_left_fmt", [int(summary.get("enemy_left", 0))]))
			var time_left := int(summary.get("time_left", 0))
			if time_left <= 0:
				time_left = int(_runtime.get_meta("duration", 0))
			if time_left > 0:
				parts.append(txt_fmt("time_left_fmt", [time_left]))
	return " · ".join(parts)

func _upgrade_label(id: String) -> String:
	var key := "upgrade_%s" % id
	var label: Variant = txt(key)
	return str(label) if str(label) != key else id

func _result_status_text() -> String:
	var parts: PackedStringArray = []
	if int(_result.get("kills", 0)) > 0:
		parts.append(txt_fmt("result_kills_fmt", [int(_result.get("kills", 0))]))
	if int(_result.get("level", 0)) > 0:
		parts.append(txt_fmt("result_level_fmt", [int(_result.get("level", 0))]))
	if _result.has("gold"):
		parts.append(txt_fmt("td_gold_fmt", [int(_result.get("gold", 0))]))
	if _result.has("base_hp"):
		parts.append(txt_fmt("base_hp_fmt", [int(_result.get("base_hp", 0))]))
	var upgrade := str(_result.get("last_upgrade", ""))
	if upgrade != "":
		parts.append(txt_fmt("upgrade_applied_fmt", [_upgrade_label(upgrade)]))
	return " · ".join(parts)

func _build_td_controls() -> void:
	if not is_instance_valid(_runtime) or not _runtime.has_method("tower_ids"):
		return
	var ids: PackedStringArray = _runtime.tower_ids()
	if ids.is_empty():
		return
	if _td_tower_id == "" or _td_tower_id not in ids:
		_td_tower_id = ids[0]
	var gold := int((_runtime.get_meta("summary", {}) as Dictionary).get("gold", 0))
	var row := Widgets.hbox(Tokens.SPACE_2)
	row.name = "TowerBuildRow"
	var gold_label := Widgets.caption(txt_fmt("td_gold_fmt", [gold]), theme_name())
	gold_label.name = "TdGoldLabel"
	row.add_child(gold_label)
	for id in ids:
		var tower_id := str(id)
		var btn := Widgets.secondary_button(tower_id, theme_name()) if _td_tower_id != tower_id else Widgets.primary_button(tower_id, theme_name())
		btn.name = "TowerPick_%s" % tower_id
		btn.pressed.connect(func() -> void:
			_td_tower_id = tower_id
			rebuild())
		row.add_child(btn)
	content.add_child(row)

func _on_runtime_gui_input(event: InputEvent) -> void:
	if _phase != "playing" or _runtime_kind() != "tower_defense":
		return
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _td_tower_id == "" or not is_instance_valid(_runtime) or not _runtime.has_method("place_tower"):
		return
	var container := find_child("RuntimeViewport", true, false)
	if container == null:
		return
	var size: Vector2 = (container as Control).size
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var local: Vector2 = event.position
	var vp := Vector2(local.x / size.x * 960.0, local.y / size.y * 540.0)
	var at := vp - _runtime.position
	_runtime.place_tower("play_%d" % Time.get_ticks_msec(), {"tower": _td_tower_id, "position": [at.x, at.y]})
	_sync_runtime_hud()

func _build_pause() -> void:
	var card := Widgets.card(theme_name(), &"surface_raised")
	card.name = "PauseMenu"
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	col.add_child(Widgets.heading(txt("paused"), 2, theme_name()))
	# 与顶部徽章一致的实时圈数(原型修过「暂停菜单圈数硬编码」的坑)
	var pause_caption := GameCard.title_of(game, state.locale)
	if _runtime_kind() == "shooter": pause_caption += " · " + txt_fmt("lap_fmt", [lap(), LAPS])
	col.add_child(Widgets.caption(pause_caption, theme_name()))
	var pause_status := Widgets.caption(_status_text(), theme_name(), &"text_secondary")
	pause_status.name = "PauseStatus"
	col.add_child(pause_status)
	var resume := Widgets.primary_button(txt("resume"), theme_name())
	resume.name = "ResumeButton"
	resume.pressed.connect(func() -> void:
		_phase = "playing"
		rebuild())
	col.add_child(resume)
	if GameCard.forkable(game):
		var fork := Widgets.secondary_button(txt("fork_here"), theme_name())
		fork.name = "ForkHereButton"
		fork.pressed.connect(func() -> void: fork_here_requested.emit(game))
		col.add_child(fork)
	var quit := Widgets.danger_button(txt("exit"), theme_name())
	quit.name = "ExitButton"
	quit.pressed.connect(func() -> void: exited.emit())
	col.add_child(quit)
	content.add_child(card)

func _detach_runtime() -> void:
	if is_instance_valid(_runtime) and _runtime.get_parent() != null:
		_runtime.get_parent().remove_child(_runtime)

func _load_baseline(runtime_ref: String = "shooter@1.0.0") -> Dictionary:
	var name := runtime_ref.split("@")[0]
	if name not in ["shooter", "survivor", "tower_defense"]: name = "shooter"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/%s/baseline.dsl.json" % name))
	return parsed if parsed is Dictionary else {}

func _build_result() -> void:
	var card := Widgets.card(theme_name())
	card.name = "ResultCard"
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	col.add_child(Widgets.heading(txt("result_title"), 1, theme_name()))
	if _result.get("defeated", false):
		var outcome := Widgets.badge(txt("result_defeated"), theme_name(), true)
		outcome.name = "ResultOutcome"
		col.add_child(outcome)
	elif _result.get("cleared", false):
		var outcome := Widgets.badge(txt("result_cleared"), theme_name(), true)
		outcome.name = "ResultOutcome"
		col.add_child(outcome)
	if _result.get("new_record", false):
		col.add_child(Widgets.badge(txt("new_best"), theme_name(), true))
	var score := Widgets.big_number(str(_result.get("score", 0)), theme_name(), Tokens.FONT_DISPLAY)
	score.name = "ResultScore"
	col.add_child(score)
	var extras := _result_status_text()
	if extras != "":
		var extra_label := Widgets.caption(extras, theme_name(), &"text_secondary")
		extra_label.name = "ResultStatus"
		col.add_child(extra_label)
	var i18n := preload("res://i18n/i18n.gd")
	col.add_child(Widgets.caption("%s %s" % [txt("best_label"), i18n.format_number(best_score, state.locale)], theme_name()))
	var again := Widgets.primary_button(txt("again"), theme_name())
	again.name = "AgainButton"
	again.pressed.connect(func() -> void: set_game(game))
	col.add_child(again)
	var done := Widgets.secondary_button(txt("back_to_detail"), theme_name())
	done.name = "DoneButton"
	done.pressed.connect(func() -> void: exited.emit())
	col.add_child(done)
	content.add_child(card)
