extends RefCounted

## Every picture of Brick Bastion, authored here as pixel art: vehicles, the beacon and the supply chips are rows of palette letters (one letter per pixel), tiles and ground are painted by small rules over the same palette. Nothing is loaded from an image file. build() turns it all into textures once per run; images() gives the raw pictures to the test.
##
## Vehicles are drawn facing up and only their left half is written down: the right half is the mirror image, and the other three headings are rotations. "T" and "U" are the two tread shades, which trade places in the second frame to make the treads roll.

const PALETTE := {
	"k": "15121f", "d": "33364a", "m": "5d6480", "l": "9aa3bd", "w": "f2f4f8",
	"a": "1b4f8a", "b": "4aa8f0", "c": "c8ecff",
	"r": "7a1f2b", "s": "d0403c", "t": "ff8a6a",
	"p": "3a2a66", "q": "7458b8", "u": "baa2f0",
	"h": "3d2226", "e": "8a3f2c", "f": "c0603a", "g": "e89a62",
	"x": "1d3f6e", "y": "2f6fa8", "z": "7ec3e6",
	"n": "143629", "o": "24613f", "v": "4f9c5a",
	"O": "e08a1e", "Y": "ffd24a", "C": "5ef2ff",
	"T": "2a2c3c", "U": "666c86",
}

## Colour changes that turn one drawing into another vehicle's livery.
const LIVERY := {
	"rover1": {"a": "8a5210", "b": "f2a83a", "c": "ffe9a8"},
	"scout": {"r": "7a1f5e", "s": "d646a0", "t": "ff9ad6"},
	"gunner": {"r": "55680f", "s": "b4d02a", "t": "f2ffa0"},
}

const ROVER := [
	"......kk",
	"......kl",
	".kkk..kl",
	".kTk.kkl",
	".kUkkabb",
	".kTkabbc",
	".kUkabck",
	".kTkabkl",
	".kUkabkm",
	".kTkabck",
	".kUkabbc",
	".kTkaabb",
	".kUkkaaa",
	".kTk.kkk",
	".kkk....",
	"........",
]

const GRUNT := [
	".....kkk",
	".kkk.kll",
	".kTk..km",
	".kUk..km",
	".kTkkkkm",
	".kUkrssk",
	".kTkrstt",
	".kUkrskk",
	".kTkrskl",
	".kUkrskm",
	".kTkrskk",
	".kUkrsst",
	".kTkrrss",
	".kUkkrrr",
	".kkk.kkk",
	"........",
]

const SCOUT := [
	".......k",
	"......kt",
	"......kt",
	"..kk.kst",
	".kTTkkss",
	".kUUkrst",
	"..kkkrst",
	"....krsk",
	"....krkl",
	"..kkkrsk",
	".kTTkrss",
	".kUUkrss",
	"..kk.krr",
	".....kkk",
	"........",
	"........",
]

const GUNNER := [
	"....kk..",
	"....klk.",
	".kk.klk.",
	".kTkklkk",
	".kUkrsss",
	".kTkrstt",
	".kUkrskk",
	".kTkrskY",
	".kUkrskY",
	".kTkrskk",
	".kUkrsst",
	".kTkrrss",
	".kUkkrrr",
	".kk..kkk",
	"........",
	"........",
]

const BULWARK := [
	"........",
	"......kk",
	"kkkk..kl",
	"kTTkkkkl",
	"kUUkpppp",
	"kTTkpqqq",
	"kUUkpquu",
	"kTTkpqkk",
	"kUUkpqkl",
	"kTTkpqkm",
	"kUUkpqkk",
	"kTTkpqqu",
	"kUUkppqq",
	"kTTkkppp",
	"kkkk.kkk",
	"........",
]

