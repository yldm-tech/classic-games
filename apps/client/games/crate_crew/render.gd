extends Node2D

## Draws the world of Crate Crew and owns everything that is only for the eye: which painted frame a squirrel shows, where the thing it carries rests on its paws, squash and stretch, shadows, particles, screen shake, flashes, floating points and the banners. It reads the simulation and never changes it; its own randomness comes from a private generator so the game's seeded sequence is untouched. All art is loaded from art/ once; positions are stage pixels and every sprite stands on the unchanged collision boxes of world.gd. The squirrels are painted larger than their 10 x 14 box: feet on its bottom edge, body on its middle, head, ears and tail above and behind it.

const World := preload("res://games/crate_crew/world.gd")
const Foes := preload("res://games/crate_crew/foes.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Bosses := preload("res://games/crate_crew/bosses.gd")
const Texts := preload("res://games/crate_crew/texts.gd")
const Rng := preload("res://games/shared/game_rng.gd")

const ART := "res://games/crate_crew/art/"
const VIEW := Vector2(384, 216)
const TILE := 16.0
const MAX_PARTICLES := 220
const MAX_PENDING := 96
const HERO_COLORS := [Color("5fd4c4"), Color("f5a340")]
## Every frame a squirrel atlas holds.
const HERO_FRAMES := ["idle_0", "idle_1", "run_0", "run_1", "run_2", "run_3", "run_4", "run_5", "jump", "fall", "land", "lift", "carry", "carry_run_0", "carry_run_1", "carry_run_2", "carry_run_3", "throw_0", "throw_1", "throw_up", "duck", "hurt", "out", "cheer", "carried"]
const RUN_FPS := 15.0
const CARRY_RUN_FPS := 11.0
## How long a crate takes from the floor to the paws, and how long something let go takes to settle from the paws onto the path the simulation gives it.
const LIFT_SPAN := 0.2
const DRIFT_SPAN := 0.12
## How long the throwing pose is held, and how much of it is the wind-up.
const THROW_SPAN := 0.24
const WIND_UP := 0.05
## A carried thing sinks this far into the paws, so the fingers lie over its bottom edge.
const HOLD_SINK := 0.7
## Where a carried thing rests when a frame names no spot of its own, from the feet.
const HOLD_DEFAULT := Vector2(0.0, -22.0)
## The pictures of the two pick-ups the simulation still calls by their old names.
const PICKUP_FRAMES := {"battery": "acorn", "core": "golden_acorn"}
## The white silhouette laid over a sprite that was just hit.
const FLASH_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * 0.85);\n}\n"
## The painted ground texture covers this many cells each way, so no single cell repeats beside itself.
const FILL_CELLS := 4
const BACK_SIZE := Vector2(480, 270)
const MOTES := 30

## Per stage: the lit top of the ground, its highlight, the dark outline, the colour laid over the far wall so play stands out, and the colour of the drifting specks.
const LOOKS := [
	{"cap": Color("d9a565"), "lip": Color("f7dcab"), "edge": Color("3a2418"), "veil": Color(0.07, 0.06, 0.12, 0.16), "mote": Color("ffe2a8"), "rise": -3.0},
	{"cap": Color("7cc7bf"), "lip": Color("c9f0ea"), "edge": Color("10242c"), "veil": Color(0.03, 0.08, 0.1, 0.16), "mote": Color("d8f4f0"), "rise": -9.0},
	{"cap": Color("d98250"), "lip": Color("ffc08a"), "edge": Color("2a1216"), "veil": Color(0.1, 0.03, 0.04, 0.16), "mote": Color("ffa24a"), "rise": -16.0},
	{"cap": Color("9c98e0"), "lip": Color("d6d4ff"), "edge": Color("161432"), "veil": Color(0.05, 0.04, 0.13, 0.16), "mote": Color("9fe8dc"), "rise": -4.0},
]

var world: World
var locale := "zh"
var players := 1

var heroes: Array[GameSprites] = []
var foes: GameSprites
var bosses: GameSprites
var props: GameSprites
var fills: Array[GameSprites] = []
var backs: Array[GameSprites] = []
var text: GameText

var _random: GameRng = Rng.new(20261)
var _pending: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _looks: Array[Dictionary] = []
## Per squirrel: frame name -> where the bottom middle of a carried thing rests, in stage pixels from the frame's pivot, for a squirrel facing right. Read from the "hold" entries of the frame tables.
var _holds: Array[Dictionary] = []
## Things just let go: [{ "thing", "offset", "life" }]. They are drawn `offset` away from where the simulation has them, shrinking to nothing, so a crate leaves from the paws.
var _drifts: Array[Dictionary] = []
## Where crates at rest and squirrels stood on the last frame: [[thing, position]], so a lift can start from where the thing was.
var _seen: Array = []
## Sprites to repeat as white silhouettes on the flash layer this frame: [[sheet, frame, position, flipped, scale, angle, pivot shift]].
var _flashes: Array = []
var _flash_layer: Node2D
var _motes: Array[Dictionary] = []
var _plate := StyleBoxFlat.new()
var _shake := 0.0
var _flash := 0.0
var _clock := 0.0
var _offset := Vector2.ZERO
var _camera := Vector2.ZERO
var _band_key := ""
var _band_age := 0.0

func setup(simulation: World, language: String) -> void:
	world = simulation
	locale = language
	if text == null:
		_load_art()
	_pending.clear()
	_particles.clear()
	_popups.clear()
	_looks.clear()
	for slot in 2:
		_looks.append({"squash": 0.0, "stretch": 0.0, "pose": "", "pose_time": 0.0, "step": 0, "land_time": 0.0, "lift_time": 0.0, "lift_from": Vector2.ZERO, "held": null, "held_at": Vector2.ZERO})
	_drifts.clear()
	_seen.clear()
	_shake = 0.0
	_flash = 0.0
	_band_key = ""

## Whether every picture the renderer draws from was found.
func art_ready() -> bool:
	if heroes.size() != 2 or fills.size() != Levels.COUNT or backs.size() != Levels.COUNT:
		return false
	for slot in 2:
		for frame: String in HERO_FRAMES:
			if not heroes[slot].has_frame(frame):
				return false
		for frame: String in ["carry", "carry_run_0", "carry_run_1", "carry_run_2", "carry_run_3", "duck"]:
			if not _holds[slot].has(frame):
				return false
	for stage in Levels.COUNT:
		if not fills[stage].has_frame("main") or not backs[stage].has_frame("main"):
			return false
	for frame: String in ["bug_0", "bug_1", "hopper_0", "hopper_1", "drone_0", "turret_0", "turret_1", "roller_0", "bare_0", "magnet_0", "magnet_1"]:
		if not foes.has_frame(frame):
			return false
	for frame: String in ["vac_closed", "vac_open", "vac_hurt", "crane_open", "crane_shut", "crane_hurt", "claw_open", "claw_shut"]:
		if not bosses.has_frame(frame):
			return false
	for frame: String in ["wood", "steel", "scrap", "hexnut", "nut", "spark", "gear", "acorn", "golden_acorn", "cog", "door_closed", "door_open", "chute", "flag_off", "flag_on", "lift", "shelf_wood", "shelf_metal", "spikes", "fx_puff", "fx_star", "fx_splinter", "fx_bolt"]:
		if not props.has_frame(frame):
			return false
	return true

