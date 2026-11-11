extends RefCounted

## The four stages of Crate Crew, written as calls on a small builder: slabs of ground, shelves, belts, spikes, crates with what is hidden inside, enemies, lifts, flags, the exit and the boss room. build(stage) returns plain data; world.gd turns it into a live stage. Positions here are in tiles (16 pixels), column then row, row 0 at the top; a thing "at" a cell stands in that cell.

const TILE := 16
const EMPTY := 0
const SOLID := 1
const SHELF := 2
const SPIKES := 3
const BELT_LEFT := 4
const BELT_RIGHT := 5

const COUNT := 4
const NAMES := [
	{"zh": "工具台", "en": "The Workbench"},
	{"zh": "管道井", "en": "Pipe Shaft"},
	{"zh": "熔炉传送带", "en": "Foundry Belt"},
	{"zh": "控制阁楼", "en": "Control Loft"},
]

var _w := 0
var _h := 0
var _tiles := PackedByteArray()
var _out: Dictionary = {}

func build(stage: int) -> Dictionary:
	_out = {"stage": stage, "objects": [], "foes": [], "lifts": [], "pickups": [], "flags": [], "chutes": [], "hints": [], "door": null, "boss": {}}
	match stage:
		0: _workbench()
		1: _pipe_shaft()
		2: _foundry()
		_: _control_loft()
	_out["w"] = _w
	_out["h"] = _h
	_out["tiles"] = _tiles
	return _out

# ---- builder ----

func _size(width: int, height: int) -> void:
	_w = width
	_h = height
	_tiles = PackedByteArray()
	_tiles.resize(width * height)

func _put_tile(x: int, y: int, tile: int) -> void:
	if x >= 0 and y >= 0 and x < _w and y < _h:
		_tiles[y * _w + x] = tile

func _fill(x: int, y: int, width: int, height: int, tile: int = SOLID) -> void:
	for row in range(y, y + height):
		for column in range(x, x + width):
			_put_tile(column, row, tile)

## Solid ground from column `from` to `to` (both included), from row `top` down to the bottom of the stage.
func _ground(from: int, to: int, top: int) -> void:
	_fill(from, top, to - from + 1, _h - top)

func _shelf(x: int, y: int, width: int) -> void:
	_fill(x, y, width, 1, SHELF)

func _spikes(x: int, y: int, width: int) -> void:
	_fill(x, y, width, 1, SPIKES)

## Turn the top of existing ground into a belt that carries whatever stands on it; direction is -1 (left) or 1 (right).
func _belt(x: int, y: int, width: int, direction: int) -> void:
	_fill(x, y, width, 1, BELT_LEFT if direction < 0 else BELT_RIGHT)

func _spawn(x: int, y: int) -> void:
	_out["spawn"] = _feet(x, y)

func _feet(x: int, y: int) -> Vector2:
	return Vector2(float(x * TILE) + 8.0, float((y + 1) * TILE))

## A crate standing in a cell. `inside` is what a wooden one drops when it breaks: "" (nothing), "gear", "gears" (three), "battery", "chip" (a spare life) or "cog" (the stage's golden cog).
func _crate(x: int, y: int, inside: String = "", kind: String = "wood") -> void:
	(_out["objects"] as Array).append({"kind": kind, "at": _feet(x, y), "inside": inside})

func _foe(kind: String, x: int, y: int, facing: int = -1, reach: int = 4) -> void:
	(_out["foes"] as Array).append({"kind": kind, "at": _feet(x, y), "face": facing, "reach": float(reach * TILE)})

## A moving platform `width` tiles wide whose top travels between two cells and back, taking `period` seconds for the round trip.
func _lift(x: int, y: int, to_x: int, to_y: int, width: int, period: float) -> void:
	(_out["lifts"] as Array).append({"from": Vector2(x * TILE, y * TILE), "to": Vector2(to_x * TILE, to_y * TILE), "w": float(width * TILE), "period": period})

## A row of floating gears, one per cell.
func _gears(x: int, y: int, count: int, step_x: int = 1, step_y: int = 0) -> void:
	for index in count:
		(_out["pickups"] as Array).append({"kind": "gear", "at": _feet(x + index * step_x, y + index * step_y) - Vector2(0, 4)})

