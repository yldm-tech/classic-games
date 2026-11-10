extends SceneTree

const GameSessionScript := preload("res://runtime/game_session.gd")
const JsonPatch := preload("res://runtime/json_patch.gd")
const ShooterRuntime := preload("res://runtime/shooter/shooter_runtime.gd")
const ShooterPlay := preload("res://runtime/shooter/shooter_play.gd")
const I18n := preload("res://i18n/i18n.gd")
const VirtualWindow := preload("res://shell/design_system/components/virtual_window.gd")
const CreatorSession := preload("res://shell/creator_session.gd")
const QrCode := preload("res://vendor/qrcode/qr_code.gd")
const PlatformBridge := preload("res://platform/platform.gd")
const ShooterContent := preload("res://runtime/shooter/shooter_content.gd")
const WeaponController := preload("res://runtime/shooter/weapon_controller.gd")
const BossSkillController := preload("res://runtime/shooter/boss_skill_controller.gd")
const DropItem := preload("res://runtime/shooter/drop_item.gd")
const NetworkMatchSession := preload("res://runtime/network_match_session.gd")
const NetworkMatchRuntime := preload("res://runtime/network_match_runtime.gd")
const DesktopIntegration := preload("res://platform/desktop_integration.gd")

# 与服务端 patch_test.go 共用的 Fork 补丁链。
# 用 JSON 字符串而非 GDScript 字面量:生产里补丁是 JSON 过线的,经 JSON.parse 后数字类型
# 才与 golden(同样 JSON.parse)一致——否则字面量 int 10 与 JSON 的 10 类型可能不同,整树比对会假阴。
const FORK_PATCH_JSON := """[
	{"op": "replace", "path": "/player/sprite", "value": "cat"},
	{"op": "add", "path": "/enemies/bird_1",
		"value": {"type": "bird", "behavior": "sine", "count": 10, "hp": 15, "speed": 12}},
	{"op": "replace", "path": "/enemies/dog_1/count", "value": 30},
	{"op": "remove", "path": "/enemies/turret_1"}
]"""

## Phase 0 spike 自测:headless 跑通版本治理 + Fork 补丁链(6902, map 寻址)+ GameSession 信号边界。
## 运行:godot --headless --path apps/client --script res://spike_test.gd
## 全过 exit 0,否则 exit 1。这是 docs/07-roadmap.md 中 spike 的「最简游戏 + GameSession 边界 / RuntimeLoader」两项的可执行验证。

var _passed := 0
var _failed := 0

