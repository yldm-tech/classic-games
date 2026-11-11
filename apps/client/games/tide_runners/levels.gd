extends RefCounted

## The three stages as data. Lengths are in tiles (16 px). A stage is either "h" (scrolls right, 17 rows tall, water under the gaps) or "v" (a tower climbed upwards, 30 tiles wide, the tide rising from below).
##
##   ground   [first column, last column, top row]         solid from the top row down to the bottom
##   blocks   [column, row, width, height]                 solid
##   plats    [column, row, width]                         thin platforms: stood on from above, jumped through from below
##   spawns   [kind, column, row, extra]                   the row is the tile the thing stands on; extra is the canister a courier or locker holds
##   zones    [first column, last column, kind, seconds]   (h) or [first row, last row, kind, seconds] (v): a stream of that enemy while the camera is inside
##   locks    [camera column, kills]                       the camera stops there until that many machines are destroyed

const STAGE_COUNT := 3

const NAMES := [
	{"zh": "沉没大道", "en": "DROWNED BOULEVARD"},
	{"zh": "泵站高塔", "en": "PUMP TOWER"},
	{"zh": "风暴船坞", "en": "STORM DOCKYARD"},
]
const BOSS_NAMES := [
	{"zh": "巨颚疏浚机", "en": "THE DREDGER MAW"},
	{"zh": "三首水阀", "en": "THE VALVE HYDRA"},
	{"zh": "龙门海兽", "en": "THE GANTRY LEVIATHAN"},
]

## The tower's platform rows, repeated up the shaft: each entry is the [column, width] spans of one row. Consecutive rows always overlap, so every row can be reached from the one below.
const TOWER_ROWS := [
	[[3, 8], [19, 8]], [[9, 12]], [[2, 8], [20, 8]], [[8, 5], [17, 5]], [[1, 8], [21, 8]],
	[[7, 6], [17, 6]], [[11, 8]], [[4, 8], [18, 8]], [[1, 5], [12, 6], [24, 5]], [[5, 8], [17, 8]],
	[[10, 10]], [[3, 8], [19, 8]], [[1, 4], [9, 5], [16, 5], [25, 4]], [[5, 6], [19, 6]], [[10, 10]],
	[[2, 9], [19, 9]], [[9, 4], [17, 4]], [[3, 7], [20, 7]], [[8, 14]], [[1, 8], [21, 8]],
]
const TOWER_LEVELS := 50
const TOWER_FLOOR_ROW := 168
const TOWER_ARENA_ROW := 15
## What stands on which tower level: level -> [kind, which span of that row, extra].
const TOWER_SPAWNS := {
	4: ["cling", 0, 0], 6: ["carrier", 0, 5], 7: ["turret", 0, 0], 8: ["cling", 1, 0], 11: ["cling", 0, 0], 12: ["turret", 1, 0],
	14: ["cling", 0, 0], 15: ["turret", 0, 0], 16: ["cling", 1, 0], 19: ["cling", 0, 0], 20: ["turret", 0, 0], 22: ["carrier", 0, 3],
	23: ["cling", 1, 0], 24: ["turret", 0, 0], 26: ["cling", 1, 0], 28: ["cling", 0, 0], 29: ["turret", 1, 0], 30: ["crate", 0, 6],
	31: ["cling", 0, 0], 32: ["turret", 0, 0], 33: ["cling", 2, 0], 35: ["turret", 0, 0], 36: ["cling", 1, 0], 38: ["carrier", 0, 1],
	39: ["cling", 0, 0], 40: ["turret", 1, 0], 41: ["cling", 0, 0], 43: ["cling", 1, 0], 44: ["turret", 0, 0], 45: ["cling", 0, 0],
	46: ["carrier", 0, 4], 47: ["turret", 1, 0], 48: ["cling", 0, 0], 49: ["turret", 0, 0],
}

static func stage(index: int) -> Dictionary:
	match index:
		0:
			return _boulevard()
		1:
			return _tower()
		_:
			return _dockyard()

static func _boulevard() -> Dictionary:
	return {
		"format": "h", "theme": 0, "cols": 330, "rows": 17, "boss": 0, "boss_col": 300, "start": Vector2(40, 224),
		"ground": [[0, 41, 14], [45, 70, 14], [71, 80, 12], [81, 97, 14], [102, 158, 14], [162, 166, 14], [170, 214, 14], [230, 280, 14], [284, 329, 14]],
		"blocks": [[188, 12, 8, 2], [196, 10, 3, 4], [250, 12, 2, 2]],
		"plats": [[34, 11, 5], [62, 10, 4], [98, 12, 4], [108, 10, 4], [124, 11, 5], [138, 11, 5], [131, 8, 5], [202, 11, 5], [216, 13, 3], [221, 12, 3], [226, 13, 3], [244, 10, 4], [258, 10, 4], [276, 11, 4], [304, 11, 4], [312, 8, 4]],
		"spawns": [
			["carrier", 22, 5, 1], ["turret", 53, 14, 0], ["troop", 66, 14, 0], ["troop", 76, 12, 0], ["turret", 87, 14, 0], ["pike", 99, 0, 0], ["turret", 110, 10, 0], ["toad", 116, 14, 0],
			["carrier", 152, 5, 2], ["pike", 160, 0, 0], ["troop", 164, 14, 0], ["pike", 168, 0, 0], ["toad", 176, 14, 0], ["turret", 184, 14, 0], ["troop", 192, 12, 0], ["turret", 197, 10, 0],
			["crate", 204, 11, 6], ["troop", 208, 14, 0], ["pike", 219, 0, 0], ["pike", 224, 0, 0], ["turret", 233, 14, 0], ["carrier", 246, 5, 4], ["turret", 264, 14, 0], ["toad", 267, 14, 0],
			["troop", 275, 14, 0], ["turret", 278, 11, 0], ["pike", 282, 0, 0], ["carrier", 288, 5, 3], ["troop", 290, 14, 0], ["turret", 294, 14, 0],
		],
		"zones": [[20, 115, "scut", 2.6], [30, 115, "drone", 5.5], [150, 235, "scut", 2.2], [150, 235, "drone", 4.0], [270, 298, "scut", 2.0]],
		"locks": [[120, 10], [240, 12]],
	}

