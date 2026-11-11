extends Node2D

## Draws Keg Burrow. It only reads the simulation (main.gd) and keeps what is pure show for itself: sparks, dust, floating scores, the screen shake and the banners. Nothing here feeds back into the game, so the same seed plays the same on any frame rate.

const Levels := preload("res://games/keg_maze/levels.gd")
const Actors := preload("res://games/keg_maze/actors.gd")
const Sprites := preload("res://games/keg_maze/sprites.gd")

const TILE := float(Levels.TILE)
const STAGE := Vector2(480, 270)
const LEFT_PANEL := Rect2(4, 62, 80, 204)
const RIGHT_PANEL := Rect2(396, 88, 80, 156)
const HERO_TINTS := [Color("f2b233"), Color("4fd1c5")]
const FOE_TINTS := {"grub": ["7fc24e", "f6d365"], "mite": ["ee8a2f", "d1433a"], "beetle": ["4a74d8", "9a6be0"], "wisp": ["58c7d9", "f4efe6"], "shell": ["b9b3c4", "6d6680"], "boss": ["58c7d9", "9a6be0"]}
const WORLD_DUST := [Color("dba45c"), Color("a6e8f0"), Color("ffb347")]
const WORLD_BACK := [Color("17100e"), Color("0d0f1e"), Color("160a0c")]
const FRAME_LIGHT := Color("b0733a")
const FRAME_DARK := Color("4a2f25")
const PANEL_FILL := Color(0.05, 0.04, 0.07, 0.82)

const TEXT := {
	"level": {"zh": "第 %d 层", "en": "LEVEL %d"},
	"boss_level": {"zh": "第 %d 层 · 首领", "en": "LEVEL %d · BOSS"},
	"clear": {"zh": "本层清空！", "en": "LEVEL CLEAR!"},
	"bonus": {"zh": "剩余时间奖励 +%d", "en": "TIME BONUS +%d"},
	"victory": {"zh": "矿井打通了！", "en": "THE MINE IS YOURS!"},
	"victory_sub": {"zh": "最深处的王座已经安静下来", "en": "The deepest throne has gone quiet"},
	"continue": {"zh": "再下去一次", "en": "ONE MORE DESCENT"},
	"continue_sub": {"zh": "剩余续关 %d", "en": "CONTINUES LEFT %d"},
	"defeat": {"zh": "挖掘队撤离", "en": "THE DIG IS ABANDONED"},
	"exit_open": {"zh": "升降机开了！", "en": "THE LIFT IS OPEN!"},
	"exit_found": {"zh": "找到升降机了", "en": "LIFT HATCH FOUND"},
	"exit_hint": {"zh": "升降机还埋在方块下面", "en": "THE LIFT IS STILL BURIED"},
	"timeup": {"zh": "空气耗尽！", "en": "OUT OF AIR!"},
	"rage": {"zh": "它发怒了！", "en": "IT IS ENRAGED!"},
	"out": {"zh": "下一层归队", "en": "BACK NEXT\nLEVEL"},
}

var game: Node
var tex: Dictionary = {}
var font: SystemFont
var clock := 0.0
var shake := 0.0
var offset := Vector2.ZERO
var flash := 0.0
var particles: Array = []
var floaters: Array = []
var notice := ""
var notice_time := 0.0
var _backdrop: ImageTexture
var _baked := -1

func attach(owner_game: Node) -> void:
	game = owner_game
	particles.clear()
	floaters.clear()
	notice_time = 0.0
	shake = 0.0
	flash = 0.0
	_baked = -1

## Once per rendered frame: take the simulation's events, move the sparks and ask for a redraw.
func frame(delta: float) -> void:
	clock += delta
	for event: Dictionary in game.fx:
		_on_event(event)
	game.fx.clear()
	shake = maxf(0.0, shake - delta * 14.0)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * minf(shake, 5.0) if shake > 0.05 else Vector2.ZERO
	flash = maxf(0.0, flash - delta * 3.0)
	notice_time = maxf(0.0, notice_time - delta)
	for index in range(particles.size() - 1, -1, -1):
		var spark: Dictionary = particles[index]
		spark["life"] = float(spark["life"]) - delta
		if float(spark["life"]) <= 0.0:
			particles.remove_at(index)
			continue
		var speed: Vector2 = spark["v"]
		speed.y += float(spark["g"]) * delta
		spark["v"] = speed * (1.0 - 1.5 * delta)
		spark["p"] = (spark["p"] as Vector2) + speed * delta
	for index in range(floaters.size() - 1, -1, -1):
		var floater: Dictionary = floaters[index]
		floater["life"] = float(floater["life"]) - delta
		if float(floater["life"]) <= 0.0:
			floaters.remove_at(index)
	queue_redraw()

