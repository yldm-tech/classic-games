extends RefCounted

## Paints what stands still: the tile layer of a stage, baked once into one image from the stage's rectangles, and the parallax layers behind it. Three themes: 0 the drowned boulevard at dawn, 1 the inside of the pump tower, 2 the dockyard in a night storm. `gfx` lends its painter.

const World := preload("res://games/tide_runners/world.gd")
const T := 16

static func noise(a: int, b: int) -> int:
	var n := (a * 374761393 + b * 668265263) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	return n ^ (n >> 16)

# ---- the tile layer ----

static func bake_level(gfx: Variant, world: World) -> Image:
	var image := Image.create(world.cols * T, world.rows * T, false, Image.FORMAT_RGBA8)
	var theme := int(world.def["theme"])
	for entry: Array in world.def["ground"]:
		var x := int(entry[0]) * T
		var y := int(entry[2]) * T
		var w := (int(entry[1]) - int(entry[0]) + 1) * T
		_ground(gfx, image, theme, x, y, w, world.rows * T - y)
	for entry: Array in world.def["blocks"]:
		_block(gfx, image, theme, int(entry[0]) * T, int(entry[1]) * T, int(entry[2]) * T, int(entry[3]) * T)
	for entry: Array in world.def["plats"]:
		_plat(gfx, image, theme, int(entry[0]) * T, int(entry[1]) * T, int(entry[2]) * T)
	return image

static func _ground(gfx: Variant, image: Image, theme: int, x: int, y: int, w: int, h: int) -> void:
	match theme:
		0:
			# The top floors of a drowned building: a ledge, brickwork and windows.
			gfx._rect(image, x, y, w, h, "h")
			for row in range(y + 9, y + h, 6):
				for column in range(x + noise(row, x) % 9, x + w - 6, 13):
					gfx._rect(image, column, row, 6, 1, "g")
			for window_row in 2:
				for column in range(x + 7, x + w - 12, 20):
					var roll := noise(column, y + window_row)
					if roll % 5 == 0:
						continue
					var top := y + 9 + window_row * 18
					gfx._rect(image, column, top, 9, 12, "0")
					gfx._rect(image, column + 1, top + 1, 7, 10, "e" if roll % 7 == 0 else "1")
					gfx._rect(image, column + 4, top + 1, 1, 10, "0")
			gfx._rect(image, x, y, w, 3, "j")
			gfx._rect(image, x, y + 3, w, 1, "i")
			gfx._rect(image, x, y + 4, w, 1, "g")
			for column in range(x, x + w - 1, 3):
				var roll := noise(column, y)
				if roll % 3 == 0:
					gfx._rect(image, column, y, 2, 1 + roll % 5, "8")
					gfx._px(image, column, y, "9")
			gfx._rect(image, x, y, 1, h, "j")
			gfx._rect(image, x + w - 2, y, 2, h, "g")
			_props(gfx, image, theme, x, y, w)
		1:
			gfx._rect(image, x, y, w, h, "7")
			gfx._rect(image, x, y, w, 1, "9")
			gfx._rect(image, x, y + 1, w, 2, "8")
			gfx._rect(image, x, y + 12, w, h - 12, "6")
			for column in range(x + 4, x + w, 8):
				gfx._px(image, column, y + 5, "9")
				gfx._px(image, column, y + 9, "6")
			for column in range(x, x + w, 32):
				gfx._rect(image, column, y + 3, 1, h - 3, "6")
		_:
			# A pier: planks on top, pilings and braces in the shadow under it.
			gfx._rect(image, x, y, w, h, "g")
			for column in range(x + 12, x + w - 6, 40):
				gfx._rect(image, column, y + 5, 7, h - 5, "k")
				gfx._rect(image, column, y + 5, 1, h - 5, "l")
				gfx._line(image, column + 7, y + 8, column + 39, y + 30, "k")
				gfx._line(image, column + 7, y + 30, column + 39, y + 8, "a")
			gfx._rect(image, x, y, w, 5, "l")
			gfx._rect(image, x, y, w, 1, "e")
			gfx._rect(image, x, y + 4, w, 1, "k")
			gfx._rect(image, x, y + 5, w, 1, "a")
			for column in range(x + 9, x + w, 11):
				gfx._rect(image, column, y + 1, 1, 3, "k")
			gfx._rect(image, x, y, 1, 6, "0")
			gfx._rect(image, x + w - 1, y, 1, 6, "0")
			_props(gfx, image, theme, x, y, w)

