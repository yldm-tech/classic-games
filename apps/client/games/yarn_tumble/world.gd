extends RefCounted

## The whole simulation of one run of Yarn Tumble, with no drawing and no sound in it: main.gd steps it with the players' inputs, and reads `events` (what just happened, for sound and effects) and the public state (for the view, the HUD and the tests). Everything random comes from the run's seeded generator.

const Levels := preload("res://games/yarn_tumble/levels.gd")
const Hero := preload("res://games/yarn_tumble/hero.gd")
const Foe := preload("res://games/yarn_tumble/foe.gd")
const Boss := preload("res://games/yarn_tumble/boss.gd")
const Item := preload("res://games/yarn_tumble/item.gd")
const FoeLogic := preload("res://games/yarn_tumble/foe_logic.gd")
const BossLogic := preload("res://games/yarn_tumble/boss_logic.gd")

const TILE := 16.0
const COLS := 30
const ROWS := 17
## The grid is 272 pixels tall on a 270 pixel stage: it starts two pixels above the top edge.
const OFFSET_Y := -2.0
const GRAVITY := 640.0
const MAX_FALL := 250.0
const JUMP := 272.0
const RUN := 84.0
const RUN_SWIFT := 106.0
const SHOT_SPEED := 200.0
const SHOT_LIFE := 0.27
const SHOT_LIFE_LONG := 0.44
const SHOT_COOLDOWN := 0.26
const SHOT_COOLDOWN_RAPID := 0.15
const UNWRAP_HOLD := 2.0
const UNWRAP_STEP := 1.0
const ROLL_SPEED := 215.0
const BALL_DAMAGE := 10
const BASE_POINTS := 500
const CHAIN_POINTS := [1000, 2000, 4000, 8000, 16000]

const PLAY := 0
const CLEAR := 1
const OVER := 2

## Per difficulty (0 easy, 1 normal, 2 hard).
const START_LIVES := [5, 4, 3]
const CONTINUES := [3, 2, 1]
const FOE_SPEED := [0.85, 1.0, 1.15]
const BALL_TIME := [8.0, 6.5, 5.5]
const HURRY_AT := [65.0, 50.0, 42.0]
const BOSS_HP := [[48, 60, 72], [64, 80, 96]]

var rng: GameRng
var difficulty := 1
var stage := 1
var theme := 0
var grid := PackedByteArray()
var phase := PLAY
var phase_timer := 0.0
var banner := 0.0
var stage_time := 0.0
var stage_deaths := 0
var hurry := false
var outcome := ""
var heroes: Array[Hero] = []
var foes: Array[Foe] = []
var boss: Boss
var shots: Array[Dictionary] = []
var pickups: Array[Item] = []
var hazards: Array[Item] = []
var husks: Array[Item] = []
## The static spark that hunts dawdlers once a floor has gone on too long; null until then.
var spark: Item
var spark_stun := 0.0
var events: Array = []
var spawn_points: Array = []
## The floor's second batch of creatures, not yet on the floor.
var pending: Array = []

var max_lives := 4
var continues := 2
var continues_used := 0
var deaths := 0
var kos := 0
var best_roll := 0
var bosses_defeated := 0
var gems := 0
var last_bonus := 0

func setup(run_rng: GameRng, level: int, players: int, first_stage: int) -> void:
	rng = run_rng
	difficulty = clampi(level, 0, 2)
	max_lives = int(START_LIVES[difficulty])
	continues = int(CONTINUES[difficulty])
	heroes = [Hero.new(0), Hero.new(1)]
	for hero in heroes:
		if hero.slot < players:
			hero.state = Hero.ALIVE
			hero.lives = max_lives
	load_stage(clampi(first_stage, 1, Levels.count()))

# ---- floors ----

