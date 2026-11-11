extends RefCounted

## Builds every picture the game shows, once per run, from the palette: hand-drawn rows (sprite_data.gd) and pictures painted by code here (tiles, bosses, props, backdrops). Nothing is loaded from a file.

const Pal := preload("res://games/ember_trail/palette.gd")
const Data := preload("res://games/ember_trail/sprite_data.gd")
const Rng := preload("res://games/shared/game_rng.gd")

## Sprites that also get a white copy ("<name>_w") for hit flashes.
const FLASHED := ["hero_idle", "hero_run", "hero_jump", "hero_fall", "hero_throw", "hero_hurt", "hero_ride", "ram", "cinderling", "sootwing", "ventcrab", "rimebeetle", "driftwisp", "shardling", "toad", "owl"]

## name -> Array[ImageTexture], one per frame.
static func build() -> Dictionary:
	var images := build_images()
	var out := {}
	for key: String in images:
		var frames: Array = []
		for image: Image in images[key]:
			frames.append(ImageTexture.create_from_image(image))
		out[key] = frames
	return out

## name -> Array[Image]. Separate from build() so a tool can look at the pictures without a renderer.
static func build_images() -> Dictionary:
	var out := {}
	for key: String in Data.FULL:
		var frames: Array = []
		for rows: Array in Data.FULL[key]:
			frames.append(_from_rows(rows))
		out[key] = frames
	for key: String in Data.HALF:
		var frames: Array = []
		for rows: Array in Data.HALF[key]:
			frames.append(_from_rows(_mirror_rows(rows)))
		out[key] = frames
	_build_hero(out)
	for area in [1, 2]:
		out["t%d_top" % area] = [_tile_ground(area, true, 0), _tile_ground(area, true, 1)]
		out["t%d_fill" % area] = [_tile_ground(area, false, 0), _tile_ground(area, false, 1)]
		out["t%d_plat" % area] = [_tile_platform(area, false)]
		out["t%d_crumble" % area] = [_tile_platform(area, true)]
		out["t%d_spike" % area] = [_tile_spike(area)]
		out["t%d_liquid" % area] = [_tile_liquid(area, 0), _tile_liquid(area, 1)]
		out["t%d_deep" % area] = [_tile_deep(area)]
		out["mover%d" % area] = [_mover(area)]
		out["sky%d" % area] = [_sky(area)]
		out["far%d" % area] = [_far(area)]
		out["near%d" % area] = [_near(area)]
	out["t2_ice"] = [_tile_ice(0), _tile_ice(1)]
	out["lamp"] = [_lamp(false), _lamp(true)]
	out["beacon"] = [_beacon(0), _beacon(1), _beacon(2)]
	out["vent"] = [_vent()]
	out["column"] = [_column(0), _column(1)]
	out["toad"] = [_toad(0), _toad(1), _toad(2), _toad(3)]
	out["owl"] = [_owl(0), _owl(1), _owl(2)]
	out["tree"] = [_tree(0), _tree(1)]
	out["spire"] = [_spire(1), _spire(2)]
	out["tuft"] = [_tuft(1), _tuft(2)]
	out["crystal"] = [_crystal(0), _crystal(1)]
	out["shroom"] = [_shroom()]
	out["glow"] = [_glow(24, "6"), _glow(24, "r")]
	for key: String in FLASHED:
		var white: Array = []
		for image: Image in out[key]:
			white.append(_whitened(image))
		out[key + "_w"] = white
	return out

# ---- rows of text ----

static func _from_rows(rows: Array) -> Image:
	var width := 0
	for row: String in rows:
		width = maxi(width, row.length())
	var image := _new(width, rows.size())
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := row[x]
			if key != ".":
				image.set_pixel(x, y, Pal.of(key))
	return image

static func _mirror_rows(rows: Array) -> Array:
	var out: Array = []
	for row: String in rows:
		out.append(row + row.reverse())
	return out

