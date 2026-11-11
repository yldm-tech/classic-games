extends "res://games/yarn_tumble/body.gd"

## A floor guardian. Kind 0 is Duchess Dustwing (a great moth that swoops), kind 1 is the Snipjaw Regent (a walking pair of shears).

const DUCHESS := 0
const REGENT := 1

var kind := DUCHESS
var hp := 1
var max_hp := 1
var state := "enter"
var timer := 0.0
var clock := 0.0
var facing := -1
var flash := 0.0
var swoops := 0
var cycle := 0
var summon := 2.0
var from_x := 0.0
var from_y := 0.0
var to_x := 0.0
var progress := 0.0

func _init(what: int = DUCHESS) -> void:
	kind = what
	hw = 14.0 if what == DUCHESS else 15.0
	h = 24.0 if what == DUCHESS else 30.0

func enraged() -> bool:
	return hp * 2 <= max_hp

func is_fighting() -> bool:
	return state != "dying"
