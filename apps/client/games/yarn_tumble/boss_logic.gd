extends RefCounted

## The two floor guardians. `world` is the World that owns them; it is untyped here because World preloads this script.

const Boss := preload("res://games/yarn_tumble/boss.gd")
const Foe := preload("res://games/yarn_tumble/foe.gd")
const Hero := preload("res://games/yarn_tumble/hero.gd")
const Item := preload("res://games/yarn_tumble/item.gd")

const HOVER_Y := 100.0
const FLOOR_Y := 254.0
const BONUS := [10000, 20000]

static func step(world: Variant, boss: Boss, dt: float) -> void:
	boss.flash = maxf(0.0, boss.flash - dt)
	boss.clock += dt
	if boss.state == "dying":
		boss.timer -= dt
		if int(boss.timer * 60.0) % 12 == 0:
			world.emit("boom", boss.x + world.rng.float_range(-18.0, 18.0), boss.y - world.rng.float_range(2.0, 30.0))
		if boss.timer <= 0.0:
			world.bosses_defeated += 1
			for hero: Hero in world.heroes:
				if hero.state == Hero.ALIVE or hero.state == Hero.DYING:
					hero.score += int(BONUS[boss.kind])
			world.emit("boss_gone", boss.x, boss.y - boss.h * 0.5, int(BONUS[boss.kind]))
			# A guardian with floors still above it leaves a heart patch for each knitter who saw it fall.
			if world.stage < world.Levels.count():
				for hero: Hero in world.heroes:
					if hero.state == Hero.ALIVE or hero.state == Hero.DYING:
						world.drop(Item.HEART, boss.x + (hero.slot * 2 - 1) * 14.0, minf(boss.y, FLOOR_Y) - 10.0)
			world.boss = null
		return
	if boss.kind == Boss.DUCHESS:
		_duchess(world, boss, dt)
	else:
		_regent(world, boss, dt)

## A blow that did not finish the guardian. A ball knocks the Duchess out of the air for a moment.
static func struck(world: Variant, boss: Boss, amount: int) -> void:
	if boss.kind == Boss.DUCHESS and amount >= world.BALL_DAMAGE and boss.state != "enter":
		boss.state = "hurt"
		boss.timer = 0.8

static func _cap(world: Variant, boss: Boss) -> int:
	return (3 if boss.enraged() else 2) + (1 if world.difficulty == 2 else 0)

# ---- Duchess Dustwing ----

static func _duchess(world: Variant, boss: Boss, dt: float) -> void:
	var fury := boss.enraged()
	match boss.state:
		"enter":
			boss.y += 70.0 * dt
			if boss.y >= HOVER_Y:
				_hover(boss, 3.0)
		"hover":
			var want_x := 240.0 + 165.0 * sin(boss.clock * 0.8)
			boss.x = move_toward(boss.x, want_x, 95.0 * dt)
			boss.y = move_toward(boss.y, HOVER_Y + 8.0 * sin(boss.clock * 3.0), 60.0 * dt)
			boss.facing = 1 if want_x > boss.x else -1
			boss.summon -= dt
			if boss.summon <= 0.0:
				boss.summon = 1.5
				if world.minions() < _cap(world, boss):
					var egg := Item.new(Item.EGG, boss.x, boss.y)
					egg.hw = 3.0
					egg.h = 6.0
					egg.life = 30.0
					world.hazards.append(egg)
					world.emit("egg", boss.x, boss.y)
			boss.timer -= dt
			if boss.timer <= 0.0:
				boss.state = "aim"
				boss.timer = 0.5 if fury else 0.75
				world.emit("alert", boss.x, boss.y - 12.0)
		"aim":
			boss.timer -= dt
			if boss.timer <= 0.0:
				boss.state = "swoop"
				boss.from_x = boss.x
				boss.from_y = boss.y
				boss.to_x = 62.0 if boss.x > 240.0 else 418.0
				boss.facing = 1 if boss.to_x > boss.x else -1
				boss.progress = 0.0
				world.emit("swoop", boss.x, boss.y)
		"swoop":
			boss.progress = minf(1.0, boss.progress + dt / (1.35 if fury else 1.75))
			boss.x = lerpf(boss.from_x, boss.to_x, boss.progress)
			boss.y = boss.from_y + (FLOOR_Y - 4.0 - boss.from_y) * sin(PI * boss.progress)
			if boss.progress >= 1.0:
				boss.swoops += 1
				if boss.swoops >= (3 if fury else 2):
					boss.swoops = 0
					boss.state = "land"
				else:
					_hover(boss, 1.3)
		"land":
			boss.x = move_toward(boss.x, 240.0, 150.0 * dt)
			boss.y = move_toward(boss.y, FLOOR_Y, 150.0 * dt)
			if is_equal_approx(boss.x, 240.0) and is_equal_approx(boss.y, FLOOR_Y):
				boss.state = "rest"
				boss.timer = 2.0 if fury else 2.7
				world.emit("thud", boss.x, boss.y)
		"rest", "hurt":
			if boss.state == "hurt":
				boss.y = minf(FLOOR_Y, boss.y + 40.0 * dt)
			boss.timer -= dt
			if boss.timer <= 0.0:
				boss.state = "rise"
		"rise":
			boss.y -= 90.0 * dt
			if boss.y <= HOVER_Y:
				_hover(boss, 2.4 if fury else 3.2)

