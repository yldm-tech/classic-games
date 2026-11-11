extends SceneTree

const Main := preload("res://games/ember_trail/main.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": 1, "seed": 7, "options": {}, "stage_size": Vector2i(480, 270)})
	game.feed(0, &"right", 1.0)
	game.advance(2.0)
	_check("the hero runs right", float(game.snapshot()["hero_x"]) > 100.0)
	game.free()
	print("ember_trail_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
