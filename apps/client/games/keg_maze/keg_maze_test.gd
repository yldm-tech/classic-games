extends SceneTree

## Headless tests of Keg Burrow. Run: GODOT=/path/to/godot scripts/run-godot-test.sh res://games/keg_maze/keg_maze_test.gd '^keg_maze_test: [0-9]+ passed, 0 failed$'

const Main := preload("res://games/keg_maze/main.gd")
const Levels := preload("res://games/keg_maze/levels.gd")
const Sprites := preload("res://games/keg_maze/sprites.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_data()
	print("keg_maze_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _start(players: int, seed_value: int, options: Dictionary = {}) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": Vector2i(480, 270)})
	return game

func _test_data() -> void:
	for line in Levels.problems():
		push_error(line)
	for line in Sprites.problems():
		push_error(line)
	_check("every stage layout is well formed and fully connected", Levels.problems().is_empty())
	_check("every sprite row has the right width and known colours", Sprites.problems().is_empty())
	var game := _start(1, 3)
	game.advance(1.0)
	game.free()

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
