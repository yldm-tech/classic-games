extends Node2D

## Draws Crate Crew and owns everything that is only for the eye: the map between levels, the painted places in two layers of depth, which frame a squirrel shows and where the thing it carries rests on its paws, squash and stretch, shadows, particles, screen shake, flashes, floating points, the tells of the bosses and the banners. It reads the simulation and never changes it; its own randomness comes from a private generator so the game's seeded sequence is untouched. All art is loaded from art/ once; positions are stage pixels and every sprite stands on the unchanged collision boxes of world.gd. The squirrels are painted larger than their 10 x 14 box: feet on its bottom edge, body on its middle, head, ears and tail above and behind it.

const World := preload("res://games/crate_crew/world.gd")
const Foes := preload("res://games/crate_crew/foes.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Bosses := preload("res://games/crate_crew/bosses.gd")
const Texts := preload("res://games/crate_crew/texts.gd")
const Rng := preload("res://games/shared/game_rng.gd")

const ART := "res://games/crate_crew/art/"
const VIEW := Vector2(384, 216)
const TILE := 16.0
const MAX_PARTICLES := 240
const MAX_PENDING := 96
const HERO_COLORS := [Color("5fd4c4"), Color("f5a340")]
## The actions a squirrel atlas holds as numbered frames ("run_0", "run_1" ...), cut from short clips of the squirrel moving, and the single pictures beside them.
const HERO_MOVES := ["idle", "run", "jump", "fall", "land", "lift", "carry", "carry_run", "throw", "throw_up", "duck", "hide", "hurt", "cheer"]
const HERO_STILLS := ["carry_jump", "carry_fall", "out", "carried"]
## The actions in which something rests on the paws: every frame of them names its carry spot.
const HERO_CARRIES := ["lift", "carry", "carry_run", "duck", "hide"]
## Stage pixels one cycle of a run covers when an atlas does not say: the legs turn with the distance run, so the feet do not slide.
const STRIDE_DEFAULT := 28.0
## How long the pick-up plays, which first part of it brings the load from where it stood into the paws, and how long something let go takes to settle from the paws onto the path the simulation gives it.
const LIFT_SPAN := 0.22
const GRIP := 0.35
const DRIFT_SPAN := 0.1
## How long the throw, the landing, the crouch under a crate and the recoil play. The recoil is as long as the simulation stuns.
const THROW_SPAN := 0.26
const LAND_SPAN := 0.18
const DUCK_SPAN := 0.12
const HURT_SPAN := 0.3
## The turn on the heel, the lean into a start and the lean back out of a stop.
const TURN_SPAN := 0.08
const START_SPAN := 0.12
const STOP_SPAN := 0.1
## A carried thing sinks this far into the paws, so the fingers lie over its bottom edge.
const HOLD_SINK := 0.4
## Where a carried thing rests when a frame names no spot of its own, from the feet.
const HOLD_DEFAULT := Vector2(0.0, -22.0)
## The white silhouette laid over a sprite that was just hit.
const FLASH_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * 0.85);\n}\n"
## The painted ground texture covers this many cells each way, so no single cell repeats beside itself.
const FILL_CELLS := 4
const FAR_SIZE := Vector2(480, 270)
const MOTES := 30
## The file names of the places' pictures.
const ART_NAMES := {"kitchen": "kitchen", "toyshop": "toys", "sewer": "sewer", "treehouse": "tree"}
## Every frame the enemy, boss and prop atlases must hold.
const FOE_FRAMES := ["ant", "fly", "shaker", "mouse", "jack", "plane", "rat", "frog", "slime", "worm", "hornet", "spider"]
const BOSS_FRAMES := ["toaster_idle", "toaster_pop", "toaster_crouch", "toaster_hurt", "robot_idle", "robot_throw", "robot_charge", "robot_hurt", "crayfish_idle", "crayfish_snap", "crayfish_dive", "crayfish_hurt", "crow_fly_0", "crow_fly_1", "crow_dive", "crow_perch", "crow_hurt"]
const PROP_FRAMES := ["wood", "steel", "apple", "can", "block", "nut", "walnut", "pinecone", "toast", "cog", "acorn", "acorn_bag", "heart", "golden_acorn", "flag_off", "flag_on", "exit_closed", "exit_open", "hole", "burrow", "crack", "fx_puff", "fx_star", "fx_splinter", "fx_bolt", "shelf_kitchen", "shelf_toys", "shelf_sewer", "shelf_tree", "hazard_kitchen", "hazard_toys", "hazard_sewer", "hazard_tree"]
## How much larger than its collision box each enemy is painted, so the small ones read at a glance; the boxes stay as they are.
const FOE_ZOOM := {"ant": 1.35, "fly": 1.55, "shaker": 1.1, "mouse": 1.25, "jack": 1.15, "plane": 1.45, "rat": 1.1, "frog": 1.15, "slime": 1.25, "worm": 1.2, "hornet": 1.4, "spider": 1.3}
const BOSS_ZOOM := 1.12
## Boss pictures that were painted facing right while the rest face left.
const FACING_RIGHT := ["robot_charge"]
## Pick-up kinds of the simulation and the props that show them.
const PICKUP_FRAMES := {"acorn": "acorn", "bag": "acorn_bag", "heart": "heart", "golden": "golden_acorn"}

## Per place: the lit top of the ground, its highlight, the dark outline, the colour laid over the far wall so play stands out, the colour and drift of the specks in the air, and the colour of the map's nodes.
const LOOKS := {
	"kitchen": {"cap": Color("d9a565"), "lip": Color("f7dcab"), "edge": Color("3a2418"), "veil": Color(0.08, 0.05, 0.04, 0.14), "mote": Color("ffe2a8"), "rise": -3.0, "node": Color("f5a340")},
	"toyshop": {"cap": Color("e8705a"), "lip": Color("ffd1a0"), "edge": Color("3a1a24"), "veil": Color(0.07, 0.04, 0.08, 0.14), "mote": Color("ffe9c0"), "rise": -2.0, "node": Color("e8705a")},
	"sewer": {"cap": Color("6f9a6a"), "lip": Color("c3e0a8"), "edge": Color("12201b"), "veil": Color(0.02, 0.07, 0.06, 0.2), "mote": Color("c8f0d0"), "rise": 6.0, "node": Color("6fc8a0")},
	"treehouse": {"cap": Color("b98a52"), "lip": Color("f4d39a"), "edge": Color("2e1c10"), "veil": Color(0.08, 0.04, 0.02, 0.12), "mote": Color("ffd27a"), "rise": -1.5, "node": Color("9bd06a")},
}

var world: World
var locale := "zh"
var players := 1

var heroes: Array[GameSprites] = []
var foes: GameSprites
var bosses: GameSprites
var props: GameSprites
var fills: Dictionary = {}
var fars: Dictionary = {}
var mids: Dictionary = {}
var map_art: GameSprites
var text: GameText

var _random: GameRng = Rng.new(20261)
var _pending: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _looks: Array[Dictionary] = []
## Per squirrel: frame name -> where the bottom middle of a carried thing rests, in stage pixels from the frame's pivot, for a squirrel facing right. Read from the "hold" entries of the frame tables.
var _holds: Array[Dictionary] = []
## Per squirrel: action -> how many frames it has.
var _counts: Array[Dictionary] = []
## Per squirrel: run action -> { "stride": stage pixels per cycle, "steps": the parts of the cycle (0 .. 1) at which a foot comes down }.
var _gaits: Array[Dictionary] = []
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
## A short banner over the play that is not tied to a phase: a secret found, a boss's new phase.
var _call := ""
var _call_age := 9.0

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
		_looks.append({"squash": 0.0, "stretch": 0.0, "pose": "", "pose_time": 0.0, "stride": 0.0, "land_time": 0.0, "lift_time": 0.0, "lift_from": Vector2.ZERO, "held": null, "held_at": Vector2.ZERO, "running": false, "face": 0, "turn": 0.0, "start": 0.0, "stop": 0.0, "hide_time": 0.0, "rise": 0.0, "air": 0.0})
	_drifts.clear()
	_seen.clear()
	_shake = 0.0
	_flash = 0.0
	_band_key = ""
	_call = ""

## Whether every picture the renderer draws from was found.
func art_ready() -> bool:
	if heroes.size() != 2 or map_art == null or not map_art.has_frame("main"):
		return false
	for slot in 2:
		for move: String in HERO_MOVES:
			if int(_counts[slot].get(move, 0)) < 1:
				return false
			for index in int(_counts[slot][move]):
				if not heroes[slot].has_frame("%s_%d" % [move, index]):
					return false
		for frame: String in HERO_STILLS:
			if not heroes[slot].has_frame(frame):
				return false
		for move: String in HERO_CARRIES:
			for index in int(_counts[slot][move]):
				if not _holds[slot].has("%s_%d" % [move, index]):
					return false
	for theme: String in Levels.THEMES:
		for sheet: Variant in [fills.get(theme), fars.get(theme), mids.get(theme)]:
			if not sheet is GameSprites or not (sheet as GameSprites).has_frame("main"):
				return false
	for kind: String in FOE_FRAMES:
		if not _has(foes, kind + "_0") or not _has(foes, kind + "_1"):
			return false
	for frame: String in BOSS_FRAMES:
		if not _has(bosses, frame):
			return false
	for frame: String in PROP_FRAMES:
		if not _has(props, frame):
			return false
	return true

