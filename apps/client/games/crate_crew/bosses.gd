extends RefCounted

## The four bosses, one at the end of each place. Nothing the squirrels find lying about hurts them: each boss throws or drops its own kind of lump into the room, the lump lands and can be picked up, and only that thrown back hurts it. Every attack is announced by a tell (a shake, a glow, a raised claw, a caw) long enough to react to. Each boss has three phases of equal health; between phases it rages for a moment, cannot be hurt and adds to what it does. Static functions on the world they are handed, like foes.gd.
##
##   toaster   (kitchen)   walks at the squirrels and pops slices of toast high into the air; from phase two it crouches and leaps at them, in phase three it spits hot crumbs and its landings send crumbs skidding along the floor
##   robot     (toy shop)  a tall wind-up tin robot that lobs brass cogs; from phase two it winds up and charges across the room and stands dazed after hitting the wall, in phase three it lobs two cogs at once
##   crayfish  (sewer)     snaps its claws at anyone in front of it and lobs rusty cans; from phase two it dives under the water and bursts up under a squirrel where bubbles rise, in phase three it also blows bubbles that float up
##   crow      (treehouse) flies over the room and drops pinecones, lands to gloat on a perch now and then; from phase two it dives straight at a squirrel after marking it, in phase three it also throws a fan of sharp feathers

const MISS := 0
const HURT := 1
const DEFLECTED := 2

## Half width and height of each boss's body (feet in the middle of its bottom edge), and what it throws.
const BODIES := {
	"toaster": {"half": 24.0, "tall": 46.0, "lump": "toast"},
	"robot": {"half": 16.0, "tall": 70.0, "lump": "cog"},
	"crayfish": {"half": 38.0, "tall": 34.0, "lump": "can"},
	"crow": {"half": 18.0, "tall": 28.0, "lump": "pinecone"},
}

const ARENA_LEFT := 16.0
const ARENA_RIGHT := 368.0
const FLOOR := 192.0
## How high the crow flies, as the height of its feet.
const SKY := 92.0

static func create(world: Variant, spec: Dictionary) -> Dictionary:
	var kind := str(spec["kind"])
	var per := int(world.rules["boss"])
	var boss := {
		"kind": kind, "x": ARENA_RIGHT - 70.0, "y": FLOOR, "vx": 0.0, "vy": 0.0, "face": -1, "phase": 1, "per_phase": per, "max_hp": per * 3, "hp": per * 3,
		"mode": "enter", "time": 1.6, "flash": 0.0, "inv": 0.0, "alive": true, "shake": 0.0, "count": 0, "goal": Vector2.ZERO, "left": ARENA_LEFT, "right": ARENA_RIGHT,
		"floor": FLOOR, "lumps": 0, "half": float(BODIES[kind]["half"]), "tall": float(BODIES[kind]["tall"]), "hidden": false, "glow": 0.0,
	}
	if kind == "crow":
		boss["x"] = ARENA_RIGHT + 40.0
		boss["y"] = SKY - 30.0
	if kind == "toaster":
		boss["y"] = FLOOR - 120.0
	return boss

