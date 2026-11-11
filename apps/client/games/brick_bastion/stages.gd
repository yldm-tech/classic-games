extends RefCounted

## Sector data of Brick Bastion: the field size, the six hand-authored layouts, their raider rosters and the tuning of every vehicle. Pure data and lookups; the simulation (sim.gd) reads it and nothing here changes during a run.

## The field in cells. A cell is CELL pixels square.
const COLS := 18
const ROWS := 14
const CELL := 16

## Tile codes of the grid.
const T_EMPTY := 0
const T_BRICK := 1
const T_CRACKED := 2
const T_PLATE := 3
const T_WATER := 4
const T_THICKET := 5
const T_CORE := 6
## Plate that the Mason chip raised around the beacon; it turns back into brick when the chip runs out.
const T_FORT := 7

## The beacon fills these two columns of the two bottom rows.
const CORE_COL := 8
const CORE_ROW := 12
## Cells of the wall around the beacon, the ones the Mason chip fortifies.
const CORE_RING: Array[Vector2i] = [Vector2i(7, 11), Vector2i(8, 11), Vector2i(9, 11), Vector2i(10, 11), Vector2i(7, 12), Vector2i(10, 12), Vector2i(7, 13), Vector2i(10, 13)]
## Columns of the three gates in the top row. A boss arrives through the middle one and is two cells wide.
const GATE_COLS: Array[int] = [0, 8, 17]
## Every layout has plate at these two cells, either side of the beacon in the bottom row, so the beacon can only be shot at down its two columns and along the row above the bottom one.
const FLANK_CELLS: Array[Vector2i] = [Vector2i(6, 13), Vector2i(11, 13)]
## Cell where each player's rover starts and comes back.
const PLAYER_CELLS: Array[Vector2i] = [Vector2i(5, 13), Vector2i(12, 13)]

## Raider kinds. `speed` and `shot_speed` are in sixteenths of a pixel per step, `fire` is the range of steps between shots, `shot_power` 2 breaks a brick in one hit.
const KINDS := {
	"grunt": {"hp": 1, "speed": 7, "fire": [100, 220], "shot_speed": 26, "shots": 1, "shot_power": 1, "score": 100},
	"scout": {"hp": 1, "speed": 13, "fire": [130, 260], "shot_speed": 26, "shots": 1, "shot_power": 1, "score": 200},
	"gunner": {"hp": 2, "speed": 7, "fire": [44, 96], "shot_speed": 40, "shots": 2, "shot_power": 1, "score": 300},
	"bulwark": {"hp": 4, "speed": 5, "fire": [100, 190], "shot_speed": 28, "shots": 1, "shot_power": 2, "score": 400},
	"crusher": {"hp": 22, "speed": 5, "fire": [70, 110], "shot_speed": 34, "shots": 4, "shot_power": 2, "score": 3000, "boss": true, "volley": 300},
	"dreadnought": {"hp": 34, "speed": 6, "fire": [56, 96], "shot_speed": 38, "shots": 6, "shot_power": 2, "score": 6000, "boss": true, "volley": 270},
}
## Roster letters.
const LETTERS := {"g": "grunt", "s": "scout", "u": "gunner", "b": "bulwark"}
## Order in which the tally lists what was destroyed.
const TALLY_ORDER: Array[String] = ["grunt", "scout", "gunner", "bulwark", "crusher", "dreadnought"]

