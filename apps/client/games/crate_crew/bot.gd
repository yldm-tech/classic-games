extends RefCounted

## An autopilot for one squirrel, used by the tests to prove with real inputs that every level can be crossed, every boss beaten and a whole route won. It only reads the world and answers, every step, which controls it holds; the caller feeds them to the module like a player would. It follows the guide points each level lays along its way (builder.gd `_way`), jumps at walls, gaps, hazards and ledges, picks up whatever lies in front of it, throws at enemies ahead (upwards at fliers overhead), and in a boss room fetches the boss's lumps and throws them back.

const World := preload("res://games/crate_crew/world.gd")
const Foes := preload("res://games/crate_crew/foes.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Bosses := preload("res://games/crate_crew/bosses.gd")

var slot := 0
## On the map, which of two offered paths to take: 0 the first, 1 the second.
var branch := 0
## Whether it plays at all: an idle bot only stands there (the tests lose a run with it).
var idle := false

var _level := ""
var _index := 0
var _held: Dictionary = {}
var _jump_hold := 0.0
var _stuck := 0.0
var _last := Vector2.ZERO
var _back := 0.0
var _map_wait := 0.0
var _grab_wait := 0.0
var _waited := 0.0
var _yield := 0.0
var _ignore: Array = []

func _init(seat: int = 0, path: int = 0) -> void:
	slot = seat
	branch = path

## The controls to hold for the coming step: { control name: true }.
func controls(world: World) -> Dictionary:
	var want := {}
	if idle:
		_held = want
		return want
	if world.phase == World.P_MAP:
		want = _on_map(world)
	elif world.phase == World.P_PLAY:
		var hero: Dictionary = world.heroes[slot]
		if world.level_id != _level:
			_level = world.level_id
			_index = 0
			_ignore.clear()
			_last = Vector2(float(hero["x"]), float(hero["y"]))
		match int(hero["state"]):
			World.H_NORMAL:
				want = _in_boss_room(world, hero) if not world.boss.is_empty() else _in_level(world, hero)
			World.H_CARRIED:
				want = {"a": not _held.has("a")}
	if want.has("jump_hold"):
		want.erase("jump_hold")
		_jump_hold = 0.4
	if world.phase == World.P_PLAY and not world.boss.is_empty():
		var hero: Dictionary = world.heroes[slot]
		if not bool(hero["ground"]) and _jump_hold > 0.0 and float(hero["vy"]) < 0.0:
			_jump_hold -= 1.0 / 60.0
			want["a"] = true
	# A button that has to be pressed again is let go for one step first.
	for button: String in ["a", "b"]:
		if want.get(button + "_tap", false):
			want.erase(button + "_tap")
			if _held.has(button):
				want.erase(button)
			else:
				want[button] = true
	for key: String in want.keys():
		if not bool(want[key]):
			want.erase(key)
	_held = want
	return want

func _on_map(world: World) -> Dictionary:
	_map_wait += 1.0 / 60.0
	var choices := world.map_choices()
	if choices.is_empty() or _map_wait < 0.3:
		return {}
	var goal: String = choices[mini(branch, choices.size() - 1)]
	if world.cursor != goal:
		if _held.size() > 0:
			return {}
		var from: Vector2 = Levels.NODES[world.cursor]["at"]
		var way: Vector2 = (Levels.NODES[goal]["at"] as Vector2) - from
		var push := ""
		if absf(way.x) > absf(way.y):
			push = "right" if way.x > 0.0 else "left"
		else:
			push = "down" if way.y > 0.0 else "up"
		return {push: true}
	if world.marker.distance_to(Levels.NODES[goal]["at"]) > 0.5:
		return {}
	_map_wait = 0.0
	return {"a_tap": true}

# ---- crossing a level ----

func _in_level(world: World, hero: Dictionary) -> Dictionary:
	var guide: Array = world.level.get("guide", [])
	var x := float(hero["x"])
	var y := float(hero["y"])
	var grounded := bool(hero["ground"])
	while _index < guide.size():
		var point: Vector2 = guide[_index]
		var near := absf(point.x - x) < 10.0 and point.y - y > -6.0 and point.y - y < 72.0 and grounded
		# Past it on the way to the next one, at its height: it counts as reached.
		if not near and _index + 1 < guide.size() and grounded and absf(point.y - y) < 14.0:
			var next: Vector2 = guide[_index + 1]
			if absf(next.y - point.y) < 14.0 and signf(next.x - point.x) == signf(x - point.x) and absf(x - point.x) < absf(next.x - point.x):
				near = true
		if not near:
			break
		_index += 1
	# Put back somewhere else (a lost life, a burrow): carry on from the nearest guide point.
	if Vector2(x, y).distance_to(_last) > 48.0 and not guide.is_empty():
		var nearest := -1
		for index in guide.size():
			var point: Vector2 = guide[index]
			# A point on this floor first; only then the nearest one anywhere.
			var score := point.distance_to(Vector2(x, y)) + (0.0 if absf(point.y - y) < 6.0 else 10000.0)
			var best_score := 1e12 if nearest < 0 else (guide[nearest] as Vector2).distance_to(Vector2(x, y)) + (0.0 if absf((guide[nearest] as Vector2).y - y) < 6.0 else 10000.0)
			if score < best_score:
				nearest = index
		_index = nearest
	var target: Vector2 = guide[mini(_index, guide.size() - 1)] if not guide.is_empty() else Vector2(x + 100.0, y)
	# Knocked down below the way: pick the way up again from the guide point on this floor.
	if grounded and target.y < y - 40.0:
		var best := -1
		var best_dx := 1e9
		for index in guide.size():
			var point: Vector2 = guide[index]
			# The point of the floor it stands on (it may stand on a crate up to two high on it).
			if point.y - y > -6.0 and point.y - y < 40.0 and absf(point.x - x) < best_dx + 48.0:
				if best < 0 or point.y < (guide[best] as Vector2).y - 1.0 or (absf(point.y - (guide[best] as Vector2).y) < 1.0 and absf(point.x - x) < best_dx):
					best_dx = absf(point.x - x)
					best = index
		if best >= 0 and best + 1 < _index:
			_index = best + 1
			target = guide[_index]
	var want := _fight(world, hero)
	if want.has("done"):
		want.erase("done")
		return want
	_move_to(world, hero, target, want)
	return want

## Throw at enemies in reach, pick up what lies ahead. Returns the controls; "done" in it means nothing else should be added this step.
func _fight(world: World, hero: Dictionary) -> Dictionary:
	var x := float(hero["x"])
	var y := float(hero["y"])
	var facing := int(hero["face"])
	var carrying: bool = hero["carry"] != null
	_grab_wait = maxf(0.0, _grab_wait - 1.0 / 60.0)
	var ahead: Dictionary = {}
	var overhead: Dictionary = {}
	var nearest := 1e9
	for foe: Dictionary in world.foes:
		if int(foe["state"]) != Foes.ALIVE:
			continue
		var dx := float(foe["x"]) - x
		var dy := y - float(foe["y"])
		if absf(dx) < 150.0 and absf(dy) < 18.0 and absf(dx) < nearest:
			if world.is_seen(float(foe["x"]), float(foe["y"]), 0.0):
				nearest = absf(dx)
				ahead = foe
		elif absf(dx) < 14.0 and dy > 14.0 and dy < 150.0 and overhead.is_empty():
			overhead = foe
	# A flier close above: throw up at it, or wait for it to pass before jumping into its way.
	var flier: Dictionary = {}
	for foe: Dictionary in world.foes:
		if int(foe["state"]) == Foes.ALIVE and bool(foe["flies"]) and absf(float(foe["x"]) - x) < 44.0 and y - float(foe["y"]) > 6.0 and y - float(foe["y"]) < 70.0:
			flier = foe
	if not flier.is_empty():
		if carrying and absf(float(flier["x"]) - x) < 12.0:
			return {"done": true, "up": true, "b_tap": true}
		# A biplane sweeps the space between shelves: let it go by before jumping up into it, but never wait long.
		var coming := (float(flier["x"]) - x) * float(int(flier["face"])) < 0.0
		if bool(hero["ground"]) and not carrying and str(flier["kind"]) == "plane" and coming and _waited < 1.2:
			_waited += 1.0 / 60.0
			return {"done": true}
	if flier.is_empty():
		_waited = 0.0
	if carrying:
		if not ahead.is_empty():
			var side := 1 if float(ahead["x"]) > x else -1
			if side != facing:
				return {"done": true, "right" if side > 0 else "left": true}
			return {"done": true, "b_tap": true}
		if not overhead.is_empty():
			return {"done": true, "up": true, "b_tap": true}
		return {}
	# Empty-handed: lift what is right in front, or under the feet when an enemy comes.
	if _grab_wait <= 0.0:
		for object: Dictionary in world.objects:
			if int(object["state"]) != World.O_REST or _ignore.has(object):
				continue
			var dx := (float(object["x"]) - x) * float(facing)
			if dx > -2.0 and dx < float(object["half"]) + World.HERO_HALF + 4.0 and absf(float(object["y"]) - y) < 4.0:
				_grab_wait = 0.4
				_ignore.append(object)
				return {"done": true, "b_tap": true}
	if not ahead.is_empty() and nearest < 34.0 and bool(hero["ground"]):
		return {"a_tap": true, "jump_hold": true}
	return {}

## Run towards a point, jumping where the way needs it.
func _move_to(world: World, hero: Dictionary, target: Vector2, want: Dictionary) -> void:
	var x := float(hero["x"])
	var y := float(hero["y"])
	var grounded := bool(hero["ground"])
	var dx := target.x - x
	var dir := 0 if absf(dx) < 3.0 else (1 if dx > 0.0 else -1)
	var step := 1.0 / 60.0
	if Vector2(x, y).distance_to(_last) < 0.6 and absf(dx) > 6.0:
		_stuck += step
	else:
		_stuck = maxf(0.0, _stuck - step * 2.0)
	_last = Vector2(x, y)
	if _back > 0.0:
		_back -= step
		dir = -dir if dir != 0 else -int(hero["face"])
	elif _stuck > 2.5:
		_back = 0.35
		_stuck = 0.0
	# The partner in the way: the second squirrel waits a moment, the first hops over (or onto its head and off).
	var partner: Dictionary = world.heroes[1 - slot]
	if dir != 0 and grounded and int(partner["state"]) == World.H_NORMAL and absf(float(partner["y"]) - y) < 8.0:
		var ahead := (float(partner["x"]) - x) * float(dir)
		if ahead > 0.0 and ahead < 16.0:
			if slot == 1 and _yield < 0.6:
				_yield += step
				return
			want["jump_hold"] = true
	else:
		_yield = maxf(0.0, _yield - step)
	if dir > 0:
		want["right"] = true
	elif dir < 0:
		want["left"] = true
	var jump := bool(want.get("jump_hold", false))
	want.erase("jump_hold")
	if grounded:
		var front := x + float(dir) * (World.HERO_HALF + 3.0)
		var wall := dir != 0 and (World.is_solid(world.tile_at_point(front + float(dir) * 2.0, y - 4.0)) or World.is_solid(world.tile_at_point(front + float(dir) * 2.0, y - 12.0)))
		# A thing in the way is lifted (see _fight) by walking up to it; one that would not come up is jumped.
		var thing: Variant = world.thing_at(front + float(dir) * 4.0, y - 6.0) if dir != 0 else null
		var block := thing != null and (hero["carry"] != null or _ignore.has(thing))
		var floor_ahead := world.is_floor(x + float(dir) * (World.HERO_HALF + 1.0), y + 2.0) or world.thing_at(x + float(dir) * (World.HERO_HALF + 1.0), y + 2.0) != null or _lift_under(world, x + float(dir) * (World.HERO_HALF + 1.0), y)
		var hazard := false
		# Burners, tacks, sludge and thorns are jumped from right at their edge, to clear them.
		if dir != 0 and world.tile_at_point(x + float(dir) * (World.HERO_HALF + 3.0), y - 4.0) == Levels.HAZARD:
			hazard = true
		var above := target.y < y - 10.0 and absf(dx) < 44.0
		var below := target.y > y + 10.0
		if wall or block or hazard or above:
			jump = true
		# A gap a moving platform crosses: wait at the edge until it is there.
		if dir != 0 and not floor_ahead and _lift_serves(world, x, y):
			want.erase("right")
			want.erase("left")
			return
		# A gap: jump it, unless the way goes down and there is floor not far below the edge.
		if dir != 0 and not floor_ahead and not (below and _floor_below(world, x + float(dir) * (World.HERO_HALF + 6.0), y, target.y)):
			jump = true
		if below and absf(dx) < 12.0 and world.tile_at_point(x, y + 1.0) == Levels.SHELF:
			want["down"] = true
			want["a_tap"] = true
			return
		if _stuck > 1.0:
			jump = true
	if jump and grounded:
		want["a_tap"] = true
		_jump_hold = 0.4
	elif _jump_hold > 0.0 and float(hero["vy"]) < 0.0:
		_jump_hold -= step
		want["a"] = true

## Whether something to stand on lies under a point, no deeper than a little below `goal_y`.
func _floor_below(world: World, x: float, y: float, goal_y: float) -> bool:
	var depth := y + 2.0
	while depth < maxf(goal_y, y) + 24.0 and depth < float(world.height) * World.TILE:
		if world.is_floor(x, depth):
			return true
		depth += 8.0
	return false

## Whether a moving platform travels past this edge at this height.
func _lift_serves(world: World, x: float, y: float) -> bool:
	for lift: Dictionary in world.lifts:
		var from: Vector2 = lift["from"]
		var to: Vector2 = lift["to"]
		var left := minf(from.x, to.x) - 24.0
		var right := maxf(from.x, to.x) + float(lift["w"]) + 24.0
		if x > left and x < right and y > minf(from.y, to.y) - 24.0 and y < maxf(from.y, to.y) + 24.0:
			return true
	return false

func _lift_under(world: World, x: float, y: float) -> bool:
	for lift: Dictionary in world.lifts:
		if x > float(lift["x"]) and x < float(lift["x"]) + float(lift["w"]) and absf(float(lift["y"]) - y) < 4.0:
			return true
	return false

# ---- a boss room ----

func _in_boss_room(world: World, hero: Dictionary) -> Dictionary:
	var boss: Dictionary = world.boss
	var x := float(hero["x"])
	var y := float(hero["y"])
	var bx := float(boss["x"])
	var by := float(boss["y"])
	var kind := str(boss["kind"])
	var mode := str(boss["mode"])
	var carrying: Variant = hero["carry"]
	var away := 1.0 if x >= bx else -1.0
	var gap := absf(bx - x)
	# Out from under whatever is coming down: where it will land is worked out as the game marks it.
	for shot: Dictionary in world.shots:
		var land := _landing(world, shot)
		if float(shot["g"]) > 0.0 and absf(land - x) < 20.0 and float(shot["y"]) < y:
			var side := 1.0 if x >= land else -1.0
			if x < 50.0:
				side = 1.0
			elif x > 334.0:
				side = -1.0
			return {"right" if side > 0.0 else "left": true}
	# Out of the way of an attack that has been announced.
	if (mode == "rise_tell" or mode == "snap_tell" or mode == "snap") and gap < 84.0:
		return _flee(x, away)
	if mode == "charge_tell" or mode == "charge" or mode == "hop_tell" or mode == "hop":
		if gap < 160.0 and bool(hero["ground"]):
			# Up onto a shelf at the side, or over the top.
			return {"a_tap": true, "jump_hold": true, "right" if x < 192.0 else "left": true} if gap < 60.0 else _flee(x, away)
		if not bool(hero["ground"]):
			return {"a": true, "right" if away > 0.0 else "left": true}
	if kind == "crow" and (mode == "dive_tell" or mode == "dive"):
		var goal: Vector2 = boss["goal"]
		if absf(goal.x - x) < 40.0:
			return _flee(x, 1.0 if x >= goal.x else -1.0)
	if carrying is Dictionary and bool((carrying as Dictionary)["special"]):
		return _aim_at_boss(world, hero, boss)
	if carrying is Dictionary:
		# Not the boss's lump: put it down and go for one.
		return {"down": true, "b_tap": true}
	var best: Dictionary = {}
	var best_distance := 1e9
	for object: Dictionary in world.objects:
		if bool(object["special"]) and int(object["state"]) == World.O_REST and absf(float(object["x"]) - bx) > float(boss["half"]) + 10.0:
			var distance := absf(float(object["x"]) - x) + absf(float(object["y"]) - y) * 2.0
			if distance < best_distance:
				best_distance = distance
				best = object
	var want := {}
	if not best.is_empty():
		var ox := float(best["x"])
		var oy := float(best["y"])
		var reach := float(best["half"]) + World.HERO_HALF + 4.0
		if absf(oy - y) > 8.0:
			_move_to(world, hero, Vector2(ox, oy), want)
		elif absf(ox - x) > reach:
			want["right" if ox > x else "left"] = true
		elif (int(hero["face"]) > 0) != (ox > x):
			want["right" if ox > x else "left"] = true
		else:
			want["b_tap"] = true
		return want
	# Nothing to throw yet: keep away from it.
	if gap < 100.0 and absf(by - y) < 60.0:
		return _flee(x, away)
	return want

## Run away from something, turning back with a jump when a wall is reached.
func _flee(x: float, away: float) -> Dictionary:
	if (away < 0.0 and x < 40.0) or (away > 0.0 and x > 344.0):
		return {"a_tap": true, "jump_hold": true, "right" if away < 0.0 else "left": true}
	return {"right" if away > 0.0 else "left": true}

## Holding the boss's lump: get to a throwing distance on its level, face it and throw when it can be hurt; under the crow, throw up.
func _aim_at_boss(world: World, hero: Dictionary, boss: Dictionary) -> Dictionary:
	var x := float(hero["x"])
	var y := float(hero["y"])
	var bx := float(boss["x"])
	var by := float(boss["y"])
	var side := 1 if bx > x else -1
	var gap := absf(bx - x)
	var want := {}
	var low := absf(by - y) < 30.0 or (str(boss["kind"]) != "crow")
	if not low:
		# High above: right under it, then straight up.
		if gap < 8.0 and Bosses.is_open(boss):
			return {"up": true, "b_tap": true}
		want["right" if bx > x else "left"] = true
		return want
	var close := float(boss["half"]) + 40.0
	if gap < close and not ((side < 0 and x > 344.0) or (side > 0 and x < 40.0)):
		want["left" if side > 0 else "right"] = true
		return want
	if int(hero["face"]) != side:
		want["right" if side > 0 else "left"] = true
		return want
	if gap > 170.0:
		want["right" if side > 0 else "left"] = true
		return want
	# The throw flies at waist height: it has to meet the body.
	var meets := y - 2.0 > by - float(boss["tall"]) + 2.0 and y - 18.0 < by - 2.0
	if not meets and bool(hero["ground"]) and y < by - 8.0 and world.tile_at_point(x, y + 1.0) == Levels.SHELF:
		return {"down": true, "a_tap": true}
	if Bosses.is_open(boss) and bool(hero["ground"]) and meets:
		want["b_tap"] = true
	return want

## Where a falling shot will come down, by the same small steps the renderer marks it with.
func _landing(world: World, shot: Dictionary) -> float:
	var x := float(shot["x"])
	var y := float(shot["y"])
	var vx := float(shot["vx"])
	var vy := float(shot["vy"])
	var g := float(shot["g"])
	for index in 90:
		var t := float(index) * 0.02
		var px := x + vx * t
		if world.is_floor(px, y + vy * t + 0.5 * g * t * t + 3.0):
			return px
	return 1e6