static func step(world: Variant, delta: float) -> void:
	var boss: Dictionary = world.boss
	if world.phase != world.P_PLAY and world.phase != world.P_INTRO:
		return
	boss["flash"] = maxf(0.0, float(boss["flash"]) - delta)
	boss["inv"] = maxf(0.0, float(boss["inv"]) - delta)
	boss["time"] = float(boss["time"]) - delta
	boss["shake"] = maxf(0.0, float(boss["shake"]) - delta)
	var mode := str(boss["mode"])
	if mode == "dying":
		boss["count"] = int(boss["count"]) + 1
		if int(boss["count"]) % 9 == 0:
			world.emit("boss_burst", float(boss["x"]) + world.rng.float_range(-20.0, 20.0), float(boss["y"]) - world.rng.float_range(4.0, float(boss["tall"])))
		boss["vy"] = minf(300.0, float(boss["vy"]) + 600.0 * delta) if str(boss["kind"]) == "crow" else 0.0
		boss["y"] = minf(FLOOR, float(boss["y"]) + float(boss["vy"]) * delta)
		if float(boss["time"]) <= 0.0 and bool(boss["alive"]):
			boss["alive"] = false
			boss["mode"] = "gone"
			world.emit("boss_down", float(boss["x"]), float(boss["y"]) - 16.0)
			world.boss_beaten()
		return
	if not bool(boss["alive"]):
		return
	if world.phase == world.P_INTRO:
		_enter(world, boss, delta)
		return
	if mode == "enter":
		_enter(world, boss, delta)
		if float(boss["time"]) <= 0.0:
			_choose(world, boss)
		return
	if mode == "rage":
		boss["shake"] = 0.2
		if float(boss["time"]) <= 0.0:
			_choose(world, boss)
		_touch(world, boss)
		return
	match str(boss["kind"]):
		"toaster":
			_step_toaster(world, boss, delta)
		"robot":
			_step_robot(world, boss, delta)
		"crayfish":
			_step_crayfish(world, boss, delta)
		_:
			_step_crow(world, boss, delta)
	_touch(world, boss)

## The way in: the toaster drops from the counter above, the crow flies in, the others are already there.
static func _enter(world: Variant, boss: Dictionary, delta: float) -> void:
	match str(boss["kind"]):
		"toaster":
			var before := float(boss["y"])
			boss["vy"] = float(boss["vy"]) + 900.0 * delta
			boss["y"] = minf(FLOOR, before + float(boss["vy"]) * delta)
			if before < FLOOR and float(boss["y"]) >= FLOOR:
				boss["vy"] = 0.0
				world.emit("boss_slam", float(boss["x"]), FLOOR)
		"crow":
			var goal := Vector2(ARENA_RIGHT - 80.0, SKY)
			var at := Vector2(float(boss["x"]), float(boss["y"])).move_toward(goal, 140.0 * delta)
			boss["x"] = at.x
			boss["y"] = at.y

static func _target(world: Variant, boss: Dictionary) -> Dictionary:
	return world.nearest_hero(float(boss["x"]), float(boss["y"]))

static func _target_x(world: Variant, boss: Dictionary) -> float:
	var target := _target(world, boss)
	return float(target["x"]) if not target.is_empty() else (ARENA_LEFT + ARENA_RIGHT) * 0.5

## Where a walking boss heads: towards the nearest squirrel, but it stops `gap` short of it, so nobody is pinned in a corner.
static func _keep_off(world: Variant, boss: Dictionary, gap: float) -> float:
	var target := _target_x(world, boss)
	var x := float(boss["x"])
	var reach := float(boss["half"]) + gap
	if absf(target - x) <= reach:
		return x
	return target - signf(target - x) * reach

static func _speed(world: Variant) -> float:
	return float(world.rules["speed"])

## How many of its lumps are about: flying, lying or carried.
static func _lumps(world: Variant, boss: Dictionary) -> int:
	var lump := str(BODIES[str(boss["kind"])]["lump"])
	var count := 0
	for shot: Dictionary in world.shots:
		if str(shot["kind"]) == lump and not bool(shot["gone"]):
			count += 1
	for object: Dictionary in world.objects:
		if bool(object["special"]) and not bool(object["gone"]):
			count += 1
	return count

## Throw a lump in an arc that comes down at `land_x`, taking `seconds` in the air.
static func _lob(world: Variant, boss: Dictionary, from: Vector2, land_x: float, seconds: float) -> void:
	var lump := str(BODIES[str(boss["kind"])]["lump"])
	var gravity := 900.0
	var land := clampf(land_x, ARENA_LEFT + 16.0, ARENA_RIGHT - 16.0)
	var vy := (FLOOR - from.y - 0.5 * gravity * seconds * seconds) / seconds
	world.add_shot(lump, from.x, from.y, (land - from.x) / seconds, vy, gravity)

