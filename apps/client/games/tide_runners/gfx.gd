extends RefCounted

## Every sprite of the game, authored here as pixel art: small sprites are rows of palette characters, large machines are painted with the helpers below. Nothing is loaded from disk. build() runs once, on the first rendered frame, so headless tests never pay for it.

const PAL := {
	"0": "0b1020", "1": "1b2a4a", "2": "2f4f7f", "3": "4f86b8", "4": "8fd0e0", "5": "e8f6f0",
	"6": "123b3a", "7": "1f6f66", "8": "3fb59a", "9": "a5e6b0",
	"a": "3a2430", "b": "7a3340", "c": "c8553d", "d": "f08a4b", "e": "f8c96a", "f": "fff1b0",
	"g": "2a2a36", "h": "4a4d60", "i": "7b8196", "j": "b5bccb",
	"k": "5a3a2a", "l": "8a6240", "m": "d14f8f", "n": "ff9ad0",
}
## Player two wears the gold suit: the teal ramp becomes brown and amber and the visor turns blue.
const SWAP_P2 := {"6": "k", "7": "l", "8": "e", "9": "f", "e": "3", "f": "4"}

const ART := {
	"h_up": [
		"....00000000....",
		"...0899888870...",
		"..089988888870..",
		"..0888000000000.",
		"..08870effffee0.",
		"..08770effeeee0.",
		"..07770eeeeeee0.",
		"..0777000000000.",
		"...067777777760.",
		"..0h0066666600..",
		".0ij078888870...",
		".0hi078888870...",
		".0hh077888770...",
		".0gh0kkkekkk0...",
		"..00067777760...",
	],
	"h_idle": [
		"....06777760....",
		"....06700670....",
		"....0670.0670...",
		"....0670.0670...",
		"....0670.0670...",
		"....0hh0.0hh0...",
		"....0hhh00hhh0..",
		"....0000000000..",
	],
	"h_run0": [
		"....06777760....",
		"...0677006770...",
		"..0677....06770.",
		".0670......0670.",
		".0hh0......0hh0.",
		"0hhh0......0hhh0",
		"0000........0000",
		"................",
	],
	"h_run1": [
		"....06777760....",
		"....0677760.....",
		".....067760.....",
		".....0677060....",
		"....0670.0hh0...",
		"....0hh0.0000...",
		"....0hhh0.......",
		"....00000.......",
	],
	"h_run2": [
		"....06777760....",
		"....06700670....",
		"...0670..0670...",
		"..0670....0670..",
		"..0hh0....0hh0..",
		".0hhh0....0hhh0.",
		".00000....00000.",
		"................",
	],
	"h_jump": [
		"....06777760....",
		"...0677.06770...",
		"..0670...0670...",
		"..0hh0...0hh0...",
		"..0hhh0..0hhh0..",
		"..00000..00000..",
		"................",
		"................",
	],
	"h_prone": [
		"..............0000000...",
		".............089988870..",
		"....000000000088000000..",
		".00006778888708870effe0.",
		"0hhh067788888708870eee0.",
		"0hh0067777777700777000..",
		".000.000000000000000....",
	],
	"h_hurt": [
		".00..........00.",
		"0770..0000..0770",
		"0770008888000770",
		".077088998880770",
		"..0770effe07700.",
		"...070effe0700..",
		"...07700007700..",
		"....07888870....",
		"....07888870....",
		"....0kkekkk0....",
		"...0677006770...",
		"..0670....0670..",
		".0hh0......0hh0.",
		".000........000.",
	],
	"gun_f": [
		".0000000000.",
		"07hiijjjii00",
		"07hhiiiihe50",
		"0700h000000.",
		"...0h0......",
		"...000......",
	],
	"gun_d": [
		"......000.",
		".....05e0.",
		"....0ij0..",
		"...0ij0...",
		"..0ii00...",
		".0hi0h0...",
		"07h0000...",
		"070.......",
		"00........",
	],
	"gun_u": [
		".000..",
		".050..",
		".0e0..",
		".0j0..",
		".0j0..",
		".0i0..",
		".0i00.",
		".0hh0.",
		".0h00.",
		".070..",
		".070..",
		".00...",
	],
	"scut0": [
		"....00000000....",
		"..00bccddccb00..",
		".0bccddddddccb0.",
		"0bcc00ffff00ccb0",
		"0bccc0feef0cccb0",
		".0bbccccccccbb0.",
		"..00bbbbbbbb00..",
		".0h0.0h00h0.0h0.",
		"0h0..0h00h0..0h0",
		"00...00..00...00",
	],
	"scut1": [
		"....00000000....",
		"..00bccddccb00..",
		".0bccddddddccb0.",
		"0bcc00ffff00ccb0",
		"0bccc0feef0cccb0",
		".0bbccccccccbb0.",
		"..00bbbbbbbb00..",
		"..0h00h..h00h0..",
		"..0h0.0hh0.0h0..",
		"..00..0000..00..",
	],
	"drone0": [
		".jjjjjj..jjjjjj.",
		"......0000......",
		"....00hiih00....",
		"...0hiijjiih0...",
		"..0hi0dddd0ih0..",
		"..0hi0dffd0ih0..",
		"...0hiiiiiih0...",
		"....00hhhh00....",
		"......0cc0......",
		".......dd.......",
	],
	"drone1": [
		"...jjj....jjj...",
		"......0000......",
		"....00hiih00....",
		"...0hiijjiih0...",
		"..0hi0dddd0ih0..",
		"..0hi0dffd0ih0..",
		"...0hiiiiiih0...",
		"....00hhhh00....",
		"......0dd0......",
		"......e..e......",
	],
	"troop0": [
		"....000000......",
		"...0cddddc0.....",
		"..0cd0ffff00....",
		"..0cdd0ee0c0....",
		"...0bccccb0.....",
		"....0hhhh0......",
		"..00bccccb0000..",
		".0b0cddddc0iij0.",
		".0b0cddddc0hh00.",
		".0h0bccccb000...",
		"..0.0bbbb0......",
		"....0h00h0......",
		"...0h0..0h0.....",
		"...0h0..0h0.....",
		"..0hh0..0hh0....",
		"..0000..0000....",
	],
	"troop1": [
		"....000000......",
		"...0cddddc0.....",
		"..0cd0ffff00....",
		"..0cdd0ee0c0....",
		"...0bccccb0.....",
		"....0hhhh0......",
		"..00bccccb0000..",
		".0b0cddddc0iij0.",
		".0b0cddddc0hh00.",
		".0h0bccccb000...",
		"..0.0bbbb0......",
		"....0h00h0......",
		"....0h00h0......",
		"...0h0.0h0......",
		"...0hh00hh0.....",
		"...0000000......",
	],
	"pike0": [
		"....000000......",
		"..00iijjji00..00",
		".0iijjjjjjii00i0",
		"0if0jjjiiiihhii0",
		"0iiijjiiihh00hi0",
		".0hhiiihh00..00.",
		"..00hhh00.......",
		"....000.........",
	],
	"toad0": [
		".......0000.......",
		"......0hiih0......",
		"......0hiih0......",
		"...000hiiih000....",
		"..0bccccccccccb0..",
		".0bcc0ff0ccddccb0.",
		".0bcc0fe0cccdccb0.",
		".0bbccccccccccbb0.",
		"..0bbbbbbbbbbbb0..",
		".0hh00......00hh0.",
		"0hhh0........0hhh0",
		"00000........00000",
	],
	"toad1": [
		"..................",
		".......0000.......",
		"......0hiih0......",
		"...000hiiih000....",
		"..0bccccccccccb0..",
		".0bcc0ff0ccddccb0.",
		".0bcc0fe0cccdccb0.",
		".0bbccccccccccbb0.",
		"..0bbbbbbbbbbbb0..",
		"0hhh00......00hhh0",
		"0hhh0........0hhh0",
		"00000........00000",
	],
	"cling0": [
		"..0..0000..0..",
		".0i00hiih00i0.",
		".0h0hiijjih0h.",
		"..0hi0dd0ih0..",
		"..0hi0fd0ih0..",
		".0h0hiiiih0h0.",
		".0i00hhhh00i0.",
		"..0..0000..0..",
	],
	"cling1": [
		"0....0000....0",
		"0i000hiih000i0",
		".0h0hiijjih0h.",
		"..0hi0dd0ih0..",
		"..0hi0fd0ih0..",
		".0h0hiiiih0h0.",
		"0i000hhhh000i0",
		"0....0000....0",
	],
	"carrier0": [
		"jjjjjjj........jjjjjjj",
		"...0..............0...",
		"..000...000000...000..",
		"..0i0000899998000i0...",
		"..0i08889999998880i0..",
		"...008899ffff998800...",
		".....0889f55f9880.....",
		".....08889ff98880.....",
		"......0088888800......",
		".......0hh00hh0.......",
		".......0h0..0h0.......",
	],
	"carrier1": [
		"..jjjjj..........jjj..",
		"...0..............0...",
		"..000...000000...000..",
		"..0i0000899998000i0...",
		"..0i08889999998880i0..",
		"...008899ffff998800...",
		".....0889f55f9880.....",
		".....08889ff98880.....",
		"......0088888800......",
		".......0hh00hh0.......",
		".......0h0..0h0.......",
	],
	"can": [
		"...000000...",
		"..0jjjjjj0..",
		".0j555555j0.",
		"0ii000000ii0",
		"0i0......0i0",
		"0i0......0i0",
		"0i0......0i0",
		"0i0......0i0",
		"0i0......0i0",
		"0hh000000hh0",
		".0hiiiiiih0.",
		"..00000000..",
	],
	"ico1": ["4....4", ".4..4.", "..44..", "444444", "..44..", ".4..4."],
	"ico2": [".44...", "4..4..", "4..4.4", "...4.4", "...44.", "......"],
	"ico3": [".dddd.", "dd55dd", "d5dd5d", "d5dd5d", "dd55dd", ".dddd."],
	"ico4": ["......", "5.....", "555555", "555555", "5.....", "......"],
	"ico5": ["..ee..", ".effe.", "eff5fe", "ef5ffe", ".effe.", "..ee.."],
	"ico6": [".9999.", "9....9", "9.99.9", "9.99.9", "9....9", ".9999."],
	"b_rivet": [".0000.", "0f55f0", "0f55f0", ".0000."],
	"b_fork": [".000.", "09590", "05550", "09590", ".000."],
	"b_arc": ["..00..", ".0440.", "045540", "045540", ".0440.", "..00.."],
	"b_limpet": [".0000.", "0hiih0", "0id5i0", "0i5di0", "0hiih0", ".0000."],
	"b_lance": ["..0000000000..", "00444555555500", "04455555555550", "00444555555500", "..0000000000.."],
	"b_disc": ["..0000..", ".0effe0.", "0ef55fe0", "0ef55fe0", ".0effe0.", "..0000.."],
	"e_orb": ["..0000..", ".0mnnm0.", "0mn55nm0", "0mn55nm0", ".0mnnm0.", "..0000.."],
	"e_bomb": ["..000...", ".0bcb0..", "0bcdcb0.", "0bcfcb0.", ".0bcb0..", "..000..."],
	"e_spike": ["...00...", "..0nn0..", ".0mn5m0.", "0mn55nm0", ".0mn5m0.", "..0nn0..", "...00..."],
	"debris": ["..0000..", ".0hiih0.", "0hiijih0", "0hhiiih0", "0ghhihh0", ".0gghh0.", "..0000.."],
	"spark": ["..5..", ".5f5.", "5fff5", ".5f5.", "..5.."],
}

