class_name BossSkillController
extends Node2D

const ShooterActor := preload("res://runtime/shooter/shooter_actor.gd")
const ProjectileMotion := preload("res://runtime/shooter/projectile_motion.gd")

var skill := "fireball"
var shot_damage := 10
var _age := 0.0
var _cooldown := 0.0
var _charge_left := 0.0
var _enemies_root: Node = null
var _player: Node2D = null
var _projectiles_root: Node = null
var _laser_area: Area2D = null
var _laser_tick := 0.0

func configure(value: String, p_damage: int = 10, p_enemies_root: Node = null, p_player: Node2D = null, p_projectiles: Node = null) -> void:
	skill = value
	shot_damage = maxi(1, p_damage)
	_enemies_root = p_enemies_root
	_player = p_player
	_projectiles_root = p_projectiles
	set_meta("skill_mode", value)
	if skill == "laser_sweep":
		var beam := Line2D.new(); beam.name = "SweepBeam"; beam.width = 7; beam.default_color = Color("fb7185")
		beam.points = PackedVector2Array([Vector2.ZERO, Vector2(-420, 0)]); add_child(beam)
		_laser_area = Area2D.new()
		_laser_area.name = "SweepHit"
		_laser_area.collision_layer = 8
		_laser_area.collision_mask = 1
		_laser_area.monitoring = true
		_laser_area.monitorable = true
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(420, 10)
		shape.shape = rect
		shape.position = Vector2(-210, 0)
		_laser_area.add_child(shape)
		add_child(_laser_area)
	elif skill == "charge":
		var warning := Line2D.new(); warning.name = "ChargeWarning"; warning.width = 3; warning.default_color = Color("f97316")
		warning.points = PackedVector2Array([Vector2.ZERO, Vector2(-300, 0)]); add_child(warning)

func _process(delta: float) -> void:
	_age += delta
	_cooldown -= delta
	if skill == "laser_sweep":
		rotation = sin(_age) * 0.9
		_tick_laser(delta)
		return
	if skill == "charge":
		_tick_charge(delta)
		if _cooldown <= 0.0:
			activate()
			_cooldown = _phase_cooldown()
		return
	if _cooldown <= 0.0:
		activate()
		_cooldown = _phase_cooldown()

func activate() -> void:
	match skill:
		"fireball":
			_spawn_bullet(Vector2.LEFT * 180.0, Color("fb923c"), shot_damage)
		"bullet_hell":
			var count := 12 * _phase()
			for i in count:
				_spawn_bullet(Vector2.from_angle(i * TAU / float(count)) * (110.0 + 20.0 * _phase()), Color("f43f5e"), shot_damage)
		"summon_minions":
			_summon()
		"charge":
			set_meta("charging", true)
			_charge_left = 0.85

func _phase() -> int:
	var boss := get_parent()
	if boss == null:
		return 1
	var phases := maxi(1, int(boss.get_meta("phase_count", 1)))
	var max_hp := maxi(1, int(boss.get_meta("max_hp", int(boss.get_meta("hp", 1)))))
	var hp := maxi(0, int(boss.get_meta("hp", 0)))
	var lost := 1.0 - float(hp) / float(max_hp)
	return clampi(1 + int(floor(lost * float(phases))), 1, phases)

func _phase_cooldown() -> float:
	return 2.0 / float(_phase())

func _tick_charge(delta: float) -> void:
	if not bool(get_meta("charging", false)):
		return
	_charge_left -= delta
	var boss := get_parent()
	if boss is Node2D and is_instance_valid(_player):
		(boss as Node2D).position += (boss as Node2D).position.direction_to(_player.position) * 260.0 * delta
	if _charge_left <= 0.0:
		set_meta("charging", false)

func _tick_laser(delta: float) -> void:
	if _laser_area == null:
		return
	_laser_tick -= delta
	if _laser_tick > 0.0:
		return
	for other in _laser_area.get_overlapping_areas():
		if other != null and other.is_in_group("player_hitbox"):
			var actor: Node = other.get_parent()
			if actor != null and actor.has_method("take_damage"):
				actor.take_damage(shot_damage)
				_laser_tick = 0.35 / float(_phase())
				return

func _summon() -> void:
	var host := _enemies_root if is_instance_valid(_enemies_root) else self
	var group := host
	if host != self:
		group = host.get_node_or_null("Group_summoned")
		if group == null:
			group = Node2D.new()
			group.name = "Group_summoned"
			host.add_child(group)
	for i in 3:
		var minion: Node = ShooterActor.new()
		minion.name = "SummonedMinion_%d" % i
		minion.configure("enemy", "swarm", "chase", 14.0)
		minion.position = (get_parent() as Node2D).position + Vector2(-40, (i - 1) * 28) if get_parent() is Node2D else Vector2(-35, (i - 1) * 24)
		minion.target = _player
		minion.set_health(8)
		minion.set_meta("contact_damage", 2)
		minion.set_meta("fire_rate", 0)
		if is_instance_valid(_projectiles_root) and minion.has_method("set_projectiles_root"):
			minion.set_projectiles_root(_projectiles_root)
		var spawned: Node = minion
		var world = _projectiles_root.get_parent() if is_instance_valid(_projectiles_root) else null
		if world != null and world.has_method("_on_enemy_died"):
			spawned.died.connect(func(points: int) -> void:
				var at := Vector2.ZERO
				if is_instance_valid(spawned) and spawned is Node2D:
					at = (spawned as Node2D).global_position
				world._on_enemy_died(points, at))
		group.add_child(minion)

func _spawn_bullet(velocity: Vector2, color: Color, damage: int) -> void:
	var host := _projectiles_root if is_instance_valid(_projectiles_root) else self
	var shot := Area2D.new()
	shot.name = "BossProjectile"
	shot.monitoring = true
	shot.monitorable = true
	shot.collision_layer = 8
	shot.collision_mask = 1
	var visual := Polygon2D.new()
	visual.color = color
	visual.polygon = PackedVector2Array([Vector2(7, 0), Vector2(0, -7), Vector2(-7, 0), Vector2(0, 7)])
	shot.add_child(visual)
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	collision.shape = circle
	shot.add_child(collision)
	shot.set_meta("velocity", velocity)
	shot.set_meta("damage", damage)
	shot.set_meta("life", 0.0)
	shot.set_script(ProjectileMotion)
	host.add_child(shot)
	if get_parent() is Node2D:
		shot.global_position = (get_parent() as Node2D).global_position