# ---- events ----

func _on_event(event: Dictionary) -> void:
	var cell: Vector2i = event["cell"]
	var at := (Vector2(cell) + Vector2(0.5, 0.5)) * TILE
	var extra: Variant = event["extra"]
	var dust: Color = WORLD_DUST[Levels.world(game.stage)]
	match str(event["kind"]):
		"stage":
			particles.clear()
			floaters.clear()
		"place":
			_burst(at + Vector2(0, 5), 5, [dust.darkened(0.3)], 26.0, 0.3, 0.0, 1.0)
		"blast":
			var links := int(extra)
			shake = maxf(shake, 2.0 + minf(4.0, float(links)))
			flash = maxf(flash, 0.12 + 0.05 * minf(4.0, float(links)))
			_burst(at, 16, [Color("fff6b0"), Color("f6d365"), Color("ee8a2f")], 95.0, 0.45, 40.0, 1.5)
			_burst(at, 8, [Color(0.25, 0.22, 0.25, 0.8)], 30.0, 0.9, -30.0, 2.5)
			if links >= 2:
				floaters.append({"p": at + Vector2(0, -6), "text": "x%d" % links, "life": 0.9, "max": 0.9, "c": Color("fff6b0")})
		"crate":
			var swap: Dictionary = Sprites.WORLD_SWAPS[Levels.world(game.stage)]
			_burst(at, 10, [Sprites.color("7", swap), Sprites.color("8", swap), Sprites.color("9", swap)], 70.0, 0.55, 220.0, 2.0)
		"reveal":
			_burst(at, 6, [Color("fff6b0"), Color.WHITE], 40.0, 0.5, -20.0, 1.0)
		"exit_found":
			_burst(at, 14, [Color("f6d365"), Color.WHITE], 60.0, 0.8, -20.0, 1.0)
			_say("exit_found", 1.6)
		"exit_open":
			_burst(at, 20, [Color("f6d365"), Color("fff6b0"), Color.WHITE], 80.0, 0.9, -30.0, 1.5)
			_say("exit_open" if game.exit_visible else "exit_hint", 2.2)
		"rock":
			shake = maxf(shake, 3.0)
			_burst(at, 12, [Color("b9b3c4"), Color("6d6680"), dust.darkened(0.4)], 80.0, 0.5, 200.0, 2.0)
		"foe_die":
			var tints: Array = FOE_TINTS.get(str(extra), FOE_TINTS["grub"])
			_burst(at, 12, [Color(str(tints[0])), Color(str(tints[1])), Color.WHITE], 75.0, 0.5, 60.0, 1.5)
		"crack":
			_burst(at, 8, [Color("b9b3c4"), Color("6d6680")], 60.0, 0.4, 160.0, 1.5)
		"boss_hit":
			shake = maxf(shake, 4.0)
			_burst(at + Vector2(8, 8), 18, [Color.WHITE, Color("58c7d9"), Color("9a6be0")], 110.0, 0.5, 80.0, 2.0)
		"rage":
			shake = maxf(shake, 6.0)
			_say("rage", 1.8)
		"tell":
			_burst(at + Vector2(8, 8), 14, [Color("ee8a2f"), Color("f6d365")], 50.0, 0.8, -60.0, 1.5)
		"spit":
			shake = maxf(shake, 4.0)
		"spawn":
			_burst(at, 10, [dust, Color.WHITE], 50.0, 0.5, -10.0, 1.5)
		"boss_die":
			shake = 12.0
			flash = 0.6
			for ring in 5:
				_burst(at + Vector2(8, 8) + Vector2(randf_range(-14, 14), randf_range(-14, 14)), 16, [Color.WHITE, Color("f6d365"), Color("ee8a2f"), Color("d1433a")], 130.0, 1.0 + 0.15 * float(ring), 50.0, 2.5)
		"hurt":
			shake = maxf(shake, 4.0)
			_burst(at, 14, [HERO_TINTS[int(extra) % 2], Color("7a6a86"), Color.WHITE], 85.0, 0.7, 120.0, 1.5)
		"shield":
			_burst(at, 12, [Color("f2b233"), Color("fff6b0")], 90.0, 0.4, 0.0, 1.5)
		"daze":
			_burst(at + Vector2(0, -6), 6, [Color("f6d365"), Color.WHITE], 30.0, 0.8, -10.0, 1.0)
		"join":
			_burst(at, 12, [HERO_TINTS[int(extra) % 2], Color.WHITE], 60.0, 0.6, -20.0, 1.5)
		"timeup":
			shake = 8.0
			flash = 0.4
			_say("timeup", 2.0)
		"pickup":
			_burst(at, 8, [Color(str(Sprites.ITEM_RIMS.get(str(extra), "ffffff"))), Color.WHITE], 55.0, 0.45, -30.0, 1.0)
		"points":
			floaters.append({"p": at + Vector2(0, -8), "text": str(int(extra)), "life": 0.9, "max": 0.9, "c": Color.WHITE})
		"clear":
			for ring in 3:
				_burst(at, 14, [Color("f6d365"), Color("58c7d9"), Color("f2a3a0"), Color.WHITE], 70.0 + 30.0 * float(ring), 1.2, 40.0, 1.5)

