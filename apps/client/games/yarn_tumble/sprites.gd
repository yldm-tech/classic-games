extends RefCounted

## All character, creature, item and effect art of Yarn Tumble, written for this game as rows of palette characters (and, for the yarn itself and the two guardians, drawn by the code below). build() turns it into textures; nothing here is loaded from a file.

const Raster := preload("res://games/yarn_tumble/raster.gd")

const PALETTE := {
	"k": Color("1b1420"), "w": Color("f6f0e4"), "c": Color("e8d5b0"), "C": Color("b89a78"),
	"s": Color("f2b98a"), "S": Color("c98562"),
	"b": Color("4f8fe8"), "B": Color("2d4fa3"), "l": Color("9cd0ff"),
	"o": Color("f08a3c"), "O": Color("b3521f"), "y": Color("ffd75a"), "Y": Color("c9962c"),
	"r": Color("e0455a"), "R": Color("9c2440"), "p": Color("ff9ec4"), "P": Color("c2478f"),
	"g": Color("6cc46a"), "G": Color("2f7d4f"), "v": Color("8c6fe0"), "V": Color("4b3a94"),
	"n": Color("9a6a45"), "N": Color("5c3a2a"), "e": Color("9aa3b5"), "E": Color("555d73"),
	"t": Color("3fb8b0"), "T": Color("1f6f78"),
}
## Yarn and clothing colours of the two knitters: main, dark, light, scarf, scarf dark.
const HERO_COLORS := [
	{"1": Color("4f8fe8"), "2": Color("2d4fa3"), "3": Color("9cd0ff"), "4": Color("ffd75a"), "5": Color("c9962c")},
	{"1": Color("f08a3c"), "2": Color("b3521f"), "3": Color("ffd08a"), "4": Color("3fb8b0"), "5": Color("1f6f78")},
]

const HEAD := [
	"......kwwk......",
	".....kwwwwk.....",
	"....kkwwwwkk....",
	"...k11111111k...",
	"..k1311111111k..",
	"..k1111111111k..",
	".k332332332332k.",
	"..kNNsssssssSk..",
	"..ksssskssskSk..",
	"..ksssskssskSk..",
	"..kspsssssspSk..",
	"...kssssssSSk...",
]
const HEAD_BLINK := {8: "..ksssssssssSk..", 9: "..kssskksskkSk.."}
const HEAD_HURT := {8: "..ksssssssssSk..", 9: "..kssskksskkSk..", 10: "..kspsskkspsSk..", 11: "...ksssskksSk..."}
const TORSO_IDLE := ["..k4444444444k..", ".45k21111112k...", "...ks111111sk...", "...k21111112k..."]
const TORSO_SHOOT := ["..k4444444444k..", ".45k21111112k...", "...k21111111ssew", "...k21111112k..."]
const TORSO_UP := [".sk4444444444ks.", ".45k21111112k...", "...k21111112k...", "...k21111112k..."]
const LEGS := {
	"stand": ["....kNNkkNNk....", "...kNNNkkNNNk..."],
	"a": ["...kNNk..kNNk...", "..kNNNk...kNNNk."],
	"pass": [".....kNNNNk.....", ".....kNNNNNk...."],
	"b": ["....kNNk.kNNk...", "...kNNNk..kNNNk."],
	"tuck": ["...kNNNkkNNNk...", "....kkk..kkk...."],
	"fall": ["...kNk....kNk...", "...kNk....kNk..."],
}
## Knitter frames: name -> [head variant, torso, legs].
const HERO_FRAMES := {
	"idle": ["", "idle", "stand"], "blink": ["blink", "idle", "stand"],
	"run0": ["", "idle", "a"], "run1": ["", "idle", "pass"], "run2": ["", "idle", "b"], "run3": ["", "idle", "pass"],
	"jump": ["", "up", "tuck"], "fall": ["", "up", "fall"],
	"shoot": ["", "shoot", "stand"], "shoot_air": ["", "shoot", "tuck"],
	"hurt": ["hurt", "up", "fall"],
}

