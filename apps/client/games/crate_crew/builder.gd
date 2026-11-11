extends RefCounted

## The small language the levels of Crate Crew are written in: slabs of ground, one-way shelves, hazards, cracked walls, crates and other things to lift with what is hidden inside, enemies and the holes they come out of, moving platforms, flags, secret burrows into bonus rooms, the exit and the boss. Positions are in tiles (16 stage pixels), column then row, row 0 at the top; a thing "at" a cell stands on the bottom of that cell. build() hands world.gd plain data; the theme scripts (kitchen.gd, toyshop.gd, sewer.gd, treehouse.gd) extend this one and only call the helpers below.

const TILE := 16
const EMPTY := 0
const SOLID := 1
const SHELF := 2
const HAZARD := 3
const CRACK := 4

var _w := 0
var _h := 0
var _tiles := PackedByteArray()
var _out: Dictionary = {}

## Start a level: its size in tiles and its theme.
func _begin(id: String, theme: String, width: int, height: int, kind: String = "level") -> void:
	_w = width
	_h = height
	_tiles = PackedByteArray()
	_tiles.resize(width * height)
	_out = {
		"id": id, "theme": theme, "kind": kind, "w": width, "h": height, "spawn": Vector2.ZERO, "exit": null, "objects": [], "foes": [], "spawners": [], "pickups": [], "lifts": [], "flags": [],
		"warps": [], "zones": [], "hints": [], "decor": [], "guide": [], "boss": {},
	}

func _finish() -> Dictionary:
	_out["tiles"] = _tiles
	return _out

func _put_tile(x: int, y: int, tile: int) -> void:
	if x >= 0 and y >= 0 and x < _w and y < _h:
		_tiles[y * _w + x] = tile

func _fill(x: int, y: int, width: int, height: int, tile: int = SOLID) -> void:
	for row in range(y, y + height):
		for column in range(x, x + width):
			_put_tile(column, row, tile)

## Solid ground from column `from` to `to` (both included), from row `top` down to the bottom of the level.
func _ground(from: int, to: int, top: int) -> void:
	_fill(from, top, to - from + 1, _h - top)

## A one-way shelf: stood on from above, jumped through from below, dropped through with down and jump.
func _shelf(x: int, y: int, width: int) -> void:
	_fill(x, y, width, 1, SHELF)

## A row of whatever hurts in this theme (a hot burner, tacks, sludge, thorns) standing in the cells of row y.
func _hazard(x: int, y: int, width: int) -> void:
	_fill(x, y, width, 1, HAZARD)

## A block of cracked wall: solid until something thrown hits it, then the whole cracked block crumbles.
func _crack(x: int, y: int, width: int, height: int) -> void:
	_fill(x, y, width, height, CRACK)

func _clear(x: int, y: int, width: int, height: int) -> void:
	_fill(x, y, width, height, EMPTY)

## The point where something standing in a cell has its feet.
func _feet(x: int, y: int) -> Vector2:
	return Vector2(float(x * TILE) + 8.0, float((y + 1) * TILE))

func _spawn(x: int, y: int) -> void:
	_out["spawn"] = _feet(x, y)

func _exit(x: int, y: int) -> void:
	_out["exit"] = _feet(x, y)

## Something to lift standing in a cell: "wood" or "steel" crates, or this theme's own things ("apple", "can", "block", "nut", "walnut", "pinecone"). `inside` is what a breaking one lets out: "" (nothing), "acorns" (three), "bag" (five), "heart", "golden" (an extra life) or "ant" and the other enemy kinds (one jumps out).
func _thing(x: int, y: int, kind: String = "wood", inside: String = "") -> void:
	(_out["objects"] as Array).append({"kind": kind, "at": _feet(x, y), "inside": inside})

func _crate(x: int, y: int, inside: String = "") -> void:
	_thing(x, y, "wood", inside)

func _steel(x: int, y: int) -> void:
	_thing(x, y, "steel")

## A column of wooden crates standing on each other, the lowest in the cell given.
func _stack(x: int, y: int, count: int, top_inside: String = "") -> void:
	for index in count:
		_thing(x, y - index, "wood", top_inside if index == count - 1 else "")

func _foe(kind: String, x: int, y: int, facing: int = -1, reach: int = 4) -> void:
	(_out["foes"] as Array).append({"kind": kind, "at": _feet(x, y), "face": facing, "reach": float(reach * TILE)})

## A slime or spider hanging under the ceiling whose underside is the top of row `row`, `reach` cells of thread below it (spiders).
func _hang(kind: String, x: int, row: int, reach: int = 4) -> void:
	(_out["foes"] as Array).append({"kind": kind, "at": Vector2(float(x * TILE) + 8.0, float(row * TILE) + 10.0), "face": -1, "reach": float(reach * TILE)})

## A hole in the wall that lets out an enemy of `kind` every `every` seconds while it is near the view and fewer than `most` of its own are about.
func _spawner(kind: String, x: int, y: int, facing: int, every: float = 4.0, most: int = 2) -> void:
	(_out["spawners"] as Array).append({"kind": kind, "at": _feet(x, y), "face": facing, "every": every, "most": most})

