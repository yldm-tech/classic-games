extends RefCounted

## The six kinds of creature on the trail and how each behaves. Level text names them by one letter (see levels.gd).

const Creature := preload("res://games/ember_trail/creature.gd")
const World := preload("res://games/ember_trail/world.gd")

const GRAVITY := 880.0
const SPECS := {
	"c": {"sprite": "cinderling", "hw": 6.0, "h": 11.0, "hp": 1, "points": 100, "flying": false},
	"v": {"sprite": "sootwing", "hw": 7.0, "h": 10.0, "hp": 1, "points": 150, "flying": true},
	"s": {"sprite": "ventcrab", "hw": 8.0, "h": 11.0, "hp": 2, "points": 200, "flying": false},
	"k": {"sprite": "rimebeetle", "hw": 7.0, "h": 10.0, "hp": 2, "points": 200, "flying": false},
	"d": {"sprite": "driftwisp", "hw": 5.0, "h": 13.0, "hp": 1, "points": 150, "flying": true},
	"j": {"sprite": "shardling", "hw": 5.0, "h": 11.0, "hp": 1, "points": 150, "flying": false},
}

static func make(kind: String, x: float, y: float) -> RefCounted:
	var spec: Dictionary = SPECS[kind]
	var creature := Creature.new()
	creature.kind = kind
	creature.sprite = spec["sprite"]
	creature.hw = spec["hw"]
	creature.h = spec["h"]
	creature.hp = spec["hp"]
	creature.max_hp = spec["hp"]
	creature.points = spec["points"]
	creature.flying = spec["flying"]
	creature.pos = Vector2(x, y - 4.0) if creature.flying else Vector2(x, y)
	creature.home = creature.pos
	# The vent crabs do not all spit at the same moment.
	creature.t = fmod(x * 0.013, 1.5)
	return creature

static func step(game: Node2D, creature: RefCounted, delta: float) -> void:
	creature.flash = maxf(0.0, creature.flash - delta)
	if not creature.awake:
		if creature.pos.x > game.cam_x - 40.0 and creature.pos.x < game.cam_x + float(game.stage_size.x) + 40.0:
			creature.awake = true
		else:
			return
	creature.t += delta
	var hero: RefCounted = game.hero
	var world: RefCounted = game.world
	match creature.kind:
		"c", "k":
			creature.vel.x = float(creature.dir) * (28.0 if creature.kind == "c" else 44.0)
			creature.vel.y = minf(creature.vel.y + GRAVITY * delta, 420.0)
			world.move_body(creature, delta)
			if creature.hit_wall:
				creature.dir = -creature.dir
			elif creature.on_ground and not world.standable(int(floor((creature.pos.x + float(creature.dir) * (creature.hw + 1.0)) / World.TILE)), int(floor((creature.pos.y + 1.0) / World.TILE))):
				creature.dir = -creature.dir
			creature.frame = int(creature.t * 6.0) % 2
		"v":
			creature.pos.x += float(creature.dir) * 46.0 * delta
			creature.pos.y = creature.home.y + sin(creature.t * 3.2) * 18.0
			creature.frame = int(creature.t * 8.0) % 2
			if creature.pos.x < game.cam_x - 80.0:
				creature.gone = true
		"s":
			creature.frame = 1 if creature.t >= 2.1 else 0
			if creature.t >= 2.6:
				creature.t = 0.0
				if absf(hero.pos.x - creature.pos.x) < 230.0:
					var reach := clampf(hero.pos.x - creature.pos.x, -130.0, 130.0)
					game.spawn_hazard("glob", creature.pos + Vector2(0.0, -12.0), Vector2(reach, -260.0), 520.0, 3.0)
					game.audio.play("spit")
					game.fx.burst(creature.pos + Vector2(0.0, -12.0), 5, "567", 40.0, 120.0, 0.3, 30.0)
		"d":
			var offset: Vector2 = hero.centre() - (creature.pos + Vector2(0.0, -6.0))
			var wanted := Vector2.ZERO
			if offset.length() < 160.0 and not hero.dead:
				wanted = offset.normalized() * 40.0
			creature.vel = creature.vel.move_toward(wanted, 90.0 * delta)
			creature.pos += creature.vel * delta
			creature.dir = 1 if offset.x > 0.0 else -1
			creature.frame = int(creature.t * 4.0) % 2
		"j":
			creature.vel.y = minf(creature.vel.y + GRAVITY * delta, 420.0)
			if creature.on_ground:
				creature.vel.x = 0.0
				creature.frame = 0
				if creature.t >= 1.2 and absf(hero.pos.x - creature.pos.x) < 200.0:
					creature.dir = 1 if hero.pos.x > creature.pos.x else -1
					creature.vel = Vector2(float(creature.dir) * 75.0, -240.0)
					creature.t = 0.0
			else:
				creature.frame = 1
			world.move_body(creature, delta)
	if creature.pos.y > float(World.ROWS * World.TILE) + 40.0:
		creature.gone = true
