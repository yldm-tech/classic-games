extends "res://games/yarn_tumble/body.gd"

## One creature of the tower, through its whole life: dropping in, roaming, half wrapped, a finished ball, a rolling ball.

const SPAWN := 0
const ROAM := 1
const WRAP := 2
const BALL := 3
const ROLL := 4
const GONE := 5

const MOTH := "moth"
const SPRING := "spring"
const PIN := "pin"
const SNIP := "snip"
const INK := "ink"
const KINDS := [MOTH, SPRING, PIN, SNIP, INK]
## Yarn hits needed to finish the ball.
const NEED := {MOTH: 3, SPRING: 3, PIN: 5, SNIP: 3, INK: 4}

var kind := MOTH
var state := SPAWN
var facing := 1
var timer := 0.0
var ai_timer := 0.0
## 0 roaming, 1 winding up (a charge or a spit), 2 charging.
var mode := 0
var wrap := 0
var need := 3
var unwrap := 0.0
var angry := false
## Slot of the knitter who last hit or kicked it.
var owner := 0
var push := 0
var dir := 1
var chain := 0
var bounces := 0
var roll_time := 0.0
var edge_go := false
var flash := 0.0
var phase := 0.0
var anim := 0.0

func _init(what: String = MOTH) -> void:
	kind = what
	need = int(NEED[what])
	hw = 6.0
	h = 12.0

func is_live() -> bool:
	return state != GONE

func is_ball() -> bool:
	return state == BALL or state == ROLL
