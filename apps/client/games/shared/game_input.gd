class_name GameInput
extends RefCounted

## The input state of one player, as a game module sees it. The host decides which keyboard scheme or gamepad drives which player and writes the result here; the game only reads. A game never polls Input, InputMap or raw events.
##
## Controls are logical: four directions and six buttons. On a gamepad they are the d-pad or left stick, A, B, X, Y, LB and RB; on a keyboard they are whatever the player bound in Settings for that player's scheme. Pause is not a control: it belongs to the host.
##
## Reading is tied to the fixed step. GameModule calls tick() once before each _game_step, so just_pressed() and just_released() are true for exactly one step, and a tap that begins and ends between two steps is still seen as pressed for one step.

const UP := &"up"
const DOWN := &"down"
const LEFT := &"left"
const RIGHT := &"right"
const A := &"a"
const B := &"b"
const X := &"x"
const Y := &"y"
const L := &"l"
const R := &"r"

const DIRECTIONS: Array[StringName] = [UP, DOWN, LEFT, RIGHT]
const BUTTONS: Array[StringName] = [A, B, X, Y, L, R]
const CONTROLS: Array[StringName] = [UP, DOWN, LEFT, RIGHT, A, B, X, Y, L, R]
## A control counts as held from this strength on.
const PRESS_THRESHOLD := 0.5

## The direction held this step: x is -1 (left) .. 1 (right), y is -1 (up) .. 1 (down), analogue on a stick, never longer than 1.
var move := Vector2.ZERO

var _raw: Dictionary = {}
var _latched: Dictionary = {}
var _down: Dictionary = {}
var _previous: Dictionary = {}

func _init() -> void:
	clear()

# ---- reading (game side) ----

## Whether the control is held during this step.
func is_down(control: StringName) -> bool:
	return bool(_down.get(control, false))

## True for the one step in which the control went down.
func just_pressed(control: StringName) -> bool:
	return bool(_down.get(control, false)) and not bool(_previous.get(control, false))

## True for the one step in which the control was let go.
func just_released(control: StringName) -> bool:
	return not bool(_down.get(control, false)) and bool(_previous.get(control, false))

## How far the control is pushed, 0 .. 1. Keys and buttons are 0 or 1; stick directions are analogue.
func strength(control: StringName) -> float:
	return float(_raw.get(control, 0.0))

## The held direction as whole steps for grid movement: each component is -1, 0 or 1.
func move_sign() -> Vector2i:
	return Vector2i(int(is_down(RIGHT)) - int(is_down(LEFT)), int(is_down(DOWN)) - int(is_down(UP)))

## Whether any direction or button is held.
func any_down() -> bool:
	for control in CONTROLS:
		if is_down(control):
			return true
	return false

# ---- writing (host side) ----

## Set how far a control is pushed (0 .. 1). Unknown control names are ignored.
func feed(control: StringName, value: float) -> void:
	if not _raw.has(control):
		return
	var clamped := clampf(value, 0.0, 1.0)
	_raw[control] = clamped
	if clamped >= PRESS_THRESHOLD:
		_latched[control] = true

## Advance one step: what was fed since the last tick becomes the state the game reads.
func tick() -> void:
	for control in CONTROLS:
		_previous[control] = _down[control]
		_down[control] = float(_raw[control]) >= PRESS_THRESHOLD or bool(_latched[control])
		_latched[control] = false
	var wanted := Vector2(float(_raw[RIGHT]) - float(_raw[LEFT]), float(_raw[DOWN]) - float(_raw[UP]))
	# A tap latched for this step still moves, even though its strength is already back to zero.
	if wanted == Vector2.ZERO:
		wanted = Vector2(move_sign())
	move = wanted.limit_length(1.0)

## Let go of everything, as on pause or when the player's device goes away. Held controls report just_released on the next step.
func release() -> void:
	for control in CONTROLS:
		_raw[control] = 0.0
		_latched[control] = false

## Forget everything, including the previous step. For the start of a run.
func clear() -> void:
	for control in CONTROLS:
		_raw[control] = 0.0
		_latched[control] = false
		_down[control] = false
		_previous[control] = false
	move = Vector2.ZERO
