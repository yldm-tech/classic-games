extends RefCounted

## The three bosses. Each is a machine built from parts with their own hit points; the outer parts have to go before the core can be hurt. A boss is a Dictionary, made dormant when its stage loads and woken when the divers reach its arena; `g` is the game module.
##
##   0  the Dredger Maw       fills the right edge of the boulevard: a cannon arm, a jaw hatch that spits machines, and a shuttered core
##   1  the Valve Hydra       hangs under the tower's pressure tank: three heads on pipe necks, then the tank's heart
##   2  the Gantry Leviathan  rides a rail over the dock: two turrets, a claw that slams down, and an eye that opens while the claw is out

const World := preload("res://games/tide_runners/world.gd")
const Foes := preload("res://games/tide_runners/foes.gd")

const MISS := 0
const HURT := 1
const DEFLECTED := 2
const DYING_TIME := 2.6

static func make(g: Variant, kind: int) -> Dictionary:
	var world: World = g.world
	var boss := {"kind": kind, "t": 0.0, "st": 0, "active": false, "dying": -1.0, "dead": false, "parts": [], "x": 0.0, "y": 0.0, "a": 0.0, "b": 0.0, "c": 0.0, "d": 0.0, "n": 0, "dir": 1, "tx": 0.0}
	var scale: float = g.boss_scale
	match kind:
		0:
			boss["x"] = float(world.def["boss_col"]) * World.TILE + 360.0
			boss["y"] = 20.0
			var bx: float = boss["x"]
			_part(boss, "cannon", bx + 8.0, 90.0, 30.0, 22.0, 26.0 * scale, true)
			_part(boss, "hatch", bx + 19.0, 201.0, 30.0, 30.0, 26.0 * scale, true)
			_part(boss, "core", bx + 36.0, 138.0, 30.0, 30.0, 54.0 * scale, false)
			boss["a"] = 1.5
			boss["b"] = 2.4
		1:
			boss["x"] = 240.0
			boss["y"] = 44.0
			for index in 3:
				var head := _part(boss, "head", 166.0 + 74.0 * index, 140.0, 24.0, 22.0, 22.0 * scale, true)
				head["i"] = index
				head["m"] = 0
				head["mt"] = 0.0
				head["ft"] = 1.2 + 0.9 * index
				head["sx"] = 0.0
				head["sy"] = 0.0
				head["lx"] = 0.0
				head["ly"] = 0.0
			_part(boss, "core", 240.0, 67.0, 36.0, 28.0, 56.0 * scale, false)
			boss["a"] = 4.0
			_place_heads(boss)
		2:
			boss["x"] = float(world.def["boss_col"]) * World.TILE + 240.0
			boss["y"] = 60.0
			var cx: float = boss["x"]
			_part(boss, "turret", cx - 39.0, 95.0, 20.0, 18.0, 24.0 * scale, true)
			_part(boss, "turret", cx + 39.0, 95.0, 20.0, 18.0, 24.0 * scale, true)
			_part(boss, "claw", cx, 132.0, 30.0, 30.0, 34.0 * scale, true)
			_part(boss, "core", cx, 106.0, 26.0, 20.0, 60.0 * scale, false)
			boss["a"] = 3.0
			boss["b"] = 1.0
			boss["tx"] = cx
	return boss

static func _part(boss: Dictionary, part_name: String, x: float, y: float, w: float, h: float, hit_points: float, open: bool) -> Dictionary:
	var hit_total := maxi(1, roundi(hit_points))
	var made := {"n": part_name, "x": x, "y": y, "w": w, "h": h, "hp": hit_total, "max": hit_total, "alive": true, "vuln": open, "flash": 0.0}
	(boss["parts"] as Array).append(made)
	return made

static func hp(boss: Dictionary) -> int:
	var total := 0
	for part: Dictionary in boss["parts"]:
		total += maxi(0, int(part["hp"]))
	return total

static func max_hp(boss: Dictionary) -> int:
	var total := 0
	for part: Dictionary in boss["parts"]:
		total += int(part["max"])
	return total