const CRUSHER := [
	"................",
	"...........kk...",
	"...........klk..",
	"...........klk..",
	".kkkkkkkkkkklkkk",
	"kwlwlwlwlwlklwlw",
	"kllllllllllklmll",
	"kmmmmmmmmmmkmmmm",
	"kkkkkkkkkkkkkkkk",
	".kTTTTk.kdklkddd",
	".kUUUUkkkdkkkddd",
	".kTTTTkrrrrrrrrr",
	".kUUUUkrssssssss",
	".kTTTTkrsttttttt",
	".kUUUUkrstkkkkkk",
	".kTTTTkrstkddddd",
	".kUUUUkrstkdmmmm",
	".kTTTTkrstkdmkkk",
	".kUUUUkrstkdmkOO",
	".kTTTTkrstkdmkOY",
	".kUUUUkrstkdmkOY",
	".kTTTTkrstkdmkOO",
	".kUUUUkrstkdmkkk",
	".kTTTTkrstkdmmmm",
	".kUUUUkrstkddddd",
	".kTTTTkrstkkkkkk",
	".kUUUUkrssssssss",
	".kTTTTkrrrrrrrrr",
	".kUUUUkkkkkkkkkk",
	".kTTTTk.kdddddkk",
	".kkkkkk..kkkkk..",
	"................",
]

const DREADNOUGHT := [
	"...............k",
	"..............kl",
	"........kk....kl",
	"........klk...kl",
	"........klk...kl",
	"...kkkkkklkkkkkl",
	"..kpppppklkppkkl",
	".kpqqqqqkkkqqpkk",
	".kpquuuuuuuuuqpp",
	"kkpqukkkkkkkuqqq",
	"kTkqukddddddkuuu",
	"kUkqukdmmmmmdkkk",
	"kTkqukdmkkkkmdkO",
	"kUkqukdmkOOOkmkO",
	"kTkqukdmkOYYOkOY",
	"kUkqukdmkOYwYOYw",
	"kTkqukdmkOYwYOYw",
	"kUkqukdmkOYYOkOY",
	"kTkqukdmkOOOkmkO",
	"kUkqukdmkkkkmdkO",
	"kTkqukdmmmmmdkkk",
	"kUkqukddddddkuuu",
	"kTkqukkkkkkkuqqq",
	"kUkpquuuuuuuuqpp",
	"kTkpqqqqqqqqqppk",
	"kUkkppppppppppkk",
	"kTk.kkkkkkkkkkk.",
	"kUk..kdddk......",
	"kkk..kkkkk......",
	"................",
	"................",
	"................",
]

## The beacon's top-left quarter; the other three are its mirror images.
const BEACON := [
	"................",
	"......kkkkkkkkkk",
	"....kkdddddddddd",
	"...kddmmmmmmmmmm",
	"..kdmmllllllllll",
	"..kdmllmmmmmmmmm",
	".kdmllmkkkkkkkkk",
	".kdmlmkkOOOOOOOO",
	".kdmlmkOOYYYYYYY",
	".kdmlmkOYYkkkkkk",
	".kdmlmkOYkkxxxxx",
	".kdmlmkOYkxxyyyy",
	".kdmlmkOYkxyyzzz",
	".kdmlmkOYkxyzzCC",
	".kdmlmkOYkxyzCCw",
	".kdmlmkOYkxyzCww",
]

## The badge every supply chip sits on, top-left quarter.
const BADGE := [
	"...kkkkk",
	"..kYYYYY",
	".kYOdddd",
	"kYOdkkkk",
	"kYdkkkkk",
	"kYdkkkkk",
	"kYdkkkkk",
	"kYdkkkkk",
]

## The eight-by-eight sign in the middle of each chip.
const CHIP_SIGNS := {
	"coil": ["....YY..", "...YY...", "..YY....", ".YYYYYY.", "...YY...", "..YY....", ".YY.....", "Y......."],
	"aegis": ["CCCCCCCC", "CwwCCCCz", "CwCCCCzz", "CCCCCCzz", ".CCCCzz.", ".CCCzzz.", "..Czzz..", "...zz..."],
	"stasis": ["...zz...", ".z.zz.z.", "..zzzz..", "zzzwwzzz", "zzzwwzzz", "..zzzz..", ".z.zz.z.", "...zz..."],
	"mason": ["ggg.gggg", "fff.ffff", "........", "ggggg.gg", "fffff.ff", "........", "gg.ggggg", "ff.fffff"],
	"surge": ["..tttt..", ".t....t.", "t..ss..t", "t.swws.t", "t.swws.t", "t..ss..t", ".t....t.", "..tttt.."],
	"spare": ["...cc...", "...cc...", "b.bccb.b", "bbbbbbbb", "b.bccb.b", "bbbccbbb", "b.bbbb.b", "b......b"],
}

