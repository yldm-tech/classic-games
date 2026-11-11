extends RefCounted

## Draws a frame of the game from its state. Nothing here changes the simulation: the view keeps only its own clock, the baked tile layer and the backdrop layers of the stage on screen, and the font.

const World := preload("res://games/tide_runners/world.gd")
const Levels := preload("res://games/tide_runners/levels.gd")
const Heroes := preload("res://games/tide_runners/heroes.gd")
const Bosses := preload("res://games/tide_runners/bosses.gd")
const Scenery := preload("res://games/tide_runners/scenery.gd")
const Gfx := preload("res://games/tide_runners/gfx.gd")

const VIEW := Vector2(480.0, 270.0)
const TEXT := {
	"stage": {"zh": "第 %d 关", "en": "STAGE %d"},
	"warning": {"zh": "警报", "en": "WARNING"},
	"ambush": {"zh": "伏击！守住这里", "en": "AMBUSH! HOLD HERE"},
	"continue": {"zh": "续关", "en": "CONTINUE"},
	"clear": {"zh": "关卡清除", "en": "STAGE CLEAR"},
	"final": {"zh": "潮水退去，城市安静了", "en": "THE TIDE TURNS. THE CITY IS QUIET."},
	"over": {"zh": "被潮水吞没", "en": "LOST TO THE TIDE"},
	"1up": {"zh": "生命 +1", "en": "EXTRA LIFE"},
	"w0": {"zh": "铆钉枪", "en": "RIVET GUN"},
	"w1": {"zh": "三叉弹", "en": "TRI-FORK"},
	"w2": {"zh": "弧光线圈", "en": "ARC COIL"},
	"w3": {"zh": "吸附雷", "en": "LIMPET"},
	"w4": {"zh": "水压矛", "en": "PRESSURE LANCE"},
	"w5": {"zh": "回旋碟", "en": "SKIPPER DISC"},
	"w6": {"zh": "气泡护盾", "en": "BUBBLE SHIELD"},
}
## Sky bands of each theme, top to bottom: [palette key, height].
const SKIES := [
	[["1", 58], ["2", 50], ["3", 46], ["4", 30], ["f", 10], ["e", 8], ["3", 68]],
	[["0", 270]],
	[["0", 80], ["1", 90], ["2", 36], ["1", 64]],
]
const SHOT_SPRITES := {"rivet": "b_rivet", "fork": "b_fork", "arc": "b_arc", "limpet": "b_limpet", "lance": "b_lance", "disc": "b_disc", "orb": "e_orb", "bomb": "e_bomb", "spike": "e_spike"}
const GUN_GRIPS := {"gun_f": Vector2(1, 2), "gun_d": Vector2(1, 7), "gun_d_v": Vector2(1, 1), "gun_u": Vector2(2, 10), "gun_u_v": Vector2(2, 1)}

var gfx: Gfx
var font: SystemFont
var time := 0.0
var _baked_stage := -1
var _level: ImageTexture
var _layers: Array = []
var _origin := Vector2.ZERO
var _lightning := 0.0
var _next_lightning := 3.0

func _init(sprites: Gfx) -> void:
	gfx = sprites
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"])
	font.allow_system_fallback = true
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE

func frame(g: Variant, delta: float) -> void:
	time += delta
	if int(g.stage_index) != _baked_stage:
		_baked_stage = g.stage_index
		var world: World = g.world
		_level = ImageTexture.create_from_image(Scenery.bake_level(gfx, world))
		_layers.clear()
		for layer: Dictionary in Scenery.layers(gfx, int(world.def["theme"])):
			_layers.append({"texture": ImageTexture.create_from_image(layer["image"]), "factor": layer["factor"], "y": layer["y"], "vertical": layer["vertical"]})
	_lightning = maxf(0.0, _lightning - delta)
	_next_lightning -= delta
	if _next_lightning <= 0.0:
		_next_lightning = randf_range(3.0, 8.0)
		_lightning = 0.22

func shake_offset(power: float) -> Vector2:
	if power <= 0.2:
		return Vector2.ZERO
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * minf(power, 6.0) * 0.6

