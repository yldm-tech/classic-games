extends RefCounted

## The simulation of Crate Crew: the stage's tiles, the two robots, everything that can be lifted and thrown, pick-ups, lifts, flags and the flow from stage to stage. It advances only through step(), reads nothing but the two GameInput objects it is handed and the seeded generator, and says what happened through `events`, which the entry script turns into sound and the renderer into particles. Enemies live in foes.gd and the bosses in bosses.gd; both work on this object.

const Levels := preload("res://games/crate_crew/levels.gd")
const Foes := preload("res://games/crate_crew/foes.gd")
const Bosses := preload("res://games/crate_crew/bosses.gd")

const TILE := 16.0
const VIEW := Vector2(384, 216)
const GRAVITY := 720.0
const MAX_FALL := 300.0
const RUN_SPEED := 80.0
const JUMP_SPEED := 262.0
const BELT_SPEED := 32.0
const HERO_HALF := 5.0
const HERO_TALL := 14.0
const THROW_SPEED := 230.0
const THROW_UP_SPEED := 380.0
## How far from the middle of the view things are still simulated.
const ACTIVE_X := 300.0
const ACTIVE_Y := 240.0

# move_box flags
const ON_GROUND := 1
const HIT_WALL := 2
const HIT_CEILING := 4

# hero states
const H_NORMAL := 0
const H_CARRIED := 1
const H_THROWN := 2
const H_DEAD := 3
const H_OUT := 4

# object states
const O_REST := 0
const O_HELD := 1
const O_THROWN := 2

# run phases
const P_INTRO := 0
const P_PLAY := 1
const P_CLEAR := 2
const P_RETRY := 3
const P_OVER := 4
const P_WON := 5
const P_LOST := 6

## What each difficulty changes: energy per life, lives, continues, enemy speed, boss health.
const DIFFICULTY := {
	1: {"energy": 4, "lives": 5, "continues": 3, "speed": 0.85, "boss": 0.75},
	2: {"energy": 3, "lives": 4, "continues": 2, "speed": 1.0, "boss": 1.0},
	3: {"energy": 3, "lives": 3, "continues": 1, "speed": 1.2, "boss": 1.3},
}

var rng: GameRng
var rules: Dictionary = DIFFICULTY[2]
var difficulty := 2

var stage := 0
var phase := P_INTRO
var phase_time := 0.0
var stage_time := 0.0
var checkpoint := -1

var width := 0
var height := 0
var tiles := PackedByteArray()
var level: Dictionary = {}

var heroes: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var foes: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var lifts: Array[Dictionary] = []
var chutes: Array[Dictionary] = []
var flags: Array = []
var boss: Dictionary = {}
var boss_fight := false
var door_open := false

var camera := Vector2.ZERO

var gears := 0
var golden_cogs := 0
## Stages whose golden cog has been found in this run: after a continue the same crate holds plain gears, so one stage cannot count twice.
var cog_stages: Dictionary = {}
var continues_left := 2
var continues_used := 0
var bosses_beaten := 0
var deaths := 0
var foes_beaten := 0
var buddy_hits := 0
var crates_broken := 0

## What happened during the last step: [{ "name", "x", "y", ... }]. The owner empties it.
var events: Array[Dictionary] = []

func _init(generator: GameRng, level_of_difficulty: int) -> void:
	rng = generator
	difficulty = clampi(level_of_difficulty, 1, 3)
	rules = DIFFICULTY[difficulty]
	continues_left = int(rules["continues"])
	for slot in 2:
		heroes.append(_new_hero(slot))

func _new_hero(slot: int) -> Dictionary:
	return {
		"slot": slot, "active": false, "state": H_OUT, "x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "face": 1, "ground": false,
		"energy": int(rules["energy"]), "lives": int(rules["lives"]), "score": 0, "carry": null, "lifting": -1, "rider_of": -1,
		"inv": 0.0, "stun": 0.0, "lift_time": 0.0, "coyote": 0.0, "buffer": 0.0, "drop": 0.0, "hide": false, "safe": Vector2.ZERO,
		"dead_time": 0.0, "off_time": 0.0, "stand": null, "anim": 0.0, "air_time": 0.0, "throw_time": 0.0, "by": -1, "left": false,
	}

func emit(name: String, x: float, y: float, extra: Dictionary = {}) -> void:
	var event := {"name": name, "x": x, "y": y}
	event.merge(extra)
	events.append(event)

# ---- stages ----

## Build a stage and put the playing robots at its start, or at the flag with this index.
func load_stage(index: int, from_flag: int = -1) -> void:
	stage = index
	level = Levels.new().build(index)
	width = int(level["w"])
	height = int(level["h"])
	tiles = level["tiles"]
	objects.clear()
	foes.clear()
	shots.clear()
	pickups.clear()
	lifts.clear()
	chutes.clear()
	flags = level["flags"]
	boss = {}
	boss_fight = false
	door_open = false
	checkpoint = from_flag if from_flag < flags.size() else -1
	stage_time = 0.0
	for spec: Dictionary in level["objects"]:
		var inside := str(spec["inside"])
		if inside == "cog" and cog_stages.has(index):
			inside = "gears"
		add_object(str(spec["kind"]), (spec["at"] as Vector2).x, (spec["at"] as Vector2).y, inside)
	for spec: Dictionary in level["foes"]:
		foes.append(Foes.create(spec))
	for spec: Dictionary in level["pickups"]:
		pickups.append({"kind": str(spec["kind"]), "x": (spec["at"] as Vector2).x, "y": (spec["at"] as Vector2).y, "vx": 0.0, "vy": 0.0, "float": true, "time": 0.0, "gone": false})
	for spec: Dictionary in level["lifts"]:
		var from: Vector2 = spec["from"]
		lifts.append({"from": from, "to": spec["to"], "w": float(spec["w"]), "period": float(spec["period"]), "x": from.x, "y": from.y, "dx": 0.0, "dy": 0.0})
	for at: Vector2 in level["chutes"]:
		chutes.append({"x": at.x, "y": at.y, "time": 1.0, "crate": null})
	var start: Vector2 = level["spawn"]
	if from_flag >= 0 and from_flag < flags.size():
		start = flags[from_flag]
	for hero in heroes:
		hero["carry"] = null
		hero["lifting"] = -1
		hero["rider_of"] = -1
		if not bool(hero["active"]):
			hero["state"] = H_OUT
			continue
		# A robot that ran out of lives gets one back for the new stage.
		if int(hero["lives"]) <= 0:
			hero["lives"] = 1
		_place_hero(hero, start.x + (10.0 if int(hero["slot"]) == 1 else -4.0), start.y)
		hero["energy"] = int(rules["energy"])
		hero["inv"] = 0.0
	camera = _camera_target()
	phase = P_INTRO
	phase_time = 1.6
	emit("stage_start", start.x, start.y)

