class_name GameModule
extends Node2D

## Base class of every game module: the script named by `entry` in a game's manifest (games/<id>/game.json) extends this. It is the whole contract between a game and its host; docs/20-adding-a-game.md is the prose version.
##
## What a game implements (all optional except _game_start and _game_step):
##   _game_start(config)          build the run. config: { options, players, seed, locale, stage_size }
##   _game_step(delta)            advance the simulation by one fixed step (delta is always STEP)
##   _game_frame(delta)           once per rendered frame after the steps: camera, animation, queue_redraw
##   _game_snapshot()             fields for the HUD, the result and achievements
##   _game_player_joined(slot)    a player joined a live run (manifest players.join_in_progress)
##   _game_player_left(slot)      a player left a live run
##   _game_paused(paused)         the run was frozen or resumed
##
## What a game uses:
##   input(slot)                  the GameInput of a player; never Input, InputMap or raw events
##   player_count(), active_players(), is_player_active(slot)
##   score                        the run's score; the host records it
##   rng                          a GameRng seeded from config.seed
##   audio                        a GameAudio for procedural effects and music
##   stage_size                   the logical stage in pixels, origin at the top left
##   elapsed                      simulated seconds, pauses excluded
##   finish(outcome, extra)       end the run
##
## What the host calls: start, set_paused, snapshot, feed, release_inputs, join, leave. A game never calls those on itself and never overrides them.
##
## Stage. The game draws in stage_size logical pixels with the origin at the top left of the visible area. The host scales that to the 1920x1080 canvas by a whole factor; a game never reads the window or the viewport size. A scrolling game adds a Camera2D as a child and moves it; the stage is the camera's view.

## The run ended. `result` is snapshot() plus cleared / defeated / timed_out and whatever finish() was given.
signal finished(result: Dictionary)
## The score changed.
signal score_changed(score: int)

const OUTCOME_CLEARED := &"cleared"
const OUTCOME_DEFEATED := &"defeated"
const OUTCOME_TIMED_OUT := &"timed_out"

## Seconds per simulation step.
const STEP := 1.0 / 60.0
## Local players a run can have.
const MAX_PLAYERS := 2

const Rng := preload("res://games/shared/game_rng.gd")
const FixedStep := preload("res://games/shared/game_fixed_step.gd")
const PlayerInput := preload("res://games/shared/game_input.gd")
const Audio := preload("res://games/shared/game_audio.gd")

var score := 0:
	set(value):
		if value == score:
			return
		score = value
		score_changed.emit(score)

var stage_size := Vector2i(960, 540)
var options: Dictionary = {}
var locale := "zh"
var elapsed := 0.0
var rng: GameRng = Rng.new(1)
var audio: GameAudio

var _inputs: Array[GameInput] = []
var _active: Array[bool] = []
var _fixed: GameFixedStep = FixedStep.new(STEP)
var _started := false
var _finished := false
var _paused := false

func _init() -> void:
	for slot in MAX_PLAYERS:
		_inputs.append(PlayerInput.new())
		_active.append(false)
	audio = Audio.new()
	add_child(audio)

# ---- for the game to override ----

func _game_start(_config: Dictionary) -> void:
	pass

func _game_step(_delta: float) -> void:
	pass

func _game_frame(_delta: float) -> void:
	pass

func _game_snapshot() -> Dictionary:
	return {}

func _game_player_joined(_slot: int) -> void:
	pass

func _game_player_left(_slot: int) -> void:
	pass

func _game_paused(_paused: bool) -> void:
	pass

# ---- for the game to use ----

## The input of the player in this slot (0 is player one). A slot nobody plays reads as nothing held.
func input(slot: int) -> GameInput:
	return _inputs[clampi(slot, 0, MAX_PLAYERS - 1)]

func is_player_active(slot: int) -> bool:
	return slot >= 0 and slot < MAX_PLAYERS and _active[slot]

## Slots that are being played, in order.
func active_players() -> Array[int]:
	var out: Array[int] = []
	for slot in MAX_PLAYERS:
		if _active[slot]:
			out.append(slot)
	return out

func player_count() -> int:
	return active_players().size()

func is_running() -> bool:
	return _started and not _finished

func is_finished() -> bool:
	return _finished

