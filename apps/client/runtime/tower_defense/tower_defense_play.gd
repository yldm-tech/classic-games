class_name TowerDefensePlay
extends Node2D

var gold := 0
var base_hp := 1
var kills := 0
var elapsed := 0.0
var _path: PackedVector2Array = []
var _tower_types: Dictionary = {}
var _waves: Array[Dictionary] = []

const BACKGROUNDS := {"grassland":Color("14532d"),"desert":Color("713f12"),"snow":Color("334155"),"volcano":Color("450a0a"),"moon":Color("172554")}
const ENEMY_SPECS := {
	"grunt":{"color":Color("fb7185"),"armor":0,"base_damage":1,"scale":1.0,"speed":1.0},
	"runner":{"color":Color("fde047"),"armor":0,"base_damage":1,"scale":0.8,"speed":1.4},
	"tank":{"color":Color("94a3b8"),"armor":3,"base_damage":2,"scale":1.3,"speed":0.7},
	"flyer":{"color":Color("67e8f9"),"armor":1,"base_damage":1,"scale":0.75,"speed":1.15},
	"boss":{"color":Color("c084fc"),"armor":5,"base_damage":5,"scale":1.8,"speed":0.6},
}

func configure(dsl: Dictionary) -> void:
	var stage: Dictionary = dsl.get("stage", {}) if dsl.get("stage") is Dictionary else {}
	gold = clampi(int(stage.get("starting_gold", 100)), 0, 99999)
	base_hp = clampi(int(stage.get("base_hp", 20)), 1, 999)
	var backdrop := ColorRect.new(); backdrop.name = "StageBackground"; backdrop.position = Vector2(-480,-270); backdrop.size = Vector2(960,540); backdrop.color = BACKGROUNDS.get(str(stage.get("background","grassland")),BACKGROUNDS["grassland"]); backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE; backdrop.show_behind_parent = true; add_child(backdrop)
	var path_data: Dictionary = dsl.get("path", {}) if dsl.get("path") is Dictionary else {}
	for raw in path_data.get("points", []):
		if raw is Array and raw.size() == 2: _path.append(Vector2(float(raw[0]), float(raw[1])))
	var path_visual := Line2D.new(); path_visual.name = "PathVisual"; path_visual.width = 18.0; path_visual.default_color = Color("64748b"); path_visual.points = _path; add_child(path_visual)
	var anchor := Node2D.new(); anchor.name = "Player"; anchor.position = _path[0] if _path.size() > 0 else Vector2.ZERO; add_child(anchor)
	_tower_types = dsl.get("towers", {}) if dsl.get("towers") is Dictionary else {}
	var enemies := Node2D.new(); enemies.name = "Enemies"; add_child(enemies)
	var towers := Node2D.new(); towers.name = "Towers"; add_child(towers)
	var projectiles := Node2D.new(); projectiles.name = "Projectiles"; add_child(projectiles)
	var placements: Dictionary = dsl.get("placements", {}) if dsl.get("placements") is Dictionary else {}
	for id in placements:
		if placements[id] is Dictionary: place_tower(str(id), placements[id])
	var waves: Dictionary = dsl.get("waves", {}) if dsl.get("waves") is Dictionary else {}
	for id in waves:
		if waves[id] is Dictionary:
			var wave: Dictionary = waves[id].duplicate(true); wave["id"] = str(id); wave["spawned"] = 0; wave["next"] = float(wave.get("start", 0)); _waves.append(wave)
	set_meta("runtime", "tower_defense"); _update_summary()

func tower_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id in _tower_types:
		ids.append(str(id))
	return ids

