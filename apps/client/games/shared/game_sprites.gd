class_name GameSprites
extends RefCounted

## High-resolution art for a game module: one texture cut into named frames, drawn at stage coordinates. The art is authored large (a 256 px character) and drawn small (32 stage pixels); every frame knows how many stage pixels one of its source pixels is worth, so a game places and sizes art in the same logical coordinates as everything else and never does that arithmetic itself.
##
## DIR below stands for the full resource path of the game's own directory, written out in the game.
##   var hero := GameSprites.load_atlas(DIR + "art/hero.json")       # made by scripts/assets/assets.py pack
##   var sky := GameSprites.load_image(DIR + "art/sky.jpg", {"height": 270})
##   func _draw() -> void:
##       sky.draw_fit(self, "main", Rect2(Vector2.ZERO, Vector2(stage_size)))
##       hero.draw_animation(self, "run", elapsed, hero_position, facing_left)
##
## A frame is drawn with its pivot at the position given (the feet of a character, the centre of a pickup), at its natural size times `zoom`. Frames that the packer trimmed keep their place: the pivot and the size are those of the untrimmed picture.
##
## Filtering. Art drawn smaller than it was authored needs mipmaps or it shimmers; the host draws a stage that is not pixel art with FILTER (linear with mipmaps), and the project's import defaults generate mipmaps for every newly imported texture (docs/20-adding-a-game.md). None of this is for pixel-art stages, which stay nearest-neighbour.
##
## The frame table (JSON, next to the image):
##   { "format": 1, "image": "hero.png", "scale": 0.125,
##     "frames": { "run_0": { "rect": [x, y, w, h], "source": [w, h], "offset": [x, y], "pivot": [x, y] } },
##     "animations": { "run": { "frames": ["run_0", "run_1"], "fps": 10, "loop": true } } }
## `rect` is where the (trimmed) frame sits in the image; `source` the size of the untrimmed picture, `offset` where the trimmed part sits inside it and `pivot` the anchor inside it, all in source pixels; `scale` is stage pixels per source pixel, for the sheet or (inside a frame) for that frame alone.

## The texture filter for high-resolution art on a canvas item.
const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const FORMAT := 1

var texture: Texture2D
## Stage pixels per source pixel, unless a frame says otherwise.
var scale := 1.0

var _frames: Dictionary = {}
var _animations: Dictionary = {}

# ---- loading ----

## Load a packed atlas from its frame table. Returns an empty sheet (has_frame() is false for everything, drawing does nothing) and reports the reason when the table or the image cannot be loaded, so a missing file never crashes a game.
static func load_atlas(table_path: String) -> GameSprites:
	var sheet := GameSprites.new()
	if not FileAccess.file_exists(table_path):
		push_error("GameSprites: no frame table at %s" % table_path)
		return sheet
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(table_path))
	if not parsed is Dictionary or not (parsed as Dictionary).get("frames") is Dictionary or not (parsed as Dictionary).get("image") is String:
		push_error("GameSprites: %s is not a frame table" % table_path)
		return sheet
	var table: Dictionary = parsed
	sheet.texture = _load_texture(table_path.get_base_dir().path_join(str(table["image"])))
	if sheet.texture == null:
		return sheet
	sheet.scale = maxf(0.0001, float(table.get("scale", 1.0)))
	for frame_name: String in table["frames"]:
		var entry: Variant = table["frames"][frame_name]
		if not entry is Dictionary or not _is_numbers(entry.get("rect"), 4):
			push_error("GameSprites: frame \"%s\" of %s has no rect" % [frame_name, table_path])
			continue
		var rect := Rect2(float(entry["rect"][0]), float(entry["rect"][1]), float(entry["rect"][2]), float(entry["rect"][3]))
		var source := Vector2(float(entry["source"][0]), float(entry["source"][1])) if _is_numbers(entry.get("source"), 2) else rect.size
		var offset := Vector2(float(entry["offset"][0]), float(entry["offset"][1])) if _is_numbers(entry.get("offset"), 2) else Vector2.ZERO
		var pivot := Vector2(float(entry["pivot"][0]), float(entry["pivot"][1])) if _is_numbers(entry.get("pivot"), 2) else source * 0.5
		sheet._frames[frame_name] = {"rect": rect, "source": source, "offset": offset, "pivot": pivot, "scale": maxf(0.0001, float(entry.get("scale", sheet.scale)))}
	if table.get("animations") is Dictionary:
		for animation: String in table["animations"]:
			var entry: Variant = table["animations"][animation]
			if entry is Dictionary and entry.get("frames") is Array:
				sheet.define_animation(animation, entry["frames"], float(entry.get("fps", 10.0)), bool(entry.get("loop", true)))
	return sheet