## Pick the next move after a pause; each boss works through its own list, which grows with the phase.
static func _choose(world: Variant, boss: Dictionary) -> void:
	var phase := int(boss["phase"])
	var turn := int(boss["count"])
	boss["count"] = turn + 1
	var plan: Array = []
	match str(boss["kind"]):
		"toaster":
			plan = [["walk", 1.4], ["pop_tell", 0.6]] if phase == 1 else ([["walk", 1.0], ["pop_tell", 0.5], ["walk", 0.8], ["hop_tell", 0.55]] if phase == 2 else [["walk", 0.7], ["pop_tell", 0.45], ["hop_tell", 0.5], ["crumb_tell", 0.45]])
		"robot":
			plan = [["walk", 1.6], ["throw_tell", 0.6]] if phase == 1 else ([["walk", 1.2], ["throw_tell", 0.55], ["walk", 0.8], ["charge_tell", 0.75]] if phase == 2 else [["walk", 0.8], ["throw_tell", 0.5], ["charge_tell", 0.6], ["throw_tell", 0.5]])
		"crayfish":
			plan = [["walk", 1.6], ["can_tell", 0.6]] if phase == 1 else ([["walk", 1.2], ["can_tell", 0.55], ["dive_tell", 0.6]] if phase == 2 else [["walk", 0.8], ["can_tell", 0.5], ["dive_tell", 0.5], ["bubble_tell", 0.5]])
		_:
			plan = [["hover", 1.6], ["drop_tell", 0.5], ["hover", 1.2], ["perch", 0.0]] if phase == 1 else ([["hover", 1.2], ["drop_tell", 0.45], ["dive_tell", 0.65], ["perch", 0.0]] if phase == 2 else [["hover", 0.9], ["drop_tell", 0.4], ["dive_tell", 0.55], ["feather_tell", 0.45], ["perch", 0.0]])
	var pick: Array = plan[turn % plan.size()]
	var mode := str(pick[0])
	# A boss that has no lump in the room makes one first, so the fight never stalls.
	if mode.ends_with("_tell") and mode != "drop_tell" and mode != "pop_tell" and mode != "throw_tell" and mode != "can_tell" and _lumps(world, boss) == 0:
		mode = {"toaster": "pop_tell", "robot": "throw_tell", "crayfish": "can_tell", "crow": "drop_tell"}[str(boss["kind"])]
	boss["mode"] = mode
	boss["time"] = float(pick[1]) / maxf(0.8, _speed(world)) if float(pick[1]) > 0.0 else 0.0
	if mode.ends_with("_tell"):
		boss["glow"] = 1.0
		world.emit("boss_tell", float(boss["x"]), float(boss["y"]) - float(boss["tall"]), {"move": mode.trim_suffix("_tell")})
	if mode == "perch":
		var spots: Array[Vector2] = [Vector2(72.0, 160.0), Vector2(312.0, 160.0), Vector2(192.0, FLOOR)]
		boss["goal"] = spots[world.rng.int_range(0, spots.size() - 1)]
		boss["time"] = 6.0

# ---- the toaster ----

