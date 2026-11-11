extends RefCounted

## The rogue machines: what each kind does every step, how the stage sends them in, and what happens when one is destroyed. A machine is a Dictionary with its feet at (x, y); `g` is the game module.
##
##   scut     runs along the ground and hops gaps
##   troop    walks towards a diver and fires level shots (go prone or jump)
##   turret   an emplacement that aims in eight directions
##   drone    flies across, fires once and drops a charge on the way
##   toad     squats and lobs charges in an arc
##   pike     leaps out of the water
##   cling    patrols one platform of the tower
##   debris   falls down the tower shaft
##   carrier  a courier that drops a weapon canister when shot
##   crate    a locker that holds a canister

const World := preload("res://games/tide_runners/world.gd")

## kind -> [width, height, hit points, score]
const KINDS := {
	"scut": [14.0, 10.0, 1, 100], "troop": [10.0, 16.0, 2, 200], "turret": [18.0, 14.0, 4, 300], "drone": [14.0, 10.0, 1, 150], "toad": [16.0, 12.0, 3, 300],
	"pike": [14.0, 9.0, 1, 150], "cling": [12.0, 10.0, 2, 150], "debris": [8.0, 7.0, 1, 50], "carrier": [20.0, 11.0, 1, 200], "crate": [16.0, 15.0, 3, 100],
}
const GRAVITY := 520.0
const STREAM_CAP := 6
const WAVE_CAP := 5
const PASSIVE := ["carrier", "crate"]
const TROOP_HOP := 290.0
const TROOP_HOP_DRIFT := 46.0

static func spawn(g: Variant, kind: String, x: float, y: float, extra: int = 0) -> Dictionary:
	var spec: Array = KINDS[kind]
	g.foe_serial += 1
	var foe := {
		"id": g.foe_serial, "k": kind, "x": x, "y": y, "vx": 0.0, "vy": 0.0, "w": spec[0], "h": spec[1], "hp": spec[2], "pts": spec[3], "extra": extra,
		"t": 0.0, "st": 0, "face": -1, "flash": 0.0, "a": 0.0, "b": 0.0, "ground": false, "dead": false, "wave": false,
	}
	match kind:
		"turret":
			foe["t"] = 1.0
		"troop":
			foe["t"] = 1.4
		"toad":
			foe["t"] = 1.6
		"drone", "carrier":
			foe["b"] = y
		"debris":
			foe["vy"] = 120.0
	g.foes.append(foe)
	return foe

static func box(foe: Dictionary) -> Rect2:
	return Rect2(float(foe["x"]) - float(foe["w"]) * 0.5, float(foe["y"]) - float(foe["h"]), float(foe["w"]), float(foe["h"]))

## Whether shots and divers can touch it right now. A pike under water cannot be hit.
static func exposed(foe: Dictionary) -> bool:
	return not foe["dead"] and not (foe["k"] == "pike" and int(foe["st"]) != 2)

static func hurt(g: Variant, foe: Dictionary, damage: int, slot: int) -> void:
	foe["hp"] = int(foe["hp"]) - damage
	foe["flash"] = 0.1
	if int(foe["hp"]) > 0:
		g.sfx("hit")
		return
	foe["dead"] = true
	g.kills += 1
	g.add_score(slot, int(foe["pts"]))
	var x: float = foe["x"]
	var y: float = float(foe["y"]) - float(foe["h"]) * 0.5
	g.boom(x, y, 12.0 if foe["k"] != "turret" else 18.0)
	g.sfx("boom_small")
	if foe["k"] == "carrier" or foe["k"] == "crate":
		g.drop_item(x, y, int(foe["extra"]))

# ---- the stage's script ----

