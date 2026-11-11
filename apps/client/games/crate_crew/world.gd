extends RefCounted

## The simulation of Crate Crew: the map between levels, the level's tiles, the two squirrels, everything that can be lifted and thrown, pick-ups, moving platforms, flags, secret burrows and the flow from level to level. It advances only through step(), reads nothing but the two GameInput objects it is handed and the seeded generator, and says what happened through `events`, which the entry script turns into sound and the renderer into particles. Enemies live in foes.gd and the bosses in bosses.gd; both work on this object.

const Levels := preload("res://games/crate_crew/levels.gd")
const Foes := preload("res://games/crate_crew/foes.gd")
const Bosses := preload("res://games/crate_crew/bosses.gd")

const TILE := 16.0
const VIEW := Vector2(384, 216)

## How a squirrel moves, in stage pixels and seconds. Quick to full speed, quicker to stop and to turn, a short jump that falls faster than it rises, and full control the moment it lands.
const RUN_SPEED := 100.0
const CARRY_SPEED := 90.0
const ACCEL := 1500.0
const TURN := 3200.0
const DECEL := 2200.0
const AIR_ACCEL := 1200.0
const AIR_TURN := 2000.0
const AIR_DECEL := 500.0
const JUMP_SPEED := 312.0
const CARRY_JUMP := 0.95
## Gravity while the jump button is held on the way up, and otherwise.
const RISE_GRAVITY := 1150.0
const GRAVITY := 1600.0
## Letting go of jump on the way up cuts the rise to this speed.
const JUMP_CUT := 150.0
const MAX_FALL := 360.0
const COYOTE := 0.07
const BUFFER := 0.1

const HERO_HALF := 5.0
const HERO_TALL := 14.0

## Thrown things fly in a straight line at these speeds until they hit something.
const THROW_SPEED := 320.0
const THROW_UP_SPEED := 340.0
const THROW_DOWN_SPEED := 300.0
## A thrown partner flies straight this long, then falls.
const BUDDY_SPEED := 270.0
const BUDDY_FLIGHT := 0.4
const BUDDY_UP_SPEED := 400.0
## How long a squirrel is held up by lifting and by throwing.
const LIFT_TIME := 0.1
const THROW_TIME := 0.08
## What an enemy that runs into a hidden squirrel or is jumped on suffers.
const STUN_TIME := 1.8
const STOMP_STUN := 1.2

const ACORNS_PER_LIFE := 50
## How far from the middle of the view things are still simulated.
const ACTIVE_X := 320.0
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
const P_MAP := 0
const P_INTRO := 1
const P_PLAY := 2
const P_CLEAR := 3
const P_RETRY := 4
const P_OVER := 5
const P_WON := 6
const P_LOST := 7

## Everything that can be lifted: its half width and height, and whether it breaks when it hits something (else it drops and can be used again).
const THINGS := {
	"wood": {"half": 8.0, "tall": 16.0, "breaks": true},
	"steel": {"half": 8.0, "tall": 16.0, "breaks": false},
	"apple": {"half": 6.0, "tall": 13.0, "breaks": true},
	"can": {"half": 6.0, "tall": 15.0, "breaks": false},
	"block": {"half": 8.0, "tall": 16.0, "breaks": false},
	"nut": {"half": 6.0, "tall": 11.0, "breaks": false},
	"walnut": {"half": 6.0, "tall": 12.0, "breaks": true},
	"pinecone": {"half": 6.0, "tall": 15.0, "breaks": true},
	"toast": {"half": 7.0, "tall": 14.0, "breaks": true},
	"cog": {"half": 8.0, "tall": 16.0, "breaks": true},
	"foe": {"half": 7.0, "tall": 10.0, "breaks": true},
}

## What each difficulty changes: hearts per life, lives, continues, enemy speed, boss health per phase.
const DIFFICULTY := {
	1: {"hearts": 4, "lives": 5, "continues": 3, "speed": 0.85, "boss": 2},
	2: {"hearts": 3, "lives": 3, "continues": 2, "speed": 1.0, "boss": 2},
	3: {"hearts": 3, "lives": 2, "continues": 1, "speed": 1.2, "boss": 3},
}

var rng: GameRng
var rules: Dictionary = DIFFICULTY[2]
var difficulty := 2

var phase := P_MAP
var phase_time := 0.0
var level_time := 0.0
var checkpoint := -1

# ---- the map ----
## The node the squirrels stand on: the start or the last level cleared.
var node := "home"
## The node the marker is on or walking to, and where it is drawn.
var cursor := "home"
var marker := Vector2.ZERO
var cleared: Dictionary = {}
var route: Array[String] = []

# ---- the level ----
var level_id := ""
var level: Dictionary = {}
var theme := "kitchen"
var width := 0
var height := 0
var tiles := PackedByteArray()

var heroes: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var foes: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var lifts: Array[Dictionary] = []
var spawners: Array[Dictionary] = []
var flags: Array = []
var boss: Dictionary = {}

var camera := Vector2.ZERO

# ---- the run ----
var acorns := 0
var acorns_total := 0
var continues_left := 2
var continues_used := 0
var bosses_beaten := 0
var deaths := 0
var foes_beaten := 0
var buddy_hits := 0
var crates_broken := 0
var stacks := 0
## Bonus rooms found in this run, by level id and room index, so one room cannot count twice.
var secrets: Dictionary = {}

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
		"slot": slot, "active": false, "state": H_OUT, "x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "dx": 0.0, "dy": 0.0, "face": 1, "ground": false,
		"hearts": int(rules["hearts"]), "lives": int(rules["lives"]), "score": 0, "carry": null, "lifting": -1, "rider_of": -1,
		"inv": 0.0, "stun": 0.0, "busy": 0.0, "coyote": 0.0, "buffer": 0.0, "drop": 0.0, "hide": false, "jumping": false, "safe": Vector2.ZERO,
		"dead_time": 0.0, "off_time": 0.0, "stand": null, "anim": 0.0, "air_time": 0.0, "fly": 0.0, "throw_time": 0.0, "by": -1, "left": false,
	}

func emit(name: String, x: float, y: float, extra: Dictionary = {}) -> void:
	var event := {"name": name, "x": x, "y": y}
	event.merge(extra)
	events.append(event)

func active_heroes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hero in heroes:
		if bool(hero["active"]):
			out.append(hero)
	return out

# ---- the map ----

## Show the map with the marker on the node the squirrels stand on.
func open_map() -> void:
	phase = P_MAP
	phase_time = 0.0
	cursor = node
	marker = Levels.NODES[node]["at"]
	level_id = ""
	boss = {}
	emit("map", marker.x, marker.y)

## The nodes the players may walk the marker to from where it is: the next nodes of the node they stand on, and back.
func map_choices() -> Array[String]:
	var out: Array[String] = []
	for next: String in Levels.NODES[node]["next"]:
		out.append(next)
	return out

