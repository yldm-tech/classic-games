extends Node2D

## Everything the player sees of a run. The view reads the World and never changes it; what it adds on its own (particles, score pop-ups, screen shake, ambient motion) is decoration that the simulation does not know about, so it may use the global random functions.

const World := preload("res://games/yarn_tumble/world.gd")
const Hero := preload("res://games/yarn_tumble/hero.gd")
const Foe := preload("res://games/yarn_tumble/foe.gd")
const Boss := preload("res://games/yarn_tumble/boss.gd")
const Item := preload("res://games/yarn_tumble/item.gd")
const Levels := preload("res://games/yarn_tumble/levels.gd")
const Sprites := preload("res://games/yarn_tumble/sprites.gd")
const Backdrop := preload("res://games/yarn_tumble/backdrop.gd")

const INK := Color("1b1420")
const CREAM := Color("f6f0e4")
const GOLD := Color("ffd75a")
## How far below its feet line a creature's sprite is drawn, so that its feet meet the ledge.
const FOE_DROP := {"moth": 1.0, "spring": 0.0, "pin": 1.0, "snip": 2.0, "ink": 0.0}
const BOSS_NAMES := [{"zh": "绒翼女爵", "en": "DUCHESS DUSTWING"}, {"zh": "铁剪摄政", "en": "THE SNIPJAW REGENT"}]
const MAX_PENDING := 96

var world: World
var locale := "zh"
var art: Sprites
var font: SystemFont

var _backdrop: ImageTexture
var _backdrop_stage := -1
var _time := 0.0
var _shake := 0.0
var _flash := 0.0
var _pending: Array = []
var _particles: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _notice := ""
var _notice_time := 0.0

func setup(run_world: World, language: String) -> void:
	world = run_world
	locale = language
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"])
	font.allow_system_fallback = true
	font.font_weight = 700

## A world event, kept until the next rendered frame turns it into effects. Headless runs never render, so the queue is bounded.
func notice(event: Array) -> void:
	_pending.append(event)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()

func animate(delta: float) -> void:
	_time += delta
	for event: Array in _pending:
		_react(event)
	_pending.clear()
	_shake = maxf(0.0, _shake - delta * 14.0)
	_flash = maxf(0.0, _flash - delta * 3.0)
	_notice_time = maxf(0.0, _notice_time - delta)
	position = Vector2(roundf(randf_range(-_shake, _shake)), roundf(randf_range(-_shake, _shake))) if _shake > 0.3 else Vector2.ZERO
	var kept: Array[Dictionary] = []
	for particle in _particles:
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			continue
		particle["vy"] = float(particle["vy"]) + float(particle["gravity"]) * delta
		particle["x"] = float(particle["x"]) + float(particle["vx"]) * delta
		particle["y"] = float(particle["y"]) + float(particle["vy"]) * delta
		kept.append(particle)
	_particles = kept
	var shown: Array[Dictionary] = []
	for popup in _popups:
		popup["life"] = float(popup["life"]) - delta
		popup["y"] = float(popup["y"]) - 16.0 * delta
		if float(popup["life"]) > 0.0:
			shown.append(popup)
	_popups = shown
	queue_redraw()

# ---- effects ----

func _yarn(slot: int) -> Color:
	return Sprites.HERO_COLORS[clampi(slot, 0, 1)]["1"]

func _burst(x: float, y: float, count: int, color: Color, speed: float, life: float = 0.5, gravity: float = 260.0, size: float = 2.0) -> void:
	for index in count:
		var angle := randf() * TAU
		var pace := speed * randf_range(0.35, 1.0)
		_particles.append({"x": x, "y": y, "vx": cos(angle) * pace, "vy": sin(angle) * pace - speed * 0.3, "gravity": gravity, "life": life * randf_range(0.6, 1.0), "span": life, "color": color, "size": size})

func _popup(x: float, y: float, text: String, color: Color) -> void:
	_popups.append({"x": clampf(x, 30.0, 450.0), "y": maxf(y, 50.0), "text": text, "life": 0.9, "color": color})