## Load one image as a sheet with a single frame, "main". `options`: { "scale": stage pixels per source pixel } or { "height": stage pixels the picture is tall } or { "width": ... } (default: scale 1), and { "pivot": Vector2 as a fraction of the picture } (default the centre, Vector2(0.5, 0.5); Vector2(0.5, 1) is the middle of the bottom edge).
static func load_image(image_path: String, options: Dictionary = {}) -> GameSprites:
	return load_grid(image_path, 1, 1, options)

## Load an image that is a grid of equal cells, read row by row: frames "0", "1", ... (or "main" for a single cell). `options` as in load_image, where "height" and "width" are those of one cell, plus { "count": how many cells are used (default all) }.
static func load_grid(image_path: String, columns: int, rows: int, options: Dictionary = {}) -> GameSprites:
	var sheet := GameSprites.new()
	sheet.texture = _load_texture(image_path)
	if sheet.texture == null or columns < 1 or rows < 1:
		return sheet
	var cell := sheet.texture.get_size() / Vector2(columns, rows)
	if options.has("scale"):
		sheet.scale = maxf(0.0001, float(options["scale"]))
	elif options.has("height"):
		sheet.scale = float(options["height"]) / cell.y
	elif options.has("width"):
		sheet.scale = float(options["width"]) / cell.x
	var pivot: Vector2 = options["pivot"] if options.get("pivot") is Vector2 else Vector2(0.5, 0.5)
	var count := clampi(int(options.get("count", columns * rows)), 1, columns * rows)
	for index in count:
		@warning_ignore("integer_division")
		var rect := Rect2(Vector2(index % columns, index / columns) * cell, cell)
		sheet._frames["main" if columns * rows == 1 else str(index)] = {"rect": rect, "source": cell, "offset": Vector2.ZERO, "pivot": cell * pivot, "scale": sheet.scale}
	return sheet

# ---- frames ----

func has_frame(frame: String) -> bool:
	return _frames.has(frame)

func frame_names() -> PackedStringArray:
	var out := PackedStringArray()
	for frame: String in _frames:
		out.append(frame)
	return out

## Size of a frame on the stage, in stage pixels (the untrimmed picture at zoom 1). Zero for an unknown frame.
func size(frame: String) -> Vector2:
	if not _frames.has(frame):
		return Vector2.ZERO
	return (_frames[frame]["source"] as Vector2) * float(_frames[frame]["scale"])

## Where a frame's pixels land on the stage when it is drawn at `at`: the rectangle of the untrimmed picture.
func bounds(frame: String, at: Vector2, zoom: float = 1.0) -> Rect2:
	if not _frames.has(frame):
		return Rect2(at, Vector2.ZERO)
	var entry: Dictionary = _frames[frame]
	var factor := float(entry["scale"]) * zoom
	return Rect2(at - (entry["pivot"] as Vector2) * factor, (entry["source"] as Vector2) * factor)

## A texture of one frame alone, for a Sprite2D, a TextureRect or a particle. It has the size of the untrimmed picture in source pixels: scale the node by `scale` to bring it to stage size.
func frame_texture(frame: String) -> AtlasTexture:
	if not _frames.has(frame):
		return null
	var entry: Dictionary = _frames[frame]
	var out := AtlasTexture.new()
	out.atlas = texture
	out.region = entry["rect"]
	var rect: Rect2 = entry["rect"]
	var source: Vector2 = entry["source"]
	var offset: Vector2 = entry["offset"]
	out.margin = Rect2(offset, source - rect.size)
	return out

