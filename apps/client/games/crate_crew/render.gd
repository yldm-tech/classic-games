extends Node2D

## Draws the world of Crate Crew and owns everything that is only for the eye: particles, screen shake, flashes, floating points and the banners. It reads the simulation and never changes it; its own randomness comes from a private generator so the game's seeded sequence is untouched.

const World := preload("res://games/crate_crew/world.gd")
const Foes := preload("res://games/crate_crew/foes.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Sprites := preload("res://games/crate_crew/sprites.gd")
const Backdrops := preload("res://games/crate_crew/backdrops.gd")
const Bosses := preload("res://games/crate_crew/bosses.gd")
const Texts := preload("res://games/crate_crew/texts.gd")
const Rng := preload("res://games/shared/game_rng.gd")

const VIEW := Vector2(384, 216)
const MAX_PARTICLES := 220
const MAX_PENDING := 96
const HERO_COLORS := [Color("5fd4c4"), Color("f5a340")]

var world: World
var locale := "zh"
var players := 1

var _textures: Dictionary = {}
var _layers: Dictionary = {}
var _font: SystemFont
var _font_locale := ""
var _random: GameRng = Rng.new(20261)
var _pending: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _shake := 0.0
var _flash := 0.0
var _clock := 0.0
var _offset := Vector2.ZERO

func setup(simulation: World, language: String) -> void:
	world = simulation
	locale = language
	_pending.clear()
	_particles.clear()
	_popups.clear()
	_shake = 0.0
	_flash = 0.0

## Called from the step with what the world reported; kept short so a run without frames (a test) cannot pile them up.
func note(event: Dictionary) -> void:
	if _pending.size() < MAX_PENDING:
		_pending.append(event)

## Once per rendered frame: build the art on first use, turn events into effects, age the particles.
func advance(delta: float) -> void:
	if _textures.is_empty():
		_textures = Sprites.new().build()
	if _font == null or _font_locale != locale:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Noto Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"])
		_font.allow_system_fallback = true
		# At this size Chinese reads best as hard pixels and Latin letters need their grey edges.
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY if locale == "en" else TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NORMAL
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font_locale = locale
	_clock += delta
	for event in _pending:
		_react(event)
	_pending.clear()
	_shake = maxf(0.0, _shake - delta * 14.0)
	_flash = maxf(0.0, _flash - delta)
	_offset = Vector2(roundf(_random.float_range(-_shake, _shake)), roundf(_random.float_range(-_shake, _shake))) if _shake > 0.3 else Vector2.ZERO
	if world != null and not world.boss.is_empty():
		if str(world.boss["mode"]) == "inhale" and _random.chance(0.6):
			var facing := float(int(world.boss["face"]))
			var mouth := Vector2(float(world.boss["x"]) + facing * 24.0, float(world.boss["y"]) - 16.0)
			var from := mouth + Vector2(facing * _random.float_range(60.0, 200.0), _random.float_range(-50.0, 14.0))
			_spark(from, (mouth - from) * 1.6, 0.0, 0.6, Color("c9c2d6"), 1.0)
		if float(world.boss.get("shake", 0.0)) > 0.0:
			_shake = maxf(_shake, 1.2)
	if world != null:
		for object in world.objects:
			if int(object["state"]) == World.O_THROWN and _random.chance(0.5):
				_spark(Vector2(float(object["x"]), float(object["y"]) - float(object["tall"]) * 0.5 + _random.float_range(-4.0, 4.0)), Vector2.ZERO, 0.0, 0.18, Color("f4f1e8"), 1.0)
	for particle in _particles:
		particle["life"] = float(particle["life"]) - delta
		particle["vy"] = float(particle["vy"]) + float(particle["g"]) * delta
		particle["x"] = float(particle["x"]) + float(particle["vx"]) * delta
		particle["y"] = float(particle["y"]) + float(particle["vy"]) * delta
	_particles = _particles.filter(func(particle: Dictionary) -> bool: return float(particle["life"]) > 0.0)
	for popup in _popups:
		popup["life"] = float(popup["life"]) - delta
		popup["y"] = float(popup["y"]) - 22.0 * delta
	_popups = _popups.filter(func(popup: Dictionary) -> bool: return float(popup["life"]) > 0.0)
	queue_redraw()

# ---- effects ----

func _spark(at: Vector2, velocity: Vector2, gravity: float, life: float, color: Color, size: float) -> void:
	if _particles.size() < MAX_PARTICLES:
		_particles.append({"x": at.x, "y": at.y, "vx": velocity.x, "vy": velocity.y, "g": gravity, "life": life, "span": life, "color": color, "size": size})

func _burst(at: Vector2, count: int, speed: float, gravity: float, life: float, colors: Array, size: float) -> void:
	for index in count:
		var angle := _random.float_range(0.0, TAU)
		var pace := _random.float_range(speed * 0.35, speed)
		_spark(at, Vector2(cos(angle), sin(angle)) * pace - Vector2(0, speed * 0.3), gravity, _random.float_range(life * 0.5, life), colors[index % colors.size()], size)

func _react(event: Dictionary) -> void:
	var at := Vector2(float(event["x"]), float(event["y"]))
	match str(event["name"]):
		"jump":
			_burst(at, 2, 20.0, 60.0, 0.25, [Color("d8d2c4")], 1.0)
		"land", "thud", "put_down":
			_burst(at, 4, 34.0, 80.0, 0.3, [Color("d8d2c4"), Color("a39c8e")], 1.0)
		"throw", "throw_up":
			_burst(at, 3, 30.0, 0.0, 0.2, [Color("f4f1e8")], 1.0)
		"break":
			_burst(at, 10, 95.0, 420.0, 0.6, [Color("c98f52"), Color("96623a"), Color("f0d9a8"), Color("5f3b28")], 2.0)
			_burst(at, 5, 30.0, 0.0, 0.3, [Color("f0d9a8")], 1.0)
			_shake = maxf(_shake, 1.5)
		"poof":
			_burst(at, 6, 45.0, 120.0, 0.35, [Color("b9c0c9"), Color("7b8794")], 1.0)
		"clang":
			_burst(at, 5, 80.0, 200.0, 0.25, [Color("ffd75e"), Color("f4f1e8")], 1.0)
		"foe_hit":
			_burst(at, 5, 70.0, 200.0, 0.3, [Color("f4f1e8"), Color("ffd75e")], 1.0)
			_shake = maxf(_shake, 1.5)
		"foe_out":
			_burst(at, 9, 100.0, 260.0, 0.45, [Color("f4f1e8"), Color("ffd75e"), Color("ff8a3c")], 2.0)
			_shake = maxf(_shake, 2.2)
		"hurt":
			_burst(at, 8, 90.0, 240.0, 0.4, [Color("e5484d"), Color("f4f1e8")], 1.0)
			_shake = maxf(_shake, 3.0)
			_flash = maxf(_flash, 0.06)
		"die":
			_burst(at, 16, 120.0, 300.0, 0.8, [HERO_COLORS[int(event.get("slot", 0))], Color("f4f1e8"), Color("b9c0c9")], 2.0)
			_shake = maxf(_shake, 4.0)
		"respawn":
			_burst(at, 10, 60.0, -40.0, 0.5, [Color("bff3ff"), Color("f4f1e8")], 1.0)
		"gear":
			_burst(at, 4, 40.0, 0.0, 0.25, [Color("ffd75e")], 1.0)
		"battery", "chip", "flag":
			_burst(at, 10, 60.0, -30.0, 0.5, [Color("b8ff9a"), Color("f4f1e8"), Color("5fd4c4")], 1.0)
		"cog":
			_burst(at, 18, 90.0, 60.0, 0.8, [Color("ffd75e"), Color("f4f1e8"), Color("c9952c")], 2.0)
			_flash = maxf(_flash, 0.08)
		"chute":
			_burst(at, 4, 30.0, 100.0, 0.3, [Color("b9c0c9")], 1.0)
		"shot", "drop", "boss_spit":
			_burst(at, 4, 50.0, 0.0, 0.2, [Color("ffd75e"), Color("f4f1e8")], 1.0)
		"boss_hit":
			_burst(at, 14, 130.0, 260.0, 0.5, [Color("f4f1e8"), Color("ffd75e"), Color("e5484d")], 2.0)
			_shake = maxf(_shake, 3.5)
			_flash = maxf(_flash, 0.07)
		"boss_slam":
			for index in 12:
				_spark(at + Vector2(_random.float_range(-26.0, 26.0), 0.0), Vector2(_random.float_range(-40.0, 40.0), _random.float_range(-90.0, -20.0)), 260.0, 0.5, Color("d8d2c4"), 2.0)
			_shake = maxf(_shake, 6.0)
		"boss_burst":
			_burst(at, 12, 110.0, 120.0, 0.55, [Color("ff8a3c"), Color("ffd75e"), Color("f4f1e8"), Color("4a5463")], 3.0)
			_shake = maxf(_shake, 3.0)
		"boss_down":
			_burst(at, 40, 190.0, 200.0, 1.1, [Color("ff8a3c"), Color("ffd75e"), Color("f4f1e8"), Color("7b8794")], 3.0)
			_shake = maxf(_shake, 9.0)
			_flash = maxf(_flash, 0.35)
		"boss_start", "boss_angry":
			_shake = maxf(_shake, 5.0)
		"stage_clear":
			for index in 36:
				_spark(Vector2(world.camera.x + _random.float_range(0.0, VIEW.x), world.camera.y - 4.0), Vector2(_random.float_range(-20.0, 20.0), _random.float_range(30.0, 110.0)), 30.0, 2.4, [Color("5fd4c4"), Color("f5a340"), Color("ffd75e"), Color("f4f1e8")][index % 4], 2.0)
		"points":
			if _popups.size() < 12:
				_popups.append({"x": at.x, "y": at.y, "text": "+%d" % int(event.get("points", 0)), "life": 0.9})

# ---- drawing ----

func _draw() -> void:
	if world == null or _textures.is_empty() or _font == null:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color("1a1423"))
		return
	var camera := Vector2(roundf(world.camera.x), roundf(world.camera.y)) + _offset
	_draw_backdrop(camera)
	draw_set_transform(-camera)
	_draw_tiles(camera)
	_draw_fixtures()
	for lift in world.lifts:
		_draw_lift(lift)
	for pickup in world.pickups:
		_draw_pickup(pickup)
	for object in world.objects:
		if int(object["state"]) == World.O_REST:
			_draw_object(object)
	for foe in world.foes:
		_draw_foe(foe)
	if not world.boss.is_empty():
		_draw_boss(world.boss)
	for hero in world.heroes:
		_draw_hero(hero)
	for object in world.objects:
		if int(object["state"]) != World.O_REST:
			_draw_object(object)
	for shot in world.shots:
		_draw_shot(shot)
	for particle in _particles:
		var size := float(particle["size"])
		if float(particle["life"]) < float(particle["span"]) * 0.4:
			size = maxf(1.0, size - 1.0)
		draw_rect(Rect2(roundf(float(particle["x"])), roundf(float(particle["y"])), size, size), particle["color"])
	for popup in _popups:
		_text(str(popup["text"]), Vector2(float(popup["x"]), float(popup["y"])), 8, Color("ffd75e"))
	# One hint at a time: the one nearest to a robot, and only while that robot stands by it.
	var hint_key := ""
	var hint_x := 0.0
	var hint_distance := 44.0
	for hint: Dictionary in world.level.get("hints", []):
		var at: Vector2 = hint["at"]
		for hero in world.heroes:
			if int(hero["state"]) != World.H_OUT and absf(float(hero["x"]) - at.x) < hint_distance:
				hint_distance = absf(float(hero["x"]) - at.x)
				hint_key = str(hint["key"])
				hint_x = at.x
	if hint_key != "" and world.phase == World.P_PLAY:
		_plate(Texts.of(hint_key, locale), Vector2(clampf(hint_x, camera.x + 100.0, camera.x + VIEW.x - 100.0), camera.y + 80.0), 10, Color("f4f1e8"))
	draw_set_transform(Vector2.ZERO)
	_draw_banners()
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(1, 1, 1, minf(0.6, _flash * 4.0)))