static func _props(gfx: Variant, image: Image, theme: int, x: int, y: int, w: int) -> void:
	for column in range(x + 10, x + w - 14, 16):
		var roll := noise(column, y * 7 + theme)
		if roll % 6 != 0:
			continue
		match (roll / 6) % 3 + theme * 3:
			0:
				# An aerial with a warning light.
				gfx._rect(image, column, y - 22, 1, 22, "g")
				gfx._rect(image, column - 3, y - 17, 7, 1, "g")
				gfx._rect(image, column - 2, y - 12, 5, 1, "g")
				gfx._px(image, column, y - 23, "c")
			1:
				gfx._plate(image, column - 5, y - 8, 11, 8, "j", "i", "h")
				gfx._rect(image, column - 3, y - 6, 7, 1, "g")
				gfx._rect(image, column - 3, y - 4, 7, 1, "g")
			2:
				for blade in 3:
					gfx._line(image, column + blade * 2, y - 1, column + blade * 3 - 2, y - 6 - blade, "8")
			6:
				gfx._plate(image, column - 3, y - 6, 6, 6, "j", "h", "g")
				gfx._rect(image, column - 4, y - 7, 8, 2, "i")
			7:
				gfx._rect(image, column, y - 30, 2, 30, "h")
				gfx._rect(image, column - 5, y - 31, 7, 2, "h")
				gfx._rect(image, column - 6, y - 29, 4, 2, "f")
				gfx._px(image, column - 5, y - 27, "e")
			_:
				gfx._plate(image, column - 4, y - 10, 9, 10, "d", "c", "b")
				gfx._rect(image, column - 4, y - 7, 9, 1, "a")
				gfx._rect(image, column - 4, y - 3, 9, 1, "a")

static func _block(gfx: Variant, image: Image, theme: int, x: int, y: int, w: int, h: int) -> void:
	match theme:
		0:
			# Rooftop plant: a vented housing.
			gfx._plate(image, x, y, w, h, "j", "i", "h")
			for row in range(y + 6, y + h - 4, 4):
				gfx._rect(image, x + 5, row, w - 10, 1, "g")
				gfx._rect(image, x + 5, row + 1, w - 10, 1, "h")
			gfx._rivets(image, x + 2, y + 2, w - 4, h - 4, 8, "5")
			for column in range(x, x + w - 1, 4):
				if noise(column, y) % 3 == 0:
					gfx._rect(image, column, y, 2, 1 + noise(column, y + 1) % 3, "8")
			gfx._rect(image, x, y + h - 1, w, 1, "g")
			gfx._rect(image, x, y, 1, h, "0")
			gfx._rect(image, x + w - 1, y, 1, h, "0")
			gfx._rect(image, x, y, w, 1, "0")
		1:
			if w > T:
				# A deck across the shaft.
				gfx._rect(image, x, y, w, h, "7")
				gfx._rect(image, x, y, w, 1, "9")
				gfx._rect(image, x, y + 1, w, 2, "8")
				gfx._rect(image, x, y + 10, w, 5, "6")
				gfx._rect(image, x, y + 15, w, 1, "0")
				for column in range(x + 4, x + w, 8):
					gfx._px(image, column, y + 6, "9")
				gfx._hazard(image, x, y + 11, 6, 3, "e", "g")
				gfx._hazard(image, x + w - 6, y + 11, 6, 3, "e", "g")
				return
			# The shaft wall.
			gfx._rect(image, x, y, w, h, "6")
			gfx._rect(image, x + (w - 3 if x == 0 else 0), y, 3, h, "7")
			gfx._rect(image, x + (w - 1 if x == 0 else 0), y, 1, h, "8")
			for row in range(y, y + h, 16):
				gfx._rect(image, x, row, w, 1, "0")
				gfx._px(image, x + 5, row + 5, "8")
				gfx._px(image, x + 10, row + 11, "8")
		_:
			# Shipping containers, stacked two tiles high.
			var palettes := [["d", "c", "b"], ["8", "7", "6"], ["3", "2", "1"], ["e", "l", "k"]]
			for stack in range(0, h, 32):
				var tone: Array = palettes[noise(x + stack, y) % palettes.size()]
				var top := y + stack
				gfx._rect(image, x, top, w, 32, tone[1])
				for column in range(x + 3, x + w - 12, 4):
					gfx._rect(image, column, top + 3, 1, 26, tone[2])
					gfx._rect(image, column + 1, top + 3, 1, 26, tone[0])
				gfx._rect(image, x, top, w, 2, tone[0])
				gfx._rect(image, x, top + 30, w, 2, "g")
				gfx._rect(image, x + w - 11, top + 3, 10, 27, tone[1])
				gfx._rect(image, x + w - 9, top + 5, 1, 23, "j")
				gfx._rect(image, x + w - 5, top + 5, 1, 23, "j")
				gfx._rect(image, x + 6, top + 10, 8, 5, "5")
				gfx._rect(image, x, top, 1, 32, "0")
				gfx._rect(image, x + w - 1, top, 1, 32, "0")
				gfx._rect(image, x, top, w, 1, "0")

