class_name LauncherGameHost
extends Control

## Runs one catalog game inside the launcher and writes what really happened into the store.
## This is the launcher's only user of the runtime, and it talks to it through GameSession alone: start_run, set_paused, snapshot, perform, end_run and the session's signals. Screens (game HUD, pause, game menu) drive the host; they never touch the session or the runtime nodes.
##
## It hosts both kinds of game the same way. What differs is input: a DSL game gets commands (perform), a game module gets per-player controls. For a module the host owns `players` (who plays on which device), turns every input event into control changes (feed_event) and shapes the stage to the size the module's manifest asks for.
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
## The set of playing slots of the live run changed (a player joined or left).
signal players_changed
## The gamepad a player was playing on was unplugged during a live run of a game module.
signal player_device_lost(slot: int)

var store: LauncherStore
## Returns the current unix time; LauncherRoot injects its own so tests can fix the clock.
var now_provider := func() -> int: return int(Time.get_unix_time_from_system())

## Player slots and their devices, for game modules.
var players := LauncherPlayers.new()
## Language handed to a game module at start. LauncherRoot keeps it current.
var locale := "zh"
## Seed handed to a game module; 0 lets the session pick one from the clock. Tests and the screenshot tool fix it.
var run_seed := 0
## The slot whose player paused the live run, -1 when the pause belongs to nobody in particular (focus loss, an unplugged gamepad).
var pause_owner := -1

var _session: GameSession
var _container: SubViewportContainer
var _viewport: SubViewport
var _stage: Dictionary = GameSession.stage_for({})
var _player_count := 1
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
	_container = container
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

## Start the catalog game with this id. Any run still live is ended (and recorded) first. Returns false and emits run_failed when the game is unknown or will not start.
## `options` are the game's own start options from LauncherGameGuide ({ option id: value }, e.g. { "difficulty": 3 }). For a DSL game each one becomes a JSON Patch on the runtime's baseline, so the run is the baseline with exactly those values replaced; a game module receives the values as they are. `player_count` is clamped to what the game supports.
func launch(game_id: String, options: Dictionary = {}, player_count: int = 1) -> bool:
	quit()
	var entry := LauncherCatalog.by_id(game_id)
	_last_error = {}
	var payload := {}
	var limits := LauncherGameGuide.player_range(game_id)
	var wanted := clampi(player_count, limits.x, limits.y)
	if LauncherGameGuide.is_module(game_id):
		payload = {"game": entry, "options": options, "players": wanted, "seed": run_seed, "locale": locale}
	elif not entry.is_empty():
		payload = GameSession.baseline_payload(str(entry.get("runtime", "")))
		var patch := LauncherGameGuide.option_patch(game_id, options)
		if not payload.is_empty() and not patch.is_empty():
			payload = {"runtime": payload["runtime"], "baseline": payload["mod"], "patches": [patch]}
	if payload.is_empty():
		_last_error = {"code": "UNKNOWN_GAME", "msg": game_id}
		run_failed.emit(game_id, _last_error)
		return false
	_game_id = game_id
	_options = options.duplicate()
	_player_count = wanted
	pause_owner = -1
	players.set_count(wanted)
	players.release_all()
	_shape_stage(GameSession.stage_for(entry))
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
	return _game_id != "" and launch(_game_id, _options, _player_count)

## Size the stage viewport for a game. A pixel-art stage is rendered at its own logical resolution and enlarged by a whole factor with nearest filtering, so every stage pixel is one crisp block. Any other stage is rendered at the canvas's full resolution with its logical coordinates mapped onto it, so shapes stay sharp. The container owns the viewport's pixel size (the canvas divided by stretch_shrink); only the shrink factor and the 2D override are set here.
func _shape_stage(stage: Dictionary) -> void:
	_stage = stage
	var pixel_art := bool(stage["pixel_art"])
	_container.stretch_shrink = int(stage["scale"]) if pixel_art else 1
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST if pixel_art else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_viewport.snap_2d_transforms_to_pixel = pixel_art
	_viewport.size_2d_override = Vector2i.ZERO if pixel_art else (stage["size"] as Vector2i)
	_viewport.size_2d_override_stretch = not pixel_art

## The stage of the game on it: { size: Vector2i, pixel_art, scale, centered }.
func stage() -> Dictionary:
	return _stage

func stage_size() -> Vector2i:
	return _stage["size"]

# ---- players and per-player input (game modules) ----

## Whether the game on the stage is a game module, which is played through per-player controls.
func is_module() -> bool:
	return _session.is_module()

## Slots being played in the live run.
func active_players() -> Array[int]:
	return _session.active_players()

## Pass an input event to the players of the live module. It is not consumed: the launcher still sees it (pause, for one). Does nothing for a DSL game, a paused run or a finished one.
func feed_event(event: InputEvent) -> void:
	if not _session.is_running() or _session.is_paused() or not _session.is_module():
		return
	for change: Array in players.translate(event):
		_session.set_control(int(change[0]), change[1], float(change[2]))

## Let go of every control of every player, e.g. when the window loses focus.
func release_controls() -> void:
	players.release_all()
	_session.release_controls()

## Write one control directly, bypassing devices. For tools that script a player (the screenshot tool).
func set_control(slot: int, control: StringName, strength: float) -> bool:
	return _session.set_control(slot, control, strength)

## Add player two to the live run, or take them out. Only for a game whose manifest allows joining in progress. Returns false when nothing changed.
func add_player() -> bool:
	if not LauncherGameGuide.joins_in_progress(_game_id) or not _session.add_player(1):
		return false
	_player_count = 2
	players.set_count(2)
	players_changed.emit()
	return true

func remove_player() -> bool:
	if not LauncherGameGuide.joins_in_progress(_game_id) or not _session.remove_player(1):
		return false
	_player_count = 1
	players.set_count(1)
	pause_owner = -1
	players_changed.emit()
	return true

## Called by the shell when a gamepad was plugged in or unplugged. Whatever an unplugged gamepad was holding is let go, with any number of players. A player who lost the gamepad they were playing on (the slot's own device with two players, the gamepad last used with one) also has all controls released and is announced, so the game screen can pause.
func pads_changed() -> void:
	if not _session.is_running() or not _session.is_module():
		return
	for change: Array in players.release_missing_pads():
		_session.set_control(int(change[0]), change[1], float(change[2]))
	# With one player every device plays, so no slot "has" a gamepad to lose; the one being played on going away is announced the same way.
	if players.count <= 1 and players.take_lost_active_pad():
		release_controls()
		player_device_lost.emit(0)
	for slot in players.disconnected_slots():
		release_controls()
		player_device_lost.emit(slot)

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
	if not paused:
		pause_owner = -1
	players.release_all()
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
	return canvas_point * Vector2(stage_size()) / LauncherTokens.CANVAS

## Convert stage coordinates into a point on the canvas.
func to_canvas(stage_point: Vector2) -> Vector2:
	return stage_point * LauncherTokens.CANVAS / Vector2(stage_size())

func _on_game_ended(result: Dictionary) -> void:
	var now: int = now_provider.call()
	var record: Dictionary = store.record_run(_game_id, result, now)
	var unlocked: Array[String] = []
	for achievement_id in LauncherCatalog.earned(_game_id, result):
		if store.unlock(_game_id, achievement_id, now):
			unlocked.append(achievement_id)
	record["unlocked"] = unlocked
	run_finished.emit(_game_id, result, record)