func load_stage(number: int) -> void:
	stage = number
	var def: Dictionary = Levels.STAGES[number - 1]
	theme = int(def["theme"])
	grid = Levels.build(def)
	spawn_points = def["spawn"]
	foes.clear()
	shots.clear()
	pickups.clear()
	hazards.clear()
	husks.clear()
	boss = null
	spark = null
	spark_stun = 0.0
	hurry = false
	stage_time = 0.0
	stage_deaths = 0
	phase = PLAY
	banner = 2.2
	_drop_in(def["foes"])
	pending = (def.get("more", []) as Array).duplicate()
	if def.has("boss"):
		boss = Boss.new(int(def["boss"]))
		boss.max_hp = int(BOSS_HP[boss.kind][difficulty])
		boss.hp = boss.max_hp
		boss.x = 240.0
		boss.y = -20.0
		boss.to_x = 240.0
	for hero in heroes:
		if hero.state == Hero.OUT:
			hero.state = Hero.ALIVE
			hero.lives = 1
		if hero.state == Hero.ALIVE or hero.state == Hero.DYING:
			hero.state = Hero.ALIVE
			_place(hero, 1.5)
	emit("stage", 240.0, 135.0, stage)

## Bring a batch of creatures onto the floor; each takes a moment to appear and is harmless until it has.
func _drop_in(entries: Array) -> void:
	var order := 0
	for entry: Array in entries:
		var foe := Foe.new(str(entry[0]))
		foe.x = (float(entry[1]) + 0.5) * TILE
		foe.y = float(entry[2]) * TILE + OFFSET_Y
		foe.facing = -1 if foe.x > 240.0 else 1
		foe.timer = 1.1 + 0.12 * order
		foe.ai_timer = rng.float_range(0.4, 1.6)
		foe.phase = rng.float_range(0.0, TAU)
		if difficulty == 2:
			foe.need += 1
		foes.append(foe)
		order += 1

func _place(hero: Hero, invuln: float) -> void:
	var point: Array = spawn_points[hero.slot]
	hero.x = (float(point[0]) + 0.5) * TILE
	hero.y = float(point[1]) * TILE + OFFSET_Y
	hero.vx = 0.0
	hero.vy = 0.0
	hero.on_ground = true
	hero.facing = 1 if hero.x < 240.0 else -1
	hero.invuln = invuln
	hero.cooldown = 0.0
	hero.shoot_anim = 0.0

func join(slot: int) -> void:
	var hero := heroes[slot]
	hero.state = Hero.ALIVE
	hero.lives = max_lives
	hero.clear_powers()
	_place(hero, 2.5)
	emit("join", hero.x, hero.y, slot)

func leave(slot: int) -> void:
	heroes[slot].state = Hero.ABSENT

func is_boss_stage() -> bool:
	return (Levels.STAGES[stage - 1] as Dictionary).has("boss")

func total_score() -> int:
	return heroes[0].score + heroes[1].score

func emit(what: String, x: float, y: float, value: int = 0, extra: int = 0) -> void:
	events.append([what, x, y, value, extra])

# ---- tiles and bodies ----

func tile(col: int, row: int) -> int:
	if col < 0 or col >= COLS:
		return Levels.SOLID
	if row < 0 or row >= ROWS:
		return Levels.EMPTY
	return grid[row * COLS + col]

func tile_at(px: float, py: float) -> int:
	return tile(int(floor(px / TILE)), int(floor((py - OFFSET_Y) / TILE)))

func solid_at(px: float, py: float) -> bool:
	return tile_at(px, py) == Levels.SOLID

## Move a body by its velocity for one step with gravity, stopping at walls, crates and (when falling) ledges. Returns -1 or 1 when it ran into a wall on that side, else 0. What falls out of the bottom comes back in at the top.
func move_body(body: Variant, dt: float, through_ledges: bool = false) -> int:
	var wall := 0
	var next_x: float = body.x + body.vx * dt
	if body.vx != 0.0:
		var ahead := 1 if body.vx > 0.0 else -1
		var col := int(floor((next_x + ahead * body.hw) / TILE))
		var top_row := int(floor((body.y - body.h - OFFSET_Y) / TILE))
		var bottom_row := int(floor((body.y - 1.0 - OFFSET_Y) / TILE))
		for row in range(top_row, bottom_row + 1):
			if tile(col, row) == Levels.SOLID:
				wall = ahead
				next_x = (col * TILE - body.hw - 0.01) if ahead > 0 else ((col + 1) * TILE + body.hw + 0.01)
				break
	body.x = next_x
	body.vy = minf(body.vy + GRAVITY * dt, MAX_FALL)
	var next_y: float = body.y + body.vy * dt
	body.on_ground = false
	var first_col := int(floor((body.x - body.hw + 1.0) / TILE))
	var last_col := int(floor((body.x + body.hw - 1.0) / TILE))
	if body.vy >= 0.0:
		var from_row := int(floor((body.y - OFFSET_Y - 0.01) / TILE))
		var to_row := int(floor((next_y - OFFSET_Y) / TILE))
		for row in range(from_row + 1, to_row + 1):
			var top := row * TILE + OFFSET_Y
			if body.y > top + 0.01 or next_y < top:
				continue
			var lands := false
			for col in range(first_col, last_col + 1):
				var kind := tile(col, row)
				if kind == Levels.SOLID or (kind == Levels.LEDGE and not through_ledges):
					lands = true
					break
			if lands:
				next_y = top
				body.vy = 0.0
				body.on_ground = true
				break
	else:
		var head_row := int(floor((next_y - body.h - OFFSET_Y) / TILE))
		for col in range(first_col, last_col + 1):
			if tile(col, head_row) == Levels.SOLID:
				next_y = (head_row + 1) * TILE + OFFSET_Y + body.h
				body.vy = 0.0
				break
	body.y = next_y
	if body.y - body.h > 276.0:
		body.y = -4.0
	return wall