# ---- animation ----

## Name an animation: a list of frames shown at `fps`, repeating or holding its last frame.
func define_animation(animation: String, frames: Array, fps: float = 10.0, loop: bool = true) -> void:
	var listed := PackedStringArray()
	for frame: Variant in frames:
		listed.append(str(frame))
	_animations[animation] = {"frames": listed, "fps": maxf(0.01, fps), "loop": loop}

func has_animation(animation: String) -> bool:
	return _animations.has(animation)

## Seconds one pass of an animation takes.
func animation_length(animation: String) -> float:
	if not _animations.has(animation):
		return 0.0
	return float((_animations[animation]["frames"] as PackedStringArray).size()) / float(_animations[animation]["fps"])

## The frame an animation shows `seconds` after it started. Feed it the module's `elapsed` (or a timer of your own that the simulation advances), never the wall clock, and a paused game holds its pose.
func animation_frame(animation: String, seconds: float) -> String:
	if not _animations.has(animation):
		return ""
	var entry: Dictionary = _animations[animation]
	var frames: PackedStringArray = entry["frames"]
	if frames.is_empty():
		return ""
	var index := int(floor(maxf(0.0, seconds) * float(entry["fps"])))
	return frames[index % frames.size() if bool(entry["loop"]) else mini(index, frames.size() - 1)]

# ---- drawing ----

