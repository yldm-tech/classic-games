class_name ShooterWorld
extends Node2D

## Live shooter session: combat tick, drop-on-kill, HUD summary, boost/shield.
## Built by ShooterRuntime.build so existing loaders keep the same entry point.

const ShooterActor := preload("res://runtime/shooter/shooter_actor.gd")
const WeaponController := preload("res://runtime/shooter/weapon_controller.gd")
const ShooterContent := preload("res://runtime/shooter/shooter_content.gd")
const BossSkillController := preload("res://runtime/shooter/boss_skill_controller.gd")
const DropItem := preload("res://runtime/shooter/drop_item.gd")
const ProceduralBGM := preload("res://runtime/shooter/procedural_bgm.gd")

var player: Node2D
var weapon_node: Node
var enemy_total := 0
var boss_enabled := false
var drop_table: Array[Dictionary] = []
var _boost := false
var _rng := RandomNumberGenerator.new()

func configure(dsl: Dictionary) -> void:
	name = "ShooterRuntime"
	set_meta("score", 0)
	_rng.randomize()

	var stage: Dictionary = dsl.get("stage", {}) if dsl.get("stage") is Dictionary else {}
	var backdrop := ColorRect.new()
	backdrop.name = "StageBackground"
	backdrop.position = Vector2(-576, -324)
	backdrop.size = Vector2(1152, 648)
	backdrop.color = ShooterContent.BACKGROUNDS.get(str(stage.get("background", "space")), ShooterContent.BACKGROUNDS["space"])
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.show_behind_parent = true
	add_child(backdrop)
	set_meta("background", stage.get("background", "space"))
	set_meta("bgm", stage.get("bgm", ""))
	set_meta("difficulty", clampi(int(stage.get("difficulty", 1)), 1, 5))
	set_meta("duration", clampi(int(stage.get("duration", 90)), 30, 300))
	var music := ProceduralBGM.new(); music.name = "BGM"; music.configure(str(stage.get("bgm", "ignition"))); add_child(music)
	var stage_timer := Timer.new(); stage_timer.name = "StageTimer"; stage_timer.one_shot = true
	stage_timer.wait_time = float(get_meta("duration")); stage_timer.autostart = true
	stage_timer.timeout.connect(func() -> void: set_meta("time_up", true)); add_child(stage_timer)

	var projectiles := Node2D.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)

	var p: Dictionary = dsl.get("player", {}) if dsl.get("player") is Dictionary else {}
	player = ShooterActor.new()
	player.name = "Player"
	player.position = Vector2(-320, 0)
	player.configure("player", str(p.get("sprite", "plane")), "input", float(p.get("speed", 10)), float(p.get("size", 1.0)))
	player.set_health(int(p.get("hp", 100)))
	player.set_meta("speed", float(p.get("speed", 10)))
	player.set_meta("sprite", p.get("sprite", "plane"))
	player.set_projectiles_root(projectiles)
	player.died.connect(_on_player_died)
	var weapon: Variant = p.get("weapon", {})
	var weapon_type: Variant = weapon.get("type", "straight") if weapon is Dictionary else "straight"
	player.set_meta("weapon_type", weapon_type)
	add_child(player)
	var weapon_config: Dictionary = weapon if weapon is Dictionary else {"type": "straight", "damage": 20, "fire_rate": 5}
	weapon_node = WeaponController.new()
	weapon_node.name = "Weapon"
	weapon_node.configure(weapon_config)
	player.add_child(weapon_node)

	var enemies_root := Node2D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	var enemies: Dictionary = dsl.get("enemies", {}) if dsl.get("enemies") is Dictionary else {}
	var difficulty := float(get_meta("difficulty"))
	enemy_total = 0
	for id in enemies:
		if typeof(enemies[id]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = enemies[id]
		var group := Node2D.new()
		group.name = "Group_%s" % str(id)
		group.set_meta("type", e.get("type", ""))
		group.set_meta("behavior", e.get("behavior", ""))
		var cnt := clampi(int(e.get("count", 0)), 0, 200)
		var base_hp := maxi(1, int(e.get("hp", 1)))
		for i in cnt:
			var inst: Node = ShooterActor.new()
			inst.name = "%s_%d" % [str(e.get("type", "enemy")), i]
			inst.position = Vector2(80 + (i % 10) * 42, -220 + (i / 10) * 48)
			inst.configure("enemy", str(e.get("type", "dog")), str(e.get("behavior", "chase")), float(e.get("speed", 5)) * (0.75 + difficulty * 0.25))
			inst.target = player
			inst.set_health(roundi(base_hp * (0.75 + difficulty * 0.25)))
			var fire_rate := int(e.get("fire_rate", 0))
			if str(e.get("type", "")) == "turret" and fire_rate <= 0:
				fire_rate = 2
			inst.set_meta("fire_rate", fire_rate)
			inst.set_meta("contact_damage", derived_damage(base_hp, 8))
			inst.set_meta("shot_damage", derived_damage(base_hp, 8))
			inst.set_projectiles_root(projectiles)
			var actor: Node = inst
			inst.died.connect(func(points: int) -> void:
				var at := Vector2.ZERO
				if is_instance_valid(actor) and actor is Node2D:
					at = (actor as Node2D).global_position
				_on_enemy_died(points, at))
			group.add_child(inst)
		enemy_total += cnt
		enemies_root.add_child(group)
	weapon_node.set_enemies_root(enemies_root)

	var boss: Dictionary = dsl.get("boss", {}) if dsl.get("boss") is Dictionary else {}
	boss_enabled = bool(boss.get("enabled", false))
	if boss_enabled:
		var b: Node = ShooterActor.new()
		b.name = "Boss"
		b.position = Vector2(330, 0)
		b.configure("boss", str(boss.get("sprite", "mecha")), _boss_behavior(str(boss.get("skill", "bullet_hell"))), 28.0, 1.5)
		b.target = player
		b.set_meta("sprite", boss.get("sprite", ""))
		b.set_meta("skill", boss.get("skill", ""))
		var boss_hp := int(boss.get("hp", 1000))
		b.set_health(boss_hp)
		b.set_meta("max_hp", boss_hp)
		b.set_meta("phase_count", clampi(int(boss.get("phase_count", 1)), 1, 3))
		b.set_meta("contact_damage", derived_damage(boss_hp, 25))
		b.set_projectiles_root(projectiles)
		var boss_actor: Node = b
		b.died.connect(func(points: int) -> void:
			var at := Vector2.ZERO
			if is_instance_valid(boss_actor) and boss_actor is Node2D:
				at = (boss_actor as Node2D).global_position
			_on_enemy_died(points, at))
		var skill_controller := BossSkillController.new()
		skill_controller.name = "Skill"
		skill_controller.configure(str(boss.get("skill", "bullet_hell")), derived_damage(boss_hp, 40), enemies_root, player, projectiles)
		b.add_child(skill_controller)
		add_child(b)

	var drops_root := Node2D.new()
	drops_root.name = "Drops"
	add_child(drops_root)
	var drops: Dictionary = dsl.get("drops", {}) if dsl.get("drops") is Dictionary else {}
	drop_table.clear()
	for id in drops:
		if not drops[id] is Dictionary:
			continue
		var drop: Dictionary = drops[id]
		drop_table.append({"id": str(id), "type": str(drop.get("type", "coin")), "rate": clampf(float(drop.get("rate", 0)), 0.0, 1.0)})
	set_meta("drop_count", drop_table.size())

	set_meta("player_sprite", player.get_meta("sprite"))
	set_meta("player_hp", player.get_meta("hp"))
	set_meta("weapon_type", player.get_meta("weapon_type"))
	set_meta("enemy_groups", enemies.size())
	set_meta("enemy_total", enemy_total)
	set_meta("boss_enabled", boss_enabled)
	set_meta("boss_sprite", boss.get("sprite", ""))
	_sync_summary()

func set_boost(on: bool) -> void:
	_boost = on
	if is_instance_valid(player):
		player.set_meta("boost", on)

func grant_shield() -> void:
	if is_instance_valid(player):
		player.set_meta("shield_hits", int(player.get_meta("shield_hits", 0)) + 1)

static func derived_damage(hp: int, divisor: int) -> int:
	return maxi(1, maxi(1, hp) / maxi(1, divisor))

func spawn_drop(kind: String, at: Vector2, rate: float = 1.0) -> Node:
	var drops_root := get_node_or_null("Drops")
	if drops_root == null or not is_instance_valid(player) or weapon_node == null:
		return null
	var item := DropItem.new()
	item.name = "Drop_%s" % kind
	item.configure(kind, rate)
	item.position = at
	item.pickup_entered.connect(func() -> void: item.collect(self, player, weapon_node))
	drops_root.add_child(item)
	return item

func _on_enemy_died(points: int, at: Vector2) -> void:
	var gained := points * (2 if _boost else 1)
	set_meta("score", int(get_meta("score", 0)) + gained)
	_roll_drops(at)
	_sync_summary()

func _on_player_died(_points: int) -> void:
	set_meta("defeated", true)
	_sync_summary()

func _roll_drops(at: Vector2) -> void:
	for spec in drop_table:
		if _rng.randf() <= float(spec.get("rate", 0.0)):
			spawn_drop(str(spec.get("type", "coin")), at, 1.0)

func _process(_delta: float) -> void:
	_sync_summary()

func _sync_summary() -> void:
	var hp := 0
	if is_instance_valid(player):
		hp = int(player.get_meta("hp", 0))
	var defeated := hp <= 0 or bool(get_meta("defeated", false))
	var enemies_left := _living_enemies()
	var boss_alive := has_node("Boss") and is_instance_valid(get_node("Boss")) and not get_node("Boss").is_queued_for_deletion()
	var cleared := (not defeated) and enemies_left == 0 and (not boss_enabled or not boss_alive)
	set_meta("player_hp", hp)
	var time_left := 0
	var timer := get_node_or_null("StageTimer")
	if timer is Timer:
		time_left = maxi(0, ceili((timer as Timer).time_left))
	set_meta("summary", {
		"runtime": "shooter",
		"score": int(get_meta("score", 0)),
		"player_sprite": get_meta("player_sprite", ""),
		"enemy_total": enemy_total,
		"enemy_left": enemies_left,
		"boss_enabled": boss_enabled,
		"duration": int(get_meta("duration", 0)),
		"time_left": time_left,
		"cleared": cleared,
		"defeated": defeated,
	})

func _living_enemies() -> int:
	var enemies := get_node_or_null("Enemies")
	if enemies == null:
		return 0
	var n := 0
	for group in enemies.get_children():
		for enemy in group.get_children():
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				n += 1
	return n

static func _boss_behavior(skill: String) -> String:
	match skill:
		"charge": return "chase"
		"summon_minions": return "flock"
		"laser_sweep": return "static"
		"fireball": return "sine"
		_: return "dive"