const MOTH := [[
	"..k..........k..",
	"...k........k...",
	"....kkkkkkkk....",
	"...kcccccccck...",
	"..kcccccccccck..",
	"..kcwkcccwkcck..",
	"nnkcwkcccwkccknn",
	"nNkccccccccccNnk",
	".nkccckkkkccckn.",
	"..kcccwkwkccck..",
	"..kCccccccccCk..",
	"...kCccccccCk...",
	"....kkCCCCkk....",
	"....kNk..kNk....",
	"...kNNk..kNNk...",
	"................",
], [
	"...k........k...",
	"...k........k...",
	"....kkkkkkkk....",
	"nn.kcccccccck.nn",
	"nNkcccccccccckNn",
	".nkcwkcccwkcckn.",
	"..kcwkcccwkcck..",
	"..kcccccccccck..",
	"..kccckkkkccck..",
	"..kcccwkwkccck..",
	"..kCccccccccCk..",
	"...kCccccccCk...",
	"....kkCCCCkk....",
	".....kNkkNk.....",
	"....kNNkkNNk....",
	"................",
]]
const SPRING := [[
	"................",
	"................",
	"................",
	"....kkkkkkkk....",
	"...krrrrrrrrk...",
	"..krpprrrrrrrk..",
	"..krrwkrrwkrrk..",
	"..krrwkrrwkrrk..",
	"..krrrrrrrrrrk..",
	"..kRrrkkkkrrRk..",
	"...kRRrrrrRRk...",
	"....kkkkkkkk....",
	".....eeeeee.....",
	"....EEEEEEEE....",
	".....eeeeee.....",
	"....kkkkkkkk....",
], [
	"....kkkkkkkk....",
	"...krrrrrrrrk...",
	"..krpprrrrrrrk..",
	"..krrwkrrwkrrk..",
	"..krrwkrrwkrrk..",
	"..krrrrrrrrrrk..",
	"..kRrkkkkkkrRk..",
	"...kRRrrrrRRk...",
	"....kkkkkkkk....",
	".....eeeeee.....",
	"......EEEE......",
	".....eeeeee.....",
	"......EEEE......",
	".....eeeeee.....",
	"......EEEE......",
	"....kkkkkkkk....",
]]
const PIN := [[
	"................",
	"...y...p...l....",
	"...e...e...e....",
	"....e..e..e.....",
	"....kkkkkkk.....",
	"...kgggggggkk...",
	"..kgglgggggcckk.",
	".kgggggglggcwkck",
	".kgGgggggggcccck",
	".kggggGggggcckkk",
	".kGgggggggGccck.",
	"..kGGggggGGGkk..",
	"...kkkkkkkkk....",
	"...kNk...kNk....",
	"..kNNk..kNNk....",
	"................",
], [
	"................",
	"...y...p...l....",
	"...e...e...e....",
	"....e..e..e.....",
	"....kkkkkkk.....",
	"...kgggggggkk...",
	"..kgglgggggcckk.",
	".kgggggglggcwkck",
	".kgGgggggggcccck",
	".kggggGggggcckkk",
	".kGgggggggGccck.",
	"..kGGggggGGGkk..",
	"...kkkkkkkkk....",
	"....kNk.kNk.....",
	"...kNNk.kNNk....",
	"................",
]]
const SNIP := [[
	"................",
	".vv..........vv.",
	".vVv........vVv.",
	"..vVvkkkkkkvVv..",
	"...vkrrkkrrkv...",
	"...krwwrrwwrk...",
	"...krwkrrwkrk...",
	"...kkrrkkrrkk...",
	"....kkeeeekk....",
	".....keeeek.....",
	".....kewwek.....",
	"....kewkkwek....",
	"....kwk..kwk....",
	"....kk....kk....",
	"................",
	"................",
], [
	"................",
	"................",
	"................",
	".....kkkkkk.....",
	".vvvkrrkkrrkvvv.",
	"vVvkrwwrrwwrkvVv",
	".v.krwkrrwkrk.v.",
	"...kkrrkkrrkk...",
	"....kkeeeekk....",
	".....keeeek.....",
	".....kewwek.....",
	".....kewwek.....",
	"......kwwk......",
	".......kk.......",
	"................",
	"................",
]]
const INK := [[
	"................",
	"................",
	"................",
	"................",
	".....kkkkkk.....",
	"....kttttttk....",
	"...kttlttttttk..",
	"..kttttwwwtttk..",
	"..ktttwwkkwttk..",
	"..ktttwwkkwttk..",
	"..kttttwwwtttk..",
	".kTttttttttttTk.",
	".kTTttttttttTTk.",
	".kTTTTttttTTTTk.",
	"..kkTkkkkkkTkk..",
	"....T......T....",
], [
	"................",
	"................",
	"................",
	"................",
	"................",
	".....kkkkkk.....",
	"...kkttttttkk...",
	"..kttlttwwwttk..",
	".kttttwwkkwtttk.",
	".kttttwwkkwtttk.",
	".kTttttwwwtttTk.",
	".kTTttttttttTTk.",
	".kTTTTttttTTTTk.",
	"..kkkTkkkkTkkk..",
	".....T....T.....",
	".....T..........",
]]

