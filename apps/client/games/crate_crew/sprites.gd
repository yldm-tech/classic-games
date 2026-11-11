extends RefCounted

## Every sprite of Crate Crew, authored here as rows of palette characters (one character is one pixel) or drawn by small routines for the larger machines. build() turns them into textures once per run; nothing is loaded from image files.

## The palette. One character names one colour everywhere in this file; "." is transparent.
const PALETTE := {
	"k": "1a1423", "w": "f4f1e8", "g": "b9c0c9", "G": "7b8794", "d": "4a5463", "D": "222834",
	"t": "5fd4c4", "T": "2a8f8a", "o": "f5a340", "O": "c2622a", "y": "ffd75e", "Y": "c9952c",
	"r": "e5484d", "R": "9c2b3b", "b": "4f8fe6", "B": "2b4c9a", "n": "c98f52", "N": "96623a",
	"m": "5f3b28", "c": "f0d9a8", "e": "6cc04a", "E": "3a7d3c", "p": "9a6bd6", "P": "5a3a8e",
	"l": "b8ff9a", "L": "bff3ff", "s": "ff8a3c", "S": "ffb26b",
}

## Characters a hero's rows use for its own colours, and what each hero maps them to: body, body shade, chest light.
const HERO_SWAPS := [
	{"H": "t", "h": "T", "A": "y"},
	{"H": "o", "h": "O", "A": "L"},
]

const HEAD_ROUND := [
	"........y.......",
	"........k.......",
	"....kkkkkkkk....",
	"...kHHHHHHHHk...",
	"..kHwwHHHHHHHk..",
	"..kHDDDDDDDDhk..",
	"..kHDDlDDDlDhk..",
	"..kHDDlDDDlDhk..",
	"..khhDDDDDDhhk..",
]
const HEAD_SQUARE := [
	".....kkkkkk.....",
	"....kk....kk....",
	"..kkkkkkkkkkkk..",
	"..kHHHHHHHHHHk..",
	"..kHwHHHHHHHhk..",
	"..kHDDDDDDDDhk..",
	"..kHDDllDllDhk..",
	"..kHDDDDDDDDhk..",
	"..khhhhhhhhhhk..",
]
const TORSO := [
	"...kkkkkkkkkk...",
	"....kHHHHHHk....",
	"....kHAAHHhk....",
	"....kHhhhhhk....",
	"....kkkkkkkk....",
]
const LEGS := {
	"idle": ["....kdk..kdk....", "...kkkk..kkkk..."],
	"apart": ["...kdk....kdk...", "..kkkk....kkkk.."],
	"close": [".....kdkkdk.....", ".....kkkkkkk...."],
	"jump": ["...kdkk..kkdk...", "....kk....kk...."],
	"fall": ["..kdk......kdk..", "..kk........kk.."],
	"squat": ["..kkkk....kkkk..", "..kkkk....kkkk.."],
}
const ARMS_DOWN := [
	"................", "................", "................", "................", "................",
	"................", "................", "................", "................", "................",
	"..kg........gk..",
	"..kg........gk..",
	"..kw........wk..",
	"..kk........kk..",
	"................", "................",
]
const ARMS_UP := [
	"................",
	"kk............kk",
	"kwk..........kwk",
	"kgk..........kgk",
	"kgk..........kgk",
	"kgk..........kgk",
	"kgk..........kgk",
	"kgk..........kgk",
	"kgk..........kgk",
	"kgkk........kkgk",
	".kkk........kkk.",
	"................", "................", "................", "................", "................",
]