static func part(boss: Dictionary, part_name: String, nth: int = 0) -> Dictionary:
	var seen := 0
	for entry: Dictionary in boss["parts"]:
		if entry["n"] == part_name:
			if seen == nth:
				return entry
			seen += 1
	return {}

static func alive_count(boss: Dictionary, part_name: String) -> int:
	var count := 0
	for entry: Dictionary in boss["parts"]:
		if entry["n"] == part_name and entry["alive"]:
			count += 1
	return count

static func part_box(entry: Dictionary) -> Rect2:
	return Rect2(float(entry["x"]) - float(entry["w"]) * 0.5, float(entry["y"]) - float(entry["h"]) * 0.5, float(entry["w"]), float(entry["h"]))

## A diver's shot at `point`: hurts an open part, bounces off a closed one or off the hull.
static func hit(g: Variant, boss: Dictionary, point: Vector2, radius: float, damage: int, slot: int) -> int:
	if boss["dead"] or float(boss["dying"]) >= 0.0:
		return MISS
	var result := MISS
	for entry: Dictionary in boss["parts"]:
		if not entry["alive"] or not part_box(entry).grow(radius).has_point(point):
			continue
		if not boss["active"] or not entry["vuln"]:
			result = DEFLECTED
			continue
		entry["hp"] = int(entry["hp"]) - damage
		entry["flash"] = 0.1
		if int(entry["hp"]) <= 0:
			_break_part(g, boss, entry, slot)
		else:
			g.sfx("hit")
		return HURT
	if result == MISS and int(boss["kind"]) == 0 and point.x > float(boss["x"]) + 18.0:
		result = DEFLECTED
	return result

static func _break_part(g: Variant, boss: Dictionary, entry: Dictionary, slot: int) -> void:
	entry["alive"] = false
	entry["hp"] = 0
	g.boom(float(entry["x"]), float(entry["y"]), 26.0)
	g.shake(5.0)
	g.sfx("boom_big")
	if entry["n"] == "core":
		g.add_score(slot, 5000)
		boss["dying"] = DYING_TIME
		g.clear_foe_shots()
		for other: Dictionary in boss["parts"]:
			other["alive"] = false
		for foe: Dictionary in g.foes:
			foe["dead"] = true
	else:
		g.add_score(slot, 1000)

static func step(g: Variant, boss: Dictionary, dt: float) -> void:
	if boss["dead"]:
		return
	for entry: Dictionary in boss["parts"]:
		entry["flash"] = maxf(0.0, float(entry["flash"]) - dt)
	if float(boss["dying"]) >= 0.0:
		boss["dying"] = float(boss["dying"]) - dt
		boss["c"] = float(boss["c"]) - dt
		if float(boss["c"]) <= 0.0:
			boss["c"] = 0.11
			var centre := Vector2(float(boss["x"]), float(boss["y"]) + 60.0) if int(boss["kind"]) != 0 else Vector2(float(boss["x"]) + 50.0, 130.0)
			g.boom(centre.x + g.fx_rng.float_range(-56.0, 56.0), centre.y + g.fx_rng.float_range(-70.0, 80.0), g.fx_rng.float_range(10.0, 24.0))
			g.shake(3.0)
			if g.fx_rng.chance(0.5):
				g.sfx("boom_small")
		if float(boss["dying"]) <= 0.0:
			boss["dead"] = true
			g.sfx("boom_big")
			g.flash = 0.5
		return
	boss["t"] = float(boss["t"]) + dt
	match int(boss["kind"]):
		0:
			_maw(g, boss, dt)
		1:
			_hydra(g, boss, dt)
		2:
			_gantry(g, boss, dt)

static func _aimed(g: Variant, from: Vector2, speed: float, spread: Array) -> void:
	var target: Dictionary = g.nearest_hero(from.x, from.y)
	var to := Vector2(-1.0, 0.3) if target.is_empty() else Vector2(float(target["x"]), float(target["y"]) - 10.0) - from
	var base := to.angle()
	for offset: float in spread:
		var dir := Vector2.from_angle(base + offset)
		g.foe_shot(from.x, from.y, dir.x * speed * float(g.shot_speed), dir.y * speed * float(g.shot_speed), "orb")
	g.sfx("foe_shot")