var tex: Dictionary = {}
var dims: Dictionary = {}
var _white: Dictionary = {}
var _images: Dictionary = {}
var built := false

static func col(key: String) -> Color:
	return Color(String(PAL[key]))

func build() -> void:
	if built:
		return
	built = true
	for key: String in ART:
		_store(key, _from_rows(ART[key], {}))
		if key.begins_with("h_") or key.begins_with("gun_"):
			_store("q" + key, _from_rows(ART[key], SWAP_P2))
	for key in ["gun_f", "gun_d", "gun_u"]:
		for prefix: String in ["", "q"]:
			var flipped: Image = (_images[prefix + key] as Image).duplicate()
			flipped.flip_y()
			_store(prefix + key + "_v", flipped)
	_paint_turret()
	_paint_crate()
	_paint_boss_maw()
	_paint_boss_hydra()
	_paint_boss_gantry()
	_paint_misc()

## The all-white silhouette of a sprite, for hit flashes. Made the first time it is asked for.
func white(key: String) -> Texture2D:
	if not _white.has(key):
		var image: Image = (_images[key] as Image).duplicate()
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.0:
					image.set_pixel(x, y, Color.WHITE)
		_white[key] = ImageTexture.create_from_image(image)
	return _white[key]

func image(key: String) -> Image:
	return _images[key]