static func _has(sheet: GameSprites, frame: String) -> bool:
	return sheet != null and sheet.has_frame(frame)

## An atlas, or null when its frame table is not there (the art of a place still to come draws as plain shapes).
static func _atlas(name: String) -> GameSprites:
	return GameSprites.load_atlas(ART + name + ".json") if FileAccess.file_exists(ART + name + ".json") else null

static func _image(path: String, options: Dictionary) -> GameSprites:
	return GameSprites.load_image(ART + path, options) if ResourceLoader.exists(ART + path) else null

func _load_art() -> void:
	text = GameText.new()
	for slot in 2:
		heroes.append(GameSprites.load_atlas(ART + "squirrel%d.json" % slot))
		var table := _read_table(ART + "squirrel%d.json" % slot)
		_holds.append(table["holds"])
		_counts.append(table["counts"])
		_gaits.append(table["gaits"])
	foes = _atlas("foes")
	bosses = _atlas("bosses")
	props = _atlas("props")
	for theme: String in Levels.THEMES:
		var name: String = ART_NAMES[theme]
		fills[theme] = _image("ground_%s.jpg" % name, {"width": TILE * FILL_CELLS, "pivot": Vector2.ZERO})
		fars[theme] = _image("far_%s.jpg" % name, {"width": FAR_SIZE.x, "pivot": Vector2.ZERO})
		mids[theme] = _image("mid_%s.webp" % name, {"height": VIEW.y, "pivot": Vector2.ZERO})
	map_art = _image("map.jpg", {"width": VIEW.x, "pivot": Vector2.ZERO})
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

## What the renderer needs from one squirrel's frame table beyond the pictures: the carry spot of each carrying frame ("hold", in source pixels like the pivot), how many frames each action has, and the stride and footfalls of its runs ("gaits").
func _read_table(table_path: String) -> Dictionary:
	var spots := {}
	var counts := {}
	var gaits := {}
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string(table_path))
	if not table is Dictionary:
		return {"holds": spots, "counts": counts, "gaits": gaits}
	var size := float(table.get("scale", 1.0))
	var frames: Dictionary = table.get("frames", {})
	for frame: String in frames:
		var entry: Dictionary = frames[frame]
		if entry.get("hold") is Array and entry.get("pivot") is Array:
			spots[frame] = Vector2(float(entry["hold"][0]) - float(entry["pivot"][0]), float(entry["hold"][1]) - float(entry["pivot"][1])) * size
		var cut := frame.rfind("_")
		if cut > 0 and frame.substr(cut + 1).is_valid_int():
			var move := frame.substr(0, cut)
			counts[move] = maxi(int(counts.get(move, 0)), int(frame.substr(cut + 1)) + 1)
	if table.get("gaits") is Dictionary:
		gaits = table["gaits"]
	return {"holds": spots, "counts": counts, "gaits": gaits}

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
	_call_age += delta
	_offset = Vector2(_random.float_range(-_shake, _shake), _random.float_range(-_shake, _shake)) * 0.6 if _shake > 0.3 else Vector2.ZERO
	for look in _looks:
		for timer: String in ["squash", "stretch", "pose_time", "land_time", "lift_time", "turn", "start", "stop", "rise"]:
			look[timer] = maxf(0.0, float(look[timer]) - delta)
	for drift in _drifts:
		drift["life"] = float(drift["life"]) - delta
	_drifts = _drifts.filter(func(drift: Dictionary) -> bool: return float(drift["life"]) > 0.0)
	if world != null and world.phase != World.P_MAP:
		_track_motion(delta)
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
## Which run a squirrel is in: its legs turn at the pace of that one.
func _gait_of(hero: Dictionary) -> String:
	return "carry_run" if hero["carry"] != null or int(hero["lifting"]) >= 0 else "run"

## Stage pixels one cycle of a squirrel's run covers.
func _stride_of(slot: int, gait: String) -> float:
	var entry: Variant = _gaits[slot].get(gait)
	return maxf(8.0, float(entry.get("stride", STRIDE_DEFAULT))) if entry is Dictionary else STRIDE_DEFAULT

## The renderer's own memory of how each squirrel moves: how far through its stride it is (the legs turn with the ground covered, not with the clock), when it turned round, set off or stopped, how long it has been crouching under its crate, and a puff of dust for every foot that comes down.
func _track_motion(delta: float) -> void:
	for hero in world.heroes:
		var slot := int(hero["slot"])
		var look: Dictionary = _looks[slot]
		var normal := int(hero["state"]) == World.H_NORMAL
		var grounded := normal and bool(hero["ground"])
		var speed := absf(float(hero["vx"]))
		var running := grounded and speed > 6.0 and float(hero["stun"]) <= 0.0
		var facing := int(hero["face"])
		if running:
			if not bool(look["running"]):
				# Every run sets off on the same foot.
				look["stride"] = 0.0
				look["start"] = START_SPAN
				look["stop"] = 0.0
			elif facing != int(look["face"]) and int(look["face"]) != 0:
				look["turn"] = TURN_SPAN
				_dust(Vector2(float(hero["x"]), float(hero["y"])), 3, 30.0, 0.5)
			var gait := _gait_of(hero)
			var before := fposmod(float(look["stride"]), 1.0)
			var after := before + speed * delta / _stride_of(slot, gait)
			look["stride"] = float(look["stride"]) + speed * delta / _stride_of(slot, gait)
			var entry: Variant = _gaits[slot].get(gait)
			if entry is Dictionary:
				for step: Variant in entry.get("steps", []):
					var part := float(step)
					if (before < part and after >= part) or (before < part + 1.0 and after >= part + 1.0):
						_spark(Vector2(float(hero["x"]) - float(facing) * 3.0, float(hero["y"]) - 0.5), Vector2(-float(facing) * 14.0, -9.0), -10.0, 0.3, Color(0.92, 0.88, 0.8, 0.6), 0.45, "puff")
		elif bool(look["running"]) and grounded:
			look["stop"] = STOP_SPAN
			look["start"] = 0.0
		look["running"] = running
		look["face"] = facing
		look["air"] = 0.0 if grounded or not normal else float(look["air"]) + delta
		var hiding := normal and bool(hero["hide"])
		if hiding:
			look["hide_time"] = float(look["hide_time"]) + delta
		elif float(look["hide_time"]) > 0.0:
			look["hide_time"] = 0.0
			if normal and hero["carry"] != null:
				look["rise"] = DUCK_SPAN

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