func _say(zh: String, en: String, seconds: float) -> void:
	_notice = zh if locale == "zh" else en
	_notice_time = seconds

func _react(event: Array) -> void:
	var x := float(event[1])
	var y := float(event[2])
	var value := int(event[3])
	match str(event[0]):
		"jump":
			_burst(x, y, 3, Color("c8b8a0"), 26.0, 0.25, 60.0, 1.0)
		"wrap":
			_burst(x, y - 8.0, 4, CREAM, 50.0, 0.3)
		"ball":
			_burst(x, y - 8.0, 12, _yarn(value), 80.0, 0.45)
			_burst(x, y - 8.0, 6, CREAM, 50.0, 0.35)
		"kick":
			_burst(x, y - 2.0, 8, Color("c8b8a0"), 60.0, 0.35, 80.0)
			_shake = maxf(_shake, 1.5)
		"bounce", "thud":
			_burst(x, y - 2.0, 5, Color("c8b8a0"), 45.0, 0.3, 80.0, 1.0)
		"ko":
			_burst(x, y, 10, GOLD, 110.0, 0.5)
			_burst(x, y, 5, CREAM, 70.0, 0.4)
			_popup(x, y - 6.0, str(value), GOLD if int(event[4]) < 3 else Color("ff9ec4"))
			_shake = maxf(_shake, 2.0 + minf(3.0, float(event[4])))
		"burst":
			_burst(x, y, 16, _yarn(int(event[4])), 120.0, 0.6)
			_burst(x, y, 8, CREAM, 80.0, 0.5)
			_popup(x, y - 4.0, "500", CREAM)
			_shake = maxf(_shake, 2.5)
		"gem":
			_burst(x, y, 6, GOLD, 60.0, 0.35, 0.0, 1.0)
			_popup(x, y - 4.0, str(value), CREAM)
		"power", "heart", "join", "respawn":
			_burst(x, y, 14, Color("9cd0ff"), 70.0, 0.5, -40.0, 1.0)
		"hurt":
			_burst(x, y - 8.0, 16, _yarn(value), 120.0, 0.7)
			_burst(x, y - 8.0, 8, Color("e0455a"), 90.0, 0.5)
			_shake = maxf(_shake, 5.0)
		"free":
			_burst(x, y - 8.0, 10, CREAM, 90.0, 0.4)
		"loosen":
			_burst(x, y - 8.0, 5, CREAM, 40.0, 0.3)
		"spit":
			_burst(x, y - 6.0, 4, Color("3fb8b0"), 50.0, 0.3)
		"pop":
			_burst(x, y - 3.0, 6, Color("3fb8b0"), 60.0, 0.3)
		"charge", "hop":
			_burst(x, y - 1.0, 4, Color("c8b8a0"), 40.0, 0.3, 60.0, 1.0)
		"hatch", "egg":
			_burst(x, y - 4.0, 6, CREAM, 50.0, 0.3)
		"slam":
			_burst(x, y, 18, Color("c8b8a0"), 130.0, 0.5, 200.0)
			_shake = maxf(_shake, 7.0)
		"boom":
			_burst(x, y, 9, Color("f08a3c"), 100.0, 0.45)
			_burst(x, y, 5, GOLD, 60.0, 0.35)
			_shake = maxf(_shake, 3.0)
		"boss_hit":
			_burst(x, y, 6 + value, CREAM, 110.0, 0.4)
			_shake = maxf(_shake, 2.0 if value < 5 else 6.0)
			if value >= 5:
				_flash = 0.5
		"boss_down":
			_flash = 1.0
			_shake = 9.0
		"boss_gone":
			_burst(x, y, 40, GOLD, 170.0, 0.9)
			_popup(x, y - 10.0, str(value), GOLD)
			_flash = 0.8
		"clear":
			for index in 46:
				_particles.append({"x": randf_range(20.0, 460.0), "y": randf_range(-40.0, 30.0), "vx": randf_range(-12.0, 12.0), "vy": randf_range(30.0, 80.0), "gravity": 20.0, "life": randf_range(1.6, 2.6), "span": 2.6, "color": [GOLD, _yarn(0), _yarn(1), Color("ff9ec4"), CREAM].pick_random(), "size": 2.0})
		"hurry":
			_say("动作快！静电火花要来了", "HURRY UP! STATIC IS COMING", 2.4)
		"wave":
			_say("又来了一批！", "MORE OF THEM!", 1.8)
		"continue":
			_say("续关！还剩 %d 次" % world.continues, "CONTINUE! %d LEFT" % world.continues, 2.0)
		"spark":
			_burst(x, y, 14, GOLD, 90.0, 0.5, 0.0)