func _flag(x: int, y: int) -> void:
	(_out["flags"] as Array).append(_feet(x, y))

func _door(x: int, y: int) -> void:
	_out["door"] = _feet(x, y)

## A ceiling chute at a cell that drops a fresh wooden crate whenever no loose crate is left near it.
func _chute(x: int, y: int) -> void:
	(_out["chutes"] as Array).append(Vector2(float(x * TILE) + 8.0, float(y * TILE)))

## A line of help text floating in the stage, shown in the player's language.
func _hint(x: int, y: int, key: String) -> void:
	(_out["hints"] as Array).append({"at": _feet(x, y), "key": key})

# ---- stage 1: the workbench ----

func _workbench() -> void:
	_size(180, 20)
	_spawn(3, 15)
	_ground(0, 24, 16)
	_hint(4, 10, "hint_move")
	_hint(9, 10, "hint_lift")
	_crate(9, 15, "gear")
	_crate(10, 15)
	_foe("bug", 20, 15)
	_gears(25, 12, 3)
	# First pit, then a raised block with the first steel crate.
	_ground(28, 47, 16)
	_hint(15, 10, "hint_throw")
	_crate(30, 15, "battery")
	_foe("hopper", 36, 15)
	_fill(38, 14, 6, 2)
	_crate(40, 13, "", "steel")
	_foe("bug", 43, 13)
	_crate(46, 15, "gears")
	# Stairs up to the long shelf and the first flyer.
	_ground(48, 52, 14)
	_ground(53, 57, 12)
	_ground(58, 66, 10)
	_hint(52, 7, "hint_up")
	_foe("drone", 56, 6, -1, 4)
	_crate(60, 9)
	_crate(61, 9, "gear")
	_crate(60, 8)
	_foe("turret", 65, 9, -1)
	_shelf(70, 10, 4)
	_gears(71, 8, 2)
	_shelf(76, 8, 4)
	_gears(77, 6, 2)
	_ground(82, 97, 10)
	_flag(83, 9)
	_hint(87, 4, "hint_hide")
	_crate(86, 9, "battery")
	_foe("bug", 90, 9)
	_crate(92, 9)
	_foe("hopper", 95, 9)
	# The tool tower: climb the shelves to get over the wall.
	_ground(98, 112, 12)
	_crate(99, 11)
	_shelf(100, 10, 3)
	_shelf(105, 8, 3)
	_shelf(109, 6, 4)
	_shelf(105, 4, 2)
	_crate(105, 3, "cog")
	_foe("drone", 103, 5, 1, 3)
	_crate(111, 5, "gears")
	_ground(113, 117, 4)
	_foe("bug", 115, 3)
	_gears(119, 5, 4, 0, 2)
	# The lower bench: rollers, tacks and a turret.
	_ground(118, 152, 16)
	_flag(121, 15)
	_crate(124, 15)
	_crate(125, 15, "gear")
	_crate(125, 14)
	_foe("roller", 130, 15)
	_spikes(133, 15, 2)
	_crate(137, 15, "", "steel")
	_shelf(138, 13, 4)
	_gears(138, 12, 4)
	_foe("hopper", 142, 15)
	_foe("turret", 146, 15, -1)
	_crate(148, 15, "battery")
	_foe("bug", 150, 15)
	# The long gap is crossed on a lift.
	_lift(153, 16, 160, 16, 2, 5.0)
	_foe("drone", 158, 11, -1, 3)
	_ground(163, 179, 16)
	_crate(165, 15, "chip")
	_crate(168, 15)
	_foe("bug", 170, 15)
	_door(175, 15)

# ---- stage 2: the pipe shaft ----