func place_tower(id: String, placement: Dictionary) -> bool:
	var type_id := str(placement.get("tower", ""))
	if not _tower_types.has(type_id) or not _tower_types[type_id] is Dictionary: return false
	var config: Dictionary = _tower_types[type_id]
	var cost := maxi(0, int(config.get("cost", 0)))
	if gold < cost: return false
	var pos: Array = placement.get("position", []) if placement.get("position") is Array else []
	if pos.size() != 2: return false
	if get_node_or_null("Towers") and get_node("Towers").has_node(id):
		id = "%s_%d" % [id, Time.get_ticks_msec()]
	var tower := Node2D.new(); tower.name = id; tower.position = Vector2(float(pos[0]), float(pos[1]))
	tower.set_meta("config", config.duplicate(true)); tower.set_meta("cooldown_left", 0.0)
	var tower_color: Color = {"arrow":Color("38bdf8"),"cannon":Color("f97316"),"frost":Color("67e8f9"),"laser":Color("f43f5e"),"tesla":Color("a78bfa")}.get(str(config.get("type","arrow")),Color("38bdf8"))
	_add_visual(tower, tower_color, 15.0)
	get_node("Towers").add_child(tower); gold -= cost; _update_summary(); return true

func _physics_process(delta: float) -> void:
	elapsed += delta; spawn_due_enemies(); _move_enemies(delta); fire_towers(delta); resolve_projectiles(delta); _update_summary()

func spawn_due_enemies() -> void:
	if _path.size() < 2: return
	for wave in _waves:
		var count := clampi(int(wave.get("count", 0)), 0, 300)
		while int(wave["spawned"]) < count and elapsed >= float(wave["next"]):
			var enemy := Node2D.new(); enemy.name = "%s_%d" % [wave["id"], wave["spawned"]]; enemy.position = _path[0]
			var archetype := str(wave.get("enemy","grunt")); var spec: Dictionary = ENEMY_SPECS.get(archetype,ENEMY_SPECS["grunt"])
			enemy.set_meta("hp", int(wave.get("hp", 10))); enemy.set_meta("speed", float(wave.get("speed", 50)) * float(spec["speed"])); enemy.set_meta("reward", int(wave.get("reward", 1))); enemy.set_meta("path_index", mini(2,_path.size()-1) if archetype=="flyer" else 1); enemy.set_meta("armor",int(spec["armor"])); enemy.set_meta("base_damage",int(spec["base_damage"])); enemy.set_meta("archetype",archetype); enemy.scale = Vector2.ONE * float(spec["scale"])
			_add_visual(enemy, spec["color"], 10.0)
			get_node("Enemies").add_child(enemy); wave["spawned"] = int(wave["spawned"]) + 1; wave["next"] = float(wave["next"]) + maxf(0.05, float(wave.get("interval", 1)))

func _move_enemies(delta: float) -> void:
	for enemy: Node2D in get_node("Enemies").get_children():
		var index := int(enemy.get_meta("path_index"))
		if index >= _path.size(): enemy.queue_free(); damage_base(int(enemy.get_meta("base_damage",1))); continue
		var target := _path[index]; enemy.position = enemy.position.move_toward(target, float(enemy.get_meta("speed")) * delta)
		if enemy.position.is_equal_approx(target): enemy.set_meta("path_index", index + 1)

func fire_towers(delta: float) -> void:
	for tower: Node2D in get_node("Towers").get_children():
		var left := float(tower.get_meta("cooldown_left")) - delta; tower.set_meta("cooldown_left", left)
		if left > 0: continue
		var config: Dictionary = tower.get_meta("config"); var target := _nearest_enemy(tower.position, float(config.get("range", 100)))
		if target == null: continue
		var effect := str(config.get("type", "arrow")); var projectile_speed := 900.0 if effect == "laser" else 340.0 if effect == "cannon" else 420.0
		var projectile := Node2D.new(); projectile.name = "Projectile"; projectile.position = tower.position; projectile.set_meta("target", target); projectile.set_meta("damage", int(config.get("damage", 1))); projectile.set_meta("speed", projectile_speed); projectile.set_meta("effect", effect); _add_visual(projectile, Color("fde047"), 7.0 if effect == "cannon" else 5.0); get_node("Projectiles").add_child(projectile)
		tower.set_meta("cooldown_left", maxf(0.05, float(config.get("cooldown", 1))))