## Send in what the stage data asks for: placed machines as the camera reaches them, streams while the camera is in a zone, and waves while it is locked.
static func direct(g: Variant, dt: float) -> void:
	var world: World = g.world
	var cam: Vector2 = g.cam
	var spawns: Array = world.def["spawns"]
	for index in spawns.size():
		if g.spawned[index] != 0:
			continue
		var entry: Array = spawns[index]
		var kind: String = entry[0]
		var x := float(entry[1]) * World.TILE + 8.0
		var y := float(entry[2]) * World.TILE
		var due := (y > cam.y - 30.0) if world.vertical else (x < cam.x + 500.0)
		if not due:
			continue
		g.spawned[index] = 1
		if kind == "pike":
			spawn(g, kind, x, float(g.water_line()))
		elif kind == "carrier":
			var from_left := world.vertical and index % 2 == 0
			var courier := spawn(g, kind, cam.x - 14.0 if from_left else cam.x + 494.0, y, int(entry[3]))
			courier["vx"] = 52.0 if from_left else -52.0
		else:
			var foe := spawn(g, kind, x, y, int(entry[3]))
			foe["ground"] = true
			if kind == "cling":
				foe["vx"] = 32.0
	if g.boss_live():
		return
	_direct_lock(g, dt)
	if not g.lock.is_empty():
		return
	var zones: Array = world.def["zones"]
	var centre := (cam.y + 135.0) / World.TILE if world.vertical else (cam.x + 240.0) / World.TILE
	for index in zones.size():
		var zone: Array = zones[index]
		if centre < float(zone[0]) or centre > float(zone[1]):
			continue
		g.zone_t[index] = float(g.zone_t[index]) - dt
		if float(g.zone_t[index]) > 0.0:
			continue
		g.zone_t[index] = float(zone[3]) * float(g.pace) * g.rng.float_range(0.75, 1.25)
		if _stream_count(g) < STREAM_CAP:
			_send(g, str(zone[2]), false)

static func _direct_lock(g: Variant, dt: float) -> void:
	var world: World = g.world
	var locks: Array = world.def["locks"]
	if g.lock.is_empty():
		if g.lock_index < locks.size() and g.cam.x >= float(locks[g.lock_index][0]) * World.TILE - 0.5:
			g.lock = {"need": int(locks[g.lock_index][1]), "sent": 0, "t": 0.8}
			g.lock_index += 1
			g.sfx("alarm")
			g.say("ambush", 1.6)
		return
	var alive := 0
	for foe: Dictionary in g.foes:
		if foe["wave"] and not foe["dead"]:
			alive += 1
	var lock: Dictionary = g.lock
	if int(lock["sent"]) >= int(lock["need"]):
		if alive == 0:
			g.lock = {}
			g.sfx("go")
			g.go_t = 2.5
		return
	lock["t"] = float(lock["t"]) - dt
	if float(lock["t"]) > 0.0 or alive >= WAVE_CAP:
		return
	lock["t"] = 0.85 * float(g.pace)
	lock["sent"] = int(lock["sent"]) + 1
	var roll: float = g.rng.unit()
	_send(g, "scut" if roll < 0.55 else ("drone" if roll < 0.8 else "troop"), true)

static func _stream_count(g: Variant) -> int:
	var count := 0
	for foe: Dictionary in g.foes:
		if not foe["dead"] and foe["k"] in ["scut", "drone", "debris"]:
			count += 1
	return count

