extends RefCounted

## How the foes of Keg Burrow move and fight. Every function takes the game (main.gd) as `g` and reads or changes its field; all randomness comes from g.rng, so a run replays exactly.
##
##   grub    a mud grub that ambles along and turns at random
##   mite    a spark mite, fast, turning at every junction
##   beetle  a pincer beetle that finds the shortest way to the nearest digger
##   wisp    a gloom wisp that drifts through blocks towards a digger
##   shell   a stoneback that takes two blasts and charges down a clear line
##   boss    a 2x2 claw: tier 0 the Geode Claw, tier 1 the Molten Claw

const Levels := preload("res://games/keg_maze/levels.gd")
const Actors := preload("res://games/keg_maze/actors.gd")

const SPECS := {
	"grub": {"speed": 1.4, "hp": 1, "points": 100},
	"mite": {"speed": 2.4, "hp": 1, "points": 200},
	"beetle": {"speed": 1.8, "hp": 1, "points": 300},
	"wisp": {"speed": 1.1, "hp": 1, "points": 400},
	"shell": {"speed": 1.2, "hp": 2, "points": 500},
}
const BOSSES := [
	{"hp": 6, "speed": 1.3, "rage_speed": 1.8, "attack": 4.6, "rage_attack": 3.4, "rocks": 4, "rage_rocks": 6, "pattern": ["rock", "spawn", "rock"], "minions": ["grub"], "points": 5000},
	{"hp": 10, "speed": 1.5, "rage_speed": 2.1, "attack": 4.2, "rage_attack": 3.0, "rocks": 5, "rage_rocks": 8, "pattern": ["rock", "spit", "spawn", "rock", "spit"], "minions": ["mite", "beetle"], "points": 10000},
]
const SPEED_SCALE := [0.85, 1.0, 1.15]
const CHARGE_SPEED := 2.6
const SIGHT := 7
const HIT_INVULN := 1.0
const SPIT_REACH := 5
const SPIT_TELL := 0.9
const MAX_MINIONS := 3
const ROCK_DELAY := 1.2

static func make(kind: String, cell: Vector2i, stage: int, difficulty: int, tier: int = 0) -> Actors.Foe:
	var foe := Actors.Foe.new()
	foe.kind = kind
	foe.cell = cell
	var scale := float(SPEED_SCALE[clampi(difficulty, 0, 2)])
	if kind == "boss":
		var boss: Dictionary = BOSSES[tier]
		foe.tier = tier
		foe.size = 2
		foe.hp = int(boss["hp"])
		foe.speed = float(boss["speed"]) * scale
		foe.points = int(boss["points"])
		foe.attack = float(boss["attack"])
		foe.rest = 1.0
	else:
		var spec: Dictionary = SPECS[kind]
		foe.hp = int(spec["hp"])
		foe.speed = float(spec["speed"]) * scale * (1.0 + 0.02 * float(stage))
		foe.points = int(spec["points"])
	foe.max_hp = foe.hp
	return foe

static func step(g: Variant, delta: float) -> void:
	for foe: Actors.Foe in g.foes.duplicate():
		if foe.dying > 0.0:
			foe.dying -= delta
			if foe.dying <= 0.0:
				g.foes.erase(foe)
			continue
		foe.anim += delta
		foe.invuln = maxf(0.0, foe.invuln - delta)
		if foe.rest > 0.0:
			foe.rest -= delta
			continue
		if foe.kind == "boss":
			_step_boss(g, foe, delta)
			continue
		if foe.dir == Vector2i.ZERO:
			_choose(g, foe)
			if foe.dir == Vector2i.ZERO:
				continue
		# Something was put down in the cell ahead after the step began: turn back while there is still room.
		if foe.t < 0.5 and not _can_enter(g, foe, foe.cell + foe.dir, false):
			foe.cell += foe.dir
			foe.dir = -foe.dir
			foe.t = 1.0 - foe.t
			foe.charge = false
		foe.t += foe.speed * (CHARGE_SPEED if foe.charge else 1.0) * delta
		if foe.t >= 1.0:
			foe.cell += foe.dir
			foe.t -= 1.0
			_choose(g, foe)
			if foe.dir == Vector2i.ZERO:
				foe.t = 0.0