func _step_map(pads: Array, delta: float) -> void:
	var target: Vector2 = Levels.NODES[cursor]["at"]
	marker = marker.move_toward(target, 260.0 * delta)
	var arrived := marker.distance_to(target) < 0.5
	var choices := map_choices()
	for hero in heroes:
		if not bool(hero["active"]):
			continue
		var pad: GameInput = pads[int(hero["slot"])]
		var push := Vector2.ZERO
		if pad.just_pressed(GameInput.LEFT):
			push = Vector2.LEFT
		elif pad.just_pressed(GameInput.RIGHT):
			push = Vector2.RIGHT
		elif pad.just_pressed(GameInput.UP):
			push = Vector2.UP
		elif pad.just_pressed(GameInput.DOWN):
			push = Vector2.DOWN
		if push != Vector2.ZERO:
			var from: Vector2 = Levels.NODES[cursor]["at"]
			var best := ""
			var best_score := 0.3
			var candidates: Array[String] = choices.duplicate()
			candidates.append(node)
			for other in candidates:
				if other == cursor:
					continue
				var way: Vector2 = (Levels.NODES[other]["at"] as Vector2) - from
				var score := way.normalized().dot(push)
				if score > best_score:
					best_score = score
					best = other
			if best != "":
				cursor = best
				emit("map_move", marker.x, marker.y)
		if pad.just_pressed(GameInput.A) or pad.just_pressed(GameInput.B):
			if cursor == node and choices.size() == 1:
				cursor = choices[0]
				emit("map_move", marker.x, marker.y)
			elif cursor != node and arrived:
				emit("map_pick", marker.x, marker.y)
				start_level(cursor)
				return
	# A single way on: the marker walks there by itself once picked, and the level starts when it arrives.
	if cursor != node and arrived and choices.size() == 1 and cursor == choices[0]:
		emit("map_pick", marker.x, marker.y)
		start_level(cursor)

# ---- levels ----

## Build a level and put the playing squirrels at its start, or at the flag with this index.
func start_level(id: String, from_flag: int = -1) -> void:
	level_id = id
	level = Levels.build(id)
	theme = str(level["theme"])
	width = int(level["w"])
	height = int(level["h"])
	tiles = (level["tiles"] as PackedByteArray).duplicate()
	objects.clear()
	foes.clear()
	shots.clear()
	pickups.clear()
	lifts.clear()
	spawners.clear()
	flags = level["flags"]
	boss = {}
	checkpoint = from_flag if from_flag < flags.size() else -1
	level_time = 0.0
	for spec: Dictionary in level["objects"]:
		add_object(str(spec["kind"]), (spec["at"] as Vector2).x, (spec["at"] as Vector2).y, str(spec["inside"]))
	for spec: Dictionary in level["foes"]:
		foes.append(Foes.create(spec))
	for spec: Dictionary in level["spawners"]:
		var at: Vector2 = spec["at"]
		spawners.append({"kind": str(spec["kind"]), "x": at.x, "y": at.y, "face": int(spec["face"]), "every": float(spec["every"]), "most": int(spec["most"]), "time": float(spec["every"]) * 0.5, "made": []})
	for spec: Dictionary in level["pickups"]:
		var at: Vector2 = spec["at"]
		pickups.append({"kind": str(spec["kind"]), "x": at.x, "y": at.y, "vx": 0.0, "vy": 0.0, "float": true, "time": 0.0, "gone": false})
	for spec: Dictionary in level["lifts"]:
		var from: Vector2 = spec["from"]
		lifts.append({"from": from, "to": spec["to"], "w": float(spec["w"]), "period": float(spec["period"]), "x": from.x, "y": from.y, "dx": 0.0, "dy": 0.0})
	var start: Vector2 = level["spawn"]
	if checkpoint >= 0:
		start = flags[checkpoint]
	for hero in heroes:
		hero["carry"] = null
		hero["lifting"] = -1
		hero["rider_of"] = -1
		if not bool(hero["active"]):
			hero["state"] = H_OUT
			continue
		# A squirrel that ran out of lives gets one back for the new level, so a partner is never left out for long.
		if int(hero["lives"]) <= 0:
			hero["lives"] = 1
		_place_hero(hero, start.x + (10.0 if int(hero["slot"]) == 1 else -4.0), start.y)
		hero["hearts"] = int(rules["hearts"])
		hero["inv"] = 0.0
	if not (level["boss"] as Dictionary).is_empty():
		boss = Bosses.create(self, level["boss"])
	camera = _camera_target()
	phase = P_INTRO
	phase_time = 1.3
	emit("level_start", start.x, start.y, {"theme": theme, "boss": not boss.is_empty()})

func _place_hero(hero: Dictionary, x: float, y: float) -> void:
	hero["state"] = H_NORMAL
	hero["x"] = x
	hero["y"] = y
	hero["vx"] = 0.0
	hero["vy"] = 0.0
	hero["ground"] = true
	hero["stun"] = 0.0
	hero["busy"] = 0.0
	hero["hide"] = false
	hero["jumping"] = false
	hero["stand"] = null
	hero["off_time"] = 0.0
	hero["fly"] = 0.0
	hero["safe"] = Vector2(x, y)

## A player joined: their squirrel appears beside the partner.
func add_hero(slot: int) -> void:
	var hero := heroes[slot]
	hero["active"] = true
	# A squirrel that left and comes back keeps the lives it left with (at least one), so leaving and joining again is not a refill.
	hero["lives"] = maxi(1, int(hero["lives"])) if bool(hero["left"]) else int(rules["lives"])
	hero["hearts"] = int(rules["hearts"])
	if phase == P_MAP or level.is_empty():
		hero["state"] = H_OUT
		return
	var at: Vector2 = level.get("spawn", Vector2.ZERO)
	var partner := heroes[1 - slot]
	if int(partner["state"]) == H_NORMAL or int(partner["state"]) == H_THROWN or int(partner["state"]) == H_CARRIED:
		at = Vector2(float(partner["x"]), float(partner["y"]))
	elif bool(partner["active"]):
		at = partner["safe"]
	_place_hero(hero, at.x, at.y)
	hero["inv"] = 2.0
	emit("respawn", at.x, at.y)

## A player left: their squirrel lets go of everything and disappears.
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
	var data: Dictionary = THINGS.get(kind, THINGS["wood"])
	var object := {
		"kind": kind, "x": x, "y": y, "vx": 0.0, "vy": 0.0, "state": O_REST, "inside": inside, "half": float(data["half"]), "tall": float(data["tall"]),
		"breaks": bool(data["breaks"]), "by": -1, "life": -1.0, "stand": null, "gone": false, "spin": 0.0, "special": false, "foe": "", "travel": 0.0,
	}
	objects.append(object)
	return object

func add_shot(kind: String, x: float, y: float, vx: float, vy: float, gravity: float) -> Dictionary:
	var shot := {"kind": kind, "x": x, "y": y, "vx": vx, "vy": vy, "g": gravity, "time": 0.0, "gone": false}
	shots.append(shot)
	return shot

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
	return tile == Levels.SOLID or tile == Levels.CRACK

## Whether something can stand at this point: solid ground or a shelf.
func is_floor(x: float, y: float) -> bool:
	var tile := tile_at_point(x, y)
	return is_solid(tile) or tile == Levels.SHELF