static func _plat(gfx: Variant, image: Image, theme: int, x: int, y: int, w: int) -> void:
	match theme:
		0:
			gfx._rect(image, x, y, w, 2, "j")
			gfx._rect(image, x, y + 2, w, 1, "i")
			gfx._rect(image, x, y + 3, w, 4, "h")
			for column in range(x, x + w, 8):
				gfx._line(image, column, y + 3, column + 3, y + 6, "g")
				gfx._line(image, column + 4, y + 6, column + 7, y + 3, "g")
			gfx._rect(image, x, y + 7, w, 1, "0")
			gfx._rect(image, x, y, 1, 8, "0")
			gfx._rect(image, x + w - 1, y, 1, 8, "0")
			gfx._rect(image, x + 3, y + 8, 2, 5, "g")
			gfx._rect(image, x + w - 5, y + 8, 2, 5, "g")
		1:
			gfx._rect(image, x, y, w, 1, "9")
			gfx._rect(image, x, y + 1, w, 2, "8")
			gfx._rect(image, x, y + 3, w, 3, "7")
			for column in range(x + 2, x + w, 4):
				gfx._px(image, column, y + 4, "0")
			gfx._rect(image, x, y + 6, w, 1, "0")
			gfx._line(image, x, y + 7, x + 6, y + 12, "6")
			gfx._line(image, x + w - 1, y + 7, x + w - 7, y + 12, "6")
			gfx._rect(image, x, y, 1, 7, "0")
			gfx._rect(image, x + w - 1, y, 1, 7, "0")
		_:
			# A crane pallet hanging on two cables.
			gfx._rect(image, x + 3, 0, 1, y, "h")
			gfx._rect(image, x + w - 4, 0, 1, y, "h")
			gfx._rect(image, x, y, w, 2, "e")
			gfx._hazard(image, x, y + 2, w, 3, "e", "g")
			gfx._rect(image, x, y + 5, w, 2, "k")
			gfx._rect(image, x, y + 7, w, 1, "0")
			gfx._rect(image, x, y, 1, 8, "0")
			gfx._rect(image, x + w - 1, y, 1, 8, "0")

# ---- the layers behind ----

