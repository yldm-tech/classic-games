extends RefCounted

## Draws one frame of the game onto main.gd's canvas, back to front: sky, two parallax layers, props, tiles, fixtures, everyone alive, particles, then the banner and the fades. It only reads the game's state.

const World := preload("res://games/ember_trail/world.gd")
const Pal := preload("res://games/ember_trail/palette.gd")
const Bosses := preload("res://games/ember_trail/bosses.gd")

const VIEW := Vector2(480.0, 270.0)

static func paint(game: Node2D) -> void:
	var art: Dictionary = game.art()
	var area := int(game.stage["area"])
	var view_x := roundf(game.cam_x)
	var origin := Vector2(view_x, 2.0)
	var time: float = game.stage_time
	var world: RefCounted = game.world

	game.draw_texture(art["sky%d" % area][0], origin)
	_layer(game, art["far%d" % area][0], view_x, 0.1, 67.0 if area == 1 else 2.0)
	_layer(game, art["near%d" % area][0], view_x, 0.32, 2.0)

	var first := int(floor(view_x / World.TILE)) - 2
	var last := first + int(VIEW.x / World.TILE) + 4
	_props(game, art, area, first, last)
	_tiles(game, art, area, first, last, time)

	for plat: Dictionary in world.plats:
		game.draw_texture(art["mover%d" % area][0], Vector2(roundf(float(plat["x"])), roundf(float(plat["y"])) - 1.0))
	for lamp: Dictionary in game.lamps:
		var at: Vector2 = lamp["pos"]
		if lamp["lit"]:
			_glow(game, art, at + Vector2(0.0, -30.0), 1)
		game.draw_texture(art["lamp"][1 if lamp["lit"] else 0], at + Vector2(-7.0, -36.0))
	if game.has_goal:
		var lit: bool = game.phase == "clear"
		if lit:
			_glow(game, art, game.goal + Vector2(0.0, -44.0), 2)
		game.draw_texture(art["beacon"][(1 + int(time * 8.0) % 2) if lit else 0], game.goal + Vector2(-18.0, -56.0))
	for geyser: Dictionary in game.geysers:
		var at: Vector2 = geyser["pos"]
		if geyser["erupting"]:
			var column: Texture2D = art["column"][int(time * 12.0) % 2]
			var along: float = fmod(time + float(geyser["offset"]), float(game.GEYSER_PERIOD)) - float(game.GEYSER_ERUPT)
			var height := minf(float(game.GEYSER_HEIGHT), along * 420.0)
			var drawn := 0.0
			while drawn < height:
				var piece := minf(16.0, height - drawn)
				game.draw_texture_rect_region(column, Rect2(at.x - 7.0, at.y - drawn - piece, 14.0, piece), Rect2(0.0, 0.0, 14.0, piece))
				drawn += piece
		game.draw_texture(art["vent"][0], at + Vector2(-8.0, -6.0))
	for icicle: Dictionary in game.icicles:
		var at: Vector2 = icicle["pos"]
		var wobble := roundf(sin(time * 60.0)) if int(icicle["state"]) == 1 else 0.0
		game.draw_texture(art["icicle"][0], at + Vector2(-4.0 + wobble, 0.0))

	for pickup: Dictionary in game.pickups:
		var at: Vector2 = pickup["pos"]
		var bob := roundf(sin(time * 4.0 + at.x * 0.1) * 1.5)
		match str(pickup["kind"]):
			"o":
				_centred(game, art["moth"][int(time * 8.0 + at.x) % 2], at + Vector2(0.0, bob), false)
			"f":
				_centred(game, art["flask"][0], at + Vector2(0.0, bob), false)
			"r":
				_glow(game, art, at, 0)
				_centred(game, art["resin"][0], at + Vector2(0.0, bob), false)
			"w":
				_glow(game, art, at, 0)
				_centred(game, art["wick"][0], at + Vector2(0.0, bob), false)
			"b":
				_centred(game, art["bell"][0], at + Vector2(roundf(sin(time * 9.0)), bob), false)

	for creature: RefCounted in game.creatures:
		if creature.gone:
			continue
		var key: String = creature.sprite + ("_w" if creature.flash > 0.0 else "")
		_standing(game, art[key][creature.frame % (art[key] as Array).size()], creature.pos, creature.dir < 0)
	if not game.runaway.is_empty():
		_standing(game, art["ram"][int(float(game.runaway["t"]) * 14.0) % 4], game.runaway["pos"], int(game.runaway["dir"]) < 0)
	if game.boss != null:
		_boss(game, art, game.boss)
	_hero(game, art, time)

	for shot: Dictionary in game.shots:
		_centred(game, art["spark"][int(float(shot["t"]) * 20.0) % 2], shot["pos"], false)
	for hazard: Dictionary in game.hazards:
		var at: Vector2 = hazard["pos"]
		var velocity: Vector2 = hazard["vel"]
		match str(hazard["kind"]):
			"glob":
				_centred(game, art["glob"][0], at, false)
			"cinder":
				_centred(game, art["cinder"][0], at, false)
			"shard":
				_centred(game, art["shard"][0], at, velocity.x < 0.0)
			"wave":
				_standing(game, art["wave"][0], at + Vector2(0.0, roundf(sin(time * 30.0))), velocity.x < 0.0)

	for particle: Dictionary in game.fx.particles:
		var size := float(particle["size"])
		# A particle shrinks to a single pixel for the last third of its life.
		if float(particle["life"]) < float(particle["max"]) * 0.33:
			size = 1.0
		game.draw_rect(Rect2(((particle["pos"] as Vector2) - Vector2(size, size) * 0.5).round(), Vector2(size, size)), Pal.of(str(particle["key"])))
	var font: SystemFont = game.font()
	for note: Dictionary in game.fx.popups:
		var at: Vector2 = (note["pos"] as Vector2).round()
		var text := str(note["text"])
		var size := 10 if text.is_valid_int() else 12
		game.draw_string_outline(font, at + Vector2(-60.0, 0.0), text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, size, 3, Pal.of("0"))
		game.draw_string(font, at + Vector2(-60.0, 0.0), text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, size, Pal.of(str(note["key"])))

	_overlays(game, origin, font)