## End the run. `outcome` is OUTCOME_CLEARED (won), OUTCOME_DEFEATED (lost) or OUTCOME_TIMED_OUT (the game's own time limit ran out without a win or a loss). `extra` adds or replaces result fields. The simulation stops at once: no further _game_step or _game_frame is called, and the last frame stays on screen under the result, so anything the player should see before the result (a death animation) has to play before finish() is called. Only the first call of a run counts, and a call from inside _game_start does nothing.
func finish(outcome: StringName, extra: Dictionary = {}) -> void:
	if not is_running():
		return
	var result := snapshot()
	result.merge(extra, true)
	result["cleared"] = outcome == OUTCOME_CLEARED
	result["defeated"] = outcome == OUTCOME_DEFEATED
	result["timed_out"] = outcome == OUTCOME_TIMED_OUT
	_finished = true
	release_inputs()
	audio.stop_music()
	finished.emit(result)

# ---- for the host ----

## Begin a run. config: { options: { option id: value }, players: number of players at the start, seed: int, locale: "zh" | "en", stage_size: Vector2i }. Missing entries take their defaults.
func start(config: Dictionary) -> void:
	options = (config.get("options", {}) as Dictionary).duplicate(true) if config.get("options") is Dictionary else {}
	locale = str(config.get("locale", "zh"))
	if config.get("stage_size") is Vector2i:
		stage_size = config["stage_size"]
	rng.reseed(int(config.get("seed", 1)))
	var players := clampi(int(config.get("players", 1)), 1, MAX_PLAYERS)
	for slot in MAX_PLAYERS:
		_inputs[slot].clear()
		_active[slot] = slot < players
	score = 0
	elapsed = 0.0
	_fixed.reset()
	_finished = false
	_paused = false
	# The run is live only once _game_start has returned: a finish() called while the run is still being built does nothing, so a host never hears of an end before the start.
	_started = false
	var normalised := {"options": options, "players": players, "seed": int(config.get("seed", 1)), "locale": locale, "stage_size": stage_size}
	_game_start(normalised)
	_started = true

## Freeze or resume. Held controls are let go on pause, so nothing stays pressed across it.
func set_paused(paused: bool) -> void:
	if paused == _paused:
		return
	_paused = paused
	if paused:
		release_inputs()
	audio.set_paused(paused)
	_game_paused(paused)

func is_paused() -> bool:
	return _paused

## The live state for the HUD: score, elapsed, player_count and the active slots, plus everything _game_snapshot returns (which wins on a clash). Per-player fields go in `players`, one dictionary per slot.
func snapshot() -> Dictionary:
	var out := {"score": score, "elapsed": elapsed, "player_count": player_count(), "active_players": active_players()}
	out.merge(_game_snapshot(), true)
	return out

## Write one control of one player (0 .. 1). See GameInput.CONTROLS.
func feed(slot: int, control: StringName, strength: float) -> void:
	if slot >= 0 and slot < MAX_PLAYERS:
		_inputs[slot].feed(control, strength)

func release_inputs() -> void:
	for player_input in _inputs:
		player_input.release()

## Add the player in `slot` to a live run. Returns false when the slot is taken or out of range.
func join(slot: int) -> bool:
	if not is_running() or slot < 0 or slot >= MAX_PLAYERS or _active[slot]:
		return false
	_inputs[slot].clear()
	_active[slot] = true
	_game_player_joined(slot)
	return true

## Remove the player in `slot` from a live run. The last player cannot leave. Returns false when nothing changed.
func leave(slot: int) -> bool:
	if not is_running() or not is_player_active(slot) or player_count() <= 1:
		return false
	_active[slot] = false
	_inputs[slot].clear()
	_game_player_left(slot)
	return true

## Run the simulation for `seconds` in whole steps, without waiting for frames. For tests and tools: the result is the same on every machine.
func advance(seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for index in steps:
		if not is_running():
			return
		_tick()

func _process(delta: float) -> void:
	if not is_running() or _paused:
		return
	for index in _fixed.advance(delta):
		if not is_running():
			break
		_tick()
	_game_frame(delta)

func _tick() -> void:
	for slot in MAX_PLAYERS:
		_inputs[slot].tick()
	_game_step(STEP)
	if is_running():
		elapsed += STEP
