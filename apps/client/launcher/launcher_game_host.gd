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
	# The canvas is exactly twice the runtime stage, so the stage renders at its own resolution and is scaled up as a whole.
	container.stretch_shrink = roundi(LauncherTokens.CANVAS.x / GameSession.STAGE_SIZE.x)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.name = "StageViewport"
	_viewport.size = GameSession.STAGE_SIZE
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

## Start the catalog game with this id. Any run still live is ended (and recorded) first. Returns false and emits run_failed when the game is unknown or its runtime will not start.
func launch(game_id: String) -> bool:
	quit()
	var entry := LauncherCatalog.by_id(game_id)
	_last_error = {}
	var payload := GameSession.baseline_payload(str(entry.get("runtime", ""))) if not entry.is_empty() else {}
	if payload.is_empty():
		_last_error = {"code": "UNKNOWN_GAME", "msg": game_id}
		run_failed.emit(game_id, _last_error)
		return false
	_game_id = game_id
	if not _session.start_run(payload):
		_game_id = ""
		run_failed.emit(game_id, _last_error)
		return false
	run_started.emit(game_id)
	return true

## End the live run as "the player left". It is recorded like any other run and run_finished fires with result.aborted = true. Does nothing when no run is live.
func quit() -> void:
	_session.end_run()

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

## GameSession.snapshot(): live score, play_seconds, hp and the runtime's own summary fields, for a HUD.
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