func _place_hero(hero: Dictionary, x: float, y: float) -> void:
	hero["state"] = H_NORMAL
	hero["x"] = x
	hero["y"] = y
	hero["vx"] = 0.0
	hero["vy"] = 0.0
	hero["ground"] = true
	hero["stun"] = 0.0
	hero["lift_time"] = 0.0
	hero["hide"] = false
	hero["stand"] = null
	hero["off_time"] = 0.0
	hero["safe"] = Vector2(x, y)

## A player joined: their robot appears beside the partner.
func add_hero(slot: int) -> void:
	var hero := heroes[slot]
	hero["active"] = true
	# A robot that left and comes back keeps the lives it left with (at least one), so leaving and joining again is not a refill.
	hero["lives"] = maxi(1, int(hero["lives"])) if bool(hero["left"]) else int(rules["lives"])
	hero["energy"] = int(rules["energy"])
	var at: Vector2 = level.get("spawn", Vector2.ZERO)
	var partner := heroes[1 - slot]
	if int(partner["state"]) != H_OUT and int(partner["state"]) != H_DEAD:
		at = Vector2(float(partner["x"]), float(partner["y"]))
	elif int(partner["state"]) == H_DEAD or bool(partner["active"]):
		at = partner["safe"]
	_place_hero(hero, at.x, at.y)
	hero["inv"] = 2.0
	emit("respawn", at.x, at.y)

## A player left: their robot lets go of everything and disappears.
func remove_hero(slot: int) -> void:
	var hero := heroes[slot]
	_let_go(hero)
	if int(hero["rider_of"]) >= 0:
		heroes[int(hero["rider_of"])]["lifting"] = -1
		hero["rider_of"] = -1
	hero["active"] = false
	hero["state"] = H_OUT
	hero["left"] = true

func add_object(kind: String, x: float, y: float, inside: String = "") -> Dictionary:
	var small := kind == "scrap" or kind == "hexnut"
	var object := {
		"kind": kind, "x": x, "y": y, "vx": 0.0, "vy": 0.0, "state": O_REST, "inside": inside, "half": 6.0 if small else 8.0, "tall": 12.0 if small else 16.0,
		"by": -1, "combo": 0, "life": -1.0, "stand": null, "gone": false, "spin": 0.0, "buddy": false,
	}
	objects.append(object)
	return object

func add_shot(kind: String, x: float, y: float, vx: float, vy: float, gravity: float) -> void:
	shots.append({"kind": kind, "x": x, "y": y, "vx": vx, "vy": vy, "g": gravity, "time": 0.0, "gone": false})

func add_pickup(kind: String, x: float, y: float, vx: float, vy: float) -> void:
	pickups.append({"kind": kind, "x": x, "y": y, "vx": vx, "vy": vy, "float": false, "time": 0.0, "gone": false})

# ---- tiles ----

func tile_at(column: int, row: int) -> int:
	if column < 0 or column >= width:
		return Levels.SOLID
	if row < 0 or row >= height:
		return Levels.EMPTY
	return tiles[row * width + column]

func tile_at_point(x: float, y: float) -> int:
	return tile_at(floori(x / TILE), floori(y / TILE))

static func is_solid(tile: int) -> bool:
	return tile == Levels.SOLID or tile == Levels.BELT_LEFT or tile == Levels.BELT_RIGHT

## Whether something can stand at this point: solid ground or a shelf.
func is_floor(x: float, y: float) -> bool:
	var tile := tile_at_point(x, y)
	return is_solid(tile) or tile == Levels.SHELF

## Move a box (x in the middle, y at its bottom) by its velocity for one step and stop it at tiles. Shelves hold it only when it comes from above and `shelves` is true. Returns ON_GROUND / HIT_WALL / HIT_CEILING flags.
func move_box(body: Dictionary, half: float, tall: float, delta: float, shelves: bool, push_x: float = 0.0) -> int:
	var flags := 0
	var x := float(body["x"])
	var y := float(body["y"])
	var step_x := (float(body["vx"]) + push_x) * delta
	if step_x != 0.0:
		x += step_x
		var top_row := floori((y - tall) / TILE)
		var bottom_row := floori((y - 0.01) / TILE)
		var column := floori((x + half - 0.001) / TILE) if step_x > 0.0 else floori((x - half) / TILE)
		for row in range(top_row, bottom_row + 1):
			if is_solid(tile_at(column, row)):
				x = float(column) * TILE - half if step_x > 0.0 else float(column + 1) * TILE + half
				flags |= HIT_WALL
				break
	var previous := y
	var velocity_y := float(body["vy"])
	y += velocity_y * delta
	var first := floori((x - half) / TILE)
	var last := floori((x + half - 0.001) / TILE)
	if velocity_y >= 0.0:
		var row := floori(y / TILE)
		for column in range(first, last + 1):
			var tile := tile_at(column, row)
			if is_solid(tile) or (shelves and tile == Levels.SHELF and previous <= float(row) * TILE + 0.01):
				y = float(row) * TILE
				body["vy"] = 0.0
				flags |= ON_GROUND
				break
	else:
		var row := floori((y - tall) / TILE)
		for column in range(first, last + 1):
			if is_solid(tile_at(column, row)):
				y = float(row + 1) * TILE + tall
				body["vy"] = 0.0
				flags |= HIT_CEILING
				break
	body["x"] = x
	body["y"] = y
	return flags