static func _layer(game: Node2D, texture: Texture2D, view_x: float, factor: float, y: float) -> void:
	var width := float(texture.get_width())
	var x := view_x - roundf(fposmod(view_x * factor, width))
	while x < view_x + VIEW.x:
		game.draw_texture(texture, Vector2(x, y))
		x += width

## Dead trees, spires, tufts, crystals and glowing caps, scattered by a hash of the column so a stage always looks the same.
static func _props(game: Node2D, art: Dictionary, area: int, first: int, last: int) -> void:
	var world: RefCounted = game.world
	for tx in range(first - 1, last + 2):
		if tx < 0 or tx >= world.width:
			continue
		var roll := posmod(tx * 7919 + int(game.stage_i) * 104729, 23)
		if not roll in [0, 4, 7, 11, 15, 19]:
			continue
		var top := -1
		for ty in range(9, World.ROWS):
			if world.solid(tx, ty):
				top = ty
				break
		if top < 11 or world.tile(tx, top - 1) != World.EMPTY:
			continue
		var foot := Vector2(float(tx * World.TILE + 8), float(top * World.TILE))
		var texture: Texture2D
		match roll:
			0:
				texture = art["tree"][tx % 2] if area == 1 else art["crystal"][tx % 2]
			11:
				texture = art["spire"][area - 1]
			19:
				texture = art["tuft"][area - 1] if area == 1 else art["shroom"][0]
			_:
				texture = art["tuft"][area - 1]
		game.draw_texture(texture, foot + Vector2(-float(texture.get_width()) * 0.5, -float(texture.get_height())).round())