func resolve_projectiles(delta: float = -1.0) -> void:
	for projectile in get_node("Projectiles").get_children():
		var target: Variant = projectile.get_meta("target")
		if is_instance_valid(target) and not target.is_queued_for_deletion():
			if delta >= 0.0:
				var step := float(projectile.get_meta("speed", 420)) * delta; projectile.position = projectile.position.move_toward(target.position, step)
				if projectile.position.distance_to(target.position) > maxf(6.0, step): continue
			var damage := int(projectile.get_meta("damage")); var effect := str(projectile.get_meta("effect", "arrow"))
			_hit_enemy(target, damage)
			if effect == "frost" and is_instance_valid(target) and not target.is_queued_for_deletion(): target.set_meta("speed", float(target.get_meta("speed")) * 0.65); target.set_meta("slowed", true)
			if effect == "cannon":
				for other: Node2D in get_node("Enemies").get_children():
					if other != target and not other.is_queued_for_deletion() and other.position.distance_to(target.position) <= 100.0: _hit_enemy(other, maxi(1, damage / 2))
			if effect == "tesla":
				var chained := 0
				for other: Node2D in get_node("Enemies").get_children():
					if other != target and not other.is_queued_for_deletion() and chained < 2: _hit_enemy(other, maxi(1, damage / 2)); chained += 1
		projectile.queue_free()
	_update_summary()

func _hit_enemy(enemy: Node2D, damage: int) -> void:
	var effective := maxi(1, damage - int(enemy.get_meta("armor",0)))
	enemy.set_meta("hp", int(enemy.get_meta("hp")) - effective)
	if int(enemy.get_meta("hp")) <= 0 and not enemy.is_queued_for_deletion(): gold += int(enemy.get_meta("reward")); kills += 1; enemy.queue_free()

func _add_visual(node: Node2D, color: Color, radius: float) -> void:
	var visual := Polygon2D.new(); visual.name = "Visual"; visual.color = color
	var points := PackedVector2Array(); for i in 6: points.append(Vector2.from_angle(i * TAU / 6.0) * radius)
	visual.polygon = points; node.add_child(visual)

func _nearest_enemy(origin: Vector2, attack_range: float) -> Node2D:
	var best: Node2D = null; var best_distance := attack_range
	for enemy: Node2D in get_node("Enemies").get_children():
		if enemy.is_queued_for_deletion(): continue
		var distance := origin.distance_to(enemy.position)
		if distance <= best_distance: best = enemy; best_distance = distance
	return best

func damage_base(amount: int) -> void:
	base_hp = maxi(0, base_hp - maxi(0, amount)); set_meta("defeated", base_hp == 0); _update_summary()

func _update_summary() -> void:
	var active := 0
	if get_node_or_null("Enemies"):
		for enemy in get_node("Enemies").get_children():
			if not enemy.is_queued_for_deletion(): active += 1
	var all_spawned := not _waves.is_empty()
	for wave in _waves:
		if int(wave.get("spawned", 0)) < int(wave.get("count", 0)): all_spawned = false
	var defeated := base_hp == 0
	var cleared := all_spawned and active == 0 and not defeated
	set_meta("defeated", defeated); set_meta("cleared", cleared)
	set_meta("summary", {"runtime":"tower_defense","score":kills * 100 + gold,"kills":kills,"gold":gold,"base_hp":base_hp,"elapsed":elapsed,"wave_count":_waves.size(),"current_wave":_current_wave(),"enemy_active":active,"cleared":cleared,"defeated":defeated})

func _current_wave() -> int:
	var started := 0
	for wave in _waves:
		if int(wave.get("spawned", 0)) > 0 or elapsed >= float(wave.get("start", 0)):
			started += 1
	return started
