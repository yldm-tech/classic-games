class_name GameFixedStep
extends RefCounted

## Turns variable frame times into a whole number of fixed simulation steps, so game logic advances by the same amount whatever the frame rate is and a test can step it exactly. GameModule owns one and calls _game_step once per step; a game only needs its own instance for a sub-system that runs at a different rate.

## Seconds per step.
var step := 1.0 / 60.0
## Most steps one advance() returns. A long frame (a window drag, a breakpoint) is cut short instead of making the game race to catch up.
var max_steps := 5

var _carry := 0.0

func _init(p_step: float = 1.0 / 60.0, p_max_steps: int = 5) -> void:
	step = maxf(p_step, 0.0001)
	max_steps = maxi(1, p_max_steps)

## Add `delta` seconds and return how many steps are due now.
func advance(delta: float) -> int:
	_carry += maxf(delta, 0.0)
	# The small epsilon keeps a delta that is an exact multiple of the step from losing a step to float rounding.
	var due := int(floor(_carry / step + 0.00001))
	if due > max_steps:
		_carry = 0.0
		return max_steps
	_carry = maxf(0.0, _carry - float(due) * step)
	return due

## How far the current frame is between the last step and the next, 0 .. 1, for drawing that interpolates.
func alpha() -> float:
	return clampf(_carry / step, 0.0, 1.0)

func reset() -> void:
	_carry = 0.0
