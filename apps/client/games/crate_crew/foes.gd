extends RefCounted

## The workshop's runaway gadgets and what they shoot. Every function is static and works on the world it is handed (world.gd), so the two scripts do not hold each other.
##
##   bug     a wind-up beetle that walks its ledge back and forth
##   hopper  a spring that jumps at the nearest robot
##   drone   a little saw that flies a wavy line and is best hit from below
##   turret  a weld gun that fires sparks along the floor
##   roller  an armoured drum that charges when it sees a robot; two hits, or one with a steel crate
##   magnet  a flying magnet that drops nuts on whoever walks under it

const ALIVE := 0
const KNOCKED_OUT := 1

const GRAVITY := 720.0

const KINDS := {
	"bug": {"half": 7.0, "tall": 10.0, "hp": 1, "points": 100},
	"hopper": {"half": 5.0, "tall": 12.0, "hp": 1, "points": 150},
	"drone": {"half": 6.0, "tall": 9.0, "hp": 1, "points": 150},
	"turret": {"half": 6.0, "tall": 13.0, "hp": 1, "points": 200},
	"roller": {"half": 7.0, "tall": 14.0, "hp": 2, "points": 300},
	"magnet": {"half": 7.0, "tall": 13.0, "hp": 1, "points": 250},
}

static func create(spec: Dictionary) -> Dictionary:
	var kind := str(spec["kind"])
	var data: Dictionary = KINDS[kind]
	var at: Vector2 = spec["at"]
	return {
		"kind": kind, "x": at.x, "y": at.y, "vx": 0.0, "vy": 0.0, "face": int(spec.get("face", -1)), "hp": int(data["hp"]), "points": int(data["points"]),
		"half": float(data["half"]), "tall": float(data["tall"]), "state": ALIVE, "time": 0.0, "home": at, "reach": float(spec.get("reach", 64.0)),
		"flash": 0.0, "cool": 1.0, "mode": "walk", "ground": false, "gone": false,
	}

static func step(world: Variant, foe: Dictionary, delta: float) -> void:
	foe["time"] = float(foe["time"]) + delta
	if int(foe["state"]) == KNOCKED_OUT:
		foe["vy"] = float(foe["vy"]) + GRAVITY * delta
		foe["x"] = float(foe["x"]) + float(foe["vx"]) * delta
		foe["y"] = float(foe["y"]) + float(foe["vy"]) * delta
		if float(foe["time"]) > 1.3:
			foe["gone"] = true
		return
	foe["flash"] = maxf(0.0, float(foe["flash"]) - delta)
	foe["cool"] = maxf(0.0, float(foe["cool"]) - delta)
	var speed := float(world.rules["speed"])
	match str(foe["kind"]):
		"bug":
			foe["vx"] = float(int(foe["face"])) * 26.0 * speed
			_walk(world, foe, delta)
		"hopper":
			_step_hopper(world, foe, delta, speed)
		"drone":
			_step_drone(world, foe, delta, speed)
		"turret":
			_step_turret(world, foe, delta, speed)
		"roller":
			_step_roller(world, foe, delta, speed)
		"magnet":
			_step_magnet(world, foe, delta, speed)
	_touch_heroes(world, foe)

## Walk along the floor and turn round at walls, at the end of a ledge and at crates. Returns the move flags.
static func _walk(world: Variant, foe: Dictionary, delta: float) -> int:
	foe["vy"] = minf(300.0, float(foe["vy"]) + GRAVITY * delta)
	var flags: int = world.move_box(foe, float(foe["half"]), float(foe["tall"]), delta, true)
	foe["ground"] = (flags & world.ON_GROUND) != 0
	var facing := int(foe["face"])
	var turn: bool = (flags & world.HIT_WALL) != 0
	if bool(foe["ground"]) and float(foe["vx"]) != 0.0:
		var ahead := float(foe["x"]) + float(facing) * (float(foe["half"]) + 2.0)
		if not world.is_floor(ahead, float(foe["y"]) + 2.0) or world.crate_at(ahead, float(foe["y"]) - 4.0):
			turn = true
	if turn:
		foe["face"] = -facing
	return flags | (8 if turn else 0)

