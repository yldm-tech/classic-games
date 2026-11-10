class_name SurvivorPlay
extends Node2D

var hero: CharacterBody2D
var weapon: Dictionary
var progression: Dictionary
var xp := 0
var level := 1
var kills := 0
var elapsed := 0.0
var attack_count := 0
var pickup_radius := 90.0
var last_upgrade := ""
var _attack_left := 0.0
var _waves: Array[Dictionary] = []
var duration := 180.0

const HERO_COLORS := {"knight":Color("38bdf8"),"mage":Color("a78bfa"),"ranger":Color("4ade80"),"robot":Color("94a3b8"),"witch":Color("f472b6")}
const BACKGROUNDS := {"meadow":Color("14532d"),"crypt":Color("29213f"),"desert":Color("713f12"),"snow":Color("334155"),"volcano":Color("450a0a")}
const ENEMY_SPECS := {
	"slime":{"color":Color("84cc16"),"damage":4,"scale":1.0,"speed":1.0},
	"bat":{"color":Color("c084fc"),"damage":3,"scale":0.75,"speed":1.25},
	"skeleton":{"color":Color("e2e8f0"),"damage":6,"scale":1.0,"speed":0.9},
	"ghost":{"color":Color("67e8f9"),"damage":5,"scale":0.9,"speed":1.1},
	"golem":{"color":Color("fb923c"),"damage":12,"scale":1.5,"speed":0.6},
}

func configure(dsl: Dictionary) -> void:
	var h: Dictionary = dsl.get("hero", {}) if dsl.get("hero") is Dictionary else {}
	# Deep-copied because _apply_upgrade writes back into it: bound by reference, level-ups mutated the caller's DSL and replaying the same game started it already upgraded. The waves below are duplicated for the same reason.
	weapon = (dsl["weapon"] as Dictionary).duplicate(true) if dsl.get("weapon") is Dictionary else {}
	progression = dsl.get("progression", {}) if dsl.get("progression") is Dictionary else {}
	var stage: Dictionary = dsl.get("stage", {}) if dsl.get("stage") is Dictionary else {}
	duration = clampf(float(stage.get("duration", 180)), 30.0, 1800.0)
	var backdrop := ColorRect.new(); backdrop.name = "StageBackground"; backdrop.position = Vector2(-480,-270); backdrop.size = Vector2(960,540); backdrop.color = BACKGROUNDS.get(str(stage.get("background","meadow")),BACKGROUNDS["meadow"]); backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE; backdrop.show_behind_parent = true; add_child(backdrop)
	hero = CharacterBody2D.new(); hero.name = "Hero"
	hero.set_meta("hp", clampi(int(h.get("hp", 100)), 1, 999))
	hero.set_meta("speed", clampf(float(h.get("speed", 240)), 1, 500))
	hero.set_meta("sprite", str(h.get("sprite", "knight")))
	pickup_radius = clampf(float(h.get("pickup_radius", 90)), 10.0, 500.0)
	hero.set_meta("pickup_radius", pickup_radius)
	_add_visual(hero, HERO_COLORS.get(str(h.get("sprite","knight")),HERO_COLORS["knight"]), 16.0)
	var hero_shape := CollisionShape2D.new(); var hero_circle := CircleShape2D.new(); hero_circle.radius = 14.0; hero_shape.shape = hero_circle; hero.add_child(hero_shape)
	add_child(hero)
	var enemies := Node2D.new(); enemies.name = "Enemies"; add_child(enemies)
	var projectiles := Node2D.new(); projectiles.name = "Projectiles"; add_child(projectiles)
	var orbs := Node2D.new(); orbs.name = "XPOrbs"; add_child(orbs)
	for id in dsl.get("waves", {}):
		var raw: Variant = dsl["waves"][id]
		if raw is Dictionary:
			var wave: Dictionary = raw.duplicate(true); wave["id"] = str(id); wave["spawned"] = 0; wave["next"] = float(wave.get("start", 0)); _waves.append(wave)
	set_meta("runtime", "survivor")
	_update_summary()