## Let a falling box land on a lift or on a crate at rest. `previous` is where its bottom was before this step. Returns the thing it now stands on, or null.
func land_on_things(body: Dictionary, half: float, previous: float) -> Variant:
	if float(body["vy"]) < 0.0:
		return null
	var x := float(body["x"])
	var y := float(body["y"])
	for lift in lifts:
		var top := float(lift["y"])
		if x + half > float(lift["x"]) and x - half < float(lift["x"]) + float(lift["w"]) and previous <= top + 3.0 and y >= top - 0.01:
			body["y"] = top
			body["vy"] = 0.0
			return lift
	for object in objects:
		if int(object["state"]) != O_REST or is_same(object, body) or bool(object["gone"]):
			continue
		var top := float(object["y"]) - float(object["tall"])
		if absf(x - float(object["x"])) < half + float(object["half"]) - 1.0 and previous <= top + 3.0 and y >= top - 0.01:
			body["y"] = top
			body["vy"] = 0.0
			return object
	return null

func is_active_at(x: float, y: float) -> bool:
	return absf(x - (camera.x + VIEW.x * 0.5)) < ACTIVE_X and absf(y - (camera.y + VIEW.y * 0.5)) < ACTIVE_Y

## The robot nearest to a point among those an enemy can see, or an empty dictionary.
func nearest_hero(x: float, y: float) -> Dictionary:
	var best := {}
	var best_distance := 1e12
	for hero in heroes:
		if int(hero["state"]) == H_NORMAL or int(hero["state"]) == H_THROWN:
			var distance := Vector2(float(hero["x"]) - x, float(hero["y"]) - y).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = hero
	return best

## Whether a crate at rest stands at this point; enemies turn round at one.
func crate_at(x: float, y: float) -> bool:
	for object in objects:
		if int(object["state"]) == O_REST and absf(x - float(object["x"])) < float(object["half"]) and y <= float(object["y"]) and y >= float(object["y"]) - float(object["tall"]):
			return true
	return false

# ---- the step ----

func step(pads: Array, delta: float) -> void:
	if phase == P_WON or phase == P_LOST:
		return
	if phase != P_PLAY:
		phase_time -= delta
		if phase == P_INTRO:
			if phase_time <= 0.0:
				phase = P_PLAY
			return
		if phase == P_RETRY or phase == P_OVER:
			if phase_time <= 0.0:
				_after_wipe()
			return
		# P_CLEAR keeps the stage alive under the fanfare so nothing freezes in mid-air.
		if phase_time <= 0.0:
			if stage + 1 >= Levels.COUNT:
				phase = P_WON
			else:
				load_stage(stage + 1)
			return
	stage_time += delta
	_step_lifts()
	for hero in heroes:
		if bool(hero["active"]):
			_step_hero(hero, pads[int(hero["slot"])], delta)
	for hero in heroes:
		_follow_carrier(hero)
	_step_objects(delta)
	for foe in foes:
		if not bool(foe["gone"]) and (int(foe["state"]) != Foes.ALIVE or is_active_at(float(foe["x"]), float(foe["y"]))):
			Foes.step(self, foe, delta)
	Foes.step_shots(self, delta)
	if not boss.is_empty():
		Bosses.step(self, delta)
	_step_pickups(delta)
	_step_chutes(delta)
	_touch_things()
	_sweep()
	_step_camera()
	if phase == P_PLAY:
		_check_boss_start()
		_check_wipe()

func _step_lifts() -> void:
	for lift in lifts:
		var from: Vector2 = lift["from"]
		var to: Vector2 = lift["to"]
		var period := float(lift["period"])
		var along := fmod(stage_time, period) / period
		# There and back with a wait at each end, so there is time to step on and off.
		var eased := smoothstep(0.1, 0.4, along) - smoothstep(0.6, 0.9, along)
		var at := from.lerp(to, eased)
		lift["dx"] = at.x - float(lift["x"])
		lift["dy"] = at.y - float(lift["y"])
		lift["x"] = at.x
		lift["y"] = at.y

