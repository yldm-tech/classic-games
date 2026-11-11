extends RefCounted

## The fourteen floors of the Loom Tower. A floor is one fixed screen of 30 x 17 tiles: side walls, a solid floor (with pits on some floors: whatever falls in comes back from the top), knitted ledges that can be jumped through from below, and a few solid crates.
##
## plats / blocks: [row, first column, last column]. pits: [first column, last column] cut out of the floor row. foes: [kind, column, row of the ledge it stands on] (for a snipper the row it hovers at). spawn: [column, row] for each knitter.

const COLS := 30
const ROWS := 17
const TILE := 16
const EMPTY := 0
const SOLID := 1
const LEDGE := 2
const FLOOR_ROW := 16

const THEME_CELLAR := 0
const THEME_DYE := 1
const THEME_LOFT := 2
const THEME_GALLERY := 3
const THEME_CLOCK := 4
const THEME_CROWN := 5

const THEME_NAMES := [
	{"zh": "羊毛地窖", "en": "Wool Cellar"},
	{"zh": "染坊", "en": "Dye Works"},
	{"zh": "飞蛾阁楼", "en": "Moth Loft"},
	{"zh": "纽扣长廊", "en": "Button Gallery"},
	{"zh": "发条织机", "en": "Clockwork Loom"},
	{"zh": "塔冠", "en": "Tower Crown"},
]