func _physics_process(delta: float) -> void:
	elapsed += delta
	var direction := _move_axis()
	hero.velocity = direction * float(hero.get_meta("speed")); hero.move_and_slide()
	_spawn_due_enemies()
	_move_enemies(delta)
	_attack_left -= delta
	if _attack_left <= 0.0 and get_node("Enemies").get_child_count() > 0:
		_attack_left = maxf(0.05, float(weapon.get("cooldown", 0.6)))
		auto_attack()
	_move_projectiles(delta)
	_collect_orbs(delta)
	_update_summary()

func _move_axis() -> Vector2:
	var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var touch := Vector2.ZERO
	if has_meta("touch_move"):
		var raw: Variant = get_meta("touch_move")
		if raw is Vector2:
			touch = raw
	return (keyboard + touch).limit_length(1.0)

func _spawn_due_enemies() -> void:
	for wave in _waves:
		var count := clampi(int(wave.get("count", 0)), 0, 300)
		while int(wave["spawned"]) < count and elapsed >= float(wave["next"]):
			var enemy := CharacterBody2D.new(); enemy.name = "%s_%d" % [wave["id"], wave["spawned"]]
			var archetype := str(wave.get("enemy","slime")); var spec: Dictionary = ENEMY_SPECS.get(archetype,ENEMY_SPECS["slime"])
			enemy.set_meta("hp", int(wave.get("hp", 10))); enemy.set_meta("xp", int(wave.get("xp", 1))); enemy.set_meta("archetype",archetype)
			enemy.set_meta("speed", float(wave.get("speed", 70)) * float(spec["speed"])); enemy.set_meta("damage", maxi(1, int(wave.get("damage", spec["damage"])))); enemy.scale = Vector2.ONE * float(spec["scale"])
			_add_visual(enemy, spec["color"], 11.0)
			var angle := float(wave["spawned"]) * 2.39996
			enemy.position = hero.position + Vector2.from_angle(angle) * 420.0
			get_node("Enemies").add_child(enemy)
			wave["spawned"] = int(wave["spawned"]) + 1
			wave["next"] = float(wave["next"]) + maxf(0.05, float(wave.get("interval", 1)))

func auto_attack() -> void:
	attack_count += 1
	var enemies: Array = []
	for enemy in get_node("Enemies").get_children():
		if not enemy.is_queued_for_deletion(): enemies.append(enemy)
	if enemies.is_empty(): return
	var mode := str(weapon.get("type", "magic_bolt")); var base_count := clampi(int(weapon.get("projectiles", 1)), 1, 12)
	var count := base_count; var speed := 520.0; var damage := int(weapon.get("damage", 10)); var radius := 5.0; var color := Color("fde047")
	match mode:
		"axe": count = 1; speed = 300.0; damage = roundi(damage * 1.5); radius = 9.0; color = Color("f97316")
		"whip": count = base_count + 2; speed = 850.0; radius = 4.0; color = Color("e879f9")
		"orbit": count = base_count + 1; speed = 220.0; damage = roundi(damage * 1.25); radius = 7.0; color = Color("a78bfa")
		"flame": count = base_count * 2; speed = 420.0; damage = maxi(1, roundi(damage * 0.7)); radius = 6.0; color = Color("fb7185")
	count = mini(enemies.size(), count)
	for i in count:
		var target: Node2D = enemies[i]
		var projectile := Node2D.new(); projectile.name = "Projectile_%d" % attack_count; projectile.position = hero.position
		projectile.set_meta("target", target); projectile.set_meta("damage", damage); projectile.set_meta("speed", speed); projectile.set_meta("mode", mode)
		_add_visual(projectile, color, radius); get_node("Projectiles").add_child(projectile)

func _move_enemies(delta: float) -> void:
	for enemy: Node2D in get_node("Enemies").get_children():
		if enemy.is_queued_for_deletion(): continue
		enemy.position = enemy.position.move_toward(hero.position, float(enemy.get_meta("speed", 70)) * delta)
		if enemy.position.distance_to(hero.position) <= 22.0:
			hero.set_meta("hp", maxi(0, int(hero.get_meta("hp")) - int(enemy.get_meta("damage", 5))))
			_spawn_orb(enemy.position, int(enemy.get_meta("xp", 1)))
			kills += 1
			enemy.queue_free()

