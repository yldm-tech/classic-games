extends RefCounted

## The two guardians: Magmaw the slag toad at the end of the highlands and Rimewing the frost owl at the end of the hollow.

const Creature := preload("res://games/ember_trail/creature.gd")
const World := preload("res://games/ember_trail/world.gd")

## The arena is the whole room, wall to wall: a guardian reaches every place the hero can stand, so no corner is out of its way.
const ARENA_LEFT := 6.0
const ARENA_RIGHT := 538.0
const FLOOR := 224.0
const TOAD_HP := 54
const OWL_HP := 30
## How far past a wall the owl's dive carries it, so the low point of the dive can be right at the wall.
const SWOOP_OVERSHOOT := 46.0
## Seconds the owl hangs at the top of a dive before it comes down, and how far down the dive goes.
const SWOOP_HANG := 0.35
const SWOOP_DEPTH := 84.0

static func make(kind: String, hp_scale: float) -> RefCounted:
	var boss := Creature.new()
	boss.kind = kind
	boss.sprite = kind
	boss.awake = true
	if kind == "toad":
		boss.hw = 21.0
		boss.h = 30.0
		boss.max_hp = maxi(1, roundi(float(TOAD_HP) * hp_scale))
		boss.points = 2000
		boss.pos = Vector2(430.0, -30.0)
	else:
		boss.hw = 15.0
		boss.h = 30.0
		boss.max_hp = maxi(1, roundi(float(OWL_HP) * hp_scale))
		boss.points = 3000
		boss.flying = true
		boss.pos = Vector2(600.0, 40.0)
	boss.hp = boss.max_hp
	boss.state = "enter"
	boss.data = {"attack": 0, "shots": 0, "hover": 0.0, "from": boss.pos, "to": boss.pos, "low": 0.0}
	return boss

static func enraged(boss: RefCounted) -> bool:
	return boss.hp * 2 <= boss.max_hp

static func step(game: Node2D, boss: RefCounted, delta: float) -> void:
	boss.flash = maxf(0.0, boss.flash - delta)
	boss.t += delta
	if boss.state == "dying":
		_dying(game, boss)
		return
	if boss.kind == "toad":
		_toad(game, boss, delta)
	else:
		_owl(game, boss, delta)

static func _dying(game: Node2D, boss: RefCounted) -> void:
	boss.frame = 0
	if int(boss.t * 60.0) % 8 == 0:
		var at: Vector2 = boss.pos + Vector2(game.fx.rng.float_range(-boss.hw, boss.hw), -game.fx.rng.float_range(0.0, boss.h))
		game.fx.burst(at, 10, "5678" if boss.kind == "toad" else "fgh8", 90.0, 120.0, 0.6)
		game.audio.play("spark_hit", 0.6)
		game.shake(2.5)
	if boss.t >= 2.0:
		boss.gone = true
		game.fx.burst(boss.pos + Vector2(0.0, -boss.h * 0.5), 60, "5678" if boss.kind == "toad" else "fgh8", 170.0, 140.0, 1.1)
		game.shake(7.0)

# ---- Magmaw ----