static func _ring(g: Variant, from: Vector2, count: int, speed: float, turn: float) -> void:
	for index in count:
		var dir := Vector2.from_angle(turn + TAU * index / float(count))
		g.foe_shot(from.x, from.y, dir.x * speed * float(g.shot_speed), dir.y * speed * float(g.shot_speed), "orb")
	g.sfx("ring")

static func _lob(g: Variant, from: Vector2) -> void:
	for h: Dictionary in g.heroes:
		if not (h["active"] and h["alive"]):
			continue
		var flight := 1.25
		var dx := float(h["x"]) - from.x
		var dy := float(h["y"]) - from.y
		g.foe_shot(from.x, from.y, dx / flight, (dy - 0.5 * g.BOMB_GRAVITY * flight * flight) / flight, "bomb")
	g.sfx("lob")

## True in the step in which the timer `key` passes `mark` while counting up by dt.
static func _passed(before: float, after: float, mark: float) -> bool:
	return before < mark and after >= mark

static func _touch(g: Variant, area: Rect2) -> void:
	for h: Dictionary in g.heroes:
		if h["active"] and h["alive"] and area.intersects(g.hero_box(h)):
			g.hit_hero(h)

# ---- 0: the Dredger Maw ----

static func _maw(g: Variant, boss: Dictionary, dt: float) -> void:
	if not boss["active"]:
		return
	var cannon := part(boss, "cannon")
	var hatch := part(boss, "hatch")
	var core := part(boss, "core")
	var pace: float = g.pace
	if cannon["alive"]:
		boss["a"] = float(boss["a"]) - dt
		if float(boss["a"]) <= 0.0:
			boss["a"] = 2.5 * pace
			_aimed(g, Vector2(float(cannon["x"]) - 18.0, float(cannon["y"])), 100.0, [-0.22, 0.0, 0.22])
	if hatch["alive"]:
		boss["b"] = float(boss["b"]) - dt
		if float(boss["b"]) <= 0.0:
			boss["b"] = 3.3 * pace
			boss["n"] = int(boss["n"]) + 1
			if int(boss["n"]) % 2 == 1:
				g.foe_shot(float(hatch["x"]) - 18.0, 217.0, -138.0 * float(g.shot_speed), 0.0, "spike")
				g.sfx("foe_shot")
			elif g.foes.size() < 4:
				var scut: Dictionary = Foes.spawn(g, "scut", float(hatch["x"]) - 14.0, 224.0)
				scut["ground"] = true
	if cannon["alive"] or hatch["alive"]:
		return
	# Both guards are gone: the core's shutter opens and closes on a cycle.
	var before: float = boss["c"]
	var after := fmod(before + dt, 4.6)
	boss["c"] = after
	core["vuln"] = after < 3.1
	var eye := Vector2(float(core["x"]) - 14.0, float(core["y"]))
	if _passed(before, after, 0.6) or _passed(before, after, 1.9):
		boss["d"] = float(boss["d"]) + 0.37
		_ring(g, eye, 10, 80.0, float(boss["d"]))
	if _passed(before, after, 1.25) or _passed(before, after, 2.55):
		_lob(g, eye)

# ---- 1: the Valve Hydra ----

static func _head_home(boss: Dictionary, head: Dictionary) -> Vector2:
	var index: int = head["i"]
	var t: float = boss["t"]
	return Vector2(166.0 + 74.0 * index + sin(t * 0.9 + index * 2.1) * 44.0, 144.0 + sin(t * 1.3 + index * 1.7) * 20.0)

static func _place_heads(boss: Dictionary) -> void:
	for entry: Dictionary in boss["parts"]:
		if entry["n"] == "head" and int(entry["m"]) == 0:
			var home := _head_home(boss, entry)
			entry["x"] = home.x
			entry["y"] = home.y

