extends RefCounted

## The two bosses. Neither can be hurt by anything the robots own: each one throws things into its room that turn into something to pick up, and those are what gets thrown back. Static functions on the world they are handed, like foes.gd.
##
##   vacuum  the Dustmaw, a canister on wheels at the top of the pipe shaft. It spits lumps of scrap, sucks the robots towards its mouth and rams across the floor. Its shell turns everything away: a throw counts only while the mouth is open, which is while it spits and while it sucks.
##   crane   the Overseer, a trolley on the ceiling rail of the control loft. It drops heavy nuts, then slams its claw into the floor, where the claw stays stuck for a moment. Throw upwards at the trolley or sideways at the stuck claw.

const MISS := 0
const HURT := 1
const DEFLECTED := 2

static func create(world: Variant, spec: Dictionary) -> Dictionary:
	var kind := str(spec["kind"])
	var scale := float(world.rules["boss"])
	var boss := {
		"kind": kind, "floor": float(spec["floor"]), "left": float(spec["left"]), "right": float(spec["right"]), "camera": spec["camera"],
		"mode": "enter", "time": 1.4, "face": -1, "flash": 0.0, "count": 0, "alive": true, "shake": 0.0, "angry": false, "vx": 0.0,
	}
	if kind == "vacuum":
		boss["max_hp"] = maxi(4, roundi(8.0 * scale))
		boss["x"] = float(spec["right"]) - 34.0
		boss["y"] = float(spec["floor"])
	else:
		boss["max_hp"] = maxi(5, roundi(10.0 * scale))
		boss["x"] = (float(spec["left"]) + float(spec["right"])) * 0.5
		boss["y"] = float(spec["floor"]) - 138.0
		boss["claw"] = 8.0
	boss["hp"] = boss["max_hp"]
	return boss

static func step(world: Variant, delta: float) -> void:
	var boss: Dictionary = world.boss
	boss["flash"] = maxf(0.0, float(boss["flash"]) - delta)
	boss["time"] = float(boss["time"]) - delta
	if str(boss["mode"]) == "dying":
		boss["count"] = int(boss["count"]) + 1
		if int(boss["count"]) % 9 == 0:
			world.emit("boss_burst", float(boss["x"]) + world.rng.float_range(-22.0, 22.0), float(boss["y"]) - world.rng.float_range(4.0, 34.0) + (30.0 if str(boss["kind"]) == "crane" else 0.0))
		if float(boss["time"]) <= 0.0 and bool(boss["alive"]):
			boss["alive"] = false
			boss["mode"] = "gone"
			world.emit("boss_down", float(boss["x"]), float(boss["y"]) - 16.0)
			world.boss_beaten()
		return
	if not bool(boss["alive"]):
		return
	if str(boss["kind"]) == "vacuum":
		_step_vacuum(world, boss, delta)
	else:
		_step_crane(world, boss, delta)

static func _target(world: Variant, boss: Dictionary) -> Dictionary:
	return world.nearest_hero(float(boss["x"]), float(boss["floor"]))

# ---- the Dustmaw ----

