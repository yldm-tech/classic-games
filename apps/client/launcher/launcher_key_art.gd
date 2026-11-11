class_name LauncherKeyArt
extends Control

## Key art of one game, cover-fitted into this control. It is the only place that knows where a game's picture comes from.
## A game ships its picture in its own directory and names it in its manifest (`art.image`, 16:9): texture_for() finds it through the catalog and nothing else changes. A game without one gets a procedural placeholder drawn from its manifest's `art` palette. The placeholders are abstract shapes authored here, not a rendition of any existing artwork.

## Reference frame the placeholders are authored in; it is scaled to cover the control like a background image.
const FRAME := Vector2(1600, 900)

var game_id := "":
	set(value):
		if value == game_id:
			return
		game_id = value
		_texture = texture_for(game_id)
		queue_redraw()

var _texture: Texture2D

func _init(p_game_id: String = "") -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_id = p_game_id

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

## The finished key art of a game, or null while it only has the procedural placeholder.
static func texture_for(id: String) -> Texture2D:
	var path := str((LauncherCatalog.by_id(id).get("art", {}) as Dictionary).get("image_path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LauncherTokens.BG)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _texture != null:
		var texture_size := _texture.get_size()
		var texture_scale := maxf(size.x / texture_size.x, size.y / texture_size.y)
		var drawn := texture_size * texture_scale
		draw_texture_rect(_texture, Rect2((size - drawn) / 2.0, drawn), false)
		return
	var entry := LauncherCatalog.by_id(game_id)
	if entry.is_empty():
		return
	var cover := maxf(size.x / FRAME.x, size.y / FRAME.y)
	draw_set_transform((size - FRAME * cover) / 2.0, 0.0, Vector2(cover, cover))
	var top := LauncherCatalog.color(entry, "art", "top", LauncherTokens.BG)
	var bottom := LauncherCatalog.color(entry, "art", "bottom", LauncherTokens.BG)
	var primary := LauncherCatalog.color(entry, "art", "primary")
	var secondary := LauncherCatalog.color(entry, "art", "secondary")
	_vertical_gradient(Rect2(Vector2.ZERO, FRAME), top, bottom)
	match str((entry.get("art", {}) as Dictionary).get("motif", "")):
		"orbit": _paint_orbit(primary, secondary, bottom)
		"swarm": _paint_swarm(primary, secondary, top)
		"road": _paint_road(primary, secondary, top)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---- placeholders ----

func _paint_orbit(primary: Color, secondary: Color, base: Color) -> void:
	_stars(11, 110, Color(1, 1, 1, 0.8))
	var planet := Vector2(1150, 440)
	_glow(planet, 620.0, Color(primary, 0.34))
	draw_circle(planet, 215.0, base.lerp(primary, 0.28))
	draw_circle(planet + Vector2(26, 22), 196.0, base.lerp(primary, 0.12))
	draw_arc(planet, 212.0, deg_to_rad(188), deg_to_rad(292), 48, Color(primary.lightened(0.5), 0.95), 7.0, true)
	var rings := [[330.0, 4.0, 0.75], [450.0, 2.5, 0.45], [600.0, 2.0, 0.26]]
	for ring: Array in rings:
		_ellipse_arc(planet, float(ring[0]), 0.3, -0.32, 0.0, TAU, Color(primary.lightened(0.35), float(ring[2])), float(ring[1]))
	# The craft and its trail ride the inner ring; the markers on the outer rings stand for the patrol's targets.
	var craft := _on_ellipse(planet, 330.0, 0.3, -0.32, deg_to_rad(150))
	_ellipse_arc(planet, 330.0, 0.3, -0.32, deg_to_rad(150), deg_to_rad(205), Color(secondary, 0.9), 6.0)
	_glow(craft, 90.0, Color(secondary, 0.6))
	draw_colored_polygon(_shape(craft, [Vector2(-34, 0), Vector2(18, -15), Vector2(8, 0), Vector2(18, 15)], -0.5), secondary)
	for angle in [20.0, 62.0, 248.0, 300.0]:
		var marker := _on_ellipse(planet, 450.0, 0.3, -0.32, deg_to_rad(angle))
		draw_colored_polygon(_shape(marker, [Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0)], 0.0), Color(primary.lightened(0.55), 0.9))
	for angle in [95.0, 330.0]:
		var far := _on_ellipse(planet, 600.0, 0.3, -0.32, deg_to_rad(angle))
		draw_colored_polygon(_shape(far, [Vector2(0, -9), Vector2(9, 0), Vector2(0, 9), Vector2(-9, 0)], 0.0), Color(primary.lightened(0.4), 0.6))

func _paint_swarm(primary: Color, secondary: Color, base: Color) -> void:
	_stars(23, 40, Color(1, 1, 1, 0.5), 330.0)
	var moon := Vector2(1330, 190)
	_glow(moon, 300.0, Color(secondary, 0.28))
	draw_circle(moon, 44.0, secondary.lightened(0.6))
	draw_colored_polygon(_ridge(520.0, 46.0, 0.0061, 0.4), base.lerp(primary, 0.2))
	draw_colored_polygon(_ridge(640.0, 34.0, 0.0043, 2.1), base.lerp(primary, 0.1))
	var hero := Vector2(1090, 610)
	_glow(hero, 430.0, Color(primary, 0.3))
	var rings := [[150.0, 9, 0.95, 13.0], [255.0, 15, 0.7, 11.0], [370.0, 22, 0.42, 9.0]]
	var index := 0
	for ring: Array in rings:
		for i in int(ring[1]):
			var at := hero + Vector2.from_angle(TAU * float(i) / float(ring[1]) + float(index) * 0.37) * Vector2(float(ring[0]), float(ring[0]) * 0.62)
			draw_colored_polygon(_regular(at, float(ring[3]), 8), Color(primary, float(ring[2])))
		index += 1
	for angle in [0.52, 2.2, 3.9, 5.3]:
		var target := hero + Vector2.from_angle(angle) * Vector2(150, 93)
		draw_line(hero, target, Color(secondary, 0.85), 3.0, true)
		draw_circle(target, 6.0, secondary)
	_glow(hero, 80.0, Color(secondary, 0.75))
	draw_colored_polygon(_shape(hero, [Vector2(0, -34), Vector2(24, 0), Vector2(0, 34), Vector2(-24, 0)], 0.0), secondary.lightened(0.35))

func _paint_road(primary: Color, secondary: Color, base: Color) -> void:
	var sun := Vector2(1380, 300)
	_glow(sun, 560.0, Color(primary, 0.42))
	draw_circle(sun, 58.0, primary.lightened(0.55))
	draw_colored_polygon(_ridge(430.0, 38.0, 0.0052, 1.2), base.lerp(primary, 0.16))
	_vertical_gradient(Rect2(0, 470, FRAME.x, 430), base.lerp(primary, 0.1), base.lerp(Color.BLACK, 0.35))
	# The same kind of bent road the runtime's baseline stage uses, drawn here in art coordinates.
	var road := PackedVector2Array([Vector2(420, 620), Vector2(820, 620), Vector2(820, 800), Vector2(1180, 800), Vector2(1180, 520), Vector2(1640, 520)])
	_thick_path(road, 84.0, base.lerp(Color.BLACK, 0.5))
	_thick_path(road, 64.0, base.lerp(primary, 0.3))
	draw_polyline(road, Color(primary.lightened(0.4), 0.35), 2.0, true)
	var walkers := [Vector2(520, 620), Vector2(640, 620), Vector2(760, 620), Vector2(820, 700), Vector2(930, 800), Vector2(1060, 800)]
	for at: Vector2 in walkers:
		draw_colored_polygon(_regular(at, 15.0, 6), primary.lightened(0.5))
	var towers := [[Vector2(650, 500), secondary, walkers[1]], [Vector2(980, 660), primary.lightened(0.2), walkers[4]], [Vector2(1320, 690), secondary, walkers[5]], [Vector2(1050, 420), primary.lightened(0.2), Vector2.ZERO]]
	for tower: Array in towers:
		var at: Vector2 = tower[0]
		var tint: Color = tower[1]
		draw_arc(at, 150.0, 0.0, TAU, 64, Color(tint, 0.2), 2.0, true)
		if tower[2] != Vector2.ZERO:
			draw_line(at, tower[2], Color(tint.lightened(0.4), 0.9), 3.0, true)
		_glow(at, 70.0, Color(tint, 0.5))
		draw_colored_polygon(_regular(at, 30.0, 6), tint)
		draw_colored_polygon(_regular(at, 15.0, 6), base.lerp(tint, 0.25))

# ---- drawing helpers ----

func _vertical_gradient(rect: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

## Soft radial light: `color` at the centre fading to transparent at `radius`.
func _glow(center: Vector2, radius: float, color: Color) -> void:
	var clear := Color(color, 0.0)
	var segments := 40
	for i in segments:
		var a := Vector2.from_angle(TAU * float(i) / segments) * radius
		var b := Vector2.from_angle(TAU * float(i + 1) / segments) * radius
		draw_polygon(PackedVector2Array([center, center + a, center + b]), PackedColorArray([color, clear, clear]))

func _stars(seed_value: int, count: int, color: Color, max_y: float = FRAME.y) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var at := Vector2(rng.randf_range(0.0, FRAME.x), rng.randf_range(0.0, max_y))
		draw_circle(at, rng.randf_range(0.8, 2.0), Color(color, color.a * rng.randf_range(0.35, 1.0)))

## A wide path with round joints. draw_polyline leaves gaps and overlaps at sharp corners when it is this wide, so each segment and each joint is drawn on its own in an opaque colour.
func _thick_path(points: PackedVector2Array, width: float, color: Color) -> void:
	for i in points.size() - 1:
		draw_line(points[i], points[i + 1], color, width)
	for point in points:
		draw_circle(point, width / 2.0, color)

func _on_ellipse(center: Vector2, radius: float, squash: float, tilt: float, angle: float) -> Vector2:
	return center + (Vector2.from_angle(angle) * Vector2(radius, radius * squash)).rotated(tilt)

func _ellipse_arc(center: Vector2, radius: float, squash: float, tilt: float, from: float, to: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var steps := maxi(8, int(96.0 * absf(to - from) / TAU))
	for i in steps + 1:
		points.append(_on_ellipse(center, radius, squash, tilt, lerpf(from, to, float(i) / steps)))
	draw_polyline(points, color, width, true)

func _shape(center: Vector2, points: Array, rotation_radians: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(center + point.rotated(rotation_radians))
	return out

func _regular(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in sides:
		out.append(center + Vector2.from_angle(TAU * float(i) / sides) * radius)
	return out

## A silhouette from `base_y` down to the bottom of the frame with a gently waving top edge.
func _ridge(base_y: float, amplitude: float, frequency: float, phase: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := 40
	for i in steps + 1:
		var x := FRAME.x * float(i) / steps
		out.append(Vector2(x, base_y + sin(x * frequency + phase) * amplitude + sin(x * frequency * 2.7 + phase) * amplitude * 0.35))
	out.append(Vector2(FRAME.x, FRAME.y))
	out.append(Vector2(0, FRAME.y))
	return out
