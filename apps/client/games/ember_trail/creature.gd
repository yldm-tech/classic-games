extends "res://games/ember_trail/body.gd"

## One creature or boss. What it does each step is in creatures.gd and bosses.gd; this is only its state.

var kind := ""
## The sprite it is drawn with.
var sprite := ""
var hp := 1
var max_hp := 1
var points := 100
var dir := -1
var t := 0.0
var state := ""
var flash := 0.0
var home := Vector2.ZERO
var flying := false
## It only starts to act once the camera has come near.
var awake := false
var gone := false
var frame := 0
## Per-kind extras (a boss's attack counter and so on).
var data: Dictionary = {}