static func _build_hero(out: Dictionary) -> void:
	var legs: Dictionary = Data.HERO_LEGS
	out["hero_idle"] = [_hero(Data.HERO_BODY, legs["stand"], 0), _hero(Data.HERO_BODY, legs["stand"], 1)]
	out["hero_run"] = [_hero(Data.HERO_BODY, legs["run1"], 0), _hero(Data.HERO_BODY, legs["run2"], 1), _hero(Data.HERO_BODY, legs["run3"], 0), _hero(Data.HERO_BODY, legs["run4"], 1)]
	out["hero_jump"] = [_hero(Data.HERO_BODY, legs["jump"], 0)]
	out["hero_fall"] = [_hero(Data.HERO_BODY, legs["fall"], 0)]
	out["hero_throw"] = [_hero(Data.HERO_BODY_THROW, legs["stand"], 0), _hero(Data.HERO_BODY_THROW, legs["run1"], 0), _hero(Data.HERO_BODY_THROW, legs["jump"], 0)]
	out["hero_hurt"] = [_hero(Data.HERO_BODY_HURT, legs["fall"], 0)]
	out["hero_ride"] = [_hero(Data.HERO_BODY, legs["sit"], 0), _hero(Data.HERO_BODY_THROW, legs["sit"], 0)]
	var ram: Array = []
	for index: int in [0, 1, 0, 2]:
		ram.append(_from_rows(Data.RAM_BODY + Data.RAM_LEGS[index]))
	out["ram"] = ram

## A hero frame: one blank row, the body (lowered a pixel when `bob` is 1, losing its last row behind the legs) and the legs.
static func _hero(body: Array, legs: Array, bob: int) -> Image:
	var rows: Array = ["................"]
	if bob == 1:
		rows.append("................")
		rows.append_array(body.slice(0, body.size() - 1))
	else:
		rows.append_array(body)
	rows.append_array(legs)
	return _from_rows(rows)

# ---- painting helpers ----

static func _new(width: int, height: int) -> Image:
	return Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

static func _px(image: Image, x: int, y: int, key: String) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, Pal.of(key))

static func _box(image: Image, x: int, y: int, width: int, height: int, key: String) -> void:
	for row in range(y, y + height):
		for column in range(x, x + width):
			_px(image, column, row, key)

static func _ell(image: Image, cx: float, cy: float, rx: float, ry: float, key: String) -> void:
	for row in range(int(floor(cy - ry)), int(ceil(cy + ry)) + 1):
		for column in range(int(floor(cx - rx)), int(ceil(cx + rx)) + 1):
			var dx := (float(column) - cx) / maxf(rx, 0.01)
			var dy := (float(row) - cy) / maxf(ry, 0.01)
			if dx * dx + dy * dy <= 1.0:
				_px(image, column, row, key)

static func _line(image: Image, x0: int, y0: int, x1: int, y1: int, key: String) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for index in steps + 1:
		var t := 0.0 if steps == 0 else float(index) / float(steps)
		_px(image, roundi(lerpf(float(x0), float(x1), t)), roundi(lerpf(float(y0), float(y1), t)), key)

static func _opaque(image: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and image.get_pixel(x, y).a > 0.5

## Put a one-pixel outline around everything already drawn.
static func _outline(image: Image, key: String) -> void:
	var source := image.duplicate() as Image
	for y in image.get_height():
		for x in image.get_width():
			if not _opaque(source, x, y) and (_opaque(source, x - 1, y) or _opaque(source, x + 1, y) or _opaque(source, x, y - 1) or _opaque(source, x, y + 1)):
				_px(image, x, y, key)

static func _whitened(image: Image) -> Image:
	var out := image.duplicate() as Image
	var white := Pal.of("8")
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).a > 0.5:
				out.set_pixel(x, y, white)
	return out

## Fill horizontal bands, dithering the four rows around each boundary. `bands` is [[first row, colour key], ...] from the top.
static func _bands(image: Image, bands: Array) -> void:
	for index in bands.size():
		var from_row := int(bands[index][0])
		var to_row := int(bands[index + 1][0]) if index + 1 < bands.size() else image.get_height()
		_box(image, 0, from_row, image.get_width(), to_row - from_row, str(bands[index][1]))
		if index > 0:
			for row in range(from_row - 4, from_row):
				for column in image.get_width():
					var depth := row - (from_row - 4)
					var on := (column + row) % 2 == 0 if depth >= 2 else (column % 4 == (row % 2) * 2 and row % 2 == depth % 2)
					if on:
						_px(image, column, row, str(bands[index][1]))