## Effects that come from what is going on rather than from one event: the trail behind anything thrown, steam from a boss winding up, bubbles where the crayfish will come up, the glow round a boss's lump. The dust of running feet comes from _track_motion.
func _ambient() -> void:
	if not world.boss.is_empty():
		var boss := world.boss
		var mode := str(boss["mode"])
		var x := float(boss["x"])
		var y := float(boss["y"])
		if mode.ends_with("_tell") and _random.chance(0.5):
			_spark(Vector2(x + _random.float_range(-float(boss["half"]), float(boss["half"])), y - _random.float_range(4.0, float(boss["tall"]))), Vector2(0, -30), -20.0, 0.4, Color(1.0, 0.85, 0.5, 0.7), 0.6, "puff")
		if mode == "rise_tell" or mode == "under":
			if _random.chance(0.6):
				_spark(Vector2(x + _random.float_range(-26.0, 26.0), y - 2.0), Vector2(_random.float_range(-6.0, 6.0), -_random.float_range(30.0, 60.0)), -10.0, 0.5, Color(0.8, 1.0, 0.9, 0.8), _random.float_range(0.5, 1.0), "bubble")
		if mode == "charge" and _random.chance(0.7):
			_spark(Vector2(x - float(int(boss["face"])) * 14.0, y - 2.0), Vector2(-float(int(boss["face"])) * 40.0, -20.0), -20.0, 0.45, Color(0.85, 0.82, 0.76, 0.8), 0.8, "puff")
		if mode == "dying" and _random.chance(0.4):
			_spark(Vector2(x + _random.float_range(-20.0, 20.0), y - _random.float_range(4.0, 40.0)), Vector2(_random.float_range(-10.0, 10.0), -30.0), -30.0, 0.7, Color(0.25, 0.24, 0.3, 0.8), _random.float_range(0.7, 1.2), "puff")
		if float(boss.get("shake", 0.0)) > 0.0:
			_shake = maxf(_shake, 1.2)
	for object in world.objects:
		if int(object["state"]) == World.O_THROWN and _random.chance(0.6):
			_spark(Vector2(float(object["x"]), float(object["y"]) - float(object["tall"]) * 0.5 + _random.float_range(-4.0, 4.0)), Vector2.ZERO, 0.0, 0.2, Color(1.0, 0.97, 0.9, 0.8), 0.8, "dot")
	if world.theme == "sewer" and _random.chance(0.05):
		_spark(Vector2(world.camera.x + _random.float_range(0.0, VIEW.x), world.camera.y), Vector2(0, 40), 300.0, 1.0, Color(0.7, 0.95, 0.85, 0.6), 0.5, "dot")

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
	var look: Variant = _look_near(at) if world.phase != World.P_MAP else null
	if event.has("slot") and int(event["slot"]) >= 0 and int(event["slot"]) < 2:
		look = _looks[int(event["slot"])]
	match str(event["name"]):
		"jump":
			_dust(at, 2, 22.0, 0.45)
			if look != null:
				look["stretch"] = 0.12
		"land":
			_dust(at, 4, 34.0, 0.55)
			if look != null:
				look["squash"] = 0.1
				look["land_time"] = LAND_SPAN
		"thud", "put_down":
			_dust(at, 4, 34.0, 0.6)
		"lift":
			if look != null:
				look["squash"] = 0.08
		"throw", "throw_up":
			_burst(at, 4, 40.0, 0.0, 0.2, [Color("fff7e0")], 0.7)
			if look != null:
				look["pose"] = str(event["name"])
				look["pose_time"] = THROW_SPAN
		"break":
			var chips := [Color.WHITE, Color(0.85, 0.8, 0.75)]
			if str(event.get("kind", "")) == "apple":
				chips = [Color("f05a46"), Color("ffe6b0")]
			elif str(event.get("kind", "")) == "toast":
				chips = [Color("e0a050"), Color("fff0c0")]
			_burst(at, 10, 110.0, 420.0, 0.7, chips, 0.9, "splinter")
			_dust(at, 4, 40.0, 0.9, Color(0.94, 0.86, 0.7, 0.8))
			_star(at, 1.3)
			_shake = maxf(_shake, 1.6)
		"crumble":
			_burst(at, 5, 70.0, 380.0, 0.6, [Color(0.85, 0.8, 0.72), Color(0.6, 0.55, 0.5)], 0.9, "splinter")
			_dust(at, 3, 30.0, 1.0)
			_shake = maxf(_shake, 1.2)
		"poof":
			_burst(at, 4, 30.0, -20.0, 0.4, [Color(0.75, 0.78, 0.84, 0.8)], 0.7, "puff")
		"clang", "bonk":
			_star(at, 0.9, Color("fff3b0"))
			_burst(at, 5, 80.0, 200.0, 0.25, [Color("ffd75e"), Color("fff7e0")], 0.6)
		"stomp", "dizzy":
			_star(at, 0.9, Color("fff3b0"))
			_burst(at, 4, 50.0, 100.0, 0.3, [Color("ffe27a")], 0.6)
		"foe_out":
			_star(at, 1.7)
			_burst(at, 6, 110.0, 300.0, 0.6, [Color.WHITE], 0.9, "bolt")
			_burst(at, 4, 40.0, -20.0, 0.45, [Color(0.3, 0.3, 0.36, 0.7)], 0.8, "puff")
			_burst(at, 7, 110.0, 260.0, 0.45, [Color("fff7e0"), Color("ffd75e"), Color("ff8a3c")], 0.9)
			_shake = maxf(_shake, 2.4)
		"hurt":
			_star(at, 1.3, Color("ff8a8a"))
			_burst(at, 8, 90.0, 240.0, 0.4, [Color("e5484d"), Color("fff7e0")], 0.7)
			_shake = maxf(_shake, 3.0)
			_flash = maxf(_flash, 0.06)
		"bump":
			_star(at, 1.0, Color("fff3b0"))
		"die":
			_star(at, 1.8)
			_burst(at, 10, 120.0, 300.0, 0.8, [HERO_COLORS[int(event.get("slot", 0))], Color("fff7e0")], 1.0)
			_burst(at, 4, 40.0, -20.0, 0.6, [Color(0.3, 0.3, 0.36, 0.7)], 0.9, "puff")
			_shake = maxf(_shake, 4.0)
		"respawn", "spawn", "foe_pop":
			_burst(at, 10, 60.0, -60.0, 0.5, [Color("bff3ff"), Color("fff7e0")], 0.7)
		"acorn":
			_star(at, 0.6, Color("fff3b0"), 0.12)
			_burst(at, 4, 40.0, 0.0, 0.25, [Color("ffd75e")], 0.6)
		"bag", "heart", "flag":
			_star(at, 0.9, Color("d8ffc8"))
			_burst(at, 10, 60.0, -50.0, 0.55, [Color("b8ff9a"), Color("fff7e0"), Color("5fd4c4")], 0.7)
		"extra_life":
			_star(at, 2.2, Color("fff3b0"), 0.3)
			_burst(at, 18, 90.0, 60.0, 0.9, [Color("ffd75e"), Color("fff7e0"), Color("c9952c")], 0.9)
			_flash = maxf(_flash, 0.08)
			if _popups.size() < 12:
				_popups.append({"x": at.x, "y": at.y - 8.0, "text": "1UP", "life": 1.2})
		"burrow":
			_burst(at, 12, 70.0, 0.0, 0.5, [Color("fff3b0"), Color("d8ffc8")], 0.8)
		"secret":
			_call = Texts.of("secret", locale)
			_call_age = 0.0
			_flash = maxf(_flash, 0.1)
		"boss_rage":
			_call = Texts.of("phase", locale) % int(event.get("phase", 2))
			_call_age = 0.0
			_shake = maxf(_shake, 5.0)
			_flash = maxf(_flash, 0.12)
		"puff", "boss_spit", "boss_pop", "boss_throw", "boss_drop":
			_star(at, 0.7, Color("fff3b0"), 0.1)
			_burst(at, 5, 50.0, 0.0, 0.25, [Color("ffd75e"), Color("fff7e0")], 0.6, "puff")
		"boss_hit":
			_star(at, 2.2)
			_burst(at, 5, 130.0, 300.0, 0.6, [Color.WHITE], 1.0, "bolt")
			_burst(at, 12, 130.0, 260.0, 0.5, [Color("fff7e0"), Color("ffd75e"), Color("e5484d")], 1.0)
			_shake = maxf(_shake, 3.5)
			_flash = maxf(_flash, 0.07)
		"boss_slam", "boss_land":
			_dust(at, 10, 90.0, 1.2)
			_star(at, 1.4)
			_shake = maxf(_shake, 5.0)
		"boss_dive", "splat":
			_burst(at, 10, 70.0, 300.0, 0.5, [Color(0.6, 0.9, 0.8, 0.8)], 0.8)
		"boss_burst":
			_star(at, 1.8, Color("ffc27a"))
			_burst(at, 8, 110.0, 120.0, 0.55, [Color("ff8a3c"), Color("ffd75e"), Color("fff7e0")], 1.1)
			_shake = maxf(_shake, 3.0)
		"boss_down":
			_star(at, 4.5, Color.WHITE, 0.4)
			_burst(at, 18, 200.0, 320.0, 1.2, [Color.WHITE], 1.2, "bolt")
			_burst(at, 24, 190.0, 200.0, 1.1, [Color("ff8a3c"), Color("ffd75e"), Color("fff7e0")], 1.3)
			_shake = maxf(_shake, 9.0)
			_flash = maxf(_flash, 0.35)
		"level_clear":
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
	if world.phase == World.P_MAP or world.level.is_empty():
		_camera = Vector2.ZERO
		_draw_map()
		return
	_camera = world.camera + _offset
	_flashes.clear()
	_draw_backdrop()
	_home()
	_draw_decor(false)
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
	# A held thing is drawn with the squirrel that holds it.
	for object in world.objects:
		if int(object["state"]) == World.O_THROWN:
			_draw_object(object)
	for shot in world.shots:
		_draw_shot(shot)
	_draw_decor(true)
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
	if not _has(sheet, frame):
		return
	draw_set_transform(at - _camera, angle, scale)
	sheet.draw(self, frame, Vector2.ZERO, flipped, 1.0, 0.0, tint)
	_home()
	if hit:
		_flashes.append([sheet, frame, at - _camera, flipped, scale, angle, Vector2.ZERO])

## Draw a frame turned round its own middle, which is put at a world point.
func _spin(sheet: GameSprites, frame: String, middle: Vector2, angle: float, zoom: float = 1.0, tint: Color = Color.WHITE, flipped: bool = false, hit: bool = false) -> void:
	if not _has(sheet, frame):
		return
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