const CRATE_WOOD := [
	"kkkkkkkkkkkkkkkk",
	"kccnnnnnnnnnnnmk",
	"kcnNNNNNNNNNNnmk",
	"knNmmNNNNNNmmNmk",
	"knNmnnNNNNnnmNmk",
	"knNNnnnNNnnnNNmk",
	"knNNNnnnnnnNNNmk",
	"knNNNNnnnnNNNNmk",
	"knNNNNnnnnNNNNmk",
	"knNNNnnnnnnNNNmk",
	"knNNnnnNNnnnNNmk",
	"knNmnnNNNNnnmNmk",
	"knNmmNNNNNNmmNmk",
	"knnNNNNNNNNNNnmk",
	"kmmmmmmmmmmmmmmk",
	"kkkkkkkkkkkkkkkk",
]
const CRATE_STEEL := [
	"kkkkkkkkkkkkkkkk",
	"kwggggggggggggGk",
	"kgGGGGGGGGGGGGdk",
	"kgGwGGGGGGGGwGdk",
	"kgGGGGGGGGGGGGdk",
	"kgddddddddddddGk",
	"kgyykkyykkyykkdk",
	"kgykkyykkyykkydk",
	"kgkkyykkyykkyydk",
	"kgwwwwwwwwwwwwdk",
	"kgGGGGGGGGGGGGdk",
	"kgGGGGGGGGGGGGdk",
	"kgGwGGGGGGGGwGdk",
	"kgGGGGGGGGGGGGdk",
	"kGddddddddddddDk",
	"kkkkkkkkkkkkkkkk",
]
const SCRAP := [
	"...kkkkkk...",
	"..kgGGdGgk..",
	".kgGnnGGdGk.",
	"kgGGnNGgGGdk",
	"kGdGGGGGnNdk",
	"kGGgGdGGnGdk",
	"kdGGGGGgGGdk",
	"kGnNGGdGGGdk",
	"kGnGGgGGdGdk",
	".kdGGGGGddk.",
	"..kddddddk..",
	"...kkkkkk...",
]
const HEXNUT := [
	"...kkkkkk...",
	"..kwggggGk..",
	".kwgGGGGGdk.",
	"kwgGkkkkGGdk",
	"kgGkDDDDkGdk",
	"kgGkDDDDkGdk",
	"kgGkDDDDkGdk",
	"kgGkDDDDkGdk",
	"kgGGkkkkGGdk",
	".kGGGGGGGdk.",
	"..kddddddk..",
	"...kkkkkk...",
]
const NUT_SMALL := [
	"..kkkk..",
	".kggGGk.",
	"kgGkkGdk",
	"kgkDDkdk",
	"kGkDDkdk",
	"kGGkkddk",
	".kGdddk.",
	"..kkkk..",
]
const SPARK_A := [
	"..y...",
	"..wy.y",
	"ywwwy.",
	".ywwwy",
	"y.yw..",
	"...y..",
]
const SPARK_B := [
	"y...y.",
	".yww..",
	".wwwy.",
	".ywww.",
	"..wwy.",
	".y...y",
]
const GEAR_A := [
	"...yy...",
	".y.yy.y.",
	"..yYYy..",
	"yyYkkYyy",
	"yyYkkYyy",
	"..yYYy..",
	".y.yy.y.",
	"...yy...",
]
const GEAR_B := [
	"..y..y..",
	"..yyyy..",
	"yyyYYyyy",
	".yYkkYy.",
	".yYkkYy.",
	"yyyYYyyy",
	"..yyyy..",
	"..y..y..",
]
const BATTERY := [
	"..kwwk..",
	".kkkkkk.",
	".keeeek.",
	".kewyek.",
	".keyyek.",
	".keywek.",
	".keeeek.",
	".keEEek.",
	".kEEEEk.",
	".kkkkkk.",
]
const CHIP := [
	"..k.kk.k..",
	".kkkkkkkk.",
	"kTttttttTk",
	"ktDDttDDtk",
	"ktDltttlDk",
	"ktttttttTk",
	"kttkkkkttk",
	"kTttttttTk",
	".kkkkkkkk.",
	"..k.kk.k..",
]
const COG_GOLD := [
	"....yyyy....",
	".yy.yYYy.yy.",
	".yyyyYYyyyy.",
	"..yYYwwYYy..",
	"yyYYwkkwYYyy",
	"yYYwkkkkwYYy",
	"yYYwkkkkwYYy",
	"yyYYwkkwYYyy",
	"..yYYwwYYy..",
	".yyyyYYyyyy.",
	".yy.yYYy.yy.",
	"....yyyy....",
]