## Bring one machine in from the edge of the view.
static func _send(g: Variant, kind: String, wave: bool) -> void:
	var world: World = g.world
	var cam: Vector2 = g.cam
	var foe: Dictionary = {}
	match kind:
		"scut":
			var from_left: bool = g.rng.chance(0.5 if wave else 0.2) and cam.x > 64.0
			var x := cam.x - 10.0 if from_left else cam.x + 490.0
			var top: float = world.surface_below(floori(x / World.TILE), floori((cam.y + 80.0) / World.TILE))
			if top == INF or top > cam.y + 244.0:
				# Nothing to stand on at that edge. A stream just skips a beat; an ambush drops it in from above.
				if not wave:
					return
				x = cam.x + g.rng.float_range(120.0, 440.0)
				top = cam.y + 40.0
			foe = spawn(g, kind, x, top)
			foe["face"] = 1 if from_left else -1
		"troop":
			foe = spawn(g, kind, cam.x + g.rng.float_range(140.0, 440.0), cam.y + 44.0)
		"drone":
			var from_left: bool = g.rng.chance(0.5) and (world.vertical or wave)
			foe = spawn(g, kind, cam.x - 12.0 if from_left else cam.x + 492.0, cam.y + g.rng.float_range(78.0, 150.0))
			foe["vx"] = 58.0 if from_left else -58.0
			foe["face"] = 1 if from_left else -1
		"debris":
			foe = spawn(g, kind, g.rng.float_range(40.0, 440.0), cam.y - 8.0)
		"pike":
			if float(g.water_line()) > cam.y + 330.0:
				return
			foe = spawn(g, kind, g.rng.float_range(60.0, 420.0), float(g.water_line()))
			foe["a"] = 0.0
	if not foe.is_empty():
		foe["wave"] = wave

# ---- behaviour ----

static func step(g: Variant, dt: float) -> void:
	var world: World = g.world
	var cam: Vector2 = g.cam
	var foes: Array = g.foes
	for foe: Dictionary in foes:
		if foe["dead"]:
			continue
		foe["flash"] = maxf(0.0, float(foe["flash"]) - dt)
		foe["t"] = float(foe["t"]) - dt
		foe["a"] = maxf(0.0, float(foe["a"]) - dt)
		var target: Dictionary = g.nearest_hero(float(foe["x"]), float(foe["y"]))
		match str(foe["k"]):
			"scut":
				_scut(g, world, foe, dt)
			"troop":
				_troop(g, world, foe, target, dt)
			"turret":
				_turret(g, foe, target)
			"drone":
				_drone(g, foe, target, dt)
			"toad":
				_fall(world, foe, dt)
				_toad(g, foe, target)
			"pike":
				_pike(g, foe, target, dt)
			"cling":
				_cling(world, foe, dt)
			"debris":
				foe["y"] = float(foe["y"]) + float(foe["vy"]) * dt
			"carrier":
				foe["x"] = float(foe["x"]) + float(foe["vx"]) * dt
				foe["y"] = float(foe["b"]) + sin(float(foe["t"]) * 2.5) * 10.0
		_cull(g, world, cam, foe)
	for index in range(foes.size() - 1, -1, -1):
		if foes[index]["dead"]:
			foes.remove_at(index)

## Machines that left the view for good, or fell in the water, are simply removed.
static func _cull(g: Variant, world: World, cam: Vector2, foe: Dictionary) -> void:
	var x: float = foe["x"]
	var y: float = foe["y"]
	var kind: String = foe["k"]
	var gone := false
	if world.vertical:
		gone = y > cam.y + 330.0 or x < -40.0 or x > 520.0
	else:
		gone = x < cam.x - 60.0 or x > cam.x + 620.0
	if kind in ["scut", "troop", "toad"] and y > float(g.drown_line()):
		g.splash(x, float(g.water_line()))
		gone = true
	if gone:
		foe["dead"] = true

static func _fall(world: World, foe: Dictionary, dt: float) -> void:
	var half := float(foe["w"]) * 0.5
	var vy := minf(340.0, float(foe["vy"]) + GRAVITY * dt)
	var y: float = foe["y"]
	var next_y := y + vy * dt
	if vy >= 0.0:
		var top := world.landing(float(foe["x"]) - half, float(foe["x"]) + half, y, next_y, false)
		if top < INF:
			foe["y"] = top
			foe["vy"] = 0.0
			foe["ground"] = true
			return
	foe["y"] = next_y
	foe["vy"] = vy
	foe["ground"] = false