## The place behind the play: its far wall sliding slowly, the big things standing nearer sliding faster, then the dust in the air between.
func _draw_backdrop() -> void:
	var theme := world.theme
	var look: Dictionary = LOOKS[theme]
	var columns := float(world.level.get("main_w", world.width))
	var room := Vector2(maxf(1.0, columns * TILE - VIEW.x), maxf(1.0, float(world.height) * TILE - VIEW.y - 8.0))
	var tall := room.y > room.x
	var far: GameSprites = fars.get(theme)
	if far != null:
		if tall:
			# A climb: the far wall is one picture larger than the view that slides slowly past and never repeats.
			var big := VIEW * 1.5
			var spare := big - VIEW
			far.draw_fit(self, "main", Rect2(-Vector2(spare.x * clampf(_camera.x / room.x, 0.0, 1.0), spare.y * clampf(_camera.y / room.y, 0.0, 1.0)), big))
		else:
			var slack := FAR_SIZE - VIEW
			far.draw_tiled(self, "main", Rect2(Vector2.ZERO, VIEW), FAR_SIZE, Vector2(_camera.x * 0.2, slack.y * clampf(_camera.y / room.y, 0.0, 1.0)))
	else:
		_fade(Rect2(Vector2.ZERO, VIEW), (look["node"] as Color).darkened(0.7), (look["edge"] as Color))
	draw_rect(Rect2(Vector2.ZERO, VIEW), look["veil"])
	var mid: GameSprites = mids.get(theme)
	if mid != null:
		var size := mid.size("main")
		# The nearer row of big things: along the bottom of a crossing, repeated up the height of a climb.
		var y := VIEW.y - size.y + 26.0 - (_camera.y - room.y) * 0.5
		if tall:
			y = fposmod(-_camera.y * 0.5, size.y) - size.y
			while y < VIEW.y:
				mid.draw_tiled(self, "main", Rect2(0.0, y, VIEW.x, size.y), size, Vector2(_camera.x * 0.5, 0.0), Color(0.86, 0.86, 0.92))
				y += size.y
		else:
			mid.draw_tiled(self, "main", Rect2(0.0, y, VIEW.x, size.y), size, Vector2(_camera.x * 0.5, 0.0), Color(0.86, 0.86, 0.92))
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
	var theme := world.theme
	var look: Dictionary = LOOKS[theme]
	var fill: GameSprites = fills.get(theme)
	var cell := fill.texture.get_size() / float(FILL_CELLS) if fill != null and fill.texture != null else Vector2.ONE
	var shelf := "shelf_" + str(ART_NAMES[theme])
	var hazard := "hazard_" + str(ART_NAMES[theme])
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
				if _has(props, shelf):
					props.draw_fit(self, shelf, Rect2(x - 0.2, y - 0.5, TILE + 0.4, 7.5))
				else:
					draw_rect(Rect2(x, y, TILE, 5.0), look["cap"])
				continue
			if tile == Levels.HAZARD:
				var glow := 0.85 + 0.15 * sin(_clock * 6.0 + float(column))
				if _has(props, hazard):
					var size := props.size(hazard)
					props.draw_fit(self, hazard, Rect2(x - 0.3, y + TILE - size.y * TILE / maxf(1.0, size.x), TILE + 0.6, size.y * TILE / maxf(1.0, size.x)), Color(glow, glow, glow))
				else:
					draw_rect(Rect2(x, y + 9.0, TILE, 7.0), Color(1.0, 0.3, 0.2, glow))
				continue
			var open_above := row == 0 or not World.is_solid(world.tile_at(column, row - 1))
			# Ground gets darker the deeper it lies under its surface.
			var shade := Color.WHITE
			if not open_above and row > 1 and World.is_solid(world.tile_at(column, row - 2)):
				shade = Color(0.8, 0.8, 0.84) if row < 3 or not World.is_solid(world.tile_at(column, row - 3)) else Color(0.62, 0.62, 0.7)
			if fill != null and fill.texture != null:
				draw_texture_rect_region(fill.texture, Rect2(x, y, TILE, TILE), Rect2(Vector2(float(posmod(column, FILL_CELLS)), float(posmod(row, FILL_CELLS))) * cell, cell), shade)
			else:
				draw_rect(Rect2(x, y, TILE, TILE), (look["cap"] as Color).darkened(0.45) * shade)
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
			if open_above:
				draw_rect(Rect2(x, y, TILE, 3.0), look["cap"])
				draw_rect(Rect2(x, y, TILE, 0.9), look["lip"])
				draw_rect(Rect2(x, y + 3.0, TILE, 0.6), edge)
				_fade(Rect2(x, y + 3.6, TILE, 3.4), dark, clear)
			if tile == Levels.CRACK:
				# Cracked plaster: the crack is painted on, and the cell is a little paler, so it can be noticed by anyone who looks.
				draw_rect(Rect2(x, y, TILE, TILE), Color(1.0, 0.95, 0.85, 0.12 + 0.05 * sin(_clock * 2.0)))
				if _has(props, "crack"):
					props.draw_fit(self, "crack", Rect2(x, y, TILE, TILE))
				else:
					draw_polyline(PackedVector2Array([Vector2(x + 3, y + 2), Vector2(x + 8, y + 7), Vector2(x + 6, y + 11), Vector2(x + 12, y + 14)]), edge, 0.8, true)

## The painted big things of the place that nothing collides with: behind the play, or (`front`) over it.
func _draw_decor(front: bool) -> void:
	for item: Dictionary in world.level.get("decor", []):
		if bool(item["front"]) != front:
			continue
		var at: Vector2 = item["at"]
		var kind := str(item["kind"])
		if not world.is_seen(at.x, at.y, 120.0) or not _has(props, kind):
			continue
		_put(props, kind, at + Vector2(0.0, 1.0), false, Vector2.ONE, 0.0, Color(0.92, 0.9, 0.9, 0.85) if front else Color(0.88, 0.86, 0.9))

func _draw_fixtures() -> void:
	var exit: Variant = world.level.get("exit")
	if exit is Vector2:
		var at: Vector2 = exit
		var near := false
		for hero in world.heroes:
			if int(hero["state"]) == World.H_NORMAL and absf(float(hero["x"]) - at.x) < 48.0 and absf(float(hero["y"]) - at.y) < 40.0:
				near = true
		if near or world.phase == World.P_CLEAR:
			draw_circle(at + Vector2(0.0, -14.0), 20.0 + sin(_clock * 3.0) * 1.5, Color(1.0, 0.85, 0.5, 0.16), true, -1.0, true)
		if _has(props, "exit_open"):
			_put(props, "exit_open" if near or world.phase == World.P_CLEAR else "exit_closed", at + Vector2(0.0, 1.0))
		else:
			draw_rect(Rect2(at.x - 9.0, at.y - 28.0, 18.0, 28.0), Color("5a3a22"))
	for spawner in world.spawners:
		var at := Vector2(float(spawner["x"]), float(spawner["y"]))
		if _has(props, "hole"):
			_put(props, "hole", at + Vector2(0.0, 1.0), int(spawner["face"]) > 0)
		else:
			draw_circle(at + Vector2(0, -8), 8.0, Color(0.05, 0.03, 0.03))
	var warps: Array = world.level.get("warps", [])
	for warp: Dictionary in warps:
		var at: Vector2 = warp["at"]
		if not world.is_seen(at.x, at.y, 30.0):
			continue
		if _has(props, "burrow"):
			_put(props, "burrow", at + Vector2(0.0, 1.0))
		else:
			draw_circle(at + Vector2(0, -7), 7.0, Color(0.05, 0.03, 0.03))
		# The sparkle that gives a secret away to those who look.
		var twinkle := absf(sin(_clock * 3.0 + at.x * 0.1))
		_spin(props, "fx_star", at + Vector2(sin(_clock * 1.7) * 6.0, -14.0 + cos(_clock * 2.3) * 3.0), _clock * 2.0, 0.18 + 0.2 * twinkle, Color(1.0, 0.95, 0.7, 0.4 + 0.5 * twinkle))
	for index in world.flags.size():
		var flag: Vector2 = world.flags[index]
		var lit := index <= world.checkpoint
		_put(props, "flag_on" if lit else "flag_off", Vector2(flag.x + 3.0, flag.y), false, Vector2(1.0, 1.0 + (sin(_clock * 5.0 + flag.x) * 0.02 if lit else 0.0)))

## A moving platform: the place's shelf plank, hung or propped by what fits the place.
func _draw_lift(lift: Dictionary) -> void:
	var x := float(lift["x"])
	var y := float(lift["y"])
	var wide := float(lift["w"])
	var shelf := "shelf_" + str(ART_NAMES[world.theme])
	var edge: Color = LOOKS[world.theme]["edge"]
	# Two ropes up out of the picture.
	for side: float in [0.12, 0.88]:
		draw_line(Vector2(x + wide * side, y), Vector2(x + wide * side, _camera.y - 4.0), Color(edge.r, edge.g, edge.b, 0.7), 0.8, true)
	if _has(props, shelf):
		var cells := maxi(1, roundi(wide / TILE))
		for index in cells:
			props.draw_fit(self, shelf, Rect2(x + float(index) * TILE - 0.2, y - 0.5, TILE + 0.4, 7.5))
	else:
		draw_rect(Rect2(x, y, wide, 5.0), LOOKS[world.theme]["cap"])