## Move a box (x in the middle, y at its bottom) by its velocity for one step and stop it at tiles. Shelves hold it only when it comes from above and `shelves` is true. Returns ON_GROUND / HIT_WALL / HIT_CEILING flags; "wall_x" and "wall_y" on the body say which cell was hit last.
func move_box(body: Dictionary, half: float, tall: float, delta: float, shelves: bool, push_x: float = 0.0) -> int:
	var hits := 0
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
				hits |= HIT_WALL
				body["wall"] = Vector2i(column, row)
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
				hits |= ON_GROUND
				break
	else:
		var row := floori((y - tall) / TILE)
		for column in range(first, last + 1):
			if is_solid(tile_at(column, row)):
				y = float(row + 1) * TILE + tall
				body["vy"] = 0.0
				hits |= HIT_CEILING
				body["wall"] = Vector2i(column, row)
				break
	body["x"] = x
	body["y"] = y
	return hits

## Let a falling box land on a lift, a resting thing or (for squirrels) the partner's head. `previous` is where its bottom was before this step. Returns the thing it now stands on, or null.
func land_on_things(body: Dictionary, half: float, previous: float, on_heroes: bool = false) -> Variant:
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
	if on_heroes:
		for hero in heroes:
			if is_same(hero, body) or int(hero["state"]) != H_NORMAL:
				continue
			var top := float(hero["y"]) - HERO_TALL
			if absf(x - float(hero["x"])) < half + HERO_HALF - 1.0 and previous <= top + 3.0 and y >= top - 0.01:
				body["y"] = top
				body["vy"] = 0.0
				return hero
	return null

func is_active_at(x: float, y: float) -> bool:
	return absf(x - (camera.x + VIEW.x * 0.5)) < ACTIVE_X and absf(y - (camera.y + VIEW.y * 0.5)) < ACTIVE_Y

## Whether a point is inside the view, with a margin.
func is_seen(x: float, y: float, margin: float = 24.0) -> bool:
	return x > camera.x - margin and x < camera.x + VIEW.x + margin and y > camera.y - margin and y < camera.y + VIEW.y + margin

## The squirrel nearest to a point among those an enemy can see, or an empty dictionary.
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

## The resting thing whose box holds this point, or null; enemies turn round at one.
func thing_at(x: float, y: float) -> Variant:
	for object in objects:
		if int(object["state"]) == O_REST and not bool(object["gone"]) and absf(x - float(object["x"])) < float(object["half"]) and y <= float(object["y"]) and y >= float(object["y"]) - float(object["tall"]):
			return object
	return null

# ---- the step ----

func step(pads: Array, delta: float) -> void:
	if phase == P_WON or phase == P_LOST:
		return
	if phase == P_MAP:
		_step_map(pads, delta)
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
		# P_CLEAR keeps the level alive under the fanfare so nothing freezes in mid-air.
		if phase_time <= 0.0:
			_after_clear()
			return
	level_time += delta
	_step_lifts()
	for hero in heroes:
		if bool(hero["active"]):
			_step_hero(hero, pads[int(hero["slot"])], delta)
	_separate_heroes()
	for hero in heroes:
		_follow_carrier(hero)
	_step_objects(delta)
	_step_spawners(delta)
	for foe in foes:
		if not bool(foe["gone"]) and (int(foe["state"]) == Foes.KNOCKED_OUT or is_active_at(float(foe["x"]), float(foe["y"]))):
			Foes.step(self, foe, delta)
	Foes.step_shots(self, delta)
	if not boss.is_empty():
		Bosses.step(self, delta)
	_step_pickups(delta)
	_touch_things(pads)
	_sweep()
	_step_camera(delta)
	if phase == P_PLAY:
		_check_wipe()

func _step_lifts() -> void:
	for lift in lifts:
		var from: Vector2 = lift["from"]
		var to: Vector2 = lift["to"]
		var period := float(lift["period"])
		var along := fmod(level_time, period) / period
		# There and back with a wait at each end, so there is time to step on and off.
		var eased := smoothstep(0.1, 0.4, along) - smoothstep(0.6, 0.9, along)
		var at := from.lerp(to, eased)
		lift["dx"] = at.x - float(lift["x"])
		lift["dy"] = at.y - float(lift["y"])
		lift["x"] = at.x
		lift["y"] = at.y