func _move_projectiles(delta: float) -> void:
	for projectile: Node2D in get_node("Projectiles").get_children():
		var target: Variant = projectile.get_meta("target")
		if not is_instance_valid(target) or target.is_queued_for_deletion(): projectile.queue_free(); continue
		var step := float(projectile.get_meta("speed", 520)) * delta
		projectile.position = projectile.position.move_toward(target.position, step)
		if projectile.position.distance_to(target.position) <= maxf(6.0, step):
			_damage_enemy(target, int(projectile.get_meta("damage", 10))); projectile.queue_free()

func _damage_enemy(enemy: Node2D, damage: int) -> void:
	enemy.set_meta("hp", int(enemy.get_meta("hp")) - maxi(0, damage))
	if int(enemy.get_meta("hp")) <= 0:
		_spawn_orb(enemy.position, int(enemy.get_meta("xp", 1)))
		enemy.queue_free()
		kills += 1

func _spawn_orb(at: Vector2, amount: int) -> void:
	var orbs := get_node_or_null("XPOrbs")
	if orbs == null:
		return
	var orb := Node2D.new()
	orb.name = "XPOrb"
	orb.position = at
	orb.set_meta("xp", maxi(1, amount))
	_add_visual(orb, Color("fde047"), 6.0)
	orbs.add_child(orb)

func _collect_orbs(delta: float) -> void:
	var orbs := get_node_or_null("XPOrbs")
	if orbs == null or not is_instance_valid(hero):
		return
	for orb in orbs.get_children():
		if orb.is_queued_for_deletion() or not (orb is Node2D):
			continue
		var node := orb as Node2D
		var dist: float = node.position.distance_to(hero.position)
		if dist <= pickup_radius:
			node.position = node.position.move_toward(hero.position, 420.0 * delta)
		if node.position.distance_to(hero.position) <= 16.0:
			gain_xp(int(node.get_meta("xp", 1)))
			node.queue_free()

func _add_visual(node: Node2D, color: Color, radius: float) -> void:
	var visual := Polygon2D.new(); visual.name = "Visual"; visual.color = color
	var points := PackedVector2Array(); for i in 8: points.append(Vector2.from_angle(i * TAU / 8.0) * radius)
	visual.polygon = points; node.add_child(visual)

func gain_xp(amount: int) -> void:
	xp += maxi(0, amount)
	var needed := maxi(1, roundi(float(progression.get("xp_base", 20)) * pow(float(progression.get("xp_growth", 1.5)), level - 1)))
	while xp >= needed:
		xp -= needed; level += 1; _apply_upgrade(level - 2)
		needed = maxi(1, roundi(float(progression.get("xp_base", 20)) * pow(float(progression.get("xp_growth", 1.5)), level - 1)))
	_update_summary()

func _apply_upgrade(index: int) -> void:
	var upgrades: Array = progression.get("upgrades", []) if progression.get("upgrades") is Array else []
	if upgrades.is_empty(): return
	last_upgrade = str(upgrades[index % upgrades.size()])
	set_meta("last_upgrade", last_upgrade)
	match last_upgrade:
		"damage": weapon["damage"] = roundi(float(weapon.get("damage", 10)) * 1.25)
		"haste": weapon["cooldown"] = maxf(0.05, float(weapon.get("cooldown", 0.6)) * 0.85)
		"projectiles": weapon["projectiles"] = mini(12, int(weapon.get("projectiles", 1)) + 1)
		"speed": hero.set_meta("speed", float(hero.get_meta("speed")) * 1.1)

func _update_summary() -> void:
	var defeated := int(hero.get_meta("hp", 0)) <= 0
	var cleared := elapsed >= duration and not defeated
	set_meta("time_up", elapsed >= duration)
	set_meta("summary", {"runtime":"survivor", "score":kills * 10, "kills":kills, "level":level, "xp":xp, "elapsed":elapsed, "duration":duration, "attack_count":attack_count, "wave_count":_waves.size(), "enemy_active":get_node_or_null("Enemies").get_child_count() if get_node_or_null("Enemies") else 0, "last_upgrade":last_upgrade, "cleared":cleared, "defeated":defeated})