func _load_art() -> void:
	text = GameText.new()
	for slot in 2:
		heroes.append(GameSprites.load_atlas(ART + "squirrel%d.json" % slot))
		_holds.append(_read_holds(ART + "squirrel%d.json" % slot))
	foes = GameSprites.load_atlas(ART + "foes.json")
	bosses = GameSprites.load_atlas(ART + "bosses.json")
	props = GameSprites.load_atlas(ART + "props.json")
	for stage in Levels.COUNT:
		fills.append(GameSprites.load_image(ART + "ground%d.jpg" % stage, {"width": TILE * FILL_CELLS, "pivot": Vector2.ZERO}))
		backs.append(GameSprites.load_image(ART + "back%d.jpg" % stage, {"width": BACK_SIZE.x, "pivot": Vector2.ZERO}))
	_flash_layer = Node2D.new()
	_flash_layer.name = "Flash"
	var shader := Shader.new()
	shader.code = FLASH_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_flash_layer.material = material
	_flash_layer.draw.connect(_draw_flashes)
	add_child(_flash_layer)
	_plate.bg_color = Color(0.09, 0.07, 0.13, 0.86)
	_plate.set_corner_radius_all(3)
	_plate.corner_detail = 6
	_plate.anti_aliasing_size = 0.3
	_plate.border_color = Color("5fd4c4")
	_plate.border_width_bottom = 1
	for index in MOTES:
		_motes.append({"at": Vector2(_random.float_range(0.0, VIEW.x), _random.float_range(0.0, VIEW.y)), "drift": Vector2(_random.float_range(-4.0, 4.0), _random.float_range(0.4, 1.0)), "size": _random.float_range(0.35, 1.0), "depth": _random.float_range(0.35, 0.8), "phase": _random.float_range(0.0, TAU)})

## The carry spots of one squirrel atlas: its frame table gives them as "hold", in source pixels like the pivot.
func _read_holds(table_path: String) -> Dictionary:
	var spots := {}
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string(table_path))
	if not table is Dictionary:
		return spots
	var size := float(table.get("scale", 1.0))
	var frames: Dictionary = table.get("frames", {})
	for frame: String in frames:
		var entry: Dictionary = frames[frame]
		if entry.get("hold") is Array and entry.get("pivot") is Array:
			spots[frame] = Vector2(float(entry["hold"][0]) - float(entry["pivot"][0]), float(entry["hold"][1]) - float(entry["pivot"][1])) * size
	return spots

## Called from the step with what the world reported; kept short so a run without frames (a test) cannot pile them up.
func note(event: Dictionary) -> void:
	if _pending.size() < MAX_PENDING:
		_pending.append(event)

## Once per rendered frame: turn events into effects, age the particles and the little poses.
func advance(delta: float) -> void:
	_clock += delta
	for event in _pending:
		_react(event)
	_pending.clear()
	_shake = maxf(0.0, _shake - delta * 14.0)
	_flash = maxf(0.0, _flash - delta)
	_offset = Vector2(_random.float_range(-_shake, _shake), _random.float_range(-_shake, _shake)) * 0.6 if _shake > 0.3 else Vector2.ZERO
	for look in _looks:
		look["squash"] = maxf(0.0, float(look["squash"]) - delta)
		look["stretch"] = maxf(0.0, float(look["stretch"]) - delta)
		look["pose_time"] = maxf(0.0, float(look["pose_time"]) - delta)
		look["land_time"] = maxf(0.0, float(look["land_time"]) - delta)
		look["lift_time"] = maxf(0.0, float(look["lift_time"]) - delta)
	for drift in _drifts:
		drift["life"] = float(drift["life"]) - delta
	_drifts = _drifts.filter(func(drift: Dictionary) -> bool: return float(drift["life"]) > 0.0)
	if world != null:
		_track_holds()
		_ambient()
	for particle in _particles:
		particle["life"] = float(particle["life"]) - delta
		particle["vy"] = float(particle["vy"]) + float(particle["g"]) * delta
		particle["x"] = float(particle["x"]) + float(particle["vx"]) * delta
		particle["y"] = float(particle["y"]) + float(particle["vy"]) * delta
		particle["turn"] = float(particle["turn"]) + float(particle["spin"]) * delta
	_particles = _particles.filter(func(particle: Dictionary) -> bool: return float(particle["life"]) > 0.0)
	for popup in _popups:
		popup["life"] = float(popup["life"]) - delta
		popup["y"] = float(popup["y"]) - 22.0 * delta
	_popups = _popups.filter(func(popup: Dictionary) -> bool: return float(popup["life"]) > 0.0)
	var key := _banner_key()
	if key != _band_key:
		_band_key = key
		_band_age = 0.0
	_band_age += delta
	queue_redraw()
	_flash_layer.queue_redraw()

## Notice what each squirrel picked up or let go since the last frame. A new load starts its way up from where it stood; a load let go keeps, for a moment, the distance between the paws it left and the place the simulation gave it.
func _track_holds() -> void:
	for hero in world.heroes:
		var look: Dictionary = _looks[int(hero["slot"])]
		var held: Variant = null
		if int(hero["state"]) == World.H_NORMAL:
			if hero["carry"] is Dictionary:
				held = hero["carry"]
			elif int(hero["lifting"]) >= 0:
				held = world.heroes[int(hero["lifting"])]
		var before: Variant = look["held"]
		var changed: bool = (before == null) != (held == null) or (held != null and not is_same(before, held))
		if changed and before != null:
			_drifts.append({"thing": before, "offset": (look["held_at"] as Vector2) - Vector2(float(before["x"]), float(before["y"])), "life": DRIFT_SPAN})
		if changed and held != null:
			look["lift_time"] = LIFT_SPAN
			look["lift_from"] = Vector2(float(held["x"]), float(held["y"]))
			for entry: Array in _seen:
				if is_same(entry[0], held):
					look["lift_from"] = entry[1]
		look["held"] = held
		if held != null:
			look["held_at"] = _held_spot(hero, _pose(hero))
	_seen.clear()
	for object in world.objects:
		if int(object["state"]) == World.O_REST and world.is_active_at(float(object["x"]), float(object["y"])):
			_seen.append([object, Vector2(float(object["x"]), float(object["y"]))])
	for hero in world.heroes:
		if int(hero["state"]) == World.H_NORMAL:
			_seen.append([hero, Vector2(float(hero["x"]), float(hero["y"]))])

## How far from its simulated place a thing is drawn: nothing, except for the moment after it left a squirrel's paws.
func _drift_of(thing: Dictionary) -> Vector2:
	for drift in _drifts:
		if is_same(drift["thing"], thing):
			var left := clampf(float(drift["life"]) / DRIFT_SPAN, 0.0, 1.0)
			return (drift["offset"] as Vector2) * left * left
	return Vector2.ZERO

## Effects that come from what is going on rather than from one event: the Dustmaw's breath, exhaust, running dust, the trail behind anything thrown.
func _ambient() -> void:
	if not world.boss.is_empty():
		var boss := world.boss
		var mode := str(boss["mode"])
		var facing := float(int(boss["face"]))
		var x := float(boss["x"])
		var y := float(boss["y"])
		if mode == "inhale" and _random.chance(0.7):
			var mouth := Vector2(x + facing * 24.0, y - 16.0)
			var from := mouth + Vector2(facing * _random.float_range(60.0, 200.0), _random.float_range(-50.0, 14.0))
			_spark(from, (mouth - from) * 1.6, 0.0, 0.6, Color(0.85, 0.82, 0.9, 0.7), _random.float_range(0.5, 1.1), "puff" if _random.chance(0.3) else "dot")
		if str(boss["kind"]) == "vacuum" and (mode == "rev" or mode == "charge") and _random.chance(0.6):
			_spark(Vector2(x - facing * 20.0, y - 2.0), Vector2(-facing * _random.float_range(20.0, 60.0), _random.float_range(-30.0, -5.0)), -20.0, 0.45, Color(0.8, 0.76, 0.7, 0.8), _random.float_range(0.5, 0.9), "puff")
		if mode == "dying" and _random.chance(0.4):
			_spark(Vector2(x + _random.float_range(-20.0, 20.0), y - _random.float_range(4.0, 30.0) + (30.0 if str(boss["kind"]) == "crane" else 0.0)), Vector2(_random.float_range(-10.0, 10.0), -30.0), -30.0, 0.7, Color(0.25, 0.24, 0.3, 0.8), _random.float_range(0.7, 1.2), "puff")
		if float(boss.get("shake", 0.0)) > 0.0:
			_shake = maxf(_shake, 1.2)
	for object in world.objects:
		if int(object["state"]) == World.O_THROWN and _random.chance(0.5):
			_spark(Vector2(float(object["x"]), float(object["y"]) - float(object["tall"]) * 0.5 + _random.float_range(-4.0, 4.0)), Vector2.ZERO, 0.0, 0.22, Color(1.0, 0.97, 0.9, 0.8), 0.8, "dot")
	for hero in world.heroes:
		if int(hero["state"]) != World.H_NORMAL or not bool(hero["ground"]) or absf(float(hero["vx"])) < 40.0:
			continue
		var look: Dictionary = _looks[int(hero["slot"])]
		var step := int(float(hero["anim"]) * RUN_FPS / 3.0)
		if step != int(look["step"]):
			look["step"] = step
			_spark(Vector2(float(hero["x"]) - signf(float(hero["vx"])) * 3.0, float(hero["y"]) - 1.0), Vector2(-signf(float(hero["vx"])) * 12.0, -8.0), -10.0, 0.3, Color(0.92, 0.88, 0.8, 0.6), 0.45, "puff")

