extends RefCounted

## The tile grid of the stage being played and the collision queries on it. Tiles are 16 px; a cell is empty, solid, or a thin platform that only stops things falling onto it.

const TILE := 16
const EMPTY := 0
const SOLID := 1
const PLAT := 2

var cols := 0
var rows := 0
var vertical := false
var cells := PackedByteArray()
var def: Dictionary = {}

func load_stage(stage_def: Dictionary) -> void:
	def = stage_def
	cols = int(def["cols"])
	rows = int(def["rows"])
	vertical = str(def["format"]) == "v"
	cells = PackedByteArray()
	cells.resize(cols * rows)
	for entry: Array in def["ground"]:
		_fill(int(entry[0]), int(entry[2]), int(entry[1]) - int(entry[0]) + 1, rows - int(entry[2]), SOLID)
	for entry: Array in def["blocks"]:
		_fill(int(entry[0]), int(entry[1]), int(entry[2]), int(entry[3]), SOLID)
	for entry: Array in def["plats"]:
		for column in range(int(entry[0]), int(entry[0]) + int(entry[2])):
			if cell(column, int(entry[1])) == EMPTY:
				cells[int(entry[1]) * cols + column] = PLAT

func _fill(column: int, row: int, width: int, height: int, kind: int) -> void:
	for y in range(maxi(0, row), mini(rows, row + height)):
		for x in range(maxi(0, column), mini(cols, column + width)):
			cells[y * cols + x] = kind

func width() -> float:
	return float(cols * TILE)

func height() -> float:
	return float(rows * TILE)

func cell(column: int, row: int) -> int:
	if column < 0 or row < 0 or column >= cols or row >= rows:
		return EMPTY
	return cells[row * cols + column]

func solid_at(x: float, y: float) -> bool:
	return cell(floori(x / TILE), floori(y / TILE)) == SOLID

## Whether a box overlaps any solid tile. Thin platforms never count.
func box_hits(left: float, top: float, right: float, bottom: float) -> bool:
	var c0 := floori(left / TILE)
	var c1 := floori((right - 0.01) / TILE)
	var r0 := floori(top / TILE)
	var r1 := floori((bottom - 0.01) / TILE)
	for row in range(r0, r1 + 1):
		for column in range(c0, c1 + 1):
			if cell(column, row) == SOLID:
				return true
	return false

## The top of the first surface a falling body lands on when its feet go from `from_y` to `to_y` between `left` and `right`, or INF when it keeps falling. Thin platforms count unless `through` is set.
func landing(left: float, right: float, from_y: float, to_y: float, through: bool) -> float:
	var c0 := floori(left / TILE)
	var c1 := floori((right - 0.01) / TILE)
	var r0 := floori(from_y / TILE)
	var r1 := floori(to_y / TILE)
	for row in range(r0, r1 + 1):
		var top := float(row * TILE)
		for column in range(c0, c1 + 1):
			var kind := cell(column, row)
			if kind == SOLID and to_y >= top:
				return top
			if kind == PLAT and not through and from_y <= top + 0.01 and to_y >= top:
				return top
	return INF

## What a body with its feet at (x, y) stands on: EMPTY, SOLID or PLAT.
func floor_kind(left: float, right: float, y: float) -> int:
	if absf(fmod(y, float(TILE))) > 0.01:
		return EMPTY
	var row := roundi(y / TILE)
	var found := EMPTY
	for column in range(floori(left / TILE), floori((right - 0.01) / TILE) + 1):
		var kind := cell(column, row)
		if kind == SOLID:
			return SOLID
		if kind == PLAT:
			found = PLAT
	return found

## The y of the highest surface in a column at or below `from_row`, or INF when there is none.
func surface_below(column: int, from_row: int) -> float:
	for row in range(maxi(0, from_row), rows):
		if cell(column, row) != EMPTY and cell(column, row - 1) == EMPTY:
			return float(row * TILE)
	return INF