func _step_hero(hero: Dictionary, pad: GameInput, delta: float) -> void:
	var state := int(hero["state"])
	var before := Vector2(float(hero["x"]), float(hero["y"]))
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
		# A carried squirrel can only hop off.
		if pad.just_pressed(GameInput.A):
			var carrier := heroes[int(hero["rider_of"])]
			carrier["lifting"] = -1
			hero["rider_of"] = -1
			hero["state"] = H_NORMAL
			hero["vy"] = -JUMP_SPEED * 0.85
			hero["jumping"] = true
			hero["ground"] = false
			emit("jump", float(hero["x"]), float(hero["y"]))
		return
	hero["stun"] = maxf(0.0, float(hero["stun"]) - delta)
	hero["busy"] = maxf(0.0, float(hero["busy"]) - delta)
	hero["drop"] = maxf(0.0, float(hero["drop"]) - delta)
	hero["buffer"] = maxf(0.0, float(hero["buffer"]) - delta)
	hero["coyote"] = maxf(0.0, float(hero["coyote"]) - delta)
	# Ride whatever it stands on.
	var stand: Variant = hero["stand"]
	if stand is Dictionary:
		var under: Dictionary = stand
		if under.has("period") or under.has("slot"):
			hero["x"] = float(hero["x"]) + float(under["dx"])
			hero["y"] = float(hero["y"]) + float(under["dy"])
		elif int(under.get("state", O_HELD)) == O_REST and not bool(under.get("gone", false)):
			hero["y"] = float(under["y"]) - float(under["tall"])
	var thrown := state == H_THROWN
	var grounded := bool(hero["ground"])
	var stunned := float(hero["stun"]) > 0.0
	var busy := stunned or float(hero["busy"]) > 0.0 or thrown
	var carrying := hero["carry"] != null or int(hero["lifting"]) >= 0
	var hiding := hero["carry"] != null and grounded and pad.is_down(GameInput.DOWN) and not busy and not pad.just_pressed(GameInput.B)
	hero["hide"] = hiding
	if thrown:
		hero["throw_time"] = float(hero["throw_time"]) + delta
		hero["fly"] = maxf(0.0, float(hero["fly"]) - delta)
	elif stunned:
		hero["vx"] = move_toward(float(hero["vx"]), 0.0, 400.0 * delta)
	elif hiding:
		hero["vx"] = move_toward(float(hero["vx"]), 0.0, DECEL * delta)
	else:
		var wanted := pad.move.x
		if absf(wanted) < 0.25:
			wanted = 0.0
		var top := (CARRY_SPEED if carrying else RUN_SPEED) * clampf(absf(wanted) * 1.25, 0.0, 1.0) * signf(wanted)
		var vx := float(hero["vx"])
		if wanted != 0.0:
			var rate := ACCEL if grounded else AIR_ACCEL
			if vx * wanted < 0.0:
				rate = TURN if grounded else AIR_TURN
			hero["vx"] = move_toward(vx, top, rate * delta)
			hero["face"] = 1 if wanted > 0.0 else -1
		else:
			hero["vx"] = move_toward(vx, 0.0, (DECEL if grounded else AIR_DECEL) * delta)
	if not busy and pad.just_pressed(GameInput.A):
		if pad.is_down(GameInput.DOWN) and grounded and _standing_on_shelf(hero):
			hero["drop"] = 0.2
			hero["ground"] = false
			hero["stand"] = null
			grounded = false
		elif not hiding:
			hero["buffer"] = BUFFER
	if float(hero["buffer"]) > 0.0 and (grounded or float(hero["coyote"]) > 0.0) and not busy and not hiding:
		hero["vy"] = -JUMP_SPEED * (CARRY_JUMP if carrying else 1.0)
		hero["buffer"] = 0.0
		hero["coyote"] = 0.0
		hero["ground"] = false
		hero["jumping"] = true
		hero["stand"] = null
		grounded = false
		emit("jump", float(hero["x"]), float(hero["y"]))
	var vy := float(hero["vy"])
	if bool(hero["jumping"]) and not pad.is_down(GameInput.A) and vy < -JUMP_CUT:
		vy = -JUMP_CUT
	if vy >= 0.0:
		hero["jumping"] = false
	var gravity := RISE_GRAVITY if (vy < 0.0 and (pad.is_down(GameInput.A) or not bool(hero["jumping"]))) else GRAVITY
	if thrown and float(hero["fly"]) > 0.0:
		gravity = 0.0
	hero["vy"] = minf(MAX_FALL, vy + gravity * delta)
	var previous := float(hero["y"])
	var hits := move_box(hero, HERO_HALF, HERO_TALL, delta, float(hero["drop"]) <= 0.0)
	_push_out_of_things(hero)
	hero["stand"] = null
	var landed := (hits & ON_GROUND) != 0
	if not landed and float(hero["drop"]) <= 0.0:
		var thing: Variant = land_on_things(hero, HERO_HALF, previous, true)
		if thing != null:
			hero["stand"] = thing
			landed = true
	if landed and not grounded and float(hero["air_time"]) > 0.2:
		emit("land", float(hero["x"]), float(hero["y"]))
	if landed:
		hero["air_time"] = 0.0
		hero["coyote"] = COYOTE
		hero["jumping"] = false
		if (hits & ON_GROUND) != 0 and not stunned and tile_at_point(float(hero["x"]), float(hero["y"]) - 1.0) != Levels.HAZARD and tile_at_point(float(hero["x"]) - 6.0, float(hero["y"]) - 1.0) != Levels.HAZARD and tile_at_point(float(hero["x"]) + 6.0, float(hero["y"]) - 1.0) != Levels.HAZARD:
			hero["safe"] = Vector2(float(hero["x"]), float(hero["y"]))
	else:
		hero["air_time"] = float(hero["air_time"]) + delta
	hero["ground"] = landed
	if thrown:
		# A thrown partner stays a missile until it lands or hits a wall: straight for a moment, then falling.
		var ended := landed or ((hits & (HIT_WALL | HIT_CEILING)) != 0)
		if ended and float(hero["throw_time"]) > 0.05:
			_end_flight(hero, (hits & HIT_WALL) != 0)
	# With two squirrels nobody walks out of the picture; in a boss room nobody leaves it.
	if _alive_count() > 1 or not boss.is_empty():
		hero["x"] = clampf(float(hero["x"]), camera.x + 6.0, camera.x + VIEW.x - 6.0)
	if not busy and pad.just_pressed(GameInput.B):
		_press_grab(hero, pad, grounded)
	var tile_x := float(hero["x"])
	var feet := float(hero["y"])
	for probe: float in [-HERO_HALF + 1.0, 0.0, HERO_HALF - 1.0]:
		if tile_at_point(tile_x + probe, feet - 2.0) == Levels.HAZARD and fmod(feet - 2.0, TILE) > 6.0:
			if hurt_hero(hero, tile_x - float(int(hero["face"])) * 4.0, true):
				hero["vy"] = -260.0
				hero["vx"] = -float(int(hero["face"])) * 60.0
			break
	if feet > float(height) * TILE + 48.0:
		_fell_out(hero)
	hero["dx"] = float(hero["x"]) - before.x
	hero["dy"] = float(hero["y"]) - before.y

func _standing_on_shelf(hero: Dictionary) -> bool:
	var x := float(hero["x"])
	var y := float(hero["y"]) + 1.0
	if is_solid(tile_at_point(x - HERO_HALF + 1.0, y)) or is_solid(tile_at_point(x + HERO_HALF - 1.0, y)):
		return false
	return tile_at_point(x, y) == Levels.SHELF or tile_at_point(x - HERO_HALF + 1.0, y) == Levels.SHELF or tile_at_point(x + HERO_HALF - 1.0, y) == Levels.SHELF

## Resting things are solid from the side to a squirrel walking into them: it walks up against a crate, not through it. In the air it may pass a thing's side (a crate left at the edge of a shelf never walls off a climb), and it is never pushed off its footing.
func _push_out_of_things(hero: Dictionary) -> void:
	if not bool(hero["ground"]) or float(hero["vy"]) < 0.0:
		return
	var x := float(hero["x"])
	var y := float(hero["y"])
	for object in objects:
		if int(object["state"]) != O_REST or bool(object["gone"]):
			continue
		var top := float(object["y"]) - float(object["tall"])
		if y <= top + 3.0 or y - HERO_TALL >= float(object["y"]):
			continue
		var gap := HERO_HALF + float(object["half"]) - absf(x - float(object["x"]))
		if gap > 0.0:
			var away := 1.0 if x >= float(object["x"]) else -1.0
			var pushed := x + away * gap
			# Never into a wall or off its footing: then the thing stays overlapped and the squirrel can still lift it.
			if not is_solid(tile_at_point(pushed + away * HERO_HALF, y - 4.0)) and (is_floor(pushed, y + 1.0) or is_same(hero["stand"], object) or hero["stand"] is Dictionary):
				x = pushed
				if float(hero["vx"]) * away < 0.0:
					hero["vx"] = 0.0
	hero["x"] = x

## Two squirrels on the ground get in each other's way: they cannot walk through each other.
func _separate_heroes() -> void:
	var a := heroes[0]
	var b := heroes[1]
	if int(a["state"]) != H_NORMAL or int(b["state"]) != H_NORMAL:
		return
	if is_same(a["stand"], b) or is_same(b["stand"], a):
		return
	var ya := float(a["y"])
	var yb := float(b["y"])
	if ya <= yb - HERO_TALL + 2.0 or yb <= ya - HERO_TALL + 2.0:
		return
	var gap := HERO_HALF * 2.0 - 1.0 - absf(float(a["x"]) - float(b["x"]))
	if gap <= 0.0:
		return
	var side := 1.0 if float(a["x"]) >= float(b["x"]) else (-1.0 if float(a["x"]) < float(b["x"]) else 1.0)
	for pair: Array in [[a, side], [b, -side]]:
		var hero: Dictionary = pair[0]
		var away: float = pair[1]
		var moved := float(hero["x"]) + away * gap * 0.5
		if not is_solid(tile_at_point(moved + away * HERO_HALF, float(hero["y"]) - 4.0)):
			hero["x"] = moved

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
		carried["y"] = float(hero["y"]) - (4.0 if bool(hero["hide"]) else HERO_TALL)