# ---- effects ----

func _spark(at: Vector2, velocity: Vector2, gravity: float, life: float, color: Color, size: float, kind: String = "dot") -> void:
	if _particles.size() < MAX_PARTICLES:
		_particles.append({"x": at.x, "y": at.y, "vx": velocity.x, "vy": velocity.y, "g": gravity, "life": life, "span": life, "color": color, "size": size, "kind": kind, "turn": _random.float_range(0.0, TAU), "spin": _random.float_range(-9.0, 9.0) if kind != "puff" and kind != "star" else _random.float_range(-1.0, 1.0)})

func _burst(at: Vector2, count: int, speed: float, gravity: float, life: float, colors: Array, size: float, kind: String = "dot") -> void:
	for index in count:
		var angle := _random.float_range(0.0, TAU)
		var pace := _random.float_range(speed * 0.35, speed)
		_spark(at, Vector2(cos(angle), sin(angle)) * pace - Vector2(0, speed * 0.3), gravity, _random.float_range(life * 0.5, life), colors[index % colors.size()], size * _random.float_range(0.7, 1.15), kind)

## A hit flash that does not move.
func _star(at: Vector2, size: float, color: Color = Color.WHITE, life: float = 0.16) -> void:
	_spark(at, Vector2.ZERO, 0.0, life, color, size, "star")

## Dust rolling away along the ground to both sides.
func _dust(at: Vector2, count: int, speed: float, size: float, color: Color = Color(0.92, 0.88, 0.8, 0.75)) -> void:
	for index in count:
		var side := -1.0 if index % 2 == 0 else 1.0
		_spark(at + Vector2(side * 2.0, -1.0), Vector2(side * _random.float_range(speed * 0.4, speed), _random.float_range(-14.0, -2.0)), -12.0, _random.float_range(0.25, 0.42), color, size * _random.float_range(0.7, 1.1), "puff")

## The look record of the squirrel an event at `at` belongs to, or null when none is near.
func _look_near(at: Vector2) -> Variant:
	for hero in world.heroes:
		if int(hero["state"]) != World.H_OUT and absf(float(hero["x"]) - at.x) < 10.0 and absf(float(hero["y"]) - at.y) < 26.0:
			return _looks[int(hero["slot"])]
	return null

func _react(event: Dictionary) -> void:
	var at := Vector2(float(event["x"]), float(event["y"]))
	var look: Variant = _look_near(at)
	match str(event["name"]):
		"jump":
			_dust(at, 2, 22.0, 0.45)
			if look != null:
				look["stretch"] = 0.16
		"land":
			_dust(at, 4, 34.0, 0.55)
			if look != null:
				look["squash"] = 0.14
				look["land_time"] = 0.13
		"thud", "put_down":
			_dust(at, 4, 34.0, 0.6)
		"lift":
			if look != null:
				look["squash"] = 0.1
		"throw", "throw_up":
			_burst(at, 3, 30.0, 0.0, 0.2, [Color("fff7e0")], 0.7)
			if look != null:
				look["pose"] = str(event["name"])
				look["pose_time"] = THROW_SPAN
		"break":
			_burst(at, 9, 100.0, 420.0, 0.7, [Color.WHITE, Color(0.85, 0.8, 0.75)], 0.9, "splinter")
			_dust(at, 4, 40.0, 0.9, Color(0.94, 0.86, 0.7, 0.8))
			_star(at, 1.3)
			_shake = maxf(_shake, 1.5)
		"poof":
			_burst(at, 4, 30.0, -20.0, 0.4, [Color(0.75, 0.78, 0.84, 0.8)], 0.7, "puff")
		"clang":
			_star(at, 0.8, Color("fff3b0"))
			_burst(at, 5, 80.0, 200.0, 0.25, [Color("ffd75e"), Color("fff7e0")], 0.6)
		"foe_hit":
			_star(at, 1.0)
			_burst(at, 5, 70.0, 200.0, 0.3, [Color("fff7e0"), Color("ffd75e")], 0.7)
			_shake = maxf(_shake, 1.5)
		"foe_out":
			_star(at, 1.6)
			_burst(at, 6, 110.0, 300.0, 0.6, [Color.WHITE], 0.9, "bolt")
			_burst(at, 4, 40.0, -20.0, 0.45, [Color(0.3, 0.3, 0.36, 0.7)], 0.8, "puff")
			_burst(at, 6, 100.0, 260.0, 0.45, [Color("fff7e0"), Color("ffd75e"), Color("ff8a3c")], 0.9)
			_shake = maxf(_shake, 2.2)
		"hurt":
			_star(at, 1.3, Color("ff8a8a"))
			_burst(at, 8, 90.0, 240.0, 0.4, [Color("e5484d"), Color("fff7e0")], 0.7)
			_shake = maxf(_shake, 3.0)
			_flash = maxf(_flash, 0.06)
		"die":
			_star(at, 1.8)
			_burst(at, 8, 120.0, 320.0, 0.8, [Color.WHITE], 0.9, "bolt")
			_burst(at, 10, 120.0, 300.0, 0.8, [HERO_COLORS[int(event.get("slot", 0))], Color("fff7e0")], 1.0)
			_burst(at, 4, 40.0, -20.0, 0.6, [Color(0.3, 0.3, 0.36, 0.7)], 0.9, "puff")
			_shake = maxf(_shake, 4.0)
		"respawn":
			_burst(at, 12, 60.0, -60.0, 0.6, [Color("bff3ff"), Color("fff7e0")], 0.7)
		"gear":
			_star(at, 0.6, Color("fff3b0"), 0.12)
			_burst(at, 4, 40.0, 0.0, 0.25, [Color("ffd75e")], 0.6)
		"battery", "core", "flag":
			_star(at, 0.9, Color("d8ffc8"))
			_burst(at, 10, 60.0, -50.0, 0.55, [Color("b8ff9a"), Color("fff7e0"), Color("5fd4c4")], 0.7)
		"cog":
			_star(at, 2.2, Color("fff3b0"), 0.3)
			_burst(at, 18, 90.0, 60.0, 0.9, [Color("ffd75e"), Color("fff7e0"), Color("c9952c")], 0.9)
			_flash = maxf(_flash, 0.08)
		"chute":
			_dust(at, 3, 24.0, 0.6, Color(0.75, 0.78, 0.84, 0.8))
		"shot", "drop", "boss_spit":
			_star(at, 0.7, Color("fff3b0"), 0.1)
			_burst(at, 4, 50.0, 0.0, 0.2, [Color("ffd75e"), Color("fff7e0")], 0.6)
		"boss_hit":
			_star(at, 2.2)
			_burst(at, 5, 130.0, 300.0, 0.6, [Color.WHITE], 1.0, "bolt")
			_burst(at, 12, 130.0, 260.0, 0.5, [Color("fff7e0"), Color("ffd75e"), Color("e5484d")], 1.0)
			_shake = maxf(_shake, 3.5)
			_flash = maxf(_flash, 0.07)
		"boss_slam":
			_dust(at, 10, 90.0, 1.2)
			_star(at, 1.4)
			_shake = maxf(_shake, 6.0)
		"boss_burst":
			_star(at, 1.8, Color("ffc27a"))
			_burst(at, 3, 30.0, -30.0, 0.6, [Color(0.25, 0.24, 0.3, 0.8)], 1.1, "puff")
			_burst(at, 8, 110.0, 120.0, 0.55, [Color("ff8a3c"), Color("ffd75e"), Color("fff7e0")], 1.1)
			_shake = maxf(_shake, 3.0)
		"boss_down":
			_star(at, 4.5, Color.WHITE, 0.4)
			_burst(at, 18, 200.0, 320.0, 1.2, [Color.WHITE], 1.2, "bolt")
			_burst(at, 10, 70.0, -20.0, 1.0, [Color(0.25, 0.24, 0.3, 0.8), Color(0.8, 0.76, 0.7, 0.8)], 1.6, "puff")
			_burst(at, 24, 190.0, 200.0, 1.1, [Color("ff8a3c"), Color("ffd75e"), Color("fff7e0")], 1.3)
			_shake = maxf(_shake, 9.0)
			_flash = maxf(_flash, 0.35)
		"boss_start", "boss_angry":
			_shake = maxf(_shake, 5.0)
		"stage_clear":
			for index in 44:
				_spark(Vector2(world.camera.x + _random.float_range(0.0, VIEW.x), world.camera.y - 4.0 - _random.float_range(0.0, 30.0)), Vector2(_random.float_range(-20.0, 20.0), _random.float_range(30.0, 110.0)), 30.0, 2.6, [Color("5fd4c4"), Color("f5a340"), Color("ffd75e"), Color("fff7e0")][index % 4], _random.float_range(1.6, 2.6), "bit")
		"points":
			if _popups.size() < 12:
				_popups.append({"x": at.x, "y": at.y, "text": "+%d" % int(event.get("points", 0)), "life": 0.9})

