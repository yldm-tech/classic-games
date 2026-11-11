extends RefCounted

## The creatures and runaway things the squirrels meet, three of each place, and what they shoot. Every function is static and works on the world it is handed (world.gd), so the two scripts do not hold each other. Anything thrown knocks any of them out in one hit; jumping on one, or letting it run into a squirrel hiding under a crate, leaves it dizzy, and a dizzy one can be picked up and thrown.
##
##   kitchen    ant      walks its ledge back and forth
##              fly      hovers, then swoops at a squirrel and climbs back
##              shaker   a pepper pot that tips forward and puffs pepper along the floor
##   toy shop   mouse    a wind-up mouse that winds itself up and dashes when it sees a squirrel
##              jack     a box that sits still until a squirrel comes near, then springs out and hops after it
##              plane    a little biplane that flies its beat back and forth
##   sewer      rat      walks, and lunges at a squirrel close in front
##              frog     sits, then leaps at the nearest squirrel
##              slime    clings to the ceiling and drops on whoever passes under, then creeps
##   treehouse  worm     a long slow caterpillar, hard to jump over
##              hornet   hovers, buzzes as it takes aim, then dives in a straight line
##              spider   hangs on its thread and drops fast to the height of a squirrel below

const ALIVE := 0
const KNOCKED_OUT := 1
const STUNNED := 2

const GRAVITY := 1400.0

const KINDS := {
	"ant": {"half": 7.0, "tall": 9.0, "points": 100, "flies": false},
	"fly": {"half": 6.0, "tall": 9.0, "points": 120, "flies": true},
	"shaker": {"half": 6.0, "tall": 16.0, "points": 150, "flies": false},
	"mouse": {"half": 8.0, "tall": 11.0, "points": 150, "flies": false},
	"jack": {"half": 7.0, "tall": 13.0, "points": 200, "flies": false},
	"plane": {"half": 10.0, "tall": 9.0, "points": 150, "flies": true},
	"rat": {"half": 9.0, "tall": 10.0, "points": 120, "flies": false},
	"frog": {"half": 7.0, "tall": 12.0, "points": 150, "flies": false},
	"slime": {"half": 7.0, "tall": 9.0, "points": 120, "flies": false},
	"worm": {"half": 12.0, "tall": 9.0, "points": 150, "flies": false},
	"hornet": {"half": 6.0, "tall": 10.0, "points": 150, "flies": true},
	"spider": {"half": 6.0, "tall": 10.0, "points": 120, "flies": true},
}

static func create(spec: Dictionary) -> Dictionary:
	var kind := str(spec["kind"])
	var data: Dictionary = KINDS[kind]
	var at: Vector2 = spec["at"]
	var foe := {
		"kind": kind, "x": at.x, "y": at.y, "vx": 0.0, "vy": 0.0, "face": int(spec.get("face", -1)), "points": int(data["points"]), "half": float(data["half"]), "tall": float(data["tall"]),
		"flies": bool(data["flies"]), "state": ALIVE, "time": 0.0, "home": at, "reach": float(spec.get("reach", 64.0)), "flash": 0.0, "cool": 0.6, "mode": "walk", "ground": false,
		"gone": false, "stun": 0.0, "aim": 0.0, "goal": at, "spawned": false,
	}
	match kind:
		"jack":
			foe["mode"] = "box"
		"slime":
			foe["mode"] = "cling"
		"fly", "plane", "hornet", "spider":
			foe["mode"] = "patrol"
	return foe