## A moving platform `width` tiles wide whose top travels between two cells and back in `period` seconds.
func _lift(x: int, y: int, to_x: int, to_y: int, width: int, period: float) -> void:
	(_out["lifts"] as Array).append({"from": Vector2(x * TILE, y * TILE), "to": Vector2(to_x * TILE, to_y * TILE), "w": float(width * TILE), "period": period})

## A line of acorns, one per cell, floating in the air above the cells' floors.
func _acorns(x: int, y: int, count: int, step_x: int = 1, step_y: int = 0) -> void:
	for index in count:
		_pickup("acorn", x + index * step_x, y + index * step_y)

## An arch of acorns over a jump.
func _arch(x: int, y: int, count: int) -> void:
	for index in count:
		var lift := int(round(sin(PI * (float(index) + 0.5) / float(count)) * 2.0))
		_pickup("acorn", x + index, y - lift)

func _pickup(kind: String, x: int, y: int) -> void:
	(_out["pickups"] as Array).append({"kind": kind, "at": _feet(x, y) - Vector2(0, 4)})

func _flag(x: int, y: int) -> void:
	(_out["flags"] as Array).append(_feet(x, y))

## A secret burrow: stand in it and press down to be carried to `to`; a bonus room's way back is an ordinary burrow too.
func _burrow(x: int, y: int, to_x: int, to_y: int, secret: bool = true) -> void:
	(_out["warps"] as Array).append({"at": _feet(x, y), "to": _feet(to_x, to_y), "secret": secret})

## A bonus room: while a squirrel is inside this block of cells the view stays inside it.
func _zone(x: int, y: int, width: int, height: int) -> void:
	(_out["zones"] as Array).append(Rect2(x * TILE, y * TILE, width * TILE, height * TILE))

## A sealed bonus room with solid walls round it; returns nothing, the caller fills it.
func _room(x: int, y: int, width: int, height: int) -> void:
	_fill(x, y, width, height)
	_clear(x + 1, y + 1, width - 2, height - 2)
	_zone(x, y, width, height)

func _hint(x: int, y: int, key: String) -> void:
	(_out["hints"] as Array).append({"at": _feet(x, y), "key": key})

## A painted object standing in a cell that nothing collides with; `front` draws it over the play instead of behind it.
func _decor(kind: String, x: int, y: int, front: bool = false) -> void:
	(_out["decor"] as Array).append({"kind": kind, "at": _feet(x, y), "front": front})

## The way the level is meant to be crossed, cell by cell where a squirrel stands. Nothing in play reads it; the tests' autopilot follows it.
func _way(x: int, y: int) -> void:
	(_out["guide"] as Array).append(_feet(x, y))

func _boss(kind: String) -> void:
	_out["boss"] = {"kind": kind}

## The columns the level is played in; bonus rooms are built to the right of them, out of sight until a squirrel finds the way in.
func _main(columns: int) -> void:
	_out["main_w"] = columns
	_fill(columns, 0, 1, _h)

## A bonus room behind a secret burrow at (x, y). Inside: rows of acorns, crates with bags of acorns, and a golden acorn (`prize` "golden") or a heart; the way out leads back to (back_x, back_y). Rooms sit side by side right of the level's columns, 24 cells wide (one view) and 13 high, at the bottom of the level.
func _bonus(x: int, y: int, back_x: int, back_y: int, prize: String = "golden", layout: int = 0) -> void:
	var index := 0
	for zone: Rect2 in _out["zones"]:
		index += 1
	var left := int(_out.get("main_w", _w)) + 1 + index * 25
	var top := _h - 13
	_room(left, top, 24, 13)
	var floor_row := top + 11
	_burrow(x, y, left + 3, floor_row, true)
	_burrow(left + 20, floor_row, back_x, back_y, false)
	match layout % 3:
		0:
			_shelf(left + 4, floor_row - 1, 6)
			_shelf(left + 13, floor_row - 1, 6)
			_shelf(left + 8, floor_row - 3, 7)
			_acorns(left + 4, floor_row - 2, 6)
			_acorns(left + 13, floor_row - 2, 6)
			_acorns(left + 5, floor_row, 14)
			_pickup(prize, left + 11, floor_row - 4)
			_crate(left + 9, floor_row - 4, "bag")
			_crate(left + 13, floor_row - 4, "bag")
		1:
			for step in 4:
				_shelf(left + 3 + step * 4, floor_row - 1 - step * 2, 3)
				_acorns(left + 3 + step * 4, floor_row - 2 - step * 2, 3)
			_acorns(left + 4, floor_row, 15)
			_pickup(prize, left + 16, floor_row - 8)
			_crate(left + 10, floor_row, "bag")
			_crate(left + 12, floor_row, "bag")
		_:
			_fill(left + 9, floor_row - 1, 6, 2)
			_acorns(left + 9, floor_row - 2, 6)
			_arch(left + 3, floor_row, 6)
			_arch(left + 15, floor_row, 6)
			_shelf(left + 10, floor_row - 3, 4)
			_pickup(prize, left + 12, floor_row - 4)
			_crate(left + 5, floor_row, "bag")
			_crate(left + 18, floor_row, "bag")
