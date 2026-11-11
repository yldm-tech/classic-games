extends RefCounted

## How the tower's creatures behave, and what a ball of yarn does once it is kicked. `world` is the World that owns the creature; it is untyped here because World preloads this script.

const Foe := preload("res://games/yarn_tumble/foe.gd")
const Hero := preload("res://games/yarn_tumble/hero.gd")
const Item := preload("res://games/yarn_tumble/item.gd")
const Levels := preload("res://games/yarn_tumble/levels.gd")

const FOE_JUMP := 270.0
const POWER_CHANCE := 0.12

static func step(world: Variant, foe: Foe, dt: float) -> void:
	foe.flash = maxf(0.0, foe.flash - dt)
	foe.anim += dt
	match foe.state:
		Foe.SPAWN:
			foe.timer -= dt
			if foe.timer <= 0.0:
				foe.state = Foe.ROAM
		Foe.ROAM:
			_roam(world, foe, dt)
		Foe.WRAP:
			foe.vx = 0.0
			world.move_body(foe, dt)
			foe.unwrap -= dt
			if foe.unwrap <= 0.0:
				foe.wrap -= 1
				foe.unwrap = world.UNWRAP_STEP
				if foe.wrap <= 0:
					foe.wrap = 0
					foe.state = Foe.ROAM
					foe.angry = true
					foe.mode = 0
					foe.ai_timer = 0.6
					world.emit("free", foe.x, foe.y)
		Foe.BALL:
			foe.vx = foe.push * 62.0
			foe.push = 0
			world.move_body(foe, dt)
			foe.timer -= dt
			if foe.timer <= 0.0:
				foe.wrap = foe.need - 1
				foe.state = Foe.WRAP
				foe.unwrap = world.UNWRAP_STEP
				world.emit("loosen", foe.x, foe.y)
		Foe.ROLL:
			_roll(world, foe, dt)

static func _speed(world: Variant, foe: Foe) -> float:
	return float(world.foe_speed()) * (1.3 if foe.angry or world.hurry else 1.0)

static func _roam(world: Variant, foe: Foe, dt: float) -> void:
	var pace := _speed(world, foe)
	var target: Hero = world.nearest_hero(foe.x, foe.y)
	match foe.kind:
		Foe.MOTH:
			_roam_moth(world, foe, dt, pace, target)
		Foe.SPRING:
			_roam_spring(world, foe, dt, pace, target)
		Foe.PIN:
			_roam_pin(world, foe, dt, pace, target)
		Foe.SNIP:
			_roam_snip(foe, dt, pace, target)
		Foe.INK:
			_roam_ink(world, foe, dt, pace, target)

## Walk a ledge; at its end either turn back or step off. Returns true when it has just turned.
static func _patrol(world: Variant, foe: Foe, speed: float, may_fall: bool) -> void:
	if not foe.on_ground:
		return
	if not world.ground_ahead(foe, foe.facing) and not foe.edge_go:
		if may_fall and world.rng.chance(0.5):
			foe.edge_go = true
		else:
			foe.facing = -foe.facing
	foe.vx = foe.facing * speed

static func _move(world: Variant, foe: Foe, dt: float) -> int:
	var was_grounded := foe.on_ground
	var wall: int = world.move_body(foe, dt)
	if foe.on_ground and not was_grounded:
		foe.edge_go = false
	return wall

## The mothkin: a plodder that wanders the ledges, steps off their ends and hops up towards a knitter above it.
static func _roam_moth(world: Variant, foe: Foe, dt: float, pace: float, target: Hero) -> void:
	_patrol(world, foe, 34.0 * pace, true)
	if foe.on_ground:
		foe.ai_timer -= dt
		if foe.ai_timer <= 0.0:
			foe.ai_timer = world.rng.float_range(1.6, 3.4)
			if target != null and target.y < foe.y - 24.0 and world.ledge_above(foe) and world.rng.chance(0.6):
				foe.vy = -FOE_JUMP
			elif target != null and world.rng.chance(0.35):
				foe.facing = 1 if target.x > foe.x else -1
				foe.vx = foe.facing * 34.0 * pace
	var wall := _move(world, foe, dt)
	if wall != 0:
		foe.facing = -wall

