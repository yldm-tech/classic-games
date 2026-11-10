class_name ShooterActor
extends Node2D

const ShooterContent := preload("res://runtime/shooter/shooter_content.gd")
signal died(points: int)

const IFRAME_SECS := 0.4

var role := "enemy"
var visual_key := "dog"
var behavior := "static"
var move_speed := 0.0
var target: Node2D
var _age := 0.0
var _origin := Vector2.ZERO
var _color := Color.WHITE
var _shape := "disc"
var hp := 1
var _iframe := 0.0
var _fire_cd := 0.0
var _projectiles_root: Node = null

func configure(p_role: String, key: String, p_behavior: String, speed: float, size: float = 1.0) -> void:
	role = p_role; visual_key = key; behavior = p_behavior; move_speed = speed
	scale = Vector2.ONE * clampf(size, 0.5, 2.0)
	var spec: Array = _spec()
	_color = spec[0]; _shape = spec[1]
	var area := Area2D.new()
	area.name = "HitArea"
	area.monitoring = true
	area.monitorable = true
	area.collision_layer = 4 if role == "enemy" or role == "boss" else 1
	# Player detects enemy bodies (4) and enemy shots (8). Enemies detect player shots (2).
	area.collision_mask = 12 if role == "player" else 2
	area.add_to_group("enemy_hitbox" if role == "enemy" or role == "boss" else "player_hitbox")
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var circle := CircleShape2D.new(); circle.radius = 12.0 if role != "boss" else 28.0
	collision.shape = circle; area.add_child(collision); add_child(area)
	queue_redraw()

func set_projectiles_root(node: Node) -> void:
	_projectiles_root = node

func set_health(value: int) -> void:
	hp = maxi(1, value)
	set_meta("hp", hp)

func take_damage(amount: int) -> void:
	# Dead/queued actors ignore further hits so one kill cannot emit died twice.
	if hp == 0 or is_queued_for_deletion():
		return
	if role == "player":
		if _iframe > 0.0:
			return
		var shields := int(get_meta("shield_hits", 0))
		if shields > 0:
			set_meta("shield_hits", shields - 1)
			_iframe = IFRAME_SECS
			return
	hp = maxi(0, hp - maxi(0, amount))
	set_meta("hp", hp)
	if hp == 0:
		died.emit(100 if role == "enemy" else (0 if role == "player" else 1000))
		if role == "player":
			set_meta("defeated", true)
			return
		queue_free()
	elif role == "player":
		_iframe = IFRAME_SECS

func _ready() -> void:
	_origin = position

func _process(delta: float) -> void:
	_age += delta
	if role == "player":
		_iframe = maxf(0.0, _iframe - delta)
		var axis := _move_axis()
		var boost := 1.65 if bool(get_meta("boost", false)) else 1.0
		position += axis * move_speed * 18.0 * boost * delta
		_apply_incoming_hits()
		return
	match behavior:
		"chase":
			if is_instance_valid(target): position += position.direction_to(target.position) * move_speed * delta
		"sine": position += Vector2(-move_speed, sin(_age * 4.0) * move_speed * .8) * delta
		"dive": position += Vector2(-move_speed * .45, move_speed * 1.4) * delta
		"flock": position += Vector2(-move_speed, sin(_age * 2.0 + get_index()) * move_speed * .35) * delta
		"static": rotation = sin(_age) * .08
	_tick_fire(delta)

func _move_axis() -> Vector2:
	var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var touch := Vector2.ZERO
	var host: Node = self
	while host != null:
		if host.has_meta("touch_move"):
			var raw: Variant = host.get_meta("touch_move")
			if raw is Vector2:
				touch = raw
			break
		host = host.get_parent()
	return (keyboard + touch).limit_length(1.0)

func _apply_incoming_hits() -> void:
	if hp <= 0 or _iframe > 0.0:
		return
	var area := get_node_or_null("HitArea")
	if area == null:
		return
	for other in area.get_overlapping_areas():
		if other == null or not is_instance_valid(other):
			continue
		if other.is_in_group("enemy_hitbox"):
			var actor: Node = other.get_parent()
			take_damage(int(actor.get_meta("contact_damage", 1)) if is_instance_valid(actor) else 1)
			return
		if other.has_meta("damage") and (int(other.collision_layer) & 8) != 0:
			take_damage(int(other.get_meta("damage", 1)))
			other.queue_free()
			return

func _tick_fire(delta: float) -> void:
	var rate := int(get_meta("fire_rate", 0))
	if rate <= 0:
		return
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	_fire_cd = 1.0 / float(rate)
	_fire_enemy_shot()

func _fire_enemy_shot() -> void:
	var host := _projectiles_root if is_instance_valid(_projectiles_root) else get_parent()
	if host == null:
		return
	var shot := Area2D.new()
	shot.name = "EnemyShot"
	shot.monitoring = true
	shot.monitorable = true
	shot.collision_layer = 8
	shot.collision_mask = 1
	var visual := Polygon2D.new()
	visual.color = Color("fb7185")
	visual.polygon = PackedVector2Array([Vector2(7, 0), Vector2(-4, -3), Vector2(-4, 3)])
	shot.add_child(visual)
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	collision.shape = circle
	shot.add_child(collision)
	var aim := Vector2.LEFT
	if is_instance_valid(target):
		aim = global_position.direction_to(target.global_position)
	shot.set_meta("velocity", aim * 220.0)
	shot.set_meta("damage", int(get_meta("shot_damage", 1)))
	shot.set_meta("life", 0.0)
	shot.set_meta("enemy_shot", true)
	shot.set_script(preload("res://runtime/shooter/projectile_motion.gd"))
	host.add_child(shot)
	shot.global_position = global_position

func _spec() -> Array:
	if role == "player": return ShooterContent.PLAYER.get(visual_key, ShooterContent.PLAYER["plane"])
	if role == "boss": return ShooterContent.BOSSES.get(visual_key, ShooterContent.BOSSES["mecha"])
	return ShooterContent.ENEMIES.get(visual_key, ShooterContent.ENEMIES["dog"])

func _draw() -> void:
	var r := 28.0 if role == "boss" else 13.0
	match _shape:
		"triangle": draw_colored_polygon(PackedVector2Array([Vector2(r,0),Vector2(-r*.8,-r*.7),Vector2(-r*.8,r*.7)]), _color)
		"diamond", "wing": draw_colored_polygon(PackedVector2Array([Vector2(r,0),Vector2(0,-r),Vector2(-r,0),Vector2(0,r)]), _color)
		"box", "turret": draw_rect(Rect2(-r*.8,-r*.7,r*1.6,r*1.4), _color, true)
		"disc", "worm": draw_circle(Vector2.ZERO, r, _color)
		"cat":
			draw_circle(Vector2.ZERO, r*.75, _color); draw_colored_polygon(PackedVector2Array([Vector2(-r*.7,-r*.5),Vector2(-r*.5,-r*1.1),Vector2(-r*.1,-r*.65)]),_color); draw_colored_polygon(PackedVector2Array([Vector2(r*.7,-r*.5),Vector2(r*.5,-r*1.1),Vector2(r*.1,-r*.65)]),_color)
		"ghost": draw_circle(Vector2.ZERO,r*.8,_color); draw_rect(Rect2(-r*.8,0,r*1.6,r*.8),_color,true)
		"spike", "tentacle":
			draw_circle(Vector2.ZERO,r*.7,_color)
			for i in 6: draw_line(Vector2.ZERO,Vector2.from_angle(i*TAU/6.0)*r,_color,5)
		_: draw_circle(Vector2.ZERO, r, _color)