func _say(key: String, seconds: float) -> void:
	notice = _t(key)
	notice_time = seconds

func _burst(at: Vector2, count: int, colors: Array, speed: float, life: float, gravity: float, size: float) -> void:
	if particles.size() > 400:
		return
	for index in count:
		var angle := randf() * TAU
		var pace := speed * randf_range(0.35, 1.0)
		var span := life * randf_range(0.6, 1.0)
		particles.append({"p": at, "v": Vector2(cos(angle), sin(angle)) * pace, "life": span, "max": span, "c": colors[randi() % colors.size()], "g": gravity, "s": size})

func _t(key: String) -> String:
	var entry: Dictionary = TEXT[key]
	return str(entry["en"] if game.locale == "en" else entry["zh"])

# ---- drawing ----

func _draw() -> void:
	if game == null or game.heroes.is_empty():
		return
	if tex.is_empty():
		tex = Sprites.build()
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Noto Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"])
		font.allow_system_fallback = true
		font.font_weight = 700
	if _baked != game.stage_serial:
		_bake()
	var world := Levels.world(game.stage)
	draw_texture(_backdrop, Vector2.ZERO)
	_draw_motes(world)
	_draw_panels(world)
	draw_set_transform(Levels.ORIGIN + offset)
	_draw_field(world)
	_draw_exit()
	_draw_items()
	_draw_hazard_shadows()
	_draw_kegs()
	_draw_foes()
	_draw_heroes()
	_draw_flames()
	_draw_hazards()
	_draw_particles()
	_draw_floaters()
	draw_set_transform(Vector2.ZERO)
	_draw_frame()
	if flash > 0.0:
		draw_rect(Rect2(Levels.ORIGIN, Vector2(Levels.COLS, Levels.ROWS) * TILE), Color(1.0, 0.95, 0.8, minf(0.5, flash)))
	_draw_low_air()
	_draw_banner()

## Paint what never changes during a stage into one texture: the dim rock around the field and the field's own floor and rock.
func _bake() -> void:
	_baked = game.stage_serial
	var world := Levels.world(game.stage)
	var image := Image.create(int(STAGE.x), int(STAGE.y), false, Image.FORMAT_RGBA8)
	image.fill(WORLD_BACK[world])
	var rock: Image = (tex["w%d_rock" % world] as ImageTexture).get_image()
	for y in rock.get_height():
		for x in rock.get_width():
			rock.set_pixel(x, y, rock.get_pixel(x, y).darkened(0.55))
	for y in range(0, int(STAGE.y) + 16, 16):
		for x in range(0, int(STAGE.x) + 16, 16):
			image.blit_rect(rock, Rect2i(0, 0, 16, 16), Vector2i(x + (8 if (y / 16) % 2 == 1 else 0) - 8, y - 2))
	var names := ["floor_a", "floor_b", "pillar", "wall"]
	var tiles := {}
	for tile: String in names:
		tiles[tile] = (tex["w%d_%s" % [world, tile]] as ImageTexture).get_image()
	var origin := Vector2i(Levels.ORIGIN)
	for y in Levels.ROWS:
		for x in Levels.COLS:
			var cell := Vector2i(x, y)
			var tile := "floor_b" if (x * 7 + y * 13 + game.stage * 3) % 5 == 0 else "floor_a"
			if game.grid[Levels.index(cell)] == Levels.WALL:
				tile = "pillar" if Levels.inside(cell) else "wall"
			image.blit_rect(tiles[tile], Rect2i(0, 0, 16, 16), origin + cell * Levels.TILE)
	_backdrop = ImageTexture.create_from_image(image)

## Slow dust in the lamp light on both sides of the field.
func _draw_motes(world: int) -> void:
	var tint: Color = WORLD_DUST[world]
	for index in 26:
		var seed_value := float(index) * 12.9898
		var column := fmod(absf(sin(seed_value) * 43758.5453), 1.0)
		var x := column * 84.0 + (0.0 if index % 2 == 0 else 394.0)
		var y := fmod(absf(cos(seed_value) * 9631.77) + clock * (3.0 + float(index % 5)), STAGE.y)
		var glow := 0.25 + 0.2 * sin(clock * 1.7 + seed_value)
		draw_rect(Rect2(floorf(x + sin(clock * 0.6 + seed_value) * 3.0), floorf(STAGE.y - y), 1, 1), Color(tint, glow))