# ---- drawing ----

func _draw() -> void:
	if world == null or text == null:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color("1a1423"))
		return
	_camera = world.camera + _offset
	_flashes.clear()
	_draw_backdrop()
	_home()
	_draw_tiles()
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
	# A held crate is drawn with the squirrel that holds it.
	for object in world.objects:
		if int(object["state"]) == World.O_THROWN:
			_draw_object(object)
	for shot in world.shots:
		_draw_shot(shot)
	_draw_particles()
	for popup in _popups:
		var fade := clampf(float(popup["life"]) / 0.3, 0.0, 1.0)
		text.draw(self, Vector2(float(popup["x"]), float(popup["y"])), str(popup["text"]), 8.0, Color(1.0, 0.84, 0.37, fade), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 800, 1.0, Color(0.1, 0.08, 0.14, fade))
	_draw_hint()
	draw_set_transform(Vector2.ZERO)
	_draw_vignette()
	_draw_banners()
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(1, 1, 1, minf(0.6, _flash * 4.0)))

## Back to plain world coordinates.
func _home() -> void:
	draw_set_transform(-_camera)

## Draw a frame with its pivot (the bottom middle of the picture) at a world point, scaled, turned and tinted. `hit` repeats it as a white silhouette on the flash layer.
func _put(sheet: GameSprites, frame: String, at: Vector2, flipped: bool = false, scale: Vector2 = Vector2.ONE, angle: float = 0.0, tint: Color = Color.WHITE, hit: bool = false) -> void:
	draw_set_transform(at - _camera, angle, scale)
	sheet.draw(self, frame, Vector2.ZERO, flipped, 1.0, 0.0, tint)
	_home()
	if hit:
		_flashes.append([sheet, frame, at - _camera, flipped, scale, angle, Vector2.ZERO])

## Draw a frame turned round its own middle, which is put at a world point.
func _spin(sheet: GameSprites, frame: String, middle: Vector2, angle: float, zoom: float = 1.0, tint: Color = Color.WHITE, flipped: bool = false, hit: bool = false) -> void:
	var down := Vector2(0.0, sheet.size(frame).y * 0.5)
	draw_set_transform(middle - _camera, angle, Vector2(zoom, zoom))
	sheet.draw(self, frame, down, flipped, 1.0, 0.0, tint)
	_home()
	if hit:
		_flashes.append([sheet, frame, middle - _camera, flipped, Vector2(zoom, zoom), angle, down])

## The hit flash: every sprite marked this frame once more, on the layer whose shader paints white where the sprite is.
func _draw_flashes() -> void:
	for flash: Array in _flashes:
		_flash_layer.draw_set_transform(flash[2], flash[5], flash[4])
		(flash[0] as GameSprites).draw(_flash_layer, flash[1], flash[6], flash[3])
	_flash_layer.draw_set_transform(Vector2.ZERO)

## A soft contact shadow on the ground under something.
func _shadow(x: float, y: float, half: float, strength: float = 0.3) -> void:
	draw_set_transform(Vector2(x, y) - _camera, 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, half, Color(0.04, 0.03, 0.08, strength), true, -1.0, true)
	_home()

## A rectangle whose colour fades from one edge to the opposite one.
func _fade(rect: Rect2, from: Color, to: Color, vertical: bool = true) -> void:
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var colors := PackedColorArray([from, from, to, to]) if vertical else PackedColorArray([from, to, to, from])
	draw_polygon(points, colors)

func _draw_backdrop() -> void:
	var stage := world.stage
	var look: Dictionary = LOOKS[stage]
	var room := Vector2(maxf(1.0, float(world.width) * TILE - VIEW.x), maxf(1.0, float(world.height) * TILE - VIEW.y - 24.0))
	if room.y > room.x:
		# A shaft is climbed, not crossed: its wall is one picture larger than the view that slides slowly past, and never repeats.
		var big := VIEW * 1.6
		var spare := big - VIEW
		backs[stage].draw_fit(self, "main", Rect2(-Vector2(spare.x * clampf(_camera.x / room.x, 0.0, 1.0), spare.y * clampf(_camera.y / room.y, 0.0, 1.0)), big))
	else:
		var slack := BACK_SIZE - VIEW
		backs[stage].draw_tiled(self, "main", Rect2(Vector2.ZERO, VIEW), BACK_SIZE, Vector2(_camera.x * 0.22, slack.y * clampf(_camera.y / room.y, 0.0, 1.0)))
	draw_rect(Rect2(Vector2.ZERO, VIEW), look["veil"])
	# Specks in the air between the wall and the stage, each at its own depth.
	var tint: Color = look["mote"]
	for mote in _motes:
		var depth := float(mote["depth"])
		var drift: Vector2 = mote["drift"]
		var at: Vector2 = (mote["at"] as Vector2) + Vector2(drift.x, float(look["rise"]) * drift.y) * _clock - _camera * depth
		at = Vector2(fposmod(at.x, VIEW.x), fposmod(at.y, VIEW.y))
		var glow := 0.16 + 0.14 * sin(_clock * 1.7 + float(mote["phase"]))
		draw_circle(at, float(mote["size"]) * (0.6 + depth), Color(tint.r, tint.g, tint.b, glow * (0.5 + depth)), true, -1.0, true)