const ITEMS := {
	"button": [
		"....kkkk....",
		"..kkrrrrkk..",
		".krrpprrrrk.",
		".krprrrrrrk.",
		"krrrkrrkrrrk",
		"krrrrrrrrrrk",
		"krrrrrrrrrRk",
		"krrrkrrkrrRk",
		".krrrrrrRRk.",
		".krrrrrRRRk.",
		"..kkRRRRkk..",
		"....kkkk....",
	],
	"thimble": [
		"............",
		"...kkkkkk...",
		"..keeeeeek..",
		"..kewewewk..",
		"..kwewewek..",
		"..kewewewk..",
		"..keeeeeEk..",
		"..keeeeEEk..",
		".kkkkkkkkkk.",
		".kwweeeeEEk.",
		".kkkkkkkkkk.",
		"............",
	],
	"ribbon": [
		"............",
		".kk......kk.",
		"kppk....kppk",
		"kpppk..kpppk",
		"kppppkkppppk",
		"kpPppkPkppPk",
		"kppppkkppppk",
		"kpppk..kpppk",
		"kPPk.kk.kPPk",
		".kk.kPPk.kk.",
		"....kPPk....",
		"....k..k....",
	],
	"spool": [
		"..kkkkkkkk..",
		".knnnnnnnnk.",
		"..kkkkkkkk..",
		"..kyyywyyk..",
		"..kyywyyYk..",
		"..kywyyyYk..",
		"..kyyywyYk..",
		"..kyywyyYk..",
		"..kyyyyYYk..",
		"..kkkkkkkk..",
		".kNNNNNNNNk.",
		"..kkkkkkkk..",
	],
	"heart": [
		"............",
		"..kk....kk..",
		".krrk..krrk.",
		"krprrkkrrrrk",
		"krprrrrrrrrk",
		"krrrrrwrrrRk",
		"krrrrwrwrrRk",
		".krrrrrrrRk.",
		"..krrrrrRk..",
		"...krrrRk...",
		"....krRk....",
		".....kk.....",
	],
}
## Power-up badges: background, shade and an 8 x 8 white icon.
const BADGES := {
	"long": ["b", "B", [".......w", "......w.", ".....w..", "....w...", "...w....", "..w.....", "ww......", "ww......"]],
	"rapid": ["g", "G", ["w...w...", ".w...w..", "..w...w.", "...w...w", "..w...w.", ".w...w..", "w...w...", "........"]],
	"thick": ["P", "R", ["..wwww..", ".wwwwww.", "wwkwwwww", "wwwkwwww", "wwwwkwww", "wwwwwkww", ".wwwwww.", "..wwww.."]],
	"swift": ["o", "O", ["..www...", "..www...", "..www...", "..www...", "..wwww..", "..wwwwww", "..wwwwww", "........"]],
}
const SHOT := [[
	"..1111..",
	".13..11.",
	"11....11",
	"1......1",
	"1......1",
	"11....12",
	".11..12.",
	"..1122..",
], [
	"........",
	".111111.",
	"113..112",
	"1......2",
	"1......2",
	"11...122",
	".112222.",
	"........",
]]
const HAZARDS := {
	"ink": [
		"..kkkk..",
		".kttttk.",
		"kttlttTk",
		"ktltttTk",
		"kttttTTk",
		"kttttTTk",
		".kTTTTk.",
		"..kkkk..",
	],
	"pin": [
		"......rr",
		".....krr",
		"....ek..",
		"...ew...",
		"..ew....",
		".ew.....",
		"ew......",
		"w.......",
	],
	"wave": [
		"......ww....",
		"....wwyyw...",
		"...wyyyyyw..",
		"..wyyoyyyyw.",
		".wyyooyyoyyw",
		".wyoooyoooyw",
		"wyyooooooyyw",
		"wyoooooooooy",
	],
	"egg": [
		"..kkkk..",
		".kwwcck.",
		"kwwcccck",
		"kwcccvck",
		"kccvcccC",
		"kcccccCk",
		".kccCCk.",
		"..kkkk..",
	],
}
const SPARK := [[
	".......y........",
	"..y....yy....y..",
	"...yy.yyyy.yy...",
	"....yyywwyyy....",
	"...yywwwwwwyy...",
	".yyywkkwwkkwyyy.",
	"yyywwwkwwkwwwyyy",
	".yyywwwwwwwwyyy.",
	"...yywkkkkwyy...",
	"....yyywwyyy....",
	"...yy.yyyy.yy...",
	"..y....yy....y..",
	".......y........",
], [
	"................",
	".y.....y.....y..",
	"..yy..yyyy..yy..",
	"...yyyywwyyyy...",
	"..yyywwwwwwyyy..",
	"..yywkkwwkkwyy..",
	".yywwwkwwkwwwyy.",
	"..yywwwwwwwwyy..",
	"..yyywkkkkwyyy..",
	"...yyyywwyyyy...",
	"..yy..yyyy..yy..",
	".y.....y.....y..",
	"................",
]]
## A 3 x 5 pixel font for scores and the floor sign.
const GLYPHS := {
	"0": ["www", "w.w", "w.w", "w.w", "www"], "1": [".w.", "ww.", ".w.", ".w.", "www"], "2": ["www", "..w", "www", "w..", "www"],
	"3": ["www", "..w", "www", "..w", "www"], "4": ["w.w", "w.w", "www", "..w", "..w"], "5": ["www", "w..", "www", "..w", "www"],
	"6": ["www", "w..", "www", "w.w", "www"], "7": ["www", "..w", "..w", ".w.", ".w."], "8": ["www", "w.w", "www", "w.w", "www"],
	"9": ["www", "w.w", "www", "..w", "www"], "/": ["..w", "..w", ".w.", "w..", "w.."], "x": ["...", "w.w", ".w.", "w.w", "..."],
	"+": ["...", ".w.", "www", ".w.", "..."], "F": ["www", "w..", "ww.", "w..", "w.."],
}