func draw(g: Variant) -> void:
	var world: World = g.world
	var theme := int(world.def["theme"])
	_origin = (g._camera as Camera2D).position
	_backdrop(g, theme)
	g.draw_texture_rect_region(_level, Rect2(_origin, VIEW), Rect2(_origin, VIEW))
	_boss(g)
	for item: Dictionary in g.items:
		if float(item["t"]) < 3.0 and int(time * 12.0) % 2 == 0:
			continue
		_bottom(g, "can%d" % int(item["k"]), float(item["x"]), float(item["y"]) - (0.0 if item["ground"] else 0.0) + sin(time * 5.0 + float(item["x"])) * 1.2 - 1.0, false, false)
	_foes(g)
	for h: Dictionary in g.heroes:
		if h["active"]:
			_hero(g, h)
	_shots(g)
	_fx(g)
	_water(g, theme)
	if theme == 2:
		_rain(g)
	_overlay(g)

# ---- helpers ----

func _c(key: String) -> Color:
	return Gfx.col(key)

## Draw a sprite with its bottom centre at (x, y).
func _bottom(g: Variant, key: String, x: float, y: float, flip: bool, white: bool) -> void:
	var size: Vector2 = gfx.dims[key]
	var area := Rect2(roundf(x - size.x * 0.5), roundf(y - size.y), size.x, size.y)
	if flip:
		area = Rect2(area.position.x + size.x, area.position.y, -size.x, size.y)
	g.draw_texture_rect(gfx.white(key) if white else gfx.tex[key], area, false)

func _centre(g: Variant, key: String, x: float, y: float, white: bool = false) -> void:
	var size: Vector2 = gfx.dims[key]
	g.draw_texture(gfx.white(key) if white else gfx.tex[key], Vector2(roundf(x - size.x * 0.5), roundf(y - size.y * 0.5)))

func _turned(g: Variant, key: String, x: float, y: float, angle: float, scale: Vector2 = Vector2.ONE, white: bool = false) -> void:
	var size: Vector2 = gfx.dims[key]
	g.draw_set_transform(Vector2(roundf(x), roundf(y)), angle, scale)
	g.draw_texture(gfx.white(key) if white else gfx.tex[key], -size * 0.5)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _text(g: Variant, text: String, centre_x: float, baseline: float, size: int, colour: Color, shadow: Color = Color("0b1020")) -> void:
	var at := Vector2(_origin.x + centre_x - 240.0, _origin.y + baseline)
	for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1)]:
		g.draw_string(font, at + offset, text, HORIZONTAL_ALIGNMENT_CENTER, 480.0, size, shadow)
	g.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 480.0, size, colour)

func _t(g: Variant, key: String) -> String:
	return str(TEXT[key]["zh" if str(g.locale) == "zh" else "en"])

# ---- backdrop ----

func _backdrop(g: Variant, theme: int) -> void:
	var y := _origin.y
	var bands: Array = SKIES[theme]
	for index in bands.size():
		var band: Array = bands[index]
		g.draw_rect(Rect2(_origin.x - 8.0, y - (8.0 if index == 0 else 0.0), 496.0, float(band[1]) + 8.0), _c(band[0]))
		# Two thin lines of the next colour soften each step of the sky.
		if index + 1 < bands.size():
			var next_colour := _c(bands[index + 1][0])
			g.draw_rect(Rect2(_origin.x - 8.0, y + float(band[1]) - 5.0, 496.0, 1.0), next_colour)
			g.draw_rect(Rect2(_origin.x - 8.0, y + float(band[1]) - 2.0, 496.0, 1.0), next_colour)
		y += float(band[1])
	if theme == 0:
		# The low sun and its road on the water.
		g.draw_circle(_origin + Vector2(338.0, 196.0), 24.0, _c("f"))
		g.draw_circle(_origin + Vector2(338.0, 196.0), 19.0, _c("5"))
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 202.0, 496.0, 70.0), _c("3"))
		for streak in 7:
			var width := 44.0 - streak * 5.0 + sin(time * 2.0 + streak) * 4.0
			g.draw_rect(Rect2(_origin.x + 338.0 - width * 0.5, _origin.y + 205.0 + streak * 5.0, width, 2.0), _c("f" if streak < 3 else "4"))
	elif theme == 2 and _lightning > 0.0:
		g.draw_rect(Rect2(_origin - Vector2(8.0, 8.0), VIEW + Vector2(16.0, 16.0)), Color(0.75, 0.85, 1.0, 0.55 * _lightning / 0.22))
	for layer: Dictionary in _layers:
		var texture: ImageTexture = layer["texture"]
		var size := texture.get_size()
		if layer["vertical"]:
			var shift := fposmod(_origin.y * float(layer["factor"]), size.y)
			for copy in 3:
				g.draw_texture(texture, Vector2(_origin.x, _origin.y - shift + (copy - 1) * size.y))
		else:
			var shift := fposmod(_origin.x * float(layer["factor"]), size.x)
			for copy in 2:
				g.draw_texture(texture, Vector2(_origin.x - shift + copy * size.x, _origin.y + float(layer["y"])))
	if theme == 2:
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 232.0, 496.0, 40.0), _c("1"))