# ---- tiles ----

static func _tile_ground(area: int, top: bool, variant: int) -> Image:
	var image := _new(16, 16)
	var rng := Rng.new(area * 100 + variant * 7 + (3 if top else 0))
	var base := "9" if area == 1 else "d"
	var light := "a" if area == 1 else "e"
	var dark := "1" if area == 1 else "s"
	var accent := "4" if area == 1 else "f"
	_box(image, 0, 0, 16, 16, dark)
	# Two courses of stones, the lower one shifted, so the seams never line up into a grid.
	for course in 2:
		var shift := 5 * course + variant * 3
		for stone in 2:
			var x := (stone * 8 + shift) % 16
			var y := course * 8
			for row in range(y, y + 7):
				for column in range(x, x + 7):
					_px(image, column % 16, row, base)
			for column in range(x, x + 6):
				_px(image, column % 16, y, light)
			_px(image, x % 16, y + 1, light)
	for speck in 5:
		_px(image, rng.int_range(0, 15), rng.int_range(4 if top else 0, 15), light if speck < 3 else dark)
	if rng.chance(0.6):
		var x := rng.int_range(2, 12)
		var y := rng.int_range(7, 13)
		_px(image, x, y, accent)
		_px(image, x + 1, y + 1, accent)
	if top:
		var cap := "b" if area == 1 else "g"
		var bright := "c" if area == 1 else "h"
		for column in 16:
			var depth := 2 + int(rng.chance(0.45)) + int(rng.chance(0.2))
			for row in depth:
				_px(image, column, row, bright if row == 0 else cap)
			_px(image, column, depth, dark)
		if area == 1:
			for ember in 2:
				_px(image, rng.int_range(0, 15), 1, "5")
	return image

static func _tile_ice(variant: int) -> Image:
	var image := _new(16, 16)
	_box(image, 0, 0, 16, 16, "f")
	_box(image, 0, 0, 16, 1, "h")
	_box(image, 0, 1, 16, 2, "g")
	_box(image, 0, 12, 16, 4, "e")
	for streak in 3:
		var x := (streak * 6 + variant * 4 + 1) % 16
		_line(image, x, 14, x + 5, 5, "g")
		_px(image, (x + 5) % 16, 4, "h")
	return image

static func _tile_platform(area: int, cracked: bool) -> Image:
	var image := _new(16, 16)
	if area == 1 and not cracked:
		_box(image, 0, 0, 16, 1, "m")
		_box(image, 0, 1, 16, 4, "l")
		for seam: int in [5, 11]:
			_box(image, seam, 0, 1, 5, "0")
		_box(image, 0, 5, 16, 1, "0")
		_px(image, 2, 2, "m")
		_px(image, 8, 3, "m")
		_px(image, 13, 2, "m")
		_box(image, 7, 6, 2, 3, "1")
	elif area == 1:
		_box(image, 0, 0, 16, 1, "c")
		_box(image, 0, 1, 16, 4, "b")
		_box(image, 0, 5, 16, 1, "0")
		_line(image, 3, 0, 5, 4, "1")
		_line(image, 10, 4, 12, 0, "1")
		_px(image, 7, 2, "a")
		_box(image, 0, 6, 16, 1, "9")
	elif not cracked:
		_box(image, 0, 0, 16, 1, "h")
		_box(image, 0, 1, 16, 3, "g")
		_box(image, 0, 4, 16, 2, "f")
		_box(image, 0, 6, 16, 1, "d")
		for facet: int in [3, 9, 14]:
			_line(image, facet, 1, facet - 2, 5, "f")
		_px(image, 5, 7, "f")
		_px(image, 11, 7, "f")
		_px(image, 11, 8, "e")
	else:
		_box(image, 0, 0, 16, 1, "h")
		_box(image, 0, 1, 16, 3, "g")
		_box(image, 0, 4, 16, 1, "d")
		_line(image, 4, 0, 6, 3, "e")
		_line(image, 11, 3, 13, 0, "e")
		_line(image, 6, 3, 9, 2, "e")
	return image