func _draw_pickup(pickup: Dictionary) -> void:
	var x := float(pickup["x"])
	var y := float(pickup["y"])
	var kind := str(pickup["kind"])
	if bool(pickup["float"]):
		y += sin(_clock * 4.0 + x * 0.1) * 1.2
	var frame := str(PICKUP_FRAMES.get(kind, kind))
	match kind:
		"acorn":
			# An acorn turns on its edge like a coin.
			var turn := cos(_clock * 5.0 + x * 0.05)
			_put(props, frame, Vector2(x, y), false, Vector2(maxf(0.25, absf(turn)), 1.0) * 0.8)
		"golden":
			draw_circle(Vector2(x, y - 6.0), 9.0 + sin(_clock * 4.0) * 1.0, Color(1.0, 0.84, 0.37, 0.2), true, -1.0, true)
			_put(props, frame, Vector2(x, y), false, Vector2.ONE * (1.0 + sin(_clock * 6.0) * 0.05))
			_spin(props, "fx_star", Vector2(x + 4.0, y - 10.0), _clock * 2.0, 0.25 + 0.2 * absf(sin(_clock * 5.0)))
		_:
			draw_circle(Vector2(x, y - 5.0), 6.5, Color(1.0, 0.7, 0.7, 0.14) if kind == "heart" else Color(0.72, 1.0, 0.6, 0.12), true, -1.0, true)
			_put(props, frame, Vector2(x, y), false, Vector2.ONE * (1.0 + sin(_clock * 6.0 + x) * 0.05))

## A thing to lift, drawn with its bottom middle at a point: a prop, or a dizzy enemy upside down.
func _draw_thing(object: Dictionary, at: Vector2, angle: float, tint: Color) -> void:
	if str(object["kind"]) == "foe":
		var frame := str(object["foe"]) + "_0"
		if _has(foes, frame):
			var size := foes.size(frame)
			var zoom := float(FOE_ZOOM.get(str(object["foe"]), 1.0))
			_spin(foes, frame, at - Vector2(0.0, size.y * 0.5 * zoom), angle + PI, zoom, tint, int(object.get("face", 1)) < 0)
		return
	var kind := str(object["kind"])
	if not _has(props, kind):
		draw_rect(Rect2(at.x - float(object["half"]), at.y - float(object["tall"]), float(object["half"]) * 2.0, float(object["tall"])), Color("a0703c") * tint)
		return
	if angle == 0.0:
		_put(props, kind, at, false, Vector2.ONE, 0.0, tint)
	else:
		_spin(props, kind, at - Vector2(0.0, float(object["tall"]) * 0.5), angle, 1.0, tint)

## Something nobody holds: at rest or in flight. One that just left a squirrel's paws is drawn on its way from them to where the simulation has it. A boss's lump glows so it is clear what to throw.
func _draw_object(object: Dictionary) -> void:
	var shift := _drift_of(object)
	var x := float(object["x"]) + shift.x
	var y := float(object["y"]) + shift.y
	var tall := float(object["tall"])
	var tint := _fading(object)
	if bool(object["special"]):
		var pulse := 0.5 + 0.5 * sin(_clock * 7.0)
		draw_circle(Vector2(x, y - tall * 0.5), tall * 0.75 + pulse * 2.0, Color(1.0, 0.92, 0.5, 0.18 + 0.14 * pulse), true, -1.0, true)
	if int(object["state"]) == World.O_THROWN:
		var back := Vector2(float(object["vx"]), float(object["vy"])) * (0.02 if shift == Vector2.ZERO else 0.0)
		var angle := sin(_clock * 22.0) * 0.06
		for ghost in [2, 1]:
			_draw_thing(object, Vector2(x, y) - back * float(ghost), angle, Color(1.0, 1.0, 1.0, 0.22 / float(ghost)))
		_draw_thing(object, Vector2(x, y), angle, tint)
		return
	if shift == Vector2.ZERO:
		_shadow(x, y, float(object["half"]) + 1.0, 0.22)
	_draw_thing(object, Vector2(x, y), 0.0, tint)

## A boss's lump that is about to vanish blinks.
func _fading(object: Dictionary) -> Color:
	var life := float(object["life"])
	if life > 0.0 and life < 2.0:
		return Color(1.0, 1.0, 1.0, 0.35 + 0.5 * absf(sin(_clock * 18.0)))
	return Color.WHITE

## Where a falling shot will hit the floor below it, or a point far below when there is none.
func _landing(shot: Dictionary) -> Vector2:
	var x := float(shot["x"])
	var y := float(shot["y"])
	var vx := float(shot["vx"])
	var vy := float(shot["vy"])
	var g := float(shot["g"])
	for index in 90:
		var t := float(index) * 0.02
		var px := x + vx * t
		var py := y + vy * t + 0.5 * g * t * t
		if world.is_floor(px, py + 3.0):
			return Vector2(px, floorf((py + 3.0) / TILE) * TILE)
	return Vector2(x, 1e6)

func _draw_shot(shot: Dictionary) -> void:
	var at := Vector2(float(shot["x"]), float(shot["y"]))
	var time := float(shot["time"])
	var kind := str(shot["kind"])
	if World.THINGS.has(kind):
		# Where it will land is marked on the floor, growing as it comes.
		var land := _landing(shot)
		if land.y < 1e5:
			var near := clampf(1.0 - (land.y - at.y) / 200.0, 0.2, 1.0)
			draw_set_transform(land - _camera, 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, 5.0 + 5.0 * near, Color(0.9, 0.2, 0.1, 0.25 + 0.35 * near), true, -1.0, true)
			_home()
		if _has(props, kind):
			_spin(props, kind, at, time * 8.0)
		else:
			draw_circle(at, 6.0, Color("d0a060"))
		return
	match kind:
		"pepper":
			var grow := clampf(time / 0.3, 0.4, 1.0)
			_spin(props, "fx_puff", at, time * 3.0, 0.6 * grow, Color(0.55, 0.45, 0.35, 0.9))
			draw_circle(at + Vector2(sin(time * 20.0) * 2.0, 0.0), 1.2, Color(0.2, 0.15, 0.1, 0.9))
		"crumb":
			draw_circle(at, 4.0, Color(1.0, 0.5, 0.1, 0.25), true, -1.0, true)
			draw_circle(at, 2.2, Color("ff9a3c"), true, -1.0, true)
			draw_circle(at + Vector2(-0.6, -0.6), 0.9, Color("fff0a0"), true, -1.0, true)
		"bubble":
			draw_arc(at, 4.0 + sin(time * 6.0) * 0.4, 0.0, TAU, 20, Color(0.75, 1.0, 0.9, 0.9), 0.8, true)
			draw_circle(at + Vector2(-1.4, -1.4), 0.9, Color(1, 1, 1, 0.9), true, -1.0, true)
		"feather":
			var way := Vector2(float(shot["vx"]), float(shot["vy"])).normalized()
			var side := way.orthogonal()
			draw_colored_polygon(PackedVector2Array([at + way * 6.0, at + side * 1.8, at - way * 6.0, at - side * 1.8]), Color("2a2a3a"))
			draw_line(at - way * 6.0, at + way * 6.0, Color("8a8aa0"), 0.5, true)
		_:
			draw_circle(at, 3.0, Color("fff0a0"))

## Which frame of an enemy shows, and how it moves on its spot.
func _draw_foe(foe: Dictionary) -> void:
	var kind := str(foe["kind"])
	var x := float(foe["x"])
	var y := float(foe["y"])
	var time := float(foe["time"]) + float(int(x)) * 0.01
	var mode := str(foe["mode"])
	var tall := float(foe["tall"])
	var state := int(foe["state"])
	var frame := kind + "_%d" % (int(time * 7.0) % 2)
	var scale := Vector2.ONE
	var angle := 0.0
	var grounded := not bool(foe["flies"])
	var flip_v := false
	match kind:
		"ant", "rat", "worm", "mouse":
			var pace := 8.0 if kind != "worm" else 4.0
			if kind == "mouse" and mode == "dash":
				pace = 18.0
			frame = kind + "_%d" % (int(time * pace) % 2)
			if kind == "mouse" and mode == "wind":
				x += sin(time * 70.0) * 0.8
		"shaker":
			frame = "shaker_1" if mode == "aim" else "shaker_0"
			if mode == "aim":
				angle = float(int(foe["face"])) * 0.12 * sin(time * 40.0)
		"jack":
			frame = "jack_0" if mode == "box" else "jack_1"
			if mode != "box" and bool(foe["ground"]):
				var squash := sin(time * 12.0) * 0.06
				scale = Vector2(1.0 + squash, 1.0 - squash)
		"frog":
			frame = "frog_0" if bool(foe["ground"]) else "frog_1"
		"slime":
			frame = "slime_1" if mode == "drop" else "slime_%d" % (int(time * 3.0) % 2)
			if mode == "cling" or mode == "wobble":
				frame = "slime_0" if mode == "cling" else "slime_1"
				flip_v = true
				if mode == "wobble":
					x += sin(time * 60.0) * 0.7
		"fly", "hornet":
			frame = kind + "_%d" % (int(time * 24.0) % 2)
			if mode == "aim":
				x += sin(time * 80.0) * 0.8
		"plane":
			frame = "plane_%d" % (int(time * 16.0) % 2)
			angle = cos(time * 2.0) * 0.08
		"spider":
			var home: Vector2 = foe["home"]
			var anchor := Vector2(home.x, home.y - tall - 70.0)
			draw_line(anchor, Vector2(x, y - tall + 2.0), Color(0.92, 0.92, 0.96, 0.75), 0.5, true)
			frame = "spider_%d" % (int(time * 3.0) % 2)
	var flipped := int(foe["face"]) < 0
	var zoom := float(FOE_ZOOM.get(kind, 1.0))
	scale *= zoom
	if state == Foes.KNOCKED_OUT:
		if _has(foes, frame):
			_spin(foes, frame, Vector2(x, y - tall * 0.5), time * 12.0 * signf(float(foe["vx"])), zoom, Color.WHITE, flipped, float(foe["time"]) < 0.1)
		return
	if state == Foes.STUNNED:
		frame = kind + "_0"
		if kind == "jack":
			frame = "jack_1"
		angle = PI if bool(foe["flies"]) else sin(_clock * 9.0) * 0.15
	if grounded or state == Foes.STUNNED:
		_shadow(float(foe["x"]), float(foe["y"]), float(foe["half"]) + 1.0)
	var hit := float(foe["flash"]) > 0.0
	if not _has(foes, frame):
		draw_rect(Rect2(x - float(foe["half"]), y - tall, float(foe["half"]) * 2.0, tall), Color("c04060"))
	elif flip_v:
		_spin(foes, frame, Vector2(x, y - tall * 0.5), PI, zoom, Color.WHITE, not flipped, hit)
	elif angle != 0.0 and state == Foes.STUNNED and bool(foe["flies"]):
		_spin(foes, frame, Vector2(x, y - tall * 0.5), angle, zoom, Color.WHITE, flipped, hit)
	else:
		_put(foes, frame, Vector2(x, y), flipped, scale, angle, Color.WHITE, hit)
	if state == Foes.STUNNED or mode == "dizzy":
		for star in 3:
			var around := _clock * 7.0 + float(star) * TAU / 3.0
			_spin(props, "fx_star", Vector2(x + cos(around) * 7.0, float(foe["y"]) - tall - 4.0 + sin(around) * 2.0), _clock * 4.0, 0.3, Color("ffe27a"))

