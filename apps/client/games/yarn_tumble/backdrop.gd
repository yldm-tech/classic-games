extends RefCounted

## Paints a floor's still picture: a dithered wall, the far decoration of its part of the tower, and the tiles on top. The view draws the moving things over it.

const Raster := preload("res://games/yarn_tumble/raster.gd")
const Levels := preload("res://games/yarn_tumble/levels.gd")

const WIDTH := 480
const HEIGHT := 270
const TILE := 16
const OFFSET_Y := -2
const INK := Color("1b1420")
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## Per part of the tower: wall gradient (top, bottom), far decoration (two tones and an accent), stone (base, light, dark) and knitted ledge (base, light, dark).
const THEMES := [
	{"sky": ["21151f", "44282a"], "far": ["3a2227", "55312c", "8a4a3a"], "stone": ["6b4a3a", "8f6a4e", "3e2a26"], "knit": ["c8553d", "f0906a", "7a2e2e"]},
	{"sky": ["152533", "33234a"], "far": ["223a4a", "35506a", "4f8a8a"], "stone": ["3f5a66", "5f8892", "24363f"], "knit": ["b9c24a", "e6e882", "6e7a2a"]},
	{"sky": ["11112a", "2c2444"], "far": ["1f1d3c", "34305a", "6a5a9a"], "stone": ["5a4636", "80684c", "33261f"], "knit": ["8c6fe0", "c0a8ff", "4b3a94"]},
	{"sky": ["0e1730", "22305a"], "far": ["1a2748", "2c3d6c", "c2478f"], "stone": ["2f3f6e", "5068a8", "1b2444"], "knit": ["e8a0b4", "ffd6de", "9c5070"]},
	{"sky": ["1f1216", "45222a"], "far": ["341c20", "55302c", "c09a48"], "stone": ["8a6a2e", "c8a250", "4e3a1c"], "knit": ["c23a4a", "f58070", "6e1c30"]},
	{"sky": ["0a0a22", "40224e"], "far": ["1c1838", "342a58", "ffd75a"], "stone": ["4a4a66", "7878a8", "26263c"], "knit": ["e0b040", "ffe68a", "8a6020"]},
]

static func build(theme: int, grid: PackedByteArray) -> Image:
	var colors: Dictionary = THEMES[clampi(theme, 0, THEMES.size() - 1)]
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	_sky(image, Color(str(colors["sky"][0])), Color(str(colors["sky"][1])))
	var far: Array = [Color(str(colors["far"][0])), Color(str(colors["far"][1])), Color(str(colors["far"][2]))]
	match theme:
		Levels.THEME_CELLAR: _cellar(image, far)
		Levels.THEME_DYE: _dye_works(image, far)
		Levels.THEME_LOFT: _loft(image, far)
		Levels.THEME_GALLERY: _gallery(image, far)
		Levels.THEME_CLOCK: _clockwork(image, far)
		_: _crown(image, far)
	_tiles(image, grid, colors)
	return image

## A vertical gradient in eight bands, ordered-dithered where two bands meet.
static func _sky(image: Image, top: Color, bottom: Color) -> void:
	for py in HEIGHT:
		var level := float(py) / float(HEIGHT - 1) * 7.0
		var band := int(floor(level))
		var part := level - band
		for px in WIDTH:
			var pick := band + (1 if part * 16.0 > float(BAYER[(py % 4) * 4 + (px % 4)]) else 0)
			image.set_pixel(px, py, top.lerp(bottom, float(pick) / 7.0))

static func _bricks(image: Image, tone: Color, height: int, width: int) -> void:
	for py in range(0, HEIGHT, height):
		var shift := (width / 2) if (py / height) % 2 == 1 else 0
		Raster.box(image, 0, py, WIDTH, 1, tone)
		for px in range(shift, WIDTH, width):
			Raster.box(image, px, py, 1, height, tone)