static func _tile_spike(area: int) -> Image:
	var image := _new(16, 16)
	var body := "2" if area == 1 else "f"
	var shade := "1" if area == 1 else "e"
	var tip := "4" if area == 1 else "h"
	for spike: Array in [[3, 9], [8, 13], [13, 8]]:
		var cx := int(spike[0])
		var height := int(spike[1])
		for row in height:
			var half := int(float(row) / float(height) * 3.0)
			for column in range(cx - half, cx + half + 1):
				_px(image, column, 16 - height + row, body if column <= cx else shade)
		_px(image, cx, 16 - height, tip)
		_px(image, cx, 17 - height, tip)
	_outline(image, "0")
	return image

static func _tile_liquid(area: int, frame: int) -> Image:
	var image := _new(16, 16)
	var crest := "7" if area == 1 else "g"
	var body := "5" if area == 1 else "e"
	var glow := "6" if area == 1 else "f"
	_box(image, 0, 3, 16, 13, body)
	for column in 16:
		var wave := int(round(1.4 * sin(float(column + frame * 4) * TAU / 16.0) + 1.5))
		for row in range(wave, 4):
			_px(image, column, row, glow if row > wave else crest)
	for bubble: Array in [[3, 8], [10, 11], [13, 6]]:
		_px(image, (int(bubble[0]) + frame * 2) % 16, int(bubble[1]), glow)
	return image

static func _tile_deep(area: int) -> Image:
	var image := _new(16, 16)
	_box(image, 0, 0, 16, 16, "5" if area == 1 else "e")
	_box(image, 0, 6, 16, 10, "4" if area == 1 else "d")
	for column in 16:
		if column % 3 == 0:
			_px(image, column, 5, "4" if area == 1 else "d")
		if column % 4 == 1:
			_px(image, column, 6, "5" if area == 1 else "e")
	return image

static func _mover(area: int) -> Image:
	var image := _new(40, 12)
	if area == 1:
		_box(image, 1, 1, 38, 6, "a")
		_box(image, 1, 1, 38, 1, "c")
		_box(image, 1, 2, 38, 1, "b")
		_box(image, 3, 7, 34, 2, "9")
		_box(image, 8, 9, 24, 1, "9")
		for rune: int in [8, 19, 30]:
			_box(image, rune, 4, 2, 2, "5")
			_px(image, rune, 4, "7")
		for column in range(10, 30, 4):
			_px(image, column, 10, "5")
	else:
		_box(image, 1, 1, 38, 5, "g")
		_box(image, 1, 1, 38, 1, "h")
		_box(image, 3, 6, 34, 2, "f")
		_box(image, 9, 8, 22, 1, "e")
		for facet in range(5, 38, 7):
			_line(image, facet, 2, facet - 3, 7, "f")
		for column in range(12, 30, 5):
			_px(image, column, 10, "r")
	_outline(image, "0")
	return image

# ---- props and fixtures ----

static func _lamp(lit: bool) -> Image:
	var image := _new(14, 36)
	_box(image, 6, 11, 2, 23, "9")
	_box(image, 6, 11, 1, 23, "a")
	_box(image, 4, 33, 6, 2, "9")
	_box(image, 5, 31, 4, 2, "a")
	_box(image, 3, 9, 8, 2, "9")
	_box(image, 4, 2, 6, 7, "6" if lit else "a")
	if lit:
		_box(image, 5, 3, 4, 5, "7")
		_box(image, 6, 4, 2, 3, "8")
	else:
		_box(image, 6, 4, 2, 4, "9")
	_box(image, 4, 2, 1, 7, "9")
	_box(image, 9, 2, 1, 7, "9")
	_box(image, 3, 1, 8, 1, "9")
	_box(image, 5, 0, 4, 1, "9")
	_outline(image, "0")
	return image