## The boss: its frame for what it is doing, the glow of a tell, and the marks that say where an attack will land.
func _draw_boss(boss: Dictionary) -> void:
	var mode := str(boss["mode"])
	if mode == "gone":
		return
	var kind := str(boss["kind"])
	var x := float(boss["x"])
	var y := float(boss["y"])
	var hurt := float(boss["flash"]) > 0.0 or mode == "dying" or mode == "rage"
	var white := float(boss["flash"]) > 0.15 or (mode == "dying" and int(_clock * 16.0) % 2 == 0)
	var face := float(int(boss["face"]))
	var scale := Vector2.ONE
	var angle := 0.0
	if float(boss.get("shake", 0.0)) > 0.0 or mode.ends_with("_tell"):
		x += sin(_clock * 110.0) * (1.4 if mode.ends_with("_tell") else 1.0)
	var frame := kind + "_idle"
	match kind:
		"toaster":
			match mode:
				"pop_tell", "crumb_tell":
					frame = "toaster_pop"
					scale = Vector2(1.0 - 0.05 * sin(_clock * 30.0), 1.0 + 0.05 * sin(_clock * 30.0))
				"hop_tell":
					frame = "toaster_crouch"
				"hop":
					frame = "toaster_idle"
					scale = Vector2(0.92, 1.1) if float(boss["vy"]) < 0.0 else Vector2(1.05, 0.96)
				"pause":
					frame = "toaster_pop"
				"walk":
					scale = Vector2(1.0, 1.0 + absf(sin(_clock * 9.0)) * 0.04)
		"robot":
			match mode:
				"throw_tell":
					frame = "robot_throw"
				"charge_tell", "charge":
					frame = "robot_charge"
				"dazed":
					frame = "robot_hurt"
					angle = sin(_clock * 8.0) * 0.06
				"walk":
					angle = sin(_clock * 6.0) * 0.04
		"crayfish":
			match mode:
				"snap_tell", "snap":
					frame = "crayfish_snap"
				"under":
					return
				"rise_tell":
					var pulse := 0.4 + 0.4 * absf(sin(_clock * 14.0))
					draw_set_transform(Vector2(x, Bosses.FLOOR) - _camera, 0.0, Vector2(1.0, 0.3))
					draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 40, Color(1.0, 0.3, 0.3, pulse), 1.6, true)
					_home()
					return
				"dive_tell":
					frame = "crayfish_dive"
				"rise":
					scale = Vector2(0.95, 1.08)
		"crow":
			frame = "crow_fly_%d" % (int(_clock * 9.0) % 2)
			match mode:
				"dive", "low":
					frame = "crow_dive"
				"perch":
					if (boss["goal"] as Vector2).distance_to(Vector2(x, y)) < 2.0:
						frame = "crow_perch"
				"dive_tell":
					var goal: Vector2 = boss["goal"]
					var pulse := 0.35 + 0.35 * absf(sin(_clock * 16.0))
					var from := Vector2(x, y - 14.0)
					var dash := 0.0
					var length := from.distance_to(goal)
					while dash < length:
						draw_line(from.lerp(goal, dash / length), from.lerp(goal, minf(1.0, (dash + 4.0) / length)), Color(1.0, 0.25, 0.25, pulse), 1.0, true)
						dash += 8.0
	if hurt:
		frame = kind + "_hurt"
	if mode.ends_with("_tell"):
		var pulse := 0.5 + 0.5 * sin(_clock * 18.0)
		draw_circle(Vector2(x, y - float(boss["tall"]) * 0.5), float(boss["half"]) + 8.0, Color(1.0, 0.45, 0.2, 0.12 + 0.12 * pulse), true, -1.0, true)
	if kind != "crow" or y > Bosses.FLOOR - 4.0:
		_shadow(x, Bosses.FLOOR, float(boss["half"]), 0.36)
	else:
		_shadow(x, Bosses.FLOOR, float(boss["half"]) * 0.6, 0.18)
	# Pictures face left; a boss facing right is drawn flipped.
	if _has(bosses, frame):
		_put(bosses, frame, Vector2(x, y + 1.0), (face > 0.0) != (frame in FACING_RIGHT), scale * BOSS_ZOOM, angle, Color.WHITE, white)
	else:
		draw_rect(Bosses.body(boss), Color("c04040"))

## The name of frame `index` of an action of a squirrel, wrapped round the action's length. An action without numbered frames is one picture of that name.
func _frame(slot: int, move: String, index: int) -> String:
	var count := int(_counts[slot].get(move, 0))
	return move if count <= 0 else "%s_%d" % [move, posmod(index, count)]

## The frame of an action that plays once, `progress` (0 .. 1) of the way through it.
func _shot(slot: int, move: String, progress: float) -> String:
	var count := int(_counts[slot].get(move, 0))
	return move if count <= 0 else "%s_%d" % [move, clampi(int(progress * float(count)), 0, count - 1)]

## An action that repeats with the clock: [the frame at `seconds`, the frame after it, how far the first has turned into the second (0 .. 1)]. Slow motions such as breathing are drawn as the first frame with the second faded in over it, so they flow instead of stepping.
func _cycle(slot: int, move: String, seconds: float) -> Array:
	var count := int(_counts[slot].get(move, 0))
	var length := heroes[slot].animation_length(move)
	if count <= 1 or length <= 0.0:
		return [_frame(slot, move, 0), "", 0.0]
	var at := fposmod(seconds / length, 1.0) * float(count)
	return [_frame(slot, move, int(at)), _frame(slot, move, int(at) + 1), at - floorf(at)]