static func _tiles(game: Node2D, art: Dictionary, area: int, first: int, last: int, time: float) -> void:
	var world: RefCounted = game.world
	var top_tiles: Array = art["t%d_top" % area]
	var fill_tiles: Array = art["t%d_fill" % area]
	var liquid: Texture2D = art["t%d_liquid" % area][int(time * 3.0) % 2]
	var deep: Texture2D = art["t%d_deep" % area][0]
	for tx in range(first, last + 1):
		if tx < 0 or tx >= world.width:
			continue
		var x := float(tx * World.TILE)
		if not world.solid(tx, World.ROWS - 1):
			game.draw_texture(liquid, Vector2(x, 246.0))
			game.draw_texture(deep, Vector2(x, 262.0))
		for ty in World.ROWS:
			var code: int = world.tile(tx, ty)
			if code == World.EMPTY:
				continue
			var at := Vector2(x, float(ty * World.TILE))
			var pick := posmod(tx * 31 + ty * 17, 2)
			match code:
				World.SOLID:
					game.draw_texture(fill_tiles[pick] if world.solid(tx, ty - 1) else top_tiles[pick], at)
				World.ICE:
					game.draw_texture(art["t2_ice"][pick] if not world.solid(tx, ty - 1) else fill_tiles[pick], at)
				World.ONEWAY:
					game.draw_texture(art["t%d_plat" % area][0], at)
				World.CRUMBLE:
					var shaking: bool = world.crumbling.has(ty * world.width + tx)
					game.draw_texture(art["t%d_crumble" % area][0], at + Vector2(roundf(sin(time * 70.0)) if shaking else 0.0, 0.0))
				World.SPIKE:
					game.draw_texture(art["t%d_spike" % area][0], at)

static func _boss(game: Node2D, art: Dictionary, boss: RefCounted) -> void:
	var white: bool = boss.flash > 0.0 or (boss.state == "dying" and int(boss.t * 30.0) % 4 < 2)
	var frames: Array = art[boss.kind + ("_w" if white else "")]
	var texture: Texture2D = frames[boss.frame % frames.size()]
	var lift := 2.0 if boss.kind == "toad" else 6.0
	if boss.state == "dying":
		lift += roundf(sin(boss.t * 50.0) * 2.0)
	game.draw_texture(texture, (boss.pos + Vector2(-float(texture.get_width()) * 0.5, -float(texture.get_height()) + lift)).round())

static func _hero(game: Node2D, art: Dictionary, time: float) -> void:
	var hero: RefCounted = game.hero
	if hero.invuln > 0.0 and not hero.dead and int(hero.invuln * 24.0) % 2 == 0:
		return
	var flip: bool = hero.facing < 0
	var at: Vector2 = hero.pos
	var white: bool = game.flash_time > 0.0
	var lantern := at + Vector2(float(hero.facing) * 6.0, -9.0)
	if hero.mounted:
		var gallop := int(hero.anim * 12.0) % 4 if absf(hero.vel.x) > 10.0 and hero.on_ground else (1 if not hero.on_ground else 0)
		_standing(game, art["ram"][gallop], at, flip)
		var seat := at + Vector2(float(hero.facing) * -2.0, -11.0 + (1.0 if gallop % 2 == 1 else 0.0))
		_glow(game, art, seat + Vector2(float(hero.facing) * 6.0, -9.0), 1 if game.flame > 35.0 else 0)
		_standing(game, art["hero_ride"][1 if hero.throw_pose > 0.0 else 0], seat, flip)
		return
	var key := "hero_idle"
	var frame := int(hero.anim * 2.0) % 2
	if hero.dead or hero.hurt_time > 0.0:
		key = "hero_hurt"
		frame = 0
	elif hero.throw_pose > 0.0:
		key = "hero_throw"
		frame = 2 if not hero.on_ground else (1 if absf(hero.vel.x) > 12.0 else 0)
	elif not hero.on_ground:
		key = "hero_jump" if hero.vel.y < 0.0 else "hero_fall"
		frame = 0
	elif absf(hero.vel.x) > 12.0:
		key = "hero_run"
		frame = int(hero.anim * 12.0) % 4
	if not hero.dead:
		_glow(game, art, lantern, 1 if game.flame > 35.0 else 0)
	if white:
		key += "_w"
	_standing(game, art[key][frame], at + Vector2(float(hero.facing), 0.0), flip)