static func _beacon(state: int) -> Image:
	var image := _new(36, 56)
	for row in range(24, 55):
		var half := 8 + (row - 24) / 5
		_box(image, 18 - half, row, half * 2, 1, "a")
		_px(image, 18 - half, row, "c")
		_px(image, 18 - half + 1, row, "b")
		_box(image, 18 + half - 3, row, 3, 1, "9")
	for course in range(28, 55, 6):
		_box(image, 9, course, 18, 1, "9")
	_box(image, 15, 34, 6, 8, "9")
	_box(image, 16, 35, 4, 7, "6" if state > 0 else "1")
	_box(image, 6, 20, 24, 4, "5")
	_box(image, 6, 20, 24, 1, "6")
	_box(image, 8, 24, 20, 1, "4")
	_box(image, 9, 18, 18, 2, "1" if state == 0 else "5")
	if state > 0:
		var lean := 1 if state == 1 else -1
		_ell(image, 18.0, 13.0, 8.0, 7.0, "5")
		_ell(image, 18.0 + lean, 9.0, 5.0, 8.0, "5")
		_ell(image, 18.0, 14.0, 5.5, 5.0, "6")
		_ell(image, 18.0 + lean, 10.0, 3.0, 6.0, "6")
		_ell(image, 18.0, 15.0, 3.0, 3.5, "7")
		_ell(image, 18.0, 16.0, 1.5, 2.0, "8")
		_px(image, 18 + lean * 2, 1, "6")
		_px(image, 12 - lean, 5, "5")
		_px(image, 25 + lean, 4, "6")
	_outline(image, "0")
	return image

static func _vent() -> Image:
	var image := _new(16, 7)
	_ell(image, 7.5, 6.0, 7.0, 4.0, "a")
	_ell(image, 7.5, 6.5, 5.0, 3.0, "9")
	_box(image, 4, 3, 8, 2, "1")
	_box(image, 5, 3, 6, 1, "4")
	_px(image, 3, 3, "c")
	_px(image, 12, 3, "b")
	_outline(image, "0")
	return image

static func _column(frame: int) -> Image:
	var image := _new(14, 16)
	var rng := Rng.new(40 + frame)
	for row in 16:
		var wobble := int(round(sin(float(row + frame * 5) * 0.9)))
		_box(image, 2 + wobble, row, 10, 1, "5")
		_box(image, 4 + wobble, row, 6, 1, "6")
		_box(image, 5 + wobble, row, 3, 1, "7")
		if rng.chance(0.4):
			_px(image, 6 + wobble, row, "8")
		if rng.chance(0.3):
			_px(image, rng.int_range(0, 1), row, "4")
		if rng.chance(0.3):
			_px(image, rng.int_range(12, 13), row, "4")
	return image

static func _tree(variant: int) -> Image:
	var image := _new(26, 40)
	var lean := 2 if variant == 0 else -2
	_line(image, 12, 39, 12 + lean, 14, "1")
	_line(image, 13, 39, 13 + lean, 14, "1")
	_line(image, 14, 39, 13 + lean, 20, "1")
	_line(image, 12 + lean, 24, 4, 12, "1")
	_line(image, 4, 12, 2, 5, "1")
	_line(image, 4, 12, 8, 6, "1")
	_line(image, 13 + lean, 18, 21, 9, "1")
	_line(image, 21, 9, 24, 3, "1")
	_line(image, 21, 9, 17, 3, "1")
	_line(image, 12 + lean, 14, 11 + lean * 2, 4, "1")
	_line(image, 12, 39, 12 + lean, 20, "2")
	return image

static func _spire(area: int) -> Image:
	var image := _new(18, 30)
	var body := "9" if area == 1 else "d"
	var light := "a" if area == 1 else "e"
	var dark := "1" if area == 1 else "s"
	for row in 30:
		var half := 1 + row / 5
		_box(image, 9 - half, row, half * 2, 1, body)
		_px(image, 9 - half, row, light)
		_box(image, 9 + half - 2, row, 2, 1, dark)
	for row in range(10, 30):
		var half := (row - 10) / 6
		_box(image, 3 - half, row, half * 2 + 1, 1, body)
	return image

static func _tuft(area: int) -> Image:
	var image := _new(9, 6)
	var blade := "b" if area == 1 else "g"
	var tip := "c" if area == 1 else "h"
	for stalk: Array in [[1, 3], [3, 5], [5, 4], [7, 2]]:
		_box(image, int(stalk[0]), 6 - int(stalk[1]), 1, int(stalk[1]), blade)
		_px(image, int(stalk[0]), 6 - int(stalk[1]), tip)
	if area == 1:
		_px(image, 3, 0, "5")
	return image

