extends GameModule

## Ember Trail: a lamplighter crosses the cinder highlands and the rime hollow, lighting the lamp posts on the way and the beacon at the end of each stage. His lantern burns down all the time; oil keeps it alight. This script is the run itself: stages, lives, the flame, and everything that happens when two things touch. The pieces are in the scripts it preloads.

const Levels := preload("res://games/ember_trail/levels.gd")
const World := preload("res://games/ember_trail/world.gd")
const Hero := preload("res://games/ember_trail/hero.gd")
const Creatures := preload("res://games/ember_trail/creatures.gd")
const Bosses := preload("res://games/ember_trail/bosses.gd")
const Fx := preload("res://games/ember_trail/fx.gd")
const Sounds := preload("res://games/ember_trail/sounds.gd")
const Texts := preload("res://games/ember_trail/texts.gd")
const Render := preload("res://games/ember_trail/render.gd")
const Art := preload("res://games/ember_trail/art.gd")

const FLAME_MAX := 100.0
const MAX_LIVES := 9
const MOTHS_PER_LIFE := 40
const GEYSER_PERIOD := 3.2
const GEYSER_WARN := 1.7
const GEYSER_ERUPT := 2.3
const GEYSER_HEIGHT := 54.0
## Per difficulty: lives, continues, flame lost per second, flame lost per hit, boss health factor.
const DIFFICULTY := {
	1: {"lives": 5, "continues": 3, "drain": 1.3, "hurt": 15.0, "boss": 0.75},
	2: {"lives": 3, "continues": 2, "drain": 1.8, "hurt": 22.0, "boss": 1.0},
	3: {"lives": 2, "continues": 1, "drain": 2.3, "hurt": 30.0, "boss": 1.3},
}

var difficulty := 2
var tuning: Dictionary = DIFFICULTY[2]
var stage_i := 0
var stage: Dictionary = Levels.STAGES[0]
var world: RefCounted
var hero: RefCounted
var creatures: Array = []
var boss: RefCounted
var shots: Array = []
var hazards: Array = []
var pickups: Array = []
var lamps: Array = []
var geysers: Array = []
var icicles: Array = []
var cinder_zones: Array = []
var goal := Vector2.ZERO
var has_goal := false
var fx: RefCounted
## The ashhorn running off after it took a hit: { pos, dir, t }, or empty.
var runaway: Dictionary = {}

var flame := FLAME_MAX
var lives := 3
var continues := 2
var continues_used := 0
var deaths := 0
var moths := 0
var kills := 0
var mount_stomps := 0
var hits_taken := 0
var areas_cleared := 0
var stages_cleared := 0
var full_run := 1

## "intro", "play", "dying", "clear", "boss_down", "area_clear", "victory" or "game_over".
var phase := "intro"
var phase_t := 0.0
var stage_time := 0.0
var cam_x := 0.0
## Index of the last lamp post lit in this stage, or -1.
var checkpoint := -1
## Spawn indices of the pick-ups already taken in this stage; they stay taken after a death.
var taken: Dictionary = {}
var banner: Dictionary = {}
var shake_amount := 0.0
var flash_time := 0.0
var cinder_wait := 1.0
var flask_wait := 8.0
var track := ""
var bonus_paid := false

var _camera: Camera2D
var _art: Dictionary = {}
var _font: SystemFont

func _game_start(config: Dictionary) -> void:
	var chosen: Dictionary = config["options"]
	difficulty = clampi(int(chosen.get("difficulty", 2)), 1, 3)
	tuning = DIFFICULTY[difficulty]
	var first := clampi(int(chosen.get("start", 1)), 1, Levels.STAGES.size()) - 1
	full_run = 1 if first == 0 else 0
	lives = int(tuning["lives"])
	continues = int(tuning["continues"])
	continues_used = 0
	deaths = 0
	moths = 0
	kills = 0
	mount_stomps = 0
	hits_taken = 0
	areas_cleared = 0
	stages_cleared = 0
	fx = Fx.new()
	hero = Hero.new()
	if _camera == null:
		_camera = Camera2D.new()
		_camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		add_child(_camera)
	Sounds.define_all(audio)
	track = ""
	_load_stage(first, true)

# ---- stages ----