func overlap(a: Variant, b: Variant) -> bool:
	return absf(a.x - b.x) < a.hw + b.hw and a.y > b.y - b.h and b.y > a.y - a.h

## The row of the tile right under a body's feet.
func feet_row(body: Variant) -> int:
	return int(floor((body.y + 1.0 - OFFSET_Y) / TILE))

func ground_ahead(body: Variant, facing: int) -> bool:
	return tile_at(body.x + facing * (body.hw + 3.0), body.y + 2.0) != Levels.EMPTY

func ledge_above(body: Variant) -> bool:
	var col := int(floor(body.x / TILE))
	var under := feet_row(body)
	for row in range(under - 3, under):
		if tile(col, row) == Levels.LEDGE:
			return true
	return false

func nearest_hero(x: float, y: float) -> Hero:
	var best: Hero = null
	var best_distance := 1.0e9
	for hero in heroes:
		if hero.state != Hero.ALIVE:
			continue
		var distance := absf(hero.x - x) + absf(hero.y - y)
		if distance < best_distance:
			best_distance = distance
			best = hero
	return best

func foe_speed() -> float:
	return float(FOE_SPEED[difficulty]) * (1.0 + 0.015 * stage)

func minions() -> int:
	var total := foes.size()
	for hazard in hazards:
		if hazard.kind == Item.EGG:
			total += 1
	return total

# ---- one step ----

func step(dt: float, pads: Array, active: Array) -> void:
	if outcome != "":
		return
	banner = maxf(0.0, banner - dt)
	for hero in heroes:
		if active.has(hero.slot):
			_step_hero(hero, pads[hero.slot], dt)
	_step_shots(dt)
	for foe: Foe in foes.duplicate():
		if foe.is_live():
			FoeLogic.step(self, foe, dt)
	foes = foes.filter(func(foe: Foe) -> bool: return foe.is_live())
	if boss != null:
		BossLogic.step(self, boss, dt)
	_step_hazards(dt)
	_step_pickups(dt)
	_step_husks(dt)
	_step_spark(dt)
	_touch(active)
	_flow(dt, active)

func _flow(dt: float, active: Array) -> void:
	match phase:
		PLAY:
			stage_time += dt
			var playing := false
			for hero in heroes:
				if active.has(hero.slot) and (hero.state == Hero.ALIVE or hero.state == Hero.DYING):
					playing = true
			if not playing:
				phase = OVER
				phase_timer = 2.4
				emit("gameover", 240.0, 135.0)
			elif foes.is_empty() and boss == null and minions() == 0:
				if pending.is_empty():
					_clear_floor()
				else:
					_drop_in(pending)
					pending = []
					emit("wave", 240.0, 135.0)
			elif not is_boss_stage():
				var limit := float(HURRY_AT[difficulty])
				if not hurry and stage_time >= limit:
					hurry = true
					emit("hurry", 240.0, 135.0)
				if spark == null and stage_time >= limit + 14.0:
					spark = Item.new("spark", 240.0, 30.0)
					spark.hw = 5.0
					spark.h = 10.0
					emit("spark", spark.x, spark.y)
		CLEAR:
			phase_timer -= dt
			if phase_timer <= 0.0:
				if stage >= Levels.count():
					outcome = "cleared"
				else:
					load_stage(stage + 1)
		OVER:
			phase_timer -= dt
			if phase_timer <= 0.0:
				outcome = "defeated"