static func step(world: Variant, foe: Dictionary, delta: float) -> void:
	foe["time"] = float(foe["time"]) + delta
	var state := int(foe["state"])
	if state == KNOCKED_OUT:
		foe["vy"] = float(foe["vy"]) + GRAVITY * delta
		foe["x"] = float(foe["x"]) + float(foe["vx"]) * delta
		foe["y"] = float(foe["y"]) + float(foe["vy"]) * delta
		if float(foe["time"]) > 1.2:
			foe["gone"] = true
		return
	foe["flash"] = maxf(0.0, float(foe["flash"]) - delta)
	foe["cool"] = maxf(0.0, float(foe["cool"]) - delta)
	if state == STUNNED:
		_step_stunned(world, foe, delta)
		return
	var speed := float(world.rules["speed"])
	match str(foe["kind"]):
		"ant":
			foe["vx"] = float(int(foe["face"])) * 34.0 * speed
			_walk(world, foe, delta)
		"worm":
			foe["vx"] = float(int(foe["face"])) * 22.0 * speed
			_walk(world, foe, delta)
		"rat":
			_step_rat(world, foe, delta, speed)
		"mouse":
			_step_mouse(world, foe, delta, speed)
		"shaker":
			_step_shaker(world, foe, delta, speed)
		"jack":
			_step_jack(world, foe, delta, speed)
		"frog":
			_step_frog(world, foe, delta, speed)
		"slime":
			_step_slime(world, foe, delta, speed)
		"fly":
			_step_fly(world, foe, delta, speed)
		"plane":
			_step_plane(world, foe, delta, speed)
		"hornet":
			_step_hornet(world, foe, delta, speed)
		"spider":
			_step_spider(world, foe, delta, speed)
	_touch_heroes(world, foe)
	if float(foe["y"]) > float(world.height) * world.TILE + 40.0:
		foe["gone"] = true

## Dizzy: it falls to the floor if it was flying, sits there with stars round its head, and can be picked up; then it shakes it off.
static func _step_stunned(world: Variant, foe: Dictionary, delta: float) -> void:
	foe["stun"] = float(foe["stun"]) - delta
	foe["vx"] = move_toward(float(foe["vx"]), 0.0, 260.0 * delta)
	foe["vy"] = minf(320.0, float(foe["vy"]) + GRAVITY * delta)
	var hits: int = world.move_box(foe, float(foe["half"]), float(foe["tall"]), delta, true)
	foe["ground"] = (hits & world.ON_GROUND) != 0
	if (hits & world.HIT_WALL) != 0:
		foe["vx"] = -float(foe["vx"]) * 0.5
	if float(foe["stun"]) <= 0.0:
		foe["state"] = ALIVE
		foe["cool"] = 0.8
		match str(foe["kind"]):
			"fly", "plane", "hornet":
				foe["mode"] = "back"
			"spider":
				foe["mode"] = "climb"
			"jack":
				foe["mode"] = "hop"
			"slime":
				foe["mode"] = "walk"
			_:
				foe["mode"] = "walk"
	if float(foe["y"]) > float(world.height) * world.TILE + 40.0:
		foe["gone"] = true

## Walk along the floor and turn round at walls, at the end of a ledge and at things lying there. Returns the move flags, with 8 added when it turned.
static func _walk(world: Variant, foe: Dictionary, delta: float) -> int:
	foe["vy"] = minf(320.0, float(foe["vy"]) + GRAVITY * delta)
	var hits: int = world.move_box(foe, float(foe["half"]), float(foe["tall"]), delta, true)
	var previous_ground := bool(foe["ground"])
	foe["ground"] = (hits & world.ON_GROUND) != 0
	if not bool(foe["ground"]):
		var thing: Variant = world.land_on_things(foe, float(foe["half"]), float(foe["y"]) - float(foe["vy"]) * delta)
		if thing != null:
			foe["ground"] = true
	var facing := int(foe["face"])
	var turn: bool = (hits & world.HIT_WALL) != 0
	if bool(foe["ground"]) and float(foe["vx"]) != 0.0:
		var ahead := float(foe["x"]) + float(facing) * (float(foe["half"]) + 2.0)
		var floor_ahead: bool = world.is_floor(ahead, float(foe["y"]) + 2.0) or world.thing_at(ahead, float(foe["y"]) + 2.0) != null
		if not floor_ahead or world.thing_at(ahead, float(foe["y"]) - 4.0) != null:
			turn = true
		elif world.tile_at_point(ahead, float(foe["y"]) - 2.0) == world.Levels.HAZARD:
			turn = true
	if turn and previous_ground:
		foe["face"] = -facing
		foe["vx"] = -float(foe["vx"])
	return hits | (8 if turn else 0)