static func _crystal(variant: int) -> Image:
	var image := _new(18, 24)
	var shards := [[5, 20, 3], [10, 23, 4], [14, 14, 2]] if variant == 0 else [[4, 13, 2], [9, 18, 3], [13, 22, 4]]
	for shard: Array in shards:
		var cx := int(shard[0])
		var height := int(shard[1])
		var half := int(shard[2])
		for row in height:
			var taper := mini(half, row / 2 + 1)
			_box(image, cx - taper, 24 - height + row, taper, 1, "g")
			_box(image, cx, 24 - height + row, taper, 1, "f")
			_px(image, cx - taper, 24 - height + row, "h")
	_outline(image, "d")
	return image

static func _shroom() -> Image:
	var image := _new(9, 8)
	_box(image, 4, 4, 1, 4, "h")
	_ell(image, 4.0, 3.0, 3.6, 2.4, "r")
	_box(image, 2, 2, 2, 1, "h")
	_outline(image, "d")
	return image

## A soft dithered disc of light, drawn under lamps and the hero's lantern.
static func _glow(size: int, key: String) -> Image:
	var image := _new(size, size)
	var centre := float(size - 1) / 2.0
	for y in size:
		for x in size:
			var distance := Vector2(float(x) - centre, float(y) - centre).length() / centre
			if distance < 0.45 or (distance < 0.75 and (x + y) % 2 == 0) or (distance < 1.0 and x % 2 == 0 and y % 2 == 0 and (x + y) % 4 == 0):
				var colour := Pal.of(key)
				colour.a = 0.14
				image.set_pixel(x, y, colour)
	return image

# ---- bosses ----

## The magma toad. pose: 0 sitting, 1 crouched, 2 in the air, 3 mouth open.
static func _toad(pose: int) -> Image:
	var image := _new(60, 44)
	var sink := 4 if pose == 1 else (-3 if pose == 2 else 0)
	var cy := 25.0 + float(sink)
	var ry := 13.0 - float(sink) * 0.5
	# Legs first, so the body overlaps them.
	if pose == 2:
		_box(image, 8, 28, 6, 14, "9")
		_box(image, 46, 28, 6, 14, "9")
		_ell(image, 10.0, 41.0, 6.0, 2.0, "a")
		_ell(image, 50.0, 41.0, 6.0, 2.0, "a")
	else:
		_ell(image, 9.0, 34.0 + float(sink) * 0.5, 8.0, 7.0, "9")
		_ell(image, 51.0, 34.0 + float(sink) * 0.5, 8.0, 7.0, "9")
		_ell(image, 10.0, 40.0, 8.0, 2.5, "a")
		_ell(image, 50.0, 40.0, 8.0, 2.5, "a")
		for toe: int in [4, 9, 14, 46, 51, 56]:
			_px(image, toe, 41, "1")
	_ell(image, 30.0, cy + 2.0, 24.0, ry, "9")
	_ell(image, 30.0, cy, 24.0, ry, "a")
	_ell(image, 30.0, cy + 6.0, 17.0, ry - 6.0, "b")
	_ell(image, 24.0, cy - 8.0, 9.0, 2.0, "b")
	for wart: Array in [[12, -2], [47, -3], [20, -9], [40, -8], [33, -11]]:
		_box(image, int(wart[0]), int(cy) + int(wart[1]), 2, 1, "c")
	for crack: Array in [[14, -5, 19, 1], [45, -6, 41, 0], [29, -11, 31, -6], [8, 2, 12, 5], [52, 1, 48, 5]]:
		_line(image, int(crack[0]), int(cy) + int(crack[1]), int(crack[2]), int(cy) + int(crack[3]), "5")
		_px(image, int(crack[0]), int(cy) + int(crack[1]), "7")
	var eye_y := cy - ry + 2.0
	for eye_x: float in [17.0, 43.0]:
		_ell(image, eye_x, eye_y, 6.5, 6.0, "a")
		_ell(image, eye_x, eye_y - 1.0, 5.0, 2.0, "b")
		_ell(image, eye_x, eye_y, 4.0, 4.0, "7" if pose != 3 else "8")
		if pose == 3:
			_box(image, int(eye_x) - 3, int(eye_y), 7, 1, "0")
		else:
			_box(image, int(eye_x) - 1, int(eye_y) - 3, 2, 7, "0")
	if pose == 3:
		_ell(image, 30.0, cy + 3.0, 15.0, 7.0, "1")
		_ell(image, 30.0, cy + 4.0, 13.0, 5.5, "4")
		_ell(image, 30.0, cy + 5.0, 10.0, 4.0, "6")
		_ell(image, 30.0, cy + 6.0, 6.0, 2.5, "7")
	else:
		for column in range(11, 50):
			var curve := int(round(3.0 * sin(PI * float(column - 11) / 38.0)))
			_px(image, column, int(cy) + 1 + curve, "1")
			if column % 9 == 3:
				_px(image, column, int(cy) + 2 + curve, "5")
	_outline(image, "0")
	return image

