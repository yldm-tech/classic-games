extends "res://games/ember_trail/body.gd"

## The lamplighter: running, jumping, throwing sparks, riding the ashhorn and being knocked about. The game around him (flame, lives, what a hit costs) lives in main.gd.

const World := preload("res://games/ember_trail/world.gd")

const RUN_SPEED := 100.0
const RAM_SPEED := 150.0
const JUMP_SPEED := 310.0
const RAM_JUMP_SPEED := 345.0
const GRAVITY := 880.0
const MAX_FALL := 420.0
const THROW_DELAY := 0.26
const MAX_SPARKS := 3
const FOOT_HW := 5.0
const FOOT_H := 19.0
const RAM_HW := 8.0
const RAM_H := 28.0

var facing := 1
var coyote := 0.0
var jump_buffer := 0.0
var throw_wait := 0.0
var throw_pose := 0.0
var invuln := 0.0
var hurt_time := 0.0
var mounted := false
## Index of the moving platform he stands on, or -1.
var ride := -1
var dead := false
var anim := 0.0
## Where his feet were before this step's fall, for telling a stomp from a collision.
var feet_before := 0.0

func place(at: Vector2) -> void:
	pos = at
	vel = Vector2.ZERO
	facing = 1
	coyote = 0.0
	jump_buffer = 0.0
	throw_wait = 0.0
	throw_pose = 0.0
	invuln = 0.0
	hurt_time = 0.0
	ride = -1
	dead = false
	anim = 0.0
	on_ground = true
	feet_before = at.y
	set_mounted(false)

func set_mounted(value: bool) -> void:
	mounted = value
	hw = RAM_HW if value else FOOT_HW
	h = RAM_H if value else FOOT_H

## Where a thrown spark leaves his hand.
func hand() -> Vector2:
	return pos + Vector2(float(facing) * 7.0, -(h - 8.0))

func centre() -> Vector2:
	return pos + Vector2(0.0, -h * 0.5)

## One step. `game` is main.gd; `control` is false while the player has no say (stage cleared, cut scenes).
func step(game: Node2D, pad: GameInput, delta: float, control: bool) -> void:
	anim += delta
	throw_wait = maxf(0.0, throw_wait - delta)
	throw_pose = maxf(0.0, throw_pose - delta)
	invuln = maxf(0.0, invuln - delta)
	hurt_time = maxf(0.0, hurt_time - delta)
	var world: RefCounted = game.world
	if dead:
		vel.y = minf(vel.y + GRAVITY * delta, MAX_FALL)
		pos += vel * delta
		return
	if ride >= 0 and ride < world.plats.size():
		var plat: Dictionary = world.plats[ride]
		pos.x += float(plat["dx"])
		pos.y = float(plat["y"])
	var want := 0.0
	var steering := control and hurt_time <= 0.0
	if steering and absf(pad.move.x) >= 0.25:
		want = clampf(pad.move.x, -1.0, 1.0)
		facing = 1 if want > 0.0 else -1
	var icy := on_ground and ground_tile == World.ICE
	var grip := 1100.0 if on_ground else 700.0
	if icy:
		grip = 260.0 if want != 0.0 else 130.0
	if hurt_time > 0.0:
		grip = 150.0
	vel.x = move_toward(vel.x, want * (RAM_SPEED if mounted else RUN_SPEED), grip * delta)

	jump_buffer = 0.12 if steering and pad.just_pressed(GameInput.A) else maxf(0.0, jump_buffer - delta)
	if jump_buffer > 0.0 and (on_ground or coyote > 0.0) and steering:
		vel.y = -(RAM_JUMP_SPEED if mounted else JUMP_SPEED)
		jump_buffer = 0.0
		coyote = 0.0
		ride = -1
		on_ground = false
		game.audio.play("ram_jump" if mounted else "jump")
		game.fx.burst(pos, 4, "bc", 26.0, 60.0, 0.3)
	if steering and pad.just_released(GameInput.A) and vel.y < -130.0:
		vel.y = -130.0
	vel.y = minf(vel.y + GRAVITY * delta, MAX_FALL)

	var was_on_ground := on_ground
	var fall_speed := vel.y
	feet_before = pos.y
	world.move_body(self, delta)
	ride = -1
	if not on_ground and vel.y >= 0.0:
		for index in world.plats.size():
			var plat: Dictionary = world.plats[index]
			if pos.x + hw > float(plat["x"]) and pos.x - hw < float(plat["x"]) + float(plat["w"]) and feet_before <= float(plat["y"]) + 2.5 and pos.y >= float(plat["y"]) - 0.01:
				pos.y = float(plat["y"])
				vel.y = 0.0
				on_ground = true
				ground_tile = World.ONEWAY
				ride = index
				break
	if on_ground:
		coyote = 0.1
		if not was_on_ground and fall_speed > 150.0:
			game.fx.burst(pos, 5, "bc", 30.0, 40.0, 0.3)
		if ride < 0:
			# Every crumbling slab under his feet starts to go, not only the one under his middle.
			for tx in range(int(floor((pos.x - hw) / World.TILE)), int(floor((pos.x + hw) / World.TILE)) + 1):
				if world.tile(tx, ground_ty) == World.CRUMBLE and world.touch_crumble(tx, ground_ty):
					game.audio.play("crumble")
	else:
		coyote = maxf(0.0, coyote - delta)

	if steering and throw_wait <= 0.0 and pad.is_down(GameInput.B) and game.shots.size() < MAX_SPARKS:
		throw_wait = THROW_DELAY
		throw_pose = 0.16
		var lob := pad.is_down(GameInput.UP)
		var velocity := Vector2(float(facing) * 130.0, -320.0) if lob else Vector2(float(facing) * 240.0, -60.0)
		velocity.x += vel.x * 0.35
		game.spawn_shot(hand(), velocity, 520.0 if lob else 380.0)

## Take a hit from something at `from_x`. Returns "" when he is safe, "ram" when the ashhorn took it for him, "hit" otherwise.
func take_hit(from_x: float) -> String:
	if invuln > 0.0 or dead:
		return ""
	ride = -1
	on_ground = false
	if mounted:
		set_mounted(false)
		invuln = 1.6
		vel = Vector2(0.0, -230.0)
		return "ram"
	hurt_time = 0.35
	invuln = 1.5
	vel = Vector2(115.0 if pos.x >= from_x else -115.0, -200.0)
	return "hit"

func die() -> void:
	dead = true
	set_mounted(false)
	ride = -1
	vel = Vector2(0.0, -270.0)
