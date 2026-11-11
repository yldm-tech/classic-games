extends RefCounted

## Particles and floating score text. They are stepped with the simulation but draw their randomness from their own generator, so nothing here can change how a run plays out.

const Rng := preload("res://games/shared/game_rng.gd")
const MAX_PARTICLES := 260

var particles: Array = []
var popups: Array = []
var rng: GameRng = Rng.new(2024)

func reset() -> void:
	particles.clear()
	popups.clear()
	rng.reseed(2024)

## Throw `count` square particles out of `at`. `keys` are palette characters, picked at random.
func burst(at: Vector2, count: int, keys: String, speed: float, gravity: float = 260.0, life: float = 0.5, up: float = 0.0) -> void:
	for index in count:
		if particles.size() >= MAX_PARTICLES:
			return
		var angle := rng.float_range(0.0, TAU)
		var velocity := Vector2(cos(angle), sin(angle)) * rng.float_range(speed * 0.3, speed)
		velocity.y -= up
		var lifetime := rng.float_range(life * 0.6, life)
		particles.append({"pos": at, "vel": velocity, "life": lifetime, "max": lifetime, "key": keys[rng.int_range(0, keys.length() - 1)], "gravity": gravity, "size": 2 if rng.chance(0.35) else 1})

## One particle with a given velocity (trails, drips, sparks).
func puff(at: Vector2, velocity: Vector2, key: String, life: float, gravity: float = 0.0, size: int = 1) -> void:
	if particles.size() < MAX_PARTICLES:
		particles.append({"pos": at, "vel": velocity, "life": life, "max": life, "key": key, "gravity": gravity, "size": size})

func popup(at: Vector2, text: String, key: String = "8") -> void:
	popups.append({"pos": at, "text": text, "t": 0.0, "key": key})

func step(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			particles.remove_at(index)
			continue
		var velocity: Vector2 = particle["vel"]
		velocity.y += float(particle["gravity"]) * delta
		particle["vel"] = velocity
		particle["pos"] = (particle["pos"] as Vector2) + velocity * delta
	for index in range(popups.size() - 1, -1, -1):
		var note: Dictionary = popups[index]
		note["t"] = float(note["t"]) + delta
		note["pos"] = (note["pos"] as Vector2) + Vector2(0.0, -22.0 * delta)
		if float(note["t"]) > 0.9:
			popups.remove_at(index)