## The hoarfrost owl. pose: 0 wings raised, 1 level, 2 lowered.
static func _owl(pose: int) -> Image:
	var image := _new(72, 46)
	var tip_y := [3.0, 19.0, 37.0][pose] as float
	for side: int in [-1, 1]:
		for step in 27:
			var t := float(step) / 26.0
			var x := 36 + side * (9 + step)
			var top := lerpf(17.0, tip_y, pow(t, 0.85))
			var thick := lerpf(13.0, 3.0, t)
			for row in int(thick):
				var y := int(top) + row
				var key := "e"
				if row >= int(thick) - 2:
					key = "g"
				elif row >= int(thick) - 5:
					key = "f"
				if step % 5 == 4 and row > 1:
					key = "d"
				_px(image, x, y, key)
			_px(image, x, int(top), "h" if step % 3 != 0 else "g")
	_ell(image, 36.0, 26.0, 10.0, 13.0, "d")
	_ell(image, 36.0, 25.0, 9.5, 12.5, "e")
	_ell(image, 36.0, 29.0, 6.5, 8.5, "g")
	for row: int in [25, 29, 33]:
		for column in range(32, 41, 2):
			_px(image, column, row + (column / 2) % 2, "f")
	_ell(image, 36.0, 12.0, 10.5, 8.0, "e")
	for side: int in [-1, 1]:
		_line(image, 36 + side * 6, 6, 36 + side * 10, 0, "e")
		_line(image, 36 + side * 7, 6, 36 + side * 10, 1, "e")
		_line(image, 36 + side * 8, 7, 36 + side * 11, 1, "f")
		_px(image, 36 + side * 10, 0, "h")
		_ell(image, 36.0 + float(side) * 5.0, 12.0, 4.5, 4.5, "h")
		_ell(image, 36.0 + float(side) * 5.0, 12.0, 2.6, 2.6, "6")
		_box(image, 36 + side * 5 - (1 if side < 0 else 0), 11, 2, 3, "0")
		_box(image, 36 + side * 4 - 1, 38, 3, 4, "6")
		_px(image, 36 + side * 4 - 1, 42, "5")
		_px(image, 36 + side * 4 + 1, 42, "5")
	_box(image, 35, 14, 2, 2, "6")
	_px(image, 35, 16, "5")
	_px(image, 36, 16, "5")
	_outline(image, "0")
	return image

# ---- backdrops ----

static func _sky(area: int) -> Image:
	var image := _new(480, 270)
	var rng := Rng.new(900 + area)
	if area == 1:
		_bands(image, [[0, "s"], [34, "1"], [70, "2"], [104, "q"], [134, "3"], [160, "4"], [182, "5"], [200, "6"]])
		for star in 70:
			var y := rng.int_range(0, 96)
			_px(image, rng.int_range(0, 479), y, "8" if star % 5 == 0 else ("c" if y < 60 else "b"))
		# A low sun, sliced by bands of haze.
		for row in range(128, 215):
			if row > 160 and (row - 160) % 7 < 2 + (row - 160) / 14:
				continue
			for column in range(280, 400):
				var distance := Vector2(float(column) - 340.0, float(row) - 176.0).length()
				if distance < 46.0:
					_px(image, column, row, "8" if distance < 22.0 else ("7" if distance < 36.0 else "6"))
	else:
		_bands(image, [[0, "0"], [60, "s"], [150, "d"], [236, "s"]])
		for mote in 46:
			var x := rng.int_range(0, 479)
			var y := rng.int_range(40, 230)
			_px(image, x, y, "e")
			if mote % 6 == 0:
				_px(image, x, y, "f")
				_px(image, x + 1, y, "e")
				_px(image, x, y + 1, "e")
	return image