func _press_grab(hero: Dictionary, pad: GameInput, grounded: bool) -> void:
	var x := float(hero["x"])
	var y := float(hero["y"])
	var facing := int(hero["face"])
	var carried: Variant = hero["carry"]
	if carried is Dictionary:
		var object: Dictionary = carried
		if pad.is_down(GameInput.DOWN) and grounded:
			_put_down(hero, object)
			return
		hero["carry"] = null
		hero["hide"] = false
		object["by"] = int(hero["slot"])
		object["state"] = O_THROWN
		object["travel"] = 0.0
		if pad.is_down(GameInput.UP):
			object["x"] = x
			object["y"] = y - HERO_TALL - 1.0
			object["vx"] = 0.0
			object["vy"] = -THROW_UP_SPEED
			emit("throw_up", x, y - HERO_TALL, {"slot": int(hero["slot"])})
		elif pad.is_down(GameInput.DOWN):
			object["x"] = x
			object["y"] = y + float(object["tall"]) * 0.5
			object["vx"] = 0.0
			object["vy"] = THROW_DOWN_SPEED
			emit("throw", x, y, {"slot": int(hero["slot"])})
		else:
			# A sideways throw flies at waist height, so it meets the low enemies on the floor.
			object["x"] = x + float(facing) * 4.0
			object["y"] = y - 2.0
			object["vx"] = float(facing) * THROW_SPEED
			object["vy"] = 0.0
			emit("throw", x, y - HERO_TALL, {"slot": int(hero["slot"])})
		hero["busy"] = THROW_TIME
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
		partner["jumping"] = false
		partner["inv"] = maxf(float(partner["inv"]), 0.2)
		if pad.is_down(GameInput.UP):
			partner["vx"] = 0.0
			partner["vy"] = -BUDDY_UP_SPEED
			partner["fly"] = 0.0
			emit("throw_up", x, y - HERO_TALL, {"slot": int(hero["slot"]), "buddy": true})
		else:
			partner["vx"] = float(facing) * BUDDY_SPEED
			partner["vy"] = 0.0
			partner["y"] = y - 2.0
			partner["fly"] = BUDDY_FLIGHT
			emit("throw", x, y - HERO_TALL, {"slot": int(hero["slot"]), "buddy": true})
		hero["busy"] = THROW_TIME
		return
	# Nothing in hand: a thing in front, a dizzy enemy in front, the thing under the feet, then the partner.
	var best: Variant = null
	var best_distance := 1e9
	for object in objects:
		if int(object["state"]) != O_REST or bool(object["gone"]):
			continue
		var dx := (float(object["x"]) - x) * float(facing)
		var reach := float(object["half"]) + HERO_HALF + 6.0
		if dx > -4.0 and dx < reach and float(object["y"]) > y - 18.0 and float(object["y"]) - float(object["tall"]) < y - 2.0 and absf(dx) < best_distance:
			best = object
			best_distance = absf(dx)
	if best == null:
		for foe in foes:
			if int(foe["state"]) != Foes.STUNNED or bool(foe["gone"]):
				continue
			var dx := (float(foe["x"]) - x) * float(facing)
			if dx > -6.0 and dx < float(foe["half"]) + HERO_HALF + 8.0 and absf(float(foe["y"]) - y) < 14.0:
				best = _lift_foe(foe)
				break
	if best == null and hero["stand"] is Dictionary:
		var under: Dictionary = hero["stand"]
		if under.has("state") and not under.has("slot") and int(under["state"]) == O_REST:
			best = under
	if best is Dictionary:
		var object: Dictionary = best
		if _something_on(object):
			emit("clunk", float(object["x"]), float(object["y"]) - 8.0)
			return
		object["state"] = O_HELD
		object["vx"] = 0.0
		object["vy"] = 0.0
		object["stand"] = null
		hero["carry"] = object
		hero["busy"] = LIFT_TIME
		hero["stand"] = null
		emit("lift", x, y, {"kind": str(object["kind"]), "slot": int(hero["slot"])})
		return
	var partner := heroes[1 - int(hero["slot"])]
	if int(partner["state"]) == H_NORMAL and partner["carry"] == null and int(partner["lifting"]) < 0 and float(partner["stun"]) <= 0.0:
		var dx := (float(partner["x"]) - x) * float(facing)
		if (dx > -6.0 and dx < 18.0 and absf(float(partner["y"]) - y) < 12.0) or is_same(hero["stand"], partner):
			partner["state"] = H_CARRIED
			partner["rider_of"] = int(hero["slot"])
			partner["hide"] = false
			hero["lifting"] = int(partner["slot"])
			hero["busy"] = LIFT_TIME
			if is_same(hero["stand"], partner):
				hero["stand"] = null
			emit("lift", x, y, {"kind": "buddy", "slot": int(hero["slot"])})

## Whether a squirrel or another thing stands on top of a thing, which then cannot be lifted out from under them.
func _something_on(object: Dictionary) -> bool:
	for other in objects:
		if not is_same(other, object) and int(other["state"]) == O_REST and is_same(other["stand"], object):
			return true
	return false

## A dizzy enemy is picked up: it leaves the enemies and becomes a thing to throw.
func _lift_foe(foe: Dictionary) -> Dictionary:
	foe["gone"] = true
	var object := add_object("foe", float(foe["x"]), float(foe["y"]))
	object["foe"] = str(foe["kind"])
	object["points"] = int(foe["points"])
	object["face"] = int(foe["face"])
	return object

## Set a carried thing down in front of the squirrel, on the cell grid, on top of whatever stands there already.
func _put_down(hero: Dictionary, object: Dictionary) -> void:
	var facing := float(int(hero["face"]))
	var x := floorf((float(hero["x"]) + facing * (HERO_HALF + float(object["half"]) + 1.0)) / TILE) * TILE + TILE * 0.5
	if absf(x - float(hero["x"])) < HERO_HALF + float(object["half"]) - 2.0:
		x += facing * TILE
	var y := float(hero["y"])
	for other in objects:
		if int(other["state"]) == O_REST and not is_same(other, object) and not bool(other["gone"]) and absf(float(other["x"]) - x) < float(other["half"]) + float(object["half"]) - 2.0 and float(other["y"]) > y - 40.0 and float(other["y"]) - float(other["tall"]) < y + 2.0:
			x = float(other["x"])
			y = minf(y, float(other["y"]) - float(other["tall"]))
	var tall := float(object["tall"])
	var half := float(object["half"])
	if is_solid(tile_at_point(x - half + 1.0, y - 1.0)) or is_solid(tile_at_point(x + half - 1.0, y - 1.0)) or is_solid(tile_at_point(x, y - tall + 1.0)):
		emit("clunk", x, y - 8.0)
		return
	hero["carry"] = null
	hero["hide"] = false
	object["state"] = O_REST
	object["x"] = x
	object["y"] = y
	object["vx"] = 0.0
	object["vy"] = 0.0
	hero["busy"] = THROW_TIME
	if y < float(hero["y"]) - 1.0:
		stacks += 1
	emit("put_down", x, y, {"stacked": y < float(hero["y"]) - 1.0})

## Drop whatever the squirrel carries, a thing or the partner.
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

## A thrown partner comes out of its flight and falls like anyone else.
func _end_flight(hero: Dictionary, bounced: bool) -> void:
	hero["state"] = H_NORMAL
	hero["fly"] = 0.0
	if bounced:
		hero["vx"] = -float(hero["vx"]) * 0.25
		hero["vy"] = -90.0
	else:
		hero["vx"] = float(hero["vx"]) * 0.4
	hero["inv"] = maxf(float(hero["inv"]), 0.3)
	emit("land", float(hero["x"]), float(hero["y"]))