var textures: Dictionary = {}

## Row-length problems in the art above, for the tests: every row of a sprite has to be as wide as its first.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var sets := {"head": HEAD, "torso_idle": TORSO_IDLE, "torso_shoot": TORSO_SHOOT, "torso_up": TORSO_UP, "shot0": SHOT[0], "shot1": SHOT[1], "spark0": SPARK[0], "spark1": SPARK[1]}
	for key: String in LEGS:
		sets["legs_" + key] = LEGS[key]
	for pair: Array in [["moth", MOTH], ["spring", SPRING], ["pin", PIN], ["snip", SNIP], ["ink", INK]]:
		for index in (pair[1] as Array).size():
			sets["%s%d" % [pair[0], index]] = pair[1][index]
	for key: String in ITEMS:
		sets[key] = ITEMS[key]
	for key: String in HAZARDS:
		sets[key] = HAZARDS[key]
	for key: String in BADGES:
		sets["badge_" + key] = BADGES[key][2]
	for key: String in sets:
		var rows: Array = sets[key]
		for row: String in rows:
			if row.length() != str(rows[0]).length():
				out.append("%s: row \"%s\" is %d wide, not %d" % [key, row, row.length(), str(rows[0]).length()])
	for variant: Dictionary in [HEAD_BLINK, HEAD_HURT]:
		for index: int in variant:
			if str(variant[index]).length() != 16:
				out.append("head variant row %d is not 16 wide" % index)
	return out

func get_texture(key: String) -> Texture2D:
	return textures.get(key)