## Whether a foe may step into a cell. `wary` foes also refuse a cell that is on fire.
static func _can_enter(g: Variant, foe: Actors.Foe, cell: Vector2i, wary: bool = true) -> bool:
	if not Levels.inside(cell):
		return false
	var at := Levels.index(cell)
	var tile: int = g.grid[at]
	if foe.kind == "wisp":
		if tile == Levels.WALL or tile == Levels.BURNING:
			return false
	elif tile != Levels.FLOOR:
		return false
	if g.keg_at(cell) != null:
		return false
	return not (wary and g.flames.has(at))

static func _choose(g: Variant, foe: Actors.Foe) -> void:
	var open: Array[Vector2i] = []
	for dir in Levels.DIRS:
		if _can_enter(g, foe, foe.cell + dir):
			open.append(dir)
	if open.is_empty():
		foe.dir = Vector2i.ZERO
		foe.charge = false
		return
	var ahead := foe.dir != Vector2i.ZERO and open.has(foe.dir)
	match foe.kind:
		"mite":
			foe.dir = _wander(g, foe, open, 0.0)
		"beetle":
			var step_dir := Vector2i.ZERO
			if g.rng.chance(0.8):
				step_dir = _chase(g, foe)
			foe.dir = step_dir if step_dir != Vector2i.ZERO and open.has(step_dir) else _wander(g, foe, open, 0.75)
		"wisp":
			var target: Vector2i = g.nearest_hero(foe.cell)
			if target.x >= 0 and g.rng.chance(0.7):
				var best := open[0]
				for dir in open:
					if _steps(foe.cell + dir, target) < _steps(foe.cell + best, target):
						best = dir
				foe.dir = best
			else:
				foe.dir = _wander(g, foe, open, 0.5)
		"shell":
			if foe.charge:
				if ahead:
					return
				foe.charge = false
				foe.rest = 0.6
				foe.dir = Vector2i.ZERO
				return
			var seen := _sight(g, foe)
			if seen != Vector2i.ZERO:
				foe.dir = seen
				foe.charge = true
				g.audio.play("charge")
				return
			foe.dir = _wander(g, foe, open, 0.75)
		_:
			foe.dir = _wander(g, foe, open, 0.75)

## Keep going with probability `keep`, otherwise turn; turning back is the last choice.
static func _wander(g: Variant, foe: Actors.Foe, open: Array[Vector2i], keep: float) -> Vector2i:
	if foe.dir != Vector2i.ZERO and open.has(foe.dir) and keep > 0.0 and g.rng.chance(keep):
		return foe.dir
	var pool: Array[Vector2i] = []
	for dir in open:
		if dir != -foe.dir:
			pool.append(dir)
	if pool.is_empty():
		pool = open
	return pool[g.rng.int_range(0, pool.size() - 1)]