func _store(key: String, image: Image) -> void:
	_images[key] = image
	tex[key] = ImageTexture.create_from_image(image)
	dims[key] = Vector2(image.get_width(), image.get_height())

func _from_rows(rows: Array, swap: Dictionary) -> Image:
	var width := 0
	for row: String in rows:
		width = maxi(width, row.length())
	var image := Image.create(width, rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := row[x]
			if key == ".":
				continue
			image.set_pixel(x, y, col(swap.get(key, key)))
	return image

# ---- painter ----

func _canvas(width: int, height: int) -> Image:
	return Image.create(width, height, false, Image.FORMAT_RGBA8)

func _rect(image: Image, x: int, y: int, w: int, h: int, key: String) -> void:
	var area := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if area.size.x > 0 and area.size.y > 0:
		image.fill_rect(area, col(key))

func _px(image: Image, x: int, y: int, key: String) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, col(key))

## A bevelled plate: lit on the top and left, shaded on the bottom and right.
func _plate(image: Image, x: int, y: int, w: int, h: int, light: String, mid: String, dark: String) -> void:
	_rect(image, x, y, w, h, mid)
	_rect(image, x, y, w, 1, light)
	_rect(image, x, y, 1, h, light)
	_rect(image, x, y + h - 1, w, 1, dark)
	_rect(image, x + w - 1, y, 1, h, dark)