const BUG_A := [
	"..yy............",
	".ykky...kkkk....",
	"..yy.kkkppppkk..",
	"..kkkpppppppppk.",
	".kppwppppppkkpk.",
	"kpppppppppkwwkpk",
	"kpPPpppppppkkPPk",
	"kPPPPPPPPPPPPPPk",
	".kkkkkkkkkkkkkk.",
	"..kd.kd..kd.kd..",
	"..kd.kd..kd.kd..",
	"..kk.kk..kk.kk..",
]
const BUG_B := [
	".yy.............",
	"ykky....kkkk....",
	".yy..kkkppppkk..",
	"..kkkpppppppppk.",
	".kppwppppppkkpk.",
	"kpppppppppkwwkpk",
	"kpPPpppppppkkPPk",
	"kPPPPPPPPPPPPPPk",
	".kkkkkkkkkkkkkk.",
	".kd..kd.kd..kd..",
	"kd...kdkd....kd.",
	"kk...kkkk....kk.",
]
const HOPPER_SIT := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"....kkkkkkk.....",
	"...keeeeeeek....",
	"..keeewwweEek...",
	"..keeewkweEek...",
	"..keeeeeeEEek...",
	"...kEEEEEEEk....",
	"....kkkkkkk.....",
	"....gGGGGGg.....",
	"....GggggGG.....",
	"...kkkkkkkkk....",
	"...kdddddddk....",
]
const HOPPER_JUMP := [
	"....kkkkkkk.....",
	"...keeeeeeek....",
	"..keeewwweEek...",
	"..keeewkweEek...",
	"..keeeeeeEEek...",
	"...kEEEEEEEk....",
	"....kkkkkkk.....",
	"......gG........",
	".......Gg.......",
	"......gG........",
	".......Gg.......",
	"......gG........",
	".......Gg.......",
	"......gG........",
	"...kkkkkkkkk....",
	"...kdddddddk....",
]
const DRONE_A := [
	"..ggg.....ggg...",
	"....k.....k.....",
	"..g.kkkkkkk.g...",
	".gGkrrrrrrrkGg..",
	"..krrwwrrrRRk...",
	"gGkrrwkrrrRRkGg.",
	"..krrrrrrRRRk...",
	".gGkRRRRRRRkGg..",
	"..g.kkkkkkk.g...",
	"....g..g..g.....",
	"................",
	"................",
]
const DRONE_B := [
	"...g.......g....",
	"....k.....k.....",
	"...gkkkkkkkg....",
	"..Gkrrrrrrrkg...",
	".gkrrwwrrrRRkG..",
	"..krrwkrrrRRk...",
	".Gkrrrrrrrrrkg..",
	"..gkRRRRRRRkG...",
	"...gkkkkkkkg....",
	".....g..g.......",
	"................",
	"................",
]
const TURRET_A := [
	"................",
	"................",
	"................",
	"....kkkkkk......",
	"...kbbbbbbk.....",
	"..kbbwwbbbbkkkk.",
	"..kbbwkbbbbgggk.",
	"..kbBBBBBBBkkkk.",
	"...kBBBBBBk.....",
	"....kkkkkk......",
	".....kGGk.......",
	".....kGGk.......",
	"...kkkkkkkk.....",
	"..kGGgGGgGGk....",
	"..kddddddddk....",
	"..kkkkkkkkkk....",
]
const TURRET_B := [
	"................",
	"................",
	"................",
	"...kkkkkk.......",
	"..kbbbbbbk....y.",
	".kbbrrbbbbkkkyw.",
	".kbbrkbbbbggywwy",
	".kbBBBBBBBkkkyw.",
	"..kBBBBBBk....y.",
	"...kkkkkk.......",
	".....kGGk.......",
	".....kGGk.......",
	"...kkkkkkkk.....",
	"..kGGgGGgGGk....",
	"..kddddddddk....",
	"..kkkkkkkkkk....",
]
const ROLLER_A := [
	"....kkkkkkkk....",
	"..kkGGGGGGGGkk..",
	".kGGgggggggGGGk.",
	".kGgGGGGGGGGgGk.",
	"kGgGGkkGGGkkGgGk",
	"kGgGkyykGkyykgdk",
	"kGgGkkykGkkykgdk",
	"kGgGGkkGGGkkGgdk",
	"kGgGdGGGGGGdGgdk",
	"kGgGGGGddGGGGgdk",
	"kGGgGGGGGGGGgGdk",
	".kGGgggggggGGdk.",
	".kdGGGGGGGGGddk.",
	"..kkddddddddkk..",
	"....kkkkkkkk....",
	"................",
]
const ROLLER_B := [
	"....kkkkkkkk....",
	"..kkGGGGGGGGkk..",
	".kGGgggggggGGGk.",
	".kGgGGGddGGGgGk.",
	"kGgGGkkGGGkkGgGk",
	"kGgGkyykGkyykgdk",
	"kGgGkkykGkkykgdk",
	"kGgGGkkGGGkkGgdk",
	"kGgGGGGGGGGGGgdk",
	"kGgdGGGGGGGGdgdk",
	"kGGgGGGGGGGGgGdk",
	".kGGgggddggGGdk.",
	".kdGGGGGGGGGddk.",
	"..kkddddddddkk..",
	"....kkkkkkkk....",
	"................",
]
const MAGNET_A := [
	"...ggggggggg....",
	".......k........",
	"...kkkkkkkkkk...",
	"..krrrrrrrrrrk..",
	".krrrwwrrwwrrRk.",
	".krrrwkrrwkrrRk.",
	".krrrrrrrrrrRRk.",
	".krrRkkkkkkrRRk.",
	".krrRk....krRRk.",
	".krrRk....krRRk.",
	".kkkkk....kkkkk.",
	".kgggk....kgggk.",
	".kgGGk....kgGGk.",
	".kkkkk....kkkkk.",
]
const MAGNET_B := [
	".....ggggg......",
	".......k........",
	"...kkkkkkkkkk...",
	"..krrrrrrrrrrk..",
	".krrrwwrrwwrrRk.",
	".krrrwkrrwkrrRk.",
	".krrrrrrrrrrRRk.",
	".krrRkkkkkkrRRk.",
	".krrRk....krRRk.",
	".krrRk....krRRk.",
	".kkkkk....kkkkk.",
	".kgggk....kgggk.",
	".kgGGk....kgGGk.",
	".kkkkk....kkkkk.",
]
const LIFT_LEFT := [
	".kkkkkkk",
	"kyykkyyk",
	"kykkyykk",
	"kGGGGGGG",
	"kddddddd",
	".kkkkkkk",
	"..k..k..",
	"........",
]
const LIFT_MID := [
	"kkkkkkkkkkkkkkkk",
	"gggggggggggggggg",
	"GGGGGGGGGGGGGGGG",
	"GGGdGGGGGGGdGGGG",
	"dddddddddddddddd",
	"kkkkkkkkkkkkkkkk",
	"....k......k....",
	"................",
]
const LIFT_RIGHT := [
	"kkkkkkk.",
	"kyykkyyk",
	"kkyykkyk",
	"GGGGGGGk",
	"dddddddk",
	"kkkkkkk.",
	"..k..k..",
	"........",
]
const FLAG_OFF := [
	"..kk........",
	".kggk.......",
	".kgGkkkkkk..",
	".kgGkGGGGGk.",
	".kgGkGdGGk..",
	".kgGkGGGk...",
	".kgGkkkk....",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	".kgGk.......",
	"kkgGkk......",
	"kddddk......",
	"kkkkkk......",
]

