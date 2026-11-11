extends RefCounted

## Presentation only: particles, blast rings, score pop-ups, scorch marks, screen shake, flashes and the weather of each sector. It is fed the simulation's events once per rendered frame and never feeds anything back, so it may use its own randomness and real frame time without touching a run's outcome.

const MAX_PARTICLES := 420
const FIRE := ["f2f4f8", "ffd24a", "e08a1e", "d0403c"]
const SMOKE := ["33364a", "5d6480", "2a2c3c"]
const BRICK := ["e89a62", "c0603a", "8a3f2c", "3d2226"]
const STEEL := ["f2f4f8", "9aa3bd", "5d6480"]

var particles: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var scorches: Array[Dictionary] = []
var weather: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var shake := 0.0
var shake_offset := Vector2.ZERO
var flash := 0.0
var flash_color := Color.WHITE
var time := 0.0
var celebrate := false
var _theme := ""
var _celebrate_t := 0.0
var _field := Vector2(288, 224)
var _dice := RandomNumberGenerator.new()

func _init() -> void:
	_dice.seed = 20261111

func reset(theme: String) -> void:
	particles.clear()
	rings.clear()
	popups.clear()
	scorches.clear()
	shake = 0.0
	flash = 0.0
	celebrate = false
	if theme != _theme:
		_theme = theme
		_make_weather()

## Take in what the simulation reported. Positions arrive in sixteenths of a pixel.
func consume(events: Array[Dictionary]) -> void:
	for event in events:
		var at := Vector2(float(event.get("x", 0)) / 16.0, float(event.get("y", 0)) / 16.0)
		match str(event["t"]):
			"boom":
				var size := int(event.get("size", 1))
				_burst(at, 10 + 8 * size, FIRE, 26.0 + 14.0 * size, 0.5 + 0.12 * size, 2)
				_burst(at, 5 + 4 * size, SMOKE, 12.0 + 5.0 * size, 0.9 + 0.2 * size, 3)
				rings.append({"at": at, "age": 0.0, "span": 0.28 + 0.1 * size, "radius": 9.0 + 7.0 * size, "color": Color("ffd24a")})
				scorches.append({"at": at, "radius": 4 + 2 * size})
				if scorches.size() > 40:
					scorches.pop_front()
				shake = maxf(shake, 1.5 + 1.2 * size)
				if size >= 4:
					flash = 1.0
					flash_color = Color("ffe9b0")
			"spark":
				_burst(at, 5, STEEL, 34.0, 0.22, 1)
			"brick":
				_burst(at, 9 if bool(event.get("broke", false)) else 4, BRICK, 30.0, 0.45, 2)
			"plate":
				_burst(at, 10, STEEL, 36.0, 0.5, 2)
				shake = maxf(shake, 1.5)
			"lay":
				_burst(at, 8, ["9aa3bd", "e89a62", "5d6480"], 16.0, 0.4, 1)
			"muzzle":
				var heading: Vector2 = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][int(event.get("dir", 0))]
				for index in 4:
					_add(at, heading * _dice.randf_range(18.0, 46.0) + Vector2(_dice.randf_range(-12, 12), _dice.randf_range(-12, 12)), 0.14, Color(FIRE[index % 2]), 1)
			"spawn":
				rings.append({"at": at, "age": 0.0, "span": 0.5, "radius": 12.0, "color": Color("5ef2ff")})
			"boss_in":
				rings.append({"at": at, "age": 0.0, "span": 0.9, "radius": 34.0, "color": Color("d0403c")})
				shake = maxf(shake, 4.0)
			"enrage":
				rings.append({"at": at, "age": 0.0, "span": 0.7, "radius": 30.0, "color": Color("ff8a6a")})
				_burst(at, 24, FIRE, 50.0, 0.6, 2)
				flash = 0.6
				flash_color = Color("ff8a6a")
			"chip_drop":
				rings.append({"at": at, "age": 0.0, "span": 0.6, "radius": 14.0, "color": Color("ffd24a")})
			"chip_take":
				rings.append({"at": at, "age": 0.0, "span": 0.5, "radius": 18.0, "color": Color("ffd24a")})
				_burst(at, 14, ["ffd24a", "f2f4f8", "5ef2ff"], 40.0, 0.5, 1)
				popups.append({"at": at + Vector2(0, -16), "age": 0.0, "span": 2.2, "text": "chip_" + str(event.get("kind", ""))})
			"points":
				popups.append({"at": at + Vector2(0, -6), "age": 0.0, "span": 0.9, "text": "+%d" % int(event.get("points", 0))})
			"core_hit":
				rings.append({"at": at, "age": 0.0, "span": 0.7, "radius": 70.0, "color": Color("5ef2ff")})
				_burst(at, 26, ["5ef2ff", "f2f4f8", "d0403c"], 60.0, 0.6, 2)
				flash = 0.8
				flash_color = Color("d0403c")
			"surge":
				rings.append({"at": _field / 2.0, "age": 0.0, "span": 0.7, "radius": 190.0, "color": Color("f2f4f8")})
				flash = 0.9
				flash_color = Color.WHITE
			"shake":
				shake = maxf(shake, float(event.get("amount", 2.0)))
			"won":
				celebrate = true

