extends SceneTree

## Headless tests of Crate Crew. Runs are driven through the public surface of the module: start(), feed(), advance(), join(), leave() and snapshot(), with the autopilot of bot.gd standing in for a player where a whole level or the whole route is played. To test one rule at a time a test may clear a level's enemies and things and put down its own with the world's own add_object / Foes.create, then plays it with real inputs. An unlisted start option "level" (an index into Levels.LEVELS, from 1) begins a run at that level instead of the map.
## Run: make games-test GODOT=/path/to/godot

const Main := preload("res://games/crate_crew/main.gd")
const World := preload("res://games/crate_crew/world.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Foes := preload("res://games/crate_crew/foes.gd")
const Bosses := preload("res://games/crate_crew/bosses.gd")
const Bot := preload("res://games/crate_crew/bot.gd")
const Sounds := preload("res://games/crate_crew/sounds.gd")
const Texts := preload("res://games/crate_crew/texts.gd")

const STEP := GameModule.STEP
const INTRO := 1.4
const CONTROLS: Array[StringName] = [&"up", &"down", &"left", &"right", &"a", &"b"]

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_start_and_snapshot()
	_test_movement_feel()
	_test_lift_and_throw()
	_test_steel_drops_and_is_reused()
	_test_throw_up()
	_test_hide_and_throw_a_dizzy_enemy()
	_test_stomp()
	_test_partner_throw()
	_test_getting_in_each_others_way()
	_test_stacking()
	_test_hidden_items()
	_test_acorns_give_lives()
	_test_cracked_wall_and_bonus_room()
	_test_map_route_choice()
	_test_boss_phases_and_lumps()
	_test_lives_and_continues()
	_test_join_and_leave()
	_test_determinism()
	_test_every_level_with_real_inputs()
	_test_whole_routes()
	_test_losing_a_run()
	_test_art_and_sound()
	print("crate_crew_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- helpers ----

func _start(players: int, seed_value: int, options: Dictionary = {}) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": Vector2i(384, 216)})
	if options.has("level"):
		game.advance(INTRO)
	return game

## A level with nothing in it but its tiles, to try one rule at a time.
func _empty(game: GameModule) -> World:
	var world: World = game.world
	world.foes.clear()
	world.objects.clear()
	world.spawners.clear()
	world.pickups.clear()
	world.shots.clear()
	return world

func _hold(game: GameModule, slot: int, control: StringName, seconds: float) -> void:
	game.feed(slot, control, 1.0)
	game.advance(seconds)
	game.feed(slot, control, 0.0)

func _tap(game: GameModule, slot: int, control: StringName) -> void:
	game.feed(slot, control, 1.0)
	game.advance(STEP)
	game.feed(slot, control, 0.0)
	game.advance(STEP)

func _release(game: GameModule) -> void:
	for slot in 2:
		for control in CONTROLS:
			game.feed(slot, control, 0.0)

func _hero(game: GameModule, slot: int = 0) -> Dictionary:
	return game.world.heroes[slot]

func _foe(world: World, kind: String, x: float, y: float, facing: int = -1, reach: float = 4.0) -> Dictionary:
	var foe := Foes.create({"kind": kind, "at": Vector2(x, y), "face": facing, "reach": reach})
	world.foes.append(foe)
	return foe

## Let the autopilots play for up to `limit` seconds or until `done` says so. Returns the seconds played.
func _play(game: GameModule, bots: Array, limit: float, done: Callable) -> float:
	var played := 0.0
	while played < limit and not done.call():
		for bot in bots:
			var want: Dictionary = bot.controls(game.world)
			for control in CONTROLS:
				game.feed(bot.slot, control, 1.0 if want.has(String(control)) else 0.0)
		game.advance(STEP)
		played += STEP
	_release(game)
	return played

func _results(game: GameModule) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	return results

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + label)

# ---- the tests ----

func _test_start_and_snapshot() -> void:
	var game := _start(1, 7)
	var state := game.snapshot()
	_check("a run opens on the map", int(state["phase"]) == World.P_MAP and str(state["node"]) == "home")
	_check("snapshot has the HUD fields", state.has("level") and state.has("levels") and state.has("acorns") and state.has("acorns_per_life"))
	_check("level counts one route of twelve", int(state["level"]) == 1 and int(state["levels"]) == Levels.ROUTE_LENGTH)
	_check("players has both seats", (state["players"] as Array).size() == 2)
	var first: Dictionary = state["players"][0]
	_check("player one has hearts and lives", int(first["hearts"]) == 3 and int(first["max_hearts"]) == 3 and int(first["lives"]) == 3)
	_check("seat two is empty", int(state["players"][1]["lives"]) == 0)
	_check("no boss bar on the map", not state.has("boss_hp"))
	game.free()
	game = _start(1, 7, {"difficulty": 1})
	_check("easy gives four hearts and five lives", int(game.snapshot()["players"][0]["hearts"]) == 4 and int(game.snapshot()["players"][0]["lives"]) == 5)
	game.free()

func _test_movement_feel() -> void:
	var game := _start(1, 3, {"level": 1})
	_empty(game)
	var hero := _hero(game)
	game.feed(0, &"right", 1.0)
	var steps := 0
	while float(hero["vx"]) < World.RUN_SPEED and steps < 60:
		game.advance(STEP)
		steps += 1
	_check("full running speed within five steps (%d)" % steps, steps <= 5)
	_check("running speed is %d px/s" % int(World.RUN_SPEED), is_equal_approx(float(hero["vx"]), World.RUN_SPEED))
	game.feed(0, &"right", 0.0)
	steps = 0
	while float(hero["vx"]) > 0.0 and steps < 60:
		game.advance(STEP)
		steps += 1
	_check("stops within four steps (%d)" % steps, steps <= 4)
	# A held jump: how high, how long up and how long down.
	var ground := float(hero["y"])
	game.feed(0, &"a", 1.0)
	var top := ground
	var up := 0
	var down := 0
	for index in 120:
		game.advance(STEP)
		var y := float(hero["y"])
		if float(hero["vy"]) < 0.0:
			up += 1
		elif not bool(hero["ground"]):
			down += 1
		top = minf(top, y)
		if bool(hero["ground"]) and index > 2:
			break
	game.feed(0, &"a", 0.0)
	var height := ground - top
	_check("a full jump is about two and a half cells (%.1f px)" % height, height > 34.0 and height < 42.0)
	_check("it is short: in the air under half a second (%d steps)" % (up + down), up + down <= 30)
	_check("it falls faster than it rises (%d down, %d up)" % [down, up], down < up)
	# A tap is a hop.
	game.advance(0.2)
	ground = float(hero["y"])
	game.feed(0, &"a", 1.0)
	game.advance(STEP)
	game.feed(0, &"a", 0.0)
	top = ground
	for index in 60:
		game.advance(STEP)
		top = minf(top, float(hero["y"]))
	_check("a tapped jump is a low hop (%.1f px)" % (ground - top), ground - top < 18.0)
	# Control the moment it lands: running right, it can turn left on the very first step on the ground.
	game.feed(0, &"right", 1.0)
	game.feed(0, &"a", 1.0)
	game.advance(STEP * 3)
	game.feed(0, &"a", 0.0)
	while not bool(hero["ground"]):
		game.advance(STEP)
	game.feed(0, &"right", 0.0)
	game.feed(0, &"left", 1.0)
	game.advance(STEP * 3)
	_check("turns at once after landing (vx %.0f)" % float(hero["vx"]), float(hero["vx"]) < 0.0)
	_release(game)
	game.advance(0.3)
	# Carrying, the jump still clears two cells.
	var world: World = game.world
	world.add_object("wood", float(hero["x"]) + 14.0 * float(int(hero["face"])), float(hero["y"]))
	_tap(game, 0, &"b")
	game.advance(0.2)
	_check("lifted the crate", hero["carry"] != null)
	ground = float(hero["y"])
	game.feed(0, &"a", 1.0)
	top = ground
	for index in 50:
		game.advance(STEP)
		top = minf(top, float(hero["y"]))
	game.feed(0, &"a", 0.0)
	_check("a carrying jump clears two cells (%.1f px)" % (ground - top), ground - top > 33.0)
	game.free()

func _test_lift_and_throw() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	var x := float(hero["x"])
	var y := float(hero["y"])
	var crate := world.add_object("wood", x + 14.0, y)
	var ant := _foe(world, "ant", x + 150.0, y, -1)
	_tap(game, 0, &"b")
	_check("B lifts the crate in front", is_same(hero["carry"], crate) and int(crate["state"]) == World.O_HELD)
	game.advance(0.15)
	_tap(game, 0, &"b")
	_check("B again throws it", int(crate["state"]) == World.O_THROWN)
	var level := float(crate["y"])
	var straight := true
	for index in 60:
		if bool(crate["gone"]) or int(crate["state"]) != World.O_THROWN:
			break
		straight = straight and is_equal_approx(float(crate["y"]), level)
		game.advance(STEP)
	_check("a thrown crate flies in a straight line", straight)
	_check("one hit knocks the ant out", int(ant["state"]) == Foes.KNOCKED_OUT)
	_check("the wooden crate broke on it", bool(crate["gone"]) and world.crates_broken == 1)
	_check("the knockout counts", int(game.snapshot()["foes_beaten"]) == 1 and int(game.snapshot()["score"]) > 0)
	# Every kind of enemy goes down to one throw.
	var everyone := true
	for kind: String in Foes.KINDS:
		world.foes.clear()
		world.objects.clear()
		var thing := world.add_object("apple", float(hero["x"]) + 14.0 * float(int(hero["face"])), float(hero["y"]))
		var target := _foe(world, kind, float(hero["x"]) + 90.0 * float(int(hero["face"])), float(hero["y"]) - (14.0 if kind == "plane" else 0.0), -int(hero["face"]), 0.0)
		if kind in ["slime"]:
			target["mode"] = "walk"
		_tap(game, 0, &"b")
		game.advance(0.12)
		_tap(game, 0, &"b")
		game.advance(0.6)
		if int(target["state"]) != Foes.KNOCKED_OUT:
			everyone = false
			print("  not knocked out by one throw: " + kind)
		game.advance(0.4)
		hero["hearts"] = 3
	_check("every enemy kind is knocked out by one throw", everyone)
	game.free()

func _test_steel_drops_and_is_reused() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	var steel := world.add_object("steel", float(hero["x"]) + 14.0, float(hero["y"]))
	var ant := _foe(world, "ant", float(hero["x"]) + 120.0, float(hero["y"]), -1)
	_tap(game, 0, &"b")
	game.advance(0.12)
	_tap(game, 0, &"b")
	game.advance(1.0)
	_check("steel knocks the ant out", int(ant["state"]) == Foes.KNOCKED_OUT)
	_check("steel does not break: it drops and lies there", not bool(steel["gone"]) and int(steel["state"]) == World.O_REST and steel in world.objects)
	game.free()

func _test_throw_up() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	world.add_object("wood", float(hero["x"]) + 14.0, float(hero["y"]))
	_tap(game, 0, &"b")
	game.advance(0.12)
	var fly := _foe(world, "fly", float(hero["x"]), float(hero["y"]) - 70.0, 1, 0.0)
	fly["cool"] = 9.0
	game.feed(0, &"up", 1.0)
	_tap(game, 0, &"b")
	game.advance(0.4)
	game.feed(0, &"up", 0.0)
	_check("up and throw hits the fly overhead", int(fly["state"]) == Foes.KNOCKED_OUT)
	game.free()

func _test_hide_and_throw_a_dizzy_enemy() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	world.add_object("wood", float(hero["x"]) + 14.0, float(hero["y"]))
	_tap(game, 0, &"b")
	game.advance(0.12)
	var ant := _foe(world, "ant", float(hero["x"]) + 60.0, float(hero["y"]), -1)
	game.feed(0, &"down", 1.0)
	var hidden := false
	for index in 150:
		game.advance(STEP)
		hidden = hidden or bool(hero["hide"])
		if int(ant["state"]) == Foes.STUNNED:
			break
	_check("holding down with a crate hides under it", hidden)
	_check("the ant that ran into the crate bounced off dizzy", int(ant["state"]) == Foes.STUNNED)
	_check("the hidden squirrel was not hurt", int(hero["hearts"]) == 3)
	game.feed(0, &"down", 0.0)
	# Throw the crate away behind, turn and pick the dizzy ant up.
	game.feed(0, &"left", 1.0)
	game.advance(STEP * 2)
	game.feed(0, &"left", 0.0)
	_tap(game, 0, &"b")
	game.advance(0.1)
	game.feed(0, &"right", 1.0)
	game.advance(STEP * 2)
	game.feed(0, &"right", 0.0)
	if absf(float(ant["x"]) - float(hero["x"])) > 18.0:
		game.feed(0, &"right", 1.0)
		for index in 30:
			if absf(float(ant["x"]) - float(hero["x"])) < 16.0:
				break
			game.advance(STEP)
		game.feed(0, &"right", 0.0)
	_tap(game, 0, &"b")
	var carried: Variant = hero["carry"]
	_check("a dizzy enemy can be lifted", carried is Dictionary and str((carried as Dictionary)["kind"]) == "foe")
	var other := _foe(world, "ant", float(hero["x"]) + 120.0, float(hero["y"]), -1)
	game.advance(0.12)
	_tap(game, 0, &"b")
	game.advance(0.8)
	_check("thrown, it knocks the other ant out", int(other["state"]) == Foes.KNOCKED_OUT)
	_check("both count as beaten", world.foes_beaten >= 2)
	game.free()

func _test_stomp() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	var ant := _foe(world, "ant", float(hero["x"]) + 20.0, float(hero["y"]), -1)
	ant["vx"] = 0.0
	game.feed(0, &"a", 1.0)
	game.feed(0, &"right", 1.0)
	game.advance(STEP * 4)
	game.feed(0, &"right", 0.0)
	for index in 60:
		game.advance(STEP)
		if int(ant["state"]) != Foes.ALIVE:
			break
	game.feed(0, &"a", 0.0)
	_check("landing on an ant leaves it dizzy", int(ant["state"]) == Foes.STUNNED)
	_check("and the squirrel bounces off unhurt", int(hero["hearts"]) == 3)
	game.free()

func _test_partner_throw() -> void:
	var game := _start(2, 3, {"level": 1})
	var world := _empty(game)
	var fenn := _hero(game, 0)
	var tug := _hero(game, 1)
	tug["x"] = float(fenn["x"]) + 12.0
	fenn["face"] = 1
	game.advance(STEP)
	_tap(game, 0, &"b")
	_check("B next to the partner lifts the partner", int(tug["state"]) == World.H_CARRIED and int(fenn["lifting"]) == 1)
	var ant := _foe(world, "ant", float(fenn["x"]) + 110.0, float(fenn["y"]), -1)
	game.advance(0.12)
	_tap(game, 0, &"b")
	_check("B again throws the partner", int(tug["state"]) == World.H_THROWN)
	for index in 90:
		game.advance(STEP)
		if int(ant["state"]) == Foes.KNOCKED_OUT:
			break
	_check("the thrown partner knocks the ant out", int(ant["state"]) == Foes.KNOCKED_OUT)
	_check("the thrown partner is not hurt", int(tug["hearts"]) == 3)
	_check("the buddy hit counts", int(game.snapshot()["buddy_hits"]) == 1)
	game.advance(1.0)
	_check("and lands on its feet", int(tug["state"]) == World.H_NORMAL and bool(tug["ground"]))
	# A carried partner hops off with jump; thrown up, a partner flies higher than any jump.
	tug["x"] = float(fenn["x"]) + 12.0
	tug["y"] = float(fenn["y"])
	fenn["face"] = 1
	game.advance(0.3)
	_tap(game, 0, &"b")
	_tap(game, 1, &"a")
	_check("a carried partner hops off with jump", int(tug["state"]) == World.H_NORMAL)
	game.advance(0.8)
	tug["x"] = float(fenn["x"]) + 12.0
	game.advance(0.2)
	_tap(game, 0, &"b")
	game.advance(0.12)
	var ground := float(fenn["y"])
	game.feed(0, &"up", 1.0)
	_tap(game, 0, &"b")
	game.feed(0, &"up", 0.0)
	var top := ground
	for index in 60:
		game.advance(STEP)
		top = minf(top, float(tug["y"]))
	_check("thrown up, the partner rises over four cells (%.0f px)" % (ground - top), ground - top > 64.0)
	game.free()

func _test_getting_in_each_others_way() -> void:
	var game := _start(2, 3, {"level": 1})
	var world := _empty(game)
	var fenn := _hero(game, 0)
	var tug := _hero(game, 1)
	tug["x"] = float(fenn["x"]) + 30.0
	game.advance(STEP)
	game.feed(0, &"right", 1.0)
	game.advance(0.6)
	game.feed(0, &"right", 0.0)
	_check("one squirrel cannot walk through the other", float(fenn["x"]) < float(tug["x"]))
	# A crate thrown into the partner knocks it back for a moment, without a heart lost.
	tug["x"] = float(fenn["x"]) + 60.0
	fenn["face"] = 1
	world.add_object("wood", float(fenn["x"]) + 14.0, float(fenn["y"]))
	game.advance(0.3)
	_tap(game, 0, &"b")
	game.advance(0.12)
	_tap(game, 0, &"b")
	game.advance(0.3)
	_check("a crate thrown into the partner makes it reel", float(tug["stun"]) > 0.0 or float(tug["x"]) > float(fenn["x"]) + 62.0)
	_check("but it loses no heart", int(tug["hearts"]) == 3)
	game.free()

func _test_stacking() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	hero["face"] = 1
	var first := world.add_object("wood", float(hero["x"]) - 14.0, float(hero["y"]))
	var second := world.add_object("wood", float(hero["x"]) - 40.0, float(hero["y"]))
	game.advance(STEP)
	# Lift the crate behind, turn, set it down in front.
	game.feed(0, &"left", 1.0)
	game.advance(STEP)
	game.feed(0, &"left", 0.0)
	_tap(game, 0, &"b")
	game.advance(0.12)
	game.feed(0, &"right", 1.0)
	game.advance(STEP * 2)
	game.feed(0, &"right", 0.0)
	game.feed(0, &"down", 1.0)
	_tap(game, 0, &"b")
	game.feed(0, &"down", 0.0)
	_check("down and B sets the crate down in front", int(first["state"]) == World.O_REST and float(first["x"]) > float(hero["x"]))
	var base_y := float(first["y"])
	# Fetch the other crate and set it on top of the first.
	game.feed(0, &"left", 1.0)
	for index in 120:
		if absf(float(second["x"]) - float(hero["x"])) < 18.0:
			break
		game.advance(STEP)
	game.feed(0, &"left", 0.0)
	game.advance(0.12)
	_tap(game, 0, &"b")
	_check("picked up the second crate", is_same(hero["carry"], second))
	game.advance(0.12)
	game.feed(0, &"right", 1.0)
	for index in 120:
		if absf(float(first["x"]) - float(hero["x"])) < 22.0:
			break
		game.advance(STEP)
	game.feed(0, &"right", 0.0)
	game.advance(0.1)
	game.feed(0, &"down", 1.0)
	_tap(game, 0, &"b")
	game.feed(0, &"down", 0.0)
	game.advance(0.3)
	_check("the second crate stands on the first", absf(float(second["x"]) - float(first["x"])) < 1.0 and is_equal_approx(float(second["y"]), base_y - 16.0))
	_check("the stack counts", world.stacks >= 1)
	# The stack is a step: from beside it, one jump lands on the top crate.
	game.feed(0, &"right", 1.0)
	game.feed(0, &"a", 1.0)
	game.advance(0.12)
	game.feed(0, &"right", 0.0)
	game.advance(0.4)
	_release(game)
	game.advance(0.3)
	_check("a squirrel can climb the stack (stands %.0f px up)" % (base_y - float(hero["y"])), base_y - float(hero["y"]) >= 31.0)
	game.free()

func _test_hidden_items() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	hero["hearts"] = 2
	hero["face"] = 1
	for inside: String in ["heart", "golden", "acorns", "ant"]:
		world.add_object("wood", float(hero["x"]) + 14.0, float(hero["y"]), inside)
		_tap(game, 0, &"b")
		game.advance(0.12)
		# Thrown into the wall behind: turn and throw.
		game.feed(0, &"left", 1.0)
		game.advance(STEP * 2)
		game.feed(0, &"left", 0.0)
		_tap(game, 0, &"b")
		game.advance(0.6)
		if inside == "ant":
			var out := false
			for foe in world.foes:
				out = out or str(foe["kind"]) == "ant"
			_check("a crate can hide an enemy that jumps out", out)
			world.foes.clear()
			continue
		var found := false
		for pickup in world.pickups:
			found = found or (str(pickup["kind"]) == ("acorn" if inside == "acorns" else inside))
		_check("a crate with %s lets it out when it breaks" % inside, found)
		# Walk over what came out.
		for index in 3:
			for pickup in world.pickups:
				hero["x"] = float(pickup["x"])
				game.advance(0.05)
		game.advance(0.3)
		hero["x"] = 56.0
		hero["face"] = 1
		game.advance(0.1)
	_check("the heart gave a heart back", int(hero["hearts"]) == 3)
	_check("the golden acorn gave a life", int(hero["lives"]) == 4)
	_check("the acorns were counted", world.acorns_total >= 3)
	game.free()

func _test_acorns_give_lives() -> void:
	var game := _start(1, 3, {"level": 1})
	var world := _empty(game)
	var hero := _hero(game)
	var lives := int(hero["lives"])
	for index in World.ACORNS_PER_LIFE:
		world.pickups.append({"kind": "acorn", "x": float(hero["x"]) + 8.0 + float(index) * 3.0, "y": float(hero["y"]) - 4.0, "vx": 0.0, "vy": 0.0, "float": true, "time": 0.0, "gone": false})
	game.feed(0, &"right", 1.0)
	game.advance(2.0)
	game.feed(0, &"right", 0.0)
	_check("fifty acorns give an extra life", int(hero["lives"]) == lives + 1)
	_check("and the count starts again", int(game.snapshot()["acorns"]) == 0 and int(game.snapshot()["acorns_total"]) == World.ACORNS_PER_LIFE)
	game.free()

func _test_cracked_wall_and_bonus_room() -> void:
	# The bread bin in level 1 has a cracked panel: a crate thrown at it opens the way to a burrow.
	var game := _start(1, 3, {"level": 1})
	var world: World = game.world
	var crack := Vector2i(158, 14)
	_check("the cracked panel is there and solid", world.tile_at(crack.x, crack.y) == Levels.CRACK and World.is_solid(Levels.CRACK))
	_empty(game)
	var hero := _hero(game)
	hero["x"] = 152.0 * 16.0 + 4.0
	hero["y"] = 15.0 * 16.0
	hero["face"] = 1
	game.advance(0.6)
	world.add_object("wood", float(hero["x"]) + 14.0, float(hero["y"]))
	_tap(game, 0, &"b")
	game.advance(0.12)
	_tap(game, 0, &"b")
	game.advance(0.6)
	_check("a throw breaks the cracked panel", world.tile_at(crack.x, crack.y) == Levels.EMPTY)
	game.feed(0, &"right", 1.0)
	for index in 120:
		if float(hero["x"]) >= 159.0 * 16.0 + 6.0:
			break
		game.advance(STEP)
	game.feed(0, &"right", 0.0)
	game.advance(0.1)
	_tap(game, 0, &"down")
	game.advance(0.1)
	_check("down in the burrow leads to the bonus room", world.zone_at(Vector2(float(hero["x"]), float(hero["y"]) - 4.0)).has_area())
	_check("the secret counts once", int(game.snapshot()["secrets"]) == 1)
	var golden := false
	for pickup: Dictionary in world.level["pickups"]:
		golden = golden or (str(pickup["kind"]) == "golden" and world.zone_at(pickup["at"]).has_area())
	_check("the bonus room holds a golden acorn", golden)
	game.free()

func _test_map_route_choice() -> void:
	var game := _start(1, 9)
	var world: World = game.world
	_check("from the stump the only way is the first kitchen level", world.map_choices() == ["k1"])
	_tap(game, 0, &"a")
	game.advance(1.0)
	_check("jump on the map walks there and starts it", world.level_id == "k1" and world.phase != World.P_MAP)
	_check("a level start plays its place's music", game.audio.music_track == "kitchen")
	var bot := Bot.new(0)
	_play(game, [bot], 240.0, func() -> bool: return world.phase == World.P_MAP)
	_check("clearing a level returns to the map", world.phase == World.P_MAP and world.node == "k1")
	_check("the map offers both branches", world.map_choices() == ["k2", "k3"])
	_check("the HUD shows the next level number", int(game.snapshot()["level"]) == 2)
	_check("the map plays the map tune", game.audio.music_track == "map")
	game.advance(0.4)
	_tap(game, 0, &"down")
	_check("down moves the marker to the lower branch", world.cursor == "k3")
	_tap(game, 0, &"up")
	_check("up moves it to the upper branch", world.cursor == "k2")
	_tap(game, 0, &"down")
	game.advance(0.8)
	_tap(game, 0, &"a")
	game.advance(0.2)
	_check("jump starts the branch the marker is on", world.level_id == "k3")
	game.free()

func _test_boss_phases_and_lumps() -> void:
	var game := _start(1, 5, {"level": 4})
	var world: World = game.world
	var boss: Dictionary = world.boss
	_check("the toaster is in its room", str(boss["kind"]) == "toaster" and game.snapshot().has("boss_hp"))
	game.advance(1.6)
	# A crate is no use against it.
	var hero := _hero(game)
	hero["face"] = 1
	world.add_object("wood", float(hero["x"]) + 14.0, float(hero["y"]))
	var hp := int(boss["hp"])
	_tap(game, 0, &"b")
	game.advance(0.12)
	_tap(game, 0, &"b")
	game.advance(1.0)
	_check("an ordinary crate does not hurt a boss", int(boss["hp"]) == hp)
	var phases := {}
	var seen := {"lumps": false}
	var bot := Bot.new(0)
	_play(game, [bot], 240.0, func() -> bool:
		phases[int(boss["phase"])] = true
		for object in world.objects:
			if bool(object["special"]):
				seen["lumps"] = true
		return world.phase != World.P_PLAY)
	_check("the toaster drops toast that can be picked up", bool(seen["lumps"]))
	_check("the fight goes through three phases", phases.size() == 3)
	_check("its own toast thrown back beats it", world.bosses_beaten == 1 and world.cleared.has("kb"))
	game.free()
	# The other three bosses with the same autopilot.
	for pick in [8, 12, 16]:
		game = _start(1, 5, {"level": pick})
		world = game.world
		var kind := str(world.boss["kind"])
		bot = Bot.new(0)
		var phases_seen := {}
		var start_boss: Dictionary = world.boss
		_play(game, [bot], 300.0, func() -> bool:
			phases_seen[int(start_boss["phase"])] = true
			return world.cleared.has(world.level_id) or world.phase == World.P_LOST)
		_check("the %s is beaten through three phases" % kind, world.bosses_beaten == 1 and phases_seen.size() == 3)
		game.free()

func _test_lives_and_continues() -> void:
	var game := _start(1, 3, {"level": 1, "difficulty": 3})
	var world := _empty(game)
	var hero := _hero(game)
	var lives := int(hero["lives"])
	_check("hard: three hearts, two lives, one continue", int(hero["hearts"]) == 3 and lives == 2 and world.continues_left == 1)
	var ant := _foe(world, "ant", float(hero["x"]) + 30.0, float(hero["y"]), -1)
	game.advance(1.0)
	_check("an enemy's touch takes a heart", int(hero["hearts"]) == 2)
	world.foes.clear()
	# Walking into the first gap again and again: each fall costs a heart, three a life.
	game.feed(0, &"right", 1.0)
	var events := 0
	for index in 60 * 40:
		game.advance(STEP)
		if world.phase == World.P_RETRY:
			break
	game.feed(0, &"right", 0.0)
	_check("losing every life uses a continue", world.phase == World.P_RETRY)
	game.advance(3.0)
	_check("after a continue the level starts again with full lives", world.phase != World.P_RETRY and int(hero["lives"]) == lives and world.continues_used == 1 and world.continues_left == 0)
	_check("deaths are counted", world.deaths == lives)
	game.free()

func _test_join_and_leave() -> void:
	var game := _start(1, 3, {"level": 1})
	var world: World = game.world
	game.feed(0, &"right", 1.0)
	game.advance(0.5)
	game.feed(0, &"right", 0.0)
	game.join(1)
	game.advance(STEP)
	var tug := _hero(game, 1)
	_check("a joining player appears beside the partner", int(tug["state"]) == World.H_NORMAL and absf(float(tug["x"]) - float(_hero(game)["x"])) < 24.0)
	_check("with full lives", int(game.snapshot()["players"][1]["lives"]) == int(world.rules["lives"]))
	tug["lives"] = 1
	game.leave(1)
	game.advance(STEP)
	_check("a leaving player's squirrel disappears", int(tug["state"]) == World.H_OUT and (game.snapshot()["players"] as Array).size() == 2)
	game.join(1)
	game.advance(STEP)
	_check("coming back keeps the lives it left with", int(tug["lives"]) == 1)
	game.free()

func _test_determinism() -> void:
	var a := _start(2, 42, {"level": 3})
	var b := _start(2, 42, {"level": 3})
	var bots_a := [Bot.new(0), Bot.new(1)]
	var bots_b := [Bot.new(0), Bot.new(1)]
	_play(a, bots_a, 25.0, func() -> bool: return false)
	_play(b, bots_b, 25.0, func() -> bool: return false)
	var same := str(a.snapshot()) == str(b.snapshot())
	var objects_a := []
	var objects_b := []
	for object in a.world.objects:
		objects_a.append([object["kind"], snappedf(float(object["x"]), 0.001), snappedf(float(object["y"]), 0.001)])
	for object in b.world.objects:
		objects_b.append([object["kind"], snappedf(float(object["x"]), 0.001), snappedf(float(object["y"]), 0.001)])
	_check("same seed and inputs give the same snapshot", same)
	_check("and the same world", objects_a == objects_b and a.world.foes.size() == b.world.foes.size())
	a.free()
	b.free()

func _test_every_level_with_real_inputs() -> void:
	for index in Levels.LEVELS.size():
		var game := _start(1, 11, {"level": index + 1})
		var world: World = game.world
		var id: String = world.level_id
		var bot := Bot.new(0)
		var seconds := _play(game, [bot], 300.0, func() -> bool: return world.cleared.has(id) or world.phase == World.P_LOST)
		_check("level %s (%s) is cleared by playing it (%.0f s)" % [id, Texts.of(id, "en"), seconds], world.cleared.has(id))
		game.free()

func _test_whole_routes() -> void:
	for branch in 2:
		var game := _start(2, 13 + branch)
		var results := _results(game)
		var world: World = game.world
		var bots := [Bot.new(0, branch), Bot.new(1, branch)]
		var seconds := _play(game, bots, 60.0 * 40.0, func() -> bool: return not results.is_empty())
		var won := not results.is_empty() and bool(results[0]["cleared"])
		_check("route %d: two players win the whole run (%.0f s)" % [branch, seconds], won)
		if won:
			var result := results[0]
			_check("route %d took twelve levels and four bosses" % branch, world.route.size() == Levels.ROUTE_LENGTH and int(result["bosses_beaten"]) == 4)
			var expected := ["k1", "k2" if branch == 0 else "k3", "kb", "t1", "t2" if branch == 0 else "t3", "tb", "s1", "s2" if branch == 0 else "s3", "sb", "r1", "r2" if branch == 0 else "r3", "rb"]
			_check("route %d went the way that was picked" % branch, world.route == expected)
			_check("the last fanfare played", game.audio.played.get("victory", 0) == 1)
		game.free()

func _test_losing_a_run() -> void:
	var game := _start(1, 3, {"difficulty": 3})
	var results := _results(game)
	_tap(game, 0, &"a")
	game.advance(2.0)
	# A careless player: runs right and only jumps when something stops it, so it runs into the first gap every time.
	var hero := _hero(game)
	var blocked := 0
	game.feed(0, &"right", 1.0)
	for index in 60 * 180:
		blocked = blocked + 1 if bool(hero["ground"]) and absf(float(hero["vx"])) < 1.0 and int(hero["state"]) == World.H_NORMAL else 0
		game.feed(0, &"a", 1.0 if blocked > 4 and blocked < 8 else 0.0)
		game.advance(STEP)
		if not results.is_empty():
			break
	_release(game)
	_check("a run with no lives and no continues left is lost", not results.is_empty() and bool(results[0]["defeated"]))
	if not results.is_empty():
		_check("the lost run counts its continue and deaths", int(results[0]["continues_used"]) == 1 and int(results[0]["deaths"]) == 4)
	_check("the game over jingle played", game.audio.played.get("gameover", 0) == 1)
	game.free()

func _test_art_and_sound() -> void:
	var game := _start(1, 3)
	_check("every picture the game draws loaded", game._view.art_ready())
	var hooks := true
	for track in ["title", "map", "kitchen", "toyshop", "sewer", "treehouse", "boss"]:
		hooks = hooks and game.audio.has_track(track)
	_check("every music hook has a track", hooks)
	_check("the first map plays the title hook", game.audio.music_track == "title")
	game.free()
	game = _start(1, 3, {"level": 9})
	_check("the sewer plays the sewer hook", game.audio.music_track == "sewer")
	game.free()
	game = _start(1, 3, {"level": 16})
	_check("a boss room plays the boss hook", game.audio.music_track == "boss")
	game.free()
	var missing := []
	for key: String in Texts.TEXT:
		if Texts.of(key, "en") == key or Texts.of(key, "zh") == key:
			missing.append(key)
	for id: String in Levels.NODES:
		if not Texts.TEXT.has(id):
			missing.append(id)
	_check("every text exists in both languages", missing.is_empty())