## Per sector: `limit` raiders on the field at once, `gap` steps between arrivals, `aggression` how hard they press for the beacon, `calm` how much longer they wait between shots than their kind's own pace.
## Map legend: "." ground, "#" brick, "@" plate, "~" water, "%" thicket, "C" the beacon.
const STAGES: Array[Dictionary] = [
	{
		"name": {"zh": "苔线前哨", "en": "Mossline Outpost"}, "theme": "moss", "roster": "gggsggsgggsgggsg", "limit": 3, "gap": 190, "aggression": 0.4, "calm": 1.5,
		"map": [
			"..................",
			".##.##..@@..##.##.",
			".##.##......##.##.",
			".......####.......",
			"%%.##........##.%%",
			"%%.##..#..#..##.%%",
			".......#..#.......",
			"##..@@......@@..##",
			"......%%##%%......",
			".##.#.%%##%%.#.##.",
			".##.#........#.##.",
			"......######......",
			".##....#CC#....##.",
			"......@#CC#@......",
		],
	},
	{
		"name": {"zh": "盐沼渡口", "en": "Saltmarsh Crossing"}, "theme": "marsh", "roster": "ggsgsgugsgsgugsggs", "limit": 3, "gap": 180, "aggression": 0.6, "calm": 1.35,
		"map": [
			"..................",
			".#.##.#....#.##.#.",
			".#.##.#.@@.#.##.#.",
			"......#....#......",
			"~~~~..~~~~~~..~~~~",
			"~~~~..~~~~~~..~~~~",
			"...#..........#...",
			".%%#.##.##.##.#%%.",
			".%%..##.##.##..%%.",
			"......@....@......",
			".##.#........#.##.",
			".##.#.######.#.##.",
			"....#..#CC#..#....",
			"......@#CC#@......",
		],
	},
	{
		"name": {"zh": "断桥关隘", "en": "Brokenspan Pass"}, "theme": "pass", "roster": "gsgugsbgsugsbgsgug", "limit": 4, "gap": 170, "aggression": 0.8, "calm": 1.2, "boss": "crusher",
		"map": [
			"..................",
			".##..~......~..##.",
			".##..~.#..#.~..##.",
			".....~.####.~.....",
			".@..............@.",
			"....##..%%..##....",
			".~~.##..%%..##.~~.",
			".~~....#@@#....~~.",
			"....#..#..#..#....",
			".##.#..#..#..#.##.",
			".##............##.",
			"......######......",
			".@.#...#CC#...#.@.",
			"......@#CC#@......",
		],
	},
	{
		"name": {"zh": "霜铁工场", "en": "Frostiron Works"}, "theme": "frost", "roster": "gsugbsgusgbugsgbusgsug", "limit": 4, "gap": 160, "aggression": 1.0, "calm": 1.1,
		"map": [
			"..................",
			".@@.#.@@..@@.#.@@.",
			"....#........#....",
			".##.#.##@@##.#.##.",
			".##............##.",
			"....@@.#..#.@@....",
			"%%..#..#..#..#..%%",
			"%%..#........#..%%",
			"....##.@..@.##....",
			".@..............@.",
			".@.##.#....#.##.@.",
			"...##.######.##...",
			".......#CC#.......",
			".#....@#CC#@....#.",
		],
	},
	{
		"name": {"zh": "暮色林带", "en": "Duskwood Belt"}, "theme": "dusk", "roster": "sgubsgsubgusbgsubsgbsugb", "limit": 4, "gap": 150, "aggression": 1.2, "calm": 1.0,
		"map": [
			"..................",
			".%%%.##.%%.##.%%%.",
			".%%%.#..%%..#.%%%.",
			"......~~..~~......",
			".##.%.~~..~~.%.##.",
			".#..%%......%%..#.",
			"...#%%.#@@#.%%#...",
			"%%.#....##....#.%%",
			"%%....%%..%%....%%",
			"..##..%%..%%..##..",
			".@.#..........#.@.",
			"......######......",
			".%%.#..#CC#..#.%%.",
			".%%...@#CC#@...%%.",
		],
	},
	{
		"name": {"zh": "熔炉腹地", "en": "Forgeheart"}, "theme": "forge", "roster": "ugbsugbsbugsbugsbbsugs", "limit": 5, "gap": 140, "aggression": 1.4, "calm": 0.9, "boss": "dreadnought",
		"map": [
			"..................",
			".#.@.##....##.@.#.",
			".#...##....##...#.",
			"...~~........~~...",
			"##.~~.#.@@.#.~~.##",
			"......#....#......",
			".@.##...%%...##.@.",
			"...##...%%...##...",
			".~......##......~.",
			".~.#.#..##..#.#.~.",
			"...#.#......#.#...",
			"......@####@......",
			".##....#CC#....##.",
			"......@#CC#@......",
		],
	},
]

static func count() -> int:
	return STAGES.size()

