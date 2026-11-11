extends RefCounted

## The scrolling backgrounds, drawn here by code: for each stage a far wall and a nearer layer of silhouettes, both 256 x 256 and made to repeat in every direction, so the renderer can slide them at different speeds behind the tiles.

const SIZE := 256

## Build the two layers of a stage: { "far": ImageTexture, "near": ImageTexture }.
func build(stage: int) -> Dictionary:
	var far := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var near := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	match stage:
		0: _workbench(far, near)
		1: _pipe_shaft(far, near)
		2: _foundry(far, near)
		_: _control_loft(far, near)
	return {"far": ImageTexture.create_from_image(far), "near": ImageTexture.create_from_image(near), "far_image": far, "near_image": near}

# ---- drawing that wraps round the edges ----

func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for offset_x: int in [0, -SIZE, SIZE]:
		for offset_y: int in [0, -SIZE, SIZE]:
			var area := Rect2i(x + offset_x, y + offset_y, width, height).intersection(Rect2i(0, 0, SIZE, SIZE))
			if area.size.x > 0 and area.size.y > 0:
				image.fill_rect(area, color)

func _dot(image: Image, x: int, y: int, color: Color) -> void:
	image.set_pixel(posmod(x, SIZE), posmod(y, SIZE), color)

func _disc(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for y in range(-radius, radius + 1):
		var span := int(sqrt(float(radius * radius - y * y)))
		_rect(image, cx - span, cy + y, span * 2 + 1, 1, color)

func _ring(image: Image, cx: int, cy: int, radius: int, thickness: int, color: Color, inside: Color) -> void:
	_disc(image, cx, cy, radius, color)
	_disc(image, cx, cy, radius - thickness, inside)

func _gear(image: Image, cx: int, cy: int, radius: int, teeth: int, color: Color, inside: Color) -> void:
	for tooth in teeth:
		var angle := TAU * float(tooth) / float(teeth)
		var tx := cx + int(cos(angle) * float(radius + 2))
		var ty := cy + int(sin(angle) * float(radius + 2))
		_rect(image, tx - 3, ty - 3, 7, 7, color)
	_disc(image, cx, cy, radius, color)
	_disc(image, cx, cy, radius / 3, inside)

# ---- stage 1: a pegboard wall hung with giant tools ----

func _workbench(far: Image, near: Image) -> void:
	var wall := Color("202437")
	var hole := Color("181b2b")
	var tool := Color("2b3150")
	var edge := Color("394166")
	far.fill(wall)
	for y in range(4, SIZE, 8):
		for x in range(4, SIZE, 8):
			_dot(far, x, y, hole)
	# A spanner.
	_rect(far, 30, 46, 12, 96, tool)
	_rect(far, 30, 46, 2, 96, edge)
	_ring(far, 36, 34, 17, 7, tool, wall)
	_rect(far, 31, 10, 10, 16, wall)
	_ring(far, 36, 150, 11, 5, tool, wall)
	# A hammer.
	_rect(far, 112, 70, 9, 120, tool)
	_rect(far, 112, 70, 2, 120, edge)
	_rect(far, 92, 52, 50, 20, tool)
	_rect(far, 92, 52, 50, 3, edge)
	_rect(far, 86, 56, 8, 12, tool)
	# A saw.
	_rect(far, 184, 24, 34, 110, tool)
	_rect(far, 184, 24, 3, 110, edge)
	for tooth in range(24, 134, 6):
		_rect(far, 218, tooth, 3, 3, tool)
	_ring(far, 201, 152, 20, 8, tool, wall)
	# A shelf with jars along the bottom of the tile.
	_rect(far, 0, 214, SIZE, 6, Color("332c3f"))
	_rect(far, 0, 214, SIZE, 1, Color("4a3f57"))
	for jar in 6:
		var x := 14 + jar * 43
		var tall := 22 + (jar * 7) % 12
		_rect(far, x, 214 - tall, 18, tall, Color("27304a"))
		_rect(far, x + 2, 214 - tall + 3, 3, tall - 6, Color("3a4870"))
		_rect(far, x - 1, 214 - tall - 3, 20, 4, Color("3b3350"))
	# Nearer: hanging lamps with a warm pool of light, and a sagging cable.
	var dark := Color("12131f")
	for lamp in 2:
		var x := 60 + lamp * 128
		var drop := 36 + lamp * 22
		_disc(near, x, drop + 20, 34, Color(1.0, 0.82, 0.42, 0.07))
		_disc(near, x, drop + 16, 20, Color(1.0, 0.82, 0.42, 0.1))
		_rect(near, x, 0, 1, drop, dark)
		_rect(near, x - 8, drop, 17, 3, dark)
		_rect(near, x - 5, drop - 4, 11, 4, dark)
		_rect(near, x - 3, drop + 3, 7, 3, Color("ffe6a0"))
	for step in SIZE:
		var sag := int(sin(float(step) / float(SIZE) * PI) * 14.0)
		_dot(near, step, 150 + sag, dark)
		_dot(near, step, 151 + sag, dark)

# ---- stage 2: the inside of a shaft full of pipes ----

func _pipe_shaft(far: Image, near: Image) -> void:
	var wall := Color("13252d")
	far.fill(wall)
	for y in range(0, SIZE, 32):
		_rect(far, 0, y, SIZE, 1, Color("0f1e25"))
		for x in range((y / 32 % 2) * 32, SIZE, 64):
			_rect(far, x, y, 1, 32, Color("0f1e25"))
	for pipe: Array in [[18, 30], [98, 42], [184, 24]]:
		var x := int(pipe[0])
		var wide := int(pipe[1])
		_rect(far, x, 0, wide, SIZE, Color("1c3843"))
		_rect(far, x + 2, 0, wide / 5, SIZE, Color("275060"))
		_rect(far, x + wide - wide / 4, 0, wide / 4, SIZE, Color("142a33"))
		for y: int in [40, 168]:
			_rect(far, x - 3, y, wide + 6, 9, Color("23475a"))
			_rect(far, x - 3, y, wide + 6, 2, Color("2f6074"))
			_rect(far, x - 3, y + 7, wide + 6, 2, Color("142a33"))
	var dark := Color("0b161b")
	_rect(near, 0, 58, SIZE, 7, dark)
	_rect(near, 0, 58, SIZE, 1, Color("16303a"))
	_rect(near, 150, 0, 7, SIZE, dark)
	_rect(near, 150, 0, 1, SIZE, Color("16303a"))
	_ring(near, 153, 61, 12, 3, dark, Color(0, 0, 0, 0))
	_rect(near, 141, 60, 25, 3, dark)
	_rect(near, 152, 49, 3, 25, dark)
	_rect(near, 0, 196, 120, 5, dark)
	_rect(near, 118, 196, 5, 60, dark)
	for drip in 5:
		_rect(near, 30 + drip * 21, 201, 1, 3 + (drip * 5) % 7, Color("2f6074"))

# ---- stage 3: furnace windows, big wheels and chains ----

func _foundry(far: Image, near: Image) -> void:
	var wall := Color("27151f")
	far.fill(wall)
	for y in range(0, SIZE, 16):
		_rect(far, 0, y, SIZE, 1, Color("1f1018"))
	_gear(far, 60, 70, 40, 12, Color("38202c"), wall)
	_gear(far, 60, 70, 12, 6, Color("452838"), Color("38202c"))
	_gear(far, 196, 150, 30, 10, Color("38202c"), wall)
	for window in 2:
		var x := 132 + window * 68
		_rect(far, x, 28, 40, 54, Color("3d1c1c"))
		_rect(far, x + 3, 31, 34, 48, Color("8a3620"))
		_rect(far, x + 6, 44, 28, 32, Color("d0642a"))
		_rect(far, x + 10, 58, 20, 18, Color("f2a13c"))
		for bar in 3:
			_rect(far, x + 3 + bar * 12, 31, 3, 48, Color("3d1c1c"))
	_rect(far, 0, 226, SIZE, 30, Color("331a20"))
	_rect(far, 0, 226, SIZE, 2, Color("5a2a26"))
	for glow in 8:
		_rect(far, glow * 32 + 6, 236, 18, 6, Color("8a3620"))
	var dark := Color("14090e")
	_rect(near, 0, 18, SIZE, 4, dark)
	_rect(near, 0, 44, SIZE, 4, dark)
	for brace in 8:
		var x := brace * 32
		for step in 22:
			_dot(near, x + step * 32 / 22, 22 + step, dark)
			_dot(near, x + step * 32 / 22 + 1, 22 + step, dark)
			_dot(near, x + 32 - step * 32 / 22, 22 + step, dark)
			_dot(near, x + 31 - step * 32 / 22, 22 + step, dark)
	for chain: Array in [[40, 150], [172, 110]]:
		var x := int(chain[0])
		var length := int(chain[1])
		for link in range(48, 48 + length, 6):
			_rect(near, x, link, 3, 4, dark)
			_rect(near, x + 1, link + 4, 1, 2, dark)
		_ring(near, x + 1, 48 + length + 8, 7, 2, dark, Color(0, 0, 0, 0))
		_rect(near, x - 6, 48 + length, 8, 8, Color(0, 0, 0, 0))

# ---- stage 4: tall night windows over banks of blinking lights ----

func _control_loft(far: Image, near: Image) -> void:
	var wall := Color("171634")
	far.fill(wall)
	for y in range(0, SIZE, 64):
		_rect(far, 0, y, SIZE, 2, Color("11102a"))
	for window in 2:
		var x := 22 + window * 128
		_rect(far, x - 4, 20, 88, 132, Color("2a2958"))
		_rect(far, x, 24, 80, 124, Color("0b0a20"))
		for star in 14:
			_dot(far, x + 4 + (star * 37 + window * 11) % 72, 28 + (star * 53 + window * 29) % 112, Color("c9c7f0"))
		if window == 0:
			_disc(far, x + 56, 52, 11, Color("ece8c4"))
			_disc(far, x + 61, 49, 9, Color("0b0a20"))
		_rect(far, x + 38, 24, 4, 124, Color("2a2958"))
		_rect(far, x, 84, 80, 4, Color("2a2958"))
	_rect(far, 0, 186, SIZE, 50, Color("201f47"))
	_rect(far, 0, 186, SIZE, 2, Color("34336c"))
	var lights := [Color("5fd4c4"), Color("f5a340"), Color("e5484d"), Color("ffd75e")]
	for light in 40:
		_rect(far, 8 + (light * 29) % 240, 194 + (light * 13) % 36, 3, 2, (lights[light % 4] as Color).darkened(0.35))
	for dial in 4:
		_ring(far, 30 + dial * 64, 212, 9, 2, Color("34336c"), Color("171634"))
	var dark := Color("0b0a1c")
	for step in SIZE:
		var sag := int(sin(float(step) / float(SIZE) * PI) * 26.0)
		_dot(near, step, 8 + sag, dark)
		_dot(near, step, 9 + sag, dark)
		var sag_two := int(sin(float(step) / float(SIZE) * TAU) * 10.0)
		_dot(near, step, 120 + sag_two, dark)
	for screen in 2:
		var x := 70 + screen * 120
		_rect(near, x + 8, 0, 2, 40 + screen * 30, dark)
		_rect(near, x, 40 + screen * 30, 20, 14, dark)
		_rect(near, x + 2, 42 + screen * 30, 16, 9, Color("1d4a52"))
		_rect(near, x + 4, 45 + screen * 30, 8, 1, Color("5fd4c4"))
		_rect(near, x + 4, 48 + screen * 30, 11, 1, Color("5fd4c4"))