func _draw_frame() -> void:
	var field := Rect2(Levels.ORIGIN, Vector2(Levels.COLS, Levels.ROWS) * TILE)
	draw_rect(field.grow(2.0), FRAME_DARK, false, 2.0)
	draw_rect(field.grow(1.0), FRAME_LIGHT, false, 1.0)

func _draw_field(world: int) -> void:
	var block: Texture2D = tex["w%d_block" % world]
	var shade := Color(0, 0, 0, 0.3)
	for y in range(1, Levels.ROWS - 1):
		for x in range(1, Levels.COLS - 1):
			var at := y * Levels.COLS + x
			var tile: int = game.grid[at]
			var corner := Vector2(x, y) * TILE
			if tile == Levels.FLOOR:
				if game.grid[at - Levels.COLS] != Levels.FLOOR:
					draw_rect(Rect2(corner, Vector2(TILE, 4)), shade)
				if game.grid[at - 1] != Levels.FLOOR:
					draw_rect(Rect2(corner, Vector2(2, TILE)), Color(0, 0, 0, 0.18))
			elif tile == Levels.CRATE:
				draw_texture(block, corner)
			elif tile == Levels.BURNING:
				var left := clampf(float(game.burning.get(at, 0.0)) / 0.45, 0.0, 1.0)
				draw_texture(block, corner, Color(1.0, 0.35 + 0.4 * left, 0.2, 0.35 + 0.65 * left))
				draw_texture(tex["flame_c_%d" % (int(clock * 14.0) % Sprites.FLAME_FRAMES)], corner, Color(1, 1, 1, 0.9))
	# The block that hides the lift twinkles once the creatures are gone, so nobody has to dig blind.
	if game.exit_open and not game.exit_visible and game.exit_cell.x >= 0:
		var hint := (Vector2(game.exit_cell) + Vector2(0.5, 0.5)) * TILE
		for index in 4:
			var angle := clock * 2.5 + float(index) * TAU / 4.0
			draw_rect(Rect2((hint + Vector2(cos(angle), sin(angle)) * 6.0).floor(), Vector2(2, 2)), Color("fff6b0"))

func _draw_exit() -> void:
	if not game.exit_visible or game.exit_cell.x < 0:
		return
	var corner := Vector2(game.exit_cell) * TILE
	draw_texture(tex["hatch_open" if game.exit_open else "hatch_shut"], corner)
	if game.exit_open:
		var pulse := 0.5 + 0.5 * sin(clock * 6.0)
		draw_rect(Rect2(corner - Vector2(1, 1), Vector2(TILE + 2, TILE + 2)), Color(1.0, 0.9, 0.4, 0.35 + 0.45 * pulse), false, 1.0)
		var hop := floorf(fmod(clock * 10.0, 6.0))
		for arrow in 3:
			draw_rect(Rect2(corner + Vector2(7 - arrow, -8 + hop + float(arrow)), Vector2(2 + arrow * 2, 1)), Color(1.0, 0.95, 0.6, 0.9))

func _draw_items() -> void:
	for at: int in game.items:
		var cell := Levels.cell_of(at)
		var bob := roundf(sin(clock * 4.0 + float(at)) * 1.0)
		draw_texture(tex["item_" + str(game.items[at])], Vector2(cell) * TILE + Vector2(0, bob))
		if int(clock * 6.0 + float(at)) % 7 == 0:
			draw_rect(Rect2(Vector2(cell) * TILE + Vector2(3, 3), Vector2(2, 2)), Color.WHITE)

func _draw_kegs() -> void:
	for keg: Actors.Keg in game.kegs:
		var corner := Vector2(keg.cell) * TILE
		var urgent := keg.fuse < 0.7 and not keg.remote
		var swell := roundf(sin(keg.age * (22.0 if urgent else 9.0)) * 1.0)
		var tint := Color(1.0, 0.6, 0.5) if urgent and int(keg.age * 16.0) % 2 == 0 else Color.WHITE
		draw_texture_rect(tex["keg"], Rect2(corner + Vector2(-swell * 0.5, swell * 0.5), Vector2(TILE + swell, TILE - swell)), false, tint)
		var bung := corner + Vector2(7, 5 + swell * 0.5)
		if keg.remote:
			# A wired keg carries a blinking red lamp instead of a burning bung.
			draw_rect(Rect2(bung, Vector2(2, 2)), Color("d1433a") if int(keg.age * 5.0) % 2 == 0 else Color("7c1f33"))
			draw_rect(Rect2(bung + Vector2(0, -3), Vector2(1, 3)), Color("b9b3c4"))
		else:
			var flick := int(clock * 20.0) % 3
			draw_rect(Rect2(bung + Vector2(-1 + flick, -3), Vector2(2, 2)), Color("fff6b0"))
			draw_rect(Rect2(bung + Vector2(flick - 2, -5), Vector2(1, 1)), Color("ee8a2f"))
			draw_rect(Rect2(bung + Vector2(2 - flick, -4), Vector2(1, 1)), Color("f6d365"))
		draw_rect(Rect2(corner + Vector2(3, 0), Vector2(2, 1)), HERO_TINTS[keg.owner % 2])