static func _step_toaster(world: Variant, boss: Dictionary, delta: float) -> void:
	var phase := int(boss["phase"])
	var speed := _speed(world)
	match str(boss["mode"]):
		"walk":
			var goal := _keep_off(world, boss, 64.0)
			boss["face"] = 1 if _target_x(world, boss) > float(boss["x"]) else -1
			boss["x"] = clampf(move_toward(float(boss["x"]), goal, (22.0 + 10.0 * float(phase)) * speed * delta), ARENA_LEFT + 30.0, ARENA_RIGHT - 30.0)
			if float(boss["time"]) <= 0.0:
				_choose(world, boss)
		"pop_tell":
			boss["shake"] = 0.1
			if float(boss["time"]) <= 0.0:
				var count := 1 if phase == 1 else 2
				if _lumps(world, boss) >= 3:
					count = 0
				for index in count:
					var land: float = _target_x(world, boss) + world.rng.float_range(-70.0, 70.0) if index == 0 else world.rng.float_range(ARENA_LEFT + 30.0, ARENA_RIGHT - 30.0)
					_lob(world, boss, Vector2(float(boss["x"]), float(boss["y"]) - 44.0), land, 1.15)
				world.emit("boss_pop", float(boss["x"]), float(boss["y"]) - 44.0)
				boss["mode"] = "pause"
				boss["time"] = 0.6
		"hop_tell":
			boss["shake"] = 0.1
			if float(boss["time"]) <= 0.0:
				var goal := clampf(_target_x(world, boss), ARENA_LEFT + 30.0, ARENA_RIGHT - 30.0)
				boss["mode"] = "hop"
				boss["vy"] = -430.0
				boss["vx"] = clampf((goal - float(boss["x"])) / 0.72, -260.0, 260.0)
				boss["face"] = 1 if float(boss["vx"]) > 0.0 else -1
				world.emit("boss_jump", float(boss["x"]), float(boss["y"]))
		"hop":
			boss["vy"] = float(boss["vy"]) + 1200.0 * delta
			boss["x"] = clampf(float(boss["x"]) + float(boss["vx"]) * delta, ARENA_LEFT + 26.0, ARENA_RIGHT - 26.0)
			boss["y"] = float(boss["y"]) + float(boss["vy"]) * delta
			if float(boss["y"]) >= FLOOR and float(boss["vy"]) > 0.0:
				boss["y"] = FLOOR
				boss["vy"] = 0.0
				world.emit("boss_slam", float(boss["x"]), FLOOR)
				if phase >= 3:
					for side: float in [-1.0, 1.0]:
						var crumb: Dictionary = world.add_shot("crumb", float(boss["x"]) + side * 26.0, FLOOR - 5.0, side * 130.0, 0.0, 0.0)
						crumb["life"] = 2.6
				boss["mode"] = "pause"
				boss["time"] = 0.7
		"crumb_tell":
			if float(boss["time"]) <= 0.0:
				var face := float(int(boss["face"]))
				for index in 3:
					world.add_shot("crumb", float(boss["x"]) + face * 20.0, float(boss["y"]) - 30.0, face * (70.0 + 45.0 * float(index)), -170.0, 700.0)
				world.emit("boss_spit", float(boss["x"]), float(boss["y"]) - 30.0)
				boss["mode"] = "pause"
				boss["time"] = 0.6
		_:
			if float(boss["time"]) <= 0.0:
				_choose(world, boss)

# ---- the robot ----

static func _step_robot(world: Variant, boss: Dictionary, delta: float) -> void:
	var phase := int(boss["phase"])
	var speed := _speed(world)
	match str(boss["mode"]):
		"walk":
			var goal := _keep_off(world, boss, 72.0)
			boss["face"] = 1 if _target_x(world, boss) > float(boss["x"]) else -1
			boss["x"] = clampf(move_toward(float(boss["x"]), goal, (20.0 + 8.0 * float(phase)) * speed * delta), ARENA_LEFT + 24.0, ARENA_RIGHT - 24.0)
			if float(boss["time"]) <= 0.0:
				_choose(world, boss)
		"throw_tell":
			boss["face"] = 1 if _target_x(world, boss) > float(boss["x"]) else -1
			if float(boss["time"]) <= 0.0:
				var hand := Vector2(float(boss["x"]) - float(int(boss["face"])) * 6.0, float(boss["y"]) - 76.0)
				if _lumps(world, boss) < 3:
					_lob(world, boss, hand, _target_x(world, boss), 0.95)
					if phase >= 3:
						_lob(world, boss, hand, world.rng.float_range(ARENA_LEFT + 30.0, ARENA_RIGHT - 30.0), 1.2)
				world.emit("boss_throw", hand.x, hand.y)
				boss["mode"] = "pause"
				boss["time"] = 0.5
		"charge_tell":
			boss["shake"] = 0.1
			boss["face"] = 1 if _target_x(world, boss) > float(boss["x"]) else -1
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "charge"
				world.emit("boss_charge", float(boss["x"]), float(boss["y"]))
		"charge":
			var face := float(int(boss["face"]))
			var x := float(boss["x"]) + face * (190.0 + 30.0 * float(phase)) * speed * delta
			var stop := ARENA_RIGHT - 18.0 if face > 0.0 else ARENA_LEFT + 18.0
			if (face > 0.0 and x >= stop) or (face < 0.0 and x <= stop):
				x = stop
				boss["mode"] = "dazed"
				boss["time"] = 1.3
				world.emit("boss_slam", x + face * 16.0, float(boss["y"]) - 30.0)
			boss["x"] = x
		_:
			if float(boss["time"]) <= 0.0:
				_choose(world, boss)

