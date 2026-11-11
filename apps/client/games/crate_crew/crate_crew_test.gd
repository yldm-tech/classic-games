extends SceneTree

const Main := preload("res://games/crate_crew/main.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": 2, "seed": 7, "options": {}, "stage_size": Vector2i(384, 216)})
	game.advance(GameModule.STEP)
	_check("a run starts on the first stage", int(game.snapshot()["stage"]) == 1)
	game.free()
	print("crate_crew_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