func _water(g: Variant, theme: int) -> void:
	var surface: float = g.water_line()
	if surface > _origin.y + VIEW.y + 4.0:
		return
	var deep := Color(_c("2"), 0.74) if theme != 2 else Color(_c("1"), 0.8)
	g.draw_rect(Rect2(_origin.x - 8.0, surface, 496.0, _origin.y + VIEW.y + 10.0 - surface), deep)
	# Foam on the surface and two rows of highlights that drift at different speeds.
	var start := floorf(_origin.x / 12.0) * 12.0 - 12.0
	var x := start
	while x < _origin.x + 492.0:
		var lift := sin(time * 2.4 + x * 0.07)
		g.draw_rect(Rect2(x, surface + roundf(lift), 9.0, 1.0), _c("5"))
		g.draw_rect(Rect2(x + 4.0, surface + 1.0 + roundf(lift), 8.0, 1.0), _c("4"))
		x += 12.0
	for row in 3:
		var drift := fposmod(time * (9.0 + row * 7.0), 40.0)
		x = floorf(_origin.x / 40.0) * 40.0 - 40.0 + drift + row * 13.0
		while x < _origin.x + 492.0:
			g.draw_rect(Rect2(x, surface + 6.0 + row * 6.0, 10.0 - row * 2.0, 1.0), Color(_c("4" if theme != 2 else "3"), 0.7))
			x += 40.0

func _rain(g: Variant) -> void:
	var colour := Color(_c("4"), 0.45)
	for index in 46:
		var seed_x := float(Scenery.noise(index, 7) % 520)
		var speed := 260.0 + float(Scenery.noise(index, 9) % 120)
		var fall := fposmod(time * speed + float(Scenery.noise(index, 3) % 300), 300.0)
		var x := _origin.x + fposmod(seed_x - fall * 0.35, 500.0) - 10.0
		var y := _origin.y + fall - 20.0
		g.draw_line(Vector2(x, y), Vector2(x - 3.0, y + 8.0), colour, 1.0)

# ---- actors ----

func _hero(g: Variant, h: Dictionary) -> void:
	var prefix := "q" if int(h["slot"]) == 1 else ""
	var x: float = h["x"]
	var y: float = h["y"]
	var face: int = h["face"]
	var flip := face < 0
	if not h["alive"]:
		if h["out"] or float(h["dead_t"]) <= 0.0:
			return
		_turned(g, prefix + "h_hurt", x, y - 8.0, time * 11.0 * face)
		return
	if float(h["inv"]) > 0.0 and int(time * 16.0) % 2 == 0:
		return
	if h["prone"]:
		_bottom(g, prefix + "h_prone", x + face * 3.0, y, flip, false)
	else:
		var legs := "h_jump"
		var bob := 0.0
		if h["ground"]:
			if h["moving"]:
				var step := int(float(h["anim"]) * 11.0) % 4
				legs = ["h_run0", "h_run1", "h_run2", "h_run1"][step]
				bob = 1.0 if step % 2 == 1 else 0.0
			else:
				legs = "h_idle"
				bob = 1.0 if fmod(time, 1.2) > 0.6 else 0.0
		_bottom(g, prefix + legs, x, y, flip, false)
		_bottom(g, prefix + "h_up", x, y - 7.0 + bob, flip, false)
		var aim: Vector2i = h["aim"]
		var gun := "gun_f"
		if aim.y != 0:
			gun = ("gun_u" if aim.x == 0 else "gun_d") + ("_v" if aim.y > 0 else "")
		var grip: Vector2 = GUN_GRIPS[gun]
		var size: Vector2 = gfx.dims[gun]
		var shoulder := Vector2(x + face * 1.0, y - 11.0 + bob)
		var area := Rect2(roundf(shoulder.x - grip.x), roundf(shoulder.y - grip.y), size.x, size.y)
		if flip:
			area = Rect2(roundf(shoulder.x + grip.x), area.position.y, -size.x, size.y)
		g.draw_texture_rect(gfx.tex[prefix + gun], area, false)
	if float(h["fire_t"]) > 0.0:
		var muzzle := Heroes.muzzle(h)
		_centre(g, "spark", muzzle.x, muzzle.y)
	if h["shield"]:
		_centre(g, "bubble", x, y - 11.0)
	if int(g.player_count()) > 1:
		# A small marker over each diver's head tells the two apart at a glance.
		var tint := _c("e") if int(h["slot"]) == 1 else _c("9")
		var head := y - (12.0 if h["prone"] else 27.0)
		g.draw_rect(Rect2(roundf(x) - 2.0, head, 5.0, 1.0), _c("0"))
		g.draw_rect(Rect2(roundf(x) - 1.0, head - 3.0, 3.0, 3.0), tint)
		g.draw_rect(Rect2(roundf(x), head, 1.0, 1.0), tint)