# ---- the crayfish ----

static func _step_crayfish(world: Variant, boss: Dictionary, delta: float) -> void:
	var phase := int(boss["phase"])
	var speed := _speed(world)
	var target := _target(world, boss)
	match str(boss["mode"]):
		"walk":
			var goal := clampf(_keep_off(world, boss, 50.0), ARENA_LEFT + 40.0, ARENA_RIGHT - 40.0)
			boss["face"] = 1 if _target_x(world, boss) > float(boss["x"]) else -1
			boss["x"] = move_toward(float(boss["x"]), goal, (18.0 + 8.0 * float(phase)) * speed * delta)
			# Anyone who comes right up to the claws gets snapped at.
			if not target.is_empty() and absf(float(target["x"]) - float(boss["x"])) < float(boss["half"]) + 30.0 and float(target["y"]) > FLOOR - 24.0:
				boss["face"] = 1 if float(target["x"]) > float(boss["x"]) else -1
				boss["mode"] = "snap_tell"
				boss["time"] = 0.45 / speed
				boss["glow"] = 1.0
				world.emit("boss_tell", float(boss["x"]), float(boss["y"]) - 30.0, {"move": "snap"})
			elif float(boss["time"]) <= 0.0:
				_choose(world, boss)
		"snap_tell":
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "snap"
				boss["time"] = 0.28
				world.emit("boss_snap", float(boss["x"]) + float(int(boss["face"])) * 44.0, float(boss["y"]) - 14.0)
		"snap":
			var front := float(boss["x"]) + float(int(boss["face"])) * 40.0
			for hero: Dictionary in world.heroes:
				if int(hero["state"]) == world.H_NORMAL and absf(float(hero["x"]) - front) < 22.0 and float(hero["y"]) > FLOOR - 20.0:
					world.hurt_hero(hero, float(boss["x"]), true)
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "pause"
				boss["time"] = 0.7
		"can_tell":
			if float(boss["time"]) <= 0.0:
				var count := 1 if phase < 3 else 2
				for index in count:
					if _lumps(world, boss) < 3:
						_lob(world, boss, Vector2(float(boss["x"]), float(boss["y"]) - 34.0), _target_x(world, boss) + (0.0 if index == 0 else world.rng.float_range(-90.0, 90.0)), 1.0)
				world.emit("boss_throw", float(boss["x"]), float(boss["y"]) - 34.0)
				boss["mode"] = "pause"
				boss["time"] = 0.6
		"dive_tell":
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "under"
				boss["hidden"] = true
				boss["time"] = 0.8
				world.emit("boss_dive", float(boss["x"]), FLOOR)
		"under":
			boss["x"] = move_toward(float(boss["x"]), clampf(_target_x(world, boss), ARENA_LEFT + 40.0, ARENA_RIGHT - 40.0), 260.0 * delta)
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "rise_tell"
				boss["time"] = 0.75 / speed
				boss["glow"] = 1.0
				world.emit("boss_tell", float(boss["x"]), FLOOR, {"move": "rise"})
		"rise_tell":
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "rise"
				boss["hidden"] = false
				boss["time"] = 0.3
				world.emit("boss_slam", float(boss["x"]), FLOOR)
				for hero: Dictionary in world.heroes:
					if int(hero["state"]) == world.H_NORMAL and absf(float(hero["x"]) - float(boss["x"])) < 34.0 and float(hero["y"]) > FLOOR - 40.0:
						world.hurt_hero(hero, float(boss["x"]), true)
		"bubble_tell":
			if float(boss["time"]) <= 0.0:
				for index in 3:
					var bubble: Dictionary = world.add_shot("bubble", float(boss["x"]) + float(index - 1) * 26.0, FLOOR - 20.0, world.rng.float_range(-25.0, 25.0), -55.0, 0.0)
					bubble["life"] = 3.2
				world.emit("boss_spit", float(boss["x"]), FLOOR - 20.0)
				boss["mode"] = "pause"
				boss["time"] = 0.5
		_:
			if float(boss["time"]) <= 0.0:
				_choose(world, boss)