func _draw_backdrop(camera: Vector2) -> void:
	var stage := world.stage
	if not _layers.has(stage):
		_layers[stage] = Backdrops.new().build(stage)
	var layer: Dictionary = _layers[stage]
	for pass_index in 2:
		var texture: Texture2D = layer["far"] if pass_index == 0 else layer["near"]
		var factor := 0.22 if pass_index == 0 else 0.5
		var shift := Vector2(posmod(int(camera.x * factor), 256), posmod(int(camera.y * factor), 256))
		for row in 2:
			for column in 3:
				draw_texture(texture, Vector2(float(column * 256) - shift.x, float(row * 256) - shift.y))

func _draw_tiles(camera: Vector2) -> void:
	var stage := world.stage
	var first_column := maxi(0, floori(camera.x / 16.0))
	var last_column := mini(world.width - 1, floori((camera.x + VIEW.x) / 16.0))
	var first_row := maxi(0, floori(camera.y / 16.0))
	var last_row := mini(world.height - 1, floori((camera.y + VIEW.y) / 16.0))
	var belt_frame := int(_clock * 8.0) % 4
	for row in range(first_row, last_row + 1):
		for column in range(first_column, last_column + 1):
			var tile := world.tile_at(column, row)
			if tile == Levels.EMPTY:
				continue
			var name := ""
			match tile:
				Levels.SOLID:
					name = "tile%d_in" % stage if World.is_solid(world.tile_at(column, row - 1)) and row > 0 else "tile%d_top" % stage
				Levels.SHELF:
					name = "tile%d_shelf" % stage
				Levels.SPIKES:
					name = "tile%d_spikes" % stage
				Levels.BELT_LEFT:
					name = "tile%d_belt%d" % [stage, 3 - belt_frame]
				Levels.BELT_RIGHT:
					name = "tile%d_belt%d" % [stage, belt_frame]
			# Ground gets darker the deeper it lies under its surface.
			var shade := Color.WHITE
			if tile == Levels.SOLID and World.is_solid(world.tile_at(column, row - 2)) and row > 1:
				shade = Color(0.8, 0.8, 0.84) if not World.is_solid(world.tile_at(column, row - 3)) or row < 3 else Color(0.62, 0.62, 0.7)
			draw_texture(_textures[name], Vector2(column * 16, row * 16), shade)