## Tile rows use shade digits: 1 lightest .. 4 darkest of the stage's material, 5 its accent.
const TILE_WOOD_TOP := [
	"1111111111111111",
	"1222222212222221",
	"2222222222222222",
	"2323222222223222",
	"4444444444444444",
	"3323333343333233",
	"3333333343333333",
	"3333332343333333",
	"4444444444444444",
	"3334333333323333",
	"3234333333333333",
	"3334333333333323",
	"4444444444444444",
	"3333333243333333",
	"3323333343333323",
	"3333333343333333",
]
const TILE_WOOD_IN := [
	"4444444444444444",
	"3323333343333233",
	"3333333343333333",
	"3333332343333333",
	"4444444444444444",
	"3334333333323333",
	"3234333333333333",
	"3334333333333323",
	"4444444444444444",
	"3333333243333333",
	"3323333343333323",
	"3333333343333333",
	"4444444444444444",
	"3334333333233333",
	"3334332333333333",
	"3334333333333233",
]
const TILE_PLATE_TOP := [
	"1111111111111111",
	"2222222222222222",
	"5555555555555555",
	"2222222222222224",
	"3333333333333334",
	"3133333333333134",
	"3333333333333334",
	"3333333333333334",
	"3333332222333334",
	"3333323333233334",
	"3333323333233334",
	"3333332222333334",
	"3333333333333334",
	"3133333333333134",
	"3333333333333334",
	"4444444444444444",
]
const TILE_PLATE_IN := [
	"3333333333333334",
	"3133333333333134",
	"3333333333333334",
	"3333333333333334",
	"3333444444443334",
	"3333433333343334",
	"3333433333343334",
	"3333433333343334",
	"3333433333343334",
	"3333433333343334",
	"3333444444443334",
	"3333333333333334",
	"3333333333333334",
	"3133333333333134",
	"3333333333333334",
	"4444444444444444",
]
const TILE_SHELF := [
	"kkkkkkkkkkkkkkkk",
	"1111111111111111",
	"2222222222222222",
	"3333333333333333",
	"kkkkkkkkkkkkkkkk",
	"..k4k......k4k..",
	"...k........k...",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
]
const TILE_SPIKES := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"...w.......w....",
	"..kgk.....kgk...",
	"..kgk..w..kgk...",
	".kgGdk.gk.gGdk.w",
	".kgGdkkgkkgGdkkg",
	"kgGGdkgGdkgGGdkg",
	"kgGGdkgGdkgGGdgG",
	"gGGGdgGGdgGGGdgG",
	"kkkkkkkkkkkkkkkk",
	"dddddddddddddddd",
]
const TILE_BELT := [
	"kkkkkkkkkkkkkkkk",
	"dddydddddddydddd",
	"ddyyydddddyyyddd",
	"dyydyydddyydyydd",
	"kkkkkkkkkkkkkkkk",
	"3kgGk333333kgGk3",
	"3kGdk333333kGdk3",
	"33kk33333333kk33",
	"3333333333333334",
	"3133333333333134",
	"3333333333333334",
	"3333333333333334",
	"3333333333333334",
	"3133333333333134",
	"3333333333333334",
	"4444444444444444",
]