## Build a stage and put the hero in it. `fresh` forgets the checkpoint and the taken pick-ups (a new stage or a continue); otherwise he comes back at the last lamp he lit.
func _load_stage(index: int, fresh: bool) -> void:
	stage_i = index
	stage = Levels.STAGES[index]
	var built: Dictionary = Levels.build(index)
	world = built["world"]
	if fresh:
		checkpoint = -1
		taken.clear()
	creatures.clear()
	shots.clear()
	hazards.clear()
	pickups.clear()
	lamps.clear()
	geysers.clear()
	icicles.clear()
	cinder_zones.clear()
	runaway = {}
	has_goal = false
	var spawns: Array = built["spawns"]
	for index_in in spawns.size():
		var spawn: Dictionary = spawns[index_in]
		var kind: String = spawn["kind"]
		var at := Vector2(float(spawn["x"]), float(spawn["y"]))
		if kind in Levels.CREATURES:
			creatures.append(Creatures.make(kind, at.x, at.y))
		elif kind in Levels.PICKUPS:
			if not taken.has(index_in):
				pickups.append({"kind": kind, "pos": at + Vector2(0.0, -8.0), "index": index_in, "fall": false})
		elif kind == "L":
			lamps.append({"pos": at, "lit": lamps.size() <= checkpoint})
		elif kind == "G":
			goal = at
			has_goal = true
		elif kind == "g":
			geysers.append({"pos": at, "offset": float(int(spawn["tx"]) % 5) * 0.55, "erupting": false})
		elif kind == "i":
			icicles.append({"pos": at + Vector2(0.0, -16.0), "state": 0, "t": 0.0, "vy": 0.0, "delay": 0.4})
		elif kind == "m":
			cinder_zones.append(at.x)
	var at_start: Vector2 = built["start"]
	if checkpoint >= 0 and checkpoint < lamps.size():
		at_start = lamps[checkpoint]["pos"]
	hero.place(at_start)
	flame = FLAME_MAX
	boss = Bosses.make(str(stage["boss"]), float(tuning["boss"])) if stage["boss"] != "" else null
	fx.reset()
	stage_time = 0.0
	shake_amount = 0.0
	flash_time = 0.0
	cinder_wait = 1.5
	flask_wait = 8.0
	bonus_paid = false
	cam_x = clampf(hero.pos.x - 200.0, 0.0, _cam_limit())
	_place_camera()
	var wanted := "boss" if boss != null else ("highland" if int(stage["area"]) == 1 else "hollow")
	if wanted != track:
		track = wanted
		audio.play_music(Sounds.tune(track))
	_set_phase("intro")
	var title := Texts.of("stage", locale) % str(stage["key"])
	banner = {"title": title, "sub": str(stage[locale] if stage.has(locale) else stage["en"]), "t": 0.0, "life": 2.4}
	if boss != null:
		banner["sub"] = Texts.of("boss_" + str(stage["boss"]), locale)

func _cam_limit() -> float:
	return maxf(0.0, float(world.width * World.TILE - stage_size.x))

func _set_phase(next: String) -> void:
	phase = next
	phase_t = 0.0

# ---- the step ----

func _game_step(delta: float) -> void:
	phase_t += delta
	if not banner.is_empty():
		banner["t"] = float(banner["t"]) + delta
	match phase:
		"intro":
			_simulate(delta, true, false)
			if phase == "intro" and phase_t >= 1.4:
				_set_phase("play")
		"play":
			_simulate(delta, true, true)
		"dying":
			_simulate(delta, false, false)
			if phase_t >= 1.5:
				_after_death()
		"clear":
			_simulate(delta, false, false)
			if not bonus_paid and phase_t >= 1.0:
				bonus_paid = true
				var bonus := 500 + int(flame) * 5
				score += bonus
				banner["sub"] = Texts.of("flame_bonus", locale) % bonus
				audio.play("bonus")
			if phase_t >= 3.0:
				_load_stage(stage_i + 1, true)
		"boss_down":
			_simulate(delta, true, false)
			if boss != null and boss.gone:
				boss = null
				areas_cleared += 1
				stages_cleared += 1
				audio.play("relight")
				_set_phase("area_clear")
				banner = {"title": Texts.of("boss_down", locale), "sub": Texts.of("flame_bonus", locale) % (int(flame) * 5), "t": 0.0, "life": 3.0}
				score += int(flame) * 5
		"area_clear":
			_simulate(delta, true, false)
			if phase_t >= 3.2:
				if stage_i + 1 >= Levels.STAGES.size():
					score += lives * 500
					track = "victory"
					audio.play_music(Sounds.tune(track))
					_set_phase("victory")
					banner = {"title": Texts.of("victory", locale), "sub": Texts.of("victory_sub", locale), "t": 0.0, "life": 9.0}
				else:
					_load_stage(stage_i + 1, true)
		"victory":
			_simulate(delta, false, false)
			if int(phase_t * 60.0) % 14 == 0:
				fx.burst(Vector2(cam_x + fx.rng.float_range(40.0, 440.0), fx.rng.float_range(70.0, 170.0)), 14, "5678r", 80.0, 60.0, 0.9)
			if phase_t >= 4.5:
				finish(OUTCOME_CLEARED)
		"game_over":
			fx.step(delta)
			if phase_t >= 2.4:
				finish(OUTCOME_DEFEATED)