func _draw_fixtures() -> void:
	var door: Variant = world.level.get("door")
	if door is Vector2:
		_sprite("door_open" if world.door_open else "door", (door as Vector2).x, (door as Vector2).y, false)
	for chute in world.chutes:
		_sprite("chute", float(chute["x"]), float(chute["y"]) + 14.0, false)
	for index in world.flags.size():
		var flag: Vector2 = world.flags[index]
		_sprite("flag_on" if index <= world.checkpoint else "flag_off", flag.x + 3.0, flag.y, false)

func _draw_lift(lift: Dictionary) -> void:
	var x := roundf(float(lift["x"]))
	var y := roundf(float(lift["y"]))
	var wide := float(lift["w"])
	draw_texture(_textures["lift_l"], Vector2(x, y))
	var at := 8.0
	while at < wide - 8.0:
		draw_texture(_textures["lift_m"], Vector2(x + at, y))
		at += 16.0
	draw_texture(_textures["lift_r"], Vector2(x + wide - 8.0, y))

func _draw_pickup(pickup: Dictionary) -> void:
	var x := float(pickup["x"])
	var y := float(pickup["y"])
	var kind := str(pickup["kind"])
	if bool(pickup["float"]):
		y += sin(_clock * 4.0 + x * 0.1) * 1.5
	var name := kind
	if kind == "gear":
		name = "gear%d" % (int(_clock * 6.0 + x * 0.05) % 2)
	_sprite(name, x, y, false)
	if kind == "cog" and int(_clock * 8.0) % 3 == 0:
		draw_rect(Rect2(roundf(x + 4.0), roundf(y - 13.0), 2, 2), Color("f4f1e8"))