## A shaded ball: three tones offset towards the top left.
func _ball(image: Image, cx: int, cy: int, radius: int, light: String, mid: String, dark: String) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var distance := x * x + y * y
			if distance > radius * radius:
				continue
			var lit := (x + radius * 0.35) * (x + radius * 0.35) + (y + radius * 0.35) * (y + radius * 0.35)
			var key := dark
			if lit < radius * radius * 0.3:
				key = light
			elif lit < radius * radius * 0.95:
				key = mid
			_px(image, cx + x, cy + y, key)

func _line(image: Image, x0: int, y0: int, x1: int, y1: int, key: String) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for index in steps + 1:
		var t := float(index) / float(maxi(1, steps))
		_px(image, roundi(lerpf(x0, x1, t)), roundi(lerpf(y0, y1, t)), key)

func _rivets(image: Image, x: int, y: int, w: int, h: int, step: int, key: String) -> void:
	for px in range(x, x + w, step):
		_px(image, px, y, key)
		_px(image, px, y + h - 1, key)
	for py in range(y, y + h, step):
		_px(image, x, py, key)
		_px(image, x + w - 1, py, key)

## Diagonal warning stripes in two tones.
func _hazard(image: Image, x: int, y: int, w: int, h: int, first: String, second: String) -> void:
	for py in h:
		for px in w:
			_px(image, x + px, y + py, first if ((px + py) / 3) % 2 == 0 else second)