func _draw_foes() -> void:
	for foe: Actors.Foe in game.foes:
		var corner := (foe.pos() * TILE).round()
		var frame := int(foe.anim * 6.0) % 2
		if foe.kind == "boss":
			_draw_boss(foe, corner)
			continue
		var sprite := foe.kind
		if foe.kind == "shell" and foe.hp < foe.max_hp:
			sprite = "shellc"
		var key := "%s_%d" % [sprite, frame]
		if foe.dying > 0.0:
			var fade := clampf(foe.dying / 0.5, 0.0, 1.0)
			var grow := (1.0 - fade) * 6.0
			draw_texture_rect(tex[key + "_flash"], Rect2(corner - Vector2(grow, grow) * 0.5, Vector2(TILE + grow, TILE + grow)), false, Color(1, 1, 1, fade))
			continue
		if foe.rest > 0.0 and foe.anim >= 0.8:
			# Dazed or winded: it stands still under a ring of little stars and can be walked past.
			draw_texture(tex[key], corner, Color(0.75, 0.75, 0.85))
			for star in 3:
				var angle := clock * 6.0 + float(star) * TAU / 3.0
				draw_rect(Rect2((corner + Vector2(7, -1) + Vector2(cos(angle) * 5.0, sin(angle) * 2.0)).floor(), Vector2(2, 2)), Color("f6d365"))
			continue
		if foe.rest > 0.0 and foe.anim < 0.8:
			# Just dug its way out next to the boss.
			draw_texture_rect(tex[key], Rect2(corner + Vector2(0, 8.0 * foe.rest), Vector2(TILE, TILE - 8.0 * foe.rest)), false, Color(1, 1, 1, 0.7))
			continue
		draw_rect(Rect2(corner + Vector2(3, 13), Vector2(10, 2)), Color(0, 0, 0, 0.25))
		var lift := Vector2(0, -1.0 - roundf(absf(sin(clock * 3.0 + foe.anim)))) if foe.kind == "wisp" else Vector2.ZERO
		if foe.invuln > 0.0 and int(clock * 20.0) % 2 == 0:
			draw_texture(tex[key + "_flash"], corner + lift)
		else:
			draw_texture(tex[key], corner + lift, Color(1, 1, 1, 0.85) if foe.kind == "wisp" else Color.WHITE)
		if foe.charge:
			draw_rect(Rect2(corner - Vector2(foe.dir) * 6.0 + Vector2(6, 12), Vector2(3, 2)), Color(1, 1, 1, 0.5))

func _draw_boss(foe: Actors.Foe, corner: Vector2) -> void:
	var frame := int(foe.anim * 4.0) % 2
	var key := "boss%d_%d" % [foe.tier, frame]
	var size := Vector2(32, 32)
	if foe.dying > 0.0:
		var fade := clampf(foe.dying / 1.8, 0.0, 1.0)
		var jitter := Vector2(randf_range(-2, 2), randf_range(-2, 2))
		draw_texture(tex[key + "_flash" if int(clock * 24.0) % 2 == 0 else key], corner + jitter, Color(1, 1, 1, fade))
		return
	draw_rect(Rect2(corner + Vector2(4, 27), Vector2(24, 4)), Color(0, 0, 0, 0.3))
	var bob := Vector2(0, roundf(sin(foe.anim * 5.0)))
	if foe.tell > 0.0:
		bob += Vector2(randf_range(-1, 1), 0).round()
		draw_texture(tex[key], corner + bob, Color(1.0, 0.75, 0.45))
		var glow := 1.0 - foe.tell / 0.9
		draw_rect(Rect2(corner - Vector2(2, 2), size + Vector2(4, 4)), Color(1.0, 0.6, 0.2, 0.2 + 0.5 * glow), false, 2.0)
	elif foe.invuln > 0.0 and int(clock * 20.0) % 2 == 0:
		draw_texture(tex[key + "_flash"], corner + bob)
	else:
		draw_texture(tex[key], corner + bob, Color(1.0, 0.8, 0.8) if foe.hp * 2 <= foe.max_hp and int(clock * 3.0) % 2 == 0 else Color.WHITE)