static func _hydra(g: Variant, boss: Dictionary, dt: float) -> void:
	_place_heads(boss)
	if not boss["active"]:
		return
	var pace: float = g.pace
	var heads := alive_count(boss, "head")
	var core := part(boss, "core")
	core["vuln"] = heads == 0
	if heads == 0:
		var before: float = boss["c"]
		var after := fmod(before + dt, 2.3 * pace)
		boss["c"] = after
		if _passed(before, after, 0.5):
			boss["d"] = float(boss["d"]) + 0.26
			_ring(g, Vector2(float(core["x"]), float(core["y"]) + 12.0), 12, 78.0, float(boss["d"]))
		boss["b"] = float(boss["b"]) - dt
		if float(boss["b"]) <= 0.0:
			boss["b"] = 0.9 * pace
			Foes.spawn(g, "debris", g.rng.float_range(40.0, 440.0), 80.0)
		return
	var hurry := pow(0.75, 3 - heads)
	# One head at a time rears back and strikes at a diver.
	boss["a"] = float(boss["a"]) - dt
	if float(boss["a"]) <= 0.0:
		boss["a"] = 5.2 * pace * hurry
		var ready: Array = []
		for entry: Dictionary in boss["parts"]:
			if entry["n"] == "head" and entry["alive"] and int(entry["m"]) == 0:
				ready.append(entry)
		var target: Dictionary = g.nearest_hero(240.0, 200.0)
		if not ready.is_empty() and not target.is_empty():
			var striker: Dictionary = g.rng.pick(ready)
			striker["m"] = 1
			striker["mt"] = 0.65
			striker["lx"] = clampf(float(target["x"]), 40.0, 440.0)
			striker["ly"] = minf(float(target["y"]) - 10.0, 222.0)
			g.sfx("alarm")
	for entry: Dictionary in boss["parts"]:
		if entry["n"] != "head" or not entry["alive"]:
			continue
		match int(entry["m"]):
			0:
				entry["ft"] = float(entry["ft"]) - dt
				if float(entry["ft"]) <= 0.0:
					entry["ft"] = 2.7 * pace * hurry
					_aimed(g, Vector2(float(entry["x"]), float(entry["y"]) + 10.0), 92.0, [0.0])
			1:
				entry["mt"] = float(entry["mt"]) - dt
				if float(entry["mt"]) <= 0.0:
					entry["m"] = 2
					entry["mt"] = 0.42
					entry["sx"] = entry["x"]
					entry["sy"] = entry["y"]
					g.sfx("lunge")
			2:
				entry["mt"] = float(entry["mt"]) - dt
				var along := 1.0 - maxf(0.0, float(entry["mt"])) / 0.42
				entry["x"] = lerpf(float(entry["sx"]), float(entry["lx"]), along)
				entry["y"] = lerpf(float(entry["sy"]), float(entry["ly"]), along)
				if float(entry["mt"]) <= 0.0:
					entry["m"] = 3
					entry["mt"] = 0.35
					g.shake(2.0)
			3:
				entry["mt"] = float(entry["mt"]) - dt
				if float(entry["mt"]) <= 0.0:
					entry["m"] = 4
					entry["mt"] = 0.8
			4:
				entry["mt"] = float(entry["mt"]) - dt
				var back := 1.0 - maxf(0.0, float(entry["mt"])) / 0.8
				var home := _head_home(boss, entry)
				entry["x"] = lerpf(float(entry["lx"]), home.x, back)
				entry["y"] = lerpf(float(entry["ly"]), home.y, back)
				if float(entry["mt"]) <= 0.0:
					entry["m"] = 0
		_touch(g, part_box(entry).grow(-2.0))

# ---- 2: the Gantry Leviathan ----