func build() -> void:
	for slot in HERO_COLORS.size():
		var palette := PALETTE.duplicate()
		palette.merge(HERO_COLORS[slot], true)
		for frame: String in HERO_FRAMES:
			var parts: Array = HERO_FRAMES[frame]
			var rows: Array = HEAD.duplicate()
			var changes: Dictionary = HEAD_BLINK if parts[0] == "blink" else (HEAD_HURT if parts[0] == "hurt" else {})
			for index: int in changes:
				rows[index] = changes[index]
			rows.append_array(TORSO_SHOOT if parts[1] == "shoot" else (TORSO_UP if parts[1] == "up" else TORSO_IDLE))
			rows.append_array(LEGS[parts[2]])
			_add("hero%d_%s" % [slot, frame], Raster.from_rows(rows, palette))
		for index in SHOT.size():
			_add("shot%d_%d" % [slot, index], Raster.from_rows(SHOT[index], palette))
		var colors: Dictionary = HERO_COLORS[slot]
		for turn in 4:
			_add("ball%d_%d" % [slot, turn], _ball(colors["1"], colors["2"], colors["3"], turn))
		for level in 4:
			_add("wrap%d_%d" % [slot, level], _wrap(colors["1"], colors["2"], colors["3"], (level + 1) / 5.0))
	for pair: Array in [["moth", MOTH], ["spring", SPRING], ["pin", PIN], ["snip", SNIP], ["ink", INK]]:
		for index in (pair[1] as Array).size():
			_add("%s_%d" % [pair[0], index], Raster.from_rows(pair[1][index], PALETTE))
	for key: String in ITEMS:
		_add(key, Raster.from_rows(ITEMS[key], PALETTE))
	for key: String in BADGES:
		_add(key, _badge(BADGES[key]))
	for key: String in HAZARDS:
		_add(key, Raster.from_rows(HAZARDS[key], PALETTE))
	for index in SPARK.size():
		_add("spark_%d" % index, Raster.from_rows(SPARK[index], PALETTE))
	for key: String in GLYPHS:
		_add("glyph_" + key, Raster.from_rows(GLYPHS[key], PALETTE))
	_add("duchess_body", _duchess_body())
	_add("duchess_wing", _duchess_wing())
	_add("regent_body", _regent_body())
	_add("regent_blade", _regent_blade())

func _add(key: String, image: Image) -> void:
	textures[key] = ImageTexture.create_from_image(image)

## A ball of yarn, 16 x 16, seen after `turn` quarter turns.
func _ball(main: Color, dark: Color, light: Color, turn: int) -> Image:
	var image := Raster.blank(16, 16)
	for py in 16:
		for px in 16:
			var dx := px - 7.5
			var dy := py - 8.5
			var distance := sqrt(dx * dx + dy * dy)
			if distance > 7.0:
				continue
			# Rotate the strand pattern, not the shading: the light stays at the top left while the ball turns.
			var rx := dx
			var ry := dy
			for quarter in turn:
				var held := rx
				rx = -ry
				ry = held
			var color := main
			if posmod(int(floor(rx * 0.9 + ry * 0.55 + 40.0)), 4) == 0:
				color = dark
			elif posmod(int(floor(rx * 0.5 - ry * 0.95 + 40.0)), 5) == 0:
				color = light
			if (dx + 2.5) * (dx + 2.5) + (dy + 3.0) * (dy + 3.0) < 3.5:
				color = light
			elif dx + dy > 6.0:
				color = dark
			if distance > 6.0:
				color = PALETTE["k"]
			image.set_pixel(px, py, color)
	return image

## Yarn wound over a creature from the feet up; `amount` (0 .. 1) is how much of it is covered.
func _wrap(main: Color, dark: Color, light: Color, amount: float) -> Image:
	var image := Raster.blank(16, 16)
	var top := 16.0 - amount * 16.0
	for py in 16:
		for px in 16:
			var dx := (px - 7.5) / 7.6
			var dy := (py - 8.5) / 7.6
			if dx * dx + dy * dy > 1.0 or py < top:
				continue
			var strand := posmod(px + py * 2, 6)
			if strand >= 4 and amount < 0.7:
				continue
			var color := main if strand < 2 else (dark if strand < 4 else light)
			if dx * dx + dy * dy > 0.78:
				color = dark
			image.set_pixel(px, py, color)
	return image

