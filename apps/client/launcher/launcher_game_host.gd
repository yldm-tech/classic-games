class_name LauncherGameHost
extends Control

## Runs one catalog game inside the launcher and writes what really happened into the store.
## This is the launcher's only user of the runtime, and it talks to it through GameSession alone: start_run, set_paused, snapshot, perform, end_run and the session's signals. Screens (game HUD, pause, game menu) drive the host; they never touch the session or the runtime nodes.
##
## The host is a shell layer, not a screen: it stays mounted while the game and pause screens swap on top of it, and LauncherRoot shows it whenever the current screen's backdrop() asks for the &"game" layer.

## A run began. The stage is live from this point.
signal run_started(game_id: String)
## A run ended, by itself or because quit() was called. `result` is GameSession's game_ended result (score, play_seconds, cleared, defeated, timed_out, aborted, plus runtime fields). `record` is { new_best, previous_best, unlocked: [achievement ids newly unlocked by this run] }. The store is already updated when this fires.
signal run_finished(game_id: String, result: Dictionary, record: Dictionary)
## The runtime refused to start. `error` is GameSession's { code, msg }.
signal run_failed(game_id: String, error: Dictionary)
signal score_changed(score: int)
signal paused_changed(paused: bool)

var store: LauncherStore
## Returns the current unix time; LauncherRoot injects its own so tests can fix the clock.
var now_provider := func() -> int: return int(Time.get_unix_time_from_system())

var _session: GameSession
var _viewport: SubViewport
var _game_id := ""
var _options: Dictionary = {}
var _last_error: Dictionary = {}

func _init() -> void:
	name = "GameHost"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var container := SubViewportContainer.new()
	container.name = "Stage"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)
	# The viewport has the canvas's own pixel size and maps the runtime's logical stage onto it, so the runtimes keep drawing in STAGE_SIZE coordinates while their shapes are rasterised at full resolution instead of being drawn small and blown up.
	_viewport = SubViewport.new()
	_viewport.name = "StageViewport"
	_viewport.size = Vector2i(LauncherTokens.CANVAS)
	_viewport.size_2d_override = GameSession.STAGE_SIZE
	_viewport.size_2d_override_stretch = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	container.add_child(_viewport)
	_session = GameSession.new()
	_session.name = "GameSession"
	_viewport.add_child(_session)
	_session.game_ended.connect(_on_game_ended)
	_session.game_error.connect(func(error: Dictionary) -> void: _last_error = error)
	_session.score_changed.connect(func(score: int) -> void: score_changed.emit(score))
	_session.paused_changed.connect(func(paused: bool) -> void: paused_changed.emit(paused))

func _notification(what: int) -> void:
	# Closing the window or tearing the launcher down with a run still live ends that run like any other quit, so its play time and score are recorded. end_run does nothing once a run is over, which is what keeps every run recorded exactly once.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _session != null and store != null:
			quit()

## Start the catalog game with this id. Any run still live is ended (and recorded) first. Returns false and emits run_failed when the game is unknown or its runtime will not start.
## `options` are the game's own start options from LauncherGameGuide ({ option id: value }, e.g. { "difficulty": 3 }); each one becomes a JSON Patch on the runtime's baseline, so the run is the baseline with exactly those values replaced.
func launch(game_id: String, options: Dictionary = {}) -> bool:
	quit()
	var entry := LauncherCatalog.by_id(game_id)
	_last_error = {}
	var payload := GameSession.baseline_payload(str(entry.get("runtime", ""))) if not entry.is_empty() else {}
	if payload.is_empty():
		_last_error = {"code": "UNKNOWN_GAME", "msg": game_id}
		run_failed.emit(game_id, _last_error)
		return false
	var patch := LauncherGameGuide.option_patch(game_id, options)
	if not patch.is_empty():
		payload = {"runtime": payload["runtime"], "baseline": payload["mod"], "patches": [patch]}
	_game_id = game_id
	_options = options.duplicate()
	if not _session.start_run(payload):
		_game_id = ""
		run_failed.emit(game_id, _last_error)
		return false
	LauncherGameGuide.apply_volume(LauncherGameGuide.stored_volume(store))
	run_started.emit(game_id)
	return true

## End the live run as "the player left". It is recorded like any other run and run_finished fires with result.aborted = true. Does nothing when no run is live.
func quit() -> void:
	_session.end_run()

## End the live run (recorded as a quit) and start the same game again with the same options. Returns false when there is no game on the stage.
func restart() -> bool:
	return _game_id != "" and launch(_game_id, _options)

## The start options of the run on the stage.
func run_options() -> Dictionary:
	return _options.duplicate()

## Remove the finished run's frozen last frame from the stage.
func clear_stage() -> void:
	quit()
	_session.clear_run()
	_game_id = ""

func is_running() -> bool:
	return _session.is_running()

func is_paused() -> bool:
	return _session.is_paused()

func set_paused(paused: bool) -> void:
	_session.set_paused(paused)

## Id of the game on the stage (live or just finished), "" when the stage is empty.
func game_id() -> String:
	return _game_id

## GameSession.snapshot(): live score, play_seconds, hp and max_hp, shield and boss state, the tower catalogue and the runtime's own summary fields, for a HUD.
func snapshot() -> Dictionary:
	return _session.snapshot()

## GameSession.perform(): "move", "boost", "shield", "place_tower". Positions are stage coordinates; use to_stage() to convert a canvas point.
func perform(action: String, args: Dictionary = {}) -> bool:
	return _session.perform(action, args)

## Convert a point on the 1920x1080 canvas into stage coordinates.
func to_stage(canvas_point: Vector2) -> Vector2:
	return canvas_point * Vector2(GameSession.STAGE_SIZE) / LauncherTokens.CANVAS

## Convert stage coordinates into a point on the canvas.
func to_canvas(stage_point: Vector2) -> Vector2:
	return stage_point * LauncherTokens.CANVAS / Vector2(GameSession.STAGE_SIZE)

func _on_game_ended(result: Dictionary) -> void:
	var now: int = now_provider.call()
	var record: Dictionary = store.record_run(_game_id, result, now)
	var unlocked: Array[String] = []
	for achievement_id in LauncherCatalog.earned(_game_id, result):
		if store.unlock(_game_id, achievement_id, now):
			unlocked.append(achievement_id)
	record["unlocked"] = unlocked
	run_finished.emit(_game_id, result, record)
