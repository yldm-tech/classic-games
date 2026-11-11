extends SceneTree

## The fixture module's own headless test, and the pattern a game's test follows: load the entry script, put it in the tree, start it with a fixed seed, write controls with feed(), step it with advance(), and read snapshot(). No launcher and no session are involved, so the test imports nothing outside the game's directory and games/shared.
## Run: make games-test GODOT=/path/to/godot

const Main := preload("res://testing/games/fixture_duo/main.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_rules()
	_test_determinism()
	print("fixture_duo_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _start(players: int, seed_value: int, options: Dictionary = {}) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": Vector2i(480, 270)})
	return game

func _test_rules() -> void:
	var game := _start(2, 5, {"duration": 5})
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	var first := game.snapshot()
	_check("a run starts with the option's countdown, a full boss and full lives", is_equal_approx(float(first["time_left"]), 5.0) and first["boss_hp"] == 5 and first["players"][0]["lives"] == 3 and first["players"][1]["lives"] == 3)
	game.feed(0, &"right", 1.0)
	game.feed(1, &"left", 1.0)
	game.advance(0.5)
	var moved := game.snapshot()
	_check("each player moves by their own input", float(moved["players"][0]["x"]) > float(first["players"][0]["x"]) and float(moved["players"][1]["x"]) < float(first["players"][1]["x"]))
	_check("the countdown runs in simulated time", is_equal_approx(float(moved["time_left"]), 4.5))
	game.feed(0, &"right", 0.0)
	game.feed(1, &"left", 0.0)
	for hit in 5:
		game.feed(1, &"a", 1.0)
		game.advance(GameModule.STEP)
		game.feed(1, &"a", 0.0)
		game.advance(GameModule.STEP)
	_check("five hits clear the run and the hitter gets the points", results.size() == 1 and results[0]["cleared"] == true and results[0]["score"] == 500 and results[0]["players"][1]["score"] == 500 and results[0]["players"][0]["score"] == 0)
	_check("the result says how it was played", results[0]["player_count"] == 2 and results[0]["deaths"] == 0 and not results[0].has("boss_hp"))
	_check("the sounds were asked for", int(game.audio.played.get("hit", 0)) == 5 and not game.audio.music_playing)
	game.free()

	game = _start(1, 5, {"duration": 5})
	results.clear()
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	for life in 3:
		game.feed(0, &"b", 1.0)
		game.advance(GameModule.STEP)
		game.feed(0, &"b", 0.0)
		game.advance(GameModule.STEP)
	_check("losing every life is a defeat", results.size() == 1 and results[0]["defeated"] == true and results[0]["cleared"] == false and results[0]["deaths"] == 3)
	game.free()

	game = _start(1, 5, {"duration": 5})
	results.clear()
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	game.advance(6.0)
	_check("the countdown running out is a time-out, neither a win nor a loss", results.size() == 1 and results[0]["timed_out"] == true and results[0]["cleared"] == false and results[0]["defeated"] == false)
	game.free()

func _test_determinism() -> void:
	var states: Array = []
	for attempt in 2:
		var game := _start(1, 77)
		game.feed(0, &"right", 1.0)
		game.advance(12.0)
		states.append(game.snapshot())
		game.free()
	_check("the same seed and the same input give the same run", states[0] == states[1] and int(states[0]["coins"]) >= 1)
	var other := _start(1, 78)
	other.feed(0, &"right", 1.0)
	other.advance(12.0)
	_check("the level scrolls: the camera followed the player past the first screen", float(other.snapshot()["camera_x"]) > 0.0)
	other.free()

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