const VEHICLES := {"rover0": ROVER, "rover1": ROVER, "grunt": GRUNT, "scout": SCOUT, "gunner": GUNNER, "bulwark": BULWARK, "crusher": CRUSHER, "dreadnought": DREADNOUGHT}

## Ground colours of each sector's setting: base, dark patch, light speck, and what stands in for water (the forge has slag instead).
const THEMES := {
	"moss": {"base": "232d2a", "dark": "1b2422", "light": "33423a", "speck": "4a6b4a", "water": ["1d3f6e", "2f6fa8", "7ec3e6"]},
	"marsh": {"base": "1f2a33", "dark": "17212a", "light": "2b3a47", "speck": "4f7a86", "water": ["1b4a5e", "2f8a94", "8fdccd"]},
	"pass": {"base": "2f2a2b", "dark": "252122", "light": "3d3637", "speck": "6b5a4e", "water": ["1d3f6e", "2f6fa8", "7ec3e6"]},
	"frost": {"base": "39424f", "dark": "2f3743", "light": "4c5869", "speck": "c9d6e6", "water": ["2a4f86", "4f8fd0", "c4ecff"]},
	"dusk": {"base": "2a2234", "dark": "201a29", "light": "382e46", "speck": "6a4f7a", "water": ["2a2f6e", "4a4fa8", "9a9eea"]},
	"forge": {"base": "2b1f20", "dark": "1f1617", "light": "3e2b28", "speck": "8a4a2a", "water": ["7a1f10", "e0561e", "ffc04a"]},
}

## Problems of the authored rows (a row of the wrong length, a letter that is not in the palette), one line each.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for kind: String in VEHICLES:
		var rows: Array = VEHICLES[kind]
		_check_rows(out, kind, rows, rows.size() / 2, rows.size())
	_check_rows(out, "beacon", BEACON, 16, 16)
	_check_rows(out, "badge", BADGE, 8, 8)
	for kind: String in CHIP_SIGNS:
		_check_rows(out, "chip " + kind, CHIP_SIGNS[kind], 8, 8)
	return out

static func _check_rows(out: PackedStringArray, label: String, rows: Array, width: int, height: int) -> void:
	if rows.size() != height:
		out.append("%s: %d rows, wanted %d" % [label, rows.size(), height])
	for index in rows.size():
		var row: String = rows[index]
		if row.length() != width:
			out.append("%s row %d: %d pixels, wanted %d" % [label, index, row.length(), width])
		for position in row.length():
			var letter := row.substr(position, 1)
			if letter != "." and not PALETTE.has(letter):
				out.append("%s row %d: letter %s is not in the palette" % [label, index, letter])

# ---- from rows to images ----

static func _color(letter: String, swap: Dictionary) -> Color:
	if letter == ".":
		return Color(0, 0, 0, 0)
	return Color(str(swap.get(letter, PALETTE.get(letter, "ff00ff"))))

## Paint rows into an image. `mirror` 1 appends the left-right mirror image, 2 mirrors both ways (the rows are a quarter).
static func paint(rows: Array, mirror: int = 0, swap: Dictionary = {}) -> Image:
	var part_w := str(rows[0]).length()
	var part_h := rows.size()
	var width := part_w * (2 if mirror >= 1 else 1)
	var height := part_h * (2 if mirror >= 2 else 1)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in part_h:
		var row: String = rows[y]
		for x in mini(part_w, row.length()):
			var color := _color(row.substr(x, 1), swap)
			image.set_pixel(x, y, color)
			if mirror >= 1:
				image.set_pixel(width - 1 - x, y, color)
			if mirror >= 2:
				image.set_pixel(x, height - 1 - y, color)
				image.set_pixel(width - 1 - x, height - 1 - y, color)
	return image

