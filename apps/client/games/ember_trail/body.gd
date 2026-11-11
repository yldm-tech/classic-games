extends RefCounted

## Anything that moves through the tiles: a box whose `pos` is the middle of its bottom edge.

var pos := Vector2.ZERO
var vel := Vector2.ZERO
## Half the width and the full height of the box.
var hw := 5.0
var h := 20.0
var on_ground := false
var hit_wall := false
## The tile the box stands on (World.EMPTY while in the air) and where it is.
var ground_tile := 0
var ground_tx := 0
var ground_ty := 0

func rect() -> Rect2:
	return Rect2(pos.x - hw, pos.y - h, hw * 2.0, h)