func _step_hero(hero: Dictionary, pad: GameInput, delta: float) -> void:
	var state := int(hero["state"])
	hero["anim"] = float(hero["anim"]) + delta
	hero["inv"] = maxf(0.0, float(hero["inv"]) - delta)
	if state == H_OUT:
		return
	if state == H_DEAD:
		hero["dead_time"] = float(hero["dead_time"]) - delta
		hero["vy"] = float(hero["vy"]) + GRAVITY * delta
		hero["y"] = float(hero["y"]) + float(hero["vy"]) * delta
		if float(hero["dead_time"]) <= 0.0:
			_respawn(hero)
		return
	if state == H_CARRIED:
		# A carried robot can only hop off.
		if pad.just_pressed(GameInput.A):
			var carrier := heroes[int(hero["rider_of"])]
			carrier["lifting"] = -1
			hero["rider_of"] = -1
			hero["state"] = H_NORMAL
			hero["vy"] = -JUMP_SPEED * 0.8
			hero["ground"] = false
			emit("jump", float(hero["x"]), float(hero["y"]))
		return
	hero["stun"] = maxf(0.0, float(hero["stun"]) - delta)
	hero["lift_time"] = maxf(0.0, float(hero["lift_time"]) - delta)
	hero["drop"] = maxf(0.0, float(hero["drop"]) - delta)
	hero["buffer"] = maxf(0.0, float(hero["buffer"]) - delta)
	hero["coyote"] = maxf(0.0, float(hero["coyote"]) - delta)
	# Ride whatever it stands on.
	var stand: Variant = hero["stand"]
	if stand is Dictionary:
		if (stand as Dictionary).has("period"):
			hero["x"] = float(hero["x"]) + float(stand["dx"])
			hero["y"] = float(hero["y"]) + float(stand["dy"])
		elif int((stand as Dictionary).get("state", O_HELD)) == O_REST:
			hero["y"] = float(stand["y"]) - float(stand["tall"])
	var thrown := state == H_THROWN
	var grounded := bool(hero["ground"])
	var busy := float(hero["stun"]) > 0.0 or float(hero["lift_time"]) > 0.0 or thrown
	var carrying := hero["carry"] != null
	var hiding := carrying and grounded and pad.is_down(GameInput.DOWN) and not busy
	hero["hide"] = hiding
	if thrown:
		hero["throw_time"] = float(hero["throw_time"]) + delta
	elif float(hero["stun"]) > 0.0:
		hero["vx"] = move_toward(float(hero["vx"]), 0.0, 300.0 * delta)
	elif hiding or float(hero["lift_time"]) > 0.0:
		hero["vx"] = 0.0
	else:
		var wanted := pad.move.x
		if absf(wanted) < 0.25:
			wanted = 0.0
		hero["vx"] = wanted * RUN_SPEED
		if wanted != 0.0:
			hero["face"] = 1 if wanted > 0.0 else -1
	if not busy and pad.just_pressed(GameInput.A):
		if pad.is_down(GameInput.DOWN) and grounded and not boss_fight and not carrying and tile_at_point(float(hero["x"]), float(hero["y"]) + 1.0) == Levels.SHELF:
			hero["drop"] = 0.22
			hero["ground"] = false
			grounded = false
		elif not hiding:
			hero["buffer"] = 0.12
	if float(hero["buffer"]) > 0.0 and (grounded or float(hero["coyote"]) > 0.0) and not busy and not hiding:
		hero["vy"] = -JUMP_SPEED
		hero["buffer"] = 0.0
		hero["coyote"] = 0.0
		hero["ground"] = false
		grounded = false
		emit("jump", float(hero["x"]), float(hero["y"]))
	if not thrown and not pad.is_down(GameInput.A) and float(hero["vy"]) < -110.0 and float(hero["stun"]) <= 0.0:
		hero["vy"] = -110.0
	hero["vy"] = minf(MAX_FALL, float(hero["vy"]) + GRAVITY * delta)
	var push := 0.0
	if grounded:
		var under := tile_at_point(float(hero["x"]), float(hero["y"]) + 1.0)
		if under == Levels.BELT_LEFT:
			push = -BELT_SPEED
		elif under == Levels.BELT_RIGHT:
			push = BELT_SPEED
	var previous := float(hero["y"])
	var flags := move_box(hero, HERO_HALF, HERO_TALL, delta, float(hero["drop"]) <= 0.0, push)
	hero["stand"] = null
	var landed := (flags & ON_GROUND) != 0
	if not landed and float(hero["drop"]) <= 0.0:
		var thing: Variant = land_on_things(hero, HERO_HALF, previous)
		if thing != null:
			hero["stand"] = thing
			landed = true
	if landed and not grounded and float(hero["air_time"]) > 0.25:
		emit("land", float(hero["x"]), float(hero["y"]))
	if landed:
		hero["air_time"] = 0.0
		hero["coyote"] = 0.09
		if (flags & ON_GROUND) != 0 and float(hero["stun"]) <= 0.0 and tile_at_point(float(hero["x"]), float(hero["y"]) - 1.0) != Levels.SPIKES:
			hero["safe"] = Vector2(float(hero["x"]), float(hero["y"]))
	else:
		hero["air_time"] = float(hero["air_time"]) + delta
	hero["ground"] = landed
	if thrown and (landed or (flags & HIT_WALL) != 0) and float(hero["throw_time"]) > 0.08:
		hero["state"] = H_NORMAL
		hero["vx"] = 0.0
		hero["inv"] = maxf(float(hero["inv"]), 0.4)
		emit("land", float(hero["x"]), float(hero["y"]))
	# With two robots nobody walks out of the picture.
	if _alive_count() > 1 or boss_fight:
		var left := camera.x + 6.0
		var right := camera.x + VIEW.x - 6.0
		if boss_fight:
			left = maxf(left, float(boss.get("left", left)) + HERO_HALF)
			right = minf(right, float(boss.get("right", right)) - HERO_HALF)
		hero["x"] = clampf(float(hero["x"]), left, right)
	if not busy and pad.just_pressed(GameInput.B):
		_press_grab(hero, pad, hiding)
	# Tacks and slag.
	if tile_at_point(float(hero["x"]), float(hero["y"]) - 2.0) == Levels.SPIKES and fmod(float(hero["y"]) - 2.0, TILE) > 6.0:
		hurt_hero(hero, float(hero["x"]) - float(int(hero["face"])), true)
	if float(hero["y"]) > float(height) * TILE + 48.0:
		_fell_out(hero)