func _hero_key(slot: int, hero: Actors.Hero) -> String:
	if game.phase == Levels.Phase.CLEAR:
		return "hero%d_cheer" % slot
	if hero.act > 0.0:
		return "hero%d_place" % slot
	var facing := "down"
	if hero.face.y < 0:
		facing = "up"
	elif hero.face.x > 0:
		facing = "right"
	elif hero.face.x < 0:
		facing = "left"
	var frame := 0
	if hero.dir != Vector2i.ZERO:
		frame = [1, 0, 2, 0][int(hero.walk * 10.0) % 4]
	return "hero%d_%s_%d" % [slot, facing, frame]

func _draw_heroes() -> void:
	var two: bool = game.player_count() > 1
	for slot: int in game.active_players():
		var hero: Actors.Hero = game.heroes[slot]
		if hero.out:
			continue
		var corner := (hero.pos() * TILE).round() + Vector2(0, -2)
		if hero.dead > 0.0:
			var spent := 1.4 - hero.dead
			if spent < 0.5:
				draw_texture(tex["hero%d_hurt" % slot], corner + Vector2(0, -roundf(sin(spent / 0.5 * PI) * 6.0)), Color.WHITE if int(clock * 20.0) % 2 == 0 else Color(1.0, 0.5, 0.5))
			else:
				draw_texture(tex["hero%d_helmet" % slot], corner + Vector2(0, 2), Color(1, 1, 1, clampf(hero.dead / 0.4, 0.0, 1.0)))
			continue
		if hero.invuln > 0.0 and int(clock * 14.0) % 2 == 0:
			continue
		draw_rect(Rect2(corner + Vector2(3, 15), Vector2(10, 2)), Color(0, 0, 0, 0.28))
		var hop := Vector2.ZERO
		if game.phase == Levels.Phase.CLEAR:
			hop.y = -roundf(absf(sin(clock * 9.0 + float(slot))) * 4.0)
		draw_texture(tex[_hero_key(slot, hero)], corner + hop)
		if hero.shield:
			var ring := 0.55 + 0.3 * sin(clock * 5.0)
			draw_arc(corner + Vector2(8, 8), 10.0, 0.0, TAU, 16, Color(1.0, 0.85, 0.35, ring), 1.0)
		if two:
			draw_rect(Rect2(corner + Vector2(7, -4 + hop.y), Vector2(2, 2)), HERO_TINTS[slot])
			draw_rect(Rect2(corner + Vector2(6, -5 + hop.y), Vector2(4, 1)), HERO_TINTS[slot])

func _draw_flames() -> void:
	var frame := int(clock * 14.0) % Sprites.FLAME_FRAMES
	for at: int in game.flames:
		var flame: Actors.Flame = game.flames[at]
		var piece := "c"
		if flame.axis != 0:
			piece = "tip%d" % flame.tip if flame.tip >= 0 else ("h" if flame.axis == 1 else "v")
		var tint := Color(1, 1, 1, clampf(flame.ttl / 0.15, 0.0, 1.0))
		if flame.owner < 0:
			tint = Color(1.0, 0.7, 0.9, tint.a)
		draw_texture(tex["flame_%s_%d" % [piece, frame]], Vector2(Levels.cell_of(at)) * TILE, tint)

func _draw_hazard_shadows() -> void:
	for hazard: Dictionary in game.hazards:
		var near := 1.0 - float(hazard["ttl"]) / float(hazard["total"])
		var centre := (Vector2(hazard["cell"]) + Vector2(0.5, 0.5)) * TILE
		var half := 3.0 + 4.0 * near
		draw_rect(Rect2(centre - Vector2(half, half * 0.6), Vector2(half * 2.0, half * 1.2)), Color(0, 0, 0, 0.25 + 0.3 * near))
		if int(clock * 10.0) % 2 == 0:
			draw_rect(Rect2((Vector2(hazard["cell"]) * TILE) + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), Color(1.0, 0.3, 0.25, 0.7), false, 1.0)
	for at: int in game.impacts:
		draw_rect(Rect2(Vector2(Levels.cell_of(at)) * TILE, Vector2(TILE, TILE)), Color(1.0, 0.9, 0.8, clampf(float(game.impacts[at]) / 0.3, 0.0, 1.0) * 0.6))

func _draw_hazards() -> void:
	for hazard: Dictionary in game.hazards:
		var corner := Vector2(hazard["cell"]) * TILE
		var height := float(hazard["ttl"]) / float(hazard["total"]) * 150.0
		draw_texture(tex["boulder"], corner + Vector2(0, -height))