func _draw_tiles() -> void:
	var stage := world.stage
	var look: Dictionary = LOOKS[stage]
	var fill := fills[stage]
	var cell := fill.texture.get_size() / float(FILL_CELLS) if fill.texture != null else Vector2.ONE
	var shelf := "shelf_wood" if stage == 0 else "shelf_metal"
	var first_column := maxi(0, floori(_camera.x / TILE))
	var last_column := mini(world.width - 1, floori((_camera.x + VIEW.x) / TILE))
	var first_row := maxi(0, floori(_camera.y / TILE))
	var last_row := mini(world.height - 1, floori((_camera.y + VIEW.y) / TILE))
	var edge: Color = look["edge"]
	var dark := Color(edge.r, edge.g, edge.b, 0.34)
	var clear := Color(edge.r, edge.g, edge.b, 0.0)
	for row in range(first_row, last_row + 1):
		for column in range(first_column, last_column + 1):
			var tile := world.tile_at(column, row)
			if tile == Levels.EMPTY:
				continue
			var x := float(column) * TILE
			var y := float(row) * TILE
			if tile == Levels.SHELF:
				props.draw_fit(self, shelf, Rect2(x, y, TILE, 7.0))
				continue
			if tile == Levels.SPIKES:
				props.draw_fit(self, "spikes", Rect2(x, y + 5.0, TILE, 11.0))
				continue
			var open_above := row == 0 or not World.is_solid(world.tile_at(column, row - 1))
			# Ground gets darker the deeper it lies under its surface.
			var shade := Color.WHITE
			if not open_above and row > 1 and World.is_solid(world.tile_at(column, row - 2)):
				shade = Color(0.8, 0.8, 0.84) if row < 3 or not World.is_solid(world.tile_at(column, row - 3)) else Color(0.62, 0.62, 0.7)
			if fill.texture != null:
				draw_texture_rect_region(fill.texture, Rect2(x, y, TILE, TILE), Rect2(Vector2(float(posmod(column, FILL_CELLS)), float(posmod(row, FILL_CELLS))) * cell, cell), shade)
			var open_left := column > 0 and not World.is_solid(world.tile_at(column - 1, row))
			var open_right := column < world.width - 1 and not World.is_solid(world.tile_at(column + 1, row))
			var open_below := row < world.height - 1 and not World.is_solid(world.tile_at(column, row + 1))
			if open_left:
				_fade(Rect2(x, y, 3.5, TILE), dark, clear, false)
				draw_rect(Rect2(x, y, 0.7, TILE), edge)
			if open_right:
				_fade(Rect2(x + TILE - 3.5, y, 3.5, TILE), clear, dark, false)
				draw_rect(Rect2(x + TILE - 0.7, y, 0.7, TILE), edge)
			if open_below:
				_fade(Rect2(x, y + TILE - 4.0, TILE, 4.0), clear, dark)
				draw_rect(Rect2(x, y + TILE - 0.7, TILE, 0.7), edge)
			if tile == Levels.BELT_LEFT or tile == Levels.BELT_RIGHT:
				_draw_belt(x, y, -1.0 if tile == Levels.BELT_LEFT else 1.0, edge)
			elif open_above:
				draw_rect(Rect2(x, y, TILE, 3.0), look["cap"])
				draw_rect(Rect2(x, y, TILE, 0.9), look["lip"])
				draw_rect(Rect2(x, y + 3.0, TILE, 0.6), edge)
				_fade(Rect2(x, y + 3.6, TILE, 3.4), dark, clear)
				# A rivet or a plank joint somewhere on the cap, placed by the cell so that neighbours differ.
				var pick := posmod(column * 73 + row * 151, 11)
				if pick < 6:
					draw_circle(Vector2(x + 2.5 + float(pick) * 2.2, y + 1.9), 0.55, Color(edge.r, edge.g, edge.b, 0.55), true, -1.0, true)
				elif pick < 8:
					draw_rect(Rect2(x + 4.0 + float(pick - 6) * 6.0, y + 0.9, 0.5, 2.1), Color(edge.r, edge.g, edge.b, 0.4))

## The running surface of a conveyor cell: a dark band with chevrons that travel the way the belt pushes.
func _draw_belt(x: float, y: float, direction: float, edge: Color) -> void:
	draw_rect(Rect2(x, y, TILE, 5.0), Color("262a35"))
	draw_rect(Rect2(x, y, TILE, 0.8), Color("8a93a5"))
	draw_rect(Rect2(x, y + 5.0, TILE, 0.6), edge)
	var shift := fposmod(direction * _clock * World.BELT_SPEED, 8.0)
	for index in range(-1, 3):
		var at := x + shift + float(index) * 8.0
		if at < x + 1.6 or at > x + TILE - 1.6:
			continue
		var tip := at + direction * 1.5
		var tail := at - direction * 1.5
		draw_polyline(PackedVector2Array([Vector2(tail, y + 1.6), Vector2(tip, y + 2.9), Vector2(tail, y + 4.2)]), Color("ffd75e"), 0.8, true)

func _draw_fixtures() -> void:
	var door: Variant = world.level.get("door")
	if door is Vector2:
		var at: Vector2 = door
		if world.door_open:
			draw_circle(at + Vector2(0.0, -12.0), 20.0 + sin(_clock * 3.0) * 1.5, Color(0.37, 0.83, 0.77, 0.12), true, -1.0, true)
		_put(props, "door_open" if world.door_open else "door_closed", at)
	for chute in world.chutes:
		# The hatch hangs from the ceiling at its own height.
		_put(props, "chute", Vector2(float(chute["x"]), float(chute["y"]) + props.size("chute").y))
	for index in world.flags.size():
		var flag: Vector2 = world.flags[index]
		var lit := index <= world.checkpoint
		_put(props, "flag_on" if lit else "flag_off", Vector2(flag.x + 3.0, flag.y), false, Vector2(1.0, 1.0 + (sin(_clock * 5.0 + flag.x) * 0.02 if lit else 0.0)))

func _draw_lift(lift: Dictionary) -> void:
	var x := float(lift["x"])
	var y := float(lift["y"])
	var wide := float(lift["w"])
	var slab := props.size("lift")
	var thick := wide * slab.y / maxf(1.0, slab.x)
	# Two small jets hold it up.
	for side: float in [0.22, 0.78]:
		var jet := Vector2(x + wide * side, y + thick - 2.0)
		var long := 3.0 + sin(_clock * 30.0 + side * 9.0) * 1.0
		draw_polygon(PackedVector2Array([jet + Vector2(-1.6, 0.0), jet + Vector2(1.6, 0.0), jet + Vector2(0.0, long)]), PackedColorArray([Color(0.6, 1.0, 0.95, 0.9), Color(0.6, 1.0, 0.95, 0.9), Color(0.37, 0.83, 0.77, 0.0)]))
	props.draw_fit(self, "lift", Rect2(x, y - 0.5, wide, thick))

func _draw_pickup(pickup: Dictionary) -> void:
	var x := float(pickup["x"])
	var y := float(pickup["y"])
	var kind := str(pickup["kind"])
	if bool(pickup["float"]):
		y += sin(_clock * 4.0 + x * 0.1) * 1.5
	match kind:
		"gear":
			# A gear turns on its edge like a coin.
			var turn := cos(_clock * 5.0 + x * 0.05)
			_put(props, "gear", Vector2(x, y), false, Vector2(maxf(0.18, absf(turn)), 1.0))
		"cog":
			draw_circle(Vector2(x, y - 6.0), 9.0 + sin(_clock * 4.0) * 1.0, Color(1.0, 0.84, 0.37, 0.16), true, -1.0, true)
			_spin(props, "cog", Vector2(x, y - 6.0), _clock * 1.5)
			_spin(props, "fx_star", Vector2(x + 4.0, y - 10.0), _clock * 2.0, 0.25 + 0.2 * absf(sin(_clock * 5.0)))
		_:
			draw_circle(Vector2(x, y - 5.0), 6.5, Color(0.72, 1.0, 0.6, 0.12), true, -1.0, true)
			_put(props, str(PICKUP_FRAMES.get(kind, kind)), Vector2(x, y), false, Vector2.ONE * (1.0 + sin(_clock * 6.0 + x) * 0.04))