static func _step_vacuum(world: Variant, boss: Dictionary, delta: float) -> void:
	var facing := int(boss["face"])
	var angry := bool(boss["angry"])
	var speed := float(world.rules["speed"])
	match str(boss["mode"]):
		"enter", "idle":
			if float(boss["time"]) <= 0.0:
				var next := int(boss["count"]) % 3
				boss["count"] = int(boss["count"]) + 1
				if next == 0:
					boss["mode"] = "spit"
					boss["left_to_spit"] = 3 if angry else 2
					boss["time"] = 0.4
				elif next == 1:
					boss["mode"] = "inhale"
					boss["time"] = 2.0 if angry else 2.4
					world.emit("boss_inhale", float(boss["x"]), float(boss["y"]) - 16.0)
				else:
					boss["mode"] = "rev"
					boss["time"] = 0.7
					world.emit("rev", float(boss["x"]), float(boss["y"]))
		"spit":
			if float(boss["time"]) <= 0.0:
				var mouth_x := float(boss["x"]) + float(facing) * 24.0
				world.add_shot("junk", mouth_x, float(boss["y"]) - 16.0, float(facing) * world.rng.float_range(60.0, 170.0), -world.rng.float_range(150.0, 240.0), 480.0)
				world.emit("boss_spit", mouth_x, float(boss["y"]) - 16.0)
				boss["left_to_spit"] = int(boss["left_to_spit"]) - 1
				boss["time"] = 0.55
				if int(boss["left_to_spit"]) <= 0:
					boss["mode"] = "idle"
					boss["time"] = 1.0 if angry else 1.5
		"inhale":
			# Everything loose slides towards the mouth.
			for hero: Dictionary in world.heroes:
				if int(hero["state"]) == world.H_NORMAL and not bool(hero["hide"]):
					var pull := -float(facing) * 40.0 * speed * delta
					hero["x"] = clampf(float(hero["x"]) + pull, float(boss["left"]) + world.HERO_HALF, float(boss["right"]) - world.HERO_HALF)
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "idle"
				boss["time"] = 0.7
		"rev":
			boss["shake"] = 1.0
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "charge"
				boss["shake"] = 0.0
				world.emit("boss_charge", float(boss["x"]), float(boss["y"]))
		"charge":
			var x := float(boss["x"]) + float(facing) * (165.0 if angry else 135.0) * speed * delta
			var stop := float(boss["left"]) + 34.0 if facing < 0 else float(boss["right"]) - 34.0
			if (facing < 0 and x <= stop) or (facing > 0 and x >= stop):
				x = stop
				boss["face"] = -facing
				boss["mode"] = "idle"
				boss["time"] = 1.2 if angry else 1.6
				world.emit("boss_slam", x, float(boss["y"]))
			boss["x"] = x
	# Touching the machine hurts, crate or no crate.
	for hero: Dictionary in world.heroes:
		if int(hero["state"]) == world.H_NORMAL and absf(float(hero["x"]) - float(boss["x"])) < 20.0 + world.HERO_HALF and float(hero["y"]) > float(boss["y"]) - 30.0:
			world.hurt_hero(hero, float(boss["x"]), true)

# ---- the Overseer ----

static func _step_crane(world: Variant, boss: Dictionary, delta: float) -> void:
	var angry := bool(boss["angry"])
	var speed := float(world.rules["speed"])
	var target := _target(world, boss)
	var target_x := float(target["x"]) if not target.is_empty() else float(boss["x"])
	var low := float(boss["left"]) + 30.0
	var high := float(boss["right"]) - 30.0
	var rest := 8.0
	var reach := float(boss["floor"]) - (float(boss["y"]) + 28.0) - 22.0
	match str(boss["mode"]):
		"enter":
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "track"
				boss["time"] = 1.6
		"track":
			boss["x"] = clampf(move_toward(float(boss["x"]), target_x, (86.0 if angry else 62.0) * speed * delta), low, high)
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "drop"
				boss["left_to_drop"] = 3 if angry else 2
				boss["time"] = 0.3
		"drop":
			boss["x"] = clampf(move_toward(float(boss["x"]), target_x, 40.0 * speed * delta), low, high)
			if float(boss["time"]) <= 0.0:
				world.add_shot("bolt", float(boss["x"]), float(boss["y"]) + 44.0, 0.0, 30.0, 520.0)
				world.emit("drop", float(boss["x"]), float(boss["y"]) + 40.0)
				boss["left_to_drop"] = int(boss["left_to_drop"]) - 1
				boss["time"] = 0.7
				if int(boss["left_to_drop"]) <= 0:
					boss["mode"] = "chase"
					boss["time"] = 1.1
		"chase":
			boss["x"] = clampf(move_toward(float(boss["x"]), target_x, (110.0 if angry else 84.0) * speed * delta), low, high)
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "aim"
				boss["time"] = 0.55 if angry else 0.7
				world.emit("rev", float(boss["x"]), float(boss["y"]))
		"aim":
			boss["shake"] = 1.0
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "slam"
				boss["shake"] = 0.0
		"slam":
			boss["claw"] = minf(reach, float(boss["claw"]) + 520.0 * delta)
			if float(boss["claw"]) >= reach:
				boss["mode"] = "stuck"
				boss["time"] = 1.3 if angry else 1.7
				world.emit("boss_slam", float(boss["x"]), float(boss["floor"]))
		"stuck":
			if float(boss["time"]) <= 0.0:
				boss["mode"] = "retract"
		"retract":
			boss["claw"] = maxf(rest, float(boss["claw"]) - 190.0 * delta)
			if float(boss["claw"]) <= rest:
				boss["mode"] = "track"
				boss["time"] = 1.2 if angry else 1.8
				# Once angry it calls a beetle in from the side now and then.
				if angry and world.foes.size() < 2 and world.rng.chance(0.6):
					var side := float(boss["left"]) + 14.0 if world.rng.chance(0.5) else float(boss["right"]) - 14.0
					world.foes.append(world.Foes.create({"kind": "bug", "at": Vector2(side, float(boss["floor"]) - 40.0), "face": 1 if side < float(boss["x"]) else -1}))
					world.emit("chute", side, float(boss["floor"]) - 40.0)
	var claw_top := float(boss["y"]) + 28.0 + float(boss["claw"])
	for hero: Dictionary in world.heroes:
		if int(hero["state"]) == world.H_NORMAL and absf(float(hero["x"]) - float(boss["x"])) < 11.0 + world.HERO_HALF and float(hero["y"]) > claw_top + 4.0 and float(hero["y"]) - world.HERO_TALL < claw_top + 22.0:
			world.hurt_hero(hero, float(boss["x"]), true)