## Wool Cellar: brickwork, two posts and shelves of put-away yarn.
static func _cellar(image: Image, far: Array) -> void:
	_bricks(image, far[0], 12, 28)
	for post: int in [118, 356]:
		Raster.box(image, post, 0, 8, HEIGHT, far[1])
		Raster.box(image, post, 0, 2, HEIGHT, far[2].darkened(0.3))
		Raster.box(image, post - 6, 40, 20, 4, far[1])
	var wools := [Color("7a4a52"), Color("5a5a7a"), Color("7a6a3a"), Color("4a6a5a")]
	for shelf: Vector2i in [Vector2i(30, 96), Vector2i(180, 60), Vector2i(180, 150), Vector2i(398, 100), Vector2i(398, 190), Vector2i(30, 190)]:
		Raster.box(image, shelf.x, shelf.y, 62, 3, far[1])
		Raster.box(image, shelf.x, shelf.y + 3, 62, 1, far[0].darkened(0.3))
		for index in 4:
			var cx := shelf.x + 8.0 + index * 15.0
			var wool: Color = wools[(index + shelf.x + shelf.y) % wools.size()]
			Raster.disc(image, cx, shelf.y - 6.0, 5.5, 5.5, wool)
			Raster.line(image, cx - 4.0, shelf.y - 8.0, cx + 3.0, shelf.y - 3.0, wool.darkened(0.25))
			Raster.line(image, cx - 2.0, shelf.y - 10.0, cx + 4.0, shelf.y - 6.0, wool.lightened(0.15))

## Dye Works: cloth hung to dry, pipes and steaming vats.
static func _dye_works(image: Image, far: Array) -> void:
	_bricks(image, far[0], 16, 40)
	Raster.box(image, 0, 34, WIDTH, 3, far[1])
	var cloths := [Color("3c2a4c"), Color("23464c"), Color("4a4028"), Color("4a2638"), Color("2a3454")]
	for index in 9:
		var cx := 34 + index * 52
		var length := 50 + int(Raster.grain(index, 3, 1) * 60.0)
		var cloth: Color = cloths[index % cloths.size()]
		for py in length:
			var sway := int(round(sin(py * 0.12 + index) * 1.5))
			Raster.box(image, cx + sway, 37 + py, 22, 1, cloth if (py / 6) % 2 == 0 else cloth.lightened(0.08))
			Raster.dot(image, cx + sway, 37 + py, cloth.darkened(0.3))
		for fringe in range(0, 22, 3):
			Raster.box(image, cx + fringe, 37 + length, 1, 3, cloth.darkened(0.2))
	for vat: int in [70, 240, 410]:
		Raster.box(image, vat - 34, 214, 68, 44, far[0].lightened(0.06))
		Raster.box(image, vat - 34, 214, 4, 44, far[1])
		Raster.disc(image, float(vat), 214.0, 34.0, 7.0, far[1])
		Raster.disc(image, float(vat), 214.0, 30.0, 5.0, far[2].darkened(0.25))
		Raster.box(image, vat - 34, 228, 68, 2, far[0])
		Raster.box(image, vat - 34, 244, 68, 2, far[0])

## Moth Loft: rafters, a round moon window and cobwebs.
static func _loft(image: Image, far: Array) -> void:
	Raster.disc(image, 240.0, 92.0, 46.0, 46.0, far[1])
	Raster.disc(image, 240.0, 92.0, 41.0, 41.0, Color("3c3a70"))
	Raster.disc(image, 252.0, 84.0, 20.0, 20.0, Color("d8d4b8"))
	Raster.disc(image, 259.0, 80.0, 17.0, 17.0, Color("3c3a70"))
	Raster.box(image, 238, 48, 4, 90, far[1])
	Raster.box(image, 196, 90, 90, 4, far[1])
	for index in 7:
		Raster.dot(image, 206 + index * 11, 60 + int(Raster.grain(index, 9, 2) * 60.0), Color("f6f0e4"))
	for side: int in [-1, 1]:
		for beam in 4:
			var x0 := 240.0 + side * (20.0 + beam * 70.0)
			for thick in 5:
				Raster.line(image, x0 + thick, 0.0, x0 + side * 150.0 + thick, 270.0, far[0] if thick > 0 else far[1])
	for corner: Vector2i in [Vector2i(16, 0), Vector2i(463, 0)]:
		var side := 1 if corner.x < 240 else -1
		for strand in 5:
			Raster.line(image, float(corner.x), 0.0, corner.x + side * (20.0 + strand * 16.0), 70.0 - strand * 14.0, far[2])
		for ring in 3:
			Raster.line(image, corner.x + side * (10.0 + ring * 14.0), 46.0 - ring * 6.0, corner.x + side * (40.0 + ring * 14.0), 10.0 + ring * 2.0, far[2])