const STAGES := [
	{"theme": 0, "plats": [[13, 1, 9], [13, 20, 28], [10, 7, 22], [7, 1, 9], [7, 20, 28], [4, 10, 19]], "foes": [["moth", 5, 13], ["moth", 24, 13], ["moth", 14, 10]], "spawn": [[12, 16], [17, 16]]},
	{"theme": 0, "plats": [[13, 4, 25], [10, 1, 8], [10, 21, 28], [7, 6, 23], [4, 1, 6], [4, 23, 28]], "foes": [["moth", 8, 13], ["moth", 21, 13], ["spring", 14, 7], ["moth", 3, 10]], "spawn": [[12, 16], [17, 16]]},
	{"theme": 0, "plats": [[13, 1, 20], [10, 9, 28], [7, 1, 20], [4, 9, 28]], "foes": [["moth", 5, 13], ["spring", 24, 10], ["moth", 6, 7], ["spring", 22, 4], ["moth", 15, 13]], "spawn": [[24, 16], [27, 16]]},
	{"theme": 1, "plats": [[13, 1, 6], [13, 11, 18], [13, 23, 28], [10, 4, 12], [10, 17, 25], [7, 1, 8], [7, 12, 17], [7, 21, 28], [4, 5, 24]], "foes": [["moth", 3, 13], ["moth", 26, 13], ["ink", 14, 7], ["spring", 8, 10], ["spring", 21, 10], ["ink", 14, 4]], "spawn": [[13, 16], [16, 16]]},
	{"theme": 1, "pits": [[6, 8], [21, 23]], "plats": [[13, 10, 19], [10, 1, 7], [10, 22, 28], [7, 9, 20], [4, 1, 8], [4, 21, 28]], "foes": [["moth", 14, 13], ["ink", 3, 10], ["ink", 26, 10], ["spring", 14, 7], ["moth", 4, 4], ["moth", 25, 4]], "spawn": [[13, 16], [16, 16]]},
	{"theme": 1, "plats": [[13, 1, 12], [13, 17, 28], [10, 10, 19], [7, 1, 12], [7, 17, 28], [4, 10, 19]], "foes": [["snip", 8, 5], ["snip", 21, 5], ["moth", 5, 13], ["moth", 24, 13], ["ink", 14, 10], ["spring", 14, 4]], "spawn": [[13, 16], [16, 16]]},
	{"theme": 2, "boss": 0, "plats": [[13, 2, 9], [13, 20, 27], [10, 11, 18]], "foes": [], "spawn": [[5, 16], [24, 16]]},
	{"theme": 3, "plats": [[13, 3, 26], [10, 1, 10], [10, 19, 28], [7, 5, 24], [4, 1, 7], [4, 22, 28]], "foes": [["pin", 14, 13], ["pin", 14, 7], ["moth", 4, 10], ["moth", 25, 10], ["spring", 3, 4], ["spring", 26, 4]], "spawn": [[13, 16], [16, 16]]},
	{"theme": 3, "blocks": [[13, 13, 16], [12, 13, 16]], "plats": [[13, 1, 8], [13, 21, 28], [10, 9, 20], [7, 1, 10], [7, 19, 28], [4, 8, 21]], "foes": [["pin", 4, 13], ["pin", 25, 13], ["snip", 14, 5], ["ink", 14, 10], ["spring", 5, 7], ["spring", 24, 7], ["moth", 14, 4]], "spawn": [[10, 16], [19, 16]]},
	{"theme": 3, "pits": [[12, 17]], "plats": [[13, 1, 10], [13, 19, 28], [10, 8, 21], [7, 1, 9], [7, 20, 28], [4, 6, 23]], "foes": [["snip", 5, 5], ["snip", 24, 5], ["snip", 14, 8], ["pin", 5, 13], ["pin", 24, 13], ["ink", 14, 10], ["moth", 14, 4]], "spawn": [[8, 16], [21, 16]]},
	{"theme": 4, "plats": [[13, 1, 5], [13, 9, 13], [13, 17, 21], [13, 25, 28], [10, 5, 9], [10, 13, 17], [10, 21, 25], [7, 1, 5], [7, 9, 13], [7, 17, 21], [7, 25, 28], [4, 5, 24]], "foes": [["spring", 3, 13], ["spring", 26, 13], ["spring", 11, 13], ["moth", 19, 13], ["ink", 7, 10], ["ink", 23, 10], ["snip", 14, 6], ["pin", 14, 4]], "spawn": [[14, 16], [16, 16]]},
	{"theme": 4, "pits": [[2, 4], [25, 27]], "blocks": [[10, 14, 15], [9, 14, 15]], "plats": [[13, 6, 23], [10, 1, 9], [10, 20, 28], [7, 6, 12], [7, 17, 23], [4, 1, 10], [4, 19, 28]], "foes": [["pin", 10, 13], ["pin", 19, 13], ["ink", 3, 10], ["ink", 26, 10], ["snip", 14, 5], ["snip", 8, 5], ["spring", 9, 7], ["spring", 20, 7], ["moth", 4, 4]], "spawn": [[12, 16], [17, 16]]},
	{"theme": 4, "plats": [[13, 1, 7], [13, 11, 18], [13, 22, 28], [10, 3, 26], [7, 1, 6], [7, 10, 19], [7, 23, 28], [4, 3, 12], [4, 17, 26]], "foes": [["pin", 14, 13], ["pin", 8, 10], ["pin", 21, 10], ["ink", 14, 7], ["snip", 3, 5], ["snip", 26, 5], ["spring", 4, 13], ["spring", 25, 13], ["moth", 7, 4], ["moth", 22, 4]], "spawn": [[9, 16], [20, 16]]},
	{"theme": 5, "boss": 1, "plats": [[13, 1, 7], [13, 22, 28], [10, 10, 19], [7, 1, 7], [7, 22, 28]], "foes": [], "spawn": [[4, 16], [25, 16]]},
]

static func count() -> int:
	return STAGES.size()

## The tile grid of a floor, row by row.
static func build(def: Dictionary) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(COLS * ROWS)
	for row in ROWS:
		grid[row * COLS] = SOLID
		grid[row * COLS + COLS - 1] = SOLID
	for col in COLS:
		grid[FLOOR_ROW * COLS + col] = SOLID
	for pit: Array in def.get("pits", []):
		for col in range(int(pit[0]), int(pit[1]) + 1):
			grid[FLOOR_ROW * COLS + col] = EMPTY
	for plat: Array in def.get("plats", []):
		for col in range(int(plat[1]), int(plat[2]) + 1):
			grid[int(plat[0]) * COLS + col] = LEDGE
	for block: Array in def.get("blocks", []):
		for col in range(int(block[1]), int(block[2]) + 1):
			grid[int(block[0]) * COLS + col] = SOLID
	return grid