func _follow_carrier(hero: Dictionary) -> void:
	if int(hero["state"]) == H_CARRIED:
		var carrier := heroes[int(hero["rider_of"])]
		hero["x"] = float(carrier["x"])
		hero["y"] = float(carrier["y"]) - HERO_TALL
		hero["face"] = int(carrier["face"])
		hero["vx"] = 0.0
		hero["vy"] = 0.0
	var carried: Variant = hero["carry"]
	if carried is Dictionary:
		carried["x"] = float(hero["x"])
		carried["y"] = float(hero["y"]) - (7.0 if bool(hero["hide"]) else HERO_TALL)

func _press_grab(hero: Dictionary, pad: GameInput, hiding: bool) -> void:
	var x := float(hero["x"])
	var y := float(hero["y"])
	var facing := int(hero["face"])
	var carried: Variant = hero["carry"]
	if carried is Dictionary:
		var object: Dictionary = carried
		hero["carry"] = null
		object["by"] = int(hero["slot"])
		object["combo"] = 0
		if hiding:
			_put_down(hero, object)
			return
		object["state"] = O_THROWN
		object["buddy"] = false
		if pad.is_down(GameInput.UP):
			object["vx"] = 0.0
			object["vy"] = -THROW_UP_SPEED
			object["g"] = GRAVITY
			emit("throw_up", x, y - HERO_TALL)
		else:
			# A sideways throw leaves at waist height, so it also meets the low machines on the floor.
			object["x"] = x + float(facing) * 4.0
			object["y"] = y - 4.0
			object["vx"] = float(facing) * THROW_SPEED
			object["vy"] = -30.0
			object["g"] = 80.0
			emit("throw", x, y - HERO_TALL)
		hero["lift_time"] = 0.1
		return
	if int(hero["lifting"]) >= 0:
		var partner := heroes[int(hero["lifting"])]
		hero["lifting"] = -1
		partner["rider_of"] = -1
		partner["state"] = H_THROWN
		partner["throw_time"] = 0.0
		partner["by"] = int(hero["slot"])
		partner["face"] = facing
		partner["ground"] = false
		if pad.is_down(GameInput.UP):
			partner["vx"] = float(facing) * 30.0
			partner["vy"] = -330.0
		else:
			partner["vx"] = float(facing) * 210.0
			partner["vy"] = -130.0
		emit("throw", x, y - HERO_TALL)
		hero["lift_time"] = 0.1
		return
	# Nothing in hand: look for a crate in front, then one under the feet, then the partner.
	var best: Variant = null
	var best_distance := 1e9
	for object in objects:
		if int(object["state"]) != O_REST or bool(object["gone"]):
			continue
		var dx := (float(object["x"]) - x) * float(facing)
		var reach := float(object["half"]) + 12.0
		if dx > -6.0 and dx < reach and float(object["y"]) > y - 20.0 and float(object["y"]) - float(object["tall"]) < y + 2.0 and absf(dx) < best_distance:
			best = object
			best_distance = absf(dx)
	if best == null and hero["stand"] is Dictionary and not (hero["stand"] as Dictionary).has("period"):
		best = hero["stand"]
	if best is Dictionary:
		var object: Dictionary = best
		object["state"] = O_HELD
		object["vx"] = 0.0
		object["vy"] = 0.0
		object["stand"] = null
		hero["carry"] = object
		hero["lift_time"] = 0.16
		hero["stand"] = null
		emit("lift", x, y)
		return
	var partner := heroes[1 - int(hero["slot"])]
	if int(partner["state"]) == H_NORMAL and partner["carry"] == null and int(partner["lifting"]) < 0 and float(partner["stun"]) <= 0.0:
		var dx := (float(partner["x"]) - x) * float(facing)
		if dx > -6.0 and dx < 18.0 and absf(float(partner["y"]) - y) < 14.0:
			partner["state"] = H_CARRIED
			partner["rider_of"] = int(hero["slot"])
			partner["hide"] = false
			hero["lifting"] = int(partner["slot"])
			hero["lift_time"] = 0.16
			emit("lift", x, y)

## Set a carried crate down in front of the robot, on top of a crate that is already there.
func _put_down(hero: Dictionary, object: Dictionary) -> void:
	var x := float(hero["x"]) + float(int(hero["face"])) * 14.0
	var y := float(hero["y"])
	if is_solid(tile_at_point(x - 7.0, y - 2.0)) or is_solid(tile_at_point(x + 7.0, y - 2.0)) or is_solid(tile_at_point(x, y - 14.0)):
		x = float(hero["x"])
	for other in objects:
		if int(other["state"]) == O_REST and not is_same(other, object) and absf(float(other["x"]) - x) < 14.0 and float(other["y"]) > y - 34.0 and float(other["y"]) - float(other["tall"]) < y + 2.0:
			x = float(other["x"])
			y = minf(y, float(other["y"]) - float(other["tall"]))
	object["state"] = O_REST
	object["x"] = x
	object["y"] = y
	object["vx"] = 0.0
	object["vy"] = 0.0
	hero["lift_time"] = 0.12
	emit("put_down", x, y)

## Drop whatever the robot carries, crate or partner.
func _let_go(hero: Dictionary) -> void:
	var carried: Variant = hero["carry"]
	if carried is Dictionary:
		carried["state"] = O_REST
		carried["vx"] = 0.0
		carried["vy"] = -60.0
		hero["carry"] = null
	if int(hero["lifting"]) >= 0:
		var partner := heroes[int(hero["lifting"])]
		partner["state"] = H_NORMAL
		partner["rider_of"] = -1
		partner["vy"] = -120.0
		partner["ground"] = false
		hero["lifting"] = -1
	hero["hide"] = false

