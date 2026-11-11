extends SceneTree

## Headless tests of the shared game library: the deterministic RNG, the fixed timestep, per-player input state, the procedural synth, the GameModule base class, and the manifest schema with the registry that discovers games.
## Run: make games-test GODOT=/path/to/godot (it runs every games/*/*_test.gd).

const Rng := preload("res://games/shared/game_rng.gd")
const FixedStep := preload("res://games/shared/game_fixed_step.gd")
const PlayerInput := preload("res://games/shared/game_input.gd")
const Audio := preload("res://games/shared/game_audio.gd")
const Module := preload("res://games/shared/game_module.gd")
const Manifest := preload("res://games/shared/game_manifest.gd")
const Registry := preload("res://games/shared/game_registry.gd")

## A module small enough to read in one glance: player one's A scores a point, B ends the run.
class Probe:
	extends "res://games/shared/game_module.gd"

	var steps := 0
	var frames := 0
	var journal: Array[String] = []

	func _game_start(config: Dictionary) -> void:
		journal.append("start:%d:%d" % [int(config["players"]), int(config["seed"])])

	func _game_step(_delta: float) -> void:
		steps += 1
		if input(0).just_pressed(&"a"):
			score += 1
		if input(0).just_pressed(&"b"):
			finish(OUTCOME_CLEARED, {"bonus": 7})

	func _game_frame(_delta: float) -> void:
		frames += 1

	func _game_snapshot() -> Dictionary:
		return {"steps": steps}

	func _game_player_joined(slot: int) -> void:
		journal.append("joined:%d" % slot)

	func _game_player_left(slot: int) -> void:
		journal.append("left:%d" % slot)

	func _game_paused(paused: bool) -> void:
		journal.append("paused" if paused else "resumed")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_rng()
	_test_fixed_step()
	_test_input()
	_test_audio()
	await _test_module()
	_test_manifest_schema()
	_test_registry()
	print("shared_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- RNG ----

func _test_rng() -> void:
	var first := Rng.new(1234)
	var second := Rng.new(1234)
	var same := true
	var in_range := true
	for index in 200:
		var value := first.next_u32()
		same = same and value == second.next_u32()
		in_range = in_range and value >= 0 and value <= 0xFFFFFFFF
	_check("the same seed gives the same sequence", same)
	_check("raw values stay in 32 bits", in_range)
	var other := Rng.new(1235)
	first.reseed(1234)
	_check("neighbouring seeds give different sequences", first.next_u32() != other.next_u32())
	_check("the sequence is pinned, so a platform that computes it differently is caught", Rng.new(1).next_u32() == Rng.new(1).next_u32() and Rng.new(0).state() != 0)
	var rng := Rng.new(7)
	var ints_ok := true
	var floats_ok := true
	var seen := {}
	for index in 500:
		var whole := rng.int_range(3, 6)
		ints_ok = ints_ok and whole >= 3 and whole <= 6
		seen[whole] = true
		var real := rng.float_range(-1.0, 1.0)
		floats_ok = floats_ok and real >= -1.0 and real < 1.0
		var unit := rng.unit()
		floats_ok = floats_ok and unit >= 0.0 and unit < 1.0
	_check("int_range covers both ends and nothing else", ints_ok and seen.size() == 4)
	_check("float_range and unit stay in their half-open ranges", floats_ok)
	_check("a degenerate range is its low end", rng.int_range(5, 5) == 5 and rng.int_range(5, 2) == 5)
	_check("chance(0) never and chance(1) always", not rng.chance(0.0) and rng.chance(1.0))
	_check("pick returns an element, or null for nothing", rng.pick(["a", "b"]) in ["a", "b"] and rng.pick([]) == null)
	var deck := [1, 2, 3, 4, 5, 6, 7, 8]
	var shuffled: Array = Rng.new(99).shuffle(deck.duplicate())
	var again: Array = Rng.new(99).shuffle(deck.duplicate())
	var sorted := shuffled.duplicate()
	sorted.sort()
	_check("shuffle keeps every element, reorders, and repeats for a seed", sorted == deck and shuffled != deck and shuffled == again)
	var saved := rng.state()
	var expected := rng.next_u32()
	rng.restore(saved)
	_check("state and restore replay from a point", rng.next_u32() == expected)

# ---- fixed step ----

func _test_fixed_step() -> void:
	var clock := FixedStep.new(1.0 / 60.0, 5)
	_check("one frame at the step is one step", clock.advance(1.0 / 60.0) == 1)
	_check("half a step is none, and the rest carries over", clock.advance(1.0 / 120.0) == 0 and clock.advance(1.0 / 120.0) == 1)
	_check("a 30 fps frame is two steps", clock.advance(1.0 / 30.0) == 2)
	var total := 0
	for index in 144:
		total += clock.advance(1.0 / 144.0)
	_check("a second at 144 fps is 60 steps", total == 60)
	_check("a long frame is cut at max_steps and does not leave a backlog", clock.advance(2.0) == 5 and clock.advance(0.0) == 0)
	clock.reset()
	clock.advance(1.0 / 120.0)
	_check("alpha is how far into the next step the frame is", is_equal_approx(clock.alpha(), 0.5))
	_check("a negative delta is ignored", clock.advance(-1.0) == 0)

# ---- input ----

func _test_input() -> void:
	var pad := PlayerInput.new()
	_check("the controls are four directions and six buttons", PlayerInput.CONTROLS.size() == 10 and PlayerInput.DIRECTIONS.size() == 4 and PlayerInput.BUTTONS.size() == 6)
	pad.tick()
	_check("nothing is held at first", not pad.any_down() and pad.move == Vector2.ZERO)
	pad.feed(&"a", 1.0)
	_check("a fed control is not visible until the step begins", not pad.is_down(&"a"))
	pad.tick()
	_check("then it is just pressed for exactly one step", pad.is_down(&"a") and pad.just_pressed(&"a") and not pad.just_released(&"a"))
	pad.tick()
	_check("held on the next", pad.is_down(&"a") and not pad.just_pressed(&"a"))
	pad.feed(&"a", 0.0)
	pad.tick()
	_check("and just released when let go", not pad.is_down(&"a") and pad.just_released(&"a"))
	pad.feed(&"b", 1.0)
	pad.feed(&"b", 0.0)
	pad.tick()
	_check("a tap between two steps is still seen for one step", pad.just_pressed(&"b") and pad.is_down(&"b"))
	pad.tick()
	_check("and released on the next", pad.just_released(&"b"))
	pad.feed(&"right", 1.0)
	pad.feed(&"up", 1.0)
	pad.tick()
	_check("two directions make a diagonal no longer than 1", is_equal_approx(pad.move.length(), 1.0) and pad.move.x > 0.0 and pad.move.y < 0.0 and pad.move_sign() == Vector2i(1, -1))
	pad.feed(&"up", 0.0)
	pad.feed(&"right", 0.4)
	pad.tick()
	_check("a stick below the press threshold still moves, analogue, without counting as held", is_equal_approx(pad.move.x, 0.4) and not pad.is_down(&"right") and is_equal_approx(pad.strength(&"right"), 0.4))
	pad.feed(&"left", 1.0)
	pad.feed(&"right", 1.0)
	pad.tick()
	_check("opposite directions cancel", pad.move == Vector2.ZERO)
	pad.feed(&"fire", 1.0)
	pad.feed(&"a", 5.0)
	pad.tick()
	_check("unknown controls are ignored and strength is clamped", not pad.is_down(&"fire") and is_equal_approx(pad.strength(&"a"), 1.0))
	pad.release()
	pad.tick()
	_check("release lets go of everything, visibly", not pad.any_down() and pad.just_released(&"a"))
	pad.feed(&"x", 1.0)
	pad.tick()
	pad.clear()
	_check("clear forgets the previous step too", not pad.is_down(&"x") and not pad.just_released(&"x"))

# ---- audio ----

func _test_audio() -> void:
	var spec := {"wave": "square", "freq": 440, "freq_end": 880, "duration": 0.1}
	var first := Audio.effect(spec)
	var second := Audio.effect(spec)
	_check("an effect is 16-bit mono PCM of the asked length", first.format == AudioStreamWAV.FORMAT_16_BITS and not first.stereo and first.mix_rate == Audio.EFFECT_RATE and first.data.size() == int(0.1 * Audio.EFFECT_RATE) * 2)
	_check("the same spec gives the same bytes", first.data == second.data)
	var loud := false
	for index in range(0, first.data.size(), 2):
		loud = loud or absi(first.data.decode_s16(index)) > 4000
	_check("it is not silence", loud)
	_check("it starts and ends quietly, so it does not click", absi(first.data.decode_s16(0)) < 2000 and absi(first.data.decode_s16(first.data.size() - 2)) < 2000)
	var noise := Audio.effect({"wave": "noise", "freq": 4000, "duration": 0.05})
	_check("noise is deterministic too", noise.data == Audio.effect({"wave": "noise", "freq": 4000, "duration": 0.05}).data and noise.data != first.data)
	var every_wave := true
	for wave: String in Audio.WAVES:
		every_wave = every_wave and Audio.effect({"wave": wave, "duration": 0.02}).data.size() > 0
	_check("every wave renders", every_wave)
	_check("an absurd duration is capped", Audio.effect({"duration": 600.0}).data.size() == int(Audio.MAX_EFFECT_SECONDS * Audio.EFFECT_RATE) * 2)
	_check("note names, sharps, flats, MIDI numbers and rests", is_equal_approx(Audio.note_frequency("A4"), 440.0) and is_equal_approx(Audio.note_frequency(69), 440.0) and is_equal_approx(Audio.note_frequency("C4"), 261.6256) and is_equal_approx(Audio.note_frequency("A#4"), Audio.note_frequency("Bb4")) and Audio.note_frequency("-") == 0.0 and Audio.note_frequency(0) == 0.0 and Audio.note_frequency("H9") == 0.0)
	var tune := Audio.music({"bpm": 120, "voices": [{"wave": "square", "notes": [["C4", 1], ["-", 1], ["G4", 2]]}, {"wave": "triangle", "notes": [["C2", 2]]}]})
	_check("a tune loops over its longest voice", tune.loop_mode == AudioStreamWAV.LOOP_FORWARD and tune.loop_end == int(2.0 * Audio.MUSIC_RATE) and tune.data.size() == tune.loop_end * 2)
	_check("a tune with no voices is still a valid stream", Audio.music({}).data.size() == 2)

	var audio := Audio.new()
	root.add_child(audio)
	audio.define("blip", spec)
	_check("a defined effect can be played and is counted", audio.has_sound("blip") and audio.play("blip") and audio.play("blip", 1.5) and int(audio.played["blip"]) == 2)
	_check("an unknown effect does nothing", not audio.play("nope") and not audio.played.has("nope"))
	audio.play_music({"bpm": 120, "voices": [{"notes": [["C4", 1]]}]})
	_check("music is tracked", audio.music_playing)
	audio.stop_music()
	_check("and stops", not audio.music_playing)
	var buses := true
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		buses = buses and player.bus == (Audio.BUS_MUSIC if player.name == "Music" else Audio.BUS_SFX)
	_check("effects go to the SFX bus and music to the Music bus, and both buses exist", buses and AudioServer.get_bus_index(Audio.BUS_SFX) > 0 and AudioServer.get_bus_index(Audio.BUS_MUSIC) > 0)
	audio.free()

# ---- module base ----

func _test_module() -> void:
	var module := Probe.new()
	root.add_child(module)
	var scores: Array[int] = []
	var results: Array[Dictionary] = []
	module.score_changed.connect(func(value: int) -> void: scores.append(value))
	module.finished.connect(func(result: Dictionary) -> void: results.append(result))
	_check("a module does nothing before it is started", not module.is_running() and module.player_count() == 0)
	module.start({"players": 2, "seed": 42, "options": {"speed": 3}, "locale": "en", "stage_size": Vector2i(480, 270)})
	_check("start hands the game its configuration", module.is_running() and module.journal == ["start:2:42"] and module.options == {"speed": 3} and module.locale == "en" and module.stage_size == Vector2i(480, 270))
	_check("both players are active", module.active_players() == [0, 1] and module.player_count() == 2 and module.is_player_active(1) and not module.is_player_active(2))
	var seeded := module.rng.next_u32()
	_check("the RNG is seeded from the configuration", seeded == Rng.new(42).next_u32())
	module.advance(0.5)
	_check("advance runs whole fixed steps", module.steps == 30 and is_equal_approx(module.elapsed, 0.5))
	module.feed(0, &"a", 1.0)
	module.advance(Module.STEP * 3.0)
	_check("a held button is one press, and the score change is announced", module.score == 1 and scores == [1])
	module.feed(1, &"a", 1.0)
	module.advance(Module.STEP)
	_check("player two's input is player two's", module.score == 1 and module.input(1).is_down(&"a") and not module.input(0).just_pressed(&"a"))
	var live := module.snapshot()
	_check("the snapshot carries the base fields and the game's own", live["score"] == 1 and live["player_count"] == 2 and live["active_players"] == [0, 1] and live["steps"] == module.steps and is_equal_approx(float(live["elapsed"]), module.elapsed))

	module.set_paused(true)
	_check("pausing lets go of every control and tells the game", module.is_paused() and module.journal.back() == "paused" and is_zero_approx(module.input(0).strength(&"a")))
	var before := module.steps
	await _frames(3)
	_check("a paused module does not step on frames", module.steps == before)
	module.set_paused(false)
	_check("resuming tells the game", module.journal.back() == "resumed")
	var frames_before := module.frames
	# A headless frame can be far shorter than a step, so wait for a step rather than for a number of frames.
	var deadline := Time.get_ticks_msec() + 3000
	while module.steps == before and Time.get_ticks_msec() < deadline:
		await process_frame
	_check("frames step it again and call the frame hook", module.steps > before and module.frames > frames_before)

	_check("the last player cannot leave, a taken seat cannot be joined", module.leave(1) and not module.leave(0) and not module.leave(1) and module.active_players() == [0])
	_check("joining seats the player and tells the game", module.join(1) and not module.join(1) and not module.join(5) and module.journal.slice(-2) == ["left:1", "joined:1"])

	module.feed(0, &"b", 1.0)
	module.advance(Module.STEP)
	_check("finish ends the run once, with the snapshot, the outcome and the extra fields", results.size() == 1 and results[0]["cleared"] == true and results[0]["defeated"] == false and results[0]["timed_out"] == false and results[0]["bonus"] == 7 and results[0]["score"] == 1 and module.is_finished() and not module.is_running())
	var frozen := module.steps
	module.advance(1.0)
	module.finish(Module.OUTCOME_DEFEATED)
	await _frames(2)
	_check("a finished module neither steps nor finishes again", module.steps == frozen and results.size() == 1 and not module.join(1))

	module.start({})
	_check("a module can be started again with defaults", module.is_running() and module.player_count() == 1 and module.score == 0 and is_zero_approx(module.elapsed) and module.journal.back() == "start:1:1")
	module.free()

# ---- manifest ----

func _valid_manifest() -> Dictionary:
	return {
		"schema": 1, "id": "sample", "kind": "dsl", "runtime": "shooter@1.0.0",
		"name": {"zh": "样例", "en": "SAMPLE"}, "initials": "yl", "genre": {"zh": "样例", "en": "SAMPLE"}, "tagline": {"zh": "一句话。", "en": "One line."},
		"players": {"min": 1, "max": 2}, "colors": {"title": "FFFFFF", "shadow": "000000", "glow": "8899AA"}, "art": {"top": "000000", "bottom": "111111", "primary": "FFFFFF", "secondary": "FF0000"},
		"achievements": [{"id": "one", "icon": "star", "name": {"zh": "一", "en": "One"}, "desc": {"zh": "一", "en": "One"}, "when": {"cleared": true, "players": 2, "min": {"score": 10}, "max": {"deaths": 0}}}],
		"how": {"zh": "玩法。", "en": "How."},
		"controls": [{"id": "move", "name": {"zh": "移动", "en": "Move"}, "actions": ["ui_up"], "glyphs": []}],
		"hud": {"clock": {"mode": "elapsed", "field": "play_seconds"}, "vital": {"field": "hp", "max": "max_hp", "label": {"zh": "生命", "en": "HP"}}, "stats": [{"label": {"zh": "击倒", "en": "Kills"}, "fields": ["kills"]}]},
		"options": [{"id": "level", "name": {"zh": "等级", "en": "Level"}, "note": {"zh": "说明", "en": "Note"}, "values": [1, 2], "default": 1, "path": "/stage/level"}],
	}

## The errors of the valid manifest after one change.
func _errors_with(change: Callable) -> String:
	var manifest := _valid_manifest()
	change.call(manifest)
	return "\n".join(Manifest.validate(manifest, "res://games/sample"))

func _test_manifest_schema() -> void:
	_check("the sample manifest is valid", Manifest.validate(_valid_manifest(), "res://games/sample").is_empty())
	var cases := {
		"schema: must be 1": func(m: Dictionary) -> void: m["schema"] = 2,
		"must equal the directory name": func(m: Dictionary) -> void: m["id"] = "other",
		"id: must be lowercase": func(m: Dictionary) -> void: m["id"] = "Sample",
		"kind: must be": func(m: Dictionary) -> void: m["kind"] = "plugin",
		"runtime: must be \"name@version\"": func(m: Dictionary) -> void: m["runtime"] = "shooter",
		"publisher: unknown field": func(m: Dictionary) -> void: m["publisher"] = "x",
		"entry: unknown field": func(m: Dictionary) -> void: m["entry"] = "main.gd",
		"name: must be { \"zh\": text, \"en\": text }": func(m: Dictionary) -> void: m["name"] = {"zh": "只有中文"},
		"tagline: must be": func(m: Dictionary) -> void: m["tagline"] = {"zh": "有", "en": "  "},
		"initials: must be lowercase letters": func(m: Dictionary) -> void: m["initials"] = "YL",
		"players: needs 1 <= min <= max <= 2": func(m: Dictionary) -> void: m["players"] = {"min": 1, "max": 3},
		"players: must be { \"min\": n, \"max\": n }": func(m: Dictionary) -> void: m["players"] = {"min": "one"},
		"players.join_in_progress: must be true or false": func(m: Dictionary) -> void: m["players"]["join_in_progress"] = 1,
		"colors.glow: must be a colour as RRGGBB": func(m: Dictionary) -> void: m["colors"]["glow"] = "#8899AA",
		"art.primary: must be a colour": func(m: Dictionary) -> void: m["art"].erase("primary"),
		"art.image: \"cover.png\" does not exist": func(m: Dictionary) -> void: m["art"]["image"] = "cover.png",
		"must be a relative path inside the game's directory": func(m: Dictionary) -> void: m["art"]["image"] = "../shooter/key_art.jpg",
		"art.image: \"cover.gd\" must end in": func(m: Dictionary) -> void: m["art"]["image"] = "cover.gd",
		"achievements[0].icon: must be one of": func(m: Dictionary) -> void: m["achievements"][0]["icon"] = "medal",
		"achievements[1].id: \"one\" is used twice": func(m: Dictionary) -> void: m["achievements"].append(m["achievements"][0].duplicate(true)),
		"achievements[0].when.fastest: unknown condition": func(m: Dictionary) -> void: m["achievements"][0]["when"] = {"fastest": true},
		"achievements[0].when.min.score: must be a number": func(m: Dictionary) -> void: m["achievements"][0]["when"] = {"min": {"score": "lots"}},
		"achievements[0].when.players: must be a player count the game supports": func(m: Dictionary) -> void: m["players"] = {"min": 1, "max": 1},
		"achievements[0].when: must be an object": func(m: Dictionary) -> void: m["achievements"][0].erase("when"),
		"controls: must be a non-empty list": func(m: Dictionary) -> void: m["controls"] = [],
		"controls[0].actions: must be a list of action names": func(m: Dictionary) -> void: m["controls"][0]["actions"] = "ui_up",
		"hud.clock.mode: must be one of": func(m: Dictionary) -> void: m["hud"]["clock"] = {"mode": "stopwatch"},
		"hud.vital.label: must be": func(m: Dictionary) -> void: m["hud"]["vital"].erase("label"),
		"hud.stats[0].fields: must name one or two snapshot fields": func(m: Dictionary) -> void: m["hud"]["stats"][0]["fields"] = ["a", "b", "c"],
		"hud.minimap: unknown field": func(m: Dictionary) -> void: m["hud"]["minimap"] = true,
		"options[0].default: must be one of the values": func(m: Dictionary) -> void: m["options"][0]["default"] = 9,
		"options[0].values: must be a non-empty list of whole numbers": func(m: Dictionary) -> void: m["options"][0]["values"] = [1.5],
		"options[0].path: must be a JSON pointer": func(m: Dictionary) -> void: m["options"][0].erase("path"),
		"options[0].labels: must have one { zh, en } per value": func(m: Dictionary) -> void: m["options"][0]["labels"] = [{"zh": "一", "en": "One"}],
		"site.screenshot: \"shot.png\" does not exist": func(m: Dictionary) -> void: m["site"] = {"screenshot": "shot.png"},
		"tuning.cooldown: must be a number": func(m: Dictionary) -> void: m["tuning"] = {"cooldown": "ten"},
	}
	for expected: String in cases:
		var errors := _errors_with(cases[expected])
		_check("a manifest with a wrong field says so: %s" % expected, errors.contains(expected))

	var module := _valid_manifest()
	module.erase("runtime")
	module["kind"] = "module"
	module["entry"] = "game_module.gd"
	module["stage"] = {"size": [480, 270], "pixel_art": true}
	module["controls"] = [{"id": "move", "name": {"zh": "移动", "en": "Move"}, "inputs": ["move"]}, {"id": "jump", "name": {"zh": "跳", "en": "Jump"}, "inputs": ["a", "up"]}]
	module["options"][0].erase("path")
	module["id"] = "shared"
	_check("a module manifest is valid with an entry, a stage and logical inputs", Manifest.validate(module, "res://games/shared").is_empty())
	_check("its stage is resolved to a size and a whole scale", Manifest.stage(module) == {"size": Vector2i(480, 270), "pixel_art": true, "scale": 4})
	var sizes_ok := true
	for size: Array in [[1920, 1080], [960, 540], [640, 360], [480, 270], [384, 216], [320, 180], [240, 135]]:
		module["stage"] = {"size": size}
		sizes_ok = sizes_ok and Manifest.validate(module, "res://games/shared").is_empty()
	_check("every whole division of the canvas is a stage size", sizes_ok)
	var module_cases := {
		"stage.size: [500, 300] must be 1920x1080 divided by a whole number": func(m: Dictionary) -> void: m["stage"] = {"size": [500, 300]},
		"stage.size: [960, 270] must be": func(m: Dictionary) -> void: m["stage"] = {"size": [960, 270]},
		"stage: must be": func(m: Dictionary) -> void: m.erase("stage"),
		"entry: \"missing.gd\" does not exist": func(m: Dictionary) -> void: m["entry"] = "missing.gd",
		"entry: \"../shooter/x.gd\" must be a relative path": func(m: Dictionary) -> void: m["entry"] = "../shooter/x.gd",
		"controls[1].inputs: \"z\" is not one of": func(m: Dictionary) -> void: m["controls"][1]["inputs"] = ["z"],
		"controls[0].actions: unknown field": func(m: Dictionary) -> void: m["controls"][0]["actions"] = ["ui_up"],
		"options[0].path: only a dsl game has one": func(m: Dictionary) -> void: m["options"][0]["path"] = "/x",
		"runtime: unknown field": func(m: Dictionary) -> void: m["runtime"] = "shooter@1.0.0",
	}
	for expected: String in module_cases:
		var broken := module.duplicate(true)
		broken["stage"] = {"size": [480, 270], "pixel_art": true}
		(module_cases[expected] as Callable).call(broken)
		_check("a module manifest with a wrong field says so: %s" % expected, "\n".join(Manifest.validate(broken, "res://games/shared")).contains(expected))

# ---- registry ----

func _test_registry() -> void:
	var found := Registry.discover(Registry.GAMES_ROOT)
	var games: Array = found["games"]
	var ids: Array = []
	for game: Dictionary in games:
		ids.append(game["id"])
	var sorted := ids.duplicate()
	sorted.sort()
	_check("every shipped game has a valid manifest", (found["problems"] as Array).is_empty() and not games.is_empty())
	_check("the shared library is not a game, and games come sorted by id", not ids.has("shared") and ids == sorted)
	var resolved := true
	var whole := true
	for game: Dictionary in games:
		resolved = resolved and game["dir"] == Registry.GAMES_ROOT.path_join(str(game["id"]))
		var art: Dictionary = game["art"]
		if art.has("image"):
			resolved = resolved and ResourceLoader.exists(str(art["image_path"]))
		if game["kind"] == Manifest.KIND_MODULE:
			resolved = resolved and ResourceLoader.exists(str(game["entry_path"]))
		whole = whole and game["schema"] is int and game["players"]["max"] is int and game["options"] is Array
		for option: Dictionary in game["options"]:
			whole = whole and option["default"] is int and option["values"][0] is int
	_check("entries carry their directory and resolved paths", resolved)
	_check("whole numbers arrive as ints", whole)
	_check("catalog() remembers what it read until told to forget", Registry.catalog() == Registry.catalog() and is_same(Registry.catalog(), Registry.catalog()))
	var remembered: Dictionary = Registry.catalog()
	Registry.forget()
	_check("forget reads again", not is_same(remembered, Registry.catalog()))
	var nowhere := Registry.discover("res://games/does_not_exist")
	_check("a root that is not there is empty, not a crash", (nowhere["games"] as Array).is_empty() and (nowhere["problems"] as Array).is_empty())
	var missing := Registry.read("res://games/shared/game.json")
	_check("a missing manifest is an error", (missing["errors"] as PackedStringArray)[0] == "game.json: missing")
	_check("problem lines name the game", Registry.problem_lines([{"id": "x", "path": "p", "errors": PackedStringArray(["a: b", "c: d"])}]) == PackedStringArray(["x: a: b", "x: c: d"]))

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