static func _toad(game: Node2D, boss: RefCounted, delta: float) -> void:
	var hero: RefCounted = game.hero
	var angry := enraged(boss)
	match boss.state:
		"enter":
			boss.frame = 2
			boss.vel.y = minf(boss.vel.y + 830.0 * delta, 460.0)
			boss.pos.y += boss.vel.y * delta
			if boss.pos.y >= FLOOR:
				_toad_lands(game, boss, false)
				game.audio.play("boss_roar")
				_enter(boss, "idle")
				boss.data["wait"] = 1.3
		"idle":
			boss.frame = 1 if boss.t > float(boss.data["wait"]) - 0.12 else 0
			if boss.t >= float(boss.data["wait"]):
				var pattern := ["hop", "spit", "hop", "hop", "spit"] if angry else ["hop", "hop", "spit"]
				var attack: String = pattern[int(boss.data["attack"]) % pattern.size()]
				boss.data["attack"] = int(boss.data["attack"]) + 1
				_enter(boss, "crouch" if attack == "hop" else "spit")
				boss.data["shots"] = 0
		"crouch":
			boss.frame = 1
			if boss.t >= (0.26 if angry else 0.4):
				boss.vel = Vector2(clampf((hero.pos.x - boss.pos.x) / 0.82, -175.0, 175.0), -340.0)
				_enter(boss, "air")
				game.audio.play("ram_jump", 0.6)
		"air":
			boss.frame = 2
			boss.vel.y = minf(boss.vel.y + 830.0 * delta, 460.0)
			boss.pos += boss.vel * delta
			boss.pos.x = clampf(boss.pos.x, ARENA_LEFT + boss.hw, ARENA_RIGHT - boss.hw)
			if boss.pos.y >= FLOOR and boss.vel.y > 0.0:
				_toad_lands(game, boss, true)
				_enter(boss, "idle")
				boss.data["wait"] = 0.7 if angry else 1.15
		"spit":
			boss.frame = 3
			var count := 4 if angry else 3
			var fired := int(boss.data["shots"])
			if fired < count and boss.t >= 0.35 + 0.28 * float(fired):
				boss.data["shots"] = fired + 1
				var reach := clampf((hero.pos.x - boss.pos.x) / 1.04, -200.0, 200.0) + float(fired - 1) * 30.0
				game.spawn_hazard("glob", boss.pos + Vector2(0.0, -16.0), Vector2(reach, -270.0), 520.0, 3.0)
				game.audio.play("spit", 0.8)
				game.fx.burst(boss.pos + Vector2(0.0, -16.0), 6, "567", 50.0, 120.0, 0.3, 40.0)
			if boss.t >= 0.35 + 0.28 * float(count) + 0.35:
				_enter(boss, "idle")
				boss.data["wait"] = 0.6 if angry else 1.0

static func _toad_lands(game: Node2D, boss: RefCounted, waves: bool) -> void:
	boss.pos.y = FLOOR
	boss.vel = Vector2.ZERO
	game.shake(5.0)
	game.audio.play("boss_land")
	game.fx.burst(boss.pos + Vector2(-18.0, 0.0), 8, "bc9", 70.0, 160.0, 0.5, 40.0)
	game.fx.burst(boss.pos + Vector2(18.0, 0.0), 8, "bc9", 70.0, 160.0, 0.5, 40.0)
	if waves:
		for side: float in [-1.0, 1.0]:
			game.spawn_hazard("wave", boss.pos + Vector2(side * 22.0, 0.0), Vector2(side * 125.0, 0.0), 0.0, 1.5)

# ---- Rimewing ----