static func _tower() -> Dictionary:
	var plats: Array = []
	var spawns: Array = []
	for level in range(1, TOWER_LEVELS + 1):
		var row := TOWER_FLOOR_ROW - 3 * level
		var spans: Array = TOWER_ROWS[(level - 1) % TOWER_ROWS.size()]
		for span: Array in spans:
			plats.append([span[0], row, span[1]])
		if TOWER_SPAWNS.has(level):
			var entry: Array = TOWER_SPAWNS[level]
			var span: Array = spans[mini(int(entry[1]), spans.size() - 1)]
			var column := int(span[0]) + int(span[1]) / 2
			var kind: String = entry[0]
			spawns.append([kind, column, row - 5 if kind == "carrier" else row, entry[2]])
	plats.append([1, TOWER_ARENA_ROW, 28])
	plats.append([3, 11, 5])
	plats.append([22, 11, 5])
	return {
		"format": "v", "theme": 1, "cols": 30, "rows": 170, "boss": 1, "boss_row": TOWER_ARENA_ROW, "start": Vector2(200, TOWER_FLOOR_ROW * 16),
		"ground": [[0, 29, TOWER_FLOOR_ROW]],
		"blocks": [[0, 0, 1, 170], [29, 0, 1, 170]],
		"plats": plats,
		"spawns": spawns,
		"zones": [[20, 140, "drone", 4.6], [20, 118, "debris", 3.4], [20, 96, "pike", 6.0]],
		"locks": [],
	}

static func _dockyard() -> Dictionary:
	return {
		"format": "h", "theme": 2, "cols": 330, "rows": 17, "boss": 2, "boss_col": 300, "start": Vector2(40, 224),
		"ground": [[0, 36, 14], [40, 74, 14], [79, 110, 14], [115, 149, 14], [153, 189, 14], [194, 239, 14], [243, 269, 14], [273, 329, 14]],
		"blocks": [[12, 12, 4, 2], [24, 12, 4, 2], [28, 10, 4, 4], [48, 12, 6, 2], [58, 12, 3, 2], [61, 10, 3, 4], [64, 12, 3, 2], [86, 12, 8, 2], [90, 10, 4, 2], [120, 12, 4, 2], [128, 12, 4, 2], [136, 12, 4, 2], [160, 12, 6, 2], [166, 10, 6, 4], [172, 8, 6, 6], [200, 12, 4, 2], [212, 12, 4, 2], [224, 12, 4, 2], [250, 12, 6, 2], [280, 12, 4, 2], [290, 12, 4, 2], [294, 10, 4, 4]],
		"plats": [[16, 9, 6], [42, 10, 4], [68, 10, 5], [75, 12, 4], [98, 9, 5], [104, 11, 4], [111, 12, 4], [142, 10, 5], [150, 12, 3], [182, 10, 5], [190, 12, 4], [204, 9, 5], [216, 9, 5], [228, 9, 5], [240, 12, 3], [256, 9, 5], [262, 11, 4], [270, 12, 3], [284, 9, 5]],
		"spawns": [
			["carrier", 14, 5, 5], ["turret", 29, 10, 0], ["troop", 33, 14, 0], ["toad", 44, 14, 0], ["turret", 50, 12, 0], ["troop", 56, 14, 0], ["turret", 62, 10, 0], ["pike", 76, 0, 0], ["pike", 78, 0, 0],
			["troop", 82, 14, 0], ["turret", 91, 10, 0], ["toad", 100, 9, 0], ["troop", 106, 14, 0], ["pike", 112, 0, 0], ["carrier", 118, 5, 3], ["turret", 122, 12, 0], ["turret", 130, 12, 0], ["turret", 138, 12, 0],
			["troop", 146, 14, 0], ["toad", 156, 14, 0], ["turret", 163, 12, 0], ["turret", 169, 10, 0], ["turret", 175, 8, 0], ["troop", 180, 14, 0], ["carrier", 184, 5, 2], ["pike", 191, 0, 0], ["pike", 193, 0, 0],
			["toad", 214, 12, 0], ["turret", 226, 12, 0], ["troop", 232, 14, 0], ["pike", 241, 0, 0], ["carrier", 244, 5, 4], ["turret", 252, 12, 0], ["toad", 258, 9, 0], ["troop", 264, 14, 0], ["pike", 271, 0, 0],
			["turret", 282, 12, 0], ["crate", 286, 9, 6], ["troop", 288, 14, 0], ["turret", 296, 10, 0],
		],
		"zones": [[10, 90, "scut", 2.2], [10, 90, "drone", 4.0], [125, 190, "scut", 1.9], [125, 190, "drone", 3.2], [230, 298, "scut", 1.7], [230, 298, "drone", 3.0]],
		"locks": [[95, 12], [195, 16]],
	}