func _draw_object(object: Dictionary) -> void:
	var life := float(object["life"])
	if life > 0.0 and life < 2.0 and int(_clock * 12.0) % 2 == 0:
		return
	var kind := str(object["kind"])
	var x := float(object["x"])
	var y := float(object["y"])
	if int(object["state"]) == World.O_THROWN and (kind == "scrap" or kind == "hexnut"):
		_spun(kind, x, y - 6.0, float(object["spin"]) * 14.0)
		return
	_sprite(kind, x, y, false)

func _draw_shot(shot: Dictionary) -> void:
	var x := float(shot["x"])
	var y := float(shot["y"])
	match str(shot["kind"]):
		"spark":
			_sprite("spark%d" % (int(_clock * 14.0) % 2), x, y + 3.0, false)
		"nut":
			_spun("nut", x, y, float(shot["time"]) * 9.0)
		"junk":
			_spun("scrap", x, y, float(shot["time"]) * 9.0)
		_:
			_spun("hexnut", x, y, float(shot["time"]) * 7.0)

func _draw_foe(foe: Dictionary) -> void:
	var kind := str(foe["kind"])
	var x := float(foe["x"])
	var y := float(foe["y"])
	var time := float(foe["time"])
	var name := kind + "0"
	var mode := str(foe["mode"])
	match kind:
		"bug":
			name = "bug%d" % (int(time * 8.0) % 2)
		"hopper":
			name = "hopper%d" % (0 if bool(foe["ground"]) else 1)
		"drone":
			name = "drone%d" % (int(time * 14.0) % 2)
		"turret":
			name = "turret%d" % (1 if mode == "aim" else 0)
		"roller":
			var turning := mode == "dash" or mode == "walk"
			name = "%s%d" % ["roller" if int(foe["hp"]) > 1 else "roller_bare", (int(time * (16.0 if mode == "dash" else 6.0)) % 2) if turning else 0]
			if mode == "rev":
				x += float(int(time * 40.0) % 2) * 2.0 - 1.0
		"magnet":
			name = "magnet%d" % (int(time * 12.0) % 2)
	if int(foe["state"]) == Foes.KNOCKED_OUT:
		_spun(name + ("#w" if time < 0.1 else ""), x, y - float(foe["tall"]) * 0.5, time * 12.0 * signf(float(foe["vx"])))
		return
	var flipped := int(foe["face"]) < 0
	_sprite(name + ("#w" if float(foe["flash"]) > 0.0 else ""), x, y + (2.0 if kind == "magnet" or kind == "drone" else 0.0), flipped)
	if mode == "dizzy":
		for star in 2:
			var angle := _clock * 7.0 + float(star) * PI
			draw_rect(Rect2(roundf(x + cos(angle) * 7.0), roundf(y - float(foe["tall"]) - 5.0 + sin(angle) * 2.0), 2, 2), Color("ffd75e"))

