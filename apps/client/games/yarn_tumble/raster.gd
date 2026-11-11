extends RefCounted

## A few pixel-drawing helpers for building sprites and backdrops into an Image. Everything clips to the image.

static func blank(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image

static func dot(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, color)

static func box(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in range(maxi(0, y), mini(image.get_height(), y + height)):
		for px in range(maxi(0, x), mini(image.get_width(), x + width)):
			image.set_pixel(px, py, color)

## Like box, but only over pixels that are already painted.
static func repaint(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in range(maxi(0, y), mini(image.get_height(), y + height)):
		for px in range(maxi(0, x), mini(image.get_width(), x + width)):
			if image.get_pixel(px, py).a > 0.0:
				image.set_pixel(px, py, color)

static func disc(image: Image, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	for py in range(int(floor(cy - ry)), int(ceil(cy + ry)) + 1):
		for px in range(int(floor(cx - rx)), int(ceil(cx + rx)) + 1):
			var dx := (px - cx) / rx
			var dy := (py - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				dot(image, px, py, color)

static func line(image: Image, x0: float, y0: float, x1: float, y1: float, color: Color) -> void:
	var steps := int(maxf(absf(x1 - x0), absf(y1 - y0))) + 1
	for index in steps + 1:
		var t := float(index) / float(steps)
		dot(image, roundi(lerpf(x0, x1, t)), roundi(lerpf(y0, y1, t)), color)

## Paint every transparent pixel that touches an opaque one.
static func outline(image: Image, color: Color) -> void:
	var source := image.duplicate() as Image
	for py in image.get_height():
		for px in image.get_width():
			if source.get_pixel(px, py).a > 0.0:
				continue
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := px + offset.x
				var ny := py + offset.y
				if nx >= 0 and ny >= 0 and nx < source.get_width() and ny < source.get_height() and source.get_pixel(nx, ny).a > 0.0:
					image.set_pixel(px, py, color)
					break

## An image from rows of palette characters; a character missing from the palette is transparent.
static func from_rows(rows: Array, palette: Dictionary) -> Image:
	var image := blank(str(rows[0]).length(), rows.size())
	for py in rows.size():
		var row := str(rows[py])
		for px in mini(row.length(), image.get_width()):
			var key := row[px]
			if palette.has(key):
				image.set_pixel(px, py, palette[key])
	return image

## A stable pseudo-random value in [0, 1) for a pixel, for texture grain that is the same on every run.
static func grain(x: int, y: int, salt: int = 0) -> float:
	var value := (x * 374761393 + y * 668265263 + salt * 144665) & 0x7FFFFFFF
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(value & 0xFFFF) / 65536.0