## A crate or a lump of scrap that nobody holds: at rest or in flight. One that just left a squirrel's paws is drawn on its way from them to where the simulation has it.
func _draw_object(object: Dictionary) -> void:
	var kind := str(object["kind"])
	var shift := _drift_of(object)
	var x := float(object["x"]) + shift.x
	var y := float(object["y"]) + shift.y
	var tall := float(object["tall"])
	var tint := _fading(object)
	if int(object["state"]) == World.O_THROWN:
		# No trail while it is still leaving the paws.
		var back := Vector2(float(object["vx"]), float(object["vy"])) * (0.022 if shift == Vector2.ZERO else 0.0)
		var angle := float(object["spin"]) * 14.0 if kind == "scrap" or kind == "hexnut" else sin(_clock * 22.0) * 0.07
		for ghost in [2, 1]:
			_spin(props, kind, Vector2(x, y - tall * 0.5) - back * float(ghost), angle, 1.0, Color(1.0, 1.0, 1.0, 0.22 / float(ghost)))
		_spin(props, kind, Vector2(x, y - tall * 0.5), angle, 1.0, tint)
		return
	if shift == Vector2.ZERO:
		_shadow(x, y, float(object["half"]) + 1.0, 0.22)
	_put(props, kind, Vector2(x, y), false, Vector2.ONE, 0.0, tint)

## Scrap that is about to vanish blinks.
func _fading(object: Dictionary) -> Color:
	var life := float(object["life"])
	if life > 0.0 and life < 2.0:
		return Color(1.0, 1.0, 1.0, 0.35 + 0.5 * absf(sin(_clock * 18.0)))
	return Color.WHITE

func _draw_shot(shot: Dictionary) -> void:
	var at := Vector2(float(shot["x"]), float(shot["y"]))
	var time := float(shot["time"])
	match str(shot["kind"]):
		"spark":
			draw_circle(at, 5.0, Color(1.0, 0.9, 0.4, 0.18), true, -1.0, true)
			_spin(props, "spark", at, _clock * 11.0, 0.85 + 0.2 * sin(_clock * 40.0))
		"nut":
			_spin(props, "nut", at, time * 9.0)
		"junk":
			_spin(props, "scrap", at, time * 9.0)
		_:
			_spin(props, "hexnut", at, time * 7.0)

func _draw_foe(foe: Dictionary) -> void:
	var kind := str(foe["kind"])
	var x := float(foe["x"])
	var y := float(foe["y"])
	var time := float(foe["time"])
	var mode := str(foe["mode"])
	var tall := float(foe["tall"])
	var frame := kind + "_0"
	var scale := Vector2.ONE
	var angle := 0.0
	var grounded := true
	match kind:
		"bug":
			frame = "bug_%d" % (int(time * 8.0) % 2)
			y -= absf(sin(time * 12.5)) * 0.6
		"hopper":
			grounded = bool(foe["ground"])
			frame = "hopper_0" if grounded else "hopper_1"
			if grounded:
				var breath := sin(time * 9.0) * 0.05
				scale = Vector2(1.0 - breath, 1.0 + breath)
		"drone":
			grounded = false
			y += 2.0
			angle = float(int(foe["face"])) * 0.1 + sin(time * 5.0) * 0.05
			scale = Vector2(1.0, 1.0 + sin(time * 44.0) * 0.03)
		"turret":
			frame = "turret_1" if mode == "aim" else "turret_0"
			if mode == "aim":
				scale = Vector2(1.0 + sin(time * 50.0) * 0.02, 1.0)
		"roller":
			frame = "roller_0" if int(foe["hp"]) > 1 else "bare_0"
			if mode == "rev":
				x += sin(time * 90.0) * 0.9
			elif mode == "dash":
				angle = x / 7.5
			elif mode == "walk":
				angle = sin(x / 7.5) * 0.3
			else:
				angle = sin(time * 9.0) * 0.2
		"magnet":
			grounded = false
			y += 2.0 + sin(time * 4.0) * 0.6
			frame = "magnet_%d" % (int(time * 7.0) % 2)
	var flipped := int(foe["face"]) < 0
	if int(foe["state"]) == Foes.KNOCKED_OUT:
		_spin(foes, frame, Vector2(x, y - tall * 0.5), time * 12.0 * signf(float(foe["vx"])), 1.0, Color.WHITE, flipped, time < 0.1)
		return
	if grounded:
		_shadow(float(foe["x"]), float(foe["y"]), float(foe["half"]) + 1.0)
	var hit := float(foe["flash"]) > 0.0
	if kind == "roller":
		_spin(foes, frame, Vector2(x, y - foes.size(frame).y * 0.5), angle * (-1.0 if flipped else 1.0), 1.0, Color.WHITE, flipped, hit)
	else:
		_put(foes, frame, Vector2(x, y), flipped, scale, angle, Color.WHITE, hit)
	if mode == "dizzy":
		for star in 2:
			var around := _clock * 7.0 + float(star) * PI
			_spin(props, "fx_star", Vector2(x + cos(around) * 7.0, float(foe["y"]) - tall - 4.0 + sin(around) * 2.0), _clock * 4.0, 0.35, Color("ffe27a"))

func _draw_boss(boss: Dictionary) -> void:
	var mode := str(boss["mode"])
	if mode == "gone":
		return
	var x := float(boss["x"])
	var y := float(boss["y"])
	var hurt := float(boss["flash"]) > 0.0 or mode == "dying"
	var white := float(boss["flash"]) > 0.2 or (mode == "dying" and int(_clock * 16.0) % 2 == 0)
	if float(boss.get("shake", 0.0)) > 0.0:
		x += sin(_clock * 120.0) * 1.0
	if str(boss["kind"]) == "vacuum":
		var facing := float(int(boss["face"]))
		var open := mode == "spit" or mode == "inhale"
		var frame := "vac_hurt" if hurt else ("vac_open" if open else "vac_closed")
		# The motor never stops shaking the shell; the breath and the charge pull it out of shape.
		var scale := Vector2(1.0, 1.0 + sin(_clock * 38.0) * 0.008)
		var angle := 0.0
		match mode:
			"inhale":
				scale = Vector2(1.0 + sin(_clock * 16.0) * 0.025, 1.0 - sin(_clock * 16.0) * 0.02)
			"rev":
				x += sin(_clock * 95.0) * 1.1
				angle = -facing * 0.05
			"charge":
				angle = facing * 0.07
				scale = Vector2(1.05, 0.96)
			"spit":
				scale = Vector2(0.97, 1.03)
		_shadow(x, y + 1.0, 24.0, 0.36)
		# The picture faces left; the wheels sit on the floor.
		_put(bosses, frame, Vector2(x + (2.0 if facing < 0.0 else -2.0), y + 1.0), facing > 0.0, scale, angle, Color.WHITE, white)
		return
	# The rail across the room, the trolley, the chain and the claw.
	var left := float(boss["left"])
	var right := float(boss["right"])
	draw_rect(Rect2(left, y - 3.5, right - left, 5.0), Color("2b3140"))
	draw_rect(Rect2(left, y - 3.5, right - left, 1.0), Color("9aa5b8"))
	draw_rect(Rect2(left, y - 1.2, right - left, 1.4), Color("48526a"))
	draw_rect(Rect2(left, y + 1.0, right - left, 0.6), Color("161a24"))
	var post := left + 8.0
	while post < right:
		draw_rect(Rect2(post - 0.8, y - 3.5, 1.6, 5.0), Color("1c202b"))
		post += 32.0
	var chain := float(boss["claw"])
	var link := 0.0
	while link < chain + 2.0:
		var at := Vector2(x, y + 28.5 + link)
		if int(link / 3.0) % 2 == 0:
			draw_arc(at, 1.5, 0.0, TAU, 16, Color("8d98ad"), 0.8, true)
		else:
			draw_line(at - Vector2(0.0, 1.8), at + Vector2(0.0, 1.8), Color("5b657a"), 1.0, true)
		link += 3.0
	if mode == "aim":
		# The eye marks where the claw will come down.
		var floor_y := float(boss["floor"])
		var pulse := 0.35 + 0.35 * absf(sin(_clock * 18.0))
		draw_line(Vector2(x, y + 28.0), Vector2(x, floor_y), Color(1.0, 0.25, 0.25, pulse), 1.0, true)
		draw_set_transform(Vector2(x, floor_y) - _camera, 0.0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 32, Color(1.0, 0.3, 0.3, pulse + 0.2), 1.6, true)
		_home()
	var body := "crane_hurt" if hurt else ("crane_open" if Bosses.is_open(boss) else "crane_shut")
	_put(bosses, body, Vector2(x, y + 28.0), false, Vector2(1.0, 1.0 + sin(_clock * 30.0) * 0.006), 0.0, Color.WHITE, white)
	var shut := mode == "stuck" or mode == "retract"
	_put(bosses, "claw_shut" if shut else "claw_open", Vector2(x, y + 28.0 + chain + 22.0), false, Vector2.ONE, sin(_clock * 3.0) * 0.03 if mode != "stuck" else 0.0, Color.WHITE, white)