## The parallax layers of a theme, far to near: [{ image, factor, y, vertical }]. A horizontal layer repeats along x and sits at `y`; a vertical one repeats along y.
static func layers(gfx: Variant, theme: int) -> Array:
	match theme:
		0:
			return [
				{"image": _dawn_clouds(gfx), "factor": 0.03, "y": 56, "vertical": false},
				{"image": _skyline(gfx, 140, "2", "3", 26, 100, 11), "factor": 0.08, "y": 66, "vertical": false},
				{"image": _skyline(gfx, 150, "1", "e", 30, 104, 29), "factor": 0.2, "y": 98, "vertical": false},
			]
		1:
			return [
				{"image": _shaft_wall(gfx), "factor": 0.3, "y": 0, "vertical": true},
				{"image": _shaft_pipes(gfx), "factor": 0.6, "y": 0, "vertical": true},
			]
		_:
			return [
				{"image": _clouds(gfx), "factor": 0.04, "y": 30, "vertical": false},
				{"image": _cranes(gfx), "factor": 0.12, "y": 70, "vertical": false},
				{"image": _stacks(gfx), "factor": 0.3, "y": 150, "vertical": false},
			]

## Long streaks of cloud catching the first light.
static func _dawn_clouds(gfx: Variant) -> Image:
	var image := Image.create(480, 100, false, Image.FORMAT_RGBA8)
	for index in 9:
		var roll := noise(index, 17)
		var x := roll % 480
		var y := 6 + (roll / 512) % 80
		var w := 50 + (roll / 4096) % 70
		for copy: int in [-480, 0, 480]:
			gfx._rect(image, x + copy, y, w, 3, "4")
			gfx._rect(image, x + copy + 8, y - 2, w - 24, 2, "4")
			gfx._rect(image, x + copy + 14, y + 3, w - 30, 1, "4")
			gfx._rect(image, x + copy + 10, y - 2, w - 30, 1, "5")
			gfx._rect(image, x + copy + 4, y + 2, w - 12, 1, "3")
	return image

static func _skyline(gfx: Variant, height: int, body: String, light: String, low: int, high: int, salt: int) -> Image:
	var image := Image.create(480, height, false, Image.FORMAT_RGBA8)
	var x := 0
	var index := 0
	while x < 480:
		var roll := noise(index, salt)
		var w := mini(480 - x, 22 + roll % 40)
		if 480 - x - w < 16:
			w = 480 - x
		var h := mini(height, low + (roll / 64) % (high - low))
		var top := height - h
		gfx._rect(image, x, top, w - 2, h, body)
		# A broken or stepped roofline.
		if roll % 3 == 0:
			gfx._rect(image, x + 4, top - 8, maxi(4, w / 3), 8, body)
		if roll % 4 == 1:
			gfx._rect(image, x + w / 2, top - 16, 1, 16, body)
		for row in range(top + 5, height - 4, 9):
			for column in range(x + 3, x + w - 6, 7):
				if noise(column, row + salt) % 9 == 0:
					gfx._rect(image, column, row, 3, 4, light)
		x += w
		index += 1
	return image

static func _shaft_wall(gfx: Variant) -> Image:
	var image := Image.create(480, 256, false, Image.FORMAT_RGBA8)
	gfx._rect(image, 0, 0, 480, 256, "0")
	for row in 4:
		for column in 8:
			var x := column * 60 + (30 if row % 2 == 1 else 0) - 30
			gfx._plate(image, x + 1, row * 64 + 1, 58, 62, "2", "1", "0")
			gfx._px(image, x + 5, row * 64 + 5, "2")
			gfx._px(image, x + 54, row * 64 + 5, "2")
			gfx._px(image, x + 5, row * 64 + 58, "2")
			gfx._px(image, x + 54, row * 64 + 58, "2")
	# Two portholes with daylight behind them.
	for porthole: Vector2i in [Vector2i(120, 90), Vector2i(360, 210)]:
		gfx._ball(image, porthole.x, porthole.y, 15, "j", "h", "g")
		gfx._ball(image, porthole.x, porthole.y, 11, "4", "3", "2")
		gfx._rect(image, porthole.x - 11, porthole.y, 23, 1, "g")
		gfx._rect(image, porthole.x, porthole.y - 11, 1, 23, "g")
	return image