static func _steps(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

## The direction in which a digger stands in a clear straight line, or zero.
static func _sight(g: Variant, foe: Actors.Foe) -> Vector2i:
	for dir in Levels.DIRS:
		var cell := foe.cell
		for reach in SIGHT:
			cell += dir
			if not _can_enter(g, foe, cell):
				break
			if g.hero_on(cell):
				return dir
	return Vector2i.ZERO

## First step of the shortest open path to the nearest digger (breadth-first over floor cells without kegs), or zero when none can be reached.
static func _chase(g: Variant, foe: Actors.Foe) -> Vector2i:
	var from := PackedInt32Array()
	from.resize(Levels.COLS * Levels.ROWS)
	from.fill(-1)
	var start := Levels.index(foe.cell)
	from[start] = start
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		var cell := Levels.cell_of(at)
		if at != start and g.hero_on(cell):
			while from[at] != start:
				at = from[at]
			return Levels.cell_of(at) - foe.cell
		for dir in Levels.DIRS:
			var next := cell + dir
			var next_at := Levels.index(next)
			if Levels.inside(next) and from[next_at] < 0 and g.grid[next_at] == Levels.FLOOR and g.keg_at(next) == null:
				from[next_at] = at
				queue.append(next_at)
	return Vector2i.ZERO

## A blast reached a foe. `owner` is the slot of the player whose keg it was and `chain` the chain reaction it belongs to.
static func damage(g: Variant, foe: Actors.Foe, owner: int, chain: int) -> void:
	if foe.invuln > 0.0 or foe.dying > 0.0:
		return
	foe.hp -= 1
	if foe.hp > 0:
		foe.invuln = HIT_INVULN
		if foe.kind == "boss":
			g.award(owner, 300, foe.spot() + Vector2i(1, 0))
			g.audio.play("boss_hit")
			g.emit_fx("boss_hit", foe.spot())
			if foe.hp * 2 <= foe.max_hp and (foe.hp + 1) * 2 > foe.max_hp:
				g.audio.play("boss_tell")
				g.emit_fx("rage", foe.spot())
		else:
			foe.speed *= 1.35
			foe.charge = false
			g.audio.play("crack")
			g.emit_fx("crack", foe.spot())
		return
	var streak := int(g.chain_kills.get(chain, 0)) + 1
	g.chain_kills[chain] = streak
	g.kills += 1
	g.best_streak = maxi(g.best_streak, streak)
	foe.dying = 0.5
	if foe.kind == "boss":
		foe.dying = 1.8
		g.bosses_beaten += 1
		g.award(owner, foe.points, foe.spot() + Vector2i(1, 0))
		g.audio.play("boss_die")
		g.emit_fx("boss_die", foe.spot())
		for other: Actors.Foe in g.foes:
			if other != foe and other.dying <= 0.0:
				other.dying = 0.5
				g.emit_fx("foe_die", other.spot(), other.kind)
		g.hazards.clear()
		return
	g.award(owner, foe.points * mini(streak, 5), foe.spot())
	g.audio.play("foe_die", 1.0 + 0.12 * float(mini(streak, 6) - 1))
	g.emit_fx("foe_die", foe.spot(), foe.kind)

# ---- boss ----

static func _step_boss(g: Variant, foe: Actors.Foe, delta: float) -> void:
	var boss: Dictionary = BOSSES[foe.tier]
	var raging := foe.hp * 2 <= foe.max_hp
	if foe.tell > 0.0:
		foe.tell -= delta
		if foe.tell <= 0.0:
			_spit(g, foe)
		return
	foe.attack -= delta
	if foe.dir == Vector2i.ZERO:
		if foe.attack <= 0.0:
			_attack(g, foe, boss, raging)
			if foe.tell > 0.0:
				return
		_choose_boss(g, foe)
		if foe.dir == Vector2i.ZERO:
			return
	foe.t += float(boss["rage_speed"] if raging else boss["speed"]) * (foe.speed / float(boss["speed"])) * delta
	if foe.t >= 1.0:
		foe.cell += foe.dir
		foe.t = 0.0
		foe.dir = Vector2i.ZERO
		_crush(g, foe)

static func _attack(g: Variant, foe: Actors.Foe, boss: Dictionary, raging: bool) -> void:
	var pattern: Array = boss["pattern"]
	var move: String = pattern[foe.cycle % pattern.size()]
	foe.cycle += 1
	foe.attack = float(boss["rage_attack"] if raging else boss["attack"])
	match move:
		"rock":
			_rockfall(g, int(boss["rage_rocks"] if raging else boss["rocks"]))
		"spawn":
			_spawn(g, foe, boss)
		"spit":
			foe.tell = SPIT_TELL
			g.audio.play("boss_tell")
			g.emit_fx("tell", foe.cell)

static func _boss_free(g: Variant, foe: Actors.Foe, base: Vector2i) -> bool:
	for y in foe.size:
		for x in foe.size:
			var cell := base + Vector2i(x, y)
			if not Levels.inside(cell):
				return false
			var tile: int = g.grid[Levels.index(cell)]
			if tile == Levels.WALL or tile == Levels.BURNING or g.keg_at(cell) != null:
				return false
	return true

static func _choose_boss(g: Variant, foe: Actors.Foe) -> void:
	var open: Array[Vector2i] = []
	for dir in Levels.DIRS:
		if _boss_free(g, foe, foe.cell + dir):
			open.append(dir)
	if open.is_empty():
		return
	var target: Vector2i = g.nearest_hero(foe.cell)
	var pick := Vector2i.ZERO
	if target.x >= 0 and g.rng.chance(0.75):
		# Twice the offset from the middle of the 2x2 body, to stay in whole numbers.
		var gap := target * 2 - (foe.cell * 2 + Vector2i(1, 1))
		var along := Vector2i(signi(gap.x), 0)
		var across := Vector2i(0, signi(gap.y))
		if absi(gap.y) > absi(gap.x):
			var held := along
			along = across
			across = held
		if along != Vector2i.ZERO and open.has(along):
			pick = along
		elif across != Vector2i.ZERO and open.has(across):
			pick = across
	if pick == Vector2i.ZERO:
		pick = open[g.rng.int_range(0, open.size() - 1)]
	foe.dir = pick

## A boss flattens the blocks it walks onto; whatever they hid is left on the floor.
static func _crush(g: Variant, foe: Actors.Foe) -> void:
	for cell in foe.cells():
		var at := Levels.index(cell)
		if g.grid[at] == Levels.CRATE:
			g.grid[at] = Levels.FLOOR
			g.uncover(at)
			g.audio.play("crush")
			g.emit_fx("crate", cell)

static func _rockfall(g: Variant, count: int) -> void:
	var marked := {}
	for slot: int in g.active_players():
		var hero: Actors.Hero = g.heroes[slot]
		if hero.in_field():
			marked[hero.spot()] = true
	var tries := 0
	while marked.size() < count and tries < 60:
		tries += 1
		var cell := Vector2i(g.rng.int_range(1, Levels.COLS - 2), g.rng.int_range(1, Levels.ROWS - 2))
		if g.grid[Levels.index(cell)] == Levels.FLOOR and cell != g.exit_cell:
			marked[cell] = true
	for cell: Vector2i in marked:
		g.hazards.append({"cell": cell, "ttl": ROCK_DELAY, "total": ROCK_DELAY})
	g.audio.play("rock_warn")

static func _spawn(g: Variant, foe: Actors.Foe, boss: Dictionary) -> void:
	var minions := 0
	for other: Actors.Foe in g.foes:
		if other.kind != "boss" and other.dying <= 0.0:
			minions += 1
	if minions >= MAX_MINIONS:
		_rockfall(g, int(boss["rocks"]))
		return
	var probe := Actors.Foe.new()
	var spots: Array[Vector2i] = []
	for y in range(-1, foe.size + 1):
		for x in range(-1, foe.size + 1):
			if x >= 0 and x < foe.size and y >= 0 and y < foe.size:
				continue
			var cell := foe.cell + Vector2i(x, y)
			var target: Vector2i = g.nearest_hero(cell)
			if _can_enter(g, probe, cell) and (target.x < 0 or _steps(cell, target) > 2):
				spots.append(cell)
	if spots.is_empty():
		return
	var kinds: Array = boss["minions"]
	var kind: String = kinds[g.rng.int_range(0, kinds.size() - 1)]
	var minion := make(kind, spots[g.rng.int_range(0, spots.size() - 1)], g.stage, g.difficulty)
	minion.rest = 0.7
	g.foes.append(minion)
	g.audio.play("spawn")
	g.emit_fx("spawn", minion.cell)

## Fire shoots out of every side of the boss in straight lines. It burns blocks and sets off kegs like any blast, but it is nobody's: it harms diggers and not foes.
static func _spit(g: Variant, foe: Actors.Foe) -> void:
	for d in 4:
		var dir: Vector2i = Levels.DIRS[d]
		for side in foe.size:
			# The two body cells that face this direction.
			var from := foe.cell + (Vector2i(side, 0 if dir.y < 0 else foe.size - 1) if dir.x == 0 else Vector2i(0 if dir.x < 0 else foe.size - 1, side))
			g.fire_line(from, d, SPIT_REACH, -1, 0)
	g.audio.play("spit")
	g.emit_fx("spit", foe.cell)