## The springtail: sits, then leaps at the nearest knitter, high when the knitter is above.
static func _roam_spring(world: Variant, foe: Foe, dt: float, pace: float, target: Hero) -> void:
	if foe.on_ground:
		foe.vx = 0.0
		foe.ai_timer -= dt * pace
		if foe.ai_timer <= 0.0:
			foe.ai_timer = world.rng.float_range(0.5, 1.1)
			if target != null and absf(target.x - foe.x) > 6.0:
				foe.facing = 1 if target.x > foe.x else -1
			var high: bool = target != null and target.y < foe.y - 24.0 and world.rng.chance(0.7)
			foe.vy = -275.0 if high else -175.0
			foe.vx = foe.facing * (38.0 if high else 76.0) * pace
			world.emit("hop", foe.x, foe.y)
	var wall := _move(world, foe, dt)
	if wall != 0:
		foe.facing = -wall
		foe.vx = -foe.vx

## The pinback: slow until a knitter stands on its level, then it shivers and charges.
static func _roam_pin(world: Variant, foe: Foe, dt: float, pace: float, target: Hero) -> void:
	match foe.mode:
		0:
			_patrol(world, foe, 24.0 * pace, false)
			foe.ai_timer -= dt
			if foe.ai_timer <= 0.0 and foe.on_ground and target != null and absf(target.y - foe.y) < 10.0 and absf(target.x - foe.x) < 130.0:
				foe.facing = 1 if target.x > foe.x else -1
				foe.mode = 1
				foe.timer = 0.5
				foe.vx = 0.0
				world.emit("alert", foe.x, foe.y)
		1:
			foe.vx = 0.0
			foe.timer -= dt
			if foe.timer <= 0.0:
				foe.mode = 2
				foe.timer = 1.5
				world.emit("charge", foe.x, foe.y)
		2:
			foe.vx = foe.facing * 132.0 * pace
			foe.timer -= dt
			if foe.timer <= 0.0:
				foe.mode = 0
				foe.ai_timer = 1.2
	var wall := _move(world, foe, dt)
	if wall != 0:
		foe.facing = -wall
		if foe.mode == 2:
			foe.mode = 0
			foe.ai_timer = 1.2

## The snipper: flies through everything, drifting towards the nearest knitter.
static func _roam_snip(foe: Foe, dt: float, pace: float, target: Hero) -> void:
	foe.phase += dt
	foe.on_ground = false
	var toward := Vector2.ZERO
	if target != null:
		toward = Vector2(target.x - foe.x, target.y - 6.0 - foe.y)
		if toward.length() > 1.0:
			toward = toward.normalized()
		if absf(target.x - foe.x) > 4.0:
			foe.facing = 1 if target.x > foe.x else -1
	foe.vx = toward.x * 30.0 * pace
	foe.vy = toward.y * 22.0 * pace + sin(foe.phase * 3.0) * 14.0
	foe.x = clampf(foe.x + foe.vx * dt, 24.0, 456.0)
	foe.y = clampf(foe.y + foe.vy * dt, 44.0, 252.0)