static func _scut(g: Variant, world: World, foe: Dictionary, dt: float) -> void:
	var face: int = foe["face"]
	var x: float = foe["x"]
	var y: float = foe["y"]
	var next_x := x + face * 74.0 * dt
	var blocked := world.box_hits(next_x - 6.0, y - 9.0, next_x + 6.0, y - 1.0)
	if foe["ground"]:
		var ahead := x + face * 11.0
		var ledge := world.landing(ahead - 1.0, ahead + 1.0, y, y + 6.0, false) == INF
		if blocked or ledge:
			foe["vy"] = -238.0
			foe["ground"] = false
	if not blocked:
		foe["x"] = next_x
	_fall(world, foe, dt)

static func _troop(g: Variant, world: World, foe: Dictionary, target: Dictionary, dt: float) -> void:
	_fall(world, foe, dt)
	if target.is_empty():
		return
	var x: float = foe["x"]
	var y: float = foe["y"]
	if not foe["ground"]:
		# Mid-hop: keep drifting the way it faces so it clears the block it jumped at.
		var drift := x + int(foe["face"]) * TROOP_HOP_DRIFT * dt
		if not world.box_hits(drift - 5.0, y - 15.0, drift + 5.0, y - 1.0):
			foe["x"] = drift
		return
	var dx := float(target["x"]) - x
	foe["face"] = 1 if dx > 0.0 else -1
	var face: int = foe["face"]
	var level := absf(float(target["y"]) - y) < 52.0
	# It closes in until it has a shot. On the open stages a diver above or below it, or behind a block, has to be walked to: a trooper that only waited there could neither hit nor be hit, and stalled an ambush. The tower's deck guards hold their deck.
	var sight := world.vertical or level and not world.box_hits(minf(x, float(target["x"])) + 6.0, y - 12.0, maxf(x, float(target["x"])) - 6.0, y - 10.0)
	# Each one stops a little nearer or farther than the next, so several of them do not end up standing in the same spot looking like one.
	var reach := 70.0 + float(int(foe["id"]) % 3) * 9.0
	if float(foe["a"]) <= 0.0 and (absf(dx) > reach or (not sight and absf(dx) > 12.0)):
		var next_x := x + face * 30.0 * dt
		var ahead := next_x + face * 8.0
		# A ledge only stops it over water; onto dry ground below it steps off.
		var ledge := world.landing(ahead - 1.0, ahead + 1.0, y, y + 6.0, false) == INF and world.landing(ahead - 1.0, ahead + 1.0, y, float(g.drown_line()) - 2.0, false) == INF
		if world.box_hits(next_x - 5.0, y - 15.0, next_x + 5.0, y - 1.0):
			# A block in the way: hop it.
			foe["vy"] = -TROOP_HOP
			foe["ground"] = false
		elif not ledge:
			foe["x"] = next_x
			foe["b"] = float(foe["b"]) + dt
	if float(foe["t"]) <= 0.0 and absf(dx) < 230.0 and absf(float(target["y"]) - y) < 52.0 and g.in_view(x, y, 0.0):
		foe["t"] = 2.5 * float(g.pace)
		foe["a"] = 0.35
		g.foe_shot(x + face * 9.0, y - 11.0, face * 118.0 * float(g.shot_speed), 0.0, "orb")
		g.sfx("foe_shot")

static func _turret(g: Variant, foe: Dictionary, target: Dictionary) -> void:
	if target.is_empty():
		return
	var origin := Vector2(float(foe["x"]), float(foe["y"]) - 9.0)
	var to := Vector2(float(target["x"]), float(target["y"]) - 10.0) - origin
	# Snap the barrel to the nearest of eight directions.
	var angle := snappedf(to.angle(), PI / 4.0)
	foe["b"] = angle
	if float(foe["t"]) > 0.0 or to.length() > 250.0 or not g.in_view(origin.x, origin.y, -6.0):
		return
	foe["t"] = 2.2 * float(g.pace)
	var dir := Vector2.from_angle(angle)
	g.foe_shot(origin.x + dir.x * 12.0, origin.y + dir.y * 12.0, dir.x * 96.0 * float(g.shot_speed), dir.y * 96.0 * float(g.shot_speed), "orb")
	g.sfx("foe_shot")

