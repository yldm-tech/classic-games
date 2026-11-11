extends SceneTree

const Main := preload("res://testing/games/fixture_arena/main.gd")

var passed := 0
var failed := 0

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func new_game(sparks: int) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": 1, "seed": 11, "options": {"sparks": sparks}, "stage_size": Vector2i(640, 360)})
	return game

## Turn towards the nearest spark and fire until the run ends.
func hunt(game: GameModule, seconds: float) -> Dictionary:
	var results: Array = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	for step in int(seconds * 60.0):
		if results.size() > 0:
			break
		var state := game.snapshot()
		var ship: Vector2 = state["ship"]
		var nearest := Vector2.INF
		for at: Vector2 in state["spark_positions"]:
			if at.distance_to(ship) < nearest.distance_to(ship):
				nearest = at
		var aim := (nearest - ship).normalized() * 0.25
		game.feed(0, &"right", maxf(aim.x, 0.0))
		game.feed(0, &"left", maxf(-aim.x, 0.0))
		game.feed(0, &"down", maxf(aim.y, 0.0))
		game.feed(0, &"up", maxf(-aim.y, 0.0))
		game.feed(0, &"a", 1.0 if step % 12 == 0 else 0.0)
		game.advance(1.0 / 60.0)
	return results[0] if results.size() == 1 else {}

func _initialize() -> void:
	var game := new_game(8)
	var state := game.snapshot()
	check(state["sparks_left"] == 8 and state["sparks_total"] == 8, "the option sets the number of sparks")
	check(state["hp"] == 3 and state["ship"] == Vector2(320, 180), "the ship starts in the middle with three shields")
	game.feed(0, &"right", 0.5)
	game.advance(1.0)
	check(is_equal_approx(game.snapshot()["ship"].x, 320.0 + 75.0), "half a stick moves at half speed")
	game.free()

	var hunter := new_game(4)
	var won := hunt(hunter, 120.0)
	check(won.get("cleared", false) == true, "clearing every spark ends the run")
	check(won.get("sparks_left", -1) == 0 and won.get("score", 0) == 200, "four sparks score 200")
	check(won.has("accuracy") and won.has("hits_taken") and won.has("shots_fired"), "achievement inputs are in the result")
	check(int(won.get("shots_hit", 0)) == 4, "four hits")
	hunter.free()

	var idle := new_game(12)
	var results: Array = []
	idle.finished.connect(func(result: Dictionary) -> void: results.append(result))
	idle.advance(600.0)
	check(results.size() == 1 and results[0].get("defeated", false) == true, "standing still is eventually lost")
	check(results.size() == 1 and results[0].get("hits_taken", 0) == 3, "three touches")
	idle.free()

	print("fixture_arena_test: %d passed, %d failed" % [passed, failed])
	quit.call_deferred(0 if failed == 0 else 1)
