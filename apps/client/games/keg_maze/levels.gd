extends RefCounted

## Stage data of Keg Burrow and the generator that turns a hand-drawn layout into a playable field. A layout fixes the walls, the start corners and where blocks may stand; the seeded generator decides which of those places hold a block, what is buried under them and where the foes begin.

const COLS := 19
const ROWS := 15
const TILE := 16
## Top-left corner of the field on the 480x270 stage. The field sits between the two HUD corners, under the clock.
const ORIGIN := Vector2(88, 30)

const FLOOR := 0
const WALL := 1
const CRATE := 2
## A block that a blast has set alight: still solid until it has burned away.
const BURNING := 3

## Where a run is: the level's name is up, the level is being played, the lift was reached, a continue is being spent, or the dig is lost.
enum Phase { INTRO, PLAY, CLEAR, CONTINUE, DEFEAT }

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Layout legend: '#' rock, '.' floor that never holds a block, '+' floor that may hold a block, 'X' always a block, '1' '2' the start cells, 'B' the top-left cell of a boss, 'x' an exit hatch that is visible from the start.
const STAGES := [
	{
		"name": {"zh": "表土坑道", "en": "TOPSOIL CUT"},
		"density": 0.42, "time": 180,
		"foes": {"grub": 3},
		"loot": ["keg", "blast", "blast", "boots", "gem", "gem"],
		"rows": [
			"###################",
			"#1.+++++++++++++++#",
			"#.#+#+#+#+#+#+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+#+#+#+#+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+#+#+#+#+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+#+#+#+#+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+#+#+#+#+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+#+#+#+#+#+#.#",
			"#+++++++++++++++.2#",
			"###################",
		],
	},
	{
		"name": {"zh": "老矿工食堂", "en": "THE OLD MESS HALL"},
		"density": 0.46, "time": 180,
		"foes": {"grub": 3, "mite": 2},
		"loot": ["keg", "blast", "boots", "hat", "clock", "gem", "gem"],
		"rows": [
			"###################",
			"#1.+++++++++++++++#",
			"#.#+#+#+#+#+#+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+###+###+#+#+#",
			"#+++++#.....#+++++#",
			"#+#+#+..X.X..+#+#+#",
			"#+++++#.....#+++++#",
			"#+#+#+..X.X..+#+#+#",
			"#+++++#.....#+++++#",
			"#+#+#+###+###+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+#+#+#+#+#+#.#",
			"#+++++++++++++++.2#",
			"###################",
		],
	},
	{
		"name": {"zh": "三层巷", "en": "THREE GALLERIES"},
		"density": 0.5, "time": 190,
		"foes": {"grub": 2, "mite": 2, "beetle": 2},
		"loot": ["keg", "blast", "remote", "heart", "gem", "gem"],
		"rows": [
			"###################",
			"#1.+++++++++++++++#",
			"#.###+#####+#####+#",
			"#+++++++++++++++++#",
			"#+#+###+#+#+###+#+#",
			"#+++++++++++++++++#",
			"###+#####+#####+###",
			"#+++++++++++++++++#",
			"#+#+###+#+#+###+#+#",
			"#+++++++++++++++++#",
			"#+#####+#####+###.#",
			"#+++++++++++++++..#",
			"#+#+#+#+#+#+#+#+#.#",
			"#+++++++++++++++.2#",
			"###################",
		],
	},
	{
		"name": {"zh": "晶柱大厅", "en": "HALL OF PRISMS"},
		"density": 0.48, "time": 190,
		"foes": {"grub": 2, "beetle": 2, "wisp": 2},
		"loot": ["keg", "blast", "boots", "hat", "gem", "gem", "gem"],
		"rows": [
			"###################",
			"#1.+++++++++++++++#",
			"#.##+++##+##+++##+#",
			"#+##+++##+##+++##+#",
			"#+++++++++++++++++#",
			"#+++##+++++++##+++#",
			"#+++##+++#+++##+++#",
			"#++++++++#++++++++#",
			"#+++##+++#+++##+++#",
			"#+++##+++++++##+++#",
			"#+++++++++++++++++#",
			"#+##+++##+##+++##+#",
			"#+##+++##+##+++##.#",
			"#+++++++++++++++.2#",
			"###################",
		],
	},
	{
		"name": {"zh": "回环晶洞", "en": "THE RINGED GEODE"},
		"density": 0.5, "time": 200,
		"foes": {"mite": 3, "beetle": 2, "wisp": 2, "shell": 1},
		"loot": ["keg", "blast", "remote", "clock", "heart", "gem", "gem"],
		"rows": [
			"###################",
			"#1.+++++++++++++++#",
			"#.###########+###+#",
			"#+#+++++++++++++#+#",
			"#+#+#####+#####+#+#",
			"#+#+#+++++++++#+#+#",
			"#+++#++##+##++#+++#",
			"#+#+++++++++++++#+#",
			"#+++#++##+##++#+++#",
			"#+#+#+++++++++#+#+#",
			"#+#+#####+#####+#+#",
			"#+#+++++++++++++#+#",
			"#+###+###########.#",
			"#+++++++++++++++.2#",
			"###################",
		],
	},
	{
		"name": {"zh": "晶螯巢穴", "en": "LAIR OF THE GEODE CLAW"},
		"density": 0.0, "time": 240,
		"foes": {},
		"boss": 0,
		"loot": ["blast", "keg", "heart", "hat"],
		"rows": [
			"###################",
			"#1.......x........#",
			"#.#.............#.#",
			"#...XX.......XX...#",
			"#...X.........X...#",
			"#.................#",
			"#.......B.........#",
			"#.................#",
			"#.................#",
			"#.................#",
			"#...X.........X...#",
			"#...XX.......XX...#",
			"#.#.............#.#",
			"#................2#",
			"###################",
		],
	},
	{
		"name": {"zh": "余烬岔口", "en": "CINDER CROSSING"},
		"density": 0.52, "time": 200,
		"foes": {"beetle": 3, "wisp": 2, "shell": 2},
		"loot": ["keg", "blast", "boots", "hat", "gem", "gem", "gem"],
		"rows": [
			"###################",
			"#1.+++++#+#+++++++#",
			"#.#+#+#+#+#+#+#+#+#",
			"#+++++++++++++++++#",
			"#+###+#+###+#+###+#",
			"#+#+++++++++++++#+#",
			"#+#+#+###+###+#+#+#",
			"#+++++++++++++++++#",
			"#+#+#+###+###+#+#+#",
			"#+#+++++++++++++#+#",
			"#+###+#+###+#+###+#",
			"#+++++++++++++++++#",
			"#+#+#+#+#+#+#+#+#.#",
			"#+++++++#+#+++++.2#",
			"###################",
		],
	},
	{
		"name": {"zh": "熔渣蜂巢", "en": "THE SLAG HIVE"},
		"density": 0.55, "time": 210,
		"foes": {"mite": 3, "beetle": 3, "wisp": 3, "shell": 2},
		"loot": ["keg", "blast", "remote", "heart", "clock", "gem", "gem", "gem"],
		"rows": [
			"###################",
			"#1.++++++#++++++++#",
			"#.##+#+#+#+#+#+##+#",
			"#+++++++++++++++++#",
			"##+#+##+#+#+##+#+##",
			"#+++++++++++++++++#",
			"#+#+##+#+++#+##+#+#",
			"#++++++++#++++++++#",
			"#+#+##+#+++#+##+#+#",
			"#+++++++++++++++++#",
			"##+#+##+#+#+##+#+##",
			"#+++++++++++++++++#",
			"#+##+#+#+#+#+#+##.#",
			"#++++++++#++++++.2#",
			"###################",
		],
	},
	{
		"name": {"zh": "熔心王座", "en": "THRONE OF THE MOLTEN CLAW"},
		"density": 0.0, "time": 300,
		"foes": {},
		"boss": 1,
		"loot": ["heart", "hat", "blast", "keg"],
		"rows": [
			"###################",
			"#1.......x.......X#",
			"#.##...........##.#",
			"#.#.............#.#",
			"#.....X.....X.....#",
			"#.................#",
			"#.......B.........#",
			"#.................#",
			"#.................#",
			"#.................#",
			"#.....X.....X.....#",
			"#.#.............#.#",
			"#.##...........##.#",
			"#X...............2#",
			"###################",
		],
	},
]