func _draw_particles() -> void:
	for spark: Dictionary in particles:
		var tint: Color = spark["c"]
		tint.a *= clampf(float(spark["life"]) / float(spark["max"]) * 1.6, 0.0, 1.0)
		var size := float(spark["s"])
		draw_rect(Rect2((spark["p"] as Vector2).floor(), Vector2(ceilf(size), ceilf(size))), tint)

func _draw_floaters() -> void:
	for floater: Dictionary in floaters:
		var spent := 1.0 - float(floater["life"]) / float(floater["max"])
		var text := str(floater["text"])
		var at := (floater["p"] as Vector2) + Vector2(-float(text.length()) * 2.0, -14.0 * spent)
		var tint: Color = floater["c"]
		tint.a = clampf(float(floater["life"]) * 3.0, 0.0, 1.0)
		_number(at.floor() + Vector2(1, 1), text, Color(0, 0, 0, tint.a))
		_number(at.floor(), text, tint)

## Draw digits (and x, P, +) in the 3x5 pixel face. Returns the x after the last one.
func _number(at: Vector2, text: String, tint: Color, scale: int = 1) -> float:
	var x := at.x
	for index in text.length():
		var glyph: Texture2D = tex.get("glyph_" + text[index])
		if glyph != null:
			draw_texture_rect(glyph, Rect2(x, at.y, 3 * scale, 5 * scale), false, tint)
		x += 4.0 * float(scale)
	return x

# ---- side panels ----

func _panel(box: Rect2) -> void:
	draw_rect(box, PANEL_FILL)
	draw_rect(box, FRAME_DARK, false, 2.0)
	draw_rect(box.grow(-2.0), Color(FRAME_LIGHT, 0.55), false, 1.0)
	for corner in [box.position, box.position + Vector2(box.size.x - 3, 0), box.position + Vector2(0, box.size.y - 3), box.end - Vector2(3, 3)]:
		draw_rect(Rect2(corner, Vector2(3, 3)), Color("b9b3c4"))

func _draw_panels(world: int) -> void:
	_panel(LEFT_PANEL)
	_gear(LEFT_PANEL.position, 0)
	var left := LEFT_PANEL.position
	draw_rect(Rect2(left + Vector2(6, 84), Vector2(68, 1)), Color(FRAME_LIGHT, 0.5))
	# Creatures still about, and continues in hand.
	draw_texture(tex["grub_%d" % (int(clock * 3.0) % 2)], left + Vector2(6, 88))
	_number(left + Vector2(26, 94), "x%d" % game.foes_left(), Color.WHITE)
	draw_texture(tex["hero0_helmet"], left + Vector2(44, 86))
	_number(left + Vector2(63, 94), "x%d" % game.continues_left, Color.WHITE)
	draw_rect(Rect2(left + Vector2(6, 108), Vector2(68, 1)), Color(FRAME_LIGHT, 0.5))
	_shaft(left + Vector2(40, 116), world)
	_panel(RIGHT_PANEL)
	_gear(RIGHT_PANEL.position, 1)

## One digger's corner of a panel: the portrait and the gear carried.
func _gear(corner: Vector2, slot: int) -> void:
	var hero: Actors.Hero = game.heroes[slot]
	var active: bool = game.is_player_active(slot)
	var tint: Color = HERO_TINTS[slot]
	_number(corner + Vector2(7, 9), "P%d" % (slot + 1), tint if active else tint.darkened(0.5), 2)
	var frame := Rect2(corner + Vector2(30, 6), Vector2(40, 36))
	draw_rect(frame, Color(0, 0, 0, 0.45))
	draw_rect(frame, Color(tint, 0.8 if active else 0.3), false, 1.0)
	var portrait := "hero%d_down_0" % slot
	if active and not hero.out and game.phase == Levels.Phase.CLEAR:
		portrait = "hero%d_cheer" % slot
	elif active and hero.dead > 0.0:
		portrait = "hero%d_hurt" % slot
	draw_texture_rect(tex[portrait], Rect2(frame.position + Vector2(4, 2), Vector2(32, 32)), false, Color.WHITE if active and not hero.out else Color(0.25, 0.25, 0.3, 0.9))
	if not active:
		return
	if hero.out:
		draw_multiline_string(font, corner + Vector2(4, 58), _t("out"), HORIZONTAL_ALIGNMENT_CENTER, 72.0, 9, 3, Color(0.85, 0.8, 0.7, 0.9))
		return
	var rows := [["keg", hero.cap, 6, 48], ["blast", hero.blast, 44, 48], ["boots", hero.boots, 6, 64]]
	for row: Array in rows:
		var at := corner + Vector2(float(row[2]), float(row[3]))
		draw_texture(tex["icon_" + str(row[0])], at)
		_number(at + Vector2(13, 3), "x%d" % int(row[1]), Color.WHITE)
	draw_texture(tex["icon_remote"], corner + Vector2(44, 64), Color.WHITE if hero.remote else Color(0.3, 0.3, 0.35, 0.6))
	draw_texture(tex["icon_hat"], corner + Vector2(60, 65), Color.WHITE if hero.shield else Color(0.3, 0.3, 0.35, 0.6))