## Which frame a squirrel shows and how it is squashed, tilted and lifted off its feet. It reads the simulation and the renderer's own short timers and changes nothing, so the frame under a carried crate is known before anything is drawn. Returns { "frame", "at", "flip", "scale", "angle" }; "at" is where the frame's pivot (the feet) goes.
func _pose(hero: Dictionary) -> Dictionary:
	var slot := int(hero["slot"])
	var look: Dictionary = _looks[slot]
	var anim := float(hero["anim"])
	var carrying: bool = hero["carry"] != null or int(hero["lifting"]) >= 0
	var grounded := bool(hero["ground"])
	var running := grounded and absf(float(hero["vx"])) > 6.0
	var frame := "carry" if carrying else "idle_0"
	var scale := Vector2.ONE
	var angle := 0.0
	var lift := 0.0
	if float(hero["stun"]) > 0.0:
		frame = "hurt"
	elif bool(hero["hide"]):
		frame = "duck"
	elif carrying and float(look["lift_time"]) > LIFT_SPAN * 0.4:
		frame = "lift"
	elif float(look["pose_time"]) > 0.0 and not carrying:
		if str(look["pose"]) == "throw_up":
			frame = "throw_up"
		else:
			frame = "throw_0" if float(look["pose_time"]) > THROW_SPAN - WIND_UP else "throw_1"
	elif not grounded:
		frame = "carry_run_3" if carrying else ("jump" if float(hero["vy"]) < 0.0 else "fall")
		# Long and thin on the way up, a little wide when falling fast.
		var pull := clampf(absf(float(hero["vy"])) / 300.0, 0.0, 1.0) * 0.06
		scale = Vector2(1.0 - pull, 1.0 + pull)
	elif running:
		# The bob of the stride is painted into the frames.
		if carrying:
			frame = "carry_run_%d" % (int(anim * CARRY_RUN_FPS) % 4)
		else:
			frame = "run_%d" % (int(anim * RUN_FPS) % 6)
	elif world.phase == World.P_CLEAR or world.phase == World.P_WON:
		if not carrying:
			frame = "cheer"
		lift = absf(sin(_clock * 7.0 + float(slot))) * 3.0
	elif float(look["land_time"]) > 0.0 and not carrying:
		frame = "land"
	else:
		# Standing still it breathes, and blinks now and then.
		var breath := sin(anim * 3.0 + float(slot)) * 0.018
		scale = Vector2(1.0 - breath, 1.0 + breath)
		if not carrying and fmod(anim + float(slot) * 1.3, 3.4) < 0.13:
			frame = "idle_1"
	var squash := float(look["squash"]) / 0.14
	var stretch := float(look["stretch"]) / 0.16
	if squash > 0.0:
		scale *= Vector2(1.0 + 0.16 * squash, 1.0 - 0.16 * squash)
	elif stretch > 0.0:
		scale *= Vector2(1.0 - 0.1 * stretch, 1.0 + 0.12 * stretch)
	var shift := _drift_of(hero)
	return {"frame": frame, "at": Vector2(float(hero["x"]) + shift.x, float(hero["y"]) + shift.y + 0.5 - lift), "flip": int(hero["face"]) < 0, "scale": scale, "angle": angle}

## Where the bottom middle of what a squirrel carries is drawn: on the paws of the frame it shows, wherever the squash, the stride and the facing put them. While the load is on its way up from the floor it travels there from where it stood; hidden under a crate, the crate is lowered to the spot the crouching frame names.
func _held_spot(hero: Dictionary, pose: Dictionary) -> Vector2:
	var slot := int(hero["slot"])
	var look: Dictionary = _looks[slot]
	var frame := str(pose["frame"])
	var hold: Vector2 = _holds[slot].get(frame if _holds[slot].has(frame) else "carry", HOLD_DEFAULT)
	var spot: Vector2 = (pose["at"] as Vector2) + (Vector2(-hold.x if bool(pose["flip"]) else hold.x, hold.y) * (pose["scale"] as Vector2)).rotated(float(pose["angle"]))
	var rising := float(look["lift_time"]) / LIFT_SPAN
	if rising > 0.0:
		var from: Vector2 = look["lift_from"]
		var along := 1.0 - rising * rising
		spot = from.lerp(spot, along) - Vector2(0.0, sin(along * PI) * 2.0)
	return spot

## What a squirrel holds, drawn on its paws: a crate, a lump of scrap or the partner.
func _draw_held(hero: Dictionary, spot: Vector2) -> void:
	var carried: Variant = hero["carry"]
	if carried is Dictionary:
		_put(props, str(carried["kind"]), spot + Vector2(0.0, HOLD_SINK), false, Vector2.ONE, 0.0, _fading(carried))
	elif int(hero["lifting"]) >= 0:
		var partner := world.heroes[int(hero["lifting"])]
		_put(heroes[int(partner["slot"])], "carried", spot + Vector2(0.0, HOLD_SINK), int(hero["face"]) < 0, Vector2.ONE, 0.0, _blinking(partner))

## A squirrel that cannot be hurt for a moment flickers.
func _blinking(hero: Dictionary) -> Color:
	if float(hero["inv"]) > 0.0 and world.phase == World.P_PLAY:
		return Color(1.0, 1.0, 1.0, 0.4 + 0.45 * absf(sin(_clock * 24.0)))
	return Color.WHITE

func _draw_hero(hero: Dictionary) -> void:
	var state := int(hero["state"])
	# A carried squirrel is drawn by its carrier, on the paws.
	if state == World.H_OUT or state == World.H_CARRIED:
		return
	var slot := int(hero["slot"])
	var sheet := heroes[slot]
	var shift := _drift_of(hero)
	var x := float(hero["x"]) + shift.x
	var y := float(hero["y"]) + shift.y
	var facing := float(int(hero["face"]))
	if state == World.H_DEAD:
		_spin(sheet, "out", Vector2(x, y - 9.0), _clock * 9.0 * facing, 1.0, Color.WHITE, facing < 0.0)
		return
	var tint := _blinking(hero)
	if state == World.H_THROWN:
		# Curled up, it tumbles through the air.
		_spin(sheet, "carried", Vector2(x, y - 8.0), float(hero["throw_time"]) * 16.0 * facing, 1.0, tint, facing < 0.0)
		return
	var pose := _pose(hero)
	var at: Vector2 = pose["at"]
	if bool(hero["ground"]):
		_shadow(x, y + 0.5, 7.0)
	var hiding := bool(hero["hide"])
	var spot := _held_spot(hero, pose)
	# The load goes behind the squirrel so that its paws lie over the bottom edge; a crate it hides under comes down in front of it and leaves the eyes peeking out.
	if not hiding:
		_draw_held(hero, spot)
	_put(sheet, str(pose["frame"]), at, bool(pose["flip"]), pose["scale"], float(pose["angle"]), tint, float(hero["stun"]) > 0.2)
	if hiding:
		_draw_held(hero, spot)
	if world.stage_time < 4.0 and world.phase == World.P_PLAY:
		# Its name, and with two players a marker in its scarf colour, while the stage is new.
		var top := Vector2(x, y - 30.0 + sin(_clock * 8.0) * 1.0)
		var fade := clampf(4.0 - world.stage_time, 0.0, 1.0)
		var ink := Color(0.1, 0.08, 0.14, fade)
		var color: Color = HERO_COLORS[slot]
		if players > 1:
			draw_colored_polygon(PackedVector2Array([top + Vector2(-3.4, -4.4), top + Vector2(3.4, -4.4), top + Vector2(0.0, 0.6)]), ink)
			draw_colored_polygon(PackedVector2Array([top + Vector2(-2.2, -3.8), top + Vector2(2.2, -3.8), top + Vector2(0.0, -0.6)]), Color(color.r, color.g, color.b, fade))
		text.draw(self, top + Vector2(0.0, -7.0), Texts.of("hero_%d" % slot, locale), 6.5, Color(color.r, color.g, color.b, fade), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 800, 0.8, ink)