## Button Gallery: panelled walls, columns and giant framed buttons.
static func _gallery(image: Image, far: Array) -> void:
	for panel in 6:
		var px := 20 + panel * 76
		Raster.box(image, px, 44, 64, 196, far[0])
		Raster.box(image, px + 3, 47, 58, 190, far[0].lightened(0.04))
	var hues := [Color("6a3a5a"), Color("3a5a6a"), Color("6a5a3a")]
	for index in 6:
		var cx := 52.0 + index * 76.0
		var cy := 96.0 if index % 2 == 0 else 176.0
		var hue: Color = hues[index % hues.size()]
		Raster.box(image, int(cx) - 22, int(cy) - 22, 44, 44, far[1])
		Raster.box(image, int(cx) - 19, int(cy) - 19, 38, 38, far[0].darkened(0.2))
		Raster.disc(image, cx, cy, 15.0, 15.0, hue)
		Raster.disc(image, cx, cy, 11.0, 11.0, hue.lightened(0.1))
		for hole: Vector2i in [Vector2i(-4, -4), Vector2i(4, -4), Vector2i(-4, 4), Vector2i(4, 4)]:
			Raster.disc(image, cx + hole.x, cy + hole.y, 1.6, 1.6, far[0].darkened(0.3))
	Raster.box(image, 0, 240, WIDTH, 4, far[1])

## Clockwork Loom: gears, a pipe run and warp threads.
static func _clockwork(image: Image, far: Array) -> void:
	for thread in range(24, WIDTH, 9):
		Raster.box(image, thread, 0, 1, HEIGHT, far[0])
	for gear: Vector3 in [Vector3(90, 110, 40), Vector3(168, 170, 26), Vector3(380, 96, 48), Vector3(300, 200, 30), Vector3(430, 210, 22)]:
		var teeth := int(gear.z / 3.0)
		for tooth in teeth:
			var angle := TAU * tooth / teeth
			Raster.disc(image, gear.x + cos(angle) * gear.z, gear.y + sin(angle) * gear.z, 3.6, 3.6, far[1])
		Raster.disc(image, gear.x, gear.y, gear.z, gear.z, far[1])
		Raster.disc(image, gear.x, gear.y, gear.z - 5.0, gear.z - 5.0, far[0])
		for spoke in 3:
			var angle := PI * spoke / 3.0
			Raster.line(image, gear.x - cos(angle) * gear.z, gear.y - sin(angle) * gear.z, gear.x + cos(angle) * gear.z, gear.y + sin(angle) * gear.z, far[1])
		Raster.disc(image, gear.x, gear.y, 5.0, 5.0, far[2].darkened(0.35))
	Raster.box(image, 0, 38, WIDTH, 5, far[1])
	Raster.box(image, 0, 43, WIDTH, 1, far[0].darkened(0.3))
	for joint in range(40, WIDTH, 80):
		Raster.box(image, joint, 36, 6, 9, far[2].darkened(0.3))

## Tower Crown: the open sky, a great moon and the roofs below.
static func _crown(image: Image, far: Array) -> void:
	for star in 90:
		var sx := int(Raster.grain(star, 1, 7) * WIDTH)
		var sy := int(Raster.grain(star, 2, 7) * 190.0)
		Raster.dot(image, sx, sy, Color("f6f0e4") if star % 3 == 0 else Color("8a84b8"))
	Raster.disc(image, 372.0, 78.0, 30.0, 30.0, Color("efe6c0"))
	Raster.disc(image, 362.0, 70.0, 5.0, 5.0, Color("d6cba0"))
	Raster.disc(image, 384.0, 88.0, 7.0, 7.0, Color("d6cba0"))
	for spire: Vector3 in [Vector3(60, 150, 30), Vector3(150, 190, 22), Vector3(250, 170, 26), Vector3(330, 200, 20), Vector3(430, 160, 28)]:
		for py in range(int(spire.y), HEIGHT):
			Raster.box(image, int(spire.x - spire.z * 0.5), py, int(spire.z), 1, far[0])
		for row in int(spire.z):
			var spread := float(row + 1) / spire.z
			Raster.box(image, int(spire.x - (spire.z * 0.5 + 3.0) * spread), int(spire.y) - int(spire.z) + row, int((spire.z + 6.0) * spread) + 1, 1, far[1])
		for window in 3:
			Raster.box(image, int(spire.x) - 2, int(spire.y) + 10 + window * 22, 4, 6, far[2].darkened(0.2))
	for cloud in 5:
		Raster.disc(image, 40.0 + cloud * 104.0, 236.0 + (cloud % 2) * 10.0, 60.0, 9.0, far[1].lightened(0.05))

static func _tile(grid: PackedByteArray, col: int, row: int) -> int:
	if col < 0 or col >= Levels.COLS:
		return Levels.SOLID
	if row < 0 or row >= Levels.ROWS:
		return Levels.EMPTY
	return grid[row * Levels.COLS + col]