func _clear_floor() -> void:
	phase = CLEAR
	phase_timer = 4.0 if is_boss_stage() else 2.8
	hazards.clear()
	spark = null
	last_bonus = maxi(0, 3000 - int(stage_time) * 50) + (1000 if stage_deaths == 0 else 0)
	for hero in heroes:
		if hero.state == Hero.ALIVE or hero.state == Hero.DYING:
			hero.score += last_bonus
	emit("clear", 240.0, 135.0, last_bonus, stage)

# ---- knitters ----

func _step_hero(hero: Hero, pad: GameInput, dt: float) -> void:
	if hero.state == Hero.DYING:
		hero.timer -= dt
		hero.vy = minf(hero.vy + GRAVITY * dt, MAX_FALL)
		hero.y += hero.vy * dt
		if hero.timer <= 0.0:
			_after_death(hero)
		return
	if hero.state != Hero.ALIVE:
		return
	hero.invuln = maxf(0.0, hero.invuln - dt)
	hero.cooldown = maxf(0.0, hero.cooldown - dt)
	hero.shoot_anim = maxf(0.0, hero.shoot_anim - dt)
	var want := 0
	if absf(pad.move.x) >= 0.3:
		want = 1 if pad.move.x > 0.0 else -1
	hero.vx = want * (RUN_SWIFT if hero.swift else RUN)
	if want != 0:
		hero.facing = want
		hero.anim += dt
	else:
		hero.anim = 0.0
	hero.coyote = 0.09 if hero.on_ground else maxf(0.0, hero.coyote - dt)
	hero.buffer = 0.1 if pad.just_pressed(GameInput.A) else maxf(0.0, hero.buffer - dt)
	if hero.buffer > 0.0 and hero.coyote > 0.0:
		hero.buffer = 0.0
		hero.coyote = 0.0
		if pad.is_down(GameInput.DOWN) and hero.on_ground and _on_ledge_only(hero):
			hero.y += 1.5
			hero.vy = 30.0
		else:
			hero.vy = -JUMP
			emit("jump", hero.x, hero.y, hero.slot)
	if not pad.is_down(GameInput.A) and hero.vy < -110.0:
		hero.vy = -110.0
	move_body(hero, dt)
	if want != 0:
		for foe in foes:
			if foe.state == Foe.BALL and overlap(hero, foe) and (foe.x - hero.x) * want > 0.0:
				foe.push = want
	if pad.is_down(GameInput.B) and hero.cooldown <= 0.0:
		_shoot(hero)

func _on_ledge_only(hero: Hero) -> bool:
	var row := feet_row(hero)
	for col in range(int(floor((hero.x - hero.hw + 1.0) / TILE)), int(floor((hero.x + hero.hw - 1.0) / TILE)) + 1):
		if tile(col, row) == Levels.SOLID:
			return false
	return row < ROWS - 1

func _shoot(hero: Hero) -> void:
	hero.cooldown = SHOT_COOLDOWN_RAPID if hero.rapid else SHOT_COOLDOWN
	hero.shoot_anim = 0.16
	shots.append({"x": hero.x + hero.facing * 7.0, "y": hero.y - 6.0, "dir": hero.facing, "life": SHOT_LIFE_LONG if hero.long_needle else SHOT_LIFE, "age": 0.0, "owner": hero.slot})
	emit("shoot", hero.x, hero.y, hero.slot)

func kill_hero(hero: Hero) -> void:
	if hero.state != Hero.ALIVE or hero.invuln > 0.0 or phase != PLAY:
		return
	hero.state = Hero.DYING
	hero.timer = 1.4
	hero.vy = -210.0
	hero.vx = 0.0
	hero.lives -= 1
	hero.clear_powers()
	deaths += 1
	stage_deaths += 1
	emit("hurt", hero.x, hero.y, hero.slot)