func _badge(spec: Array) -> Image:
	var image := Raster.blank(12, 12)
	Raster.box(image, 1, 1, 10, 10, PALETTE[spec[0]])
	Raster.box(image, 1, 9, 10, 2, PALETTE[spec[1]])
	Raster.box(image, 9, 1, 2, 10, PALETTE[spec[1]])
	Raster.box(image, 1, 0, 10, 1, PALETTE["k"])
	Raster.box(image, 1, 11, 10, 1, PALETTE["k"])
	Raster.box(image, 0, 1, 1, 10, PALETTE["k"])
	Raster.box(image, 11, 1, 1, 10, PALETTE["k"])
	var icon: Array = spec[2]
	for py in icon.size():
		for px in str(icon[py]).length():
			var key := str(icon[py])[px]
			if key != ".":
				image.set_pixel(px + 2, py + 2, PALETTE[key])
	return image

## Duchess Dustwing without her wings: a furred head with lamp eyes, a ruff, a banded abdomen, feathered feelers and a little crown. 48 x 54, feet at the bottom centre.
func _duchess_body() -> Image:
	var image := Raster.blank(48, 54)
	var fur: Color = PALETTE["c"]
	var shade: Color = PALETTE["C"]
	# Dangling legs.
	for side: int in [-1, 1]:
		for leg in 3:
			Raster.line(image, 23.5 + side * 7.0, 30.0 + leg * 5.0, 23.5 + side * (13.0 - leg), 36.0 + leg * 5.0, PALETTE["N"])
	# Abdomen with dusty bands.
	Raster.disc(image, 23.5, 38.0, 9.5, 13.5, fur)
	for band in 5:
		Raster.repaint(image, 12, 31 + band * 5, 24, 2, PALETTE["v"])
		Raster.repaint(image, 12, 33 + band * 5, 24, 1, PALETTE["V"])
	# Head.
	Raster.disc(image, 23.5, 14.5, 12.0, 10.0, fur)
	for py in 54:
		for px in 48:
			if image.get_pixel(px, py) == fur and px * 2 + py > 78:
				image.set_pixel(px, py, shade)
	# Ruff.
	for tuft in 9:
		Raster.disc(image, 9.5 + tuft * 3.5, 25.5 + (tuft % 2) * 1.5, 3.2, 3.4, PALETTE["w"])
		Raster.dot(image, roundi(10.0 + tuft * 3.5), 28 + (tuft % 2), shade)
	# Eyes.
	for eye_x: float in [16.0, 31.0]:
		Raster.disc(image, eye_x, 14.0, 5.2, 5.8, PALETTE["R"])
		Raster.disc(image, eye_x, 14.0, 4.0, 4.6, PALETTE["r"])
		Raster.box(image, int(eye_x), 11, 1, 6, PALETTE["k"])
		Raster.box(image, int(eye_x) - 3, 11, 2, 2, PALETTE["p"])
		Raster.dot(image, int(eye_x) + 2, 17, PALETTE["R"])
	# Mouth with two fangs.
	Raster.box(image, 21, 20, 6, 1, PALETTE["k"])
	Raster.box(image, 21, 21, 1, 2, PALETTE["w"])
	Raster.box(image, 26, 21, 1, 2, PALETTE["w"])
	# Feelers.
	for side: int in [-1, 1]:
		for step in 10:
			var fx := 23.5 + side * (5.0 + step * 1.7)
			var fy := 6.0 - step * 0.9 + (step * step) * 0.07
			Raster.dot(image, roundi(fx), roundi(fy), PALETTE["N"])
			if step % 2 == 1:
				Raster.dot(image, roundi(fx), roundi(fy) - 1, PALETTE["n"])
				Raster.dot(image, roundi(fx), roundi(fy) + 1, PALETTE["n"])
	# Crown.
	Raster.box(image, 19, 3, 10, 3, PALETTE["y"])
	Raster.box(image, 19, 5, 10, 1, PALETTE["Y"])
	for point: int in [19, 21, 24, 26, 28]:
		Raster.box(image, point, 1, 1, 2, PALETTE["y"])
	Raster.dot(image, 24, 4, PALETTE["r"])
	Raster.outline(image, PALETTE["k"])
	return image