## Which frame a squirrel shows and how it is squashed and tilted. It reads the simulation and the renderer's own short timers and changes nothing, so the frame under a carried crate is known before anything is drawn. Runs advance with the ground covered, actions that happen once with their timers, and standing still with the clock. Returns { "frame", "next", "mix", "at", "flip", "scale", "angle" }: "at" is where the frame's pivot (the feet) goes, "next" a frame to fade in over "frame" by "mix" (or "").
func _pose(hero: Dictionary) -> Dictionary:
	var slot := int(hero["slot"])
	var look: Dictionary = _looks[slot]
	var anim := float(hero["anim"])
	var carrying: bool = hero["carry"] != null or int(hero["lifting"]) >= 0
	var grounded := bool(hero["ground"])
	var running := grounded and absf(float(hero["vx"])) > 6.0
	var facing := float(int(hero["face"]))
	var flip := facing < 0.0
	var loop: Array = []
	var frame := ""
	var scale := Vector2.ONE
	var angle := 0.0
	if float(hero["stun"]) > 0.0:
		frame = _shot(slot, "hurt", 1.0 - float(hero["stun"]) / HURT_SPAN)
	elif bool(hero["hide"]):
		# Down under the crate, then peeking out from under it for as long as it stays there.
		var crouched := float(look["hide_time"])
		if crouched < DUCK_SPAN:
			frame = _shot(slot, "duck", crouched / DUCK_SPAN)
		else:
			loop = _cycle(slot, "hide", crouched - DUCK_SPAN)
	elif carrying and float(look["lift_time"]) > 0.0:
		frame = _shot(slot, "lift", 1.0 - float(look["lift_time"]) / LIFT_SPAN)
	elif float(look["pose_time"]) > 0.0 and not carrying:
		frame = _shot(slot, str(look["pose"]), 1.0 - float(look["pose_time"]) / THROW_SPAN)
	elif not grounded:
		var rise := float(hero["vy"])
		if carrying:
			frame = "carry_jump" if rise < 0.0 else "carry_fall"
		elif rise < 0.0:
			# The leap opens up as the rise slows, the fall as it quickens.
			frame = _shot(slot, "jump", 1.0 - clampf(-rise / World.JUMP_SPEED, 0.0, 1.0))
		else:
			frame = _shot(slot, "fall", rise / World.MAX_FALL)
		# Long and thin on the way up, a little wide when falling fast.
		var pull := clampf(absf(rise) / 300.0, 0.0, 1.0) * 0.05
		scale = Vector2(1.0 - pull, 1.0 + pull)
	elif carrying and float(look["rise"]) > 0.0:
		# Up from under the crate: the crouch played backwards.
		frame = _shot(slot, "duck", float(look["rise"]) / DUCK_SPAN * 0.999)
	elif running:
		var gait := _gait_of(hero)
		frame = _frame(slot, gait, int(fposmod(float(look["stride"]), 1.0) * float(int(_counts[slot].get(gait, 1)))))
	elif (world.phase == World.P_CLEAR or world.phase == World.P_WON) and not carrying:
		loop = _cycle(slot, "cheer", _clock + float(slot) * 0.21)
	elif float(look["land_time"]) > 0.0 and not carrying:
		frame = _shot(slot, "land", 1.0 - float(look["land_time"]) / LAND_SPAN)
	else:
		# Standing still it breathes, blinks and sways its tail; the two squirrels are never in step.
		loop = _cycle(slot, "carry" if carrying else "idle", anim + float(slot) * 0.7)
	if grounded:
		# The simulation changes speed at once; the body shows the effort: it leans into a start, back out of a stop, and comes round thin on its heel in a turn, facing the old way for the first half.
		var turn := float(look["turn"]) / TURN_SPAN
		var start := float(look["start"]) / START_SPAN
		var stop := float(look["stop"]) / STOP_SPAN
		if turn > 0.0:
			if turn > 0.5:
				flip = not flip
			scale.x *= 0.4 + 0.6 * absf(turn * 2.0 - 1.0)
			angle += facing * 0.2 * turn
		elif start > 0.0 and running:
			angle += facing * 0.15 * start * start
			scale *= Vector2(1.0 + 0.05 * start, 1.0 - 0.04 * start)
		elif stop > 0.0 and not running:
			angle -= facing * 0.12 * stop
			scale *= Vector2(1.0 + 0.05 * stop, 1.0 - 0.06 * stop)
	var squash := float(look["squash"]) / 0.14
	var stretch := float(look["stretch"]) / 0.16
	if squash > 0.0:
		scale *= Vector2(1.0 + 0.14 * squash, 1.0 - 0.14 * squash)
	elif stretch > 0.0:
		scale *= Vector2(1.0 - 0.1 * stretch, 1.0 + 0.12 * stretch)
	var shift := _drift_of(hero)
	var pose := {"frame": frame, "next": "", "mix": 0.0, "at": Vector2(float(hero["x"]) + shift.x, float(hero["y"]) + shift.y + 0.5), "flip": flip, "scale": scale, "angle": angle}
	if not loop.is_empty():
		pose["frame"] = loop[0]
		pose["next"] = loop[1]
		pose["mix"] = loop[2]
	return pose

## Where a frame of a squirrel has its paws, from its pivot, facing right.
func _hold_of(slot: int, frame: String) -> Vector2:
	return _holds[slot].get(frame, _holds[slot].get("carry_0", HOLD_DEFAULT))

## Where the bottom middle of what a squirrel carries is drawn: on the paws of the frame it shows, wherever the squash, the stride, the lean and the facing put them, so the load rides every frame of the motion. A load being picked up leaves the place it stood and is in the paws within the first part of the pick-up, then comes up with them; hidden under a crate, the crate comes down with the paws of the crouch.
func _held_spot(hero: Dictionary, pose: Dictionary) -> Vector2:
	var slot := int(hero["slot"])
	var look: Dictionary = _looks[slot]
	var hold := _hold_of(slot, str(pose["frame"]))
	if str(pose["next"]) != "":
		hold = hold.lerp(_hold_of(slot, str(pose["next"])), float(pose["mix"]))
	var spot: Vector2 = (pose["at"] as Vector2) + (Vector2(-hold.x if bool(pose["flip"]) else hold.x, hold.y) * (pose["scale"] as Vector2)).rotated(float(pose["angle"]))
	var left := float(look["lift_time"]) / LIFT_SPAN
	if left > 0.0:
		spot = (look["lift_from"] as Vector2).lerp(spot, smoothstep(0.0, GRIP, 1.0 - left))
	return spot

## What a squirrel holds, drawn on its paws: a crate, a lump of scrap or the partner.
func _draw_held(hero: Dictionary, spot: Vector2) -> void:
	var carried: Variant = hero["carry"]
	if carried is Dictionary:
		_draw_thing(carried, spot + Vector2(0.0, HOLD_SINK), 0.0, _fading(carried))
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
	_put(sheet, str(pose["frame"]), at, bool(pose["flip"]), pose["scale"], float(pose["angle"]), tint)
	if str(pose["next"]) != "" and float(pose["mix"]) > 0.0:
		_put(sheet, str(pose["next"]), at, bool(pose["flip"]), pose["scale"], float(pose["angle"]), Color(tint.r, tint.g, tint.b, tint.a * float(pose["mix"])))
	if hiding:
		_draw_held(hero, spot)
	if world.level_time < 4.0 and world.phase == World.P_PLAY:
		# Its name, and with two players a marker in its scarf colour, while the stage is new.
		var top := Vector2(x, y - (50.0 if hero["carry"] != null or int(hero["lifting"]) >= 0 else 31.0) + sin(_clock * 8.0) * 1.0)
		var fade := clampf(4.0 - world.level_time, 0.0, 1.0)
		# Side by side, the second name steps above the first.
		if slot == 1 and int(world.heroes[0]["state"]) == World.H_NORMAL and absf(float(world.heroes[0]["x"]) - x) < 26.0:
			top.y -= 9.0
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
			"bubble":
				draw_arc(at, size * 2.4, 0.0, TAU, 16, Color(color.r, color.g, color.b, color.a * left), 0.6, true)
			"bit":
				draw_set_transform(at - _camera, float(particle["turn"]), Vector2(1.0, absf(cos(float(particle["turn"]) * 0.7)) * 0.8 + 0.2))
				draw_rect(Rect2(-size * 0.5, -size * 0.3, size, size * 0.6), Color(color.r, color.g, color.b, minf(1.0, left * 4.0)))
				_home()
			_:
				draw_circle(at, size * (0.4 + 0.6 * left), Color(color.r, color.g, color.b, color.a * minf(1.0, left * 2.5)), true, -1.0, true)

## One sign at a time: the one nearest to a squirrel, and only while that squirrel stands by it.
func _draw_hint() -> void:
	if world.phase != World.P_PLAY:
		return
	var key := ""
	var hint_x := 0.0
	var distance := 48.0
	for hint: Dictionary in world.level.get("hints", []):
		var at: Vector2 = hint["at"]
		for hero in world.heroes:
			if int(hero["state"]) != World.H_OUT and absf(float(hero["x"]) - at.x) < distance and absf(float(hero["y"]) - at.y) < 48.0:
				distance = absf(float(hero["x"]) - at.x)
				key = str(hint["key"])
				hint_x = at.x
	if key == "":
		return
	var words := Texts.of(key, locale)
	var size := 8.0 if locale == "en" else 9.0
	var wide := text.measure(words, size, 700).x
	var middle := Vector2(clampf(hint_x, _camera.x + wide * 0.5 + 10.0, _camera.x + VIEW.x - wide * 0.5 - 10.0), _camera.y + 64.0 + sin(_clock * 2.5) * 1.0)
	draw_style_box(_plate, Rect2(middle.x - wide * 0.5 - 6.0, middle.y - size - 3.0, wide + 12.0, size + 8.0))
	text.draw(self, middle, words, size, Color("fff7e0"), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 700)

## Darker corners pull the eye to the middle of the stage.
func _draw_vignette() -> void:
	var dark := Color(0.03, 0.02, 0.07, 0.4)
	var clear := Color(0.03, 0.02, 0.07, 0.0)
	_fade(Rect2(0.0, 0.0, VIEW.x, 34.0), dark, clear)
	_fade(Rect2(0.0, VIEW.y - 22.0, VIEW.x, 22.0), clear, dark)
	_fade(Rect2(0.0, 0.0, 36.0, VIEW.y), Color(dark.r, dark.g, dark.b, 0.26), clear, false)
	_fade(Rect2(VIEW.x - 36.0, 0.0, 36.0, VIEW.y), clear, Color(dark.r, dark.g, dark.b, 0.26), false)