## The inkblot: keeps to its ledge and spits a slow drop of dye along it.
static func _roam_ink(world: Variant, foe: Foe, dt: float, pace: float, target: Hero) -> void:
	if foe.mode == 0:
		_patrol(world, foe, 20.0 * pace, false)
		foe.ai_timer -= dt
		if foe.ai_timer <= 0.0:
			if foe.on_ground and target != null and absf(target.y - foe.y) < 14.0:
				foe.facing = 1 if target.x > foe.x else -1
				foe.mode = 1
				foe.timer = 0.4
			else:
				foe.ai_timer = 0.5
	else:
		foe.vx = 0.0
		foe.timer -= dt
		if foe.timer <= 0.0:
			foe.mode = 0
			foe.ai_timer = world.rng.float_range(2.2, 3.6) / pace
			var drop := Item.new(Item.INK, foe.x + foe.facing * 8.0, foe.y - 3.0)
			drop.vx = foe.facing * 92.0 * pace
			drop.life = 2.6
			drop.hw = 3.0
			drop.h = 6.0
			world.hazards.append(drop)
			world.emit("spit", foe.x, foe.y)
	var wall := _move(world, foe, dt)
	if wall != 0:
		foe.facing = -wall

## A kicked ball: it rolls, drops from ledge to ledge, turns at walls and knocks out every creature in its way. It bursts against a wall of the bottom floor, on a guardian, or when it has rolled long enough.
static func _roll(world: Variant, ball: Foe, dt: float) -> void:
	ball.roll_time += dt
	ball.vx = ball.dir * world.ROLL_SPEED
	var was_grounded := ball.on_ground
	var wall: int = world.move_body(ball, dt)
	if ball.on_ground and not was_grounded:
		world.emit("thud", ball.x, ball.y)
	var owner: Hero = world.heroes[ball.owner]
	for other: Foe in world.foes:
		if other == ball or other.state == Foe.SPAWN or other.state == Foe.ROLL or other.state == Foe.GONE or not world.overlap(ball, other):
			continue
		ball.chain += 1
		var points := int(world.CHAIN_POINTS[mini(ball.chain, world.CHAIN_POINTS.size()) - 1])
		owner.score += points
		world.kos += 1
		world.emit("ko", other.x, other.y - 8.0, points, ball.chain)
		world.drop(Item.GEMS[mini(ball.chain, Item.GEMS.size()) - 1], other.x, other.y - 4.0)
		world.knock_out(other, ball.dir)
	for hazard: Item in world.hazards:
		if hazard.kind != Item.EGG and world.overlap(ball, hazard):
			hazard.life = 0.0
	if world.boss != null and world.boss.is_fighting() and world.boss.state != "enter" and world.overlap(ball, world.boss):
		var hit_x := ball.x
		var hit_y := ball.y
		var chain := ball.chain
		world.hurt_boss(world.BALL_DAMAGE, ball.owner)
		if ball.is_live():
			burst(world, ball)
		else:
			# The guardian fell to this very ball, which took the ball's creature with it.
			world.kos += 1
			world.best_roll = maxi(world.best_roll, chain + 1)
			world.emit("burst", hit_x, hit_y, chain + 1, ball.owner)
		return
	if wall != 0:
		ball.dir = -wall
		ball.bounces += 1
		world.emit("bounce", ball.x, ball.y)
		if (ball.on_ground and world.feet_row(ball) == Levels.FLOOR_ROW) or ball.bounces >= 6:
			burst(world, ball)
			return
	if ball.roll_time > 7.0:
		burst(world, ball)

static func burst(world: Variant, ball: Foe) -> void:
	var owner: Hero = world.heroes[ball.owner]
	var total := ball.chain + 1
	owner.score += world.BASE_POINTS
	world.kos += 1
	world.best_roll = maxi(world.best_roll, total)
	world.emit("burst", ball.x, ball.y - 6.0, total, ball.owner)
	if total >= 3:
		var hurt: bool = owner.lives < world.max_lives
		world.drop(Item.HEART if hurt and world.rng.chance(0.3) else str(world.rng.pick(Item.POWERS)), ball.x, ball.y - 4.0)
	elif world.rng.chance(POWER_CHANCE):
		world.drop(str(world.rng.pick(Item.POWERS)), ball.x, ball.y - 4.0)
	world.knock_out(ball, -ball.dir)