func _draw_boss(boss: Dictionary) -> void:
	var mode := str(boss["mode"])
	if mode == "gone":
		return
	var x := float(boss["x"])
	var y := float(boss["y"])
	var hurt := float(boss["flash"]) > 0.0 or mode == "dying"
	var white := float(boss["flash"]) > 0.2 or (mode == "dying" and int(_clock * 16.0) % 2 == 0)
	if float(boss.get("shake", 0.0)) > 0.0:
		x += float(int(_clock * 40.0) % 2) * 2.0 - 1.0
	if str(boss["kind"]) == "vacuum":
		var open := mode == "spit" or mode == "inhale"
		var name := "vac_%d_%d" % [1 if open else 0, 1 if hurt else 0]
		# The sprite faces left; the wheels sit on the floor.
		_sprite(name + ("#w" if white else ""), x + (2.0 if int(boss["face"]) < 0 else -2.0), y + 1.0, int(boss["face"]) > 0)
		return
	# The rail across the room, the trolley, the chain and the claw.
	draw_rect(Rect2(float(boss["left"]), y - 3.0, float(boss["right"]) - float(boss["left"]), 4.0), Color("4a5463"))
	draw_rect(Rect2(float(boss["left"]), y - 3.0, float(boss["right"]) - float(boss["left"]), 1.0), Color("b9c0c9"))
	var chain := float(boss["claw"])
	var link := 0.0
	while link < chain:
		draw_rect(Rect2(roundf(x) - 1.0, roundf(y + 27.0 + link), 3.0, 3.0), Color("7b8794") if int(link / 4.0) % 2 == 0 else Color("4a5463"))
		link += 4.0
	_sprite("crane_%d" % (1 if hurt else 0) + ("#w" if white else ""), x, y + 28.0, false)
	if not Bosses.is_open(boss) and mode != "dying":
		# The shutter over the lens.
		draw_rect(Rect2(roundf(x) - 8.0, roundf(y) + 9.0, 16.0, 11.0), Color("4a5463"))
		draw_rect(Rect2(roundf(x) - 8.0, roundf(y) + 9.0, 16.0, 1.0), Color("b9c0c9"))
		draw_rect(Rect2(roundf(x) - 8.0, roundf(y) + 13.0, 16.0, 1.0), Color("222834"))
		draw_rect(Rect2(roundf(x) - 8.0, roundf(y) + 17.0, 16.0, 1.0), Color("222834"))
	var shut := mode == "stuck" or mode == "retract"
	_sprite("claw_shut" if shut else "claw_open", x, y + 28.0 + chain + 22.0, false)