## One step of the world. `control` lets the player steer; `burning` lets the lantern run down.
func _simulate(delta: float, control: bool, burning: bool) -> void:
	stage_time += delta
	flash_time = maxf(0.0, flash_time - delta)
	world.step_plats(stage_time)
	for index: int in world.step_crumbles(delta, hero.rect()):
		var cell := Vector2(float((index % world.width) * World.TILE + 8), float((index / world.width) * World.TILE + 4))
		fx.burst(cell, 8, "abc" if int(stage["area"]) == 1 else "fgh", 40.0, 300.0, 0.6)
	hero.step(self, input(0), delta, control)
	if not hero.dead:
		_hero_against_stage()
	_step_shots(delta)
	_step_creatures(delta)
	if boss != null:
		_step_boss(delta)
	_step_hazards(delta)
	_step_fixtures(delta)
	_step_pickups(delta)
	if not runaway.is_empty():
		runaway["t"] = float(runaway["t"]) + delta
		runaway["pos"] = (runaway["pos"] as Vector2) + Vector2(float(runaway["dir"]) * 170.0 * delta, 0.0)
		if float(runaway["t"]) > 1.6:
			runaway = {}
	if burning and not hero.dead and phase == "play":
		flame -= float(tuning["drain"]) * (0.6 if boss != null else 1.0) * delta
		if flame <= 0.0:
			flame = 0.0
			_kill_hero()
	fx.step(delta)
	_step_camera(delta)

func _step_camera(delta: float) -> void:
	if not hero.dead:
		var target := clampf(hero.pos.x - 200.0 + float(hero.facing) * 16.0, 0.0, _cam_limit())
		cam_x = lerpf(cam_x, target, minf(1.0, 7.0 * delta))
	shake_amount = maxf(0.0, shake_amount - 16.0 * delta)
	_place_camera()

func _place_camera() -> void:
	var jitter := Vector2.ZERO
	if shake_amount > 0.2:
		jitter = Vector2(roundf(fx.rng.float_range(-1.0, 1.0) * shake_amount), roundf(fx.rng.float_range(-1.0, 1.0) * shake_amount))
	# The stage is two pixels shorter than the seventeen rows of tiles; the top two are never seen.
	_camera.position = Vector2(roundf(cam_x), 2.0) + jitter

# ---- the hero against the world ----

func _hero_against_stage() -> void:
	if hero.pos.y > float(World.ROWS * World.TILE) - 8.0:
		fx.burst(Vector2(hero.pos.x, float(World.ROWS * World.TILE) - 22.0), 22, "567" if int(stage["area"]) == 1 else "fgh", 110.0, 320.0, 0.8, 90.0)
		audio.play("splash")
		_kill_hero()
		return
	var box: Rect2 = hero.rect()
	var row := int(floor((hero.pos.y - 1.0) / World.TILE))
	for tx in range(int(floor(box.position.x / World.TILE)), int(floor(box.end.x / World.TILE)) + 1):
		if world.tile(tx, row) == World.SPIKE and box.intersects(Rect2(float(tx * World.TILE + 2), float(row * World.TILE + 6), 12.0, 10.0)):
			_hurt_hero(float(tx * World.TILE + 8))
			return