const STAGE_COUNT := 9
## Seconds added to or taken from every stage's clock by the difficulty option (easy, normal, hard).
const TIME_SHIFT := [30, 0, -20]
## Foes begin at least this many steps away from either start cell.
const FOE_DISTANCE := 7
const EXIT_DISTANCE := 8

static func index(cell: Vector2i) -> int:
	return cell.y * COLS + cell.x

static func cell_of(at: int) -> Vector2i:
	return Vector2i(at % COLS, at / COLS)

static func inside(cell: Vector2i) -> bool:
	return cell.x >= 1 and cell.y >= 1 and cell.x < COLS - 1 and cell.y < ROWS - 1

## Which of the three depths a stage belongs to (tiles, music and palette follow it).
static func world(stage: int) -> int:
	return clampi(stage / 3, 0, 2)

static func stage_name(stage: int, locale: String) -> String:
	var names: Dictionary = STAGES[stage]["name"]
	return str(names["en"] if locale == "en" else names["zh"])

## Build the field of one stage: { grid, buried: { cell index: item }, starts: [cell, cell], foes: [[kind, cell]], exit: cell, exit_visible, time, boss: tier or -1 }.
static func build(stage: int, rng: GameRng, difficulty: int) -> Dictionary:
	var spec: Dictionary = STAGES[stage]
	var rows: Array = spec["rows"]
	var grid := PackedInt32Array()
	grid.resize(COLS * ROWS)
	var starts: Array[Vector2i] = [Vector2i(1, 1), Vector2i(COLS - 2, ROWS - 2)]
	var maybe: Array[Vector2i] = []
	var crates: Array[Vector2i] = []
	var foes: Array = []
	var exit := Vector2i(-1, -1)
	var exit_visible := false
	for y in ROWS:
		var row: String = rows[y]
		for x in COLS:
			var cell := Vector2i(x, y)
			match row[x]:
				"#":
					grid[index(cell)] = WALL
				"+":
					maybe.append(cell)
				"X":
					crates.append(cell)
				"1":
					starts[0] = cell
				"2":
					starts[1] = cell
				"B":
					foes.append(["boss", cell])
				"x":
					exit = cell
					exit_visible = true
	var density := float(spec["density"])
	for cell in maybe:
		if _near_start(cell, starts):
			continue
		if rng.chance(density):
			crates.append(cell)
	# Foes take cells far from both starts; a block standing there gives way.
	var far: Array[Vector2i] = []
	for cell in maybe:
		if _distance(cell, starts[0]) >= FOE_DISTANCE and _distance(cell, starts[1]) >= FOE_DISTANCE:
			far.append(cell)
	rng.shuffle(far)
	var wanted: Dictionary = spec["foes"]
	for kind: String in ["grub", "mite", "beetle", "wisp", "shell"]:
		for count in int(wanted.get(kind, 0)):
			if far.is_empty():
				break
			var spot: Vector2i = far.pop_back()
			crates.erase(spot)
			foes.append([kind, spot])
	for cell in crates:
		grid[index(cell)] = CRATE
	var hiding: Array[Vector2i] = crates.duplicate()
	rng.shuffle(hiding)
	var buried := {}
	if not exit_visible:
		var best := -1
		for at in hiding.size():
			if _distance(hiding[at], starts[0]) >= EXIT_DISTANCE and _distance(hiding[at], starts[1]) >= EXIT_DISTANCE - 4:
				best = at
				break
		if best < 0:
			best = 0
		exit = hiding[best]
		hiding.remove_at(best)
		buried[index(exit)] = "exit"
	for item: String in spec["loot"]:
		if hiding.is_empty():
			break
		buried[index(hiding.pop_back())] = item
	return {
		"grid": grid, "buried": buried, "starts": starts, "foes": foes, "exit": exit, "exit_visible": exit_visible,
		"time": float(int(spec["time"]) + int(TIME_SHIFT[clampi(difficulty, 0, 2)])), "boss": int(spec.get("boss", -1)),
	}