# ---- the crow ----

static func _step_crow(world: Variant, boss: Dictionary, delta: float) -> void:
	var phase := int(boss["phase"])
	var speed := _speed(world)
	var at := Vector2(float(boss["x"]), float(boss["y"]))
	match str(boss["mode"]):
		"hover":
			var goal := Vector2(clampf(_target_x(world, boss) + sin(float(world.level_time) * 1.3) * 60.0, ARENA_LEFT + 30.0, ARENA_RIGHT - 30.0), SKY + sin(float(world.level_time) * 2.1) * 8.0)
			var next := at.move_toward(goal, (60.0 + 20.0 * float(phase)) * speed * delta)
			if absf(next.x - at.x) > 0.05:
				boss["face"] = 1 if next.x > at.x else -1
			boss["x"] = next.x
			boss["y"] = next.y
			if float(boss["time"]) <= 0.0:
				_choose(world, boss)
		"drop_tell":
			if float(boss["time"]) <= 0.0:
				if _lumps(world, boss) < 3:
					world.add_shot("pinecone", float(boss["x"]), float(boss["y"]) + 4.0, 0.0, 40.0, 900.0)
				world.emit("boss_drop", float(boss["x"]), float(boss["y"]))
				boss["mode"] = "pause"
				boss["time"] = 0.4
		"dive_tell":
			var target := _target(world, boss)
			if not target.is_empty():
				boss["goal"] = Vector2(float(target["x"]), FLOOR)
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "dive"
				var way := ((boss["goal"] as Vector2) - at)
				boss["goal"] = at + way.normalized() * maxf(way.length(), 60.0)
				boss["face"] = 1 if way.x > 0.0 else -1
				world.emit("boss_charge", float(boss["x"]), float(boss["y"]))
		"dive":
			var goal: Vector2 = boss["goal"]
			goal.y = minf(goal.y, FLOOR)
			var next := at.move_toward(goal, (230.0 + 30.0 * float(phase)) * speed * delta)
			next.x = clampf(next.x, ARENA_LEFT + 20.0, ARENA_RIGHT - 20.0)
			boss["x"] = next.x
			boss["y"] = next.y
			if next.distance_to(goal) < 2.0 or next.y >= FLOOR - 0.5 or next == at:
				boss["mode"] = "low"
				boss["time"] = 0.7
				world.emit("boss_slam", next.x, next.y)
		"low":
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "climb"
		"climb":
			var next := at.move_toward(Vector2(at.x, SKY), 130.0 * delta)
			boss["x"] = next.x
			boss["y"] = next.y
			if absf(next.y - SKY) < 1.0:
				_choose(world, boss)
		"perch":
			var goal: Vector2 = boss["goal"]
			if at.distance_to(goal) > 1.0:
				var next := at.move_toward(goal, 130.0 * delta)
				if absf(next.x - at.x) > 0.05:
					boss["face"] = 1 if next.x > at.x else -1
				boss["x"] = next.x
				boss["y"] = next.y
				if next.distance_to(goal) <= 1.0:
					boss["time"] = 1.8 / speed
					world.emit("boss_land", next.x, next.y)
			elif float(boss["time"]) <= 0.0 or float(boss["time"]) > 3.0:
				boss["mode"] = "climb"
				world.emit("boss_flap", at.x, at.y)
		"feather_tell":
			if float(boss["time"]) <= 0.0:
				for index in 3:
					var angle := PI * 0.5 + float(index - 1) * 0.42
					world.add_shot("feather", float(boss["x"]), float(boss["y"]) - 10.0, cos(angle) * 150.0, sin(angle) * 150.0, 0.0)
				world.emit("boss_spit", float(boss["x"]), float(boss["y"]) - 10.0)
				boss["mode"] = "pause"
				boss["time"] = 0.5
		_:
			if float(boss["time"]) <= 0.0:
				_choose(world, boss)