## Materials of the four stages: shades 1 .. 4 and accent 5 for the tile rows above.
const MATERIALS := [
	{"1": "e2b47a", "2": "c98f52", "3": "96623a", "4": "5f3b28", "5": "c98f52"},
	{"1": "9fd0c8", "2": "5c9aa0", "3": "3d6b78", "4": "22404f", "5": "e0b048"},
	{"1": "d9a37a", "2": "a8674e", "3": "74423d", "4": "40232b", "5": "ff8a3c"},
	{"1": "b7b5e6", "2": "7d79c2", "3": "4d4a8a", "4": "2a2850", "5": "5fd4c4"},
]

var errors: PackedStringArray = PackedStringArray()
## The images the textures were made from, by the same names. The renderer does not need them; tools and tests do.
var images: Dictionary = {}

## Build every texture. Keys are sprite names; "<name>#w" is the same sprite in solid white for hit flashes.
func build() -> Dictionary:
	var out := {}
	for slot in 2:
		var swap: Dictionary = HERO_SWAPS[slot]
		var head: Array = HEAD_ROUND if slot == 0 else HEAD_SQUARE
		var heads := {"open": head, "blink": _replace(head, "l", "d"), "hurt": _replace(head, "l", "r")}
		for leg_name: String in LEGS:
			for head_name: String in heads:
				if head_name != "open" and leg_name != "idle" and leg_name != "fall":
					continue
				var rows: Array = []
				if leg_name == "squat":
					rows = _blank(16, 4) + (heads[head_name] as Array) + [TORSO[0]] + (LEGS[leg_name] as Array)
				elif leg_name == "apart":
					# The stride frame sits one pixel lower: the torso loses a row.
					rows = _blank(16, 1) + (heads[head_name] as Array) + [TORSO[0], TORSO[1], TORSO[2], TORSO[4]] + (LEGS[leg_name] as Array)
				else:
					rows = (heads[head_name] as Array) + TORSO + (LEGS[leg_name] as Array)
				_add(out, "hero%d_%s_%s" % [slot, leg_name, head_name], rows, swap)
		_add(out, "hero%d_arms_down" % slot, ARMS_DOWN, swap)
		_add(out, "hero%d_arms_up" % slot, ARMS_UP, swap)
	_add(out, "wood", CRATE_WOOD)
	_add(out, "steel", CRATE_STEEL)
	_add(out, "scrap", SCRAP)
	_add(out, "hexnut", HEXNUT)
	_add(out, "nut", NUT_SMALL)
	_add(out, "spark0", SPARK_A)
	_add(out, "spark1", SPARK_B)
	_add(out, "gear0", GEAR_A)
	_add(out, "gear1", GEAR_B)
	_add(out, "battery", BATTERY)
	_add(out, "chip", CHIP)
	_add(out, "cog", COG_GOLD)
	_add(out, "bug0", BUG_A)
	_add(out, "bug1", BUG_B)
	_add(out, "hopper0", HOPPER_SIT)
	_add(out, "hopper1", HOPPER_JUMP)
	_add(out, "drone0", DRONE_A)
	_add(out, "drone1", DRONE_B)
	_add(out, "turret0", TURRET_A)
	_add(out, "turret1", TURRET_B)
	_add(out, "roller0", ROLLER_A)
	_add(out, "roller1", ROLLER_B)
	_add(out, "roller_bare0", ROLLER_A, {"G": "s", "g": "S", "d": "O"})
	_add(out, "roller_bare1", ROLLER_B, {"G": "s", "g": "S", "d": "O"})
	_add(out, "magnet0", MAGNET_A)
	_add(out, "magnet1", MAGNET_B)
	_add(out, "lift_l", LIFT_LEFT)
	_add(out, "lift_m", LIFT_MID)
	_add(out, "lift_r", LIFT_RIGHT)
	_add(out, "flag_off", FLAG_OFF)
	_add(out, "flag_on", FLAG_OFF, {"G": "T", "g": "t", "d": "w"})
	for stage in MATERIALS.size():
		var material: Dictionary = MATERIALS[stage]
		var wood := stage == 0
		_add_tile(out, "tile%d_top" % stage, TILE_WOOD_TOP if wood else TILE_PLATE_TOP, material)
		_add_tile(out, "tile%d_in" % stage, TILE_WOOD_IN if wood else TILE_PLATE_IN, material)
		_add_tile(out, "tile%d_shelf" % stage, TILE_SHELF, material)
		_add_tile(out, "tile%d_spikes" % stage, TILE_SPIKES, material)
		for frame in 4:
			_add_tile(out, "tile%d_belt%d" % [stage, frame], _belt_rows(frame), material)
	_put(out, "door", _door(false))
	_put(out, "door_open", _door(true))
	_put(out, "chute", _chute())
	for open in 2:
		for hurt in 2:
			_put(out, "vac_%d_%d" % [open, hurt], _vacuum(open == 1, hurt == 1))
	for hurt in 2:
		_put(out, "crane_%d" % hurt, _crane(hurt == 1))
	_put(out, "claw_open", _claw(true))
	_put(out, "claw_shut", _claw(false))
	return out