static func _drone(g: Variant, foe: Dictionary, target: Dictionary, dt: float) -> void:
	foe["x"] = float(foe["x"]) + float(foe["vx"]) * dt
	foe["a"] = float(foe["a"]) + dt * 2.0
	foe["y"] = float(foe["b"]) + sin(float(foe["a"]) * 3.0) * 12.0
	if target.is_empty() or not g.in_view(float(foe["x"]), float(foe["y"]), -10.0):
		return
	var x: float = foe["x"]
	var y: float = foe["y"]
	if int(foe["st"]) == 0 and float(foe["a"]) > 1.1:
		foe["st"] = 1
		var dir := (Vector2(float(target["x"]), float(target["y"]) - 10.0) - Vector2(x, y)).normalized()
		g.foe_shot(x, y, dir.x * 88.0 * float(g.shot_speed), dir.y * 88.0 * float(g.shot_speed), "orb")
		g.sfx("foe_shot")
	elif int(foe["st"]) == 1 and absf(float(target["x"]) - x) < 10.0 and float(target["y"]) > y:
		foe["st"] = 2
		g.foe_shot(x, y, 0.0, 40.0, "bomb")

static func _toad(g: Variant, foe: Dictionary, target: Dictionary) -> void:
	if target.is_empty() or float(foe["t"]) > 0.0 or not foe["ground"]:
		return
	var x: float = foe["x"]
	var y: float = float(foe["y"]) - 14.0
	var dx := float(target["x"]) - x
	foe["face"] = 1 if dx > 0.0 else -1
	if absf(dx) > 270.0 or not g.in_view(x, y, 0.0):
		return
	foe["t"] = 2.9 * float(g.pace)
	foe["a"] = 0.3
	var flight := 1.15
	var dy := float(target["y"]) - y
	g.foe_shot(x, y, dx / flight, (dy - 0.5 * g.BOMB_GRAVITY * flight * flight) / flight, "bomb")
	g.sfx("lob")

static func _pike(g: Variant, foe: Dictionary, target: Dictionary, dt: float) -> void:
	var water: float = g.water_line()
	match int(foe["st"]):
		0:
			foe["y"] = water
			if not target.is_empty() and float(foe["a"]) <= 0.0 and absf(float(target["x"]) - float(foe["x"])) < 110.0 and float(target["y"]) < water + 4.0 and water < g.cam.y + 300.0:
				foe["st"] = 1
				foe["t"] = 0.55
				foe["face"] = 1 if float(target["x"]) > float(foe["x"]) else -1
		1:
			foe["y"] = water
			if g.fx_rng.chance(0.3):
				g.bubble(float(foe["x"]) + g.fx_rng.float_range(-6.0, 6.0), water - 2.0)
			if float(foe["t"]) <= 0.0:
				foe["st"] = 2
				foe["vy"] = -318.0
				foe["vx"] = int(foe["face"]) * 46.0
				g.splash(float(foe["x"]), water)
				g.sfx("splash")
		2:
			foe["vy"] = float(foe["vy"]) + 430.0 * dt
			foe["x"] = float(foe["x"]) + float(foe["vx"]) * dt
			foe["y"] = float(foe["y"]) + float(foe["vy"]) * dt
			if float(foe["vy"]) > 0.0 and float(foe["y"]) > water + 6.0:
				g.splash(float(foe["x"]), water)
				if g.world.vertical:
					foe["dead"] = true
				foe["st"] = 0
				foe["a"] = 1.7

static func _cling(world: World, foe: Dictionary, dt: float) -> void:
	var x: float = foe["x"]
	var y: float = foe["y"]
	var vx: float = foe["vx"]
	var ahead := x + signf(vx) * 8.0
	if world.landing(ahead - 1.0, ahead + 1.0, y, y + 4.0, false) == INF or world.solid_at(ahead, y - 4.0):
		vx = -vx
		foe["vx"] = vx
	foe["x"] = x + vx * dt
	foe["face"] = 1 if vx > 0.0 else -1