## The stage title, the fades between stages and the flash of a hit. Drawn in view space: `origin` is the top left of what the camera shows.
static func _overlays(game: Node2D, origin: Vector2, font: SystemFont) -> void:
	if game.flash_time > 0.0:
		game.draw_rect(Rect2(origin, VIEW), Color(1.0, 0.95, 0.8, 0.18))
	var banner: Dictionary = game.banner
	if not banner.is_empty() and float(banner["t"]) < float(banner["life"]):
		var age := float(banner["t"])
		var open := minf(1.0, age / 0.2) * minf(1.0, (float(banner["life"]) - age) / 0.2)
		var half := roundf(22.0 * open)
		var band := Rect2(origin + Vector2(0.0, 118.0 - half), Vector2(VIEW.x, half * 2.0))
		game.draw_rect(band, Color(Pal.of("0"), 0.78))
		game.draw_rect(Rect2(band.position, Vector2(VIEW.x, 1.0)), Pal.of("6"))
		game.draw_rect(Rect2(band.position + Vector2(0.0, band.size.y - 1.0), Vector2(VIEW.x, 1.0)), Pal.of("6"))
		if open >= 1.0:
			var has_sub := str(banner["sub"]) != ""
			game.draw_string(font, origin + Vector2(0.0, 117.0 if has_sub else 124.0), str(banner["title"]), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 16, Pal.of("7"))
			if has_sub:
				game.draw_string(font, origin + Vector2(0.0, 134.0), str(banner["sub"]), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 12, Pal.of("8"))
			if banner.has("hint"):
				game.draw_string_outline(font, origin + Vector2(0.0, 162.0), str(banner["hint"]), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 12, 2, Pal.of("0"))
				game.draw_string(font, origin + Vector2(0.0, 162.0), str(banner["hint"]), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 12, Pal.of("8"))
	var dark := 0.0
	match str(game.phase):
		"intro":
			dark = 1.0 - game.phase_t / 0.35
		"clear":
			dark = (game.phase_t - 2.6) / 0.4
		"area_clear":
			dark = (game.phase_t - 2.8) / 0.4 if int(game.stage_i) + 1 < 6 else 0.0
		"dying":
			dark = (game.phase_t - 1.15) / 0.35
		"game_over":
			dark = 0.55
	if dark > 0.0:
		# Stepped, not smooth: the fade closes in four shades like everything else on this stage.
		game.draw_rect(Rect2(origin - Vector2(8.0, 8.0), VIEW + Vector2(16.0, 16.0)), Color(Pal.of("0"), ceilf(clampf(dark, 0.0, 1.0) * 4.0) / 4.0))
		if str(game.phase) == "game_over" and not banner.is_empty():
			game.draw_string(font, origin + Vector2(0.0, 124.0), str(banner["title"]), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 16, Pal.of("7"))

## Draw a texture standing on `feet` (the middle of its bottom edge), mirrored when `flip`.
static func _standing(game: Node2D, texture: Texture2D, feet: Vector2, flip: bool) -> void:
	var size := Vector2(texture.get_size())
	var corner := (feet + Vector2(-size.x * 0.5, -size.y)).round()
	if flip:
		game.draw_texture_rect(texture, Rect2(corner + Vector2(size.x, 0.0), Vector2(-size.x, size.y)), false)
	else:
		game.draw_texture(texture, corner)

static func _centred(game: Node2D, texture: Texture2D, middle: Vector2, flip: bool) -> void:
	var size := Vector2(texture.get_size())
	_standing(game, texture, middle + Vector2(0.0, size.y * 0.5), flip)

## A disc of light: size 0 for the lantern and small things, 1 for a lamp post, 2 for a beacon.
static func _glow(game: Node2D, art: Dictionary, middle: Vector2, size: int) -> void:
	var texture: Texture2D = art["glow"][size]
	game.draw_texture(texture, (middle - Vector2(texture.get_size()) * 0.5).round())