## One wing of the Duchess, drawn for her left side with the root at the right edge. 36 x 50.
func _duchess_wing() -> Image:
	var image := Raster.blank(36, 50)
	Raster.disc(image, 18.0, 16.0, 16.5, 15.0, PALETTE["v"])
	Raster.disc(image, 21.0, 36.0, 12.5, 12.0, PALETTE["V"])
	Raster.disc(image, 16.5, 15.0, 12.0, 10.5, PALETTE["P"])
	Raster.disc(image, 15.0, 15.0, 7.0, 7.0, PALETTE["y"])
	Raster.disc(image, 15.0, 15.0, 4.6, 4.6, PALETTE["o"])
	Raster.disc(image, 15.0, 15.0, 2.8, 2.8, PALETTE["k"])
	Raster.box(image, 13, 13, 2, 2, PALETTE["w"])
	Raster.disc(image, 21.0, 37.0, 5.0, 5.0, PALETTE["p"])
	Raster.disc(image, 21.0, 37.0, 2.2, 2.2, PALETTE["V"])
	for py in 50:
		for px in 36:
			if image.get_pixel(px, py).a > 0.0 and Raster.grain(px, py, 5) > 0.88:
				image.set_pixel(px, py, PALETTE["l"])
	for vein in 4:
		Raster.line(image, 35.0, 24.0, 3.0 + vein * 3.0, 4.0 + vein * 12.0, PALETTE["V"])
	Raster.outline(image, PALETTE["k"])
	return image

## The Snipjaw Regent without its blades: a riveted steel head on stubby legs, two finger-ring eyes, a toothed jaw and a screw for a crown. 34 x 36.
func _regent_body() -> Image:
	var image := Raster.blank(34, 36)
	var steel: Color = PALETTE["e"]
	var dark: Color = PALETTE["E"]
	Raster.disc(image, 16.5, 17.0, 14.0, 12.5, steel)
	Raster.box(image, 5, 17, 24, 12, steel)
	for py in 36:
		for px in 34:
			if image.get_pixel(px, py).a > 0.0:
				if px + py > 42:
					image.set_pixel(px, py, dark)
				elif px + py < 20:
					image.set_pixel(px, py, PALETTE["w"])
	# Ring eyes.
	for eye_x: float in [10.5, 22.5]:
		Raster.disc(image, eye_x, 13.5, 5.5, 5.5, PALETTE["R"])
		Raster.disc(image, eye_x, 13.5, 4.5, 4.5, PALETTE["r"])
		Raster.disc(image, eye_x, 13.5, 3.0, 3.0, PALETTE["k"])
		Raster.disc(image, eye_x, 13.5, 1.6, 1.6, PALETTE["y"])
		Raster.dot(image, int(eye_x) - 2, 10, PALETTE["p"])
	# Jaw.
	Raster.box(image, 7, 22, 20, 6, PALETTE["k"])
	for tooth in 5:
		Raster.box(image, 8 + tooth * 4, 22, 2, 2, PALETTE["w"])
		Raster.box(image, 10 + tooth * 4, 26, 2, 2, PALETTE["w"])
	# Rivets.
	for rivet: Vector2i in [Vector2i(4, 19), Vector2i(29, 19), Vector2i(16, 6), Vector2i(6, 28), Vector2i(27, 28)]:
		Raster.dot(image, rivet.x, rivet.y, PALETTE["y"])
		Raster.dot(image, rivet.x + 1, rivet.y + 1, PALETTE["k"])
	# Screw crown.
	Raster.box(image, 13, 1, 8, 3, PALETTE["y"])
	Raster.box(image, 13, 2, 8, 1, PALETTE["Y"])
	Raster.box(image, 15, 4, 4, 2, PALETTE["Y"])
	# Legs.
	Raster.box(image, 8, 29, 6, 6, dark)
	Raster.box(image, 20, 29, 6, 6, dark)
	Raster.box(image, 6, 33, 9, 2, PALETTE["N"])
	Raster.box(image, 19, 33, 9, 2, PALETTE["N"])
	Raster.outline(image, PALETTE["k"])
	return image

## One blade of the Regent, pointing right with its pivot at the left end. 30 x 9.
func _regent_blade() -> Image:
	var image := Raster.blank(30, 9)
	for px in range(1, 29):
		var half := 3.0 * (1.0 - float(px) / 30.0) + 0.6
		for py in range(1, 8):
			if absf(py - 4.0) <= half:
				image.set_pixel(px, py, PALETTE["w"] if py < 4 else (PALETTE["e"] if py == 4 else PALETTE["E"]))
	Raster.disc(image, 3.0, 4.0, 2.0, 2.0, PALETTE["y"])
	Raster.dot(image, 3, 4, PALETTE["k"])
	Raster.outline(image, PALETTE["k"])
	return image