static func _turned(image: Image, quarter_turns: int) -> Image:
	var out: Image = image.duplicate()
	for turn in quarter_turns:
		out.rotate_90(CLOCKWISE)
	return out

## The same picture with every opaque pixel in one colour, for hit flashes.
static func _silhouette(image: Image, color: Color) -> Image:
	var out: Image = image.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).a > 0.0:
				out.set_pixel(x, y, color)
	return out

static func _hash(x: int, y: int, salt: int) -> int:
	var value := (x * 374761393 + y * 668265263 + salt * 1274126177) & 0x7FFFFFFF
	value = ((value ^ (value >> 13)) * 1103515245) & 0x7FFFFFFF
	return value ^ (value >> 16)

# ---- tiles ----

static func _brick(cracked: bool) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var course := y / 4
			var along := (x + (4 if course % 2 == 1 else 0)) % 8
			var letter := "f"
			if y % 4 == 3 or along == 7:
				letter = "h"
			elif y % 4 == 0:
				letter = "g"
			elif y % 4 == 2 or along == 6:
				letter = "e"
			if _hash(x / 2, course, 5) % 5 == 0 and letter == "f":
				letter = "e"
			image.set_pixel(x, y, _color(letter, {}))
	if cracked:
		# A crack runs corner to corner, the brick is darker and two corners are gone.
		for y in 16:
			for x in 16:
				var color := image.get_pixel(x, y).darkened(0.22)
				var on_crack: bool = absi(x - (3 + y * 5 / 8 + (1 if y % 3 == 0 else 0))) <= 0 or (y in [6, 7] and x in [9, 10, 11]) or (y in [10, 11] and x in [4, 5])
				if on_crack:
					color = _color("k", {})
				if (x + y < 4) or (x - y > 11) or (y - x > 12 and y > 13):
					color = Color(0, 0, 0, 0)
				image.set_pixel(x, y, color)
	return image

static func _plate(fort: bool) -> Image:
	var swap := {"l": "ffe08a", "m": "c9922e", "d": "7a5416"} if fort else {}
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var letter := "m"
			if x == 0 or y == 0:
				letter = "l"
			if x == 15 or y == 15:
				letter = "d"
			if x >= 4 and x <= 11 and y >= 4 and y <= 11:
				letter = "l" if (x == 4 or y == 4) else ("d" if (x == 11 or y == 11) else "m")
				if x - y == 0 and x > 4 and x < 11:
					letter = "l"
			if (x in [2, 13]) and (y in [2, 13]):
				letter = "k"
			if (x in [1, 12]) and (y in [1, 12]):
				letter = "w"
			image.set_pixel(x, y, _color(letter, swap))
	return image

static func _water(frame: int, colors: Array) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var color := Color(str(colors[0]))
			var band := (x + frame * 3 + (y / 4) * 5) % 8
			if y % 4 == 1 and band < 4:
				color = Color(str(colors[1]))
			if y % 4 == 2 and band >= 1 and band < 3:
				color = Color(str(colors[1])).darkened(0.25)
			if y % 8 == 1 and band == 1:
				color = Color(str(colors[2]))
			image.set_pixel(x, y, color)
	return image

static func _thicket() -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var clumps := [Vector2i(4, 4), Vector2i(11, 3), Vector2i(8, 8), Vector2i(3, 11), Vector2i(12, 12)]
	for y in 16:
		for x in 16:
			var letter := "n"
			for clump: Vector2i in clumps:
				var dx: int = x - clump.x
				var dy: int = y - clump.y
				if dx * dx + dy * dy <= 16:
					letter = "v" if dx + dy <= -3 else ("n" if dx + dy >= 4 else "o")
			if _hash(x, y, 9) % 11 == 0 and letter == "o":
				letter = "v"
			# A few gaps at the rim let the ground show through, so a thicket reads as leaves and not as a block.
			var rim: bool = x == 0 or y == 0 or x == 15 or y == 15
			image.set_pixel(x, y, Color(0, 0, 0, 0) if (rim and _hash(x, y, 3) % 3 == 0) else _color(letter, {}))
	return image

