extends SceneTree

## Headless tests of the module contract as a host sees it: GameSession discovering games, refusing broken ones, and running the fixture module (testing/games/fixture_duo) through its whole life: start with options and players, per-player controls, pause, join and leave, snapshot, score, every way a run ends.
## Run: make games-test GODOT=/path/to/godot

const Session := preload("res://runtime/game_session.gd")

const FIXTURES := "res://testing/games"
const BROKEN := "res://testing/broken_games"
const STEP := 1.0 / 60.0

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_catalog()
	_test_broken_manifests()
	await _test_run()
	await _test_players()
	await _test_endings()
	await _test_refusals()
	_test_dsl_still_runs()
	print("module_contract_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _fixture() -> Dictionary:
	for game: Dictionary in Session.catalog(FIXTURES)["games"]:
		if game["id"] == "fixture_duo":
			return game
	return {}

func _session() -> GameSession:
	var session: GameSession = Session.new()
	root.add_child(session)
	return session

func _module(session: GameSession) -> GameModule:
	return session.get_node("Module") as GameModule

## Hold a control for one step and let it go, which is one press.
func _tap(session: GameSession, slot: int, control: StringName) -> void:
	session.set_control(slot, control, 1.0)
	_module(session).advance(STEP)
	session.set_control(slot, control, 0.0)
	_module(session).advance(STEP)

# ---- discovery ----

func _test_catalog() -> void:
	var shipped := Session.catalog()
	var ids: Array = []
	for game: Dictionary in shipped["games"]:
		ids.append(game["id"])
	# Only what must hold however many games are added: the three migrated ones are there and nothing found is broken.
	_check("the shipped catalog holds the three migrated games and no broken one", ids.has("shooter") and ids.has("survivor") and ids.has("tower_defense") and (shipped["problems"] as Array).is_empty())
	_check("the fixture is not in the shipped catalog", not ids.has("fixture_duo"))
	var kinds := true
	var migrated: Dictionary = {}
	for game: Dictionary in shipped["games"]:
		if not str(game["id"]) in ["shooter", "survivor", "tower_defense"]:
			continue
		migrated = game
		kinds = kinds and game["kind"] == Session.KIND_DSL and not Session.baseline_payload(str(game["runtime"])).is_empty() and ResourceLoader.exists(str(game["art"]["image_path"]))
	_check("each migrated game names a runtime that has a baseline, and its picture", kinds)
	var fixture := _fixture()
	_check("another games root is discovered the same way", fixture.get("kind") == Session.KIND_MODULE and fixture["entry_path"] == "res://testing/games/fixture_duo/main.gd" and fixture["players"] == {"min": 1, "max": 2, "join_in_progress": true})
	_check("a module's stage comes from its manifest", Session.stage_for(fixture) == {"size": Vector2i(480, 270), "pixel_art": true, "scale": 4, "centered": false})
	_check("a DSL game's stage is the runtimes' own", Session.stage_for(migrated) == {"size": Session.STAGE_SIZE, "pixel_art": false, "scale": 2, "centered": true})
	_check("the host is told the controls and the player limit", Session.CONTROLS.size() == 10 and Session.MAX_PLAYERS == 2)

func _test_broken_manifests() -> void:
	var found := Session.catalog(BROKEN)
	var problems: Array = found["problems"]
	var by_id := {}
	for problem: Dictionary in problems:
		by_id[problem["id"]] = "\n".join(problem["errors"] as PackedStringArray)
	_check("a root of broken games loads nothing and reports each one", (found["games"] as Array).is_empty() and by_id.keys() == ["bad_json", "no_manifest", "wrong_shape"])
	_check("unreadable JSON is reported with its line", str(by_id.get("bad_json", "")).begins_with("game.json: not valid JSON (line "))
	_check("a directory without a manifest is reported", by_id.get("no_manifest", "") == "game.json: missing")
	var wrong := str(by_id.get("wrong_shape", ""))
	var expected := ["schema: must be 1", "id: \"another_name\" must equal the directory name \"wrong_shape\"", "publisher: unknown field", "entry: \"../shared/game_module.gd\" must be a relative path", "stage.size: [500, 300]", "name: must be", "initials: must be lowercase letters", "players: needs 1 <= min <= max <= 2", "colors.glow: must be a colour", "art.image: \"missing.png\" does not exist", "achievements[0].icon", "achievements[0].when.fastest: unknown condition", "controls[0].inputs: \"z\" is not one of", "hud.clock.mode", "options[0].default: must be one of the values"]
	var all_named := true
	for line: String in expected:
		if not wrong.contains(line):
			all_named = false
			push_error("missing manifest error: " + line)
	_check("a manifest of the wrong shape lists every problem at once", all_named)

# ---- a run ----

func _test_run() -> void:
	var session := _session()
	var started: Array[Dictionary] = []
	var scores: Array[int] = []
	var pauses: Array[bool] = []
	var ended: Array[Dictionary] = []
	session.game_started.connect(func(info: Dictionary) -> void: started.append(info))
	session.score_changed.connect(func(score: int) -> void: scores.append(score))
	session.paused_changed.connect(func(paused: bool) -> void: pauses.append(paused))
	session.game_ended.connect(func(result: Dictionary) -> void: ended.append(result))

	_check("starting a module run succeeds", session.start_run({"game": _fixture(), "options": {"duration": 60}, "players": 2, "seed": 11, "locale": "en"}))
	var module := _module(session)
	_check("the session reports a live module run", session.is_running() and session.is_module() and not session.is_paused() and started == [{"runtime": "fixture_duo", "stage_size": Vector2i(480, 270)}])
	_check("the module got its options, players, seed, locale and stage", module.events == ["start:2"] and is_equal_approx(module.duration, 60.0) and module.locale == "en" and module.stage_size == Vector2i(480, 270) and session.active_players() == [0, 1])
	_check("a pixel-art stage is filtered nearest and drawn from the top left", module.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and module.position == Vector2.ZERO and session.stage()["scale"] == 4)
	_check("a module takes no commands", not session.perform("move", {"axis": Vector2.RIGHT}))

	var before := session.snapshot()
	session.set_control(0, &"right", 1.0)
	session.set_control(1, &"up", 1.0)
	module.advance(1.0)
	var after := session.snapshot()
	_check("each player's controls move that player only", float(after["players"][0]["x"]) > float(before["players"][0]["x"]) + 50.0 and is_equal_approx(float(after["players"][0]["y"]), float(before["players"][0]["y"])) and float(after["players"][1]["y"]) < float(before["players"][1]["y"]) - 50.0 and is_equal_approx(float(after["players"][1]["x"]), float(before["players"][1]["x"])))
	_check("the snapshot carries the HUD fields the manifest names", after.has("time_left") and after["boss_hp"] == 5 and after["boss_max_hp"] == 5 and after["coins_total"] == 3 and after["players"][1]["lives"] == 3 and after["player_count"] == 2 and after.has("play_seconds"))
	_check("unknown controls and seats are ignored", session.set_control(0, &"jump", 1.0) and session.set_control(7, &"a", 1.0))

	_tap(session, 1, &"a")
	_check("a score change is announced once, with the new score", scores == [100] and session.snapshot()["score"] == 100 and session.snapshot()["players"][1]["hits"] == 1)

	session.set_paused(true)
	_check("pause freezes the module, tells it, and lets go of the controls", session.is_paused() and pauses == [true] and module.events.back() == "paused" and is_zero_approx(module.input(0).strength(&"right")) and module.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("controls are refused while paused", not session.set_control(0, &"a", 1.0))
	var played := float(session.snapshot()["play_seconds"])
	await _frames(4)
	_check("paused time is not play time", is_equal_approx(float(session.snapshot()["play_seconds"]), played))
	session.set_paused(false)
	_check("resume tells the module", not session.is_paused() and pauses == [true, false] and module.events.back() == "resumed")
	await _frames(4)
	_check("and play time runs again", float(session.snapshot()["play_seconds"]) > played)

	session.end_run()
	_check("a run the host ends is reported once as aborted, with what happened so far", ended.size() == 1 and ended[0]["aborted"] == true and ended[0]["cleared"] == false and ended[0]["score"] == 100 and ended[0]["runtime_ref"] == "fixture_duo" and ended[0]["player_count"] == 2)
	session.end_run()
	_check("ending it again does nothing", ended.size() == 1 and not session.is_running())
	_check("the finished run stays mounted until it is cleared", is_instance_valid(_module(session)) and not session.snapshot().is_empty())
	session.clear_run()
	await _frames(2)
	_check("clearing removes it", session.get_child_count() == 0 and session.snapshot().is_empty() and not session.is_module() and session.active_players().is_empty())
	session.free()

func _test_players() -> void:
	var session := _session()
	session.start_run({"game": _fixture(), "players": 1, "seed": 3})
	var module := _module(session)
	_check("a one-player run has one active seat", session.active_players() == [0] and session.snapshot()["player_count"] == 1)
	session.set_control(1, &"right", 1.0)
	module.advance(0.5)
	_check("an empty seat's controls move nobody", is_equal_approx(float(session.snapshot()["players"][1]["x"]), 80.0))
	_check("player two can join a live run", session.add_player(1) and session.active_players() == [0, 1] and module.events.back() == "joined:1")
	_check("a taken seat cannot be joined again", not session.add_player(1) and not session.add_player(0))
	session.set_control(1, &"right", 1.0)
	module.advance(0.5)
	_check("the joined player plays", float(session.snapshot()["players"][1]["x"]) > 80.0)
	_check("and can leave", session.remove_player(1) and session.active_players() == [0] and module.events.back() == "left:1")
	_check("the last player cannot leave", not session.remove_player(0) and not session.remove_player(1))
	session.set_paused(true)
	_check("a seat can change while the run is paused", session.add_player(1) and session.active_players() == [0, 1])
	session.end_run()
	_check("nobody joins a run that is over", not session.add_player(1) and not session.remove_player(1))
	session.free()
	await _frames(1)

func _test_endings() -> void:
	var session := _session()
	var ended: Array[Dictionary] = []
	session.game_ended.connect(func(result: Dictionary) -> void: ended.append(result))

	session.start_run({"game": _fixture(), "players": 2, "seed": 3})
	for hit in 5:
		_tap(session, hit % 2, &"a")
	_check("the module ending the run ends the session's run, cleared", ended.size() == 1 and ended[0]["cleared"] == true and ended[0]["defeated"] == false and ended[0]["aborted"] == false and ended[0]["timed_out"] == false and ended[0]["score"] == 500 and not session.is_running())
	_check("the result carries the per-player fields and the achievement inputs", ended[0]["players"][0]["score"] == 300 and ended[0]["players"][1]["score"] == 200 and ended[0]["deaths"] == 0 and ended[0]["player_count"] == 2 and ended[0].has("play_seconds"))
	_check("the snapshot after the end is the result", session.snapshot()["cleared"] == true and session.snapshot()["score"] == 500)

	session.start_run({"game": _fixture(), "players": 1, "seed": 3})
	_check("starting again replaces the finished run", session.is_running() and session.snapshot()["score"] == 0 and session.snapshot()["cleared"] == false)
	for life in 3:
		_tap(session, 0, &"b")
	_check("defeated", ended.size() == 2 and ended[1]["defeated"] == true and ended[1]["cleared"] == false and ended[1]["deaths"] == 3)

	session.start_run({"game": _fixture(), "players": 1, "seed": 3, "options": {"duration": 5}})
	_module(session).advance(6.0)
	_check("timed out", ended.size() == 3 and ended[2]["timed_out"] == true and ended[2]["cleared"] == false and ended[2]["defeated"] == false)

	var states: Array = []
	for attempt in 2:
		session.start_run({"game": _fixture(), "players": 1, "seed": 2024})
		session.set_control(0, &"right", 1.0)
		_module(session).advance(10.0)
		var state := session.snapshot()
		state.erase("play_seconds")
		states.append(state)
	_check("the same seed and input replay the same run through the session", states[0] == states[1])
	session.free()
	await _frames(1)

func _test_refusals() -> void:
	var session := _session()
	var errors: Array[Dictionary] = []
	session.game_error.connect(func(error: Dictionary) -> void: errors.append(error))
	var missing := _fixture().duplicate(true)
	missing["entry_path"] = "res://testing/games/fixture_duo/nowhere.gd"
	_check("an entry script that is not there is refused", not session.start_run({"game": missing}) and errors.size() == 1 and errors[0]["code"] == "MODULE_NOT_FOUND" and not session.is_running())
	var wrong := _fixture().duplicate(true)
	wrong["entry_path"] = "res://games/shared/game_audio.gd"
	_check("an entry script that is not a GameModule is refused", not session.start_run({"game": wrong}) and errors.size() == 2 and errors[1]["code"] == "MODULE_INVALID" and session.get_child_count() == 0)
	_check("nothing can be fed to a session without a run", not session.set_control(0, &"a", 1.0) and not session.add_player(1) and session.stage().is_empty())
	session.free()
	await _frames(1)

## The DSL path is untouched by module hosting.
func _test_dsl_still_runs() -> void:
	var session := _session()
	var payload := Session.baseline_payload("survivor@1.0.0")
	_check("a DSL baseline still starts through the same session", session.start_run(payload) and session.is_running() and not session.is_module() and session.active_players() == [0] and session.stage()["centered"] == true)
	_check("and takes no per-player controls", not session.set_control(0, &"a", 1.0) and not session.add_player(1))
	session.end_run()
	session.clear_run()
	session.free()

# ---- helpers ----

func _frames(count: int) -> void:
	for index in count:
		await process_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