## Give every opaque shape a one pixel dark outline.
func _outline(image: Image, key: String) -> void:
	var source: Image = image.duplicate()
	var tint := col(key)
	for y in image.get_height():
		for x in image.get_width():
			if source.get_pixel(x, y).a > 0.0:
				continue
			var touches := false
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + offset.x
				var ny := y + offset.y
				if nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and source.get_pixel(nx, ny).a > 0.0:
					touches = true
					break
			if touches:
				image.set_pixel(x, y, tint)

func _stamp(image: Image, x: int, y: int, rows: Array) -> void:
	for row_index in rows.size():
		var row: String = rows[row_index]
		for column in row.length():
			if row[column] != ".":
				_px(image, x + column, y + row_index, row[column])

# ---- painted sprites ----

func _paint_turret() -> void:
	var base := _canvas(22, 16)
	_plate(base, 2, 9, 18, 6, "i", "h", "g")
	_rivets(base, 3, 10, 16, 4, 5, "j")
	_ball(base, 11, 9, 7, "d", "c", "b")
	_rect(base, 0, 9, 22, 7, "h")
	_plate(base, 1, 10, 20, 5, "i", "h", "g")
	_hazard(base, 3, 12, 16, 2, "e", "g")
	_ball(base, 11, 7, 3, "f", "e", "d")
	_outline(base, "0")
	_store("turret", base)
	var barrel := _canvas(14, 6)
	_plate(barrel, 1, 1, 12, 4, "j", "i", "h")
	_rect(barrel, 10, 1, 3, 4, "g")
	_rect(barrel, 12, 2, 1, 2, "d")
	_outline(barrel, "0")
	_store("turret_barrel", barrel)

func _paint_crate() -> void:
	var crate := _canvas(18, 16)
	_plate(crate, 1, 1, 16, 14, "9", "8", "7")
	_plate(crate, 3, 3, 12, 10, "7", "6", "7")
	_hazard(crate, 4, 6, 10, 4, "e", "6")
	_rivets(crate, 2, 2, 14, 12, 4, "5")
	_outline(crate, "0")
	_store("crate", crate)

## Stage one's boss: a dredging machine that fills the right edge of its arena.
func _paint_boss_maw() -> void:
	var body := _canvas(120, 212)
	_rect(body, 14, 0, 106, 212, "g")
	for row in range(0, 212, 26):
		_plate(body, 16, row + 1, 104, 24, "h", "g", "0")
		_rivets(body, 18, row + 3, 100, 20, 9, "i")
	# The spine of pipes running down the hull.
	_plate(body, 86, 0, 12, 212, "i", "h", "g")
	_plate(body, 102, 0, 8, 212, "8", "7", "6")
	for row in range(6, 212, 18):
		_rect(body, 85, row, 14, 3, "j")
		_rect(body, 101, row + 6, 10, 2, "9")
	# Jaw housing at the bottom and the cannon mount at the top.
	_plate(body, 0, 150, 60, 62, "c", "b", "a")
	_hazard(body, 2, 152, 56, 6, "e", "g")
	_rivets(body, 3, 160, 54, 50, 8, "d")
	_plate(body, 4, 30, 44, 40, "c", "b", "a")
	_hazard(body, 6, 64, 40, 4, "e", "g")
	# The core socket.
	_plate(body, 8, 84, 56, 52, "i", "h", "g")
	_ball(body, 36, 110, 22, "h", "g", "0")
	_rivets(body, 10, 86, 52, 48, 7, "j")
	_outline(body, "0")
	_store("maw_body", body)

	var cannon := _canvas(40, 26)
	_ball(cannon, 26, 13, 11, "d", "c", "b")
	_plate(cannon, 2, 8, 24, 10, "j", "i", "h")
	_rect(cannon, 2, 8, 4, 10, "g")
	_rect(cannon, 3, 11, 2, 4, "d")
	_ball(cannon, 27, 12, 4, "f", "e", "d")
	_outline(cannon, "0")
	_store("maw_cannon", cannon)

	var hatch := _canvas(34, 34)
	_plate(hatch, 1, 1, 32, 32, "d", "c", "b")
	_rect(hatch, 5, 6, 24, 24, "0")
	for tooth in 4:
		_rect(hatch, 6 + tooth * 6, 6, 4, 5, "j")
		_rect(hatch, 6 + tooth * 6, 25, 4, 5, "j")
	_ball(hatch, 17, 18, 5, "f", "d", "c")
	_rivets(hatch, 2, 2, 30, 30, 7, "f")
	_outline(hatch, "0")
	_store("maw_hatch", hatch)

	var core := _canvas(40, 40)
	_ball(core, 20, 20, 18, "j", "i", "h")
	_ball(core, 20, 20, 13, "n", "m", "b")
	_ball(core, 20, 20, 6, "5", "f", "e")
	_outline(core, "0")
	_store("maw_core", core)
	var shut := _canvas(40, 40)
	_ball(shut, 20, 20, 18, "j", "i", "h")
	for blade in 6:
		_rect(shut, 5, 6 + blade * 5, 30, 4, "h" if blade % 2 == 0 else "g")
		_rect(shut, 5, 6 + blade * 5, 30, 1, "j")
	_outline(shut, "0")
	_store("maw_shut", shut)