func _pipe_shaft() -> void:
	_size(26, 92)
	_fill(0, 0, 1, 92)
	_fill(25, 0, 1, 92)
	_fill(0, 0, 26, 2)
	_ground(1, 24, 88)
	_spawn(4, 87)
	_crate(7, 87)
	_shelf(8, 86, 4)
	_shelf(14, 84, 4)
	_gears(15, 83, 2)
	_shelf(19, 82, 5)
	_fill(1, 80, 16, 1)
	_foe("bug", 6, 79)
	_crate(10, 79, "gear")
	_crate(11, 79)
	_shelf(2, 78, 3)
	_shelf(7, 76, 4)
	_fill(12, 74, 13, 1)
	_crate(14, 73, "battery")
	_crate(16, 73)
	_foe("turret", 22, 73, -1)
	_shelf(8, 72, 3)
	_shelf(3, 70, 4)
	_gears(4, 69, 2)
	_shelf(8, 68, 5)
	_flag(9, 67)
	# A long ride up with flyers crossing it.
	_lift(15, 68, 15, 56, 2, 8.0)
	_foe("drone", 12, 63, 1, 5)
	_foe("drone", 14, 59, -1, 5)
	_shelf(20, 62, 4)
	_crate(22, 61, "cog")
	_fill(1, 56, 12, 1)
	_spikes(2, 55, 2)
	_foe("bug", 6, 55)
	_foe("hopper", 11, 55)
	_crate(8, 55)
	_crate(9, 55, "gears")
	_shelf(15, 54, 3)
	_shelf(20, 52, 4)
	_gears(21, 51, 2)
	_shelf(14, 50, 4)
	_fill(3, 48, 9, 1)
	_foe("turret", 4, 47, 1)
	_crate(9, 47, "", "steel")
	_shelf(13, 46, 3)
	_shelf(18, 44, 3)
	_shelf(22, 42, 3)
	_fill(8, 40, 12, 1)
	_flag(18, 39)
	_crate(10, 39)
	_foe("bug", 12, 39)
	_foe("hopper", 15, 39)
	_shelf(4, 38, 3)
	_lift(8, 36, 16, 36, 2, 5.0)
	_gears(10, 34, 4, 2)
	_shelf(21, 36, 3)
	_shelf(16, 34, 3)
	_fill(2, 32, 12, 1)
	_foe("turret", 3, 31, 1)
	_crate(7, 31, "battery")
	_crate(8, 31)
	_foe("drone", 10, 28, 1, 4)
	_shelf(15, 30, 3)
	_shelf(20, 28, 4)
	_shelf(14, 26, 4)
	_fill(1, 24, 11, 1)
	_foe("bug", 4, 23)
	_crate(6, 23)
	_foe("bug", 9, 23)
	_shelf(14, 22, 3)
	_shelf(19, 20, 4)
	_foe("drone", 17, 15, -1, 4)
	_fill(8, 18, 6, 1)
	_shelf(14, 18, 3)
	_crate(10, 17, "chip")
	_foe("hopper", 13, 17)
	_shelf(3, 16, 4)
	_flag(4, 15)
	_shelf(1, 14, 3)
	# The boss room on top: its floor is solid except for the way in at the left.
	_fill(5, 12, 20, 2)
	_shelf(1, 12, 4)
	_shelf(5, 10, 4)
	_shelf(13, 10, 4)
	_chute(3, 2)
	_chute(11, 2)
	_out["boss"] = {"kind": "vacuum", "floor": 12.0 * TILE, "left": 1.0 * TILE, "right": 25.0 * TILE, "camera": Vector2(16, 0)}

# ---- stage 3: the foundry belt ----