## Draw a frame with its pivot at `at`. Call it from the _draw() of `canvas`. `zoom` scales it about the pivot, `rotation` (radians) turns it about the pivot, `flip_h` / `flip_v` mirror it about the pivot. A rotated draw sets the canvas item's draw transform and puts it back to identity afterwards.
func draw(canvas: CanvasItem, frame: String, at: Vector2, flip_h: bool = false, zoom: float = 1.0, rotation: float = 0.0, modulate: Color = Color.WHITE, flip_v: bool = false) -> void:
	if not _frames.has(frame):
		return
	var entry: Dictionary = _frames[frame]
	var factor := float(entry["scale"]) * zoom
	var rect: Rect2 = entry["rect"]
	var corner: Vector2 = (entry["offset"] as Vector2) - (entry["pivot"] as Vector2)
	# Mirroring moves the trimmed part to the other side of the pivot.
	if flip_h:
		corner.x = (entry["pivot"] as Vector2).x - (entry["offset"] as Vector2).x - rect.size.x
	if flip_v:
		corner.y = (entry["pivot"] as Vector2).y - (entry["offset"] as Vector2).y - rect.size.y
	var extent := rect.size * factor
	# A negative size is how a canvas rectangle is told to mirror its texture; it stays where its position says.
	var target := Rect2(corner * factor, Vector2(-extent.x if flip_h else extent.x, -extent.y if flip_v else extent.y))
	if rotation == 0.0:
		target.position += at
		canvas.draw_texture_rect_region(texture, target, rect, modulate)
		return
	canvas.draw_set_transform(at, rotation, Vector2.ONE)
	canvas.draw_texture_rect_region(texture, target, rect, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Draw the frame an animation shows at `seconds`.
func draw_animation(canvas: CanvasItem, animation: String, seconds: float, at: Vector2, flip_h: bool = false, zoom: float = 1.0, rotation: float = 0.0, modulate: Color = Color.WHITE) -> void:
	draw(canvas, animation_frame(animation, seconds), at, flip_h, zoom, rotation, modulate)

## Draw a frame stretched to fill `rect` (stage coordinates), whatever its natural size: a background, a tile on a grid, a bar.
func draw_fit(canvas: CanvasItem, frame: String, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	if not _frames.has(frame):
		return
	var entry: Dictionary = _frames[frame]
	var region: Rect2 = entry["rect"]
	var source: Vector2 = entry["source"]
	var ratio := rect.size / source
	canvas.draw_texture_rect_region(texture, Rect2(rect.position + (entry["offset"] as Vector2) * ratio, region.size * ratio), region, modulate)

## Fill `rect` with repeats of a frame, each `tile_size` stage pixels (default: the frame's natural size), cut off at the edges of `rect`. `scroll` shifts the pattern (a scrolling floor or a parallax layer passes its camera offset). The frame should be untrimmed and made to repeat seamlessly.
func draw_tiled(canvas: CanvasItem, frame: String, rect: Rect2, tile_size: Vector2 = Vector2.ZERO, scroll: Vector2 = Vector2.ZERO, modulate: Color = Color.WHITE) -> void:
	if not _frames.has(frame) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var entry: Dictionary = _frames[frame]
	var region: Rect2 = entry["rect"]
	var tile := tile_size if tile_size.x > 0.0 and tile_size.y > 0.0 else region.size * float(entry["scale"])
	var per_pixel := region.size / tile
	var start := Vector2(fposmod(scroll.x, tile.x), fposmod(scroll.y, tile.y))
	var y := rect.position.y - start.y
	while y < rect.end.y:
		var top := maxf(y, rect.position.y)
		var bottom := minf(y + tile.y, rect.end.y)
		var x := rect.position.x - start.x
		while x < rect.end.x:
			var left := maxf(x, rect.position.x)
			var right := minf(x + tile.x, rect.end.x)
			if right > left and bottom > top:
				canvas.draw_texture_rect_region(texture, Rect2(left, top, right - left, bottom - top), Rect2(region.position + Vector2(left - x, top - y) * per_pixel, Vector2(right - left, bottom - top) * per_pixel), modulate)
			x += tile.x
		y += tile.y

## Draw a frame as a nine-patch over `rect`: the four corners keep their size, the edges stretch one way and the middle both ways (a panel, a speech bubble, a bar). `margin` is the width of the border in source pixels (left, top, right, bottom the same; pass a Vector4 as `margins` for different ones).
func draw_patch(canvas: CanvasItem, frame: String, rect: Rect2, margin: float, modulate: Color = Color.WHITE, margins: Vector4 = Vector4.ZERO) -> void:
	if not _frames.has(frame):
		return
	var entry: Dictionary = _frames[frame]
	var region: Rect2 = entry["rect"]
	var border := margins if margins != Vector4.ZERO else Vector4(margin, margin, margin, margin)
	var factor := float(entry["scale"])
	var source_x := [0.0, border.x, region.size.x - border.z, region.size.x]
	var source_y := [0.0, border.y, region.size.y - border.w, region.size.y]
	# Borders shrink together when the rectangle is too small to hold them.
	var squeeze := minf(1.0, minf(rect.size.x / maxf(0.001, (border.x + border.z) * factor), rect.size.y / maxf(0.001, (border.y + border.w) * factor)))
	var target_x := [0.0, border.x * factor * squeeze, rect.size.x - border.z * factor * squeeze, rect.size.x]
	var target_y := [0.0, border.y * factor * squeeze, rect.size.y - border.w * factor * squeeze, rect.size.y]
	for row in 3:
		for column in 3:
			var part := Rect2(source_x[column], source_y[row], source_x[column + 1] - source_x[column], source_y[row + 1] - source_y[row])
			var place := Rect2(target_x[column], target_y[row], target_x[column + 1] - target_x[column], target_y[row + 1] - target_y[row])
			if part.size.x > 0.0 and part.size.y > 0.0 and place.size.x > 0.0 and place.size.y > 0.0:
				canvas.draw_texture_rect_region(texture, Rect2(rect.position + place.position, place.size), Rect2(region.position + part.position, part.size), modulate)

## Load a texture of a game. Works the same from the project directory and from an exported pack, where only the imported form of the image exists.
static func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_error("GameSprites: no image at %s (is it imported and committed with its .import file?)" % path)
		return null
	var loaded := load(path) as Texture2D
	if loaded == null:
		push_error("GameSprites: %s is not an image Godot can draw" % path)
	return loaded

static func _is_numbers(value: Variant, count: int) -> bool:
	if not value is Array or (value as Array).size() != count:
		return false
	for item: Variant in value:
		if not item is float and not item is int:
			return false
	return true