func _foes(g: Variant) -> void:
	for foe: Dictionary in g.foes:
		if foe["dead"]:
			continue
		var x: float = foe["x"]
		var y: float = foe["y"]
		var white := float(foe["flash"]) > 0.0
		var flip := int(foe["face"]) < 0
		match str(foe["k"]):
			"scut":
				_bottom(g, "scut%d" % (int(time * 12.0 + float(foe["id"])) % 2), x, y, false, white)
			"troop":
				_bottom(g, "troop%d" % (int(float(foe["b"]) * 7.0) % 2), x + (2.0 if not flip else -2.0), y, flip, white)
				if float(foe["a"]) > 0.2:
					_centre(g, "spark", x + int(foe["face"]) * 10.0, y - 11.0)
			"turret":
				_turned(g, "turret_barrel", x + cos(float(foe["b"])) * 7.0, y - 9.0 + sin(float(foe["b"])) * 7.0, float(foe["b"]), Vector2.ONE, white)
				_bottom(g, "turret", x, y, false, white)
			"drone":
				_bottom(g, "drone%d" % (int(time * 20.0) % 2), x, y, false, white)
			"toad":
				_bottom(g, "toad1" if float(foe["a"]) > 0.0 else "toad0", x, y, flip, white)
			"pike":
				if int(foe["st"]) == 2:
					var heading := Vector2(float(foe["vx"]), float(foe["vy"])).angle()
					_turned(g, "pike0", x, y - 4.0, heading, Vector2(1.0, -1.0 if float(foe["vx"]) < 0.0 else 1.0), white)
				elif int(foe["st"]) == 1:
					g.draw_rect(Rect2(x - 7.0 - fmod(time * 20.0, 4.0), y - 1.0, 14.0 + fmod(time * 40.0, 8.0), 1.0), _c("5"))
			"cling":
				_bottom(g, "cling%d" % (int(time * 8.0) % 2), x, y, false, white)
			"debris":
				_turned(g, "debris", x, y - 3.0, time * 5.0 + float(foe["id"]), Vector2.ONE, white)
			"carrier":
				_bottom(g, "can%d" % int(foe["extra"]), x, y + 11.0, false, false)
				_bottom(g, "carrier%d" % (int(time * 20.0) % 2), x, y, false, white)
			"crate":
				_bottom(g, "crate", x, y, false, white)

func _shots(g: Variant) -> void:
	for shot: Dictionary in g.shots:
		var key: String = SHOT_SPRITES[shot["k"]]
		if shot["k"] == "lance":
			_turned(g, key, float(shot["x"]), float(shot["y"]), Vector2(float(shot["vx"]), float(shot["vy"])).angle())
		elif shot["k"] == "disc":
			_turned(g, key, float(shot["x"]), float(shot["y"]), float(shot["t"]) * 14.0)
		else:
			_centre(g, key, float(shot["x"]), float(shot["y"]))
	for shot: Dictionary in g.foe_shots:
		var x: float = shot["x"]
		var y: float = shot["y"]
		if shot["k"] == "orb":
			g.draw_circle(Vector2(roundf(x), roundf(y)), 4.0 + sin(time * 22.0), Color(_c("m"), 0.35))
		_centre(g, str(SHOT_SPRITES[shot["k"]]), x, y)

func _fx(g: Variant) -> void:
	for blast: Dictionary in g.blasts:
		var along := float(blast["t"]) / float(blast["life"])
		var at := Vector2(roundf(float(blast["x"])), roundf(float(blast["y"])))
		var radius := float(blast["r"]) * (0.5 + along * 0.7)
		if along < 0.25:
			g.draw_circle(at, radius, _c("5"))
		elif along < 0.6:
			g.draw_circle(at, radius, _c("e"))
			g.draw_circle(at, radius * 0.6, _c("f"))
		else:
			g.draw_circle(at, radius, Color(_c("c"), 0.8))
			g.draw_circle(at, radius * (0.4 + along * 0.6), Color(_c("a"), 0.9))
			g.draw_circle(at + Vector2(-radius * 0.2, -radius * 0.2), radius * 0.45 * (1.4 - along), _c("d"))
	for spark: Dictionary in g.sparks:
		var size := 2.0 if float(spark["t"]) > 0.2 else 1.0
		g.draw_rect(Rect2(roundf(float(spark["x"])), roundf(float(spark["y"])), size, size), _c(str(spark["c"])))