func _foundry() -> void:
	_size(200, 20)
	_spawn(3, 15)
	_ground(0, 18, 16)
	_crate(6, 15)
	_crate(7, 15, "gear")
	_foe("bug", 13, 15)
	_ground(19, 30, 16)
	_belt(19, 16, 12, 1)
	_foe("roller", 27, 15)
	_gears(22, 13, 3, 2)
	# A slag pit crossed over a shelf.
	_ground(31, 36, 18)
	_spikes(31, 17, 6)
	_shelf(32, 14, 4)
	_crate(33, 13, "battery")
	_ground(37, 60, 16)
	_crate(38, 15)
	_crate(39, 15)
	_belt(41, 16, 10, -1)
	_foe("magnet", 46, 9, -1, 5)
	_foe("hopper", 54, 15)
	_crate(56, 15, "", "steel")
	_foe("turret", 59, 15, -1)
	_ground(61, 70, 14)
	_crate(63, 13)
	_foe("bug", 67, 13)
	_ground(71, 80, 12)
	_belt(71, 12, 10, 1)
	_foe("drone", 76, 7, -1, 4)
	# High road over the furnace or low road past the rollers.
	_ground(81, 135, 16)
	_shelf(83, 12, 3)
	_shelf(88, 10, 3)
	_shelf(93, 8, 3)
	_fill(97, 6, 12, 1)
	_gears(98, 5, 5, 2)
	_crate(106, 5, "cog")
	_foe("magnet", 102, 1, 1, 4)
	_crate(86, 15)
	_foe("roller", 92, 15)
	_spikes(98, 15, 2)
	_crate(101, 15, "gear")
	_foe("roller", 106, 15)
	_flag(112, 15)
	_crate(113, 15, "battery")
	_belt(115, 16, 11, -1)
	_foe("magnet", 120, 9, -1, 5)
	_foe("hopper", 128, 15)
	_crate(131, 15)
	_crate(132, 15, "gears")
	_crate(132, 14)
	_ground(139, 154, 16)
	_crate(141, 15, "", "steel")
	_foe("bug", 145, 15)
	_foe("turret", 151, 15, -1)
	# A lift climbs out of the last pit to the high plateau.
	_lift(156, 16, 156, 10, 2, 5.0)
	_ground(160, 199, 10)
	_flag(163, 9)
	_crate(164, 9, "chip")
	_belt(167, 10, 10, 1)
	_foe("drone", 172, 5, -1, 4)
	_foe("roller", 181, 9)
	_crate(184, 9)
	_crate(185, 9)
	_foe("hopper", 189, 9)
	_door(195, 9)

# ---- stage 4: the control loft ----

func _control_loft() -> void:
	_size(96, 44)
	_fill(0, 0, 96, 4)
	_fill(0, 0, 1, 44)
	_fill(95, 0, 1, 44)
	# Lower corridor, walked to the right.
	_ground(0, 95, 40)
	_fill(0, 28, 79, 2)
	_spawn(3, 39)
	_crate(7, 39)
	_crate(8, 39, "gear")
	_foe("bug", 13, 39)
	_foe("magnet", 18, 33, 1, 5)
	_shelf(20, 38, 3)
	_shelf(25, 36, 4)
	_crate(26, 35, "battery")
	_foe("turret", 31, 39, -1)
	_spikes(34, 39, 3)
	_crate(39, 39, "", "steel")
	_foe("roller", 44, 39)
	_foe("hopper", 50, 39)
	_crate(53, 39)
	_crate(54, 39, "gears")
	_crate(54, 38)
	_foe("magnet", 60, 33, -1, 5)
	_spikes(63, 39, 2)
	_foe("roller", 69, 39)
	_crate(73, 39)
	_foe("turret", 77, 39, -1)
	_flag(80, 39)
	# The climb on the right.
	_shelf(84, 38, 4)
	_shelf(90, 36, 4)
	_crate(92, 35, "cog")
	_shelf(84, 34, 4)
	_foe("drone", 88, 32, -1, 3)
	_shelf(90, 32, 4)
	_shelf(84, 30, 4)
	_shelf(80, 28, 3)
	# Upper corridor, walked back to the left.
	_fill(26, 14, 70, 2)
	_flag(76, 27)
	_crate(74, 27, "battery")
	_foe("bug", 70, 27, 1)
	_foe("hopper", 65, 27)
	_crate(62, 27)
	_crate(61, 27)
	_foe("magnet", 57, 20, -1, 5)
	_spikes(52, 27, 3)
	_shelf(51, 25, 5)
	_foe("roller", 46, 27, 1)
	_crate(42, 27, "", "steel")
	_foe("turret", 38, 27, 1)
	_foe("drone", 34, 22, 1, 4)
	_crate(30, 27, "chip")
	_crate(29, 27)
	# The climb on the left to the boss room.
	_shelf(20, 26, 4)
	_shelf(14, 24, 4)
	_shelf(8, 22, 4)
	_gears(9, 21, 2)
	_shelf(2, 20, 4)
	_flag(3, 19)
	_shelf(1, 18, 3)
	_shelf(1, 16, 4)
	_fill(5, 14, 21, 2)
	_shelf(1, 14, 4)
	_fill(26, 4, 1, 12)
	_shelf(5, 12, 3)
	_shelf(18, 12, 3)
	_chute(4, 4)
	_chute(21, 4)
	_out["boss"] = {"kind": "crane", "floor": 14.0 * TILE, "left": 1.0 * TILE, "right": 26.0 * TILE, "camera": Vector2(24, 32)}
