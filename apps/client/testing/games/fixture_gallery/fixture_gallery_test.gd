extends SceneTree

const Main := preload("res://testing/games/fixture_gallery/main.gd")

var passed := 0
var failed := 0

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func new_game(lamps: int) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": 1, "seed": 5, "options": {"lamps": lamps}, "stage_size": Vector2i(640, 360)})
	return game

func _initialize() -> void:
	var game := new_game(3)
	var sprites: GameSprites = game.sprites
	check(sprites.texture != null and sprites.has_frame("idle") and sprites.has_frame("walk_0") and sprites.has_animation("walk"), "the atlas and its frame table load")
	check(is_equal_approx(sprites.size("idle").y, 60.0), "a frame has the stage size the table gives it, whatever the size of its source")
	check((game.floor_tile as GameSprites).size("main") == Vector2(64, 64), "a single image is sized by the stage height asked for")
	check(game.audio.has_track("village") and game.audio.has_stinger("clear") and game.audio.has_sound("chime") and game.audio.has_sound("jump"), "music, stinger, file effect and preset effect are all registered")
	check(game.audio.music_playing and game.audio.music_track == "village", "the music file is playing from the start")
	var state := game.snapshot()
	check(state["frame"] == "idle" and state["lit"] == 0 and state["lamps_total"] == 3, "the keeper starts idle with every lamp dark")

	game.feed(0, &"right", 1.0)
	var frames := {}
	for step in 30:
		game.advance(GameModule.STEP)
		frames[game.snapshot()["frame"]] = true
	check(frames.has("walk_0") and frames.has("walk_1"), "walking cycles through the animation's frames on simulated time")
	game.feed(0, &"a", 1.0)
	game.advance(GameModule.STEP)
	game.feed(0, &"a", 0.0)
	check(int(game.audio.played.get("jump", 0)) == 1 and game.snapshot()["keeper"].y < 300.0, "a hop plays the preset effect")
	var results: Array = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	game.advance(6.0)
	check(int(game.audio.played.get("land", 0)) == 1, "and landing plays another")
	check(int(game.audio.played.get("chime", 0)) == 3, "each lamp plays the file effect once")
	check(int(game.audio.played.get("clear", 0)) == 1, "lighting the last lamp plays the stinger")
	check(results.size() == 1 and results[0]["cleared"] == true and results[0]["score"] == 300 and int(results[0]["seconds_left"]) >= 50, "the run is cleared a moment later, with the achievement's field in the result")
	check(not game.audio.music_playing and game.audio.stinger_playing, "the music stops with the run while the stinger rings on")
	game.free()

	var idle := new_game(2)
	var ended: Array = []
	idle.finished.connect(func(result: Dictionary) -> void: ended.append(result))
	idle.advance(61.0)
	check(ended.size() == 1 and ended[0]["timed_out"] == true and ended[0]["lit"] == 0, "standing still runs out of time")
	idle.free()

	var first := new_game(5)
	var second := new_game(5)
	for game_pair: GameModule in [first, second]:
		game_pair.feed(0, &"right", 1.0)
		game_pair.advance(2.0)
	check(first.snapshot() == second.snapshot(), "the same seed and input give the same snapshot")
	first.free()
	second.free()

	print("fixture_gallery_test: %d passed, %d failed" % [passed, failed])
	quit.call_deferred(0 if failed == 0 else 1)