func _draw_particles() -> void:
	for particle in _particles:
		var left := clampf(float(particle["life"]) / float(particle["span"]), 0.0, 1.0)
		var at := Vector2(float(particle["x"]), float(particle["y"]))
		var color: Color = particle["color"]
		var size := float(particle["size"])
		match str(particle["kind"]):
			"puff":
				_spin(props, "fx_puff", at, float(particle["turn"]), size * (1.4 - 0.8 * left), Color(color.r, color.g, color.b, color.a * left))
			"star":
				_spin(props, "fx_star", at, float(particle["turn"]), size * (0.5 + 0.7 * (1.0 - left)), Color(color.r, color.g, color.b, minf(1.0, left * 2.0)))
			"splinter":
				_spin(props, "fx_splinter", at, float(particle["turn"]), size, Color(color.r, color.g, color.b, minf(1.0, left * 3.0)))
			"bolt":
				_spin(props, "fx_bolt", at, float(particle["turn"]), size, Color(color.r, color.g, color.b, minf(1.0, left * 3.0)))
			"bit":
				draw_set_transform(at - _camera, float(particle["turn"]), Vector2(1.0, absf(cos(float(particle["turn"]) * 0.7)) * 0.8 + 0.2))
				draw_rect(Rect2(-size * 0.5, -size * 0.3, size, size * 0.6), Color(color.r, color.g, color.b, minf(1.0, left * 4.0)))
				_home()
			_:
				draw_circle(at, size * (0.4 + 0.6 * left), Color(color.r, color.g, color.b, color.a * minf(1.0, left * 2.5)), true, -1.0, true)

## One hint at a time: the one nearest to a squirrel, and only while that squirrel stands by it.
func _draw_hint() -> void:
	if world.phase != World.P_PLAY:
		return
	var key := ""
	var hint_x := 0.0
	var distance := 44.0
	for hint: Dictionary in world.level.get("hints", []):
		var at: Vector2 = hint["at"]
		for hero in world.heroes:
			if int(hero["state"]) != World.H_OUT and absf(float(hero["x"]) - at.x) < distance:
				distance = absf(float(hero["x"]) - at.x)
				key = str(hint["key"])
				hint_x = at.x
	if key == "":
		return
	var words := Texts.of(key, locale)
	var size := 8.0 if locale == "en" else 9.0
	var wide := text.measure(words, size, 700).x
	var middle := Vector2(clampf(hint_x, _camera.x + wide * 0.5 + 10.0, _camera.x + VIEW.x - wide * 0.5 - 10.0), _camera.y + 78.0 + sin(_clock * 2.5) * 1.0)
	draw_style_box(_plate, Rect2(middle.x - wide * 0.5 - 6.0, middle.y - size - 3.0, wide + 12.0, size + 8.0))
	text.draw(self, middle, words, size, Color("fff7e0"), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 700)

## Darker corners pull the eye to the middle of the stage.
func _draw_vignette() -> void:
	var dark := Color(0.03, 0.02, 0.07, 0.42)
	var clear := Color(0.03, 0.02, 0.07, 0.0)
	_fade(Rect2(0.0, 0.0, VIEW.x, 34.0), dark, clear)
	_fade(Rect2(0.0, VIEW.y - 26.0, VIEW.x, 26.0), clear, dark)
	_fade(Rect2(0.0, 0.0, 40.0, VIEW.y), Color(dark.r, dark.g, dark.b, 0.3), clear, false)
	_fade(Rect2(VIEW.x - 40.0, 0.0, 40.0, VIEW.y), clear, Color(dark.r, dark.g, dark.b, 0.3), false)

## Which banner is up, as one word; an empty string when none is.
func _banner_key() -> String:
	if world == null:
		return ""
	match world.phase:
		World.P_INTRO:
			return "intro"
		World.P_CLEAR, World.P_WON:
			return "clear"
		World.P_RETRY:
			return "retry"
		World.P_OVER, World.P_LOST:
			return "lost"
	if not world.boss.is_empty() and str(world.boss["mode"]) == "enter":
		return "boss"
	return ""

func _band(title: String, subtitle: String, accent: Color) -> void:
	# The band opens from its middle line and the title settles after it.
	var open := 1.0 - pow(1.0 - clampf(_band_age / 0.28, 0.0, 1.0), 3.0)
	var half := 27.0 * open
	var middle := 108.0
	var ink := Color(0.08, 0.06, 0.13, 0.9)
	var thin := Color(0.08, 0.06, 0.13, 0.0)
	draw_rect(Rect2(0.0, middle - half, VIEW.x, half * 2.0), Color(0.08, 0.06, 0.13, 0.78))
	_fade(Rect2(0.0, middle - half - 10.0, VIEW.x, 10.0), thin, Color(ink.r, ink.g, ink.b, 0.5))
	_fade(Rect2(0.0, middle + half, VIEW.x, 10.0), Color(ink.r, ink.g, ink.b, 0.5), thin)
	for side: float in [-1.0, 1.0]:
		var line := middle + side * half
		_fade(Rect2(0.0, line - 0.6, VIEW.x * 0.5, 1.2), Color(accent.r, accent.g, accent.b, 0.0), accent, false)
		_fade(Rect2(VIEW.x * 0.5, line - 0.6, VIEW.x * 0.5, 1.2), accent, Color(accent.r, accent.g, accent.b, 0.0), false)
	if open < 0.6:
		return
	var show := clampf((_band_age - 0.16) / 0.25, 0.0, 1.0)
	var slide := (1.0 - show) * 14.0
	var white := Color(1.0, 0.97, 0.88, show)
	var size := 20.0
	var wide := text.measure(title, size, 800).x
	var baseline := middle + (2.0 if subtitle != "" else 7.0)
	text.draw(self, Vector2(VIEW.x * 0.5 - slide, baseline), title, size, white, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 800, 1.2, Color(0.1, 0.07, 0.14, show))
	# A gear turns at each end of the title.
	for side: float in [-1.0, 1.0]:
		draw_set_transform(Vector2(VIEW.x * 0.5 + side * (wide * 0.5 + 14.0) - slide, baseline - 7.0), _clock * 1.6 * side, Vector2.ONE * 1.3)
		props.draw(self, "gear", Vector2(0.0, props.size("gear").y * 0.5), false, 1.0, 0.0, Color(1.0, 1.0, 1.0, show))
		draw_set_transform(Vector2.ZERO)
	if subtitle != "":
		text.draw(self, Vector2(VIEW.x * 0.5 + slide, middle + 18.0), subtitle, 9.0 if locale == "en" else 10.0, Color(accent.r, accent.g, accent.b, show), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 700, 0.8, Color(0.1, 0.07, 0.14, show))

func _draw_banners() -> void:
	match _band_key:
		"intro":
			_band(Texts.of("stage", locale) % (world.stage + 1), str(Levels.NAMES[world.stage]["en" if locale == "en" else "zh"]).to_upper(), Color("5fd4c4"))
		"clear":
			var last := world.stage + 1 >= Levels.COUNT
			_band(Texts.of("won" if last else "clear", locale), "", Color("ffd75e"))
		"retry":
			_band(Texts.of("continue", locale) % maxi(0, world.continues_left - 1), "", Color("f5a340"))
		"lost":
			_band(Texts.of("lost", locale), "", Color("e5484d"))
		"boss":
			var kind := str(world.boss["kind"])
			_band(Texts.of("boss_" + kind, locale), Texts.of("boss_tip_" + kind, locale), Color("e5484d"))