## Something at `from_x` hit the hero.
func _hurt_hero(from_x: float) -> void:
	if phase != "play" and phase != "intro":
		return
	var took: String = hero.take_hit(from_x)
	if took == "":
		return
	shake(3.0)
	if took == "ram":
		runaway = {"pos": hero.pos, "dir": -hero.facing, "t": 0.0}
		audio.play("ram_lost")
		fx.burst(hero.pos + Vector2(0.0, -10.0), 12, "abc", 70.0, 200.0, 0.5)
		return
	hits_taken += 1
	flame -= float(tuning["hurt"])
	flash_time = 0.12
	audio.play("hurt")
	fx.burst(hero.centre(), 12, "678", 80.0, 200.0, 0.5)
	if flame <= 0.0:
		flame = 0.0
		_kill_hero()

func _kill_hero() -> void:
	if hero.dead:
		return
	hero.die()
	lives -= 1
	deaths += 1
	shake(4.0)
	audio.play("die")
	_set_phase("dying")

func _after_death() -> void:
	if lives > 0:
		_load_stage(stage_i, false)
	elif continues > 0:
		continues -= 1
		continues_used += 1
		lives = int(tuning["lives"])
		_load_stage(stage_i, true)
		banner = {"title": Texts.of("continue", locale) % continues, "sub": str(stage[locale] if stage.has(locale) else stage["en"]), "t": 0.0, "life": 2.4}
		audio.play("relight")
	else:
		lives = 0
		banner = {"title": Texts.of("game_over", locale), "sub": "", "t": 0.0, "life": 9.0}
		audio.play("game_over")
		audio.stop_music()
		_set_phase("game_over")

func shake(amount: float) -> void:
	shake_amount = maxf(shake_amount, amount)

func add_score(points: int, at: Vector2) -> void:
	score += points
	fx.popup(at, str(points))

# ---- sparks ----

func spawn_shot(at: Vector2, velocity: Vector2, gravity: float) -> void:
	shots.append({"pos": at, "vel": velocity, "gravity": gravity, "t": 0.0})
	audio.play("throw")

func _step_shots(delta: float) -> void:
	for index in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[index]
		var velocity: Vector2 = shot["vel"]
		velocity.y += float(shot["gravity"]) * delta
		var at: Vector2 = (shot["pos"] as Vector2) + velocity * delta
		shot["vel"] = velocity
		shot["pos"] = at
		shot["t"] = float(shot["t"]) + delta
		if int(float(shot["t"]) * 60.0) % 3 == 0:
			fx.puff(at, Vector2(0.0, 10.0), "6", 0.18)
		var box := Rect2(at - Vector2(3.0, 3.0), Vector2(6.0, 6.0))
		var spent := false
		for creature: RefCounted in creatures:
			if not creature.gone and creature.awake and box.intersects(creature.rect()):
				_hit_creature(creature)
				spent = true
				break
		if not spent and boss != null and boss.state != "dying" and boss.state != "enter" and box.intersects(boss.rect()):
			_hit_boss()
			spent = true
		if spent:
			fx.burst(at, 6, "678", 60.0, 100.0, 0.25)
			shots.remove_at(index)
		elif world.solid_at(at) or float(shot["t"]) > 1.1 or at.y > float(World.ROWS * World.TILE) or at.x < cam_x - 20.0 or at.x > cam_x + float(stage_size.x) + 20.0:
			if world.solid_at(at):
				fx.burst(at, 4, "67", 40.0, 100.0, 0.2)
				audio.play("spark_fizzle")
			shots.remove_at(index)

func _hit_creature(creature: RefCounted) -> void:
	creature.hp -= 1
	creature.flash = 0.14
	audio.play("spark_hit")
	if creature.hp <= 0:
		_creature_down(creature)

func _creature_down(creature: RefCounted) -> void:
	creature.gone = true
	kills += 1
	var middle: Vector2 = creature.pos + Vector2(0.0, -creature.h * 0.5)
	add_score(creature.points, middle)
	audio.play("creature_down")
	fx.burst(middle, 14, "456" if int(stage["area"]) == 1 else "fgh", 90.0, 220.0, 0.55, 30.0)
	# Now and then a creature leaves a flask behind.
	if rng.chance(0.14):
		pickups.append({"kind": "f", "pos": middle, "index": -1, "fall": true})