# ---- drawing ----

func _sprite(key: String, x: float, y: float, flip: bool = false, tint: Color = Color.WHITE) -> void:
	var texture := art.get_texture(key)
	if texture == null:
		return
	var size := texture.get_size()
	var rect := Rect2(roundf(x - size.x * 0.5), roundf(y - size.y), size.x, size.y)
	# A negative width mirrors the texture in place.
	if flip:
		rect.size.x = -size.x
	draw_texture_rect(texture, rect, false, tint)

func _spun(key: String, x: float, y: float, angle: float, tint: Color = Color.WHITE, scale_by: Vector2 = Vector2.ONE) -> void:
	var texture := art.get_texture(key)
	if texture == null:
		return
	draw_set_transform(Vector2(roundf(x), roundf(y)), angle, scale_by)
	draw_texture(texture, -texture.get_size() * 0.5, tint)
	draw_set_transform(Vector2.ZERO)

## Digits and a few signs in the 3 x 5 pixel font, with a dark edge. `x` is the centre when `centered`.
func _number(text: String, x: float, y: float, color: Color, centered: bool = true) -> void:
	var left := roundf(x - text.length() * 2.0) if centered else roundf(x)
	for pass_index in 2:
		for index in text.length():
			var texture := art.get_texture("glyph_" + text[index])
			if texture == null:
				continue
			var at := Vector2(left + index * 4.0, roundf(y))
			if pass_index == 0:
				for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					draw_texture(texture, at + offset, INK)
			else:
				draw_texture(texture, at, color)

func _text(text: String, y: float, size: int, color: Color) -> void:
	draw_string_outline(font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 480.0, size, 4, INK)
	draw_string(font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 480.0, size, color)

func _draw() -> void:
	if world == null:
		return
	if art == null:
		art = Sprites.new()
		art.build()
	if _backdrop_stage != world.stage:
		_backdrop_stage = world.stage
		_backdrop = ImageTexture.create_from_image(Backdrop.build(world.theme, world.grid))
	# The backdrop is drawn a little larger than the stage so that a shake never shows the edge.
	draw_rect(Rect2(-12.0, -12.0, 504.0, 294.0), INK)
	draw_texture(_backdrop, Vector2.ZERO)
	_draw_ambience()
	_draw_sign()
	for item in world.pickups:
		if item.life > 2.5 or int(item.life * 10.0) % 2 == 0:
			_sprite(item.kind, item.x, item.y - 1.0 + sin(_time * 5.0 + item.x) * 1.0)
	for foe in world.foes:
		_draw_foe(foe)
	for husk in world.husks:
		_spun(husk.kind + "_0", husk.x, husk.y - 8.0, husk.spin * 9.0 * (1.0 if husk.vx >= 0.0 else -1.0), Color(1.0, 1.0, 1.0, 0.9), Vector2(1.0, -1.0))
	if world.boss != null:
		_draw_boss(world.boss)
	for hazard in world.hazards:
		_draw_hazard(hazard)
	for shot in world.shots:
		_draw_shot(shot)
	for hero in world.heroes:
		_draw_hero(hero)
	if world.spark != null:
		var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) if world.spark_stun <= 0.0 else Vector2.ZERO
		_sprite("spark_%d" % (int(_time * 12.0) % 2), world.spark.x + jitter.x, world.spark.y + 2.0 + jitter.y, false, Color(1, 1, 1, 0.5) if world.spark_stun > 0.0 else Color.WHITE)
	for particle in _particles:
		var fade := clampf(float(particle["life"]) / float(particle["span"]) * 2.0, 0.0, 1.0)
		var tint: Color = particle["color"]
		var size := float(particle["size"])
		draw_rect(Rect2(roundf(float(particle["x"])), roundf(float(particle["y"])), size, size), Color(tint.r, tint.g, tint.b, fade))
	for popup in _popups:
		_number(str(popup["text"]), float(popup["x"]), float(popup["y"]), popup["color"])
	_draw_strip()
	_draw_banner()
	if _flash > 0.0:
		draw_rect(Rect2(-12.0, -12.0, 504.0, 294.0), Color(1.0, 1.0, 1.0, minf(0.7, _flash * 0.6)))