## Stage two's boss: three valve heads on pipe necks under a pressure tank.
func _paint_boss_hydra() -> void:
	var tank := _canvas(220, 46)
	_plate(tank, 0, 0, 220, 18, "i", "h", "g")
	_rivets(tank, 2, 2, 216, 14, 10, "j")
	_hazard(tank, 0, 16, 220, 4, "e", "g")
	for mount in 3:
		_plate(tank, 26 + mount * 74, 20, 20, 12, "8", "7", "6")
		_rect(tank, 30 + mount * 74, 32, 12, 4, "6")
	_plate(tank, 78, 18, 64, 26, "h", "g", "0")
	_outline(tank, "0")
	_store("hydra_tank", tank)

	var head := _canvas(34, 30)
	_ball(head, 16, 13, 12, "9", "8", "7")
	_plate(head, 6, 18, 22, 8, "8", "7", "6")
	_rect(head, 8, 22, 18, 3, "0")
	for tooth in 4:
		_rect(head, 9 + tooth * 4, 22, 2, 2, "5")
	_ball(head, 10, 11, 3, "5", "f", "d")
	_ball(head, 22, 11, 3, "5", "f", "d")
	_px(head, 10, 11, "0")
	_px(head, 22, 11, "0")
	_rect(head, 12, 1, 8, 3, "e")
	_outline(head, "0")
	_store("hydra_head", head)
	var jaw := _canvas(34, 30)
	_ball(jaw, 16, 11, 12, "9", "8", "7")
	_plate(jaw, 6, 22, 22, 6, "8", "7", "6")
	_rect(jaw, 8, 17, 18, 6, "0")
	_ball(jaw, 17, 20, 3, "5", "n", "m")
	_ball(jaw, 10, 9, 3, "5", "f", "c")
	_ball(jaw, 22, 9, 3, "5", "f", "c")
	_rect(jaw, 12, 0, 8, 2, "e")
	_outline(jaw, "0")
	_store("hydra_jaw", jaw)

	var link := _canvas(12, 12)
	_ball(link, 5, 5, 5, "9", "7", "6")
	_rect(link, 3, 5, 5, 1, "6")
	_outline(link, "0")
	_store("hydra_link", link)

	var heart := _canvas(44, 34)
	_plate(heart, 1, 1, 42, 32, "j", "i", "h")
	_ball(heart, 22, 17, 13, "n", "m", "b")
	_ball(heart, 22, 17, 6, "5", "f", "e")
	_rivets(heart, 3, 3, 38, 28, 7, "5")
	_outline(heart, "0")
	_store("hydra_heart", heart)
	var plate := _canvas(44, 34)
	_plate(plate, 1, 1, 42, 32, "j", "i", "h")
	_plate(plate, 6, 6, 32, 22, "i", "h", "g")
	_hazard(plate, 8, 14, 28, 6, "e", "g")
	_rivets(plate, 3, 3, 38, 28, 7, "5")
	_outline(plate, "0")
	_store("hydra_plate", plate)