func _draw_hero(hero: Dictionary) -> void:
	var state := int(hero["state"])
	if state == World.H_OUT:
		return
	var slot := int(hero["slot"])
	var x := float(hero["x"])
	var y := float(hero["y"])
	var prefix := "hero%d_" % slot
	if state == World.H_DEAD:
		_spun(prefix + "fall_hurt", x, y - 8.0, _clock * 14.0)
		return
	if float(hero["inv"]) > 0.0 and int(_clock * 20.0) % 2 == 0 and world.phase == World.P_PLAY:
		return
	if state == World.H_THROWN:
		_spun(prefix + "jump_open", x, y - 8.0, float(hero["throw_time"]) * 18.0 * float(int(hero["face"])))
		return
	var legs := "idle"
	var head := "open"
	var anim := float(hero["anim"])
	if bool(hero["hide"]):
		legs = "squat"
	elif state == World.H_CARRIED:
		legs = "jump"
	elif not bool(hero["ground"]):
		legs = "jump" if float(hero["vy"]) < 0.0 else "fall"
	elif absf(float(hero["vx"])) > 6.0:
		legs = "apart" if int(anim * 10.0) % 2 == 0 else "close"
	if float(hero["stun"]) > 0.0:
		head = "hurt"
		legs = "fall"
	elif legs == "idle" and fmod(anim + float(slot), 3.2) < 0.12:
		head = "blink"
	if legs != "idle" and legs != "fall":
		head = "open"
	var flipped := int(hero["face"]) < 0
	var raised: bool = hero["carry"] != null or int(hero["lifting"]) >= 0 or float(hero["lift_time"]) > 0.0 or legs == "fall"
	_sprite(prefix + legs + "_" + head, x, y + 1.0, flipped)
	if legs != "squat":
		_sprite(prefix + ("arms_up" if raised else "arms_down"), x, y + (2.0 if legs == "apart" else 1.0), flipped)
	if players > 1 and world.stage_time < 4.0:
		draw_rect(Rect2(roundf(x) - 1.0, roundf(y) - 26.0 + float(int(_clock * 4.0) % 2), 3, 3), HERO_COLORS[slot])