## The ground of the whole field in one picture, so it never repeats cell by cell.
static func ground(theme: String, width: int, height: int) -> Image:
	var colors: Dictionary = THEMES[theme]
	var base := Color(str(colors["base"]))
	var dark := Color(str(colors["dark"]))
	var light := Color(str(colors["light"]))
	var speck := Color(str(colors["speck"]))
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var color := base
			# Broad patches from a coarse lattice, then fine grain on top.
			var patch := _hash(x / 12 + (y / 24) % 2, y / 12, 21) % 7
			if patch == 0:
				color = dark
			elif patch == 1 and (x + y) % 2 == 0:
				color = light
			var grain := _hash(x, y, 33) % 97
			if grain < 4:
				color = dark
			elif grain < 7:
				color = light
			elif grain == 7 and _hash(x / 3, y / 3, 41) % 5 == 0:
				color = speck
			# Faint seams every cell keep the grid readable without drawing one.
			if (x % 16 == 0 or y % 16 == 0) and (x + y) % 4 == 0:
				color = color.darkened(0.18)
			image.set_pixel(x, y, color)
	return image

# ---- everything, as images ----

## Every picture by name. Vehicles: "<kind>_<heading>_<frame>" with frame 0 or 1, and "<kind>_<heading>_w" for the white flash.
static func images(theme: String) -> Dictionary:
	var out := {}
	for kind: String in VEHICLES:
		var rows: Array = VEHICLES[kind]
		var swap: Dictionary = LIVERY.get(kind, {})
		var still := paint(rows, 1, swap)
		var rolled_swap := swap.duplicate()
		rolled_swap["T"] = PALETTE["U"]
		rolled_swap["U"] = PALETTE["T"]
		var rolled := paint(rows, 1, rolled_swap)
		var white := _silhouette(still, Color("f2f4f8"))
		for heading in 4:
			out["%s_%d_0" % [kind, heading]] = _turned(still, heading)
			out["%s_%d_1" % [kind, heading]] = _turned(rolled, heading)
			out["%s_%d_w" % [kind, heading]] = _turned(white, heading)
	out["brick"] = _brick(false)
	out["cracked"] = _brick(true)
	out["plate"] = _plate(false)
	out["fort"] = _plate(true)
	var water: Array = THEMES[theme]["water"]
	out["water0"] = _water(0, water)
	out["water1"] = _water(1, water)
	out["water2"] = _water(2, water)
	out["thicket"] = _thicket()
	out["beacon0"] = paint(BEACON, 2)
	out["beacon1"] = paint(BEACON, 2, {"x": PALETTE["y"], "y": PALETTE["z"], "z": PALETTE["C"], "C": PALETTE["w"]})
	out["beacon_hurt"] = paint(BEACON, 2, {"x": "5a1420", "y": "a02a2a", "z": "e0604a", "C": "ffb08a", "w": "ffe0c0", "Y": "c08a3a", "O": "8a5416"})
	out["beacon_dead"] = paint(BEACON, 2, {"x": "15121f", "y": "1d1a28", "z": "262433", "C": "33364a", "w": "33364a", "Y": "4a3d2a", "O": "33291f", "l": "5d6480", "m": "3d4055", "d": "262433"})
	for kind: String in CHIP_SIGNS:
		var chip := paint(BADGE, 2)
		var sign_image := paint(CHIP_SIGNS[kind])
		chip.blend_rect(sign_image, Rect2i(0, 0, 8, 8), Vector2i(4, 4))
		out["chip_" + kind] = chip
	return out

## The same as textures, ready to draw.
static func build(theme: String) -> Dictionary:
	var out := {}
	var pictures := images(theme)
	for name: String in pictures:
		out[name] = ImageTexture.create_from_image(pictures[name])
	return out