## Take one unit of energy from a robot, unless it is flashing, hidden under a crate, carried or thrown. `forced` ignores the crate (tacks from below, a boss ramming).
func hurt_hero(hero: Dictionary, from_x: float, forced: bool = false) -> bool:
	if int(hero["state"]) != H_NORMAL or float(hero["inv"]) > 0.0 or phase != P_PLAY:
		return false
	if bool(hero["hide"]) and not forced:
		return false
	_let_go(hero)
	hero["energy"] = int(hero["energy"]) - 1
	hero["inv"] = 1.6
	hero["stun"] = 0.32
	hero["vx"] = (1.0 if float(hero["x"]) >= from_x else -1.0) * 95.0
	hero["vy"] = -150.0
	hero["ground"] = false
	emit("hurt", float(hero["x"]), float(hero["y"]) - 8.0, {"slot": int(hero["slot"])})
	if int(hero["energy"]) <= 0:
		_kill(hero)
	return true

func _kill(hero: Dictionary) -> void:
	_let_go(hero)
	hero["state"] = H_DEAD
	hero["dead_time"] = 1.5
	hero["vx"] = 0.0
	hero["vy"] = -220.0
	hero["lives"] = int(hero["lives"]) - 1
	hero["energy"] = 0
	deaths += 1
	emit("die", float(hero["x"]), float(hero["y"]) - 8.0, {"slot": int(hero["slot"])})

func _fell_out(hero: Dictionary) -> void:
	_let_go(hero)
	hero["energy"] = int(hero["energy"]) - 1
	emit("hurt", float(hero["x"]), float(height) * TILE - 8.0, {"slot": int(hero["slot"])})
	if int(hero["energy"]) <= 0:
		_kill(hero)
		hero["y"] = float(height) * TILE + 40.0
		return
	var back := _return_point(hero)
	_place_hero(hero, back.x, back.y)
	hero["safe"] = back
	hero["inv"] = 2.0

## Where a robot comes back: beside a living partner, else where it last stood safely.
func _return_point(hero: Dictionary) -> Vector2:
	var partner := heroes[1 - int(hero["slot"])]
	if int(partner["state"]) == H_NORMAL and bool(partner["ground"]):
		return Vector2(float(partner["x"]), float(partner["y"]))
	return hero["safe"]

func _respawn(hero: Dictionary) -> void:
	if int(hero["lives"]) <= 0:
		hero["state"] = H_OUT
		return
	var back := _return_point(hero)
	_place_hero(hero, back.x, back.y)
	hero["safe"] = back
	hero["energy"] = int(rules["energy"])
	hero["inv"] = 2.2
	emit("respawn", back.x, back.y - 8.0)

func _alive_count() -> int:
	var count := 0
	for hero in heroes:
		if int(hero["state"]) == H_NORMAL or int(hero["state"]) == H_CARRIED or int(hero["state"]) == H_THROWN:
			count += 1
	return count

# ---- crates and other things to throw ----

func _step_objects(delta: float) -> void:
	for object in objects:
		if bool(object["gone"]):
			continue
		var state := int(object["state"])
		if state == O_HELD:
			continue
		if not is_active_at(float(object["x"]), float(object["y"])):
			if state == O_THROWN:
				object["gone"] = true
			continue
		if state == O_REST:
			_step_resting(object, delta)
		else:
			_step_thrown(object, delta)

func _step_resting(object: Dictionary, delta: float) -> void:
	if float(object["life"]) > 0.0:
		object["life"] = float(object["life"]) - delta
		if float(object["life"]) <= 0.0:
			object["gone"] = true
			emit("poof", float(object["x"]), float(object["y"]) - 6.0)
			return
	var stand: Variant = object["stand"]
	if stand is Dictionary and (stand as Dictionary).has("period"):
		object["x"] = float(object["x"]) + float(stand["dx"])
		object["y"] = float(object["y"]) + float(stand["dy"])
	var push := 0.0
	var under := tile_at_point(float(object["x"]), float(object["y"]) + 1.0)
	if under == Levels.BELT_LEFT:
		push = -BELT_SPEED
	elif under == Levels.BELT_RIGHT:
		push = BELT_SPEED
	object["vx"] = move_toward(float(object["vx"]), 0.0, 400.0 * delta)
	object["vy"] = minf(MAX_FALL, float(object["vy"]) + GRAVITY * delta)
	var previous := float(object["y"])
	var flags := move_box(object, float(object["half"]), float(object["tall"]), delta, true, push)
	object["stand"] = null
	if (flags & ON_GROUND) == 0:
		object["stand"] = land_on_things(object, float(object["half"]), previous)
	if float(object["y"]) > float(height) * TILE + 64.0:
		object["gone"] = true

func _step_thrown(object: Dictionary, delta: float) -> void:
	object["spin"] = float(object["spin"]) + delta
	object["vy"] = minf(MAX_FALL + 80.0, float(object["vy"]) + float(object.get("g", GRAVITY)) * delta)
	var previous := float(object["y"])
	var flags := move_box(object, float(object["half"]) - 1.0, float(object["tall"]) - 2.0, delta, float(object["vy"]) > 0.0)
	if flags == 0 and float(object["vy"]) > 0.0 and land_on_things(object, float(object["half"]), previous) != null:
		flags = ON_GROUND
	var x := float(object["x"])
	var y := float(object["y"])
	var half := float(object["half"])
	var tall := float(object["tall"])
	# Enemy shots in the way are knocked out of the air.
	for shot in shots:
		if not bool(shot["gone"]) and absf(float(shot["x"]) - x) < half + 4.0 and float(shot["y"]) > y - tall - 4.0 and float(shot["y"]) < y + 4.0:
			shot["gone"] = true
			emit("clang", float(shot["x"]), float(shot["y"]))
	var direction := 1.0 if float(object["vx"]) >= 0.0 else -1.0
	var steel := str(object["kind"]) == "steel"
	for foe in foes:
		if int(foe["state"]) != Foes.ALIVE or bool(foe["gone"]):
			continue
		if absf(float(foe["x"]) - x) < half + float(foe["half"]) and float(foe["y"]) > y - tall and float(foe["y"]) - float(foe["tall"]) < y:
			if Foes.hit(self, foe, int(object["by"]), 2 if steel else 1, direction, int(object["combo"]), false):
				object["combo"] = int(object["combo"]) + 1
				if not steel:
					_break(object)
					return
	if not boss.is_empty():
		var result := Bosses.take_throw(self, x, y - tall * 0.5, half, tall * 0.5)
		if result != Bosses.MISS:
			if steel:
				object["state"] = O_REST
				object["vx"] = -direction * 60.0
				object["vy"] = -140.0
				emit("clang", x, y - 8.0)
			else:
				_break(object)
			return
	if flags != 0:
		if steel:
			object["state"] = O_REST
			if (flags & HIT_WALL) != 0:
				object["vx"] = -direction * 50.0
				object["vy"] = -90.0
			emit("clang", x, y - 8.0)
		else:
			_break(object)
		return
	if y > float(height) * TILE + 64.0:
		object["gone"] = true