## Which banner is up, as one word; an empty string when none is.
func _banner_key() -> String:
	if world == null:
		return ""
	match world.phase:
		World.P_INTRO:
			return "boss" if not world.boss.is_empty() else "intro"
		World.P_CLEAR, World.P_WON:
			return "clear"
		World.P_RETRY:
			return "retry"
		World.P_OVER, World.P_LOST:
			return "lost"
	if not world.boss.is_empty() and str(world.boss["mode"]) == "enter":
		return "boss"
	return ""

func _draw_banners() -> void:
	match _band_key:
		"intro":
			_band(Texts.of(world.level_id, locale), Texts.of(world.theme, locale) + "  ·  " + Texts.of("level", locale) % clampi(world.route.size() + 1, 1, Levels.ROUTE_LENGTH), LOOKS[world.theme]["node"])
		"clear":
			_band(Texts.of("won" if world.level_id == Levels.FINAL else "clear", locale), "", Color("ffd75e"))
		"retry":
			_band(Texts.of("continue", locale) % maxi(0, world.continues_left - 1), "", Color("f5a340"))
		"lost":
			_band(Texts.of("lost", locale), "", Color("e5484d"))
		"boss":
			_band(Texts.of(world.level_id, locale), Texts.of("tip_" + world.level_id, locale), Color("e5484d"))
	if _call != "" and _call_age < 1.6:
		var show := clampf(minf(_call_age / 0.15, (1.6 - _call_age) / 0.3), 0.0, 1.0)
		var size := 14.0
		var wide := text.measure(_call, size, 800).x
		var middle := Vector2(VIEW.x * 0.5, 72.0 - (1.0 - show) * 8.0)
		draw_style_box(_plate, Rect2(middle.x - wide * 0.5 - 10.0, middle.y - size - 4.0, wide + 20.0, size + 11.0))
		text.draw(self, middle, _call, size, Color(1.0, 0.86, 0.4, show), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 800, 1.0, Color(0.1, 0.07, 0.14, show))

func _band(title: String, subtitle: String, accent: Color) -> void:
	# The band opens from its middle line and the title settles after it.
	var open := 1.0 - pow(1.0 - clampf(_band_age / 0.24, 0.0, 1.0), 3.0)
	var half := 27.0 * open
	var middle := 112.0
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
	var show := clampf((_band_age - 0.12) / 0.2, 0.0, 1.0)
	var slide := (1.0 - show) * 14.0
	var white := Color(1.0, 0.97, 0.88, show)
	var size := 20.0
	var wide := text.measure(title, size, 800).x
	var baseline := middle + (2.0 if subtitle != "" else 7.0)
	text.draw(self, Vector2(VIEW.x * 0.5 - slide, baseline), title, size, white, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 800, 1.2, Color(0.1, 0.07, 0.14, show))
	# An acorn turns at each end of the title.
	for side: float in [-1.0, 1.0]:
		draw_set_transform(Vector2(VIEW.x * 0.5 + side * (wide * 0.5 + 14.0) - slide, baseline - 7.0), sin(_clock * 3.0) * 0.3 * side, Vector2.ONE * 1.3)
		if _has(props, "acorn"):
			props.draw(self, "acorn", Vector2(0.0, props.size("acorn").y * 0.5), false, 1.0, 0.0, Color(1.0, 1.0, 1.0, show))
		draw_set_transform(Vector2.ZERO)
	if subtitle != "":
		text.draw(self, Vector2(VIEW.x * 0.5 + slide, middle + 18.0), subtitle, 9.0 if locale == "en" else 10.0, Color(accent.r, accent.g, accent.b, show), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 700, 0.8, Color(0.1, 0.07, 0.14, show))

# ---- the map ----

## The map between levels: the painted paper, the paths, a badge for every level (cleared, open or still closed), the squirrels on the marker and, at the bottom, the name of the level under it.
func _draw_map() -> void:
	if map_art != null:
		map_art.draw_fit(self, "main", Rect2(Vector2.ZERO, VIEW))
	else:
		_fade(Rect2(Vector2.ZERO, VIEW), Color("c9a878"), Color("8a6a48"))
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.05, 0.03, 0.02, 0.12))
	var open := world.map_choices()
	for id: String in Levels.NODES:
		var from: Vector2 = Levels.NODES[id]["at"]
		for next: String in Levels.NODES[id]["next"]:
			var to: Vector2 = Levels.NODES[next]["at"]
			var walked := world.cleared.has(next) and (world.cleared.has(id) or id == "home")
			var offered := id == world.node and next in open
			var color := Color(0.98, 0.84, 0.4, 0.95) if walked else (Color(1.0, 1.0, 0.95, 0.7 + 0.3 * sin(_clock * 5.0)) if offered else Color(0.3, 0.2, 0.12, 0.55))
			var length := from.distance_to(to)
			var dot := 0.0
			while dot < length:
				draw_circle(from.lerp(to, dot / length), 1.5 if walked or offered else 1.0, color, true, -1.0, true)
				dot += 5.0
	for id: String in Levels.NODES:
		var node: Dictionary = Levels.NODES[id]
		var at: Vector2 = node["at"]
		var theme := str(node["theme"])
		var tint: Color = LOOKS[theme]["node"] if theme != "" else Color("9b6a3c")
		var done := world.cleared.has(id) or id == "home"
		var offered := id in open
		var boss := str(node["kind"]) == "boss"
		var radius := 9.0 if boss else 6.5
		if offered:
			draw_circle(at, radius + 3.0 + sin(_clock * 6.0) * 1.0, Color(1.0, 0.95, 0.7, 0.35), true, -1.0, true)
		draw_circle(at + Vector2(0.0, 1.5), radius + 1.2, Color(0.1, 0.06, 0.04, 0.5), true, -1.0, true)
		draw_circle(at, radius + 1.0, Color("3a2416"), true, -1.0, true)
		draw_circle(at, radius, tint if done or offered else tint.darkened(0.55), true, -1.0, true)
		if boss and _has(bosses, theme_boss_frame(theme)):
			var frame := theme_boss_frame(theme)
			var size := bosses.size(frame)
			var zoom := (radius * 1.7) / maxf(size.x, size.y)
			bosses.draw(self, frame, at + Vector2(0.0, size.y * zoom * 0.5), false, zoom, 0.0, Color.WHITE if done or offered else Color(0.4, 0.4, 0.45))
		elif id == "home":
			_put(props, "acorn", at + Vector2(0.0, 4.0), false, Vector2.ONE * 0.9)
		if done and id != "home":
			draw_polyline(PackedVector2Array([at + Vector2(-3.0, 0.0), at + Vector2(-0.8, 2.6), at + Vector2(3.6, -3.0)]), Color.WHITE, 1.4, true)
	# The two squirrels stand on the marker.
	var marker := world.marker
	var shown := 0
	for hero in world.heroes:
		if bool(hero["active"]):
			shown += 1
	var place := 0
	for hero in world.heroes:
		if not bool(hero["active"]):
			continue
		var slot := int(hero["slot"])
		var side := 0.0 if shown == 1 else (-5.0 if place == 0 else 5.0)
		place += 1
		var moving := marker.distance_to(Levels.NODES[world.cursor]["at"]) > 0.5
		var hop := absf(sin(_clock * 12.0)) * 3.0 if moving else 0.0
		var frame: String = _frame(slot, "run", int(_clock * 12.0)) if moving else _cycle(slot, "idle", _clock + float(slot) * 0.7)[0]
		var facing := (Levels.NODES[world.cursor]["at"] as Vector2).x < marker.x
		_put(heroes[slot], frame, marker + Vector2(side, 2.0 - hop), facing, Vector2.ONE * 0.85)
	# The name of the level the marker points at.
	var shown_id := world.cursor
	var title := Texts.of(shown_id, locale)
	var theme_name := str(Levels.NODES[shown_id]["theme"])
	var sub := Texts.of(theme_name, locale) if theme_name != "" else ""
	var size := 11.0
	var line := (sub + "  ·  " if sub != "" else "") + Texts.of("map_pick" if open.size() > 1 else "map_go", locale)
	var wide := maxf(text.measure(title, size, 800).x, text.measure(line, 7.0, 600).x) + 4.0
	# A label beside the marker, above it in the lower half of the map and below it in the upper half, kept clear of the HUD.
	var at := marker + Vector2(0.0, -40.0 if marker.y > 110.0 else 14.0)
	var box := Rect2(clampf(at.x - wide * 0.5 - 10.0, 4.0, VIEW.x - wide - 24.0), clampf(at.y, 38.0, VIEW.y - 34.0), wide + 20.0, 30.0)
	draw_style_box(_plate, box)
	var middle := box.position.x + box.size.x * 0.5
	text.draw(self, Vector2(middle, box.position.y + 14.0), title, size, Color("fff7e0"), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 800)
	text.draw(self, Vector2(middle, box.position.y + 25.0), line, 7.0, Color(0.9, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 600)

static func theme_boss_frame(theme: String) -> String:
	return {"kitchen": "toaster_idle", "toyshop": "robot_idle", "sewer": "crayfish_idle", "treehouse": "crow_perch"}.get(theme, "")