# ---- touching and being hit ----

## The boss's body as a rectangle in stage pixels.
static func body(boss: Dictionary) -> Rect2:
	var half := float(boss["half"])
	var tall := float(boss["tall"])
	return Rect2(float(boss["x"]) - half, float(boss["y"]) - tall, half * 2.0, tall)

## Touching a boss hurts, crate or no crate, except while it is under the water.
static func _touch(world: Variant, boss: Dictionary) -> void:
	if bool(boss["hidden"]):
		return
	var box := body(boss).grow(-3.0)
	for hero: Dictionary in world.heroes:
		if int(hero["state"]) != world.H_NORMAL:
			continue
		var hero_box := Rect2(float(hero["x"]) - world.HERO_HALF, float(hero["y"]) - world.HERO_TALL, world.HERO_HALF * 2.0, world.HERO_TALL)
		if box.intersects(hero_box):
			world.hurt_hero(hero, float(boss["x"]), true)

## Whether its own lump thrown back hurts it now.
static func is_open(boss: Dictionary) -> bool:
	var mode := str(boss["mode"])
	return bool(boss["alive"]) and float(boss["inv"]) <= 0.0 and mode != "enter" and mode != "rage" and mode != "dying" and mode != "gone" and not bool(boss["hidden"])

## A thrown thing reached the room's boss. Returns MISS, HURT or DEFLECTED.
static func take_throw(world: Variant, object: Dictionary) -> int:
	var boss: Dictionary = world.boss
	if not bool(boss["alive"]) or bool(boss["hidden"]) or str(boss["mode"]) == "dying":
		return MISS
	var thing := Rect2(float(object["x"]) - float(object["half"]), float(object["y"]) - float(object["tall"]), float(object["half"]) * 2.0, float(object["tall"]))
	if not body(boss).intersects(thing):
		return MISS
	if not bool(object["special"]) or not is_open(boss):
		world.emit("clang", float(object["x"]), float(object["y"]) - 8.0)
		return DEFLECTED
	boss["hp"] = int(boss["hp"]) - 1
	boss["flash"] = 0.3
	boss["inv"] = 0.35
	world.emit("boss_hit", float(object["x"]), float(object["y"]) - 8.0)
	if int(boss["hp"]) <= 0:
		boss["mode"] = "dying"
		boss["time"] = 2.2
		boss["count"] = 0
		boss["vy"] = 0.0
		boss["shake"] = 2.2
		for shot: Dictionary in world.shots:
			shot["gone"] = true
		for foe: Dictionary in world.foes:
			if int(foe["state"]) != world.Foes.KNOCKED_OUT:
				world.Foes.knock_out(world, foe, -1, 1.0, false)
		return HURT
	var phase := 1 + (int(boss["max_hp"]) - int(boss["hp"])) / int(boss["per_phase"])
	if phase > int(boss["phase"]):
		boss["phase"] = phase
		boss["mode"] = "rage"
		boss["time"] = 1.2
		boss["hidden"] = false
		boss["count"] = 0
		for shot: Dictionary in world.shots:
			if not world.THINGS.has(str(shot["kind"])):
				shot["gone"] = true
		world.emit("boss_rage", float(boss["x"]), float(boss["y"]) - float(boss["tall"]), {"phase": phase})
	return HURT