## A wooden crate or a lump of scrap comes apart; whatever was inside pops out.
func _break(object: Dictionary) -> void:
	object["gone"] = true
	var x := float(object["x"])
	var y := float(object["y"]) - float(object["tall"]) * 0.5
	var kind := str(object["kind"])
	if kind != "wood":
		emit("poof", x, y, {"kind": kind})
		return
	crates_broken += 1
	emit("break", x, y)
	_award(int(object["by"]), 10, x, y, false)
	match str(object["inside"]):
		"gear":
			add_pickup("gear", x, y, 0.0, -150.0)
		"gears":
			for index in 3:
				add_pickup("gear", x, y, float(index - 1) * 42.0, -170.0 + absf(float(index - 1)) * 30.0)
		"battery":
			add_pickup("battery", x, y, 0.0, -150.0)
		"core":
			add_pickup("core", x, y, 0.0, -170.0)
		"cog":
			add_pickup("cog", x, y, 0.0, -190.0)

func _award(slot: int, points: int, x: float, y: float, show: bool = true) -> void:
	var receiver := slot
	if receiver < 0 or receiver > 1 or not bool(heroes[receiver]["active"]):
		receiver = 0 if bool(heroes[0]["active"]) else 1
	heroes[receiver]["score"] = int(heroes[receiver]["score"]) + points
	if show:
		emit("points", x, y, {"points": points})

## An enemy was knocked out by something `slot` threw; `chain` is how many this throw had already hit.
func foe_beaten(foe: Dictionary, slot: int, chain: int, by_buddy: bool) -> void:
	foes_beaten += 1
	if by_buddy:
		buddy_hits += 1
	_award(slot, int(foe["points"]) * (1 << mini(chain, 3)), float(foe["x"]), float(foe["y"]) - float(foe["tall"]))

func boss_beaten() -> void:
	bosses_beaten += 1
	for hero in heroes:
		if bool(hero["active"]):
			hero["score"] = int(hero["score"]) + 2000
	emit("points", float(boss["x"]), float(boss["y"]) - 40.0, {"points": 2000})
	_clear_stage()

func _clear_stage() -> void:
	if phase != P_PLAY:
		return
	phase = P_CLEAR
	phase_time = 3.2
	for hero in heroes:
		if bool(hero["active"]) and int(hero["state"]) != H_OUT:
			hero["score"] = int(hero["score"]) + 500
			hero["inv"] = 4.0
	for shot in shots:
		shot["gone"] = true
	emit("stage_clear", camera.x + VIEW.x * 0.5, camera.y + VIEW.y * 0.5)

# ---- pick-ups, chutes, flags, the door ----

func _step_pickups(delta: float) -> void:
	for pickup in pickups:
		if bool(pickup["gone"]):
			continue
		pickup["time"] = float(pickup["time"]) + delta
		if not bool(pickup["float"]):
			pickup["vy"] = minf(MAX_FALL, float(pickup["vy"]) + GRAVITY * delta)
			var flags := move_box(pickup, 4.0, 8.0, delta, true)
			if (flags & ON_GROUND) != 0:
				pickup["vx"] = 0.0
			if (flags & HIT_WALL) != 0:
				pickup["vx"] = -float(pickup["vx"]) * 0.5
			if float(pickup["y"]) > float(height) * TILE + 32.0:
				pickup["gone"] = true
				continue
		# A fresh pick-up cannot be taken for a moment, so the player sees what came out.
		if float(pickup["time"]) < 0.25 and not bool(pickup["float"]):
			continue
		for hero in heroes:
			var state := int(hero["state"])
			if state != H_NORMAL and state != H_THROWN and state != H_CARRIED:
				continue
			if absf(float(hero["x"]) - float(pickup["x"])) < 11.0 and float(pickup["y"]) > float(hero["y"]) - 20.0 and float(pickup["y"]) - 8.0 < float(hero["y"]) + 2.0:
				_collect(hero, pickup)
				break

func _collect(hero: Dictionary, pickup: Dictionary) -> void:
	pickup["gone"] = true
	var x := float(pickup["x"])
	var y := float(pickup["y"]) - 4.0
	var slot := int(hero["slot"])
	match str(pickup["kind"]):
		"gear":
			gears += 1
			_award(slot, 50, x, y, false)
			emit("gear", x, y)
		"battery":
			if int(hero["energy"]) < int(rules["energy"]):
				hero["energy"] = int(hero["energy"]) + 1
			else:
				_award(slot, 200, x, y)
			emit("battery", x, y)
		"core":
			hero["lives"] = int(hero["lives"]) + 1
			emit("core", x, y)
		"cog":
			golden_cogs += 1
			cog_stages[stage] = true
			_award(slot, 1000, x, y)
			emit("cog", x, y)

