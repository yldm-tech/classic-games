extends SceneTree

## Headless tests of Yarn Tumble. Run: GODOT=/path/to/godot scripts/run-godot-test.sh res://games/yarn_tumble/yarn_tumble_test.gd '^yarn_tumble_test: [0-9]+ passed, 0 failed$'

const Main := preload("res://games/yarn_tumble/main.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": 2, "seed": 3, "options": {}, "stage_size": Vector2i(480, 270)})
	game.advance(1.0)
	_check("a run starts on floor 1", int(game.snapshot()["stage"]) == 1)
	game.free()
	print("yarn_tumble_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