static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _near_start(cell: Vector2i, starts: Array[Vector2i]) -> bool:
	return _distance(cell, starts[0]) <= 2 or _distance(cell, starts[1]) <= 2

## Problems of the authored data, for the test: every row is COLS wide, the border is rock, both starts exist and every open cell can be reached from the first start.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if STAGES.size() != STAGE_COUNT:
		out.append("expected %d stages, found %d" % [STAGE_COUNT, STAGES.size()])
	for stage in STAGES.size():
		var rows: Array = STAGES[stage]["rows"]
		if rows.size() != ROWS:
			out.append("stage %d: %d rows" % [stage + 1, rows.size()])
			continue
		var fine := true
		for y in ROWS:
			if str(rows[y]).length() != COLS:
				out.append("stage %d row %d: %d columns" % [stage + 1, y, str(rows[y]).length()])
				fine = false
		if not fine:
			continue
		var open := 0
		var first := Vector2i(-1, -1)
		var seconds := 0
		for y in ROWS:
			for x in COLS:
				var mark: String = rows[y][x]
				if (x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1) and mark != "#":
					out.append("stage %d: the border is open at %d,%d" % [stage + 1, x, y])
				if mark != "#":
					open += 1
				if mark == "1":
					first = Vector2i(x, y)
				if mark == "2":
					seconds += 1
		if first.x < 0 or seconds != 1:
			out.append("stage %d: needs one '1' and one '2'" % (stage + 1))
			continue
		var seen := {first: true}
		var queue: Array[Vector2i] = [first]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			for dir in DIRS:
				var next := cell + dir
				if inside(next) and rows[next.y][next.x] != "#" and not seen.has(next):
					seen[next] = true
					queue.append(next)
		if seen.size() != open:
			out.append("stage %d: %d open cells cannot be reached" % [stage + 1, open - seen.size()])
	return out