func update(delta: float) -> void:
	time += delta
	shake = maxf(0.0, shake - delta * 14.0)
	shake_offset = Vector2(roundf(_dice.randf_range(-shake, shake)), roundf(_dice.randf_range(-shake, shake))) if shake > 0.3 else Vector2.ZERO
	flash = maxf(0.0, flash - delta * 3.0)
	for index in range(particles.size() - 1, -1, -1):
		var particle := particles[index]
		particle.age += delta
		if particle.age >= particle.span:
			particles.remove_at(index)
			continue
		particle.at += particle.speed * delta
		particle.speed *= 1.0 - minf(1.0, delta * 3.2)
	for index in range(rings.size() - 1, -1, -1):
		rings[index].age += delta
		if rings[index].age >= rings[index].span:
			rings.remove_at(index)
	for index in range(popups.size() - 1, -1, -1):
		popups[index].age += delta
		if popups[index].age >= popups[index].span:
			popups.remove_at(index)
	for drop in weather:
		drop.at += drop.speed * delta
		if drop.at.x < -4.0:
			drop.at.x += _field.x + 8.0
		elif drop.at.x > _field.x + 4.0:
			drop.at.x -= _field.x + 8.0
		if drop.at.y < -4.0:
			drop.at.y += _field.y + 8.0
		elif drop.at.y > _field.y + 4.0:
			drop.at.y -= _field.y + 8.0
	for cloud in clouds:
		cloud.at.x += cloud.drift * delta
		if cloud.at.x > _field.x + 70.0:
			cloud.at.x = -70.0
			cloud.at.y = _dice.randf_range(10.0, _field.y - 10.0)
	if celebrate:
		_celebrate_t -= delta
		if _celebrate_t <= 0.0:
			_celebrate_t = 0.22
			var at := Vector2(_dice.randf_range(20.0, _field.x - 20.0), _dice.randf_range(20.0, _field.y - 60.0))
			_burst(at, 22, [["5ef2ff", "f2f4f8"], ["ffd24a", "f2f4f8"], ["ff8a6a", "ffd24a"], ["f2a83a", "ffe9a8"]][_dice.randi() % 4], 58.0, 0.9, 2)
			rings.append({"at": at, "age": 0.0, "span": 0.5, "radius": 20.0, "color": Color("f2f4f8")})

func _add(at: Vector2, speed: Vector2, span: float, color: Color, size: int) -> void:
	if particles.size() >= MAX_PARTICLES:
		particles.pop_front()
	particles.append({"at": at, "speed": speed, "age": 0.0, "span": span, "color": color, "size": size})

func _burst(at: Vector2, count: int, colors: Array, reach: float, span: float, size: int) -> void:
	for index in count:
		var heading := Vector2.RIGHT.rotated(_dice.randf() * TAU)
		_add(at + heading * _dice.randf_range(0.0, 3.0), heading * _dice.randf_range(reach * 0.3, reach), span * _dice.randf_range(0.5, 1.0), Color(str(colors[_dice.randi() % colors.size()])), 1 if _dice.randf() < 0.5 else size)

## What drifts over the field in each setting: pollen, rain, dust, snow, fireflies or embers, plus the shadows of slow clouds outdoors.
func _make_weather() -> void:
	weather.clear()
	clouds.clear()
	var count := 46
	for index in count:
		var at := Vector2(_dice.randf() * _field.x, _dice.randf() * _field.y)
		match _theme:
			"marsh":
				weather.append({"at": at, "speed": Vector2(-38.0, 150.0) * _dice.randf_range(0.8, 1.2), "color": Color("8fdccd", 0.5), "size": Vector2(1, 4), "blink": 0.0})
			"pass":
				weather.append({"at": at, "speed": Vector2(_dice.randf_range(30.0, 60.0), _dice.randf_range(-3.0, 3.0)), "color": Color("b9a58c", 0.35), "size": Vector2(3 if index % 3 == 0 else 2, 1), "blink": 0.0})
			"frost":
				weather.append({"at": at, "speed": Vector2(_dice.randf_range(-10.0, 4.0), _dice.randf_range(14.0, 30.0)), "color": Color("eaf3ff", 0.8), "size": Vector2(2, 2) if index % 4 == 0 else Vector2(1, 1), "blink": 0.0})
			"dusk":
				if index < 22:
					weather.append({"at": at, "speed": Vector2(_dice.randf_range(-6.0, 6.0), _dice.randf_range(-6.0, 6.0)), "color": Color("f0ffa6", 0.9), "size": Vector2(1, 1), "blink": _dice.randf_range(1.5, 4.0)})
			"forge":
				weather.append({"at": at, "speed": Vector2(_dice.randf_range(-8.0, 8.0), _dice.randf_range(-36.0, -14.0)), "color": Color("ffc04a" if index % 3 == 0 else "e0561e", 0.85), "size": Vector2(1, 1), "blink": _dice.randf_range(0.0, 3.0)})
			_:
				if index < 26:
					weather.append({"at": at, "speed": Vector2(_dice.randf_range(4.0, 12.0), _dice.randf_range(-4.0, 4.0)), "color": Color("cfe8a8", 0.5), "size": Vector2(1, 1), "blink": _dice.randf_range(0.0, 2.0)})
	if _theme in ["moss", "marsh", "pass", "dusk"]:
		for index in 3:
			var blobs: Array[Rect2] = []
			for part in 5:
				var width := _dice.randf_range(22.0, 44.0)
				blobs.append(Rect2(roundf(_dice.randf_range(-26.0, 26.0) - width / 2.0), roundf(_dice.randf_range(-12.0, 12.0)), roundf(width), roundf(_dice.randf_range(8.0, 16.0))))
			clouds.append({"at": Vector2(_dice.randf() * _field.x, 30.0 + 70.0 * index), "drift": _dice.randf_range(5.0, 10.0), "blobs": blobs})
