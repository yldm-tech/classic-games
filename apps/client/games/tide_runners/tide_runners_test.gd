extends SceneTree

## Headless tests of Tide Runners: movement and collision, aiming and the weapons, losing lives and continues, the three bosses and stage clears, the tower's tide, two-player rules and determinism. Players are driven through feed() wherever the rule under test is an input rule; a diver is put in place directly (and made safe for the long boss fights) where the test would otherwise have to play a whole stage first. The options "_stage", "_boss", "_lives" and "_continues" are not in the manifest, so no menu offers them.
## Run: GODOT=/path/to/godot scripts/run-godot-test.sh res://games/tide_runners/tide_runners_test.gd '^tide_runners_test: [0-9]+ passed, 0 failed$'

const Main := preload("res://games/tide_runners/main.gd")
const Levels := preload("res://games/tide_runners/levels.gd")
const Foes := preload("res://games/tide_runners/foes.gd")
const Bosses := preload("res://games/tide_runners/bosses.gd")
const World := preload("res://games/tide_runners/world.gd")
const Sounds := preload("res://games/tide_runners/sounds.gd")

const STEP := GameModule.STEP

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_stage_data()
	_test_start()
	_test_movement()
	_test_aim_and_weapons()
	_test_hits_and_lives()
	_test_foes_and_score()
	_test_first_boss_by_shooting()
	_test_tower()
	_test_full_clear()
	_test_two_players()
	_test_determinism()
	print("tide_runners_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _start(players: int, seed_value: int, options: Dictionary = {}) -> Main:
	var game: Main = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": Vector2i(480, 270)})
	return game

func _tap(game: GameModule, slot: int, control: StringName) -> void:
	game.feed(slot, control, 1.0)
	game.advance(STEP)
	game.feed(slot, control, 0.0)

func _put(game: Main, slot: int, x: float, y: float) -> void:
	var h: Dictionary = game.heroes[slot]
	h["x"] = x
	h["y"] = y
	h["vx"] = 0.0
	h["vy"] = 0.0

func _safe(game: Main) -> void:
	for h: Dictionary in game.heroes:
		h["inv"] = 1000000.0

# ---- data ----

func _test_stage_data() -> void:
	var kinds_ok := true
	var spawns_stand := true
	for index in Levels.STAGE_COUNT:
		var world := World.new()
		world.load_stage(Levels.stage(index))
		for entry: Array in world.def["spawns"]:
			if not Foes.KINDS.has(entry[0]):
				kinds_ok = false
			if entry[0] in ["turret", "troop", "toad", "cling", "crate"] and world.cell(int(entry[1]), int(entry[2])) == World.EMPTY:
				spawns_stand = false
				push_error("stage %d: %s at column %d row %d stands on nothing" % [index, entry[0], entry[1], entry[2]])
		for zone: Array in world.def["zones"]:
			if not Foes.KINDS.has(zone[2]):
				kinds_ok = false
	_check("every machine a stage asks for exists", kinds_ok)
	_check("every placed machine has a tile under it", spawns_stand)
	var reachable := true
	for level in range(1, Levels.TOWER_LEVELS):
		var here: Array = Levels.TOWER_ROWS[(level - 1) % Levels.TOWER_ROWS.size()]
		var above: Array = Levels.TOWER_ROWS[level % Levels.TOWER_ROWS.size()]
		var linked := false
		for low: Array in here:
			for high: Array in above:
				if int(low[0]) <= int(high[0]) + int(high[1]) and int(high[0]) <= int(low[0]) + int(low[1]):
					linked = true
		reachable = reachable and linked
	_check("every row of the tower can be reached from the row below", reachable)
	# No gap in the ground of a scrolling stage is wider than a jump unless a platform bridges it.
	var crossable := true
	for index in [0, 2]:
		var world := World.new()
		world.load_stage(Levels.stage(index))
		var run := 0
		for column in world.cols:
			var open := true
			for row in range(8, world.rows):
				if world.cell(column, row) != World.EMPTY:
					open = false
			run = run + 1 if open else 0
			if run > 4:
				crossable = false
				push_error("stage %d: a gap wider than four tiles ends at column %d" % [index, column])
	_check("no gap is wider than a jump", crossable)
	_check("the tunes parse into notes", Sounds.notes("D5:.5 -:1").size() == 2 and is_equal_approx(float(Sounds.notes("D5:.5")[0][1]), 0.5) and (Sounds.boss_music()["voices"] as Array).size() == 3)

# ---- rules ----

func _test_start() -> void:
	var game := _start(1, 3)
	var first := game.snapshot()
	_check("a run starts on stage one of three with full lives and the rivet gun", first["stage"] == 1 and first["stages_total"] == 3 and first["players"][0]["lives"] == 3 and first["players"][0]["max_lives"] == 3 and first["players"][0]["weapon"] == 0 and first["continues"] == 2)
	_check("the snapshot lists both seats and the second is empty in a solo run", (first["players"] as Array).size() == 2 and first["players"][1]["alive"] == false and first["player_count"] == 1)
	_check("no boss bar before the boss", not first.has("boss_hp"))
	_check("the stage tune is playing and every effect is defined", game.audio.music_playing and game.audio.has_sound("shot3") and game.audio.has_sound("fanfare"))
	game.free()
	var easy := _start(1, 3, {"difficulty": 0})
	var hard := _start(1, 3, {"difficulty": 2})
	_check("difficulty sets lives and continues", easy.snapshot()["players"][0]["lives"] == 5 and easy.snapshot()["continues"] == 3 and hard.snapshot()["players"][0]["lives"] == 2 and hard.snapshot()["continues"] == 1 and hard.snapshot()["difficulty"] == 2)
	easy.free()
	hard.free()

func _test_movement() -> void:
	var game := _start(1, 4)
	game.advance(0.3)
	var rest := game.snapshot()["players"][0] as Dictionary
	_check("a diver lands on the ground and stays there", rest["ground"] == true and is_equal_approx(float(rest["y"]), 224.0))
	game.feed(0, &"right", 1.0)
	game.advance(1.0)
	game.feed(0, &"right", 0.0)
	var ran := game.snapshot()["players"][0] as Dictionary
	_check("holding right runs right at the running speed", is_equal_approx(float(ran["x"]) - float(rest["x"]), 84.0))
	game.feed(0, &"a", 1.0)
	game.advance(0.3)
	var air := game.snapshot()["players"][0] as Dictionary
	game.advance(1.0)
	var landed := game.snapshot()["players"][0] as Dictionary
	_check("jump leaves the ground and comes back down", air["ground"] == false and float(air["y"]) < 200.0 and landed["ground"] == true and is_equal_approx(float(landed["y"]), 224.0) and int(game.audio.played.get("jump", 0)) == 1)
	game.feed(0, &"a", 0.0)
	game.advance(STEP)
	var top_of_hop := 224.0
	_tap(game, 0, &"a")
	for wait in 30:
		game.advance(STEP)
		top_of_hop = minf(top_of_hop, float(game.snapshot()["players"][0]["y"]))
	_check("letting go of jump early makes a short hop", top_of_hop < 222.0 and top_of_hop > 200.0)
	game.advance(0.5)
	game.feed(0, &"down", 1.0)
	game.advance(0.1)
	_check("holding down on the ground goes prone", game.snapshot()["players"][0]["prone"] == true)
	game.feed(0, &"down", 0.0)
	game.advance(0.1)
	# Brace: the diver stands still while aiming.
	var before := float(game.snapshot()["players"][0]["x"])
	game.feed(0, &"r", 1.0)
	game.feed(0, &"right", 1.0)
	game.advance(0.5)
	game.release_inputs()
	_check("bracing holds the diver in place", is_equal_approx(float(game.snapshot()["players"][0]["x"]), before))
	# A thin platform: stand on it, then drop through with down and jump.
	game.cam.x = 400.0
	_put(game, 0, 36.0 * 16.0, 11.0 * 16.0 - 30.0)
	game.advance(0.6)
	var on_plat := game.snapshot()["players"][0] as Dictionary
	game.feed(0, &"down", 1.0)
	game.advance(STEP)
	_tap(game, 0, &"a")
	game.feed(0, &"down", 0.0)
	game.advance(0.8)
	var below := game.snapshot()["players"][0] as Dictionary
	_check("a diver stands on a thin platform and drops through it with down and jump", is_equal_approx(float(on_plat["y"]), 176.0) and on_plat["ground"] == true and is_equal_approx(float(below["y"]), 224.0))
	# And jumps up through it from below.
	_tap(game, 0, &"a")
	game.feed(0, &"a", 1.0)
	game.advance(0.25)
	var rising := float(game.snapshot()["players"][0]["y"])
	game.advance(1.0)
	game.feed(0, &"a", 0.0)
	_check("a jump passes up through a thin platform and lands on it", rising < 200.0 and is_equal_approx(float(game.snapshot()["players"][0]["y"]), 176.0))
	# A solid wall stops a run: the block at column 250 of stage one is two tiles high.
	_put(game, 0, 249.0 * 16.0 - 20.0, 224.0)
	game.cam.x = 240.0 * 16.0
	game.lock_index = 99
	game.feed(0, &"right", 1.0)
	game.advance(1.0)
	game.feed(0, &"right", 0.0)
	_check("a solid block stops a diver", float(game.snapshot()["players"][0]["x"]) < 250.0 * 16.0 - 3.0)
	game.free()

func _test_aim_and_weapons() -> void:
	var game := _start(1, 5)
	game.advance(0.3)
	game.feed(0, &"up", 1.0)
	game.feed(0, &"right", 1.0)
	game.feed(0, &"r", 1.0)
	_tap(game, 0, &"b")
	var diagonal: Dictionary = game.shots[0]
	_check("up and right aims the shot diagonally", float(diagonal["vx"]) > 0.0 and float(diagonal["vy"]) < 0.0 and is_equal_approx(absf(float(diagonal["vx"])), absf(float(diagonal["vy"]))))
	game.release_inputs()
	game.advance(0.4)
	game.shots.clear()
	game.feed(0, &"up", 1.0)
	_tap(game, 0, &"x")
	_check("up alone fires straight up, and X fires as well as B", game.shots.size() == 1 and is_zero_approx(float(game.shots[0]["vx"])) and float(game.shots[0]["vy"]) < 0.0)
	game.release_inputs()
	game.advance(0.4)
	game.shots.clear()
	game.feed(0, &"left", 1.0)
	game.advance(STEP)
	game.feed(0, &"left", 0.0)
	game.feed(0, &"down", 1.0)
	game.advance(0.1)
	_tap(game, 0, &"b")
	_check("a prone diver fires level along the ground, the way they face", game.shots.size() == 1 and float(game.shots[0]["vx"]) < 0.0 and is_zero_approx(float(game.shots[0]["vy"])) and float(game.shots[0]["y"]) > 214.0)
	game.release_inputs()
	game.advance(0.5)
	# Every canister changes what one pull of the trigger does.
	var counts: Array[int] = []
	for weapon in range(1, 6):
		var hero: Dictionary = game.heroes[0]
		game.drop_item(float(hero["x"]), float(hero["y"]) - 4.0, weapon)
		game.advance(0.6)
		game.shots.clear()
		_tap(game, 0, &"b")
		counts.append(game.shots.size())
		_check("canister %d arms the diver with weapon %d" % [weapon, weapon], game.snapshot()["players"][0]["weapon"] == weapon)
		game.advance(0.6)
	_check("the tri-fork fires three, the arc coil two, the others one", counts == [3, 2, 1, 1, 1])
	_check("each weapon picked up is counted once", game.snapshot()["weapons_tried"] == 5 and int(game.audio.played.get("pickup", 0)) == 5)
	var hero: Dictionary = game.heroes[0]
	game.drop_item(float(hero["x"]), float(hero["y"]) - 4.0, Main.SHIELD)
	game.advance(0.6)
	_check("the bubble canister gives a shield and keeps the weapon", game.snapshot()["players"][0]["shield"] == true and game.snapshot()["players"][0]["weapon"] == 5)
	game.foe_shot(float(hero["x"]) - 30.0, float(hero["y"]) - 10.0, 200.0, 0.0, "orb")
	game.advance(0.4)
	_check("the shield takes one hit instead of a life", game.snapshot()["players"][0]["shield"] == false and game.snapshot()["players"][0]["lives"] == 3 and game.snapshot()["deaths"] == 0)
	# The skipper disc comes back off the edge of the view.
	game.shots.clear()
	game.foes.clear()
	game.heroes[0]["face"] = -1
	_tap(game, 0, &"b")
	var away := float(game.shots[0]["vx"])
	game.advance(1.2)
	_check("the skipper disc bounces back", away < 0.0 and game.shots.size() == 1 and float(game.shots[0]["vx"]) > 0.0)
	game.free()

func _test_hits_and_lives() -> void:
	var game := _start(1, 6, {"_continues": 1})
	game.advance(0.3)
	var hero: Dictionary = game.heroes[0]
	hero["weapon"] = 4
	# A level shot at chest height passes over a prone diver and hits a standing one.
	game.feed(0, &"down", 1.0)
	game.advance(0.1)
	game.foe_shot(float(hero["x"]) - 40.0, float(hero["y"]) - 11.0, 160.0, 0.0, "orb")
	game.advance(0.6)
	game.feed(0, &"down", 0.0)
	_check("going prone lets a level shot pass overhead", game.snapshot()["deaths"] == 0 and game.snapshot()["players"][0]["alive"] == true)
	game.advance(0.1)
	game.foe_shot(float(hero["x"]) - 40.0, float(hero["y"]) - 11.0, 160.0, 0.0, "orb")
	game.advance(0.4)
	var hit := game.snapshot()
	_check("one hit costs a life and the salvaged weapon", hit["deaths"] == 1 and hit["players"][0]["lives"] == 2 and hit["players"][0]["alive"] == false and hit["players"][0]["weapon"] == 0 and int(game.audio.played.get("die", 0)) == 1)
	game.advance(1.5)
	var back := game.snapshot()
	_check("the diver comes back on dry ground", back["players"][0]["alive"] == true and back["players"][0]["ground"] == true and float(back["players"][0]["y"]) <= 224.0)
	game.foe_shot(float(hero["x"]) - 20.0, float(hero["y"]) - 11.0, 160.0, 0.0, "orb")
	game.advance(0.4)
	_check("a diver who just came back cannot be hit for a moment", game.snapshot()["deaths"] == 1)
	game.advance(3.0)
	# The water: the gap at columns 42-44 of stage one.
	game.foes.clear()
	game.foe_shots.clear()
	_put(game, 0, 43.0 * 16.0 + 8.0, 200.0)
	game.cam.x = 500.0
	game.advance(0.6)
	_check("falling into the water costs a life", game.snapshot()["deaths"] == 2 and game.snapshot()["players"][0]["lives"] == 1)
	game.advance(1.6)
	game.foes.clear()
	game.foe_shots.clear()
	_put(game, 0, 43.0 * 16.0 + 8.0, 200.0)
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	game.advance(4.0)
	var continued := game.snapshot()
	_check("with no lives left a continue is spent and the diver returns with full lives", results.is_empty() and continued["continues"] == 0 and continued["continues_used"] == 1 and continued["players"][0]["lives"] == 3 and continued["players"][0]["alive"] == true)
	for life in 3:
		game.foes.clear()
		game.foe_shots.clear()
		_put(game, 0, 43.0 * 16.0 + 8.0, 200.0)
		game.advance(2.0)
	game.advance(3.0)
	_check("out of lives and continues, the run is lost", results.size() == 1 and results[0]["defeated"] == true and results[0]["cleared"] == false and results[0]["deaths"] == 6 and results[0]["continues_used"] == 1 and results[0]["bosses_down"] == 0)
	game.free()

func _test_foes_and_score() -> void:
	var game := _start(1, 8)
	game.advance(0.3)
	var hero: Dictionary = game.heroes[0]
	game.foes.clear()
	var scut: Dictionary = Foes.spawn(game, "scut", float(hero["x"]) + 120.0, 224.0)
	scut["ground"] = true
	game.feed(0, &"b", 1.0)
	game.advance(0.8)
	game.feed(0, &"b", 0.0)
	var shot_down := game.snapshot()
	_check("a shot destroys a scuttler and scores it", shot_down["kills"] == 1 and shot_down["score"] == 100 and shot_down["players"][0]["score"] == 100 and int(game.audio.played.get("boom_small", 0)) >= 1)
	# A turret takes four rivets and fires back.
	game.shots.clear()
	var turret: Dictionary = Foes.spawn(game, "turret", float(hero["x"]) + 100.0, 224.0)
	game.advance(1.2)
	_check("a turret fires at a diver in range", game.foe_shots.size() >= 1)
	game.foe_shots.clear()
	_safe(game)
	game.feed(0, &"b", 1.0)
	game.advance(0.5)
	var hurt := int(turret["hp"])
	game.advance(1.0)
	game.feed(0, &"b", 0.0)
	_check("a turret takes several hits", hurt < 4 and hurt > 0 and game.snapshot()["kills"] == 2 and game.snapshot()["score"] == 400)
	hero["inv"] = 0.0
	# A machine that touches a diver costs a life.
	game.foe_shots.clear()
	var cling: Dictionary = Foes.spawn(game, "cling", float(hero["x"]), 224.0)
	cling["vx"] = 0.0
	game.advance(STEP * 2.0)
	_check("touching a machine costs a life", game.snapshot()["deaths"] == 1)
	# A courier drops its canister when shot.
	game.foes.clear()
	game.advance(2.0)
	_safe(game)
	var courier: Dictionary = Foes.spawn(game, "carrier", float(hero["x"]), 150.0, 2)
	game.feed(0, &"up", 1.0)
	game.feed(0, &"b", 1.0)
	game.advance(0.5)
	game.release_inputs()
	_check("a courier that is shot drops its canister", courier["dead"] == true and game.items.size() == 1 and int(game.items[0]["k"]) == 2)
	game.advance(2.5)
	_check("the canister falls to the diver and is picked up", game.items.is_empty() and game.snapshot()["players"][0]["weapon"] == 2)
	# The camera stops at an ambush until the wave is beaten.
	game.cam.x = 119.0 * 16.0
	_put(game, 0, 119.0 * 16.0 + 300.0, 224.0)
	game.advance(0.5)
	var locked := float(game.snapshot()["camera_x"])
	_put(game, 0, locked + 460.0, 224.0)
	game.advance(1.0)
	_check("the camera locks for an ambush", is_equal_approx(locked, 120.0 * 16.0) and is_equal_approx(float(game.snapshot()["camera_x"]), locked) and not game.lock.is_empty())
	for wait in 200:
		for foe: Dictionary in game.foes:
			if foe["wave"]:
				Foes.hurt(game, foe, 9, 0)
		game.advance(0.25)
		if game.lock.is_empty():
			break
	_put(game, 0, locked + 460.0, 224.0)
	game.advance(1.0)
	_check("beating the wave frees the camera", game.lock.is_empty() and float(game.snapshot()["camera_x"]) > locked)
	game.free()

func _test_first_boss_by_shooting() -> void:
	var game := _start(1, 9, {"_boss": 1})
	_safe(game)
	var arena := 300.0 * 16.0
	_check("the boss arena starts with the camera at the end of the stage", is_equal_approx(float(game.snapshot()["camera_x"]), arena))
	game.advance(0.2)
	_check("reaching the arena raises the alarm and shows the boss bar", game.snapshot().has("boss_hp") and game.snapshot()["boss_active"] == false and int(game.audio.played.get("alarm", 0)) >= 1)
	var full := int(game.snapshot()["boss_hp"])
	game.feed(0, &"b", 1.0)
	game.advance(1.0)
	_check("the boss cannot be hurt before it wakes", int(game.snapshot()["boss_hp"]) == full)
	game.advance(2.0)
	_check("the boss wakes after the warning", game.snapshot()["boss_active"] == true)
	# Level shots reach the jaw hatch; the shuttered core takes nothing yet.
	var core: Dictionary = Bosses.part(game.boss, "core")
	_put(game, 0, arena + 200.0, 224.0)
	game.heroes[0]["face"] = 1
	for wait in 40:
		game.foes.clear()
		game.advance(0.5)
		if not Bosses.part(game.boss, "hatch")["alive"]:
			break
	_check("level fire breaks the jaw hatch", Bosses.part(game.boss, "hatch")["alive"] == false and int(core["hp"]) == int(core["max"]))
	# Diagonal fire from the right spot reaches the cannon arm.
	var cannon: Dictionary = Bosses.part(game.boss, "cannon")
	_put(game, 0, float(cannon["x"]) - (212.0 - float(cannon["y"])) - 10.0, 224.0)
	game.feed(0, &"r", 1.0)
	game.feed(0, &"up", 1.0)
	game.feed(0, &"right", 1.0)
	for wait in 40:
		game.advance(0.5)
		if not cannon["alive"]:
			break
	_check("diagonal fire breaks the cannon arm", cannon["alive"] == false and int(core["hp"]) == int(core["max"]))
	_put(game, 0, float(core["x"]) - (212.0 - float(core["y"])) - 10.0, 224.0)
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	for wait in 120:
		game.advance(0.5)
		if game.snapshot()["stage_clear"]:
			break
	game.release_inputs()
	var cleared := game.snapshot()
	_check("with both guards gone the core opens and can be destroyed", cleared["stage_clear"] == true and cleared["bosses_down"] == 1 and not cleared.has("boss_hp") and int(cleared["score"]) >= 2000 + 5000 + 2000)
	game.advance(6.0)
	_check("clearing a stage moves on to the next", results.is_empty() and game.snapshot()["stage"] == 2 and float(game.snapshot()["camera_y"]) > 2000.0)
	game.free()

func _test_tower() -> void:
	var game := _start(1, 10, {"_stage": 1})
	var bottom := float(game.snapshot()["camera_y"])
	game.advance(3.5)
	var tide := float(game.snapshot()["water_y"])
	game.advance(2.0)
	_check("the tide rises in the tower", float(game.snapshot()["water_y"]) < tide)
	# Climbing: jump from row to row and the camera follows upwards only.
	_put(game, 0, 9.0 * 16.0, float(Levels.TOWER_FLOOR_ROW - 3) * 16.0 - 2.0)
	game.advance(0.3)
	for hop in 3:
		game.feed(0, &"a", 1.0)
		game.advance(0.9)
		game.feed(0, &"a", 0.0)
		game.advance(0.1)
	var climbed := game.snapshot()
	_check("jumping climbs the platforms and the camera follows", float(climbed["players"][0]["y"]) <= float(Levels.TOWER_FLOOR_ROW - 9) * 16.0 + 0.5 and float(climbed["camera_y"]) < bottom)
	var held := float(climbed["camera_y"])
	_put(game, 0, 9.0 * 16.0, float(climbed["players"][0]["y"]) + 60.0)
	game.advance(0.2)
	_check("the camera never scrolls back down", float(game.snapshot()["camera_y"]) <= held)
	game.advance(60.0)
	_check("a diver who stops climbing is caught by the tide", game.snapshot()["deaths"] >= 1)
	game.free()

func _test_full_clear() -> void:
	var game := _start(1, 11, {"_stage": 1, "_boss": 1, "difficulty": 2})
	_safe(game)
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	game.advance(3.0)
	var heart: Dictionary = Bosses.part(game.boss, "core")
	_check("the hydra's heart is armoured while a head lives", Bosses.hit(game, game.boss, Vector2(float(heart["x"]), float(heart["y"])), 2.0, 5, 0) == Bosses.DEFLECTED and int(heart["hp"]) == int(heart["max"]))
	for entry: Dictionary in game.boss["parts"]:
		if entry["n"] == "head":
			for blow in 40:
				Bosses.hit(game, game.boss, Vector2(float(entry["x"]), float(entry["y"])), 2.0, 5, 0)
	game.advance(0.1)
	_check("with the heads gone the heart is open", Bosses.alive_count(game.boss, "head") == 0 and heart["vuln"] == true)
	for blow in 40:
		Bosses.hit(game, game.boss, Vector2(float(heart["x"]), float(heart["y"])), 2.0, 5, 0)
	game.advance(Bosses.DYING_TIME + 6.0)
	_check("the tower's boss falls and the dockyard begins", game.snapshot()["stage"] == 3 and game.snapshot()["bosses_down"] == 1 and results.is_empty())
	# The gantry: its eye only opens while the claw is out, or once the claw is gone.
	game._skip_to_boss()
	_safe(game)
	game.advance(3.0)
	var eye: Dictionary = Bosses.part(game.boss, "core")
	_check("the gantry's eye is shut while the claw is stowed", game.snapshot()["boss_active"] == true and eye["vuln"] == false)
	var opened := false
	for wait in 400:
		game.advance(0.05)
		if eye["vuln"]:
			opened = true
			break
	game.advance(0.6)
	_check("the eye opens when the claw slams down", opened and int(game.boss["st"]) >= 3 and int(game.audio.played.get("slam", 0)) >= 1)
	var claw: Dictionary = Bosses.part(game.boss, "claw")
	for blow in 40:
		Bosses.hit(game, game.boss, Vector2(float(claw["x"]), float(claw["y"])), 2.0, 5, 0)
	game.advance(0.1)
	_check("without its claw the eye stays open", claw["alive"] == false and eye["vuln"] == true)
	for blow in 60:
		Bosses.hit(game, game.boss, Vector2(float(eye["x"]), float(eye["y"])), 2.0, 5, 0)
	game.advance(Bosses.DYING_TIME + 6.0)
	_check("clearing the last stage clears the run", results.size() == 1 and results[0]["cleared"] == true and results[0]["defeated"] == false)
	if results.size() == 1:
		_check("the result carries what the achievements read", results[0]["bosses_down"] == 2 and results[0]["continues_used"] == 0 and results[0]["difficulty"] == 2 and results[0]["stage"] == 3 and results[0]["player_count"] == 1 and int(results[0]["score"]) > 0 and not game.audio.music_playing)
	game.free()

func _test_two_players() -> void:
	var game := _start(2, 12, {"_lives": 1, "_continues": 0})
	game.advance(0.3)
	var first := game.snapshot()
	_check("two divers start side by side", first["players"][0]["alive"] == true and first["players"][1]["alive"] == true and float(first["players"][1]["x"]) > float(first["players"][0]["x"]))
	game.feed(0, &"right", 1.0)
	game.feed(1, &"left", 1.0)
	game.advance(0.25)
	game.release_inputs()
	var moved := game.snapshot()
	_check("each diver moves by their own input", float(moved["players"][0]["x"]) > float(first["players"][0]["x"]) and float(moved["players"][1]["x"]) < float(first["players"][1]["x"]))
	game.foes.clear()
	var scut: Dictionary = Foes.spawn(game, "scut", float(game.heroes[1]["x"]) + 90.0, 224.0)
	scut["ground"] = true
	scut["face"] = 1
	game.heroes[1]["face"] = 1
	game.feed(1, &"b", 1.0)
	game.advance(0.6)
	game.release_inputs()
	_check("a kill scores for the diver who made it, and the total is the sum", game.snapshot()["players"][1]["score"] == 100 and game.snapshot()["players"][0]["score"] == 0 and game.snapshot()["score"] == 100)
	# The camera waits for the diver at the back.
	game.foes.clear()
	_put(game, 0, 400.0, 224.0)
	_put(game, 1, 30.0, 224.0)
	game.advance(1.0)
	_check("the camera does not leave the diver at the back behind", float(game.snapshot()["camera_x"]) <= 30.0)
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	game.foe_shot(float(game.heroes[1]["x"]) - 20.0, 213.0, 200.0, 0.0, "orb")
	game.advance(3.0)
	_check("one diver out of lives does not end the run for the other", results.is_empty() and game.snapshot()["players"][1]["alive"] == false and game.snapshot()["players"][1]["lives"] == 0 and game.snapshot()["players"][0]["alive"] == true)
	game.feed(1, &"right", 1.0)
	game.advance(0.5)
	game.release_inputs()
	_check("a diver who is out no longer acts", game.snapshot()["players"][1]["alive"] == false)
	game.foes.clear()
	game.foe_shots.clear()
	game.foe_shot(float(game.heroes[0]["x"]) - 20.0, 213.0, 200.0, 0.0, "orb")
	game.advance(5.0)
	_check("when both are out the run is lost", results.size() == 1 and results[0]["defeated"] == true and results[0]["player_count"] == 2)
	game.free()

	# Joining and leaving a live run.
	game = _start(1, 13)
	game.advance(1.0)
	_check("a second player can join a live run", game.join(1) and game.snapshot()["player_count"] == 2 and game.snapshot()["players"][1]["alive"] == true and game.snapshot()["players"][1]["lives"] == 3)
	game.feed(1, &"right", 1.0)
	var joined_x := float(game.snapshot()["players"][1]["x"])
	game.advance(0.5)
	game.release_inputs()
	_check("the joined diver is driven by the second seat", float(game.snapshot()["players"][1]["x"]) > joined_x)
	_check("the second player can leave again", game.leave(1) and game.snapshot()["player_count"] == 1 and game.snapshot()["players"][1]["alive"] == false and (game.snapshot()["players"] as Array).size() == 2)
	game.advance(1.0)
	_check("the run goes on for the diver who stayed", game.is_running() and game.snapshot()["players"][0]["alive"] == true)
	game.free()

	# Two divers face a tougher boss than one.
	var solo := _start(1, 14, {"_boss": 1})
	var duo := _start(2, 14, {"_boss": 1})
	_check("a boss has more hit points against two divers", Bosses.max_hp(duo.boss) > Bosses.max_hp(solo.boss))
	solo.free()
	duo.free()

func _test_determinism() -> void:
	var states: Array = []
	for attempt in 2:
		var game := _start(2, 77)
		var script := [[2.0, ["right", "b"], ["right"]], [0.5, ["right", "a", "b"], ["right", "up", "b"]], [3.0, ["right", "b"], ["right", "b", "a"]], [1.0, ["down", "b"], ["left"]], [6.0, ["right", "up", "b"], ["right", "b"]], [8.0, ["right", "b", "a"], ["right", "b"]]]
		for segment: Array in script:
			game.release_inputs()
			for slot in 2:
				for control: String in segment[slot + 1]:
					game.feed(slot, StringName(control), 1.0)
			game.advance(float(segment[0]))
		states.append(game.snapshot())
		game.free()
	_check("the same seed and the same inputs give the same run", states[0] == states[1] and float(states[0]["elapsed"]) > 20.0 and float(states[0]["camera_x"]) > 100.0)
	var other := _start(2, 78)
	other.feed(0, &"right", 1.0)
	other.feed(0, &"b", 1.0)
	other.advance(20.5)
	var same := _start(2, 77)
	same.feed(0, &"right", 1.0)
	same.feed(0, &"b", 1.0)
	same.advance(20.5)
	_check("the simulated clock is exact", is_equal_approx(float(same.snapshot()["elapsed"]), 20.5) and is_equal_approx(float(other.snapshot()["elapsed"]), 20.5))
	other.free()
	same.free()

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