## Stage three's boss: a gantry carriage that rides a rail across the top of the dock.
func _paint_boss_gantry() -> void:
	var body := _canvas(132, 44)
	_plate(body, 6, 6, 120, 26, "d", "c", "b")
	_plate(body, 0, 0, 132, 8, "j", "i", "h")
	for wheel in 5:
		_ball(body, 12 + wheel * 27, 4, 3, "j", "h", "g")
	_hazard(body, 8, 28, 116, 4, "e", "g")
	_rivets(body, 8, 8, 116, 20, 9, "f")
	_plate(body, 14, 12, 26, 14, "i", "h", "g")
	_plate(body, 92, 12, 26, 14, "i", "h", "g")
	_plate(body, 48, 30, 36, 14, "h", "g", "0")
	_outline(body, "0")
	_store("gantry_body", body)

	var turret := _canvas(26, 22)
	_ball(turret, 13, 9, 9, "j", "i", "h")
	_plate(turret, 9, 12, 8, 9, "i", "h", "g")
	_ball(turret, 13, 9, 4, "f", "d", "c")
	_rect(turret, 11, 19, 4, 2, "d")
	_outline(turret, "0")
	_store("gantry_turret", turret)

	var claw := _canvas(40, 34)
	_plate(claw, 12, 0, 16, 12, "i", "h", "g")
	_ball(claw, 20, 13, 7, "d", "c", "b")
	for side in 2:
		var flip := -1 if side == 0 else 1
		for step in 16:
			var x := 20 + flip * (6 + step if step < 8 else 14 - (step - 8))
			_rect(claw, x - 2, 14 + step, 5, 2, "i")
			_px(claw, x - 2, 14 + step, "j")
	_ball(claw, 20, 13, 3, "f", "e", "d")
	_outline(claw, "0")
	_store("gantry_claw", claw)

	var eye := _canvas(34, 26)
	_ball(eye, 17, 12, 12, "j", "i", "h")
	_ball(eye, 17, 12, 8, "n", "m", "b")
	_ball(eye, 17, 12, 3, "5", "f", "e")
	_outline(eye, "0")
	_store("gantry_eye", eye)
	var lid := _canvas(34, 26)
	_ball(lid, 17, 12, 12, "j", "i", "h")
	_rect(lid, 6, 10, 22, 5, "g")
	_rect(lid, 6, 10, 22, 1, "j")
	_outline(lid, "0")
	_store("gantry_lid", lid)

func _paint_misc() -> void:
	# The weapon canister with each icon set into its window.
	for kind in range(1, 7):
		var can: Image = (_images["can"] as Image).duplicate()
		_rect(can, 3, 4, 6, 5, "1")
		_stamp(can, 3, 4, (ART["ico%d" % kind] as Array).slice(0, 5))
		_store("can%d" % kind, can)
	var ring := _canvas(26, 30)
	for angle_step in 48:
		var angle := TAU * angle_step / 48.0
		_px(ring, 13 + roundi(cos(angle) * 12.0), 15 + roundi(sin(angle) * 14.0), "4" if angle_step % 3 != 0 else "5")
	_px(ring, 7, 6, "5")
	_px(ring, 8, 5, "5")
	_store("bubble", ring)
	var arrow := _canvas(16, 11)
	_stamp(arrow, 0, 0, ["......00....", "......0f0...", "0000000ff0..", "0ffffffffff0", "0eeeeeeeeee0", "0000000ee0..", "......0e0...", "......00...."])
	_store("arrow", arrow)