func _step_creatures(delta: float) -> void:
	for index in range(creatures.size() - 1, -1, -1):
		var creature: RefCounted = creatures[index]
		if creature.gone:
			creatures.remove_at(index)
			continue
		Creatures.step(self, creature, delta)
		if creature.gone or not creature.awake or hero.dead:
			continue
		if hero.rect().grow(-1.0).intersects(creature.rect()):
			# From the ashhorn's back, coming down on a creature flattens it.
			if hero.mounted and hero.vel.y > 30.0 and hero.feet_before <= creature.pos.y - creature.h + 9.0:
				mount_stomps += 1
				hero.vel.y = -250.0
				audio.play("stomp")
				shake(2.0)
				_creature_down(creature)
			else:
				_hurt_hero(creature.pos.x)

# ---- bosses ----

func _step_boss(delta: float) -> void:
	Bosses.step(self, boss, delta)
	if boss.gone or boss.state == "dying":
		return
	if not hero.dead and boss.state != "enter" and hero.rect().grow(-1.0).intersects(boss.rect().grow(-2.0)):
		_hurt_hero(boss.pos.x)
	# The fight is long; a flask drifts down now and then.
	flask_wait -= delta
	if flask_wait <= 0.0:
		flask_wait = 11.0
		pickups.append({"kind": "f", "pos": Vector2(rng.float_range(Bosses.ARENA_LEFT + 30.0, Bosses.ARENA_RIGHT - 30.0), 70.0), "index": -1, "fall": true})

func _hit_boss() -> void:
	boss.hp -= 1
	boss.flash = 0.12
	score += 50
	audio.play("boss_hit")
	if boss.hp > 0:
		return
	boss.state = "dying"
	boss.t = 0.0
	boss.vel = Vector2.ZERO
	hazards.clear()
	icicles.clear()
	add_score(boss.points, boss.pos + Vector2(0.0, -boss.h))
	audio.play("boss_down")
	audio.stop_music()
	track = ""
	_set_phase("boss_down")

# ---- things that hurt ----

func spawn_hazard(kind: String, at: Vector2, velocity: Vector2, gravity: float, life: float) -> void:
	hazards.append({"kind": kind, "pos": at, "vel": velocity, "gravity": gravity, "life": life, "t": 0.0})

func spawn_icicle(x: float, y: float, delay: float) -> void:
	icicles.append({"pos": Vector2(x, y), "state": 1, "t": 0.0, "vy": 0.0, "delay": delay})

func _step_hazards(delta: float) -> void:
	for index in range(hazards.size() - 1, -1, -1):
		var hazard: Dictionary = hazards[index]
		var velocity: Vector2 = hazard["vel"]
		velocity.y += float(hazard["gravity"]) * delta
		var at: Vector2 = (hazard["pos"] as Vector2) + velocity * delta
		hazard["vel"] = velocity
		hazard["pos"] = at
		hazard["t"] = float(hazard["t"]) + delta
		var kind: String = hazard["kind"]
		var box := Rect2(at - Vector2(3.0, 3.0), Vector2(6.0, 6.0))
		var done := float(hazard["t"]) >= float(hazard["life"]) or at.y > float(World.ROWS * World.TILE) + 20.0
		if kind == "wave":
			box = Rect2(at.x - 5.0, at.y - 11.0, 10.0, 11.0)
			done = done or at.x < Bosses.ARENA_LEFT or at.x > Bosses.ARENA_RIGHT
			if int(float(hazard["t"]) * 60.0) % 4 == 0:
				fx.puff(at + Vector2(0.0, -4.0), Vector2(-velocity.x * 0.2, -30.0), "5", 0.3)
		elif kind == "cinder":
			if int(float(hazard["t"]) * 60.0) % 2 == 0:
				fx.puff(at, Vector2(12.0, -20.0), "5" if int(float(hazard["t"]) * 30.0) % 2 == 0 else "3", 0.4)
		if not done and kind != "wave" and kind != "shard" and (world.solid_at(at) or (velocity.y > 0.0 and world.standable(int(floor(at.x / World.TILE)), int(floor(at.y / World.TILE))) and fmod(at.y, float(World.TILE)) < 6.0)):
			done = true
			fx.burst(at, 8, "456", 60.0, 200.0, 0.35, 30.0)
			if kind == "cinder":
				audio.play("cinder")
		if not done and kind == "shard" and world.solid_at(at):
			done = true
			fx.burst(at, 5, "fgh", 50.0, 150.0, 0.3)
		if not done and not hero.dead and box.intersects(hero.rect()):
			_hurt_hero(at.x)
			done = kind != "wave"
		if done:
			hazards.remove_at(index)

