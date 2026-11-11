extends "res://games/yarn_tumble/body.gd"

## One knitter. Slot 0 is Pim (blue), slot 1 is Nell (orange).

const ALIVE := 0
const DYING := 1
## Out of lives with no continue left; comes back with one life on the next floor if a partner carries the run there.
const OUT := 2
## Nobody sits in this slot.
const ABSENT := 3

var slot := 0
var state := ABSENT
## Whether this seat has been played at any time in this run.
var seated := false
var facing := 1
var lives := 0
var score := 0
var timer := 0.0
var invuln := 0.0
var cooldown := 0.0
var shoot_anim := 0.0
var coyote := 0.0
var buffer := 0.0
## Seconds spent running without a stop, for the run cycle.
var anim := 0.0
## Power-ups, lost with a life: longer reach, faster needle, double wrap, faster feet.
var long_needle := false
var rapid := false
var thick := false
var swift := false

func _init(seat: int = 0) -> void:
	slot = seat
	hw = 4.0
	h = 13.0

func clear_powers() -> void:
	long_needle = false
	rapid = false
	thick = false
	swift = false
