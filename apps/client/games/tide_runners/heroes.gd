extends RefCounted

## The two divers: movement, aiming, firing and dying. A diver is a Dictionary so the simulation can be compared and replayed as plain data; `g` is the game module.

const World := preload("res://games/tide_runners/world.gd")

const RUN := 84.0
const JUMP := 272.0
const GRAVITY := 620.0
const MAX_FALL := 360.0
const HALF_WIDTH := 4.0
const STAND_HEIGHT := 20.0
const AIR_HEIGHT := 16.0
const PRONE_HEIGHT := 8.0
const DROP_TIME := 0.24
const RESPAWN_SAFE := 2.5
const DEATH_TIME := 1.3
## Seconds between shots of each weapon, indexed by weapon id.
const COOLDOWN := [0.15, 0.26, 0.2, 0.5, 0.42, 0.3]

static func make(slot: int, lives: int) -> Dictionary:
	return {
		"slot": slot, "active": false, "x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "ground": false, "face": 1, "aim": Vector2i(1, 0),
		"prone": false, "drop_t": 0.0, "alive": false, "dead_t": 0.0, "inv": 0.0, "weapon": 0, "cd": 0.0, "lives": lives, "score": 0,
		"out": true, "shield": false, "anim": 0.0, "fire_t": 0.0, "next_life": 20000, "moving": false, "seen": false,
	}

static func height(h: Dictionary) -> float:
	if h["prone"]:
		return PRONE_HEIGHT
	return STAND_HEIGHT if h["ground"] else AIR_HEIGHT

static func box(h: Dictionary) -> Rect2:
	var tall := height(h)
	var half := 7.0 if h["prone"] else HALF_WIDTH - 1.0
	return Rect2(float(h["x"]) - half, float(h["y"]) - tall + 1.0, half * 2.0, tall - 2.0)

static func muzzle(h: Dictionary) -> Vector2:
	if h["prone"]:
		return Vector2(float(h["x"]) + int(h["face"]) * 13.0, float(h["y"]) - 4.0)
	var aim: Vector2i = h["aim"]
	return Vector2(float(h["x"]) + aim.x * 10.0, float(h["y"]) - 12.0 + aim.y * 11.0)

static func step(g: Variant, h: Dictionary, pad: GameInput, dt: float) -> void:
	h["inv"] = maxf(0.0, float(h["inv"]) - dt)
	h["cd"] = maxf(0.0, float(h["cd"]) - dt)
	h["fire_t"] = maxf(0.0, float(h["fire_t"]) - dt)
	h["drop_t"] = maxf(0.0, float(h["drop_t"]) - dt)
	if not h["alive"]:
		_step_fallen(g, h, dt)
		return
	var world: World = g.world
	var held := pad.move_sign()
	var brace := pad.is_down(GameInput.R)
	if held.x != 0:
		h["face"] = held.x
	var face: int = h["face"]
	var on_ground: bool = h["ground"]
	h["prone"] = on_ground and held.y > 0 and held.x == 0
	var aim := Vector2i(face, 0)
	if held.y < 0:
		aim = Vector2i(held.x, -1)
	elif held.y > 0:
		if not on_ground:
			aim = Vector2i(held.x, 1)
		elif held.x != 0:
			aim = Vector2i(face, 1)
	h["aim"] = aim
	var vx := 0.0 if (h["prone"] or brace) else held.x * RUN
	var vy: float = h["vy"]
	var x: float = h["x"]
	var y: float = h["y"]
	if pad.just_pressed(GameInput.A) and on_ground:
		var under: int = world.floor_kind(x - HALF_WIDTH, x + HALF_WIDTH, y)
		if held.y > 0 and under == World.PLAT and g.can_drop(y):
			h["drop_t"] = DROP_TIME
		else:
			vy = -JUMP
			g.sfx("jump")
		on_ground = false
		h["prone"] = false
	if not on_ground and vy < -110.0 and not pad.is_down(GameInput.A):
		vy = -110.0
	vy = minf(MAX_FALL, vy + GRAVITY * dt)
	# Sideways first, against solid tiles and the edges of the view.
	var tall := height(h)
	var next_x := x + vx * dt
	if vx != 0.0 and world.box_hits(next_x - HALF_WIDTH, y - tall, next_x + HALF_WIDTH, y - 0.5):
		next_x = x
	var bounds: Vector2 = g.hero_bounds()
	x = clampf(next_x, bounds.x, bounds.y)
	# Then down or up.
	var next_y := y + vy * dt
	if vy >= 0.0:
		var top: float = world.landing(x - HALF_WIDTH, x + HALF_WIDTH, y, next_y, float(h["drop_t"]) > 0.0)
		if top < INF:
			if not on_ground and vy > 120.0:
				g.dust(x, top)
			y = top
			vy = 0.0
			on_ground = true
		else:
			y = next_y
			on_ground = false
	else:
		if world.box_hits(x - HALF_WIDTH, next_y - tall, x + HALF_WIDTH, next_y - tall + 3.0):
			vy = 0.0
		else:
			y = next_y
		on_ground = false
	h["x"] = x
	h["y"] = y
	h["vx"] = vx
	h["vy"] = vy
	h["ground"] = on_ground
	h["moving"] = vx != 0.0
	h["anim"] = float(h["anim"]) + dt
	if y > float(g.drown_line()):
		g.splash(x, float(g.drown_line()) - 10.0)
		g.fell(h)
		return
	if (pad.is_down(GameInput.B) or pad.is_down(GameInput.X)) and float(h["cd"]) <= 0.0:
		h["cd"] = COOLDOWN[int(h["weapon"])]
		h["fire_t"] = 0.07
		g.fire(h)

## A diver who was hit tumbles for a moment, then comes back if a life is left.
static func _step_fallen(g: Variant, h: Dictionary, dt: float) -> void:
	if h["out"]:
		return
	h["vy"] = float(h["vy"]) + 520.0 * dt
	h["x"] = float(h["x"]) + float(h["vx"]) * dt
	h["y"] = float(h["y"]) + float(h["vy"]) * dt
	h["dead_t"] = float(h["dead_t"]) - dt
	if float(h["dead_t"]) > 0.0:
		return
	if int(h["lives"]) > 0:
		g.respawn(h)
	else:
		h["out"] = true