static func _owl(game: Node2D, boss: RefCounted, delta: float) -> void:
	var hero: RefCounted = game.hero
	var angry := enraged(boss)
	var centre := (ARENA_LEFT + ARENA_RIGHT) * 0.5
	boss.frame = [0, 1, 2, 1][int(boss.t * (9.0 if angry else 7.0)) % 4]
	match boss.state:
		"enter":
			_fly_to(boss, Vector2(centre + 110.0, 124.0), 150.0, delta)
			if boss.t >= 1.5:
				game.audio.play("boss_screech")
				_enter(boss, "hover")
				boss.data["wait"] = 1.6
		"hover":
			boss.data["hover"] = float(boss.data["hover"]) + delta
			var along := float(boss.data["hover"])
			_fly_to(boss, Vector2(centre + 150.0 * sin(along * 0.8), 132.0 + 12.0 * sin(along * 2.1)), 130.0 if angry else 95.0, delta)
			if boss.t >= float(boss.data["wait"]):
				var pattern := ["swoop", "icicles", "shards", "swoop"] if angry else ["icicles", "swoop", "shards"]
				var attack: String = pattern[int(boss.data["attack"]) % pattern.size()]
				boss.data["attack"] = int(boss.data["attack"]) + 1
				boss.data["shots"] = 0
				_enter(boss, attack)
				if attack == "swoop":
					# It dives from the side the hero is not on, across the whole room and out past the far wall.
					var from_right: bool = hero.pos.x < centre
					boss.data["from"] = Vector2(ARENA_RIGHT - 30.0 if from_right else ARENA_LEFT + 30.0, 128.0)
					boss.data["to"] = Vector2(ARENA_LEFT - SWOOP_OVERSHOOT if from_right else ARENA_RIGHT + SWOOP_OVERSHOOT, 128.0)
		"icicles":
			_fly_to(boss, Vector2(centre, 104.0), 140.0, delta)
			if int(boss.data["shots"]) == 0 and boss.t >= 0.5:
				boss.data["shots"] = 1
				game.audio.play("boss_screech")
				game.shake(2.0)
				var count := 7 if angry else 5
				var spacing := (ARENA_RIGHT - ARENA_LEFT - 60.0) / float(count)
				var skip: int = game.rng.int_range(0, count - 1)
				# One is always for the hero, whatever the gaps in the row: standing still under the owl is never safe.
				game.spawn_icicle(clampf(hero.pos.x, ARENA_LEFT + 4.0, ARENA_RIGHT - 4.0), 62.0, 0.75)
				for index in count:
					if index == skip:
						continue
					var x: float = ARENA_LEFT + 30.0 + spacing * (float(index) + game.rng.float_range(0.2, 0.8))
					game.spawn_icicle(x, 62.0, 0.5 + 0.12 * float(index))
			if boss.t >= 2.0:
				_enter(boss, "hover")
				boss.data["wait"] = 1.4 if angry else 2.2
		"swoop":
			var dive := 1.5 if angry else 1.9
			var from: Vector2 = boss.data["from"]
			var to: Vector2 = boss.data["to"]
			boss.frame = 0
			if int(boss.data["shots"]) < 2:
				# It flies to where the dive starts, however far that is, and hangs there for a moment: that is the warning.
				_fly_to(boss, from, 300.0, delta)
				if int(boss.data["shots"]) == 0 and boss.t >= 0.2:
					boss.data["shots"] = 1
					game.audio.play("boss_screech", 1.2)
				if int(boss.data["shots"]) == 1 and boss.pos.distance_to(from) < 0.5:
					boss.data["shots"] = 2
					boss.t = 0.0
					# The dive is lowest where the hero stands as it begins.
					boss.data["low"] = clampf(hero.pos.x, minf(from.x, to.x) + 50.0, maxf(from.x, to.x) - 50.0)
			elif boss.t >= SWOOP_HANG:
				var along := clampf((boss.t - SWOOP_HANG) / dive, 0.0, 1.0)
				boss.pos = swoop_point(from, to, float(boss.data["low"]), along)
				if int(boss.t * 30.0) % 2 == 0:
					game.fx.puff(boss.pos + Vector2(0.0, -14.0), Vector2(0.0, 12.0), "g", 0.35)
				if along >= 1.0:
					_enter(boss, "hover")
					boss.data["wait"] = 1.2 if angry else 2.0
		"shards":
			_fly_to(boss, Vector2(clampf(boss.pos.x, ARENA_LEFT + 60.0, ARENA_RIGHT - 60.0), 166.0), 110.0, delta)
			var volleys := 3 if angry else 2
			var fired := int(boss.data["shots"])
			if fired < volleys and boss.t >= 0.6 + 0.6 * float(fired):
				boss.data["shots"] = fired + 1
				var aim: Vector2 = (hero.centre() - (boss.pos + Vector2(0.0, -14.0))).normalized()
				# Calm, it throws one shard at a time, straight at him. Enraged, a fan of three: wide enough apart that a short hop passes between the middle one and the one above it.
				var spread := 1 if angry else 0
				for index in range(-spread, spread + 1):
					game.spawn_hazard("shard", boss.pos + Vector2(0.0, -14.0), aim.rotated(0.4 * float(index)) * 135.0, 0.0, 3.0)
				game.audio.play("icicle", 0.8)
			if boss.t >= 0.6 + 0.6 * float(volleys) + 0.5:
				_enter(boss, "hover")
				boss.data["wait"] = 1.3 if angry else 2.0

## Where the owl is `along` (0 to 1) of the way through a dive from `from` to `to` that is lowest over `low_x`: it travels evenly sideways and sinks to head height over that spot.
static func swoop_point(from: Vector2, to: Vector2, low_x: float, along: float) -> Vector2:
	var turn := clampf((low_x - from.x) / (to.x - from.x), 0.05, 0.95)
	var arc := 0.5 * along / turn if along < turn else 0.5 + 0.5 * (along - turn) / (1.0 - turn)
	return Vector2(lerpf(from.x, to.x, along), from.y + SWOOP_DEPTH * sin(PI * arc))

static func _fly_to(boss: RefCounted, target: Vector2, speed: float, delta: float) -> void:
	boss.pos = boss.pos.move_toward(target, speed * delta)

static func _enter(boss: RefCounted, state: String) -> void:
	boss.state = state
	boss.t = 0.0