static func _hover(boss: Boss, seconds: float) -> void:
	boss.state = "hover"
	boss.timer = seconds
	boss.summon = minf(boss.summon, 0.8)

# ---- Snipjaw Regent ----

static func _regent(world: Variant, boss: Boss, dt: float) -> void:
	var fury := boss.enraged()
	var target: Hero = world.nearest_hero(boss.x, boss.y)
	boss.summon -= dt
	if boss.summon <= 0.0 and boss.state != "enter":
		boss.summon = 5.0 if fury else 6.5
		if world.minions() < _cap(world, boss):
			var foe := Foe.new(Foe.PIN if boss.cycle % 2 == 0 else Foe.SPRING)
			foe.x = float(world.rng.pick([88.0, 240.0, 392.0]))
			foe.y = 40.0
			foe.timer = 0.6
			foe.facing = 1 if foe.x < boss.x else -1
			foe.ai_timer = 1.0
			world.foes.append(foe)
			world.emit("hatch", foe.x, foe.y)
	match boss.state:
		"enter":
			boss.vx = 0.0
			world.move_body(boss, dt, true)
			if boss.on_ground:
				# The entrance only shakes the floor: nobody should lose a life before the fight has begun.
				boss.state = "recover"
				boss.timer = 1.4
				world.emit("slam", boss.x, boss.y)
		"walk":
			if target != null and absf(target.x - boss.x) > 6.0:
				boss.facing = 1 if target.x > boss.x else -1
			boss.vx = boss.facing * (42.0 if fury else 28.0)
			world.move_body(boss, dt, true)
			boss.timer -= dt
			if boss.timer <= 0.0:
				boss.cycle += 1
				var leap: bool = boss.cycle % 2 == 0
				if world.rng.chance(0.3):
					leap = not leap
				boss.state = "crouch" if leap else "raise"
				boss.timer = 0.5
				boss.vx = 0.0
				world.emit("alert", boss.x, boss.y - 32.0)
		"crouch":
			world.move_body(boss, dt, true)
			boss.timer -= dt
			if boss.timer <= 0.0:
				var aim_x := clampf(target.x if target != null else 240.0, 48.0, 432.0)
				boss.vy = -340.0
				boss.vx = clampf((aim_x - boss.x) / (2.0 * 340.0 / world.GRAVITY), -190.0, 190.0)
				boss.state = "leap"
				world.emit("leap", boss.x, boss.y)
		"leap":
			var wall: int = world.move_body(boss, dt, true)
			if wall != 0:
				boss.vx = 0.0
			if boss.on_ground:
				_slam(world, boss, 0.7 if fury else 1.0)
		"raise":
			world.move_body(boss, dt, true)
			boss.timer -= dt
			if boss.timer <= 0.0:
				for index in (5 if fury else 3):
					var pin := Item.new(Item.PIN, boss.x + boss.facing * 12.0, boss.y - 26.0)
					pin.vx = boss.facing * (46.0 + 40.0 * index)
					pin.vy = -(215.0 + 14.0 * index)
					pin.life = 6.0
					pin.hw = 3.0
					pin.h = 6.0
					pin.facing = boss.facing
					world.hazards.append(pin)
				world.emit("throw", boss.x, boss.y - 26.0)
				boss.state = "recover"
				boss.timer = 0.8
		"recover":
			boss.vx = 0.0
			world.move_body(boss, dt, true)
			boss.timer -= dt
			if boss.timer <= 0.0:
				boss.state = "walk"
				boss.timer = 1.4 if fury else 2.0

## The Regent lands: a shock wave runs along the floor both ways.
static func _slam(world: Variant, boss: Boss, rest: float) -> void:
	boss.state = "recover"
	boss.timer = rest
	boss.vx = 0.0
	for side: int in [-1, 1]:
		var wave := Item.new(Item.WAVE, boss.x + side * 18.0, boss.y)
		wave.vx = side * 125.0
		wave.life = 1.5
		wave.hw = 5.0
		wave.h = 9.0
		wave.facing = side
		world.hazards.append(wave)
	world.emit("slam", boss.x, boss.y)
