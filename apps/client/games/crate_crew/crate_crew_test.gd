extends SceneTree

## Headless tests of Crate Crew. Every run is driven through the public surface of the module: start(), feed(), advance(), join(), leave() and snapshot(). The tests look into game.world to decide what to press and to say what they expect, never to change anything. Two unlisted start options, "stage" and "flag", begin a run further in so the boss rooms can be fought with real inputs without replaying the stages before them.
## Run: make games-test GODOT=/path/to/godot

const Main := preload("res://games/crate_crew/main.gd")
const World := preload("res://games/crate_crew/world.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Sounds := preload("res://games/crate_crew/sounds.gd")
const Texts := preload("res://games/crate_crew/texts.gd")

const STEP := GameModule.STEP
const INTRO := 1.7

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_start()
	_test_moving()
	_test_lift_and_throw()
	_test_throw_up_and_put_down()
	_test_hiding()
	_test_losing()
	_test_two_players()
	_test_join_and_leave()
	_test_lift_belt_and_door()
	_test_golden_cog_counts_once()
	_test_first_boss()
	_test_last_boss_clears_the_game()
	_test_determinism()
	_test_stages_can_be_walked()
	_test_art_and_sound()
	print("crate_crew_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- helpers ----

func _start(players: int, seed_value: int, options: Dictionary = {}, skip_intro: bool = true) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": Vector2i(384, 216)})
	if skip_intro:
		game.advance(INTRO)
	return game

func _tap(game: GameModule, slot: int, control: StringName) -> void:
	game.feed(slot, control, 1.0)
	game.advance(STEP)
	game.feed(slot, control, 0.0)
	game.advance(STEP)

func _hold(game: GameModule, slot: int, control: StringName, seconds: float) -> void:
	game.feed(slot, control, 1.0)
	game.advance(seconds)
	game.feed(slot, control, 0.0)

func _hero(game: GameModule, slot: int) -> Dictionary:
	return game.world.heroes[slot]

## Hold a direction until the robot's x passes `x`, at most for `limit` seconds. Returns whether it got there.
func _walk_to(game: GameModule, slot: int, x: float, limit: float = 8.0) -> bool:
	var hero := _hero(game, slot)
	var control := &"right" if float(hero["x"]) < x else &"left"
	var going_right := control == &"right"
	game.feed(slot, control, 1.0)
	var steps := int(limit / STEP)
	var reached := false
	for index in steps:
		if (going_right and float(hero["x"]) >= x) or (not going_right and float(hero["x"]) <= x):
			reached = true
			break
		game.advance(STEP)
	game.feed(slot, control, 0.0)
	game.advance(STEP)
	return reached

func _results(game: GameModule) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	return results

# ---- rules ----

func _test_start() -> void:
	var game := _start(1, 3, {}, false)
	var first := game.snapshot()
	_check("a run starts on stage 1 of 4 with the intro card up", first["stage"] == 1 and first["stages"] == 4 and first["phase"] == World.P_INTRO)
	_check("player one starts with 3 energy and 4 lives on normal, player two is not playing", first["players"][0]["energy"] == 3 and first["players"][0]["max_energy"] == 3 and first["players"][0]["lives"] == 4 and first["players"][1]["lives"] == 0)
	_check("the stage tune is playing", game.audio.music_playing)
	var x := float(first["players"][0]["x"])
	_hold(game, 0, &"right", 1.0)
	_check("nothing moves while the intro card is up", is_equal_approx(float(game.snapshot()["players"][0]["x"]), x))
	game.free()
	var easy := _start(1, 3, {"difficulty": 1})
	var hard := _start(1, 3, {"difficulty": 3})
	_check("easy gives more energy, lives and continues than hard", easy.snapshot()["players"][0]["max_energy"] == 4 and easy.snapshot()["players"][0]["lives"] == 5 and easy.snapshot()["continues_left"] == 3 and hard.snapshot()["players"][0]["lives"] == 3 and hard.snapshot()["continues_left"] == 1 and hard.snapshot()["difficulty"] == 3)
	easy.free()
	hard.free()

func _test_moving() -> void:
	var game := _start(1, 3)
	var before := game.snapshot()["players"][0] as Dictionary
	_hold(game, 0, &"right", 0.5)
	var after := game.snapshot()["players"][0] as Dictionary
	_check("holding right walks right along the floor", float(after["x"]) > float(before["x"]) + 30.0 and is_equal_approx(float(after["y"]), float(before["y"])) and bool(after["ground"]))
	game.feed(0, &"a", 1.0)
	game.advance(0.3)
	var top := float(game.snapshot()["players"][0]["y"])
	game.advance(0.7)
	game.feed(0, &"a", 0.0)
	_check("jump rises about three tiles and lands again", float(after["y"]) - top > 40.0 and float(after["y"]) - top < 48.0 and is_equal_approx(float(game.snapshot()["players"][0]["y"]), float(after["y"])))
	_check("the jump was heard", int(game.audio.played.get("jump", 0)) == 1)
	# A wall stops the robot: the left edge of the stage.
	_hold(game, 0, &"left", 3.0)
	_check("a wall stops the robot", is_equal_approx(float(game.snapshot()["players"][0]["x"]), World.HERO_HALF))
	game.free()
	# Walking into the first pit costs energy and puts the robot back on the edge. The beetle on the way is jumped.
	game = _start(1, 3, {"difficulty": 1})
	game.feed(0, &"right", 1.0)
	var bug: Dictionary = game.world.foes[0]
	for index in 60 * 12:
		game.feed(0, &"a", 1.0 if absf(float(bug["x"]) - float(_hero(game, 0)["x"])) < 30.0 else 0.0)
		game.advance(STEP)
		if int(game.audio.played.get("hurt", 0)) > 0:
			break
	game.feed(0, &"right", 0.0)
	game.feed(0, &"a", 0.0)
	game.advance(0.2)
	var fallen := game.snapshot()["players"][0] as Dictionary
	_check("falling into a pit costs one energy and returns the robot to the edge it left", int(fallen["energy"]) == 3 and float(fallen["x"]) > 380.0 and float(fallen["x"]) < 406.0 and int(fallen["state"]) == World.H_NORMAL and is_equal_approx(float(fallen["y"]), 256.0))
	game.free()

func _test_lift_and_throw() -> void:
	var game := _start(1, 3)
	_walk_to(game, 0, 136.0)
	_tap(game, 0, &"b")
	_check("the lift button picks up the crate in front", bool(game.snapshot()["players"][0]["carrying"]) and int(game.audio.played.get("lift", 0)) == 1)
	game.advance(0.3)
	var crate: Dictionary = _hero(game, 0)["carry"]
	_check("the crate rides on the robot's head", is_equal_approx(float(crate["x"]), float(_hero(game, 0)["x"])) and is_equal_approx(float(crate["y"]), float(_hero(game, 0)["y"]) - World.HERO_TALL))
	# Carry it towards the beetle and throw when it is in range.
	var bug: Dictionary = game.world.foes[0]
	game.feed(0, &"right", 1.0)
	for index in 600:
		if float(bug["x"]) - float(_hero(game, 0)["x"]) < 110.0:
			break
		game.advance(STEP)
	game.feed(0, &"right", 0.0)
	_tap(game, 0, &"b")
	_check("pressing again throws it sideways", not bool(game.snapshot()["players"][0]["carrying"]) and int(crate["state"]) == World.O_THROWN and float(crate["vx"]) > 200.0)
	game.advance(1.0)
	var state := game.snapshot()
	_check("the thrown crate knocks the beetle out and breaks", state["foes_beaten"] == 1 and state["crates_broken"] == 1 and int(bug["state"]) != 0)
	_check("the thrower scores for the crate and the enemy", state["score"] == 110 and state["players"][0]["score"] == 110)
	_check("a broken crate drops what was hidden inside", game.world.pickups.any(func(pickup: Dictionary) -> bool: return not bool(pickup["float"]) and str(pickup["kind"]) == "gear"))
	_walk_to(game, 0, 420.0, 6.0)
	_check("walking over the gear collects it", game.snapshot()["gears"] >= 1 and int(game.audio.played.get("gear", 0)) >= 1 and int(game.snapshot()["score"]) >= 160)
	game.free()

func _test_throw_up_and_put_down() -> void:
	var game := _start(1, 3)
	_walk_to(game, 0, 136.0)
	_tap(game, 0, &"b")
	game.advance(0.3)
	var crate: Dictionary = _hero(game, 0)["carry"]
	# Hide and press: the crate is set down in front, whole.
	game.feed(0, &"down", 1.0)
	game.advance(0.2)
	_check("holding down under a crate hides the robot", bool(game.snapshot()["players"][0]["hiding"]))
	_tap(game, 0, &"b")
	game.feed(0, &"down", 0.0)
	game.advance(0.5)
	_check("pressing the button while hidden sets the crate down unbroken", not bool(game.snapshot()["players"][0]["carrying"]) and int(crate["state"]) == World.O_REST and not bool(crate["gone"]) and game.snapshot()["crates_broken"] == 0)
	_tap(game, 0, &"b")
	game.advance(0.3)
	_check("a crate that was set down can be lifted again", bool(game.snapshot()["players"][0]["carrying"]))
	var held: Dictionary = _hero(game, 0)["carry"]
	var x := float(held["x"])
	game.feed(0, &"up", 1.0)
	_tap(game, 0, &"b")
	game.feed(0, &"up", 0.0)
	_check("up and the button throws straight up", int(held["state"]) == World.O_THROWN and float(held["vy"]) < -300.0 and is_equal_approx(float(held["vx"]), 0.0))
	game.advance(0.4)
	_check("a crate thrown up rises well above the robot without drifting", float(held["y"]) < float(_hero(game, 0)["y"]) - 80.0 and is_equal_approx(float(held["x"]), x))
	_walk_to(game, 0, 60.0)
	game.advance(1.5)
	_check("and breaks when it comes down", game.snapshot()["crates_broken"] == 1)
	game.free()

func _test_hiding() -> void:
	# Without a crate the beetle hurts on touch.
	var bare := _start(1, 3)
	_walk_to(bare, 0, 200.0)
	bare.advance(6.0)
	_check("an enemy that touches a robot takes one energy", int(bare.snapshot()["players"][0]["energy"]) == 2 and int(bare.audio.played.get("hurt", 0)) == 1)
	bare.free()
	# Hidden under a crate it does not, and the beetle turns round.
	var game := _start(1, 3)
	_walk_to(game, 0, 152.0)
	_tap(game, 0, &"b")
	_walk_to(game, 0, 200.0)
	game.feed(0, &"down", 1.0)
	game.advance(8.0)
	var bug: Dictionary = game.world.foes[0]
	_check("hidden under a crate the robot is not hurt and the beetle turns away", int(game.snapshot()["players"][0]["energy"]) == 3 and bool(game.snapshot()["players"][0]["hiding"]) and int(bug["face"]) == 1 and float(bug["x"]) > float(_hero(game, 0)["x"]))
	game.free()

func _test_losing() -> void:
	var game := _start(1, 5, {"difficulty": 3})
	var results := _results(game)
	# Keep walking into the first pit until nothing is left: 3 energy x 3 lives, one continue, then the same again.
	game.feed(0, &"right", 1.0)
	var seen_continue := false
	for second in 240:
		game.advance(1.0)
		if game.snapshot()["phase"] == World.P_RETRY:
			seen_continue = true
		if not results.is_empty():
			break
	_check("running out of lives uses the continue and restarts the stage", seen_continue and int(game.audio.played.get("continue", 0)) == 1)
	_check("running out again with no continue left is a defeat", results.size() == 1 and results[0]["defeated"] == true and results[0]["cleared"] == false)
	if results.size() == 1:
		_check("the result counts the deaths and the continue", results[0]["deaths"] == 6 and results[0]["continues_used"] == 1 and results[0]["continues_left"] == 0 and results[0]["bosses_beaten"] == 0 and results[0]["stage"] == 1)
	_check("the music stops with the run", not game.audio.music_playing)
	game.free()

func _test_two_players() -> void:
	var game := _start(2, 9)
	var first := game.snapshot()
	_check("both robots start with lives", first["players"][0]["lives"] == 4 and first["players"][1]["lives"] == 4 and first["player_count"] == 2)
	game.feed(0, &"left", 1.0)
	game.feed(1, &"right", 1.0)
	game.advance(0.4)
	game.feed(0, &"left", 0.0)
	game.feed(1, &"right", 0.0)
	var moved := game.snapshot()
	_check("each robot follows its own player", float(moved["players"][0]["x"]) < float(first["players"][0]["x"]) and float(moved["players"][1]["x"]) > float(first["players"][1]["x"]))
	# Player one walks up to the partner and lifts it.
	_walk_to(game, 0, float(_hero(game, 1)["x"]) - 10.0)
	_tap(game, 0, &"b")
	game.advance(0.3)
	_check("a robot can lift its partner", int(_hero(game, 1)["state"]) == World.H_CARRIED and int(_hero(game, 0)["lifting"]) == 1)
	_check("the carried partner sits on the carrier's head", is_equal_approx(float(_hero(game, 1)["x"]), float(_hero(game, 0)["x"])) and is_equal_approx(float(_hero(game, 1)["y"]), float(_hero(game, 0)["y"]) - World.HERO_TALL))
	_tap(game, 1, &"a")
	game.advance(0.8)
	_check("the carried partner can hop off", int(_hero(game, 1)["state"]) == World.H_NORMAL and int(_hero(game, 0)["lifting"]) == -1)
	# Lift again and throw the partner at the beetle.
	_walk_to(game, 0, float(_hero(game, 1)["x"]) - 30.0)
	_walk_to(game, 0, float(_hero(game, 1)["x"]) - 10.0)
	_tap(game, 0, &"b")
	var bug: Dictionary = game.world.foes[0]
	game.feed(0, &"right", 1.0)
	for index in 900:
		if float(bug["x"]) - float(_hero(game, 0)["x"]) < 90.0:
			break
		game.advance(STEP)
	game.feed(0, &"right", 0.0)
	_tap(game, 0, &"b")
	_check("the partner can be thrown", int(_hero(game, 1)["state"]) == World.H_THROWN)
	game.advance(1.2)
	var after := game.snapshot()
	_check("a thrown partner knocks out the enemy it hits, unhurt", after["buddy_hits"] == 1 and after["foes_beaten"] == 1 and after["players"][1]["energy"] == 3 and int(_hero(game, 1)["state"]) == World.H_NORMAL)
	_check("the thrower gets the points and the total is the sum", after["players"][0]["score"] == 100 and after["score"] == int(after["players"][0]["score"]) + int(after["players"][1]["score"]))
	game.free()

func _test_join_and_leave() -> void:
	var game := _start(1, 4)
	_hold(game, 0, &"right", 0.5)
	_check("player two joins a run in progress", game.join(1))
	var joined := game.snapshot()
	_check("the newcomer appears beside the partner with full lives", joined["players"][1]["lives"] == 4 and joined["players"][1]["energy"] == 3 and absf(float(joined["players"][1]["x"]) - float(joined["players"][0]["x"])) < 1.0 and joined["player_count"] == 2)
	_hold(game, 1, &"left", 0.4)
	_check("and is driven by the second player's controls", float(game.snapshot()["players"][1]["x"]) < float(joined["players"][1]["x"]) - 20.0)
	# Leaving while carrying: the crate is let go, the robot disappears.
	_walk_to(game, 1, 136.0)
	_tap(game, 1, &"b")
	_check("the second robot can carry too", bool(game.snapshot()["players"][1]["carrying"]))
	_check("player two leaves", game.leave(1))
	var left := game.snapshot()
	_check("a robot that left drops its crate and is out, and is still reported", left["players"].size() == 2 and int(left["players"][1]["state"]) == World.H_OUT and left["players"][1]["lives"] == 0 and left["player_count"] == 1 and game.world.objects.all(func(object: Dictionary) -> bool: return int(object["state"]) != World.O_HELD))
	_hold(game, 0, &"right", 0.3)
	_check("the run goes on with one player", game.is_running() and int(game.snapshot()["phase"]) == World.P_PLAY)
	game.free()
	# Leaving and joining again must not refill lives: lose one first, leave, come back.
	game = _start(2, 4)
	game.feed(1, &"right", 1.0)
	for index in 60 * 30:
		game.advance(STEP)
		if int(game.snapshot()["players"][1]["lives"]) < 4 and int(_hero(game, 1)["state"]) == World.H_NORMAL:
			break
	game.feed(1, &"right", 0.0)
	var worn := int(game.snapshot()["players"][1]["lives"])
	_check("player two lost a life in the first pit", worn == 3)
	game.leave(1)
	game.join(1)
	_check("a robot that left and came back keeps the lives it left with", int(game.snapshot()["players"][1]["lives"]) == worn and int(game.snapshot()["players"][1]["energy"]) == 3 and int(_hero(game, 1)["state"]) == World.H_NORMAL)
	game.free()

func _test_lift_belt_and_door() -> void:
	# The pipe shaft's second flag stands by a lift that climbs twelve tiles. Run and jump onto it while it is still low.
	var game := _start(1, 8, {"stage": 2, "flag": 2, "difficulty": 1})
	var lift: Dictionary = game.world.lifts[0]
	var bottom := float(lift["y"])
	for index in 60 * 12:
		game.advance(STEP)
		if float(lift["dy"]) > 0.0 and float(lift["y"]) > bottom - 20.0:
			break
	_check("a lift travels on its own and comes back", float(lift["dy"]) > 0.0 and game.world.stage_time > 5.0)
	game.feed(0, &"right", 1.0)
	for index in 60 * 3:
		game.feed(0, &"a", 1.0 if float(_hero(game, 0)["x"]) > 200.0 else 0.0)
		game.advance(STEP)
		if float(_hero(game, 0)["x"]) > 250.0:
			break
	game.feed(0, &"right", 0.0)
	game.feed(0, &"a", 0.0)
	game.advance(2.5)
	var rider := _hero(game, 0)
	_check("a robot standing on a lift rides up with it", bool(rider["ground"]) and is_equal_approx(float(rider["y"]), float(lift["y"])) and float(rider["y"]) < bottom - 60.0 and int(rider["energy"]) == 4)
	game.free()
	# The foundry opens with a belt that carries whatever stands on it.
	game = _start(1, 8, {"stage": 3, "difficulty": 1})
	var bug: Dictionary = game.world.foes[0]
	game.feed(0, &"right", 1.0)
	for index in 60 * 10:
		game.feed(0, &"a", 1.0 if absf(float(bug["x"]) - float(_hero(game, 0)["x"])) < 30.0 else 0.0)
		game.advance(STEP)
		if float(_hero(game, 0)["x"]) > 330.0 and bool(_hero(game, 0)["ground"]):
			break
	game.feed(0, &"right", 0.0)
	game.feed(0, &"a", 0.0)
	game.advance(STEP)
	var before := float(_hero(game, 0)["x"])
	game.advance(0.15)
	_check("a belt carries a robot that stands still on it", float(_hero(game, 0)["x"]) > before + 4.0 and float(_hero(game, 0)["x"]) < before + 6.0)
	game.free()
	# From the foundry's last flag, run to the exit door.
	game = _start(1, 8, {"stage": 3, "flag": 4, "difficulty": 1})
	var score_before := int(game.snapshot()["score"])
	game.feed(0, &"right", 1.0)
	for index in 60 * 90:
		var hero := _hero(game, 0)
		var danger := false
		for foe: Dictionary in game.world.foes:
			var ahead := float(foe["x"]) - float(hero["x"])
			danger = danger or (int(foe["state"]) == 0 and ahead > -10.0 and ahead < 34.0 and absf(float(foe["y"]) - float(hero["y"])) < 30.0)
		game.feed(0, &"a", 1.0 if danger else 0.0)
		game.advance(STEP)
		if int(game.snapshot()["stage"]) != 3 or not game.is_running():
			break
	var after := game.snapshot()
	_check("reaching the exit door clears the stage and the next one begins", after["stage"] == 4 and int(game.audio.played.get("stage_clear", 0)) == 1 and int(after["score"]) >= score_before + 500 and after["bosses_beaten"] == 0)
	_check("the next stage starts with full energy and its own tune", after["players"][0]["energy"] == after["players"][0]["max_energy"] and game.audio.music_playing and int(game.audio.played.get("stage_start", 0)) == 2)
	game.free()

## Jump holding a direction until the robot has passed `until_x`, then let it come down.
func _hop(game: GameModule, slot: int, control: StringName, until_x: float) -> void:
	var hero := _hero(game, slot)
	game.feed(slot, &"a", 1.0)
	game.feed(slot, control, 1.0)
	for index in 120:
		game.advance(STEP)
		if (control == &"right" and float(hero["x"]) >= until_x) or (control == &"left" and float(hero["x"]) <= until_x):
			game.feed(slot, control, 0.0)
		if index > 10 and bool(hero["ground"]):
			break
	game.feed(slot, &"a", 0.0)
	game.feed(slot, control, 0.0)
	game.advance(STEP)

## From the control loft's second flag: up two shelves to the crate with the golden cog, throw it at the wall and walk into what falls out.
func _fetch_loft_cog(game: GameModule) -> void:
	_walk_to(game, 0, 1326.0)
	_hop(game, 0, &"right", 1368.0)
	_walk_to(game, 0, 1400.0)
	_hop(game, 0, &"right", 1452.0)
	_walk_to(game, 0, 1464.0)
	_tap(game, 0, &"b")
	game.advance(0.3)
	_tap(game, 0, &"b")
	game.advance(1.2)
	_walk_to(game, 0, 1512.0)
	game.advance(0.5)

func _test_golden_cog_counts_once() -> void:
	var game := _start(1, 6, {"stage": 4, "flag": 2, "difficulty": 3})
	_fetch_loft_cog(game)
	var found := game.snapshot()
	_check("the crate on the loft's high shelf hides the stage's golden cog", found["golden_cogs"] == 1 and int(found["score"]) >= 1000 and int(game.audio.played.get("cog", 0)) == 1)
	# Stand in the tacks until every life is gone and the continue puts the stage back.
	for index in 60 * 120:
		var x := float(_hero(game, 0)["x"])
		game.feed(0, &"left", 1.0 if x > 1030.0 else 0.0)
		game.feed(0, &"right", 1.0 if x < 1016.0 else 0.0)
		game.advance(STEP)
		if game.world.continues_used > 0 and game.world.phase == World.P_PLAY:
			break
	game.release_inputs()
	game.advance(STEP)
	_check("tacks wear a robot down to a continue, which restarts at the last flag", game.snapshot()["continues_used"] == 1 and game.snapshot()["deaths"] == 3 and absf(float(_hero(game, 0)["x"]) - 1284.0) < 1.0)
	_fetch_loft_cog(game)
	var again := game.snapshot()
	_check("after a continue the same crate holds plain gears: a stage's golden cog counts once", again["golden_cogs"] == 1 and again["gears"] == 3 and int(game.audio.played.get("cog", 0)) == 1)
	game.free()

# ---- bosses, fought through the controls ----

## Presses for one step of a boss fight: fetch something to throw, keep clear of the machine, throw when it lines up.
func _fight_step(game: GameModule, upwards: bool) -> void:
	var world: World = game.world
	var hero: Dictionary = world.heroes[0]
	var boss: Dictionary = world.boss
	var want_left := false
	var want_right := false
	var want_up := false
	var press := false
	var jump := false
	if int(hero["state"]) == World.H_NORMAL and not boss.is_empty():
		var x := float(hero["x"])
		var boss_x := float(boss["x"])
		if hero["carry"] == null:
			var best: Variant = null
			for object in world.objects:
				if int(object["state"]) == World.O_REST and absf(float(object["y"]) - float(hero["y"])) < 20.0 and (best == null or absf(float(object["x"]) - x) < absf(float(best["x"]) - x)):
					best = object
			if best != null:
				var dx := float(best["x"]) - x
				if absf(dx) > 10.0:
					want_right = dx > 0.0
					want_left = dx < 0.0
				else:
					want_right = dx > 0.0 and int(hero["face"]) < 0
					want_left = dx < 0.0 and int(hero["face"]) > 0
					press = not want_left and not want_right
		elif str(boss["kind"]) == "crane":
			var dx := boss_x - x
			var mode := str(boss["mode"])
			if mode == "stuck":
				# The claw is in the floor: face it and throw sideways.
				var facing_it := (dx > 0.0) == (int(hero["face"]) > 0)
				if not facing_it or absf(dx) > 120.0:
					want_right = dx > 0.0
					want_left = dx < 0.0
				else:
					press = true
			elif mode == "aim" and absf(dx) < 8.0:
				want_up = upwards
				press = upwards
			elif absf(dx) < 44.0:
				# Keep out from under it while it drops nuts and takes aim.
				want_left = dx > 0.0 and x > float(boss["left"]) + 30.0
				want_right = not want_left
		else:
			var dx := boss_x - x
			var facing_it := (dx > 0.0) == (int(hero["face"]) > 0)
			if not facing_it:
				want_right = dx > 0.0
				want_left = dx < 0.0
			elif absf(dx) > 150.0:
				want_right = dx > 0.0
				want_left = dx < 0.0
			elif str(boss["mode"]) == "spit" or str(boss["mode"]) == "inhale":
				press = true
		# Hop over a ramming machine.
		if str(boss["kind"]) == "vacuum" and str(boss["mode"]) == "charge" and absf(boss_x - x) < 60.0 and bool(hero["ground"]):
			jump = true
	game.feed(0, &"left", 1.0 if want_left else 0.0)
	game.feed(0, &"right", 1.0 if want_right else 0.0)
	game.feed(0, &"up", 1.0 if want_up else 0.0)
	game.feed(0, &"a", 1.0 if jump else 0.0)
	# Alternate so every press is a fresh one.
	game.feed(0, &"b", 1.0 if press and not game.input(0).is_down(&"b") else 0.0)
	game.advance(STEP)

func _test_first_boss() -> void:
	# Start at the last flag of the pipe shaft, just under the boss room, and climb in.
	var game := _start(1, 21, {"stage": 2, "flag": 4, "difficulty": 1})
	_check("the test start option puts the robot at the stage's last flag", game.snapshot()["stage"] == 2 and float(game.snapshot()["players"][0]["y"]) < 300.0 and not game.snapshot().has("boss_hp"))
	_walk_to(game, 0, 40.0)
	for jump in 2:
		_hold(game, 0, &"a", 0.5)
		game.advance(0.4)
	var entered := game.snapshot()
	_check("standing on the boss room floor starts the fight: bar, tune and locked camera", entered.has("boss_hp") and entered["boss_hp"] == entered["boss_max_hp"] and int(game.audio.played.get("boss_start", 0)) == 1 and game.audio.music_playing)
	game.advance(0.5)
	_check("the camera is locked on the room", is_equal_approx(float(game.snapshot()["camera_x"]), 16.0) and is_equal_approx(float(game.snapshot()["camera_y"]), 0.0))
	var steps := 0
	while game.is_running() and int(game.snapshot()["stage"]) == 2 and steps < 60 * 240:
		_fight_step(game, false)
		steps += 1
	var after := game.snapshot()
	_check("throwing its scrap and the chute's crates back beats the Dustmaw", after["bosses_beaten"] == 1 and int(game.audio.played.get("boss_hit", 0)) >= 4 and int(game.audio.played.get("boss_down", 0)) == 1)
	_check("beating the boss clears the stage and the next one begins", after["stage"] == 3 and not after.has("boss_hp") and int(after["score"]) >= 2500 and game.is_running())
	game.release_inputs()
	game.free()

func _test_last_boss_clears_the_game() -> void:
	var game := _start(1, 33, {"stage": 4, "flag": 4, "difficulty": 1})
	var results := _results(game)
	# From the flag the shelves go straight up into the room.
	for jump in 3:
		_hold(game, 0, &"a", 0.5)
		game.advance(0.4)
	_check("the last flag leads into the Overseer's room", game.snapshot().has("boss_hp"))
	var steps := 0
	while game.is_running() and steps < 60 * 300:
		_fight_step(game, true)
		steps += 1
	_check("throwing its nuts at the Overseer while its shutter is up wins the game", results.size() == 1 and results[0]["cleared"] == true and results[0]["defeated"] == false)
	if results.size() == 1:
		var result := results[0]
		_check("the result carries what the achievements read", result["bosses_beaten"] == 1 and result["stage"] == 4 and result["difficulty"] == 1 and result.has("continues_used") and result.has("golden_cogs") and result.has("buddy_hits") and result["player_count"] == 1 and int(result["score"]) >= 2500)
		_check("one player alone finished it, and the boss bar is gone from the result", not result.has("boss_hp") and result["players"][1]["lives"] == 0)
	game.free()

func _test_determinism() -> void:
	var states: Array = []
	for attempt in 2:
		var game := _start(2, 77)
		game.feed(0, &"right", 1.0)
		game.feed(1, &"right", 1.0)
		for second in 20:
			game.feed(0, &"a", 1.0 if second % 2 == 0 else 0.0)
			game.feed(1, &"b", 1.0 if second % 3 == 0 else 0.0)
			game.advance(1.0)
		states.append(game.snapshot())
		game.free()
	_check("the same seed and inputs give the same run", states[0] == states[1] and is_equal_approx(float(states[0]["elapsed"]), 20.0 + INTRO))
	var fights: Array = []
	for attempt in 2:
		var game := _start(1, 41, {"stage": 2, "flag": 4})
		_walk_to(game, 0, 40.0)
		for jump in 2:
			_hold(game, 0, &"a", 0.5)
			game.advance(0.4)
		for step in 60 * 20:
			_fight_step(game, false)
		game.release_inputs()
		fights.append(game.snapshot())
		game.free()
	_check("a boss fight replays exactly too, random scrap included", fights[0] == fights[1] and fights[0].has("boss_hp"))
	var other := _start(1, 42, {"stage": 2, "flag": 4})
	_walk_to(other, 0, 40.0)
	for jump in 2:
		_hold(other, 0, &"a", 0.5)
		other.advance(0.4)
	for step in 60 * 20:
		_fight_step(other, false)
	other.release_inputs()
	_check("another seed gives another fight", other.snapshot() != fights[0])
	other.free()

# ---- level data ----

## Cells a robot can stand in, by a cautious model of its jump: two tiles up, three tiles across a gap, any drop.
func _reachable(level: Dictionary) -> Dictionary:
	var width := int(level["w"])
	var height := int(level["h"])
	var tiles: PackedByteArray = level["tiles"]
	var tile := func(column: int, row: int) -> int:
		if column < 0 or column >= width:
			return Levels.SOLID
		if row < 0 or row >= height:
			return Levels.EMPTY
		return tiles[row * width + column]
	var solid := func(column: int, row: int) -> bool:
		var value: int = tile.call(column, row)
		return value == Levels.SOLID or value == Levels.BELT_LEFT or value == Levels.BELT_RIGHT
	var lift_cells := {}
	for lift: Dictionary in level["lifts"]:
		var from: Vector2 = lift["from"] / 16.0
		var to: Vector2 = lift["to"] / 16.0
		var cells := int(float(lift["w"]) / 16.0)
		for part in 33:
			var at := from.lerp(to, float(part) / 32.0)
			for column in cells:
				lift_cells[Vector2i(int(round(at.x)) + column, int(round(at.y)) - 1)] = true
	var stands := func(column: int, row: int) -> bool:
		if solid.call(column, row) or tile.call(column, row) == Levels.SPIKES:
			return false
		var under: int = tile.call(column, row + 1)
		return solid.call(column, row + 1) or under == Levels.SHELF or lift_cells.has(Vector2i(column, row))
	var spawn: Vector2 = level["spawn"]
	var start := Vector2i(int(spawn.x / 16.0), int(spawn.y / 16.0) - 1)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for dx in range(-4, 5):
			for row in range(cell.y - 2, height):
				var next := Vector2i(cell.x + dx, row)
				if seen.has(next) or not stands.call(next.x, next.y):
					continue
				var rise := cell.y - row
				if rise > 0 and absi(dx) > 3:
					continue
				if dx == 0 and (rise <= 0 or solid.call(next.x, next.y + 1)):
					continue
				var top := mini(cell.y, row)
				var blocked := false
				for column in range(mini(cell.x, next.x), maxi(cell.x, next.x) + 1):
					if solid.call(column, top) or solid.call(column, top - 1):
						blocked = true
				for between in range(top, row + 1):
					if solid.call(next.x, between):
						blocked = true
				if rise > 0 and (solid.call(cell.x, cell.y - 1) and solid.call(cell.x, cell.y - 2)):
					blocked = true
				if not blocked:
					seen[next] = true
					queue.append(next)
	return seen

func _test_stages_can_be_walked() -> void:
	for stage in Levels.COUNT:
		var level: Dictionary = Levels.new().build(stage)
		var seen := _reachable(level)
		var goal := Vector2i.ZERO
		if level["door"] is Vector2:
			goal = Vector2i(int((level["door"] as Vector2).x / 16.0), int((level["door"] as Vector2).y / 16.0) - 1)
		else:
			goal = Vector2i(int(float(level["boss"]["left"]) / 16.0) + 6, int(float(level["boss"]["floor"]) / 16.0) - 1)
		_check("stage %d: its end can be reached from its start on foot" % (stage + 1), seen.has(goal))
		var flags_ok := true
		for flag: Vector2 in level["flags"]:
			flags_ok = flags_ok and seen.has(Vector2i(int(flag.x / 16.0), int(flag.y / 16.0) - 1))
		_check("stage %d: every flag stands where a robot can get to" % (stage + 1), flags_ok and (level["flags"] as Array).size() >= 2)
		var grounded := true
		var cogs := 0
		for object: Dictionary in level["objects"]:
			var at: Vector2 = object["at"]
			var under: int = (level["tiles"] as PackedByteArray)[int(at.y / 16.0) * int(level["w"]) + int(at.x / 16.0)]
			var on_crate := (level["objects"] as Array).any(func(other: Dictionary) -> bool: return (other["at"] as Vector2) == at + Vector2(0, 16))
			grounded = grounded and (under != Levels.EMPTY or on_crate)
			if str(object["inside"]) == "cog":
				cogs += 1
				grounded = grounded and seen.has(Vector2i(int(at.x / 16.0), int(at.y / 16.0) - 1))
		_check("stage %d: every crate stands on something and exactly one, within reach, hides a golden cog" % (stage + 1), grounded and cogs == 1)
	var sizes: Array = []
	for stage in Levels.COUNT:
		var built: Dictionary = Levels.new().build(stage)
		sizes.append(maxi(int(built["w"]), int(built["h"])))
	_check("every stage is long enough for a few minutes of play: at least 120 tiles along its way", sizes.all(func(size: int) -> bool: return size >= 96) and sizes[0] >= 230 and sizes[1] >= 120 and sizes[2] >= 250 and (Levels.new().build(3)["flags"] as Array).size() >= 4)
	# The lifts of the two walking stages (the foundry's first one aside, which is jumped off at the top) dock flush with the ground at both ends, so no jump is needed to step on or off.
	var docked := true
	for pick: Array in [[0, 0], [0, 1], [2, 1]]:
		var with_lift: Dictionary = Levels.new().build(int(pick[0]))
		var lift: Dictionary = (with_lift["lifts"] as Array)[int(pick[1])]
		var from: Vector2 = lift["from"] / 16.0
		var to: Vector2 = (lift["to"] as Vector2) / 16.0
		var cells: PackedByteArray = with_lift["tiles"]
		var wide := int(with_lift["w"])
		var near := cells[int(from.y) * wide + int(from.x) - 1]
		var far := cells[int(to.y) * wide + int(to.x) + int(float(lift["w"]) / 16.0)]
		docked = docked and near != Levels.EMPTY and near != Levels.SPIKES and far != Levels.EMPTY and far != Levels.SPIKES
	_check("lifts between two banks dock flush with both", docked)
	_check("two stages end in a boss room and two at a door", not (Levels.new().build(1)["boss"] as Dictionary).is_empty() and not (Levels.new().build(3)["boss"] as Dictionary).is_empty() and Levels.new().build(0)["door"] is Vector2 and Levels.new().build(2)["door"] is Vector2)

func _test_art_and_sound() -> void:
	var game := _start(1, 1)
	var view: Node = game.get_node("View")
	_check("every picture the renderer draws from is loaded: both squirrels with their carry spots, the enemies, the bosses, the props, a ground texture and a far wall per stage", bool(view.art_ready()))
	_check("each squirrel has a run cycle and a carrying cycle of at least eight frames with their stride and footfalls, a standing loop, and frames for every other action", [0, 1].all(func(slot: int) -> bool: return int(view._counts[slot]["run"]) >= 8 and int(view._counts[slot]["carry_run"]) >= 8 and int(view._counts[slot]["idle"]) >= 4 and view.heroes[slot].animation_length("idle") > 0.5 and float(view._gaits[slot]["run"]["stride"]) > 8.0 and (view._gaits[slot]["run"]["steps"] as Array).size() == 2 and view.heroes[slot].has_frame("throw_1") and view.heroes[slot].has_frame("cheer_0")))
	_check("in every frame of standing and running with a load the crate rests on the paws above the squirrel's 14 pixel box, close to its own column", [0, 1].all(func(slot: int) -> bool: return ["carry", "carry_run"].all(func(move: String) -> bool: return range(int(view._counts[slot][move])).all(func(index: int) -> bool: return (view._holds[slot]["%s_%d" % [move, index]] as Vector2).y < -World.HERO_TALL - 4.0 and absf((view._holds[slot]["%s_%d" % [move, index]] as Vector2).x) < 3.5))))
	_check("a load being picked up starts low in front of the squirrel and ends above its head", [0, 1].all(func(slot: int) -> bool: return (view._holds[slot]["lift_0"] as Vector2).y > -World.HERO_TALL and (view._holds[slot]["lift_%d" % (int(view._counts[slot]["lift"]) - 1)] as Vector2).y < -World.HERO_TALL - 4.0))
	_check("every event the game can make a sound for has an effect defined", Main.HEARD.all(func(name: String) -> bool: return game.audio.has_sound(name)))
	_check("stage text exists in both languages and the English is in capitals", Texts.TEXT.values().all(func(entry: Dictionary) -> bool: return str(entry["zh"]) != "" and str(entry["en"]) != "" and str(entry["en"]).replace("%d", "") == str(entry["en"]).replace("%d", "").to_upper()))
	_check("two stage themes, a boss theme and three fanfares are registered", Sounds.TRACKS.keys().all(func(name: String) -> bool: return game.audio.has_track(name)) and Sounds.STINGERS.keys().all(func(name: String) -> bool: return game.audio.has_stinger(name)))
	_check("the workbench opens with the bright theme", game.audio.music_track == "theme_bench")
	game.free()
	var shaft := _start(1, 21, {"stage": 2, "flag": 4, "difficulty": 1})
	_check("the pipe shaft plays the darker theme", shaft.audio.music_track == "theme_shaft")
	_walk_to(shaft, 0, 40.0)
	for jump in 2:
		_hold(shaft, 0, &"a", 0.5)
		shaft.advance(0.4)
	_check("the boss room cross-fades to the boss theme", shaft.world.boss_fight and shaft.audio.music_track == "theme_boss")
	shaft.free()
	var lost := _start(1, 5, {"difficulty": 3})
	var ended := _results(lost)
	lost.feed(0, &"right", 1.0)
	for second in 240:
		lost.advance(1.0)
		if not ended.is_empty():
			break
	_check("a lost run ends on the defeat fanfare with the music gone", not ended.is_empty() and int(lost.audio.played.get("fanfare_lost", 0)) == 1 and not lost.audio.music_playing)
	lost.free()

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
