extends "res://games/yarn_tumble/body.gd"

## Something that flies or falls on its own: a pick-up, a hazard thrown by a creature, or a knocked-out creature tumbling off the screen.

## Pick-ups.
const GEMS := ["button", "thimble", "ribbon", "spool"]
const GEM_POINTS := {"button": 200, "thimble": 500, "ribbon": 1000, "spool": 2000}
const POWERS := ["long", "rapid", "thick", "swift"]
const HEART := "heart"
## Hazards.
const INK := "ink"
const PIN := "pin"
const WAVE := "wave"
const EGG := "egg"

var kind := "button"
var life := 0.0
var facing := 1
var spin := 0.0

func _init(what: String = "button", at_x: float = 0.0, at_y: float = 0.0) -> void:
	kind = what
	x = at_x
	y = at_y
	hw = 4.0
	h = 8.0