# ---- bosses ----

func _boss(g: Variant) -> void:
	var boss: Dictionary = g.boss
	if boss.is_empty():
		return
	var wreck: bool = boss["dead"]
	var tint := Color(0.35, 0.35, 0.4) if wreck else Color.WHITE
	var jolt := Vector2.ZERO
	if float(boss["dying"]) >= 0.0 and not wreck:
		jolt = Vector2(roundf(sin(time * 70.0) * 2.0), roundf(cos(time * 53.0)))
	match int(boss["kind"]):
		0:
			g.draw_texture(gfx.tex["maw_body"], Vector2(float(boss["x"]), float(boss["y"])) + jolt, tint)
			var core := Bosses.part(boss, "core")
			if core["alive"]:
				_centre(g, "maw_core" if core["vuln"] and boss["active"] else "maw_shut", float(core["x"]), float(core["y"]), float(core["flash"]) > 0.0)
			var cannon := Bosses.part(boss, "cannon")
			if cannon["alive"]:
				_centre(g, "maw_cannon", float(cannon["x"]) - 4.0, float(cannon["y"]) + roundf(sin(time * 2.0) * 2.0), float(cannon["flash"]) > 0.0)
			var hatch := Bosses.part(boss, "hatch")
			if hatch["alive"]:
				_centre(g, "maw_hatch", float(hatch["x"]), float(hatch["y"]), float(hatch["flash"]) > 0.0)
		1:
			g.draw_texture(gfx.tex["hydra_tank"], Vector2(float(boss["x"]) - 110.0, float(boss["y"])) + jolt, tint)
			var heart := Bosses.part(boss, "core")
			if heart["alive"]:
				_centre(g, "hydra_heart" if heart["vuln"] else "hydra_plate", float(heart["x"]), float(heart["y"]), float(heart["flash"]) > 0.0)
			for entry: Dictionary in boss["parts"]:
				if entry["n"] != "head" or not entry["alive"]:
					continue
				var base := Vector2(166.0 + 74.0 * int(entry["i"]), 80.0)
				var head := Vector2(float(entry["x"]), float(entry["y"]))
				if int(entry["m"]) == 1:
					head += Vector2(roundf(sin(time * 60.0) * 1.5), 0.0)
				var bend := Vector2(base.x, (base.y + head.y) * 0.5 + 16.0)
				for link in 8:
					var along := float(link) / 8.0
					var at := base.lerp(bend, along).lerp(bend.lerp(head, along), along)
					_centre(g, "hydra_link", at.x, at.y)
				_centre(g, "hydra_jaw" if int(entry["m"]) in [1, 2, 3] else "hydra_head", head.x, head.y, float(entry["flash"]) > 0.0)
		2:
			var world: World = g.world
			var left := float(world.def["boss_col"]) * World.TILE
			g.draw_rect(Rect2(left, 54.0, 480.0, 5.0), _c("h"))
			g.draw_rect(Rect2(left, 54.0, 480.0, 1.0), _c("j"))
			g.draw_rect(Rect2(left, 59.0, 480.0, 1.0), _c("0"))
			var x: float = boss["x"]
			var claw := Bosses.part(boss, "claw")
			if claw["alive"]:
				g.draw_rect(Rect2(roundf(x) - 1.0, 100.0, 3.0, float(claw["y"]) - 112.0), _c("i"))
				g.draw_rect(Rect2(roundf(x) - 1.0, 100.0, 1.0, float(claw["y"]) - 112.0), _c("0"))
				var warn := int(boss["st"]) == 2 and int(time * 14.0) % 2 == 0
				_centre(g, "gantry_claw", x, float(claw["y"]), float(claw["flash"]) > 0.0 or warn)
			g.draw_texture(gfx.tex["gantry_body"], Vector2(roundf(x) - 66.0, float(boss["y"])) + jolt, tint)
			for index in 2:
				var turret := Bosses.part(boss, "turret", index)
				if turret["alive"]:
					_centre(g, "gantry_turret", float(turret["x"]), float(turret["y"]), float(turret["flash"]) > 0.0)
			var eye := Bosses.part(boss, "core")
			if eye["alive"]:
				_centre(g, "gantry_eye" if eye["vuln"] and boss["active"] else "gantry_lid", float(eye["x"]), float(eye["y"]), float(eye["flash"]) > 0.0)