## The tile grid of a stage, row by row, COLS * ROWS codes.
static func grid(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(COLS * ROWS)
	var rows: Array = STAGES[index]["map"]
	for row in ROWS:
		var line: String = rows[row]
		for col in COLS:
			var code := T_EMPTY
			match line.substr(col, 1):
				"#": code = T_BRICK
				"@": code = T_PLATE
				"~": code = T_WATER
				"%": code = T_THICKET
				"C": code = T_CORE
			out[row * COLS + col] = code
	return out

## The raider kinds of a stage in arrival order. With two players the column is a quarter longer: the first quarter of the roster comes round again at the end.
static func roster(index: int, players: int) -> Array[String]:
	var letters: String = STAGES[index]["roster"]
	if players > 1:
		letters += letters.substr(0, letters.length() / 4)
	var out: Array[String] = []
	for position in letters.length():
		out.append(str(LETTERS[letters.substr(position, 1)]))
	return out

## Whether the raider at this place of the roster carries a supply chip.
static func is_carrier(position: int) -> bool:
	return position % 5 == 3

## Problems of the authored data, one line each; empty when every layout is sound. The game's test asserts on it.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for index in STAGES.size():
		var stage: Dictionary = STAGES[index]
		var rows: Array = stage["map"]
		if rows.size() != ROWS:
			out.append("stage %d: %d rows, wanted %d" % [index + 1, rows.size(), ROWS])
			continue
		var sound := true
		for row in ROWS:
			if str(rows[row]).length() != COLS:
				out.append("stage %d row %d: %d columns, wanted %d" % [index + 1, row, str(rows[row]).length(), COLS])
				sound = false
		if not sound:
			continue
		var tiles := grid(index)
		for row in [CORE_ROW, CORE_ROW + 1]:
			for col in [CORE_COL, CORE_COL + 1]:
				if tiles[row * COLS + col] != T_CORE:
					out.append("stage %d: the beacon is missing at %d,%d" % [index + 1, col, row])
		for gate in GATE_COLS:
			for row in 2:
				if tiles[row * COLS + gate] != T_EMPTY and row == 0:
					out.append("stage %d: gate column %d is blocked" % [index + 1, gate])
		for col in [8, 9]:
			for row in 2:
				if tiles[row * COLS + col] != T_EMPTY and stage.has("boss"):
					out.append("stage %d: the boss gate is blocked at %d,%d" % [index + 1, col, row])
		for cell in PLAYER_CELLS:
			if tiles[cell.y * COLS + cell.x] != T_EMPTY:
				out.append("stage %d: a rover start is blocked" % (index + 1))
		for cell in FLANK_CELLS:
			if tiles[cell.y * COLS + cell.x] != T_PLATE:
				out.append("stage %d: the beacon's flank at %d,%d is not plate" % [index + 1, cell.x, cell.y])
		for cell in CORE_RING:
			if not tiles[cell.y * COLS + cell.x] in [T_BRICK, T_PLATE]:
				out.append("stage %d: the beacon wall is open at %d,%d" % [index + 1, cell.x, cell.y])
		for letter_index in str(stage["roster"]).length():
			if not LETTERS.has(str(stage["roster"]).substr(letter_index, 1)):
				out.append("stage %d: unknown roster letter" % (index + 1))
		out.append_array(_unreachable(index, tiles))
	return out

## Every gate must reach the beacon wall driving over ground, thicket and brick (raiders shoot their way through brick).
static func _unreachable(index: int, tiles: PackedInt32Array) -> PackedStringArray:
	var out := PackedStringArray()
	for gate in GATE_COLS:
		var seen := {}
		var queue: Array[Vector2i] = [Vector2i(gate, 0)]
		seen[Vector2i(gate, 0)] = true
		var reached := false
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			if cell in CORE_RING:
				reached = true
				break
			for step in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				var next: Vector2i = cell + step
				if next.x < 0 or next.y < 0 or next.x >= COLS or next.y >= ROWS or seen.has(next):
					continue
				if tiles[next.y * COLS + next.x] in [T_PLATE, T_WATER, T_CORE, T_FORT]:
					continue
				seen[next] = true
				queue.append(next)
		if not reached:
			out.append("stage %d: gate column %d cannot reach the beacon wall" % [index + 1, gate])
	return out