static func _gantry(g: Variant, boss: Dictionary, dt: float) -> void:
	var world: World = g.world
	var centre := float(world.def["boss_col"]) * World.TILE + 240.0
	var claw := part(boss, "claw")
	var core := part(boss, "core")
	var left := part(boss, "turret", 0)
	var right := part(boss, "turret", 1)
	var x: float = boss["x"]
	var pace: float = g.pace
	var fury: bool = not claw["alive"]
	var state: int = boss["st"]
	if boss["active"]:
		match state:
			0:
				# Patrol the rail, and now and then go after a diver with the claw.
				x += int(boss["dir"]) * (72.0 if fury else 46.0) * dt
				if absf(x - centre) > 150.0:
					x = centre + signf(x - centre) * 150.0
					boss["dir"] = -int(boss["dir"])
				if claw["alive"]:
					boss["a"] = float(boss["a"]) - dt
					if float(boss["a"]) <= 0.0:
						boss["st"] = 1
						boss["c"] = 1.4
			1:
				var target: Dictionary = g.nearest_hero(x, 200.0)
				var goal := clampf(float(target["x"]) if not target.is_empty() else x, centre - 190.0, centre + 190.0)
				x = move_toward(x, goal, 118.0 * dt)
				boss["c"] = float(boss["c"]) - dt
				if absf(goal - x) < 3.0 or float(boss["c"]) <= 0.0:
					boss["st"] = 2
					boss["c"] = 0.5
					g.sfx("alarm")
			2:
				boss["c"] = float(boss["c"]) - dt
				if float(boss["c"]) <= 0.0:
					boss["st"] = 3
					g.sfx("lunge")
			3:
				claw["y"] = float(claw["y"]) + 520.0 * dt
				var floor_y: float = world.landing(x - 8.0, x + 8.0, float(claw["y"]) - 20.0, float(claw["y"]) + 17.0, true)
				if floor_y < INF or float(claw["y"]) > 250.0:
					claw["y"] = minf(float(claw["y"]), (floor_y if floor_y < INF else 250.0) - 17.0)
					boss["st"] = 4
					boss["c"] = 1.0
					g.shake(7.0)
					g.sfx("slam")
					g.dust(x - 10.0, float(claw["y"]) + 17.0)
					g.dust(x + 10.0, float(claw["y"]) + 17.0)
					g.foe_shot(x - 12.0, float(claw["y"]) + 10.0, -142.0 * float(g.shot_speed), 0.0, "spike")
					g.foe_shot(x + 12.0, float(claw["y"]) + 10.0, 142.0 * float(g.shot_speed), 0.0, "spike")
			4:
				boss["c"] = float(boss["c"]) - dt
				if float(boss["c"]) <= 0.0:
					boss["st"] = 5
			5:
				claw["y"] = float(claw["y"]) - 130.0 * dt
				if float(claw["y"]) <= 132.0:
					claw["y"] = 132.0
					boss["st"] = 0
					boss["a"] = 4.4 * pace
		if not claw["alive"] and state != 0:
			boss["st"] = 0
		# The turrets take turns.
		boss["b"] = float(boss["b"]) - dt
		if float(boss["b"]) <= 0.0:
			boss["b"] = 1.25 * pace
			boss["n"] = int(boss["n"]) + 1
			var gunner := left if int(boss["n"]) % 2 == 0 else right
			if not gunner["alive"]:
				gunner = right if is_same(gunner, left) else left
			if gunner["alive"]:
				_aimed(g, Vector2(float(gunner["x"]), float(gunner["y"]) + 10.0), 100.0, [0.0])
		if fury:
			var before: float = boss["d"]
			var after := fmod(before + dt, 3.4 * pace)
			boss["d"] = after
			if _passed(before, after, 0.8) or _passed(before, after, 2.5 * pace):
				_aimed(g, Vector2(x, float(core["y"]) + 10.0), 96.0, [-0.5, -0.25, 0.0, 0.25, 0.5])
			if _passed(before, after, 1.7 * pace):
				_lob(g, Vector2(x, float(core["y"]) + 10.0))
	core["vuln"] = fury or int(boss["st"]) >= 3
	boss["x"] = x
	left["x"] = x - 39.0
	right["x"] = x + 39.0
	claw["x"] = x
	core["x"] = x
	if claw["alive"]:
		_touch(g, part_box(claw).grow(-3.0))