func _step_chutes(delta: float) -> void:
	for chute in chutes:
		if not is_active_at(float(chute["x"]), float(chute["y"])):
			continue
		var crate: Variant = chute["crate"]
		if crate is Dictionary and not bool(crate["gone"]):
			continue
		chute["time"] = float(chute["time"]) - delta
		if float(chute["time"]) > 0.0:
			continue
		chute["time"] = 2.6
		var inside := ""
		var roll := rng.unit()
		if roll < 0.12:
			inside = "battery"
		elif roll < 0.4:
			inside = "gear"
		chute["crate"] = add_object("wood", float(chute["x"]), float(chute["y"]) + 22.0, inside)
		emit("chute", float(chute["x"]), float(chute["y"]) + 12.0)

func _touch_things() -> void:
	for hero in heroes:
		if int(hero["state"]) != H_NORMAL:
			continue
		var x := float(hero["x"])
		var y := float(hero["y"])
		for index in flags.size():
			var flag: Vector2 = flags[index]
			if index > checkpoint and absf(flag.x - x) < 12.0 and absf(flag.y - y) < 24.0:
				checkpoint = index
				emit("flag", flag.x, flag.y - 12.0)
		var door: Variant = level["door"]
		if door is Vector2 and phase == P_PLAY and bool(hero["ground"]) and absf((door as Vector2).x - x) < 9.0 and absf((door as Vector2).y - y) < 6.0:
			door_open = true
			_clear_stage()

func _sweep() -> void:
	objects = objects.filter(func(object: Dictionary) -> bool: return not bool(object["gone"]))
	foes = foes.filter(func(foe: Dictionary) -> bool: return not bool(foe["gone"]))
	shots = shots.filter(func(shot: Dictionary) -> bool: return not bool(shot["gone"]))
	pickups = pickups.filter(func(pickup: Dictionary) -> bool: return not bool(pickup["gone"]))

# ---- camera, boss room, losing ----

func _camera_target() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for hero in heroes:
		var state := int(hero["state"])
		if state == H_NORMAL or state == H_THROWN:
			sum += Vector2(float(hero["x"]), float(hero["y"]))
			count += 1
	if count == 0:
		return camera
	var focus := sum / float(count)
	var target := Vector2(focus.x - VIEW.x * 0.5, focus.y - VIEW.y * 0.74)
	if boss_fight:
		return boss["camera"]
	target.x = clampf(target.x, 0.0, maxf(0.0, float(width) * TILE - VIEW.x))
	# The lowest rows are only there to be solid: the view stops a little above the bottom of the stage.
	target.y = clampf(target.y, 0.0, maxf(0.0, float(height) * TILE - VIEW.y - 24.0))
	return target

func _step_camera() -> void:
	var target := _camera_target()
	camera.x = move_toward(camera.x, target.x, maxf(1.0, absf(target.x - camera.x) * 0.14))
	camera.y = move_toward(camera.y, target.y, maxf(1.0, absf(target.y - camera.y) * 0.1))
	# A robot left far outside the picture is brought back to its partner.
	if _alive_count() < 2:
		return
	for hero in heroes:
		if int(hero["state"]) != H_NORMAL:
			continue
		var outside := float(hero["y"]) > camera.y + VIEW.y + 28.0 or float(hero["y"]) < camera.y - 28.0
		hero["off_time"] = float(hero["off_time"]) + 1.0 / 60.0 if outside else 0.0
		if float(hero["off_time"]) > 0.9:
			var partner := heroes[1 - int(hero["slot"])]
			if int(partner["state"]) == H_NORMAL:
				_let_go(hero)
				_place_hero(hero, float(partner["x"]), float(partner["y"]))
				hero["inv"] = 1.2
				emit("respawn", float(hero["x"]), float(hero["y"]) - 8.0)

func _check_boss_start() -> void:
	var spec: Dictionary = level["boss"]
	if spec.is_empty() or boss_fight or not boss.is_empty():
		return
	var floor_y := float(spec["floor"])
	for hero in heroes:
		if int(hero["state"]) == H_NORMAL and bool(hero["ground"]) and float(hero["y"]) <= floor_y + 0.5 and float(hero["y"]) > floor_y - 100.0 and float(hero["x"]) > float(spec["left"]) and float(hero["x"]) < float(spec["right"]):
			boss = Bosses.create(self, spec)
			boss_fight = true
			# The partner is pulled into the room so nobody is locked out.
			for other in heroes:
				if not is_same(other, hero) and (int(other["state"]) == H_NORMAL or int(other["state"]) == H_THROWN) and (float(other["y"]) > floor_y + 0.5 or float(other["x"]) > float(spec["right"])):
					_let_go(other)
					_place_hero(other, float(hero["x"]), float(hero["y"]))
			emit("boss_start", float(boss["x"]), float(boss["y"]))
			return

func _check_wipe() -> void:
	var anyone := false
	for hero in heroes:
		if bool(hero["active"]):
			anyone = true
			if int(hero["state"]) != H_OUT:
				return
	if not anyone:
		return
	if continues_left > 0:
		phase = P_RETRY
		phase_time = 2.4
		emit("continue", camera.x + VIEW.x * 0.5, camera.y + VIEW.y * 0.5)
	else:
		phase = P_OVER
		phase_time = 2.6
		emit("game_over", camera.x + VIEW.x * 0.5, camera.y + VIEW.y * 0.5)

func _after_wipe() -> void:
	if phase == P_OVER:
		phase = P_LOST
		return
	continues_left -= 1
	continues_used += 1
	for hero in heroes:
		if bool(hero["active"]):
			hero["lives"] = int(rules["lives"])
	load_stage(stage, checkpoint)