static func _shaft_pipes(gfx: Variant) -> Image:
	var image := Image.create(480, 320, false, Image.FORMAT_RGBA8)
	for pipe: Vector2i in [Vector2i(52, 12), Vector2i(150, 8), Vector2i(292, 14), Vector2i(404, 9)]:
		gfx._rect(image, pipe.x, 0, pipe.y, 320, "6")
		gfx._rect(image, pipe.x, 0, 2, 320, "7")
		gfx._rect(image, pipe.x + pipe.y - 2, 0, 2, 320, "0")
		for row in range(20, 320, 80):
			gfx._rect(image, pipe.x - 2, row, pipe.y + 4, 5, "7")
			gfx._rect(image, pipe.x - 2, row + 5, pipe.y + 4, 1, "0")
	gfx._rect(image, 150, 150, 142, 8, "6")
	gfx._rect(image, 150, 150, 142, 2, "7")
	gfx._rect(image, 150, 157, 142, 1, "0")
	# The valve wheel is the pipes' own green: red is kept for things that hurt.
	gfx._ball(image, 222, 154, 9, "8", "7", "6")
	gfx._ball(image, 222, 154, 3, "j", "h", "g")
	return image

static func _clouds(gfx: Variant) -> Image:
	var image := Image.create(480, 120, false, Image.FORMAT_RGBA8)
	for index in 26:
		var roll := noise(index, 91)
		var cx := roll % 480
		var cy := 20 + (roll / 512) % 70
		var radius := 12 + (roll / 4096) % 18
		for copy: int in [-480, 0, 480]:
			gfx._ball(image, cx + copy, cy, radius, "1", "1", "1")
			gfx._rect(image, cx + copy - radius, cy + radius / 3, radius * 2, radius, "1")
	return image

static func _cranes(gfx: Variant) -> Image:
	var image := Image.create(480, 160, false, Image.FORMAT_RGBA8)
	for crane: Vector2i in [Vector2i(70, 30), Vector2i(250, 10), Vector2i(400, 44)]:
		# A lattice tower with a jib.
		gfx._rect(image, crane.x, crane.y, 2, 160 - crane.y, "1")
		gfx._rect(image, crane.x + 12, crane.y, 2, 160 - crane.y, "1")
		for row in range(crane.y, 160, 12):
			gfx._line(image, crane.x, row, crane.x + 12, row + 12, "1")
			gfx._line(image, crane.x + 12, row, crane.x, row + 12, "1")
		gfx._rect(image, crane.x - 30, crane.y, 110, 3, "1")
		gfx._line(image, crane.x + 6, crane.y - 16, crane.x + 78, crane.y, "1")
		gfx._line(image, crane.x + 6, crane.y - 16, crane.x - 28, crane.y, "1")
		gfx._rect(image, crane.x + 5, crane.y - 16, 3, 16, "1")
		gfx._rect(image, crane.x + 60, crane.y + 3, 1, 34, "1")
		gfx._rect(image, crane.x + 57, crane.y + 37, 7, 5, "1")
		gfx._px(image, crane.x + 6, crane.y - 17, "c")
	# A freighter at anchor.
	gfx._rect(image, 120, 132, 110, 28, "1")
	gfx._rect(image, 190, 112, 30, 20, "1")
	gfx._rect(image, 200, 100, 6, 12, "1")
	for column in range(194, 218, 6):
		gfx._px(image, column, 118, "e")
	return image

static func _stacks(gfx: Variant) -> Image:
	var image := Image.create(480, 110, false, Image.FORMAT_RGBA8)
	var x := 0
	var index := 0
	while x < 480:
		var roll := noise(index, 53)
		var w := mini(480 - x, 36 + roll % 28)
		var tiers := 1 + (roll / 32) % 4
		for tier in tiers:
			var top := 110 - (tier + 1) * 20
			gfx._rect(image, x, top, w - 3, 19, "g" if (tier + index) % 2 == 0 else "a")
			gfx._rect(image, x, top, w - 3, 1, "h")
			for column in range(x + 3, x + w - 6, 5):
				gfx._rect(image, column, top + 3, 1, 13, "0")
		if roll % 5 == 0:
			gfx._px(image, x + 4, 110 - tiers * 20 - 2, "e")
		x += w
		index += 1
	return image