func _step_fixtures(delta: float) -> void:
	var view_left := cam_x - 24.0
	var view_right := cam_x + float(stage_size.x) + 24.0
	for index in lamps.size():
		var lamp: Dictionary = lamps[index]
		var at: Vector2 = lamp["pos"]
		if not lamp["lit"] and not hero.dead and hero.pos.x >= at.x - 6.0 and absf(hero.pos.y - at.y) < 70.0:
			lamp["lit"] = true
			checkpoint = maxi(checkpoint, index)
			flame = minf(FLAME_MAX, flame + 30.0)
			audio.play("lamp")
			fx.burst(at + Vector2(0.0, -30.0), 16, "678", 70.0, 60.0, 0.7)
			fx.popup(at + Vector2(0.0, -44.0), Texts.of("checkpoint", locale), "7")
	if has_goal and phase == "play" and not hero.dead and hero.rect().intersects(Rect2(goal.x - 12.0, goal.y - 48.0, 24.0, 48.0)):
		stages_cleared += 1
		audio.play("beacon")
		fx.burst(goal + Vector2(0.0, -44.0), 40, "5678", 130.0, 60.0, 1.0)
		shake(3.0)
		_set_phase("clear")
		banner = {"title": Texts.of("stage_clear", locale), "sub": "", "t": 0.0, "life": 3.2}
	for geyser: Dictionary in geysers:
		var at: Vector2 = geyser["pos"]
		var along := fmod(stage_time + float(geyser["offset"]), GEYSER_PERIOD)
		var erupting := along >= GEYSER_ERUPT
		var seen := at.x > view_left and at.x < view_right
		if erupting and not geyser["erupting"] and seen:
			audio.play("geyser")
		geyser["erupting"] = erupting
		if seen and along >= GEYSER_WARN and int(stage_time * 60.0) % (2 if erupting else 6) == 0:
			fx.puff(at + Vector2(fx.rng.float_range(-4.0, 4.0), -4.0), Vector2(fx.rng.float_range(-14.0, 14.0), -fx.rng.float_range(40.0, 150.0) if erupting else -30.0), "6" if fx.rng.chance(0.5) else "c", 0.5, 220.0 if erupting else 0.0)
		if erupting and not hero.dead and hero.rect().intersects(Rect2(at.x - 6.0, at.y - GEYSER_HEIGHT, 12.0, GEYSER_HEIGHT)):
			_hurt_hero(at.x)
	for index in range(icicles.size() - 1, -1, -1):
		var icicle: Dictionary = icicles[index]
		var at: Vector2 = icicle["pos"]
		match int(icicle["state"]):
			0:
				if not hero.dead and absf(hero.pos.x - at.x) < 30.0 and hero.pos.y > at.y and at.x > view_left and at.x < view_right:
					icicle["state"] = 1
					icicle["t"] = 0.0
					audio.play("icicle")
			1:
				icicle["t"] = float(icicle["t"]) + delta
				if float(icicle["t"]) >= float(icicle["delay"]):
					icicle["state"] = 2
			2:
				icicle["vy"] = minf(float(icicle["vy"]) + 700.0 * delta, 380.0)
				at.y += float(icicle["vy"]) * delta
				icicle["pos"] = at
				var broke: bool = world.standable(int(floor(at.x / World.TILE)), int(floor((at.y + 14.0) / World.TILE))) or at.y > float(World.ROWS * World.TILE)
				if not hero.dead and Rect2(at.x - 3.0, at.y, 6.0, 14.0).intersects(hero.rect()):
					_hurt_hero(at.x)
					broke = true
				if broke:
					fx.burst(at + Vector2(0.0, 12.0), 10, "fgh", 70.0, 260.0, 0.45, 40.0)
					audio.play("shatter")
					icicles.remove_at(index)
	if not cinder_zones.is_empty() and phase == "play":
		var near := false
		for zone: float in cinder_zones:
			near = near or absf(hero.pos.x - zone) < 210.0
		if near:
			cinder_wait -= delta
			if cinder_wait <= 0.0:
				cinder_wait = rng.float_range(1.1, 1.9)
				spawn_hazard("cinder", Vector2(hero.pos.x + rng.float_range(-20.0, 150.0), 40.0), Vector2(-36.0, 150.0), 0.0, 4.0)