static func _tiles(image: Image, grid: PackedByteArray, colors: Dictionary) -> void:
	var stone: Array = [Color(str(colors["stone"][0])), Color(str(colors["stone"][1])), Color(str(colors["stone"][2]))]
	var knit: Array = [Color(str(colors["knit"][0])), Color(str(colors["knit"][1])), Color(str(colors["knit"][2]))]
	# Soft shadows first, so the tiles sit on top of them.
	for row in Levels.ROWS:
		for col in Levels.COLS:
			if _tile(grid, col, row) == Levels.EMPTY:
				continue
			var below := (row + 1) * TILE + OFFSET_Y - (6 if _tile(grid, col, row) == Levels.LEDGE else 0)
			if _tile(grid, col, row + 1) == Levels.EMPTY:
				for py in range(below, mini(HEIGHT, below + 5)):
					for px in range(col * TILE, (col + 1) * TILE):
						if py >= 0 and (px + py) % 2 == 0:
							image.set_pixel(px, py, image.get_pixel(px, py).darkened(0.35))
	for row in Levels.ROWS:
		for col in Levels.COLS:
			var kind := _tile(grid, col, row)
			var ox := col * TILE
			var oy := row * TILE + OFFSET_Y
			if kind == Levels.SOLID:
				_stone(image, grid, col, row, ox, oy, stone, knit)
			elif kind == Levels.LEDGE:
				_knit(image, ox, oy, knit, _tile(grid, col - 1, row) != Levels.LEDGE, _tile(grid, col + 1, row) != Levels.LEDGE)

## A block of masonry: two courses of bricks with a lit top edge; where it is walked on it carries a runner in the floor's ledge colour.
static func _stone(image: Image, grid: PackedByteArray, col: int, row: int, ox: int, oy: int, stone: Array, knit: Array) -> void:
	for py in TILE:
		for px in TILE:
			var course := py / 8
			var bx := (px + (8 if (course + row) % 2 == 1 else 0) + col * TILE) % 16
			var by := py % 8
			var color: Color = stone[0]
			if by == 0:
				color = stone[1]
			elif by == 7 or bx == 15:
				color = stone[2]
			elif bx == 0:
				color = stone[1]
			elif Raster.grain(ox + px, oy + py, 3) > 0.9:
				color = stone[2].lerp(stone[0], 0.5)
			elif Raster.grain(ox + px, oy + py, 4) > 0.93:
				color = stone[1].lerp(stone[0], 0.5)
			if oy + py >= 0 and oy + py < HEIGHT:
				image.set_pixel(ox + px, oy + py, color)
	if _tile(grid, col, row - 1) == Levels.EMPTY and row > 0:
		for px in TILE:
			Raster.dot(image, ox + px, oy, INK)
			Raster.dot(image, ox + px, oy + 1, knit[1] if (px + col * TILE) % 4 < 2 else knit[0])
			Raster.dot(image, ox + px, oy + 2, knit[0])
			Raster.dot(image, ox + px, oy + 3, knit[2])
	if _tile(grid, col - 1, row) == Levels.EMPTY:
		Raster.box(image, ox, maxi(0, oy), 1, TILE, INK)
	if _tile(grid, col + 1, row) == Levels.EMPTY:
		Raster.box(image, ox + TILE - 1, maxi(0, oy), 1, TILE, INK)
	if _tile(grid, col, row + 1) == Levels.EMPTY and row < Levels.ROWS - 1:
		Raster.box(image, ox, oy + TILE - 1, TILE, 1, INK)

## A length of knitted ledge: stocking stitch between two dark edges, with a fringe hanging under it.
static func _knit(image: Image, ox: int, oy: int, knit: Array, left_end: bool, right_end: bool) -> void:
	for px in TILE:
		var gx := (ox + px) % 4
		Raster.dot(image, ox + px, oy, INK)
		Raster.dot(image, ox + px, oy + 1, knit[1])
		for py in range(2, 8):
			var gy := (py - 2) % 3
			var color: Color = knit[0]
			if gy == 0 and (gx == 0 or gx == 3):
				color = knit[1]
			elif gy == 1 and (gx == 1 or gx == 2):
				color = knit[1]
			elif gy == 2 and (gx == 0 or gx == 3):
				color = knit[2]
			Raster.dot(image, ox + px, oy + py, color)
		Raster.dot(image, ox + px, oy + 8, knit[2])
		Raster.dot(image, ox + px, oy + 9, INK)
		if gx == 1:
			Raster.box(image, ox + px, oy + 10, 1, 3, knit[0])
			Raster.dot(image, ox + px, oy + 13, knit[2])
	if left_end:
		Raster.box(image, ox, oy + 1, 1, 8, INK)
	if right_end:
		Raster.box(image, ox + TILE - 1, oy + 1, 1, 8, INK)