## Slow background motion that belongs to the part of the tower: drifting lint everywhere, lantern light in the cellar, dye drips, turning cogs, twinkling stars.
func _draw_ambience() -> void:
	var far: Array = Backdrop.THEMES[world.theme]["far"]
	var accent := Color(str(far[2]))
	match world.theme:
		Levels.THEME_CELLAR:
			for post: float in [122.0, 360.0]:
				var glow := 0.1 + 0.03 * sin(_time * 7.0 + post)
				draw_circle(Vector2(post, 52.0), 30.0, Color(1.0, 0.8, 0.4, glow * 0.6))
				draw_circle(Vector2(post, 52.0), 16.0, Color(1.0, 0.85, 0.5, glow))
				draw_rect(Rect2(post - 3.0, 46.0, 6.0, 8.0), Color("ffd75a"))
				draw_rect(Rect2(post - 4.0, 44.0, 8.0, 2.0), INK)
				draw_rect(Rect2(post - 4.0, 54.0, 8.0, 2.0), INK)
		Levels.THEME_DYE:
			for index in 9:
				var fall := fposmod(_time * (40.0 + index * 3.0) + index * 61.0, 260.0)
				if fall < 150.0:
					draw_rect(Rect2(44.0 + index * 52.0, 96.0 + fall, 1.0, 3.0), Color(accent.r, accent.g, accent.b, 0.7))
			for vat: float in [70.0, 240.0, 410.0]:
				for blob in 3:
					var rise := fposmod(_time * 14.0 + blob * 9.0 + vat, 26.0)
					draw_circle(Vector2(vat - 14.0 + blob * 14.0 + sin(_time * 2.0 + blob) * 2.0, 212.0 - rise), 2.0, Color(accent.r, accent.g, accent.b, 0.5 * (1.0 - rise / 26.0)))
		Levels.THEME_CLOCK:
			for cog: Vector3 in [Vector3(240.0, 120.0, 1.0), Vector3(40.0, 220.0, -1.4)]:
				draw_set_transform(Vector2(cog.x, cog.y), _time * cog.z * 0.8)
				draw_circle(Vector2.ZERO, 11.0, Color(str(far[1])))
				for tooth in 8:
					var direction := Vector2.from_angle(TAU * tooth / 8.0)
					draw_rect(Rect2(direction * 12.0 - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(str(far[1])))
				draw_circle(Vector2.ZERO, 5.0, Color(str(far[0])))
				draw_rect(Rect2(-1.0, -9.0, 2.0, 18.0), Color(str(far[0])))
				draw_set_transform(Vector2.ZERO)
		Levels.THEME_CROWN:
			for star in 14:
				if sin(_time * (1.5 + star * 0.3) + star * 2.1) > 0.6:
					draw_rect(Rect2(fposmod(star * 97.0, 440.0) + 20.0, fposmod(star * 53.0, 150.0) + 8.0, 2.0, 2.0), CREAM)
	for mote in 22:
		var drift_x := fposmod(mote * 71.3 + sin(_time * 0.4 + mote) * 14.0 + _time * (3.0 if world.theme == Levels.THEME_CROWN else 0.0), 448.0) + 16.0
		var drift_y := fposmod(mote * 37.7 - _time * (3.0 + mote % 5), 250.0)
		draw_rect(Rect2(roundf(drift_x), roundf(drift_y), 1.0, 1.0), Color(1.0, 0.95, 0.85, 0.16 + 0.1 * sin(_time * 2.0 + mote)))

## The floor plaque under the game's title at the top centre: "F 07/14".
func _draw_sign() -> void:
	var knit: Array = Backdrop.THEMES[world.theme]["knit"]
	draw_rect(Rect2(214.0, 19.0, 52.0, 13.0), INK)
	draw_rect(Rect2(215.0, 20.0, 50.0, 11.0), Color(str(knit[2])))
	draw_rect(Rect2(216.0, 21.0, 48.0, 9.0), Color("2a1c2c"))
	_number("F", 222.0, 23.0, Color(str(knit[1])), false)
	_number("%02d/%02d" % [world.stage, Levels.count()], 246.0, 23.0, CREAM)

func _draw_foe(foe: Foe) -> void:
	var drop := float(FOE_DROP[foe.kind])
	var flip := foe.facing < 0
	var tint := Color(1.0, 0.72, 0.72) if foe.angry else Color.WHITE
	if foe.flash > 0.0:
		tint = Color(3.0, 3.0, 3.0)
	var x := foe.x
	var y := foe.y + drop
	match foe.state:
		Foe.SPAWN:
			var shown := clampf(1.0 - foe.timer / 1.1, 0.0, 1.0)
			for thread in 5:
				var angle := _time * 6.0 + thread * TAU / 5.0
				var reach := 12.0 * (1.0 - shown) + 3.0
				draw_rect(Rect2(roundf(x + cos(angle) * reach), roundf(y - 8.0 + sin(angle) * reach), 2.0, 2.0), CREAM)
			if int(_time * 20.0) % 2 == 0 or shown > 0.7:
				_sprite(foe.kind + "_0", x, y, flip, Color(1.0, 1.0, 1.0, 0.35 + 0.65 * shown))
		Foe.ROAM:
			var frame := int(foe.anim * 6.0) % 2
			match foe.kind:
				Foe.SPRING:
					frame = 0 if foe.on_ground else 1
				Foe.SNIP:
					frame = int(foe.anim * 9.0) % 2
				Foe.PIN:
					frame = int(foe.anim * (14.0 if foe.mode == 2 else 5.0)) % 2
					if foe.mode == 1:
						x += 1.0 if int(_time * 30.0) % 2 == 0 else -1.0
				Foe.INK:
					frame = 1 if foe.mode == 1 else int(foe.anim * 3.0) % 2
			_sprite("%s_%d" % [foe.kind, frame], x, y, flip, tint)
			if foe.angry and int(_time * 6.0) % 2 == 0:
				draw_rect(Rect2(roundf(x + 5.0), roundf(y - 17.0), 2.0, 2.0), Color("e0455a"))
				draw_rect(Rect2(roundf(x + 7.0), roundf(y - 19.0), 2.0, 2.0), Color("e0455a"))
		Foe.WRAP:
			if foe.unwrap < 0.5 and int(_time * 24.0) % 2 == 0:
				x += 1.0
			_sprite(foe.kind + "_0", x, y, flip, tint)
			var level := clampi(int(ceil(float(foe.wrap) / float(foe.need) * 4.0)) - 1, 0, 3)
			_sprite("wrap%d_%d" % [foe.owner, level], x, foe.y, false, Color(3.0, 3.0, 3.0) if foe.flash > 0.0 else Color.WHITE)
		Foe.BALL:
			if foe.timer < 1.6 and int(_time * 24.0) % 2 == 0:
				x += 1.0
			_sprite("ball%d_0" % foe.owner, x, foe.y, false, Color(3.0, 3.0, 3.0) if foe.flash > 0.0 else Color.WHITE)
		Foe.ROLL:
			var turn := int(foe.roll_time * 18.0) % 4
			_sprite("ball%d_%d" % [foe.owner, turn if foe.dir > 0 else 3 - turn], x, foe.y)
			for streak in 3:
				draw_rect(Rect2(roundf(x - foe.dir * (9.0 + streak * 5.0)), roundf(foe.y - 12.0 + streak * 4.0), 4.0 - streak, 1.0), Color(1.0, 1.0, 1.0, 0.5 - streak * 0.12))

func _draw_hero(hero: Hero) -> void:
	if hero.state == Hero.ABSENT or hero.state == Hero.OUT:
		return
	var prefix := "hero%d_" % hero.slot
	if hero.state == Hero.DYING:
		_spun(prefix + "hurt", hero.x, hero.y - 9.0, (1.4 - hero.timer) * 9.0)
		return
	if hero.invuln > 0.0 and int(_time * 16.0) % 2 == 0:
		return
	var frame := "idle"
	if hero.shoot_anim > 0.0:
		frame = "shoot" if hero.on_ground else "shoot_air"
	elif not hero.on_ground:
		frame = "jump" if hero.vy < 0.0 else "fall"
	elif hero.vx != 0.0:
		frame = "run%d" % (int(hero.anim * 11.0) % 4)
	elif world.phase == World.CLEAR:
		frame = "jump" if int(_time * 4.0) % 2 == 0 else "idle"
	elif fposmod(_time + hero.slot * 1.3, 3.4) < 0.13:
		frame = "blink"
	var bob := -1.0 if frame == "run1" or frame == "run3" else 0.0
	_sprite(prefix + frame, hero.x, hero.y + bob, hero.facing < 0)

func _draw_shot(shot: Dictionary) -> void:
	var owner := world.heroes[int(shot["owner"])]
	var x := float(shot["x"])
	var y := float(shot["y"])
	if owner.state == Hero.ALIVE:
		var hand := Vector2(owner.x + owner.facing * 8.0, owner.y - 5.0)
		var sag := Vector2((hand.x + x) * 0.5, maxf(hand.y, y) + 3.0)
		draw_polyline(PackedVector2Array([hand, sag, Vector2(x, y)]), _yarn(owner.slot), 1.0)
	_sprite("shot%d_%d" % [int(shot["owner"]), int(float(shot["age"]) * 22.0) % 2], x, y + 4.0, int(shot["dir"]) < 0)

func _draw_hazard(hazard: Item) -> void:
	match hazard.kind:
		Item.INK:
			_sprite("ink", hazard.x, hazard.y + 1.0 + sin(hazard.spin * 20.0), hazard.vx < 0.0)
		Item.PIN:
			_spun("pin", hazard.x, hazard.y - 3.0, atan2(hazard.vy, hazard.vx) + PI * 0.25)
		Item.WAVE:
			_sprite("wave", hazard.x, hazard.y + (1.0 if int(hazard.spin * 16.0) % 2 == 0 else 0.0), hazard.vx > 0.0)
		Item.EGG:
			_spun("egg", hazard.x, hazard.y - 4.0, hazard.spin * 5.0)

func _draw_boss(boss: Boss) -> void:
	var tint := Color(3.0, 3.0, 3.0) if boss.flash > 0.0 else Color.WHITE
	var x := boss.x
	var y := boss.y
	if boss.state == "dying":
		if int(_time * 18.0) % 2 == 0:
			tint = Color(3.0, 1.2, 1.2)
		x += randf_range(-2.0, 2.0)
		y += (2.8 - boss.timer) * 6.0
	if boss.kind == Boss.DUCHESS:
		var resting := boss.state == "rest" or boss.state == "hurt" or boss.state == "dying"
		var beat := absf(sin(boss.clock * (3.0 if resting else 13.0)))
		var spread := (0.35 + 0.2 * beat) if resting else (0.55 + 0.45 * beat)
		var wing := art.get_texture("duchess_wing")
		var width := roundf(36.0 * spread)
		if boss.state == "aim" and int(_time * 20.0) % 2 == 0:
			tint = Color(2.0, 1.4, 1.4)
		draw_texture_rect(wing, Rect2(roundf(x) - 7.0 - width, roundf(y) - 56.0, width, 50.0), false, tint)
		draw_texture_rect(wing, Rect2(roundf(x) + 7.0, roundf(y) - 56.0, -width, 50.0), false, tint)
		_sprite("duchess_body", x, y + 2.0, false, tint)
		return
	var squash := 0.86 if boss.state == "crouch" else 1.0
	var body := art.get_texture("regent_body")
	var height := roundf(36.0 * squash)
	if (boss.state == "crouch" or boss.state == "raise") and int(_time * 20.0) % 2 == 0:
		tint = Color(2.0, 1.4, 1.4)
	var blade := art.get_texture("regent_blade")
	var open := 0.35 + 0.3 * absf(sin(boss.clock * 5.0))
	if boss.state == "raise":
		open = 1.25
	elif boss.state == "leap":
		open = 0.9
	elif boss.state == "recover":
		open = 0.12
	for side: float in [-1.0, 1.0]:
		draw_set_transform_matrix(Transform2D(0.0, Vector2(roundf(x + boss.facing * 9.0), roundf(y - 13.0 * squash))) * Transform2D(0.0, Vector2(boss.facing, 1.0), 0.0, Vector2.ZERO) * Transform2D(side * open, Vector2.ZERO))
		draw_texture(blade, Vector2(-3.0, -4.5), tint)
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(body, Rect2(roundf(x) - 17.0, roundf(y) - height, 34.0, height), false, tint)

## The bottom strip: continues left, and each knitter's power-ups.
func _draw_strip() -> void:
	draw_rect(Rect2(19.0, 258.0, 27.0, 10.0), INK)
	draw_texture_rect(art.get_texture("ball0_0"), Rect2(20.0, 259.0, 8.0, 8.0), false)
	_number("x%d" % world.continues, 31.0, 261.0, CREAM, false)
	for hero in world.heroes:
		if hero.state == Hero.ABSENT:
			continue
		var at := 54.0 if hero.slot == 0 else 330.0
		for power: Array in [["long", hero.long_needle], ["rapid", hero.rapid], ["thick", hero.thick], ["swift", hero.swift]]:
			if power[1]:
				draw_texture(art.get_texture(str(power[0])), Vector2(at, 257.0))
				at += 13.0

func _draw_banner() -> void:
	var zh := locale == "zh"
	if world.phase == World.OVER:
		_text("毛线用完了……" if zh else "OUT OF YARN", 132.0, 20, Color("ff9ec4"))
		return
	if world.phase == World.CLEAR:
		if world.stage >= Levels.count():
			_text("织塔登顶！" if zh else "THE TOWER IS YOURS!", 118.0, 22, GOLD)
			_text(("奖励 +%d" if zh else "BONUS +%d") % world.last_bonus, 142.0, 12, CREAM)
		else:
			_text("本层清空！" if zh else "FLOOR CLEAR!", 118.0, 20, GOLD)
			_text(("奖励 +%d" if zh else "BONUS +%d") % world.last_bonus, 140.0, 12, CREAM)
		return
	if world.banner > 0.0:
		var name: Dictionary = Levels.THEME_NAMES[world.theme]
		_text(("第 %d 层" if zh else "FLOOR %d") % world.stage, 116.0, 20, GOLD)
		if world.is_boss_stage():
			_text(str(BOSS_NAMES[int(Levels.STAGES[world.stage - 1]["boss"])]["zh" if zh else "en"]), 138.0, 14, Color("ff9ec4"))
		else:
			_text(str(name["zh" if zh else "en"]), 136.0, 12, CREAM)
		return
	if _notice_time > 0.0 and int(_notice_time * 6.0) % 3 != 0:
		_text(_notice, 104.0, 14, Color("ff9ec4"))