# ---- rows to images ----

func _blank(width: int, count: int) -> Array:
	var out: Array = []
	for index in count:
		out.append(".".repeat(width))
	return out

func _replace(rows: Array, from: String, to: String) -> Array:
	var out: Array = []
	for row: String in rows:
		out.append(row.replace(from, to))
	return out

## The belt tile with its chevrons shifted by `frame` * 4 pixels, so four frames make the belt run.
func _belt_rows(frame: int) -> Array:
	var out: Array = TILE_BELT.duplicate()
	for row in [1, 2, 3]:
		var text: String = TILE_BELT[row]
		var shift := frame * 4
		out[row] = text.substr(16 - shift) + text.substr(0, 16 - shift) if shift > 0 else text
	return out

func _image(name: String, rows: Array, swap: Dictionary, colors: Dictionary) -> Image:
	var height := rows.size()
	var width := (rows[0] as String).length() if height > 0 else 1
	var image := Image.create(maxi(1, width), maxi(1, height), false, Image.FORMAT_RGBA8)
	for y in height:
		var row: String = rows[y]
		if row.length() != width:
			errors.append("%s: row %d is %d wide, expected %d" % [name, y, row.length(), width])
			continue
		for x in width:
			var key := row[x]
			if key == ".":
				continue
			key = str(swap.get(key, key))
			if colors.has(key):
				image.set_pixel(x, y, Color(str(colors[key])))
			elif PALETTE.has(key):
				image.set_pixel(x, y, Color(str(PALETTE[key])))
			else:
				errors.append("%s: row %d uses unknown colour '%s'" % [name, y, key])
	return image

func _add(out: Dictionary, name: String, rows: Array, swap: Dictionary = {}) -> void:
	_put(out, name, _image(name, rows, swap, {}))

func _add_tile(out: Dictionary, name: String, rows: Array, material: Dictionary) -> void:
	var image := _image(name, rows, {}, material)
	images[name] = image
	out[name] = ImageTexture.create_from_image(image)