static func _far(area: int) -> Image:
	var image := _new(320, 150)
	var rng := Rng.new(700 + area)
	if area == 1:
		for column in 320:
			var phase := float(column) * TAU / 320.0
			var height := 46.0 + 20.0 * sin(phase * 2.0 + 0.6) + 12.0 * sin(phase * 5.0 + 2.0) + 5.0 * sin(phase * 13.0)
			# One volcano stands above the range.
			var cone := 104.0 - absf(float(column) - 210.0) * 1.25
			if cone > height:
				height = minf(cone, 96.0)
			var top := 150 - int(height)
			_box(image, column, top, 1, int(height), "2")
			_px(image, column, top, "q")
			if rng.chance(0.3):
				_px(image, column, top + rng.int_range(3, 20), "1")
		_box(image, 204, 54, 13, 2, "6")
		_box(image, 206, 53, 9, 1, "7")
		_line(image, 209, 56, 204, 80, "5")
		_line(image, 204, 80, 207, 104, "4")
		_line(image, 213, 56, 219, 90, "4")
		for puff: Array in [[212, 44, 7], [220, 33, 9], [232, 22, 11], [248, 14, 9]]:
			_ell(image, float(puff[0]), float(puff[1]), float(puff[2]), float(puff[2]) * 0.6, "2")
			_ell(image, float(puff[0]) - 1.0, float(puff[1]) - 2.0, float(puff[2]) * 0.6, float(puff[2]) * 0.3, "q")
	else:
		for pillar in 9:
			var x := pillar * 36 + rng.int_range(0, 12)
			var width := rng.int_range(10, 22)
			var lean := rng.int_range(-10, 10)
			for row in 150:
				var offset := int(float(lean) * float(row) / 150.0)
				var pinch := int(4.0 * sin(float(row) / 150.0 * PI))
				for column in range(x + offset + pinch, x + offset + width - pinch):
					_px(image, posmod(column, 320), row, "d")
				_px(image, posmod(x + offset + pinch, 320), row, "e")
				if row % 17 == pillar % 17:
					_px(image, posmod(x + offset + pinch + 2, 320), row, "f")
	return image

static func _near(area: int) -> Image:
	var image := _new(320, 270)
	var rng := Rng.new(500 + area)
	if area == 1:
		for column in 320:
			var phase := float(column) * TAU / 320.0
			var height := 36.0 + 14.0 * sin(phase * 3.0 + 1.0) + 8.0 * sin(phase * 7.0) + 3.0 * sin(phase * 19.0 + 1.0)
			var top := 270 - 44 - int(height)
			_box(image, column, top, 1, 270 - top, "1")
			_px(image, column, top, "3")
			if rng.chance(0.08):
				_box(image, column, top - rng.int_range(2, 7), 1, 8, "1")
			if rng.chance(0.05):
				_px(image, column, top + rng.int_range(8, 26), "4")
	else:
		for column in 320:
			var phase := float(column) * TAU / 320.0
			var hang := 30.0 + 16.0 * absf(sin(phase * 4.0 + 0.5)) + 14.0 * maxf(0.0, sin(phase * 11.0)) + 6.0 * sin(phase * 23.0)
			_box(image, column, 0, 1, int(hang), "0")
			_px(image, column, int(hang), "d")
			var rise := 34.0 + 18.0 * absf(sin(phase * 3.0 + 2.0)) + 10.0 * maxf(0.0, sin(phase * 9.0 + 1.0))
			var top := 270 - 40 - int(rise)
			_box(image, column, top, 1, 270 - top, "0")
			_px(image, column, top, "d")
			if rng.chance(0.04):
				_px(image, column, top + rng.int_range(4, 16), "r")
	return image