func _after_death(hero: Hero) -> void:
	if hero.lives <= 0:
		if continues <= 0:
			hero.state = Hero.OUT
			return
		continues -= 1
		continues_used += 1
		hero.lives = max_lives
		emit("continue", hero.x, hero.y, hero.slot)
	hero.state = Hero.ALIVE
	_place(hero, 2.5)
	emit("respawn", hero.x, hero.y, hero.slot)

# ---- yarn ----

func _step_shots(dt: float) -> void:
	var kept: Array[Dictionary] = []
	for shot in shots:
		shot["x"] = float(shot["x"]) + int(shot["dir"]) * SHOT_SPEED * dt
		shot["age"] = float(shot["age"]) + dt
		shot["life"] = float(shot["life"]) - dt
		# The loop droops a little at the end of its reach.
		if float(shot["life"]) < 0.1:
			shot["y"] = float(shot["y"]) + 26.0 * dt
		if float(shot["life"]) > 0.0 and not solid_at(float(shot["x"]), float(shot["y"])) and not _shot_hits(shot):
			kept.append(shot)
	shots = kept

func _shot_hits(shot: Dictionary) -> bool:
	var probe := Item.new("shot", float(shot["x"]), float(shot["y"]) + 4.0)
	probe.hw = 4.0
	probe.h = 8.0
	var hero := heroes[int(shot["owner"])]
	for foe in foes:
		if not overlap(probe, foe):
			continue
		if foe.state == Foe.ROAM or foe.state == Foe.WRAP:
			wrap_foe(foe, hero)
			return true
		if foe.state == Foe.BALL:
			kick(foe, int(shot["dir"]), hero.slot)
			return true
	for hazard in hazards:
		if hazard.kind == Item.INK and overlap(probe, hazard):
			hazard.life = 0.0
			hero.score += 50
			emit("pop", hazard.x, hazard.y)
			return true
	if spark != null and overlap(probe, spark):
		spark_stun = 1.2
		emit("pop", spark.x, spark.y)
		return true
	if boss != null and boss.is_fighting() and boss.state != "enter" and overlap(probe, boss):
		hurt_boss(1, hero.slot)
		return true
	return false

func wrap_foe(foe: Foe, hero: Hero) -> void:
	foe.wrap = mini(foe.need, foe.wrap + (2 if hero.thick else 1))
	foe.owner = hero.slot
	foe.unwrap = UNWRAP_HOLD
	foe.flash = 0.1
	foe.mode = 0
	foe.vx = 0.0
	hero.score += 10
	if foe.wrap >= foe.need:
		foe.state = Foe.BALL
		foe.timer = float(BALL_TIME[difficulty])
		hero.score += 90
		emit("ball", foe.x, foe.y, hero.slot)
	else:
		foe.state = Foe.WRAP
		emit("wrap", foe.x, foe.y, foe.wrap)

func kick(foe: Foe, direction: int, slot: int) -> void:
	foe.state = Foe.ROLL
	foe.dir = direction
	foe.owner = slot
	foe.chain = 0
	foe.bounces = 0
	foe.roll_time = 0.0
	emit("kick", foe.x, foe.y, slot)

## Take a creature off the floor: it tumbles away as a husk.
func knock_out(foe: Foe, toward: int) -> void:
	foe.state = Foe.GONE
	var husk := Item.new(foe.kind, foe.x, foe.y)
	husk.vx = toward * rng.float_range(60.0, 130.0)
	husk.vy = -rng.float_range(200.0, 270.0)
	husk.life = 2.0
	husk.facing = foe.facing
	husks.append(husk)

func drop(kind: String, x: float, y: float) -> void:
	var item := Item.new(kind, clampf(x, 24.0, 456.0), y)
	item.vy = -170.0
	item.life = 10.0
	pickups.append(item)

func hurt_boss(amount: int, slot: int) -> void:
	if boss == null or not boss.is_fighting():
		return
	boss.hp = maxi(0, boss.hp - amount)
	boss.flash = 0.14
	heroes[slot].score += amount * 20
	emit("boss_hit", boss.x, boss.y - boss.h * 0.5, amount)
	if boss.hp > 0:
		BossLogic.struck(self, boss, amount)
		return
	boss.state = "dying"
	boss.timer = 2.8
	boss.vx = 0.0
	boss.vy = 0.0
	hazards.clear()
	for foe in foes:
		if foe.is_live():
			heroes[slot].score += 300
			knock_out(foe, 1 if foe.x > boss.x else -1)
	foes.clear()
	emit("boss_down", boss.x, boss.y - boss.h * 0.5, boss.kind)