## Take a heart from a squirrel, unless it is flashing, hidden under a crate, carried or thrown. `forced` ignores the crate (hazards, a boss's body).
func hurt_hero(hero: Dictionary, from_x: float, forced: bool = false) -> bool:
	if int(hero["state"]) != H_NORMAL or float(hero["inv"]) > 0.0 or phase != P_PLAY:
		return false
	if bool(hero["hide"]) and not forced:
		return false
	_let_go(hero)
	hero["hearts"] = int(hero["hearts"]) - 1
	hero["inv"] = 1.5
	hero["stun"] = 0.3
	hero["vx"] = (1.0 if float(hero["x"]) >= from_x else -1.0) * 110.0
	hero["vy"] = -170.0
	hero["ground"] = false
	hero["jumping"] = false
	emit("hurt", float(hero["x"]), float(hero["y"]) - 8.0, {"slot": int(hero["slot"])})
	if int(hero["hearts"]) <= 0:
		_kill(hero)
	return true

## A thrown thing or the partner bumped a squirrel: it reels for a moment but loses nothing.
func bump_hero(hero: Dictionary, direction: float) -> void:
	if int(hero["state"]) != H_NORMAL or float(hero["inv"]) > 0.0:
		return
	_let_go(hero)
	hero["stun"] = 0.4
	hero["vx"] = direction * 120.0
	hero["vy"] = -140.0
	hero["ground"] = false
	emit("bump", float(hero["x"]), float(hero["y"]) - 8.0, {"slot": int(hero["slot"])})

func _kill(hero: Dictionary) -> void:
	_let_go(hero)
	hero["state"] = H_DEAD
	hero["dead_time"] = 1.4
	hero["vx"] = 0.0
	hero["vy"] = -240.0
	hero["lives"] = int(hero["lives"]) - 1
	hero["hearts"] = 0
	deaths += 1
	emit("die", float(hero["x"]), float(hero["y"]) - 8.0, {"slot": int(hero["slot"])})

func _fell_out(hero: Dictionary) -> void:
	_let_go(hero)
	hero["hearts"] = int(hero["hearts"]) - 1
	emit("hurt", float(hero["x"]), float(height) * TILE - 8.0, {"slot": int(hero["slot"])})
	if int(hero["hearts"]) <= 0:
		_kill(hero)
		hero["y"] = float(height) * TILE + 40.0
		return
	var back := _return_point(hero, false)
	_place_hero(hero, back.x, back.y)
	hero["safe"] = back
	hero["inv"] = 1.6

## Where a squirrel comes back: beside a partner standing on the ground, else where it last stood safely or (after losing a life) at the last flag.
func _return_point(hero: Dictionary, after_death: bool) -> Vector2:
	var partner := heroes[1 - int(hero["slot"])]
	if int(partner["state"]) == H_NORMAL and bool(partner["ground"]) and partner["stand"] == null:
		return Vector2(float(partner["x"]), float(partner["y"]))
	if after_death:
		if checkpoint >= 0:
			return flags[checkpoint]
		return level["spawn"]
	return hero["safe"]

func _respawn(hero: Dictionary) -> void:
	if int(hero["lives"]) <= 0:
		hero["state"] = H_OUT
		return
	var back := _return_point(hero, boss.is_empty())
	if not boss.is_empty():
		back = level["spawn"]
	_place_hero(hero, back.x, back.y)
	hero["hearts"] = int(rules["hearts"])
	hero["inv"] = 2.0
	emit("respawn", back.x, back.y - 8.0, {"slot": int(hero["slot"])})

func _alive_count() -> int:
	var count := 0
	for hero in heroes:
		if int(hero["state"]) == H_NORMAL or int(hero["state"]) == H_CARRIED or int(hero["state"]) == H_THROWN:
			count += 1
	return count

# ---- things to lift and throw ----

func _step_objects(delta: float) -> void:
	for object in objects:
		if bool(object["gone"]):
			continue
		var state := int(object["state"])
		if state == O_HELD:
			continue
		if state == O_THROWN:
			_step_thrown(object, delta)
		elif is_active_at(float(object["x"]), float(object["y"])):
			_step_resting(object, delta)

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
	object["vx"] = move_toward(float(object["vx"]), 0.0, 400.0 * delta)
	object["vy"] = minf(MAX_FALL, float(object["vy"]) + GRAVITY * delta)
	var previous := float(object["y"])
	var hits := move_box(object, float(object["half"]), float(object["tall"]), delta, true)
	object["stand"] = null
	if (hits & ON_GROUND) == 0:
		object["stand"] = land_on_things(object, float(object["half"]), previous)
	if float(object["y"]) > float(height) * TILE + 64.0:
		object["gone"] = true
	elif tile_at_point(float(object["x"]), float(object["y"]) - 2.0) == Levels.HAZARD and str(object["kind"]) == "foe":
		object["gone"] = true
		emit("poof", float(object["x"]), float(object["y"]) - 6.0)

func _step_thrown(object: Dictionary, delta: float) -> void:
	object["spin"] = float(object["spin"]) + delta
	var vx := float(object["vx"])
	var vy := float(object["vy"])
	object["travel"] = float(object["travel"]) + Vector2(vx, vy).length() * delta
	var hits := move_box(object, float(object["half"]) - 1.0, float(object["tall"]) - 2.0, delta, false)
	var x := float(object["x"])
	var y := float(object["y"])
	var half := float(object["half"])
	var tall := float(object["tall"])
	var direction := signf(vx) if vx != 0.0 else 0.0
	# Enemy shots in the way are knocked out of the air; the throw flies on.
	for shot in shots:
		if not bool(shot["gone"]) and not bool(shot.get("solid", false)) and absf(float(shot["x"]) - x) < half + 4.0 and float(shot["y"]) > y - tall - 4.0 and float(shot["y"]) < y + 4.0:
			shot["gone"] = true
			emit("clang", float(shot["x"]), float(shot["y"]))
	# The first enemy in the way is knocked out, whatever kind it is.
	for foe in foes:
		var state := int(foe["state"])
		if (state != Foes.ALIVE and state != Foes.STUNNED) or bool(foe["gone"]):
			continue
		if absf(float(foe["x"]) - x) < half + float(foe["half"]) and float(foe["y"]) > y - tall and float(foe["y"]) - float(foe["tall"]) < y:
			Foes.knock_out(self, foe, int(object["by"]), direction if direction != 0.0 else 1.0, false)
			if str(object["kind"]) == "foe":
				_score_thrown_foe(object)
			_impact(object, direction, true)
			return
	if not boss.is_empty():
		var result := Bosses.take_throw(self, object)
		if result != Bosses.MISS:
			_impact(object, direction, true)
			return
	# A squirrel in the way (not the thrower at the moment it lets go) is bumped.
	for hero in heroes:
		if int(hero["state"]) != H_NORMAL or (int(hero["slot"]) == int(object["by"]) and float(object["travel"]) < 30.0):
			continue
		if absf(float(hero["x"]) - x) < half + HERO_HALF - 1.0 and float(hero["y"]) > y - tall and float(hero["y"]) - HERO_TALL < y:
			if bool(hero["hide"]):
				emit("clang", x, y - tall * 0.5)
			else:
				bump_hero(hero, direction if direction != 0.0 else 1.0)
			_impact(object, direction, false)
			return
	# A resting thing in the way stops it; a wooden one breaks too.
	for other in objects:
		if is_same(other, object) or int(other["state"]) != O_REST or bool(other["gone"]):
			continue
		if absf(float(other["x"]) - x) < half + float(other["half"]) - 2.0 and float(other["y"]) > y - tall + 2.0 and float(other["y"]) - float(other["tall"]) < y - 2.0:
			if bool(other["breaks"]) and str(other["kind"]) != "foe" and not _something_on(other):
				other["by"] = int(object["by"])
				_break(other)
			_impact(object, direction, false)
			return
	if hits != 0:
		if (hits & (HIT_WALL | HIT_CEILING)) != 0 and object.has("wall"):
			var cell: Vector2i = object["wall"]
			if tile_at(cell.x, cell.y) == Levels.CRACK:
				_crumble(cell.x, cell.y)
		_impact(object, direction, false)
		return
	if float(object["travel"]) > VIEW.x * 1.1 or not is_active_at(x, y):
		object["gone"] = true

