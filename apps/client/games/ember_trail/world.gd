extends RefCounted

## The tile grid of one stage and everything in it that carries weight: solid ground, one-way ledges, crumbling slabs and moving platforms. Collision is done here by hand, one axis at a time, so a run replays exactly.

const TILE := 16
const ROWS := 17
const EMPTY := 0
const SOLID := 1
const ONEWAY := 2
const SPIKE := 3
const ICE := 4
const CRUMBLE := 5
## Seconds a crumbling slab holds after it is stepped on, and until it grows back.
const CRUMBLE_HOLD := 0.5
const CRUMBLE_BACK := 3.5

var width := 0
var tiles := PackedByteArray()
## Moving platforms: { x, y, w, x0, y0, range, period, phase, axis, dx, dy }. dx / dy is how far the platform moved in the last step.
var plats: Array = []
## Crumbling slabs that were stepped on: tile index -> { t, gone }.
var crumbling: Dictionary = {}

func tile(tx: int, ty: int) -> int:
	if tx < 0 or tx >= width:
		return SOLID
	if ty < 0 or ty >= ROWS:
		return EMPTY
	return tiles[ty * width + tx]

func solid(tx: int, ty: int) -> bool:
	var code := tile(tx, ty)
	return code == SOLID or code == ICE

## Whether something can stand on the tile.
func standable(tx: int, ty: int) -> bool:
	var code := tile(tx, ty)
	return code == SOLID or code == ICE or code == ONEWAY or code == CRUMBLE

func solid_at(point: Vector2) -> bool:
	return solid(int(floor(point.x / TILE)), int(floor(point.y / TILE)))

## The top of the first standable tile at or below `from_y` in the column of `x`, or a value below the stage when there is none (a pit).
func ground_y(x: float, from_y: float) -> float:
	var tx := int(floor(x / TILE))
	for ty in range(maxi(0, int(floor(from_y / TILE))), ROWS):
		if standable(tx, ty):
			return float(ty * TILE)
	return float(ROWS * TILE + 64)

## Move a body by its velocity for one step: sideways first, then up or down. Sets on_ground, hit_wall and the ground tile.
func move_body(body: RefCounted, delta: float) -> void:
	var next_x: float = body.pos.x + body.vel.x * delta
	body.hit_wall = false
	if body.vel.x != 0.0:
		var side := 1.0 if body.vel.x > 0.0 else -1.0
		var tx := int(floor((next_x + side * body.hw) / TILE))
		var top := int(floor((body.pos.y - body.h) / TILE))
		var bottom := int(floor((body.pos.y - 0.01) / TILE))
		for ty in range(top, bottom + 1):
			if solid(tx, ty):
				next_x = float(tx * TILE) - body.hw - 0.01 if side > 0.0 else float((tx + 1) * TILE) + body.hw + 0.01
				body.vel.x = 0.0
				body.hit_wall = true
				break
	body.pos.x = next_x

	var next_y: float = body.pos.y + body.vel.y * delta
	body.on_ground = false
	body.ground_tile = EMPTY
	var left := int(floor((body.pos.x - body.hw + 0.5) / TILE))
	var right := int(floor((body.pos.x + body.hw - 0.5) / TILE))
	if body.vel.y >= 0.0:
		for ty in range(int(floor(body.pos.y / TILE)), int(floor(next_y / TILE)) + 1):
			for tx in range(left, right + 1):
				var code := tile(tx, ty)
				var lands := code == SOLID or code == ICE
				# A ledge only catches what comes down onto it from above.
				if (code == ONEWAY or code == CRUMBLE) and body.pos.y <= float(ty * TILE) + 0.01:
					lands = true
				if lands and (not body.on_ground or code == ICE or absf(float(tx * TILE + 8) - body.pos.x) < absf(float(body.ground_tx * TILE + 8) - body.pos.x)):
					body.on_ground = true
					body.ground_tile = code
					body.ground_tx = tx
					body.ground_ty = ty
			if body.on_ground:
				next_y = float(ty * TILE)
				body.vel.y = 0.0
				break
	else:
		var ty := int(floor((next_y - body.h) / TILE))
		for tx in range(left, right + 1):
			if solid(tx, ty):
				next_y = float((ty + 1) * TILE) + body.h
				body.vel.y = 0.0
				break
	body.pos.y = next_y

## Put every moving platform where it is at `time` seconds into the stage.
func step_plats(time: float) -> void:
	for plat: Dictionary in plats:
		var swing := 0.5 - 0.5 * cos(time * TAU / float(plat["period"]) + float(plat["phase"]))
		var x := float(plat["x0"])
		var y := float(plat["y0"])
		if plat["axis"] == "x":
			x += float(plat["range"]) * swing
		else:
			y += float(plat["range"]) * swing
		plat["dx"] = x - float(plat["x"])
		plat["dy"] = y - float(plat["y"])
		plat["x"] = x
		plat["y"] = y

## Start a slab crumbling. Returns true when this call started it.
func touch_crumble(tx: int, ty: int) -> bool:
	var index := ty * width + tx
	if crumbling.has(index):
		return false
	crumbling[index] = {"t": 0.0, "gone": false}
	return true

## Advance the crumbling slabs. Returns the tile indices that fell in this step. `keep_clear` is a box in which nothing grows back (the hero).
func step_crumbles(delta: float, keep_clear: Rect2) -> Array:
	var fell: Array = []
	for index: int in crumbling.keys():
		var entry: Dictionary = crumbling[index]
		entry["t"] = float(entry["t"]) + delta
		if not entry["gone"] and float(entry["t"]) >= CRUMBLE_HOLD:
			entry["gone"] = true
			tiles[index] = EMPTY
			fell.append(index)
		elif entry["gone"] and float(entry["t"]) >= CRUMBLE_HOLD + CRUMBLE_BACK:
			var cell := Rect2(float((index % width) * TILE), float((index / width) * TILE), TILE, TILE)
			if not cell.grow(2.0).intersects(keep_clear):
				tiles[index] = CRUMBLE
				crumbling.erase(index)
	return fell
