class_name WeaponController
extends Node2D

const ShooterContent := preload("res://runtime/shooter/shooter_content.gd")

var config: Dictionary = {}
var weapon_type := "straight"
var _cooldown := 0.0
var _age := 0.0
var _beam_cd := 0.0
var _orbit_cd := 0.0
var _enemies_root: Node = null  # 由 ShooterRuntime.build 注入,missile 追踪用;未注入时直线飞行不受影响

## Runtime 建好 Enemies 子树后注入,供 missile 追踪最近敌人(headless 测试不注入也不报错,只是不追踪)。
func set_enemies_root(node: Node) -> void:
	_enemies_root = node

func configure(value: Dictionary) -> void:
	config = value.duplicate(true)
	weapon_type = str(config.get("type", "straight"))
	set_meta("mode", ShooterContent.WEAPONS.get(weapon_type, "single"))
	if weapon_type == "laser":
		var beam := Line2D.new(); beam.name = "LaserBeam"; beam.width = float(config.get("width", 1.0)) * 3.0
		beam.default_color = Color("67e8f9"); beam.points = PackedVector2Array([Vector2(12,0),Vector2(360,0)]); add_child(beam)
		var hit := Area2D.new(); hit.name = "LaserHit"
		hit.collision_layer = 2; hit.collision_mask = 4; hit.monitoring = true; hit.monitorable = true
		var shape := CollisionShape2D.new(); var rect := RectangleShape2D.new()
		rect.size = Vector2(348, maxf(8.0, float(config.get("width", 1.0)) * 6.0)); shape.shape = rect; shape.position = Vector2(186, 0)
		hit.add_child(shape); add_child(hit)
	elif weapon_type == "orbit":
		for i in clampi(int(config.get("orbit_count", 1)), 1, 8):
			var orb := Area2D.new(); orb.name = "Orbit_%d" % i
			orb.collision_layer = 2; orb.collision_mask = 4; orb.monitoring = true; orb.monitorable = true
			var visual := Polygon2D.new(); visual.polygon = _disc(6, 8); visual.color = Color("facc15"); orb.add_child(visual)
			var collision := CollisionShape2D.new(); var circle := CircleShape2D.new(); circle.radius = 8.0; collision.shape = circle; orb.add_child(collision)
			orb.set_meta("orbit_index", i); add_child(orb)

func _process(delta: float) -> void:
	_age += delta
	if weapon_type == "orbit":
		var n := get_child_count()
		for i in n: get_child(i).position = Vector2.from_angle(_age * 2.5 + i * TAU / n) * 38.0
		_tick_orbit(delta)
		return
	if weapon_type == "laser":
		_tick_laser(delta)
		return
	_cooldown -= delta
	if _cooldown <= 0:
		_fire()
		_cooldown = 1.0 / maxf(1.0, float(config.get("fire_rate", 4)))
	for child in get_children():
		if child.has_meta("velocity"):
			if bool(child.get_meta("homing", false)): _steer_missile(child, delta)
			elif bool(child.get_meta("returning", false)): _turn_boomerang(child)
			child.position += child.get_meta("velocity") * delta
			child.set_meta("life", float(child.get_meta("life", 0.0)) + delta)
			if float(child.get_meta("life")) > 2.5: child.queue_free()

## missile:每帧朝最近敌人转向,转速受 turn_rate(schema:weapon.turn_rate,0.1~10)限制,速度不变。
func _steer_missile(shot: Node2D, delta: float) -> void:
	var target: Variant = _nearest_enemy_position(shot.global_position)
	if target == null: return
	var velocity: Vector2 = shot.get_meta("velocity")
	var speed := velocity.length()
	if speed <= 0.0: return
	var desired := (target as Vector2) - shot.global_position
	var turn_rate := float(config.get("turn_rate", 3.0))
	var new_angle := rotate_toward(velocity.angle(), desired.angle(), turn_rate * delta)
	shot.set_meta("velocity", Vector2.from_angle(new_angle) * speed)

func _nearest_enemy_position(from: Vector2) -> Variant:
	if _enemies_root == null: return null
	var best_dist := INF
	var best: Vector2 = Vector2.ZERO
	var found := false
	for group in _enemies_root.get_children():
		for enemy in group.get_children():
			if not (enemy is Node2D) or not is_instance_valid(enemy): continue
			var d := from.distance_squared_to((enemy as Node2D).global_position)
			if d < best_dist:
				best_dist = d; best = (enemy as Node2D).global_position; found = true
	return best if found else null

## boomerang:飞出 range(schema:weapon.range,1~20,按像素换算)后原路折返,只转一次向。
func _turn_boomerang(shot: Node2D) -> void:
	if bool(shot.get_meta("turned_back", false)): return
	var origin: Vector2 = shot.get_meta("origin", Vector2.ZERO)
	var range_px := float(config.get("range", 6.0)) * 30.0
	if shot.position.distance_to(origin) >= range_px:
		shot.set_meta("velocity", -(shot.get_meta("velocity") as Vector2))
		shot.set_meta("turned_back", true)

func _fire() -> void:
	var count := clampi(int(config.get("bullet_count", 1)), 1, 12) if weapon_type == "spread" else 1
	for i in count:
		var shot := Area2D.new(); shot.name = "Shot_%s" % weapon_type
		shot.collision_layer = 2; shot.collision_mask = 4
		var visual := Polygon2D.new(); visual.color = Color("fde047")
		visual.polygon = _disc(5, 6) if weapon_type == "missile" else PackedVector2Array([Vector2(9,0),Vector2(-4,-3),Vector2(-4,3)])
		shot.add_child(visual)
		var collision := CollisionShape2D.new(); var circle := CircleShape2D.new(); circle.radius = 5.0; collision.shape = circle; shot.add_child(collision)
		var angle := lerpf(-0.5, 0.5, float(i) / maxf(1.0, count - 1.0)) if count > 1 else 0.0
		shot.set_meta("velocity", Vector2.from_angle(angle) * 260.0)
		shot.set_meta("damage", int(config.get("damage", 1)))
		shot.set_meta("life", 0.0)
		shot.set_meta("origin", shot.position)
		shot.set_meta("homing", weapon_type == "missile")
		shot.set_meta("returning", weapon_type == "boomerang")
		shot.area_entered.connect(func(area: Area2D) -> void:
			var actor := area.get_parent()
			if actor.has_method("take_damage"): actor.take_damage(int(shot.get_meta("damage")))
			if weapon_type != "boomerang": shot.queue_free())
		add_child(shot)

func _tick_laser(delta: float) -> void:
	_beam_cd -= delta
	if _beam_cd > 0.0:
		return
	var hit := get_node_or_null("LaserHit")
	if hit == null:
		return
	var damage := int(config.get("damage", 1))
	for area in hit.get_overlapping_areas():
		var actor: Node = area.get_parent() if area != null else null
		if actor != null and actor.has_method("take_damage"):
			actor.take_damage(damage)
			_beam_cd = 0.12
			return

func _tick_orbit(delta: float) -> void:
	_orbit_cd -= delta
	if _orbit_cd > 0.0:
		return
	var damage := int(config.get("damage", 1))
	for child in get_children():
		if not (child is Area2D):
			continue
		for area in (child as Area2D).get_overlapping_areas():
			var actor: Node = area.get_parent() if area != null else null
			if actor != null and actor.has_method("take_damage"):
				actor.take_damage(damage)
				_orbit_cd = 0.2
				return

func _disc(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides: points.append(Vector2.from_angle(i * TAU / sides) * radius)
	return points