# ---- pick-ups ----

func _step_pickups(delta: float) -> void:
	var reach: Rect2 = hero.rect().grow(3.0)
	for index in range(pickups.size() - 1, -1, -1):
		var pickup: Dictionary = pickups[index]
		var at: Vector2 = pickup["pos"]
		if pickup["fall"]:
			at.y = minf(at.y + 70.0 * delta, world.ground_y(at.x, at.y) - 8.0)
			pickup["pos"] = at
			if at.y > float(World.ROWS * World.TILE):
				pickups.remove_at(index)
				continue
		if hero.dead or not reach.intersects(Rect2(at - Vector2(5.0, 5.0), Vector2(10.0, 10.0))):
			continue
		if int(pickup["index"]) >= 0:
			taken[int(pickup["index"])] = true
		pickups.remove_at(index)
		_collect(str(pickup["kind"]), at)

func _collect(kind: String, at: Vector2) -> void:
	match kind:
		"o":
			moths += 1
			add_score(50, at)
			audio.play("moth")
			fx.burst(at, 6, "r8", 40.0, 0.0, 0.4)
			if moths % MOTHS_PER_LIFE == 0:
				_gain_life(at)
		"f":
			flame = minf(FLAME_MAX, flame + 16.0)
			score += 20
			audio.play("flask")
			fx.burst(at, 8, "67", 50.0, 0.0, 0.4)
		"r":
			flame = minf(FLAME_MAX, flame + 45.0)
			add_score(100, at)
			audio.play("resin")
			fx.burst(at, 14, "678", 70.0, 0.0, 0.6)
		"w":
			add_score(200, at)
			_gain_life(at)
		"b":
			hero.set_mounted(true)
			hero.invuln = maxf(hero.invuln, 0.6)
			add_score(100, at)
			audio.play("bell")
			fx.burst(hero.pos + Vector2(0.0, -8.0), 18, "abc", 80.0, 120.0, 0.6)
			fx.popup(hero.pos + Vector2(0.0, -40.0), Texts.of("mount", locale), "7")

func _gain_life(at: Vector2) -> void:
	lives = mini(MAX_LIVES, lives + 1)
	audio.play("one_up")
	fx.popup(at + Vector2(0.0, -12.0), Texts.of("one_up", locale), "k")

# ---- what the host reads ----

func _game_snapshot() -> Dictionary:
	var out := {
		"stage": stage_i + 1,
		"stages_total": Levels.STAGES.size(),
		"flame": int(ceil(flame)),
		"flame_max": int(FLAME_MAX),
		"lives": lives,
		"continues": continues,
		"continues_used": continues_used,
		"deaths": deaths,
		"moths": moths,
		"kills": kills,
		"mount_stomps": mount_stomps,
		"hits_taken": hits_taken,
		"areas_cleared": areas_cleared,
		"stages_cleared": stages_cleared,
		"full_run": full_run,
		"difficulty": difficulty,
		"phase": phase,
		"mounted": 1 if hero != null and hero.mounted else 0,
		"hero_x": hero.pos.x if hero != null else 0.0,
		"hero_y": hero.pos.y if hero != null else 0.0,
		"camera_x": cam_x,
		"players": [{"score": score, "flame": int(ceil(flame)), "flame_max": int(FLAME_MAX), "lives": lives}],
	}
	if boss != null and boss.state != "dying" and boss.hp > 0:
		out["boss_hp"] = boss.hp
		out["boss_max_hp"] = boss.max_hp
	return out

# ---- drawing ----

func _game_frame(_delta: float) -> void:
	queue_redraw()

## The pictures, built the first time something is drawn: a headless test never pays for them.
func art() -> Dictionary:
	if _art.is_empty():
		_art = Art.build()
	return _art

func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Noto Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"])
		_font.allow_system_fallback = true
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font

func _draw() -> void:
	if world != null:
		Render.paint(self)