static func _ahead_of(foe: Dictionary, hero: Dictionary, distance: float, height: float) -> bool:
	if hero.is_empty():
		return false
	var ahead := (float(hero["x"]) - float(foe["x"])) * float(int(foe["face"]))
	return ahead > 0.0 and ahead < distance and absf(float(hero["y"]) - float(foe["y"])) < height

static func _step_rat(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	if str(foe["mode"]) == "lunge":
		var hits := _walk(world, foe, delta)
		if bool(foe["ground"]) and float(foe["vy"]) >= 0.0 and float(foe["aim"]) <= 0.0:
			foe["mode"] = "walk"
			foe["cool"] = 1.3
		foe["aim"] = maxf(0.0, float(foe["aim"]) - delta)
		if (hits & 8) != 0:
			foe["mode"] = "walk"
		return
	foe["vx"] = float(int(foe["face"])) * 42.0 * speed
	_walk(world, foe, delta)
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	if float(foe["cool"]) <= 0.0 and bool(foe["ground"]) and _ahead_of(foe, target, 56.0, 14.0):
		foe["mode"] = "lunge"
		foe["vx"] = float(int(foe["face"])) * 150.0 * speed
		foe["vy"] = -170.0
		foe["ground"] = false
		foe["aim"] = 0.1
		world.emit("lunge", float(foe["x"]), float(foe["y"]))

static func _step_mouse(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var facing := int(foe["face"])
	match str(foe["mode"]):
		"walk":
			foe["vx"] = float(facing) * 38.0 * speed
			_walk(world, foe, delta)
			var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
			if float(foe["cool"]) <= 0.0 and _ahead_of(foe, target, 130.0, 14.0):
				foe["mode"] = "wind"
				foe["aim"] = 0.45
				world.emit("wind", float(foe["x"]), float(foe["y"]))
		"wind":
			foe["vx"] = 0.0
			_walk(world, foe, delta)
			foe["face"] = facing
			foe["aim"] = float(foe["aim"]) - delta
			if float(foe["aim"]) <= 0.0:
				foe["mode"] = "dash"
		"dash":
			foe["vx"] = float(facing) * 160.0 * speed
			var hits := _walk(world, foe, delta)
			if (hits & 8) != 0:
				foe["mode"] = "dizzy"
				foe["aim"] = 0.9
				foe["vx"] = 0.0
				world.emit("clang", float(foe["x"]), float(foe["y"]) - 6.0)
		_:
			foe["vx"] = 0.0
			_walk(world, foe, delta)
			foe["aim"] = float(foe["aim"]) - delta
			if float(foe["aim"]) <= 0.0:
				foe["mode"] = "walk"
				foe["cool"] = 0.9

static func _step_shaker(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	foe["vx"] = 0.0
	_walk(world, foe, delta)
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	if str(foe["mode"]) == "aim":
		foe["aim"] = float(foe["aim"]) - delta
		if float(foe["aim"]) <= 0.0:
			foe["mode"] = "walk"
			foe["cool"] = 2.4 / speed
			var facing := int(foe["face"])
			var shot: Dictionary = world.add_shot("pepper", float(foe["x"]) + float(facing) * 8.0, float(foe["y"]) - 12.0, float(facing) * 110.0 * speed, 0.0, 0.0)
			shot["life"] = 1.6
			world.emit("puff", float(foe["x"]) + float(facing) * 8.0, float(foe["y"]) - 12.0)
		return
	if target.is_empty():
		return
	var dx := float(target["x"]) - float(foe["x"])
	if absf(dx) < 200.0:
		foe["face"] = 1 if dx > 0.0 else -1
	if float(foe["cool"]) <= 0.0 and absf(dx) < 170.0 and absf(float(target["y"]) - float(foe["y"])) < 28.0:
		foe["mode"] = "aim"
		foe["aim"] = 0.55
		world.emit("aim", float(foe["x"]), float(foe["y"]) - 16.0)

static func _step_jack(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	if str(foe["mode"]) == "box":
		foe["vx"] = 0.0
		_walk(world, foe, delta)
		if not target.is_empty() and absf(float(target["x"]) - float(foe["x"])) < 72.0 and absf(float(target["y"]) - float(foe["y"])) < 40.0:
			foe["mode"] = "hop"
			foe["tall"] = 22.0
			foe["cool"] = 0.35
			foe["vy"] = -200.0
			world.emit("pop", float(foe["x"]), float(foe["y"]) - 12.0)
		return
	foe["vy"] = minf(320.0, float(foe["vy"]) + GRAVITY * delta)
	var hits: int = world.move_box(foe, float(foe["half"]), float(foe["tall"]), delta, true)
	var grounded: bool = (hits & world.ON_GROUND) != 0
	if (hits & world.HIT_WALL) != 0:
		foe["vx"] = -float(foe["vx"])
		foe["face"] = -int(foe["face"])
	if grounded and not bool(foe["ground"]):
		foe["vx"] = 0.0
	foe["ground"] = grounded
	if grounded and float(foe["cool"]) <= 0.0:
		if not target.is_empty() and absf(float(target["x"]) - float(foe["x"])) < 160.0:
			foe["face"] = 1 if float(target["x"]) > float(foe["x"]) else -1
		foe["vx"] = float(int(foe["face"])) * 64.0 * speed
		foe["vy"] = -250.0
		foe["ground"] = false
		foe["cool"] = 0.9 / speed
		world.emit("hop", float(foe["x"]), float(foe["y"]))

static func _step_frog(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	foe["vy"] = minf(320.0, float(foe["vy"]) + GRAVITY * delta)
	var hits: int = world.move_box(foe, float(foe["half"]), float(foe["tall"]), delta, true)
	var grounded: bool = (hits & world.ON_GROUND) != 0
	if (hits & world.HIT_WALL) != 0:
		foe["vx"] = -float(foe["vx"]) * 0.5
		foe["face"] = -int(foe["face"])
	if grounded and not bool(foe["ground"]):
		foe["vx"] = 0.0
		foe["cool"] = 1.1 / speed
	foe["ground"] = grounded
	if grounded and float(foe["cool"]) <= 0.0:
		var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
		var far := true
		if not target.is_empty() and absf(float(target["x"]) - float(foe["x"])) < 150.0 and absf(float(target["y"]) - float(foe["y"])) < 60.0:
			foe["face"] = 1 if float(target["x"]) > float(foe["x"]) else -1
			far = false
		else:
			# Out of sight it stays near its pond: hop back towards home.
			var home: Vector2 = foe["home"]
			if absf(float(foe["x"]) - home.x) > float(foe["reach"]):
				foe["face"] = 1 if home.x > float(foe["x"]) else -1
		foe["vx"] = float(int(foe["face"])) * (50.0 if far else 85.0) * speed
		foe["vy"] = -200.0 if far else -290.0
		foe["ground"] = false
		world.emit("hop", float(foe["x"]), float(foe["y"]))

static func _step_slime(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	match str(foe["mode"]):
		"cling":
			var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
			foe["y"] = (foe["home"] as Vector2).y + sin(float(foe["time"]) * 3.0) * 0.6
			if not target.is_empty() and absf(float(target["x"]) - float(foe["x"])) < 26.0 and float(target["y"]) > float(foe["y"]) and float(target["y"]) - float(foe["y"]) < 160.0:
				# It wobbles first, so whoever runs on gets past and whoever stops under it has a moment to move.
				foe["mode"] = "wobble"
				foe["aim"] = 0.4
				world.emit("drip", float(foe["x"]), float(foe["y"]))
		"wobble":
			foe["aim"] = float(foe["aim"]) - delta
			foe["y"] = (foe["home"] as Vector2).y + sin(float(foe["time"]) * 40.0) * 0.8
			if float(foe["aim"]) <= 0.0:
				foe["mode"] = "drop"
				foe["vy"] = 40.0
		"drop":
			foe["vx"] = 0.0
			var hits := _walk(world, foe, delta)
			if (hits & world.ON_GROUND) != 0:
				foe["mode"] = "walk"
				world.emit("splat", float(foe["x"]), float(foe["y"]))
		_:
			foe["vx"] = float(int(foe["face"])) * 20.0 * speed
			_walk(world, foe, delta)

static func _step_fly(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var home: Vector2 = foe["home"]
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	match str(foe["mode"]):
		"patrol":
			var x := float(foe["x"]) + float(int(foe["face"])) * 30.0 * speed * delta
			if absf(x - home.x) > float(foe["reach"]):
				foe["face"] = -int(foe["face"])
			foe["x"] = clampf(x, home.x - float(foe["reach"]), home.x + float(foe["reach"]))
			foe["y"] = home.y + sin(float(foe["time"]) * 4.0) * 6.0
			if float(foe["cool"]) <= 0.0 and not target.is_empty() and absf(float(target["x"]) - float(foe["x"])) < 96.0 and float(target["y"]) > float(foe["y"]) - 10.0 and float(target["y"]) - float(foe["y"]) < 110.0:
				foe["mode"] = "swoop"
				foe["aim"] = 1.1
				foe["goal"] = Vector2(float(target["x"]), float(target["y"]) - 8.0)
				foe["face"] = 1 if float(target["x"]) > float(foe["x"]) else -1
				world.emit("buzz", float(foe["x"]), float(foe["y"]))
		"swoop":
			foe["aim"] = float(foe["aim"]) - delta
			_fly_to(world, foe, foe["goal"], 95.0 * speed, delta)
			if float(foe["aim"]) <= 0.0 or (foe["goal"] as Vector2).distance_to(Vector2(float(foe["x"]), float(foe["y"]))) < 3.0:
				foe["mode"] = "back"
		_:
			if _fly_to(world, foe, home, 60.0 * speed, delta):
				foe["mode"] = "patrol"
				foe["cool"] = 1.4

## Fly straight towards a point, not through walls. Returns whether it got there.
static func _fly_to(world: Variant, foe: Dictionary, goal: Vector2, pace: float, delta: float) -> bool:
	var at := Vector2(float(foe["x"]), float(foe["y"]))
	var next := at.move_toward(goal, pace * delta)
	if world.is_solid(world.tile_at_point(next.x, next.y - float(foe["tall"]) * 0.5)):
		next = Vector2(at.x, next.y) if not world.is_solid(world.tile_at_point(at.x, next.y - float(foe["tall"]) * 0.5)) else at
	if next.x != at.x:
		foe["face"] = 1 if next.x > at.x else -1
	foe["x"] = next.x
	foe["y"] = next.y
	return next.distance_to(goal) < 1.0

static func _step_plane(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var home: Vector2 = foe["home"]
	if str(foe["mode"]) == "back":
		if _fly_to(world, foe, home, 70.0 * speed, delta):
			foe["mode"] = "patrol"
		return
	var x := float(foe["x"]) + float(int(foe["face"])) * 70.0 * speed * delta
	if absf(x - home.x) > float(foe["reach"]) or world.is_solid(world.tile_at_point(x + float(int(foe["face"])) * 12.0, float(foe["y"]) - 4.0)):
		foe["face"] = -int(foe["face"])
		x = clampf(x, home.x - float(foe["reach"]), home.x + float(foe["reach"]))
	foe["x"] = x
	# It dips at the middle of its beat and climbs at the ends.
	var along := (x - home.x) / maxf(1.0, float(foe["reach"]))
	foe["y"] = home.y + (1.0 - along * along) * 14.0

static func _step_hornet(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var home: Vector2 = foe["home"]
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	match str(foe["mode"]):
		"patrol":
			var t := float(foe["time"])
			foe["x"] = home.x + sin(t * 1.4) * float(foe["reach"]) * 0.6
			foe["y"] = home.y + sin(t * 2.8) * 8.0
			foe["face"] = 1 if cos(t * 1.4) > 0.0 else -1
			if float(foe["cool"]) <= 0.0 and not target.is_empty() and Vector2(float(target["x"]) - float(foe["x"]), float(target["y"]) - float(foe["y"])).length() < 120.0 and float(target["y"]) > float(foe["y"]) - 20.0:
				foe["mode"] = "aim"
				foe["aim"] = 0.45 / speed
				foe["face"] = 1 if float(target["x"]) > float(foe["x"]) else -1
				world.emit("buzz", float(foe["x"]), float(foe["y"]))
		"aim":
			foe["aim"] = float(foe["aim"]) - delta
			if not target.is_empty():
				foe["goal"] = Vector2(float(target["x"]), float(target["y"]) - 6.0)
			if float(foe["aim"]) <= 0.0:
				var from := Vector2(float(foe["x"]), float(foe["y"]))
				var way := ((foe["goal"] as Vector2) - from).normalized()
				foe["goal"] = from + way * 150.0
				foe["mode"] = "dive"
				foe["aim"] = 1.0
		"dive":
			foe["aim"] = float(foe["aim"]) - delta
			var before := Vector2(float(foe["x"]), float(foe["y"]))
			var arrived := _fly_to(world, foe, foe["goal"], 160.0 * speed, delta)
			if arrived or float(foe["aim"]) <= 0.0 or before == Vector2(float(foe["x"]), float(foe["y"])):
				foe["mode"] = "back"
		_:
			if _fly_to(world, foe, home, 70.0 * speed, delta):
				foe["mode"] = "patrol"
				foe["cool"] = 1.3
				foe["time"] = 0.0

static func _step_spider(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var home: Vector2 = foe["home"]
	var bottom := home.y + float(foe["reach"])
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	var y := float(foe["y"])
	var below := not target.is_empty() and absf(float(target["x"]) - float(foe["x"])) < 26.0 and float(target["y"]) > y - 4.0
	if str(foe["mode"]) == "climb":
		# Back up the thread after being knocked dizzy.
		foe["x"] = move_toward(float(foe["x"]), home.x, 40.0 * delta)
		foe["y"] = move_toward(y, home.y, 60.0 * delta)
		if absf(float(foe["y"]) - home.y) < 1.0:
			foe["mode"] = "patrol"
		return
	if below:
		foe["y"] = move_toward(y, minf(bottom, float(target["y"])), 130.0 * speed * delta)
	else:
		# Up and down its thread slowly while nobody is under it.
		var swing := (sin(float(foe["time"]) * 1.2) * 0.5 + 0.5) * float(foe["reach"]) * 0.5
		foe["y"] = move_toward(y, home.y + swing, 40.0 * delta)

## What happens when an enemy and a squirrel overlap: a thrown squirrel knocks it out, a squirrel landing on it from above leaves it dizzy, a hidden squirrel turns it away dizzy, anyone else is hurt.
static func _touch_heroes(world: Variant, foe: Dictionary) -> void:
	if int(foe["state"]) != ALIVE:
		return
	var x := float(foe["x"])
	var y := float(foe["y"])
	var top := y - float(foe["tall"])
	for hero: Dictionary in world.heroes:
		var state := int(hero["state"])
		if state != world.H_NORMAL and state != world.H_THROWN:
			continue
		var hx := float(hero["x"])
		var hy := float(hero["y"])
		if absf(hx - x) >= float(foe["half"]) + world.HERO_HALF - 1.0 or hy - world.HERO_TALL >= y or hy <= top:
			continue
		if state == world.H_THROWN:
			knock_out(world, foe, int(hero["by"]), signf(float(hero["vx"])) if float(hero["vx"]) != 0.0 else 1.0, true)
			world._end_flight(hero, true)
			return
		if float(hero["vy"]) > 30.0 and hy - float(hero["vy"]) / 60.0 <= top + 3.0:
			stun(world, foe, world.STOMP_STUN, 1.0 if x >= hx else -1.0)
			hero["vy"] = -250.0
			hero["jumping"] = false
			hero["ground"] = false
			world.emit("stomp", x, top, {"slot": int(hero["slot"])})
			return
		if bool(hero["hide"]):
			var away := 1.0 if x > hx else -1.0
			foe["x"] = hx + away * (float(foe["half"]) + world.HERO_HALF + 1.0)
			stun(world, foe, world.STUN_TIME, away)
			world.emit("bonk", x, y - 6.0)
			return
		world.hurt_hero(hero, x)

## Leave an enemy dizzy, knocked a little away from where it was hit.
static func stun(world: Variant, foe: Dictionary, seconds: float, away: float) -> void:
	foe["state"] = STUNNED
	foe["stun"] = seconds
	foe["vx"] = away * 90.0
	foe["vy"] = -150.0
	foe["ground"] = false
	foe["flash"] = 0.15
	if str(foe["kind"]) == "jack" and str(foe["mode"]) == "box":
		foe["mode"] = "hop"
		foe["tall"] = 22.0
	world.emit("dizzy", float(foe["x"]), float(foe["y"]) - float(foe["tall"]))

## Something thrown by player `slot` reached this enemy: it is out, whatever it was. Returns false when it was already out.
static func knock_out(world: Variant, foe: Dictionary, slot: int, direction: float, by_buddy: bool) -> bool:
	if int(foe["state"]) == KNOCKED_OUT:
		return false
	foe["state"] = KNOCKED_OUT
	foe["time"] = 0.0
	foe["flash"] = 0.15
	foe["vx"] = direction * 80.0
	foe["vy"] = -220.0
	world.emit("foe_out", float(foe["x"]), float(foe["y"]) - 8.0, {"kind": str(foe["kind"])})
	world.foe_beaten(foe, slot, by_buddy)
	return true

## Pepper, and whatever a boss throws or drops: fly, hit squirrels, stop at walls. A boss's lump that lands turns into something a squirrel can pick up and throw back.
static func step_shots(world: Variant, delta: float) -> void:
	for shot: Dictionary in world.shots:
		if bool(shot["gone"]):
			continue
		shot["time"] = float(shot["time"]) + delta
		shot["vy"] = minf(420.0, float(shot["vy"]) + float(shot["g"]) * delta)
		shot["x"] = float(shot["x"]) + float(shot["vx"]) * delta
		shot["y"] = float(shot["y"]) + float(shot["vy"]) * delta
		var x := float(shot["x"])
		var y := float(shot["y"])
		var kind := str(shot["kind"])
		if not world.is_active_at(x, y) or float(shot["time"]) > float(shot.get("life", 8.0)):
			shot["gone"] = true
			if float(shot["time"]) > float(shot.get("life", 8.0)):
				world.emit("poof", x, y, {"kind": kind})
			continue
		var special: bool = world.THINGS.has(kind)
		var tile: int = world.tile_at_point(x, y + 3.0)
		var landed: bool = world.is_solid(tile) or (float(shot["vy"]) > 0.0 and tile == world.Levels.SHELF and fmod(y + 3.0, 16.0) < 6.0)
		if landed or world.is_solid(world.tile_at_point(x + signf(float(shot["vx"])) * 4.0, y)):
			shot["gone"] = true
			if special and landed:
				var object: Dictionary = world.add_object(kind, x, floorf((y + 3.0) / 16.0) * 16.0)
				object["special"] = true
				object["life"] = 10.0
				world.emit("thud", x, y, {"kind": kind})
			else:
				world.emit("poof", x, y, {"kind": kind})
			continue
		var reach := 6.0 if special else 4.0
		for hero: Dictionary in world.heroes:
			if int(hero["state"]) != world.H_NORMAL:
				continue
			if absf(float(hero["x"]) - x) < reach + world.HERO_HALF and y > float(hero["y"]) - world.HERO_TALL - reach and y < float(hero["y"]) + reach:
				if bool(hero["hide"]):
					shot["gone"] = true
					world.emit("clang", x, y)
					if special:
						var object: Dictionary = world.add_object(kind, float(hero["x"]) + signf(float(shot["vx"])) * 14.0, float(hero["y"]))
						object["special"] = true
						object["life"] = 10.0
				elif world.hurt_hero(hero, x - float(shot["vx"]) * 0.01):
					shot["gone"] = true
					world.emit("poof", x, y, {"kind": kind})
				break