# ---- text and screen effects ----

func _overlay(g: Variant) -> void:
	var zh := str(g.locale) == "zh"
	if float(g.flash) > 0.0:
		g.draw_rect(Rect2(_origin - Vector2(8.0, 8.0), VIEW + Vector2(16.0, 16.0)), Color(1.0, 1.0, 1.0, minf(0.8, float(g.flash) * 2.0)))
	for label: Dictionary in g.labels:
		var at := Vector2(float(label["x"]) - _origin.x, float(label["y"]) - _origin.y)
		_text(g, _t(g, str(label["key"])), clampf(at.x, 40.0, 440.0), at.y, 10, _c("f"))
	_weapon_tags(g)
	if float(g.go_t) > 0.0 and int(time * 5.0) % 2 == 0:
		_centre(g, "arrow", _origin.x + 440.0, _origin.y + 128.0)
	if float(g.intro_t) > 0.0:
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 100.0, 496.0, 52.0), Color(_c("0"), 0.72))
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 100.0, 496.0, 1.0), _c("8"))
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 151.0, 496.0, 1.0), _c("8"))
		_text(g, _t(g, "stage") % (int(g.stage_index) + 1), 240.0, 119.0, 10, _c("9"))
		_text(g, str(Levels.NAMES[int(g.stage_index)]["zh" if zh else "en"]), 240.0, 142.0, 18, _c("5"))
	elif bool(g.boss_started) and float(g.warn_t) > 0.0:
		var pulse := 0.5 + 0.5 * sin(time * 12.0)
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 100.0, 496.0, 52.0), Color(_c("a"), 0.55 + 0.25 * pulse))
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 100.0, 496.0, 2.0), _c("d"))
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 150.0, 496.0, 2.0), _c("d"))
		_text(g, _t(g, "warning"), 240.0, 119.0, 10, _c("e"))
		_text(g, str(Levels.BOSS_NAMES[int(g.stage_index)]["zh" if zh else "en"]), 240.0, 142.0, 18, _c("f"))
	elif int(g.mode) == 1:
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 100.0, 496.0, 52.0), Color(_c("0"), 0.72))
		var last := int(g.stage_index) + 1 >= Levels.STAGE_COUNT
		_text(g, _t(g, "clear"), 240.0, 122.0 if last else 132.0, 18, _c("f"))
		if last:
			_text(g, _t(g, "final"), 240.0, 143.0, 10, _c("9"))
	elif int(g.mode) == 2:
		g.draw_rect(Rect2(_origin.x - 8.0, _origin.y + 100.0, 496.0, 52.0), Color(_c("0"), 0.72))
		_text(g, _t(g, "continue" if int(g.continues) > 0 else "over"), 240.0, 133.0, 18, _c("f"))
	elif float(g.banner_t) > 0.0 and str(g.banner) != "":
		_text(g, _t(g, str(g.banner)), 240.0, 104.0, 14, _c("f") if int(time * 6.0) % 2 == 0 else _c("d"))

## Which weapon each diver holds, along the bottom edge and clear of the pause chip.
func _weapon_tags(g: Variant) -> void:
	var column := 0
	for h: Dictionary in g.heroes:
		if not h["active"] or h["out"]:
			continue
		var left := _origin.x + 6.0 + column * 118.0
		var top := _origin.y + 253.0
		column += 1
		g.draw_rect(Rect2(left, top, 112.0, 14.0), Color(_c("0"), 0.7))
		g.draw_rect(Rect2(left, top, 2.0, 14.0), _c("e") if int(h["slot"]) == 1 else _c("8"))
		var weapon: int = h["weapon"]
		if weapon == 0:
			_centre(g, "b_rivet", left + 10.0, top + 7.0)
		else:
			g.draw_texture_rect_region(gfx.tex["ico%d" % weapon], Rect2(left + 7.0, top + 4.0, 6.0, 6.0), Rect2(0, 0, 6, 6))
		g.draw_string(font, Vector2(left + 18.0, top + 11.0), _t(g, "w%d" % weapon), HORIZONTAL_ALIGNMENT_LEFT, 92.0, 10, _c("5"))