## A thrown thing hit something: a breaking one comes apart, any other drops where it is and can be used again.
func _impact(object: Dictionary, direction: float, struck: bool) -> void:
	if str(object["kind"]) == "foe":
		object["gone"] = true
		emit("foe_out", float(object["x"]), float(object["y"]) - 6.0, {"kind": str(object["foe"])})
		if not struck:
			_score_thrown_foe(object)
		return
	if bool(object["breaks"]):
		_break(object)
		return
	object["state"] = O_REST
	object["vx"] = -direction * 50.0
	object["vy"] = -150.0 if float(object["vy"]) >= 0.0 else 0.0
	emit("clang", float(object["x"]), float(object["y"]) - float(object["tall"]) * 0.5)

## A dizzy enemy that was thrown counts as beaten once, whatever it hit.
func _score_thrown_foe(object: Dictionary) -> void:
	if bool(object.get("scored", false)):
		return
	object["scored"] = true
	foes_beaten += 1
	award(int(object["by"]), int(object.get("points", 100)), float(object["x"]), float(object["y"]) - 10.0)

## A wall cell of cracked plaster and every cracked cell joined to it crumble away.
func _crumble(column: int, row: int) -> void:
	var open: Array[Vector2i] = [Vector2i(column, row)]
	var count := 0
	while not open.is_empty() and count < 64:
		var cell: Vector2i = open.pop_back()
		if tile_at(cell.x, cell.y) != Levels.CRACK:
			continue
		tiles[cell.y * width + cell.x] = Levels.EMPTY
		count += 1
		emit("crumble", float(cell.x) * TILE + 8.0, float(cell.y) * TILE + 8.0)
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			open.append(cell + step)

## A wooden crate, an apple or a nut comes apart; whatever was inside pops out.
func _break(object: Dictionary) -> void:
	object["gone"] = true
	var x := float(object["x"])
	var y := float(object["y"]) - float(object["tall"]) * 0.5
	var kind := str(object["kind"])
	emit("break", x, y, {"kind": kind})
	if kind == "wood":
		crates_broken += 1
		award(int(object["by"]), 10, x, y, false)
	match str(object["inside"]):
		"":
			pass
		"acorns":
			for index in 3:
				add_pickup("acorn", x, y, float(index - 1) * 45.0, -190.0 + absf(float(index - 1)) * 30.0)
		"bag":
			add_pickup("bag", x, y, 0.0, -180.0)
		"heart":
			add_pickup("heart", x, y, 0.0, -180.0)
		"golden":
			add_pickup("golden", x, y, 0.0, -200.0)
		var inside:
			if Foes.KINDS.has(inside):
				var foe := Foes.create({"kind": inside, "at": Vector2(x, float(object["y"])), "face": 1 if rng.chance(0.5) else -1})
				foe["vy"] = -160.0
				foes.append(foe)
				emit("foe_pop", x, y)

func award(slot: int, points: int, x: float, y: float, show: bool = true) -> void:
	var receiver := slot
	if receiver < 0 or receiver > 1 or not bool(heroes[receiver]["active"]):
		receiver = 0 if bool(heroes[0]["active"]) else 1
	heroes[receiver]["score"] = int(heroes[receiver]["score"]) + points
	if show:
		emit("points", x, y, {"points": points})

## An enemy was knocked out by player `slot` (-1: by the level itself).
func foe_beaten(foe: Dictionary, slot: int, by_buddy: bool) -> void:
	foes_beaten += 1
	if by_buddy:
		buddy_hits += 1
	if slot >= 0:
		award(slot, int(foe["points"]), float(foe["x"]), float(foe["y"]) - float(foe["tall"]))

func boss_beaten() -> void:
	bosses_beaten += 1
	for hero in heroes:
		if bool(hero["active"]):
			hero["score"] = int(hero["score"]) + 2000
	emit("points", float(boss["x"]), float(boss["y"]) - 40.0, {"points": 2000})
	_clear_level()

func _clear_level() -> void:
	if phase != P_PLAY:
		return
	phase = P_CLEAR
	phase_time = 2.6
	cleared[level_id] = true
	route.append(level_id)
	node = level_id
	for hero in heroes:
		if bool(hero["active"]) and int(hero["state"]) != H_OUT:
			hero["score"] = int(hero["score"]) + 500
			hero["inv"] = 4.0
	for shot in shots:
		shot["gone"] = true
	emit("level_clear", camera.x + VIEW.x * 0.5, camera.y + VIEW.y * 0.5, {"final": level_id == Levels.FINAL})

func _after_clear() -> void:
	if level_id == Levels.FINAL:
		phase = P_WON
		return
	open_map()

# ---- pick-ups, spawners, flags, burrows, the exit ----

func _step_pickups(delta: float) -> void:
	for pickup in pickups:
		if bool(pickup["gone"]):
			continue
		pickup["time"] = float(pickup["time"]) + delta
		if not bool(pickup["float"]):
			pickup["vy"] = minf(MAX_FALL, float(pickup["vy"]) + GRAVITY * delta)
			var hits := move_box(pickup, 4.0, 8.0, delta, true)
			if (hits & ON_GROUND) != 0:
				pickup["vx"] = 0.0
			if (hits & HIT_WALL) != 0:
				pickup["vx"] = -float(pickup["vx"]) * 0.5
			if float(pickup["y"]) > float(height) * TILE + 32.0:
				pickup["gone"] = true
				continue
			# A fresh pick-up cannot be taken for a moment, so the player sees what came out.
			if float(pickup["time"]) < 0.2:
				continue
		for hero in heroes:
			var state := int(hero["state"])
			if state != H_NORMAL and state != H_THROWN and state != H_CARRIED:
				continue
			if absf(float(hero["x"]) - float(pickup["x"])) < 10.0 and float(pickup["y"]) > float(hero["y"]) - 20.0 and float(pickup["y"]) - 8.0 < float(hero["y"]) + 2.0:
				_collect(hero, pickup)
				break

