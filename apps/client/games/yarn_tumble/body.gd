extends RefCounted

## Anything the tile physics can move: a rectangle anchored at the centre of its bottom edge (x, y), `hw` wide to each side and `h` tall.

var x := 0.0
var y := 0.0
var vx := 0.0
var vy := 0.0
var hw := 5.0
var h := 12.0
var on_ground := false