# ---- being hit ----

## Something thrown is at (x, y), `half` wide and `half_tall` high around that point. Returns MISS, HURT or DEFLECTED.
static func take_throw(world: Variant, x: float, y: float, half: float, half_tall: float) -> int:
	var boss: Dictionary = world.boss
	if not bool(boss["alive"]) or str(boss["mode"]) == "dying":
		return MISS
	var touched := false
	if str(boss["kind"]) == "vacuum":
		touched = absf(x - float(boss["x"])) < 22.0 + half and y + half_tall > float(boss["y"]) - 36.0 and y - half_tall < float(boss["y"])
		# Its shell shrugs everything off; only the open mouth is soft.
		if touched and str(boss["mode"]) != "spit" and str(boss["mode"]) != "inhale":
			world.emit("clang", x, y)
			return DEFLECTED
	else:
		var body_top := float(boss["y"])
		var claw_top := body_top + 28.0 + float(boss["claw"])
		touched = absf(x - float(boss["x"])) < 23.0 + half and y + half_tall > body_top + 4.0 and y - half_tall < body_top + 28.0
		touched = touched or (absf(x - float(boss["x"])) < 12.0 + half and y + half_tall > claw_top and y - half_tall < claw_top + 22.0)
	if not touched:
		return MISS
	boss["hp"] = int(boss["hp"]) - 1
	boss["flash"] = 0.3
	world.emit("boss_hit", x, y)
	if int(boss["hp"]) <= 0:
		boss["mode"] = "dying"
		boss["time"] = 2.2
		boss["count"] = 0
		boss["shake"] = 1.0
		for shot: Dictionary in world.shots:
			shot["gone"] = true
		for foe: Dictionary in world.foes:
			if int(foe["state"]) == 0 and world.is_active_at(float(foe["x"]), float(foe["y"])) and float(foe["y"]) <= float(boss["floor"]) + 1.0:
				world.Foes.hit(world, foe, -1, 9, 1.0, 0, false)
		return HURT
	if not bool(boss["angry"]) and int(boss["hp"]) * 2 <= int(boss["max_hp"]):
		boss["angry"] = true
		world.emit("boss_angry", float(boss["x"]), float(boss["y"]) - 20.0)
	if str(boss["mode"]) == "inhale":
		boss["mode"] = "idle"
		boss["time"] = 0.8
	return HURT