## Store an image and its white silhouette.
func _put(out: Dictionary, name: String, image: Image) -> void:
	images[name] = image
	out[name] = ImageTexture.create_from_image(image)
	var white := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				white.set_pixel(x, y, Color.WHITE)
	out[name + "#w"] = ImageTexture.create_from_image(white)

# ---- drawn machines ----

func _c(key: String) -> Color:
	return Color(str(PALETTE[key]))

func _new(width: int, height: int) -> Image:
	return Image.create(width, height, false, Image.FORMAT_RGBA8)

func _box(image: Image, x: int, y: int, width: int, height: int, key: String) -> void:
	image.fill_rect(Rect2i(x, y, width, height).intersection(Rect2i(0, 0, image.get_width(), image.get_height())), _c(key))

func _dot(image: Image, x: int, y: int, key: String) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, _c(key))

func _oval(image: Image, cx: float, cy: float, rx: float, ry: float, key: String) -> void:
	for y in range(int(floor(cy - ry)), int(ceil(cy + ry)) + 1):
		for x in range(int(floor(cx - rx)), int(ceil(cx + rx)) + 1):
			var dx := (float(x) + 0.5 - cx) / rx
			var dy := (float(y) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_dot(image, x, y, key)

## Surround everything opaque with a one-pixel dark line, so a drawn machine has the same outline as the row sprites.
func _outlined(image: Image) -> Image:
	var out := _new(image.get_width(), image.get_height())
	var dark := _c("k")
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.5:
				out.set_pixel(x, y, pixel)
				continue
			var near := false
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var at := Vector2i(x, y) + offset
				if at.x >= 0 and at.y >= 0 and at.x < image.get_width() and at.y < image.get_height() and image.get_pixel(at.x, at.y).a > 0.5:
					near = true
			if near:
				out.set_pixel(x, y, dark)
	return out

## The exit lift door, 24 x 32.
func _door(open: bool) -> Image:
	var image := _new(24, 32)
	_box(image, 1, 1, 22, 31, "d")
	_box(image, 2, 2, 20, 2, "g")
	_box(image, 2, 4, 2, 28, "G")
	_box(image, 20, 4, 2, 28, "D")
	if open:
		_box(image, 4, 6, 16, 26, "D")
		_box(image, 5, 7, 14, 25, "k")
		_box(image, 6, 26, 12, 6, "T")
		_box(image, 8, 22, 8, 4, "t")
		_box(image, 4, 6, 3, 26, "G")
		_box(image, 17, 6, 3, 26, "G")
	else:
		_box(image, 4, 6, 16, 26, "G")
		_box(image, 4, 6, 16, 1, "g")
		_box(image, 11, 6, 2, 26, "D")
		for stripe in 4:
			_box(image, 5 + stripe * 4, 24, 2, 3, "y")
			_box(image, 7 + stripe * 4, 24, 2, 3, "k")
		_box(image, 6, 10, 3, 6, "L")
		_box(image, 15, 10, 3, 6, "L")
	_box(image, 10, 3, 4, 2, "e" if open else "r")
	return _outlined(image)

## The ceiling chute a fresh crate drops from, 24 x 14.
func _chute() -> Image:
	var image := _new(24, 14)
	_box(image, 1, 0, 22, 5, "G")
	_box(image, 1, 0, 22, 1, "g")
	_box(image, 3, 5, 18, 5, "d")
	_box(image, 3, 5, 2, 5, "G")
	_box(image, 5, 10, 14, 3, "D")
	for stripe in 5:
		_box(image, 2 + stripe * 4, 2, 2, 2, "y")
	return _outlined(image)

## The vacuum beast, 52 x 40, facing left: canister body on wheels, a wide nozzle mouth, a dust bag behind.
func _vacuum(open: bool, hurt: bool) -> Image:
	var image := _new(52, 40)
	# Dust bag behind.
	_oval(image, 43.0, 18.0, 8.0, 12.0, "N")
	_oval(image, 42.0, 16.0, 6.0, 9.0, "n")
	_box(image, 40, 9, 2, 16, "m")
	# Canister.
	_oval(image, 26.0, 19.0, 15.0, 14.0, "P")
	_oval(image, 25.0, 17.0, 13.5, 12.0, "p")
	_oval(image, 22.0, 11.0, 7.0, 3.0, "L")
	_box(image, 13, 22, 26, 2, "P")
	_box(image, 14, 26, 24, 5, "d")
	_box(image, 14, 26, 24, 1, "G")
	# Exhaust stack.
	_box(image, 30, 1, 5, 6, "G")
	_box(image, 29, 0, 7, 2, "g")
	# Nozzle.
	_box(image, 2, 14, 12, 14 if open else 10, "G")
	_box(image, 2, 14, 12, 2, "g")
	_box(image, 0, 13, 3, 16 if open else 12, "d")
	if open:
		_box(image, 3, 17, 9, 9, "k")
		_box(image, 4, 18, 7, 7, "R")
		for tooth in 3:
			_box(image, 4 + tooth * 3, 17, 2, 2, "w")
			_box(image, 4 + tooth * 3, 24, 2, 2, "w")
	else:
		_box(image, 3, 18, 9, 3, "k")
		for tooth in 4:
			_box(image, 3 + tooth * 2, 19, 1, 1, "w")
	# Eyes.
	if hurt:
		for eye in 2:
			var ex := 16 + eye * 9
			for step in 5:
				_dot(image, ex + step, 12 + step, "w")
				_dot(image, ex + 4 - step, 12 + step, "w")
	else:
		for eye in 2:
			var ex := 16 + eye * 9
			_box(image, ex, 12, 6, 5, "y")
			_box(image, ex, 14, 3, 3, "k")
			_box(image, ex + 1, 15, 1, 1, "w")
			for step in 6:
				_dot(image, ex + step, 11 + (step / 2 if eye == 0 else (5 - step) / 2) - 1, "k")
				_dot(image, ex + step, 11 + (step / 2 if eye == 0 else (5 - step) / 2), "k")
	# Wheels.
	for wheel in 2:
		var wx := 18.0 + float(wheel) * 17.0
		_oval(image, wx, 34.0, 5.0, 5.0, "D")
		_oval(image, wx, 34.0, 3.0, 3.0, "G")
		_oval(image, wx, 34.0, 1.2, 1.2, "w")
	return _outlined(image)

## The crane boss's trolley, 48 x 28: a box on rail wheels with one big lens.
func _crane(hurt: bool) -> Image:
	var image := _new(48, 28)
	for wheel in 3:
		_oval(image, 10.0 + float(wheel) * 14.0, 4.0, 4.0, 4.0, "d")
		_oval(image, 10.0 + float(wheel) * 14.0, 4.0, 1.5, 1.5, "g")
	_box(image, 3, 7, 42, 16, "B")
	_box(image, 3, 7, 42, 2, "b")
	_box(image, 3, 9, 2, 14, "b")
	_box(image, 41, 9, 4, 14, "D")
	_box(image, 5, 20, 36, 3, "D")
	for stripe in 9:
		_box(image, 5 + stripe * 4, 20, 2, 3, "y")
	_oval(image, 24.0, 14.0, 8.0, 6.0, "k")
	_oval(image, 24.0, 14.0, 6.5, 4.8, "w" if hurt else "R")
	_oval(image, 24.0, 14.5, 4.0, 3.2, "r")
	_oval(image, 24.0, 15.0, 1.8, 1.8, "k")
	_dot(image, 22, 12, "w")
	_dot(image, 23, 12, "w")
	for lamp in 2:
		_box(image, 8 + lamp * 28, 11, 4, 4, "y" if not hurt else "r")
		_box(image, 8 + lamp * 28, 11, 4, 1, "w")
	_box(image, 20, 23, 8, 4, "G")
	_box(image, 20, 23, 8, 1, "g")
	return _outlined(image)

## The crane boss's claw, 28 x 22.
func _claw(open: bool) -> Image:
	var image := _new(28, 22)
	_box(image, 9, 0, 10, 6, "G")
	_box(image, 9, 0, 10, 1, "g")
	_box(image, 12, 2, 4, 2, "r")
	var spread := 0 if open else 4
	for side in 2:
		var direction := -1 if side == 0 else 1
		var base := 10 if side == 0 else 17
		for step in 8:
			var x := base + direction * (step if step < 5 else 4) + (-direction * spread * step) / 8
			_box(image, x - 1, 6 + step, 3, 1, "G")
			_dot(image, x - direction, 6 + step, "g")
		for step in 7:
			var x := base + direction * (4 - step) + (-direction * spread * (step + 8)) / 15
			_box(image, x - 1, 14 + step, 3, 1, "d" if step > 3 else "G")
		_dot(image, base + direction * -2 + (-direction * spread), 21, "w")
	return _outlined(image)