func _initialize() -> void:
	var baseline := _load_baseline()
	if baseline.is_empty():
		push_error("无法加载 baseline DSL")
		quit(1)
		return
	var fork_patch: Array = JSON.parse_string(FORK_PATCH_JSON)

	var gs := GameSessionScript.new()
	root.add_child(gs)

	# 用 Dictionary(引用类型)收集信号:GDScript lambda 按值捕获,直接赋值外层变量不生效。
	var bus := {"ended": {}, "error": {}}
	gs.game_ended.connect(func(r): bus["ended"] = r)
	gs.game_error.connect(func(e): bus["error"] = e)

	# A. 直传基线 DSL → 应正常结束
	bus["ended"] = {}; bus["error"] = {}
	gs.start_game({"runtime": "shooter@1.0.0", "mod": baseline})
	_check("A 基线加载成功", not bus["ended"].is_empty() and bus["error"].is_empty())
	_check("A 玩家 sprite=plane", bus["ended"].get("player_sprite") == "plane")
	_check("A 敌人总数=24", bus["ended"].get("enemy_total") == 24)

	# B. 版本不兼容(major 不同)→ 应 game_error RUNTIME_VERSION_MISMATCH
	bus["ended"] = {}; bus["error"] = {}
	gs.start_game({"runtime": "shooter@2.0.0", "mod": baseline})
	_check("B 版本不兼容被拦截", bus["ended"].is_empty() and not bus["error"].is_empty())
	_check("B 错误码正确", bus["error"].get("code") == "RUNTIME_VERSION_MISMATCH")

	# B2. 同 major 应兼容(防 _version_compatible 退化成全等比较把合法 1.x mod 误杀)
	bus["ended"] = {}; bus["error"] = {}
	gs.start_game({"runtime": "shooter@1.5.0", "mod": baseline})
	_check("B2 同 major(1.5.0)兼容加载", not bus["ended"].is_empty() and bus["error"].is_empty())

	# B3. 未知 runtime → UNKNOWN_RUNTIME
	bus["ended"] = {}; bus["error"] = {}
	gs.start_game({"runtime": "racing@1.0.0", "mod": baseline})
	_check("B3 未知 runtime 被拦截", bus["error"].get("code") == "UNKNOWN_RUNTIME")

	# Survivor 是独立 Runtime：波次、自动攻击和经验升级均由自己的实现驱动。
	var survivor := _load_json("res://runtime/survivor/baseline.dsl.json")
	var survivor_loader := preload("res://runtime/runtime_loader.gd").new()
	var survivor_run := survivor_loader.load_from_dsl("survivor@1.0.0", survivor)
	_check("B3.1 Survivor 独立加载", survivor_run != null and survivor_run.name == "SurvivorRuntime" and survivor_run.get_meta("runtime") == "survivor")
	root.add_child(survivor_run)
	survivor_run.elapsed = 2.5; survivor_run._spawn_due_enemies()
	_check("B3.2 Survivor 波次真实生成", survivor_run.get_node("Enemies").get_child_count() >= 2)
	_check("B3.2.1 Survivor 角色与敌人可见", survivor_run.hero.find_child("Visual", true, false) is Polygon2D and survivor_run.get_node("Enemies").get_child(0).find_child("Visual", true, false) is Polygon2D)
	var chasing_enemy: Node2D = survivor_run.get_node("Enemies").get_child(0); var distance_before := chasing_enemy.position.distance_to(survivor_run.hero.position); survivor_run._move_enemies(0.5)
	_check("B3.2.2 Survivor 敌人真实追击", chasing_enemy.position.distance_to(survivor_run.hero.position) < distance_before)
	var hp_before_contact := int(survivor_run.hero.get_meta("hp")); chasing_enemy.position = survivor_run.hero.position + Vector2(5,0); survivor_run._move_enemies(0.1)
	_check("B3.2.3 Survivor 接触伤害真实扣血", int(survivor_run.hero.get_meta("hp")) < hp_before_contact)
	survivor_run.set_meta("touch_move", Vector2.RIGHT)
	_check("B3.2.4 Survivor 触控方向合成", survivor_run._move_axis() == Vector2.RIGHT)
	survivor_run.set_meta("touch_move", Vector2.ZERO)
	_check("B3.2.5 Survivor 松开触控后方向归零", survivor_run._move_axis() == Vector2.ZERO)
	var attacks_before: int = survivor_run.attack_count; survivor_run.auto_attack()
	_check("B3.3 Survivor 自动攻击存在", survivor_run.attack_count == attacks_before + 1)
	_check("B3.3.1 Survivor 自动攻击生成可见弹丸", survivor_run.get_node("Projectiles").get_child_count() > 0 and survivor_run.get_node("Projectiles").get_child(0).find_child("Visual", true, false) is Polygon2D)
	survivor_run._move_projectiles(1.0)
	_check("B3.3.2 Survivor 弹丸命中结算击杀", survivor_run.kills > 0)
	_check("B3.3.3 Survivor 击杀掉落经验珠而非直接加 XP", survivor_run.xp == 0 and survivor_run.get_node("XPOrbs").get_child_count() > 0)
	var orb: Node2D = survivor_run.get_node("XPOrbs").get_child(0)
	orb.position = survivor_run.hero.position + Vector2(200, 0)
	var orb_before := orb.position
	survivor_run.pickup_radius = 90.0
	survivor_run._collect_orbs(0.2)
	_check("B3.3.4 Survivor 半径外经验珠不吸附", is_equal_approx(orb.position.x, orb_before.x) and survivor_run.xp == 0)
	orb.position = survivor_run.hero.position + Vector2(40, 0)
	survivor_run._collect_orbs(0.3)
	_check("B3.3.5 Survivor pickup_radius 内磁吸取 XP", survivor_run.xp > 0)
	var damage_before: int = survivor_run.weapon["damage"]; survivor_run.gain_xp(20)
	_check("B3.4 Survivor XP 升级生效", survivor_run.level == 2 and survivor_run.weapon["damage"] > damage_before)
	_check("B3.4.0 Survivor 升级记录 last_upgrade", survivor_run.last_upgrade != "")
	survivor_run.elapsed = 180.0; survivor_run._update_summary()
	_check("B3.4.1 Survivor 到时自动通关", survivor_run.get_meta("summary", {}).get("cleared", false))
	survivor_run.free()
	var survivor_modes := {}
	for weapon_type in ["magic_bolt","axe","whip","orbit","flame"]:
		var variant: Dictionary = survivor.duplicate(true); variant["weapon"]["type"] = weapon_type; variant["weapon"]["projectiles"] = 2
		var mode_run = survivor_loader.load_from_dsl("survivor@1.0.0", variant); mode_run.elapsed = 2.5; mode_run._spawn_due_enemies(); mode_run.auto_attack()
		var shot = mode_run.get_node("Projectiles").get_child(0)
		survivor_modes["%d:%d:%d" % [mode_run.get_node("Projectiles").get_child_count(), int(shot.get_meta("speed",0)), int(shot.get_meta("damage",0))]] = true
		mode_run.free()
	_check("B3.4.2 Survivor 五种武器行为互异", survivor_modes.size() == 5)
	var hero_colors := {}; var survivor_backgrounds := {}
	for hero_key in ["knight","mage","ranger","robot","witch"]:
		var hero_dsl: Dictionary = survivor.duplicate(true); hero_dsl["hero"]["sprite"] = hero_key; var hero_run = survivor_loader.load_from_dsl("survivor@1.0.0",hero_dsl); hero_colors[str(hero_run.hero.get_node("Visual").color)] = true; hero_run.free()
	for background_key in ["meadow","crypt","desert","snow","volcano"]:
		var bg_dsl: Dictionary = survivor.duplicate(true); bg_dsl["stage"]["background"] = background_key; var bg_run = survivor_loader.load_from_dsl("survivor@1.0.0",bg_dsl); survivor_backgrounds[str(bg_run.get_node("StageBackground").color)] = true; bg_run.free()
	_check("B3.4.3 Survivor 五英雄与五背景均有映射", hero_colors.size() == 5 and survivor_backgrounds.size() == 5)
	var enemy_dsl: Dictionary = survivor.duplicate(true); enemy_dsl["waves"] = {}
	for enemy_type in ["slime","bat","skeleton","ghost","golem"]: enemy_dsl["waves"][enemy_type] = {"enemy":enemy_type,"start":0,"interval":1,"count":1,"hp":100,"speed":60,"xp":1}
	var enemy_run = survivor_loader.load_from_dsl("survivor@1.0.0",enemy_dsl); enemy_run.elapsed = 1; enemy_run._spawn_due_enemies(); var enemy_signatures := {}
	for enemy in enemy_run.get_node("Enemies").get_children(): enemy_signatures["%s:%s:%s" % [enemy.get_node("Visual").color,enemy.get_meta("damage",0),enemy.scale]] = true
	_check("B3.4.4 Survivor 五敌人视觉/机制互异", enemy_signatures.size() == 5); enemy_run.free()

	# Tower Defense 必须是第三套独立玩法：路径波次、建塔经济、弹丸攻击、基地生命。
	var tower_dsl := {
		"meta":{"runtime":"tower_defense","runtime_version":"1.0.0","fork_of":null},
		"stage":{"background":"grassland","starting_gold":120,"base_hp":20},
		"path":{"points":[[0,0],[200,0],[200,200]]},
		"towers":{"arrow":{"type":"arrow","cost":50,"damage":12,"range":180,"cooldown":0.5}},
		"placements":{"first":{"tower":"arrow","position":[80,60]}},
		"waves":{"first":{"enemy":"grunt","count":3,"hp":10,"speed":60,"reward":8,"start":0,"interval":0.5}}
	}
	var tower_loader := preload("res://runtime/runtime_loader.gd").new()
	var tower_run := tower_loader.load_from_dsl("tower_defense@1.0.0", tower_dsl)
	_check("B3.5 Tower Defense 独立加载", tower_run != null and tower_run.name == "TowerDefenseRuntime")
	if tower_run != null:
		root.add_child(tower_run)
		_check("B3.6 Tower Defense 建塔扣费", tower_run.get_node("Towers").get_child_count() == 1 and tower_run.gold == 70)
		_check("B3.6.1 Tower Defense 路径和塔可见", tower_run.get_node("PathVisual") is Line2D and tower_run.get_node("Towers").get_child(0).find_child("Visual", true, false) is Polygon2D)
		_check("B3.6.2 Tower Defense 运行时暴露可建造塔", tower_run.tower_ids().size() > 0 and tower_run.has_node("Player"))
		tower_run.elapsed = 1.1; tower_run.spawn_due_enemies(); tower_run._update_summary()
		_check("B3.7 Tower Defense 波次沿路径生成", tower_run.get_node("Enemies").get_child_count() == 3)
		_check("B3.7.0 Tower Defense 记录当前波次", int(tower_run.get_meta("summary", {}).get("current_wave", 0)) == 1)
		_check("B3.7.1 Tower Defense 敌人可见", tower_run.get_node("Enemies").get_child(0).find_child("Visual", true, false) is Polygon2D)
		var gold_before: int = tower_run.gold; tower_run.fire_towers(1.0)
		_check("B3.7.2 Tower Defense 生成可见弹丸", tower_run.get_node("Projectiles").get_child_count() > 0 and tower_run.get_node("Projectiles").get_child(0).find_child("Visual", true, false) is Polygon2D)
		tower_run.resolve_projectiles()
		_check("B3.8 Tower Defense 弹丸击杀奖励", tower_run.gold > gold_before and tower_run.kills > 0)
		for enemy in tower_run.get_node("Enemies").get_children(): enemy.queue_free()
		tower_run._update_summary()
		_check("B3.8.1 Tower Defense 清完全部波次判胜", tower_run.get_meta("summary", {}).get("cleared", false))
		var hp_before: int = tower_run.base_hp; tower_run.damage_base(2)
		_check("B3.9 Tower Defense 基地生命与失败", tower_run.base_hp == hp_before - 2)
		tower_run.damage_base(999)
		_check("B3.10 Tower Defense 基地归零判负", tower_run.get_meta("summary", {}).get("defeated", false) and not tower_run.get_meta("summary", {}).get("cleared", true))
		tower_run.free()
	var tower_modes_dsl: Dictionary = tower_dsl.duplicate(true); tower_modes_dsl["stage"]["starting_gold"] = 9999; tower_modes_dsl["waves"]["first"]["hp"] = 100; tower_modes_dsl["towers"] = {}; tower_modes_dsl["placements"] = {}
	var tower_types := ["arrow","cannon","frost","laser","tesla"]
	for i in tower_types.size():
		var kind: String = tower_types[i]; tower_modes_dsl["towers"][kind] = {"type":kind,"cost":0,"damage":10,"range":500,"cooldown":1.0}; tower_modes_dsl["placements"][kind] = {"tower":kind,"position":[20,i*5]}
	var modes_run = tower_loader.load_from_dsl("tower_defense@1.0.0", tower_modes_dsl); modes_run.elapsed = 1.1; modes_run.spawn_due_enemies(); modes_run.fire_towers(1.0)
	var tower_effects := {}
	for shot in modes_run.get_node("Projectiles").get_children(): tower_effects[str(shot.get_meta("effect",""))] = true
	_check("B3.10.1 Tower Defense 五种塔效果互异", tower_effects.size() == 5)
	var normal_speed := float(modes_run.get_node("Enemies").get_child(0).get_meta("speed")); var normal_hp := int(modes_run.get_node("Enemies").get_child(0).get_meta("hp")); modes_run.resolve_projectiles()
	var slowed := false; var damaged_count := 0
	for enemy in modes_run.get_node("Enemies").get_children():
		if float(enemy.get_meta("speed")) < normal_speed: slowed = true
		if int(enemy.get_meta("hp")) < normal_hp: damaged_count += 1
	_check("B3.10.2 frost 减速且 cannon/tesla 波及多目标", slowed and damaged_count >= 2)
	modes_run.free()
	var tower_backgrounds := {}
	for background_key in ["grassland","desert","snow","volcano","moon"]:
		var bg_dsl: Dictionary = tower_dsl.duplicate(true); bg_dsl["stage"]["background"] = background_key; var bg_run = tower_loader.load_from_dsl("tower_defense@1.0.0",bg_dsl); tower_backgrounds[str(bg_run.get_node("StageBackground").color)] = true; bg_run.free()
	var tower_enemy_dsl: Dictionary = tower_dsl.duplicate(true); tower_enemy_dsl["waves"] = {}
	for enemy_type in ["grunt","runner","tank","flyer","boss"]: tower_enemy_dsl["waves"][enemy_type] = {"enemy":enemy_type,"count":1,"hp":100,"speed":60,"reward":1,"start":0,"interval":1}
	var tower_enemy_run = tower_loader.load_from_dsl("tower_defense@1.0.0",tower_enemy_dsl); tower_enemy_run.elapsed=1; tower_enemy_run.spawn_due_enemies(); var tower_enemy_signatures := {}
	for enemy in tower_enemy_run.get_node("Enemies").get_children(): tower_enemy_signatures["%s:%s:%s" % [enemy.get_node("Visual").color,enemy.get_meta("armor",0),enemy.get_meta("base_damage",1)]] = true
	_check("B3.10.3 Tower 五背景与五敌人均有映射", tower_backgrounds.size()==5 and tower_enemy_signatures.size()==5)
	var grunt: Node2D; var tank: Node2D; var boss: Node2D
	for enemy: Node2D in tower_enemy_run.get_node("Enemies").get_children():
		if enemy.get_meta("archetype") == "grunt": grunt = enemy
		if enemy.get_meta("archetype") == "tank": tank = enemy
		if enemy.get_meta("archetype") == "boss": boss = enemy
	tower_enemy_run._hit_enemy(grunt,10); tower_enemy_run._hit_enemy(tank,10)
	_check("B3.10.4 tank 装甲真实减伤", int(tank.get_meta("hp")) > int(grunt.get_meta("hp")))
	boss.set_meta("path_index",tower_enemy_run._path.size()); var base_before_boss: int = tower_enemy_run.base_hp; tower_enemy_run._move_enemies(0)
	_check("B3.10.5 boss 漏怪造成更高基地伤害", tower_enemy_run.base_hp == base_before_boss - 5); tower_enemy_run.free()

	# B4. 0.x 旧结构迁移到 1.x：数组转稳定 id map、字符串武器展开，且不污染历史文档。
	var legacy := baseline.duplicate(true)
	legacy["meta"]["runtime_version"] = "0.9.0"
	legacy["player"]["weapon"] = "spread"
	legacy["enemies"] = [{"id":"dog_old","type":"dog","behavior":"chase","count":2,"hp":10,"speed":4}]
	legacy["drops"] = [{"id":"heal_old","type":"heal","rate":0.2}]
	var migration_loader := preload("res://runtime/runtime_loader.gd").new()
	var migrated := migration_loader.load_from_dsl("shooter@0.9.0", legacy)
	_check("B4 旧 major DSL 可迁移", migrated != null and migrated.get_meta("weapon_type") == "spread"
		and migrated.get_meta("enemy_total") == 2 and int(migrated.get_meta("drop_count", 0)) == 1)
	_check("B4 迁移不污染历史 DSL", legacy["enemies"] is Array and legacy["player"]["weapon"] == "spread")
	migrated.free()

	# C. Fork 补丁链(6902):换皮 + 按 id 增删敌人(验证 map 寻址稳定)
	bus["ended"] = {}; bus["error"] = {}
	gs.start_game({"runtime": "shooter@1.0.0", "baseline": baseline, "patches": [fork_patch]})
	_check("C Fork 加载成功", not bus["ended"].is_empty() and bus["error"].is_empty())
	_check("C 换皮生效 sprite=cat", bus["ended"].get("player_sprite") == "cat")
	# 原 dog_1:20→30,turret_1:4 删除,新增 bird_1:10 → 30+10 = 40
	_check("C map 寻址增删正确 enemy_total=40", bus["ended"].get("enemy_total") == 40)

	# C2. 黄金对拍:apply 后整树必须等于 golden(与服务端 patch_test.go 共用同一份 golden)。
	# 这才把「两端补丁语义一致」钉成可执行约束,而不是靠 enemy_total 一个标量背书。
	var golden := _load_json("res://runtime/shooter/testdata/fork_expected.dsl.json")
	var res := JsonPatch.apply(baseline, fork_patch)
	_check("C2 补丁 apply 成功", res["ok"])
	_check("C2 整树等于 golden(两端一致性锚点)", _canon(res["result"]) == _canon(golden))
	# 防整体覆盖:dog_1 改了 count 仍保留其余字段
	var dog1: Dictionary = res["result"]["enemies"]["dog_1"]
	_check("C2 dog_1.count=30 且保留 type/behavior/hp",
		dog1.get("count") == 30 and dog1.get("type") == "dog" and dog1.has("behavior") and dog1.has("hp"))
	_check("C2 enemies 仅剩 2 项(turret_1 已删)", res["result"]["enemies"].size() == 2)
	_check("C2 基线未被污染", baseline["player"]["sprite"] == "plane")

	# D. 补丁错误应被 JsonPatch 捕获(replace 不存在的路径)→ DSL_INVALID
	var bad_patch := [[{"op": "replace", "path": "/player/nope", "value": 1}]]
	bus["ended"] = {}; bus["error"] = {}
	gs.start_game({"runtime": "shooter@1.0.0", "baseline": baseline, "patches": bad_patch})
	_check("D 非法补丁被拦截", bus["ended"].is_empty() and bus["error"].get("code") == "DSL_INVALID")

	# E. 根路径操作两端对称拒绝(回归服务端 panic / GD 越界)
	var root_op := [[{"op": "replace", "path": "", "value": {}}]]
	bus["ended"] = {}; bus["error"] = {}
	gs.start_game({"runtime": "shooter@1.0.0", "baseline": baseline, "patches": root_op})
	_check("E 根路径操作被拒绝", bus["ended"].is_empty() and bus["error"].get("code") == "DSL_INVALID")

	# F. Shooter Runtime 对象树:DSL → 游戏对象(敌人按 count 实例化、boss 创建)
	var run := ShooterRuntime.build(baseline)
	var enemies_root := run.get_node("Enemies")
	var enemy_nodes := 0
	for group in enemies_root.get_children():
		enemy_nodes += group.get_child_count()
	# baseline: dog_1 count 20 + turret_1 count 4 = 24 个敌人实例
	_check("F 敌人实例数=24(按 count 实例化)", enemy_nodes == 24)
	_check("F 敌人组数=2", enemies_root.get_child_count() == 2)
	_check("F Player hp=100", run.get_node("Player").get_meta("hp") == 100)
	_check("F Boss 节点已创建(enabled)", run.has_node("Boss"))
	var player_before: Vector2 = run.get_node("Player").position
	run.set_meta("touch_move", Vector2.RIGHT)
	run.get_node("Player")._process(0.2)
	_check("F 触控方向移动玩家", run.get_node("Player").position.x > player_before.x)
	run.set_meta("touch_move", Vector2.ZERO)
	_check("F 玩家有程序化视觉与碰撞", run.get_node("Player") is Node2D
		and run.has_node("Player/HitArea/CollisionShape2D"))
	_check("F 武器控制器真实挂载", run.has_node("Player/Weapon")
		and run.get_node("Player/Weapon").get_meta("mode") == "single")
	_check("F 舞台背景与掉落表可见", run.get_node("StageBackground") is ColorRect
		and run.get_node("Drops") != null and int(run.get_meta("drop_count", 0)) == 2)
	_check("F BGM 与局时长真实节点", run.has_node("BGM") and run.get_node("BGM").get_meta("bgm_key") == "ignition"
		and run.has_node("StageTimer") and run.get_node("StageTimer").wait_time == 90.0)
	_check("F 内容清单所有枚举均有实现", ShooterContent.has_complete_catalog())
	var first_enemy := enemies_root.get_child(0).get_child(0)
	first_enemy.take_damage(9999)
	_check("F 命中死亡进入 Runtime 计分", run.get_meta("score") == 100)
	var weapon_cases := {
		"straight": {"damage": 1, "fire_rate": 2},
		"spread": {"damage": 1, "fire_rate": 2, "bullet_count": 5},
		"laser": {"damage": 1, "width": 2.0},
		"missile": {"damage": 1, "fire_rate": 2, "turn_rate": 1.0},
		"boomerang": {"damage": 1, "range": 8.0},
		"orbit": {"damage": 1, "orbit_count": 4},
	}
	var weapon_modes := {}
	for kind in weapon_cases:
		var controller := WeaponController.new()
		var cfg: Dictionary = weapon_cases[kind].duplicate(); cfg["type"] = kind
		controller.configure(cfg); weapon_modes[controller.get_meta("mode")] = true
		if kind == "spread": controller._fire(); _check("F spread 真实扇形 5 发", controller.get_child_count() == 5)
		if kind == "laser": _check("F laser 真实 Beam", controller.has_node("LaserBeam"))
		if kind == "orbit": _check("F orbit 真实 4 环绕弹", controller.get_child_count() == 4)
		controller.free()
	_check("F 六类武器行为互异", weapon_modes.size() == 6)

	# missile 追踪:朝最近敌人转向,转速受 turn_rate 限制,速度不变(此前 turn_rate 只写 meta 不消费)。
	var missile_ctrl := WeaponController.new()
	missile_ctrl.configure({"type": "missile", "damage": 1, "fire_rate": 2, "turn_rate": 10.0})
	var fake_enemies := Node2D.new(); var fake_group := Node2D.new(); fake_enemies.add_child(fake_group)
	var fake_enemy := Node2D.new(); fake_enemy.position = Vector2(0, 400); fake_group.add_child(fake_enemy)
	missile_ctrl.set_enemies_root(fake_enemies)
	missile_ctrl._fire()
	var missile_shot: Node2D = missile_ctrl.get_child(0)
	var missile_speed_before: float = (missile_shot.get_meta("velocity") as Vector2).length()
	var missile_angle_before: float = (missile_shot.get_meta("velocity") as Vector2).angle()
	missile_ctrl._steer_missile(missile_shot, 0.5)
	var missile_velocity_after: Vector2 = missile_shot.get_meta("velocity")
	_check("F missile 朝最近敌人转向(角度改变)", not is_equal_approx(missile_velocity_after.angle(), missile_angle_before))
	_check("F missile 转向不改变速度大小", is_equal_approx(missile_velocity_after.length(), missile_speed_before))
	missile_ctrl.free(); fake_enemies.free()

	# boomerang 折返:飞出 range 后原路返回(此前 range 只写 meta 不消费,表现等同直线单发)。
	var boomerang_ctrl := WeaponController.new()
	boomerang_ctrl.configure({"type": "boomerang", "damage": 1, "range": 2.0})  # range_px = 2*30 = 60
	boomerang_ctrl._fire()
	var boomerang_shot: Node2D = boomerang_ctrl.get_child(0)
	var boomerang_velocity_before: Vector2 = boomerang_shot.get_meta("velocity")
	boomerang_shot.position = Vector2(100, 0)  # 已超出 60px 射程
	boomerang_ctrl._turn_boomerang(boomerang_shot)
	_check("F boomerang 超出射程后反向折返", boomerang_shot.get_meta("velocity") == -boomerang_velocity_before)
	boomerang_ctrl.free()

	var skill_outputs := {}
	for skill in ShooterContent.BOSS_SKILLS:
		var boss_skill := BossSkillController.new(); boss_skill.configure(skill); boss_skill.activate()
		skill_outputs[skill] = boss_skill.get_child_count() + (1 if boss_skill.get_meta("charging", false) else 0)
		boss_skill.free()
	_check("F 五类 Boss 技能都有行为输出", skill_outputs.values().all(func(n: int) -> bool: return n > 0))
	var coin := DropItem.new(); coin.configure("coin", 1.0); coin.collect(run, run.get_node("Player"), run.get_node("Player/Weapon"))
	_check("F coin 掉落真实加分", run.get_meta("score") == 600)
	var heal := DropItem.new(); heal.configure("heal", 1.0); run.get_node("Player").take_damage(30); heal.collect(run, run.get_node("Player"), run.get_node("Player/Weapon"))
	_check("F heal 掉落真实回血", run.get_node("Player").get_meta("hp") == 95)

	# 掉落物拾取靠真实 Area2D 物理重叠触发,不是直接调用 collect()——上面两条测的是 collect()
	# 本身的效果,这条测的是触发链路本身(此前是死代码:配了 PickupArea 但没人连 pickup_entered)。
	root.add_child(run)
	var pickup_item: DropItem = run.spawn_drop("heal", Vector2(80, 0))
	var pickup_hp_before := int(run.get_node("Player").get_meta("hp", 0))
	var pickup_fired := {}
	pickup_item.pickup_entered.connect(func() -> void: pickup_fired["hit"] = true)
	run.get_node("Player").global_position = pickup_item.global_position + Vector2(500, 500)
	await physics_frame; await physics_frame
	_check("F 玩家离掉落物远时不触发拾取", not pickup_fired.has("hit"))
	run.get_node("Player").global_position = pickup_item.global_position
	await physics_frame; await physics_frame
	_check("F 玩家真实重叠掉落物才触发拾取(物理检测,非直接调用)", pickup_fired.has("hit"))
	_check("F 拾取触发后 collect() 真实生效(heal 回血)", int(run.get_node("Player").get_meta("hp", 0)) > pickup_hp_before)
	var player_actor = run.get_node("Player")
	player_actor._iframe = 0.0
	var hp_before_hit := int(player_actor.get_meta("hp"))
	player_actor.take_damage(9)
	_check("F 玩家受击真实掉血", int(player_actor.get_meta("hp")) == hp_before_hit - 9)
	var hp_during_iframe := int(player_actor.get_meta("hp"))
	player_actor.take_damage(9)
	_check("F 受伤后有无敌帧", int(player_actor.get_meta("hp")) == hp_during_iframe)
	player_actor._iframe = 0.0
	run.grant_shield()
	player_actor.take_damage(40)
	_check("F 护盾吸收运行时伤害", int(player_actor.get_meta("hp")) == hp_during_iframe and int(player_actor.get_meta("shield_hits", 0)) == 0)
	var turret: Node = null
	for group in run.get_node("Enemies").get_children():
		if str(group.get_meta("type", "")) == "turret" and group.get_child_count() > 0:
			turret = group.get_child(0)
			break
	_check("F 炮塔敌人存在", turret != null)
	if turret != null:
		turret._tick_fire(1.0)
		_check("F 炮塔按 fire_rate 开火", run.get_node("Projectiles").get_child_count() > 0)
	var boss_skill_live := BossSkillController.new()
	var phase_host := Node2D.new(); phase_host.set_meta("phase_count", 2); phase_host.set_meta("max_hp", 100); phase_host.set_meta("hp", 10)
	phase_host.add_child(boss_skill_live); boss_skill_live.configure("bullet_hell", 5)
	_check("F Boss phase_count 低血量进入后段", boss_skill_live._phase() == 2)
	var hell_before := boss_skill_live.get_child_count()
	boss_skill_live.activate()
	_check("F Boss 后段弹幕数量随阶段增加", boss_skill_live.get_child_count() >= hell_before + 24)
	var moving := boss_skill_live.get_child(boss_skill_live.get_child_count() - 1) as Node2D
	var shot_pos: Vector2 = moving.position
	moving._process(0.4)
	_check("F Boss 弹幕真实位移", moving.position != shot_pos)
	phase_host.free()
	run.free()

	# G. i18n 数字本地化(docs/18-i18n.md:4.8万 vs 48.2k,中文不加千分位)
	_check("G zh 48200=4.8万", I18n.format_number(48200, "zh") == "4.8万")
	_check("G zh 2100=2100(无逗号)", I18n.format_number(2100, "zh") == "2100")
	_check("G zh 100000000=1亿", I18n.format_number(100000000, "zh") == "1亿")
	_check("G en 48200=48.2k", I18n.format_number(48200, "en") == "48.2k")
	_check("G en 1500000=1.5M", I18n.format_number(1500000, "en") == "1.5M")
	_check("G en 999=999", I18n.format_number(999, "en") == "999")

	# H. 玩法规则:计分 / 加速倍率 / 护盾 / 结算
	var play := ShooterPlay.new(100)
	play.on_kill()
	_check("H 普通击杀 +100", play.score == 100)
	play.set_boost(true)
	play.on_kill()
	_check("H 加速击杀 +200(翻倍)", play.score == 300)
	play.activate_shield()
	play.on_hit(40)
	_check("H 护盾吸收一次,hp 不掉", play.hp == 100)
	play.on_hit(40)
	_check("H 护盾用完后受击扣血", play.hp == 60)
	var result := play.finish(250)
	_check("H 存活通关 cleared", result["cleared"] == true)
	_check("H 分数 300>250 新纪录", result["new_record"] == true)

	# I. 虚拟列表窗口计算(评审标记的 bug 面:渲染哪几项 + 节点池)
	# 视口 600 / 每项 60 → 一屏 10 项,buffer 2
	var vw := VirtualWindow.new(60.0, 600.0, 1000, 2)
	var w0 := vw.window(0.0)
	# 顶部:first 夹到 0,count = 10 + buffer*2 = 14
	_check("I 顶部 first=0", w0["first"] == 0)
	_check("I 顶部 count=14(含buffer)", w0["count"] == 14)
	# 滚到第 100 项处(offset 6000):first = 100-2 = 98
	var w1 := vw.window(6000.0)
	_check("I 中部 first=98(滚动位置-buffer)", w1["first"] == 98)
	_check("I 中部 count=14", w1["count"] == 14)
	# 底部:offset 让 first 接近末尾,count 不越界
	var w2 := vw.window(60.0 * 995)
	_check("I 底部 count 不越界", w2["first"] + w2["count"] <= 1000)
	_check("I 内容总高=60000", vw.content_height() == 60000.0)
	_check("I 第10项 y=600", vw.item_y(10) == 600.0)
	# 空列表
	var empty := VirtualWindow.new(60.0, 600.0, 0)
	_check("I 空列表 count=0", empty.window(0.0)["count"] == 0)

	# J. 创作流状态机:apply 补丁预览 / 撤销 / 重做 / dirty
	var cs := CreatorSession.new(baseline)
	_check("J 初始非 dirty", not cs.is_dirty())
	cs.apply_patch([{"op": "replace", "path": "/player/sprite", "value": "cat"}])
	_check("J 改一版后 dirty", cs.is_dirty())
	_check("J 当前 sprite=cat", cs.current()["player"]["sprite"] == "cat")
	cs.apply_patch([{"op": "add", "path": "/enemies/bird_1",
		"value": {"type": "bird", "behavior": "sine", "count": 5, "hp": 10, "speed": 8}}])
	_check("J 第二步:含 bird", cs.current()["enemies"].has("bird_1"))
	_check("J 步数=2", cs.step_count() == 2)
	cs.undo()
	_check("J 撤销后 bird 消失", not cs.current()["enemies"].has("bird_1"))
	_check("J 撤销后 sprite 仍 cat", cs.current()["player"]["sprite"] == "cat")
	cs.redo()
	_check("J 重做后 bird 回来", cs.current()["enemies"].has("bird_1"))
	_check("J 非法补丁被拒(状态不变)",
		not cs.apply_patch([{"op": "replace", "path": "/nope/x", "value": 1}]) and cs.step_count() == 2)
	var steps_before_empty: int = cs.step_count()
	_check("J 空补丁不伪装成创作成功", not cs.apply_patch([]) and cs.step_count() == steps_before_empty)
	var edited := cs.current().duplicate(true)
	edited["player"]["sprite"] = "ufo"
	edited["editor_note"] = {"enabled": true}
	_check("J 整份 DSL 编辑可应用", cs.apply_document(edited))
	_check("J 整份 DSL 编辑生成可撤销步骤",
		cs.current()["player"]["sprite"] == "ufo" and cs.current().has("editor_note") and cs.step_count() == 3)
	cs.undo()
	_check("J 整份 DSL 编辑可撤销", cs.current()["player"]["sprite"] == "cat" and not cs.current().has("editor_note"))

	# K. 真二维码：标准版本尺寸、三个定位符与 4-module quiet zone。
	var qr := QrCode.new()
	var qr_data := qr.get_data("https://forgeplay.app/u/%40koru")
	_check("K QR 最小版本为 21×21", qr_data.size() >= 21 and (qr_data.size() - 17) % 4 == 0)
	_check("K QR 左上定位符", qr_data[0][0] and qr_data[0][6] and qr_data[6][0] and qr_data[3][3])
	var qr_image := qr.get_texture("https://forgeplay.app/u/%40koru").get_image()
	_check("K QR quiet zone 为 4 modules", qr_image.get_width() == qr_data.size() + 8
		and qr_image.get_pixel(0, 0) == Color.WHITE and qr_image.get_pixel(3, 3) == Color.WHITE)
	qr.free()

	# L. 平台层：分享 URL 必须正确编码，能力结果有统一结构。
	var x_url := PlatformBridge.build_share_url("x", "https://forgeplay.app/g/a b", "猫咪 飞机")
	_check("L X 分享参数编码", x_url.begins_with("https://twitter.com/intent/tweet?")
		and "%20" in x_url and not "a b" in x_url)
	var caps := PlatformBridge.capabilities()
	_check("L 平台能力结构", caps.has("share") and caps.has("qr_scan") and caps.has("oauth"))
	_check("L 手机端强制禁用支付",not PlatformBridge.payment_allowed("Android") and not PlatformBridge.payment_allowed("iOS"))
	_check("L 桌面/Web 可由插件提供支付",PlatformBridge.payment_allowed("macOS") and PlatformBridge.payment_allowed("Web"))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("cache/nested"))
	var cache_file := FileAccess.open("user://cache/nested/test.bin", FileAccess.WRITE); cache_file.store_buffer(PackedByteArray([1,2,3])); cache_file.close()
	_check("L 缓存大小统计", PlatformBridge.cache_size_bytes() == 3)
	_check("L 清缓存真实删除文件", PlatformBridge.clear_cache() and PlatformBridge.cache_size_bytes() == 0)

	# M. 联机 Runtime：只接受单调权威快照，并把所有玩家状态投影为可见实体。
	var network_session := NetworkMatchSession.new()
	network_session.configure(null, "room_test", "host")
	var first_snapshot := {"room_id":"room_test", "tick":1, "status":"started", "winner_id":"", "players":[
		{"user_id":"host", "x":-56.0, "y":-8.0, "health":100, "score":10, "last_seq":1},
		{"user_id":"guest", "x":64.0, "y":0.0, "health":90, "score":0, "last_seq":0}]}
	_check("M 权威快照首次应用", network_session.apply_snapshot(first_snapshot))
	_check("M 本人状态来自服务端", network_session.local_player().get("score") == 10 and network_session.local_player().get("x") == -56.0)
	_check("M 旧 tick 不覆盖新状态", not network_session.apply_snapshot({"room_id":"room_test", "tick":0, "status":"started", "players":[]}))
	_check("M 房间串包被拒", not network_session.apply_snapshot({"room_id":"other", "tick":2, "status":"started", "players":[]}))

	var network_runtime := NetworkMatchRuntime.new()
	root.add_child(network_runtime)
	network_runtime.configure("host")
	network_runtime.apply_snapshot(first_snapshot)
	_check("M 双方权威实体可见", network_runtime.get_node("Players").get_child_count() == 2)
	_check("M 本地与远端实体可区分", network_runtime.get_node("Players/host").get_meta("local") and not network_runtime.get_node("Players/guest").get_meta("local"))
	_check("M 运行时同步生命与位置", network_runtime.get_node("Players/guest").get_meta("hp") == 90 and network_runtime.get_node("Players/host").position != network_runtime.get_node("Players/guest").position)
	network_runtime.free()

	# N. 桌面集成：DSL 文件真实往返、多窗口加载 Runtime，移动端不暴露桌面能力。
	_check("N 桌面平台识别", DesktopIntegration.is_desktop("macOS") and DesktopIntegration.is_desktop("Windows") and not DesktopIntegration.is_desktop("Android"))
	_check("N 原生菜单动作完整", DesktopIntegration.menu_actions() == ["import_dsl", "export_dsl", "preview_window"])
	var desktop := DesktopIntegration.new()
	root.add_child(desktop)
	var desktop_path := "user://desktop_roundtrip.classic-games.json"
	_check("N DSL 文件导出成功", desktop.save_dsl(desktop_path, baseline))
	_check("N DSL 文件无损导入", desktop.load_dsl(desktop_path) == baseline)
	var bad_file := FileAccess.open("user://desktop_bad.classic-games.json", FileAccess.WRITE); bad_file.store_string("[]"); bad_file.close()
	_check("N 非对象文件拒绝导入", desktop.load_dsl("user://desktop_bad.classic-games.json").is_empty())
	var preview_window := desktop.open_preview_window("shooter@1.0.0", baseline)
	_check("N 多窗口运行真实 Runtime", preview_window is Window and preview_window.get_node_or_null("ShooterRuntime") != null)
	preview_window.queue_free(); desktop.queue_free()

	print("\n=== spike 结果: %d passed, %d failed ===" % [_passed, _failed])
	_finish.call_deferred(1 if _failed > 0 else 0)

func _finish(exit_code:int)->void:
	await process_frame
	for child in root.get_children(): child.queue_free()
	await process_frame
	await process_frame
	quit(exit_code)

func _load_baseline() -> Dictionary:
	return _load_json("res://runtime/shooter/baseline.dsl.json")

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

# 规范化:key 排序后的 JSON 字符串,用于整树相等比较。
func _canon(d: Variant) -> String:
	return JSON.stringify(d, "", true)

func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