## The mine shaft as a column of nine lamps: the levels behind are lit, the current one blinks, the two boss levels are ringed in red.
func _shaft(top: Vector2, _world: int) -> void:
	draw_rect(Rect2(top + Vector2(-1, 0), Vector2(2, 9 * 9)), Color("4a2f25"))
	for index in Levels.STAGE_COUNT:
		var centre := top + Vector2(0, 4 + index * 9)
		var tint: Color = WORLD_DUST[Levels.world(index)]
		if index > game.stage:
			tint = tint.darkened(0.7)
		elif index == game.stage and int(clock * 4.0) % 2 == 0:
			tint = Color.WHITE
		var boss: bool = Levels.STAGES[index].has("boss")
		if boss:
			draw_rect(Rect2(centre - Vector2(5, 4), Vector2(10, 8)), Color("d1433a") if index >= game.stage else Color("7c1f33"))
		draw_rect(Rect2(centre - Vector2(3, 3), Vector2(6, 6)), Color("1a1420"))
		draw_rect(Rect2(centre - Vector2(2, 2), Vector2(4, 4)), tint)
		_number(centre + Vector2(-22, -2), str(index + 1), Color(1, 1, 1, 0.9 if index == game.stage else 0.35))
		if index == game.stage:
			draw_texture(tex["hero0_helmet"], centre + Vector2(8, -12))

# ---- banners ----

func _draw_low_air() -> void:
	if game.phase != Levels.Phase.PLAY or game.time_left > 30.0:
		return
	var pulse := 0.5 + 0.5 * sin(clock * (10.0 if game.time_left < 10.0 else 5.0))
	var field := Rect2(Levels.ORIGIN, Vector2(Levels.COLS, Levels.ROWS) * TILE)
	draw_rect(field.grow(-1.0), Color(0.9, 0.2, 0.15, 0.25 + 0.4 * pulse), false, 2.0)

func _draw_banner() -> void:
	var title := ""
	var sub := ""
	var tint := Color("fff6b0")
	match game.phase:
		Levels.Phase.INTRO:
			title = _t("boss_level" if Levels.STAGES[game.stage].has("boss") else "level") % (game.stage + 1)
			sub = Levels.stage_name(game.stage, game.locale)
		Levels.Phase.CLEAR:
			if game.stage >= Levels.STAGE_COUNT - 1:
				title = _t("victory")
				sub = _t("victory_sub")
			else:
				title = _t("clear")
				sub = _t("bonus") % game.clear_bonus
		Levels.Phase.CONTINUE:
			title = _t("continue")
			sub = _t("continue_sub") % maxi(0, game.continues_left - 1)
			tint = Color("f2a3a0")
		Levels.Phase.DEFEAT:
			title = _t("defeat")
			tint = Color("d1433a")
	var centre := Levels.ORIGIN + Vector2(Levels.COLS, Levels.ROWS) * TILE * 0.5
	var width := float(Levels.COLS) * TILE
	if title != "":
		var band := Rect2(Levels.ORIGIN.x, centre.y - 26.0, width, 52.0)
		draw_rect(band, Color(0.04, 0.03, 0.06, 0.82))
		draw_rect(Rect2(band.position, Vector2(width, 1)), FRAME_LIGHT)
		draw_rect(Rect2(band.position + Vector2(0, 51), Vector2(width, 1)), FRAME_LIGHT)
		_text(Vector2(Levels.ORIGIN.x, centre.y + (0.0 if sub != "" else 7.0)), title, width, 20, tint)
		if sub != "":
			_text(Vector2(Levels.ORIGIN.x, centre.y + 18.0), sub, width, 12, Color("f4efe6"))
	elif notice_time > 0.0:
		var fade := clampf(notice_time * 3.0, 0.0, 1.0)
		var band := Rect2(Levels.ORIGIN.x + 40.0, Levels.ORIGIN.y + 20.0, width - 80.0, 20.0)
		draw_rect(band, Color(0.04, 0.03, 0.06, 0.78 * fade))
		_text(Vector2(band.position.x, band.position.y + 15.0), notice, band.size.x, 12, Color(1.0, 0.96, 0.7, fade))

func _text(at: Vector2, text: String, width: float, size: int, tint: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 3, Color(0.05, 0.03, 0.06, tint.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, tint)