func _collect(hero: Dictionary, pickup: Dictionary) -> void:
	pickup["gone"] = true
	var x := float(pickup["x"])
	var y := float(pickup["y"]) - 4.0
	var slot := int(hero["slot"])
	match str(pickup["kind"]):
		"acorn":
			_add_acorns(hero, 1, x, y)
			emit("acorn", x, y)
		"bag":
			_add_acorns(hero, 5, x, y)
			emit("bag", x, y)
		"heart":
			if int(hero["hearts"]) < int(rules["hearts"]):
				hero["hearts"] = int(hero["hearts"]) + 1
			else:
				award(slot, 200, x, y)
			emit("heart", x, y, {"slot": slot})
		"golden":
			hero["lives"] = int(hero["lives"]) + 1
			award(slot, 1000, x, y)
			emit("extra_life", x, y, {"slot": slot})

## Acorns count for both squirrels together; every fiftieth gives the one who picked it up an extra life.
func _add_acorns(hero: Dictionary, count: int, x: float, y: float) -> void:
	acorns_total += count
	award(int(hero["slot"]), 10 * count, x, y, false)
	acorns += count
	while acorns >= ACORNS_PER_LIFE:
		acorns -= ACORNS_PER_LIFE
		hero["lives"] = int(hero["lives"]) + 1
		emit("extra_life", x, y, {"slot": int(hero["slot"])})

func _step_spawners(delta: float) -> void:
	for spawner in spawners:
		var x := float(spawner["x"])
		var y := float(spawner["y"])
		if not is_seen(x, y, 40.0):
			continue
		var made: Array = spawner["made"]
		var alive := 0
		for foe: Dictionary in made:
			if not bool(foe["gone"]) and int(foe["state"]) != Foes.KNOCKED_OUT:
				alive += 1
		spawner["made"] = made.filter(func(foe: Dictionary) -> bool: return not bool(foe["gone"]))
		spawner["time"] = float(spawner["time"]) - delta
		if float(spawner["time"]) > 0.0 or alive >= int(spawner["most"]):
			continue
		# Nothing comes out while a squirrel stands right in front of the hole.
		var blocked := false
		for hero in heroes:
			if int(hero["state"]) == H_NORMAL and absf(float(hero["x"]) - x) < 20.0 and absf(float(hero["y"]) - y) < 20.0:
				blocked = true
		if blocked:
			continue
		spawner["time"] = float(spawner["every"])
		var foe := Foes.create({"kind": str(spawner["kind"]), "at": Vector2(x, y), "face": int(spawner["face"])})
		foe["spawned"] = true
		foes.append(foe)
		(spawner["made"] as Array).append(foe)
		emit("spawn", x, y - 8.0)

func _touch_things(pads: Array) -> void:
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
		var pad: GameInput = pads[int(hero["slot"])]
		if bool(hero["ground"]) and pad.just_pressed(GameInput.DOWN) and hero["carry"] == null and int(hero["lifting"]) < 0:
			var warps: Array = level["warps"]
			for index in warps.size():
				var warp: Dictionary = warps[index]
				var at: Vector2 = warp["at"]
				if absf(at.x - x) < 9.0 and absf(at.y - y) < 4.0:
					_take_burrow(warp, index)
					return
		var exit: Variant = level["exit"]
		if exit is Vector2 and phase == P_PLAY and bool(hero["ground"]) and absf((exit as Vector2).x - x) < 10.0 and absf((exit as Vector2).y - y) < 6.0:
			_clear_level()
			return

## Both squirrels go through a burrow together, so the view never has to choose between them.
func _take_burrow(warp: Dictionary, index: int) -> void:
	var to: Vector2 = warp["to"]
	emit("burrow", float((warp["at"] as Vector2).x), float((warp["at"] as Vector2).y) - 8.0)
	for hero in heroes:
		var state := int(hero["state"])
		if state == H_NORMAL or state == H_THROWN:
			_let_go(hero)
			_place_hero(hero, to.x + (8.0 if int(hero["slot"]) == 1 else -2.0), to.y)
			hero["inv"] = maxf(float(hero["inv"]), 0.5)
	if bool(warp["secret"]):
		var key := "%s/%d" % [level_id, index]
		if not secrets.has(key):
			secrets[key] = true
			emit("secret", to.x, to.y - 20.0)
	camera = _camera_target()

func _sweep() -> void:
	objects = objects.filter(func(object: Dictionary) -> bool: return not bool(object["gone"]))
	foes = foes.filter(func(foe: Dictionary) -> bool: return not bool(foe["gone"]))
	shots = shots.filter(func(shot: Dictionary) -> bool: return not bool(shot["gone"]))
	pickups = pickups.filter(func(pickup: Dictionary) -> bool: return not bool(pickup["gone"]))

# ---- camera, losing ----

## The bonus room a point is in, or an empty rectangle.
func zone_at(point: Vector2) -> Rect2:
	for zone: Rect2 in level.get("zones", []):
		if zone.has_point(point):
			return zone
	return Rect2()

func _camera_target() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for hero in heroes:
		var state := int(hero["state"])
		if state == H_NORMAL or state == H_THROWN or state == H_CARRIED:
			sum += Vector2(float(hero["x"]), float(hero["y"]))
			count += 1
	if count == 0:
		return camera
	var focus := sum / float(count)
	var target := Vector2(focus.x - VIEW.x * 0.5, focus.y - VIEW.y * 0.66)
	var zone := zone_at(focus - Vector2(0, 4))
	if zone.has_area():
		target.x = clampf(target.x, zone.position.x, maxf(zone.position.x, zone.end.x - VIEW.x))
		target.y = clampf(target.y, zone.position.y - 40.0, maxf(zone.position.y - 40.0, zone.end.y - VIEW.y))
		return target
	target.x = clampf(target.x, 0.0, maxf(0.0, float(level.get("main_w", width)) * TILE - VIEW.x))
	# The lowest row is only there to be solid: the view stops a little above the bottom of the level.
	target.y = clampf(target.y, 0.0, maxf(0.0, float(height) * TILE - VIEW.y - 8.0))
	return target

func _step_camera(delta: float) -> void:
	var target := _camera_target()
	var rate := 60.0 * delta
	camera.x = move_toward(camera.x, target.x, maxf(1.5, absf(target.x - camera.x) * 0.16 * rate))
	camera.y = move_toward(camera.y, target.y, maxf(1.0, absf(target.y - camera.y) * 0.12 * rate))
	# A squirrel left far outside the picture is brought back to its partner.
	if _alive_count() < 2:
		return
	for hero in heroes:
		if int(hero["state"]) != H_NORMAL:
			continue
		var outside := float(hero["y"]) > camera.y + VIEW.y + 28.0 or float(hero["y"]) < camera.y - 40.0
		hero["off_time"] = float(hero["off_time"]) + delta if outside else 0.0
		if float(hero["off_time"]) > 0.8:
			var partner := heroes[1 - int(hero["slot"])]
			if int(partner["state"]) == H_NORMAL:
				_let_go(hero)
				_place_hero(hero, float(partner["x"]), float(partner["y"]))
				hero["inv"] = 1.2
				emit("respawn", float(hero["x"]), float(hero["y"]) - 8.0, {"slot": int(hero["slot"])})

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
	start_level(level_id, checkpoint)