# ---- things in the air ----

func _step_hazards(dt: float) -> void:
	var kept: Array[Item] = []
	for hazard in hazards:
		hazard.life -= dt
		hazard.spin += dt
		match hazard.kind:
			Item.INK, Item.WAVE:
				hazard.x += hazard.vx * dt
				if solid_at(hazard.x + signf(hazard.vx) * hazard.hw, hazard.y - 3.0):
					hazard.life = 0.0
			Item.PIN:
				hazard.vy += GRAVITY * 0.55 * dt
				hazard.x += hazard.vx * dt
				hazard.y += hazard.vy * dt
				if hazard.y > 290.0 or hazard.x < 14.0 or hazard.x > 466.0:
					hazard.life = 0.0
			Item.EGG:
				move_body(hazard, dt)
				if hazard.on_ground:
					hazard.life = 0.0
					var foe := Foe.new(Foe.MOTH)
					foe.x = hazard.x
					foe.y = hazard.y
					foe.timer = 0.5
					foe.facing = 1 if hazard.x < 240.0 else -1
					foe.ai_timer = rng.float_range(0.5, 1.5)
					foes.append(foe)
					emit("hatch", foe.x, foe.y)
		if hazard.life > 0.0:
			kept.append(hazard)
	hazards = kept

func _step_pickups(dt: float) -> void:
	var kept: Array[Item] = []
	for item in pickups:
		item.life -= dt
		item.vx = 0.0
		move_body(item, dt)
		if item.life > 0.0:
			kept.append(item)
	pickups = kept

func _step_husks(dt: float) -> void:
	var kept: Array[Item] = []
	for husk in husks:
		husk.life -= dt
		husk.spin += dt
		husk.vy += GRAVITY * dt
		husk.x += husk.vx * dt
		husk.y += husk.vy * dt
		if husk.life > 0.0 and husk.y < 320.0:
			kept.append(husk)
	husks = kept

func _step_spark(dt: float) -> void:
	if spark == null:
		return
	spark.spin += dt
	spark_stun = maxf(0.0, spark_stun - dt)
	var target := nearest_hero(spark.x, spark.y)
	if target == null or spark_stun > 0.0:
		return
	var toward := Vector2(target.x - spark.x, target.y - 4.0 - spark.y)
	if toward.length() > 1.0:
		toward = toward.normalized() * 38.0 * foe_speed()
		spark.x += toward.x * dt
		spark.y += toward.y * dt

func _touch(active: Array) -> void:
	for hero in heroes:
		if hero.state != Hero.ALIVE or not active.has(hero.slot):
			continue
		for index in range(pickups.size() - 1, -1, -1):
			if overlap(hero, pickups[index]):
				_collect(hero, pickups[index])
				pickups.remove_at(index)
		if hero.invuln > 0.0:
			continue
		var doomed := false
		for foe in foes:
			if foe.state == Foe.ROAM and overlap(hero, foe):
				doomed = true
		for hazard in hazards:
			if hazard.kind != Item.EGG and overlap(hero, hazard):
				doomed = true
		if spark != null and spark_stun <= 0.0 and overlap(hero, spark):
			doomed = true
		if boss != null and boss.is_fighting() and overlap(hero, boss):
			doomed = true
		if doomed:
			kill_hero(hero)

func _collect(hero: Hero, item: Item) -> void:
	if Item.GEM_POINTS.has(item.kind):
		var points := int(Item.GEM_POINTS[item.kind])
		hero.score += points
		gems += 1
		emit("gem", item.x, item.y - 6.0, points)
		return
	if item.kind == Item.HEART:
		if hero.lives < max_lives:
			hero.lives += 1
		else:
			hero.score += 1000
		emit("heart", item.x, item.y - 6.0, hero.slot)
		return
	match item.kind:
		"long": hero.long_needle = true
		"rapid": hero.rapid = true
		"thick": hero.thick = true
		"swift": hero.swift = true
	hero.score += 100
	emit("power", item.x, item.y - 6.0, Item.POWERS.find(item.kind))