# ---- helpers ----

## Draw a sprite with x at its middle and y at its bottom.
func _sprite(name: String, x: float, y: float, flipped: bool) -> void:
	var texture: Texture2D = _textures.get(name)
	if texture == null:
		return
	var size := texture.get_size()
	var left := roundf(x - size.x * 0.5)
	var top := roundf(y - size.y)
	if flipped:
		draw_texture_rect(texture, Rect2(left + size.x, top, -size.x, size.y), false)
	else:
		draw_texture(texture, Vector2(left, top))

## Draw a sprite turned round its middle, which is at (x, y).
func _spun(name: String, x: float, y: float, angle: float) -> void:
	var texture: Texture2D = _textures.get(name)
	if texture == null:
		return
	var camera := Vector2(roundf(world.camera.x), roundf(world.camera.y)) + _offset
	# Quarter turns keep the pixels square.
	var snapped_angle := roundf(angle / (PI * 0.5)) * PI * 0.5
	draw_set_transform(Vector2(roundf(x), roundf(y)) - camera, snapped_angle)
	draw_texture(texture, -texture.get_size() * 0.5)
	draw_set_transform(-camera)

func _text(text: String, at: Vector2, size: int, color: Color) -> void:
	var wide := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := Vector2(roundf(at.x - wide * 0.5), roundf(at.y))
	draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, Color("1a1423"))
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Text on a small dark plate, for hints standing in the stage.
func _plate(text: String, at: Vector2, size: int, color: Color) -> void:
	var wide := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var box := Rect2(roundf(at.x - wide * 0.5) - 4.0, roundf(at.y) - float(size) - 2.0, wide + 8.0, float(size) + 6.0)
	draw_rect(box, Color(0.1, 0.08, 0.14, 0.82))
	draw_rect(Rect2(box.position, Vector2(box.size.x, 1.0)), Color("5fd4c4"))
	draw_string(_font, Vector2(box.position.x + 4.0, roundf(at.y)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _band(title: String, subtitle: String, accent: Color) -> void:
	draw_rect(Rect2(0, 84, VIEW.x, 50), Color(0.1, 0.08, 0.14, 0.86))
	draw_rect(Rect2(0, 84, VIEW.x, 2), accent)
	draw_rect(Rect2(0, 132, VIEW.x, 2), accent)
	_text(title, Vector2(VIEW.x * 0.5, 108 if subtitle != "" else 115), 16, Color("f4f1e8"))
	if subtitle != "":
		_text(subtitle, Vector2(VIEW.x * 0.5, 125), 11, accent)

func _draw_banners() -> void:
	match world.phase:
		World.P_INTRO:
			_band(Texts.of("stage", locale) % (world.stage + 1), str(Levels.NAMES[world.stage]["en" if locale == "en" else "zh"]), Color("5fd4c4"))
		World.P_CLEAR, World.P_WON:
			var last := world.stage + 1 >= Levels.COUNT
			_band(Texts.of("won" if last else "clear", locale), "", Color("ffd75e"))
		World.P_RETRY:
			_band(Texts.of("continue", locale) % maxi(0, world.continues_left - 1), "", Color("f5a340"))
		World.P_OVER, World.P_LOST:
			_band(Texts.of("lost", locale), "", Color("e5484d"))
		_:
			if not world.boss.is_empty() and str(world.boss["mode"]) == "enter":
				var kind := str(world.boss["kind"])
				_band(Texts.of("boss_" + kind, locale), Texts.of("boss_tip_" + kind, locale), Color("e5484d"))