static func _step_hopper(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	foe["vy"] = minf(300.0, float(foe["vy"]) + GRAVITY * delta)
	var flags: int = world.move_box(foe, float(foe["half"]), float(foe["tall"]), delta, true)
	var grounded: bool = (flags & world.ON_GROUND) != 0
	if (flags & world.HIT_WALL) != 0:
		foe["vx"] = -float(foe["vx"])
	if grounded and not bool(foe["ground"]):
		foe["cool"] = 1.1 / speed
		foe["vx"] = 0.0
	foe["ground"] = grounded
	if grounded and float(foe["cool"]) <= 0.0:
		var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
		if not target.is_empty() and absf(float(target["x"]) - float(foe["x"])) < 150.0:
			foe["face"] = 1 if float(target["x"]) > float(foe["x"]) else -1
		foe["vx"] = float(int(foe["face"])) * 56.0 * speed
		foe["vy"] = -215.0
		foe["ground"] = false
		world.emit("hop", float(foe["x"]), float(foe["y"]))

static func _step_drone(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var home: Vector2 = foe["home"]
	var facing := int(foe["face"])
	var x := float(foe["x"]) + float(facing) * 38.0 * speed * delta
	if absf(x - home.x) > float(foe["reach"]) or world.is_solid(world.tile_at_point(x + float(facing) * 8.0, float(foe["y"]) - 4.0)):
		foe["face"] = -facing
		x = clampf(x, home.x - float(foe["reach"]), home.x + float(foe["reach"]))
	foe["x"] = x
	foe["y"] = home.y + sin(float(foe["time"]) * 3.2) * 9.0

static func _step_turret(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	if str(foe["mode"]) == "aim":
		foe["aim"] = float(foe.get("aim", 0.0)) - delta
		if float(foe["aim"]) <= 0.0:
			foe["mode"] = "walk"
			foe["cool"] = 2.6 / speed
			var facing := int(foe["face"])
			world.add_shot("spark", float(foe["x"]) + float(facing) * 9.0, float(foe["y"]) - 9.0, float(facing) * 95.0 * speed, 0.0, 0.0)
			world.emit("shot", float(foe["x"]), float(foe["y"]) - 9.0)
		return
	if target.is_empty():
		return
	var dx := float(target["x"]) - float(foe["x"])
	if absf(dx) < 200.0:
		foe["face"] = 1 if dx > 0.0 else -1
	if float(foe["cool"]) <= 0.0 and absf(dx) < 170.0 and absf(float(target["y"]) - float(foe["y"])) < 30.0:
		foe["mode"] = "aim"
		foe["aim"] = 0.45

static func _step_roller(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var facing := int(foe["face"])
	match str(foe["mode"]):
		"walk":
			foe["vx"] = float(facing) * 18.0 * speed
			_walk(world, foe, delta)
			var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
			if not target.is_empty() and float(foe["cool"]) <= 0.0:
				var ahead := (float(target["x"]) - float(foe["x"])) * float(int(foe["face"]))
				if ahead > 0.0 and ahead < 120.0 and absf(float(target["y"]) - float(foe["y"])) < 18.0:
					foe["mode"] = "rev"
					foe["aim"] = 0.42
					world.emit("rev", float(foe["x"]), float(foe["y"]))
		"rev":
			foe["vx"] = 0.0
			_walk(world, foe, delta)
			foe["face"] = facing
			foe["aim"] = float(foe["aim"]) - delta
			if float(foe["aim"]) <= 0.0:
				foe["mode"] = "dash"
		"dash":
			foe["vx"] = float(facing) * 132.0 * speed
			var flags := _walk(world, foe, delta)
			if (flags & 8) != 0:
				foe["mode"] = "dizzy"
				foe["aim"] = 1.2
				world.emit("clang", float(foe["x"]), float(foe["y"]) - 8.0)
		_:
			foe["vx"] = 0.0
			_walk(world, foe, delta)
			foe["face"] = facing
			foe["aim"] = float(foe["aim"]) - delta
			if float(foe["aim"]) <= 0.0:
				foe["mode"] = "walk"
				foe["cool"] = 0.8

static func _step_magnet(world: Variant, foe: Dictionary, delta: float, speed: float) -> void:
	var home: Vector2 = foe["home"]
	var target: Dictionary = world.nearest_hero(float(foe["x"]), float(foe["y"]))
	var wanted := home.x
	if not target.is_empty() and absf(float(target["x"]) - home.x) < float(foe["reach"]) + 40.0 and float(target["y"]) > float(foe["y"]):
		wanted = clampf(float(target["x"]), home.x - float(foe["reach"]), home.x + float(foe["reach"]))
		if absf(float(target["x"]) - float(foe["x"])) < 10.0 and float(foe["cool"]) <= 0.0 and float(target["y"]) - float(foe["y"]) < 150.0:
			foe["cool"] = 1.8 / speed
			world.add_shot("nut", float(foe["x"]), float(foe["y"]) + 2.0, 0.0, 20.0, 480.0)
			world.emit("drop", float(foe["x"]), float(foe["y"]))
	var x := move_toward(float(foe["x"]), wanted, 42.0 * speed * delta)
	if x != float(foe["x"]):
		foe["face"] = 1 if x > float(foe["x"]) else -1
	foe["x"] = x
	foe["y"] = home.y + sin(float(foe["time"]) * 2.0) * 4.0

## What happens when an enemy and a robot overlap: a thrown robot knocks it out, a hidden robot turns it away, anyone else is hurt.
static func _touch_heroes(world: Variant, foe: Dictionary) -> void:
	if int(foe["state"]) != ALIVE:
		return
	var x := float(foe["x"])
	var y := float(foe["y"])
	for hero: Dictionary in world.heroes:
		var state := int(hero["state"])
		if state != world.H_NORMAL and state != world.H_THROWN:
			continue
		if absf(float(hero["x"]) - x) >= float(foe["half"]) + world.HERO_HALF - 1.0 or float(hero["y"]) - world.HERO_TALL >= y or float(hero["y"]) <= y - float(foe["tall"]):
			continue
		if state == world.H_THROWN:
			hit(world, foe, int(hero["by"]), 2, 1.0 if float(hero["vx"]) >= 0.0 else -1.0, 0, true)
			return
		if bool(hero["hide"]):
			var kind := str(foe["kind"])
			if kind == "bug" or kind == "roller" or kind == "hopper":
				var away := 1 if x > float(hero["x"]) else -1
				foe["face"] = away
				foe["x"] = float(hero["x"]) + float(away) * (float(foe["half"]) + world.HERO_HALF)
				if kind == "hopper":
					foe["vx"] = float(away) * 50.0
				if kind == "roller" and str(foe["mode"]) == "dash":
					foe["mode"] = "dizzy"
					foe["aim"] = 1.2
					world.emit("clang", x, y - 8.0)
			continue
		world.hurt_hero(hero, x)

## Something thrown by player `slot` reached this enemy. `power` 2 breaks armour at once. Returns false when the enemy was already out.
static func hit(world: Variant, foe: Dictionary, slot: int, power: int, direction: float, chain: int, by_buddy: bool) -> bool:
	if int(foe["state"]) != ALIVE:
		return false
	foe["hp"] = int(foe["hp"]) - power
	foe["flash"] = 0.18
	if int(foe["hp"]) > 0:
		foe["mode"] = "dizzy"
		foe["aim"] = 1.0
		world.emit("foe_hit", float(foe["x"]), float(foe["y"]) - 8.0)
		return true
	foe["state"] = KNOCKED_OUT
	foe["time"] = 0.0
	foe["vx"] = direction * 70.0
	foe["vy"] = -190.0
	world.emit("foe_out", float(foe["x"]), float(foe["y"]) - 8.0, {"kind": str(foe["kind"])})
	world.foe_beaten(foe, slot, chain, by_buddy)
	return true

## Sparks, nuts and whatever a boss throws: fly, hit robots, stop at walls. A lump that lands may turn into something a robot can pick up.
static func step_shots(world: Variant, delta: float) -> void:
	for shot: Dictionary in world.shots:
		if bool(shot["gone"]):
			continue
		shot["time"] = float(shot["time"]) + delta
		shot["vy"] = float(shot["vy"]) + float(shot["g"]) * delta
		shot["x"] = float(shot["x"]) + float(shot["vx"]) * delta
		shot["y"] = float(shot["y"]) + float(shot["vy"]) * delta
		var x := float(shot["x"])
		var y := float(shot["y"])
		var kind := str(shot["kind"])
		if not world.is_active_at(x, y) or float(shot["time"]) > 8.0:
			shot["gone"] = true
			continue
		var tile: int = world.tile_at_point(x, y + 3.0)
		var landed: bool = world.is_solid(tile) or (float(shot["vy"]) > 0.0 and tile == 2 and fmod(y + 3.0, 16.0) < 6.0)
		if landed or world.is_solid(world.tile_at_point(x + signf(float(shot["vx"])) * 4.0, y)):
			shot["gone"] = true
			if (kind == "junk" or kind == "bolt") and landed:
				var object: Dictionary = world.add_object("scrap" if kind == "junk" else "hexnut", x, floorf((y + 3.0) / 16.0) * 16.0)
				object["life"] = 9.0
				world.emit("thud", x, y)
			else:
				world.emit("poof", x, y, {"kind": kind})
			continue
		var reach := 6.0 if kind == "junk" or kind == "bolt" else 3.0
		for hero: Dictionary in world.heroes:
			if int(hero["state"]) != world.H_NORMAL:
				continue
			if absf(float(hero["x"]) - x) < reach + world.HERO_HALF and y > float(hero["y"]) - world.HERO_TALL - reach and y < float(hero["y"]) + reach:
				if bool(hero["hide"]):
					shot["gone"] = true
					world.emit("clang", x, y)
				elif world.hurt_hero(hero, x - float(shot["vx"]) * 0.01):
					shot["gone"] = true
					world.emit("poof", x, y, {"kind": kind})
				break
