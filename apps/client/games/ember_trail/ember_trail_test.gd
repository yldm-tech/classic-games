extends SceneTree

## Headless tests of Ember Trail. Everything is driven through feed() and advance(), as a player would drive it: the scripted player at the bottom of this file reads the stage and presses the same controls a person has, so a stage it clears is a stage that can be cleared.
## Run: GODOT=/path/to/godot scripts/run-godot-test.sh res://games/ember_trail/ember_trail_test.gd '^ember_trail_test: [0-9]+ passed, 0 failed$'

const Main := preload("res://games/ember_trail/main.gd")
const Levels := preload("res://games/ember_trail/levels.gd")
const World := preload("res://games/ember_trail/world.gd")
const Art := preload("res://games/ember_trail/art.gd")
const Texts := preload("res://games/ember_trail/texts.gd")
const Body := preload("res://games/ember_trail/body.gd")

const STAGE := Vector2i(480, 270)
const STEP := GameModule.STEP

var _passed := 0
var _failed := 0
## Whether the scripted player was holding jump in the previous step.
var _bot_jump := false
## The height the scripted player last stood at.
var _bot_from := 0.0

func _initialize() -> void:
	_test_levels()
	_test_art()
	_test_world()
	_test_start()
	_test_movement()
	_test_sparks()
	_test_flame_and_defeat()
	_test_pit_and_hits()
	_test_stage_clear()
	_test_guardians()
	_test_full_run()
	_test_determinism()
	print("ember_trail_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _start(options: Dictionary = {}, seed_value: int = 7, locale: String = "zh") -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": 1, "seed": seed_value, "options": options, "locale": locale, "stage_size": STAGE})
	return game

func _results(game: GameModule) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	return results

func _hold(game: GameModule, controls: Array, seconds: float) -> void:
	for control: StringName in GameInput.CONTROLS:
		game.feed(0, control, 1.0 if String(control) in controls else 0.0)
	game.advance(seconds)

func _tap(game: GameModule, control: StringName) -> void:
	game.feed(0, control, 1.0)
	game.advance(STEP)
	game.feed(0, control, 0.0)
	game.advance(STEP)

# ---- data ----

func _test_levels() -> void:
	var sound := true
	var counts: Array = []
	for index in Levels.STAGES.size():
		var built: Dictionary = Levels.build(index)
		sound = sound and (built["problems"] as Array).is_empty()
		var lamps := 0
		var goals := 0
		var flasks := 0
		for spawn: Dictionary in built["spawns"]:
			lamps += int(spawn["kind"] == "L")
			goals += int(spawn["kind"] == "G")
			flasks += int(spawn["kind"] == "f")
		counts.append([lamps, goals, flasks, built["world"].width])
		for problem: String in built["problems"]:
			push_error("stage %d: %s" % [index, problem])
	_check("every stage is drawn without a ragged row", sound)
	var shaped := true
	for index in Levels.STAGES.size():
		var is_boss: bool = Levels.STAGES[index]["boss"] != ""
		if is_boss:
			shaped = shaped and counts[index][1] == 0 and counts[index][0] == 1 and counts[index][3] == 34
		else:
			shaped = shaped and counts[index][1] == 1 and counts[index][0] >= 2 and counts[index][2] >= 9 and counts[index][3] >= 480
	_check("a trail stage has one beacon, two lamp posts, flasks to live on and real length; a guardian's stage is one arena", shaped)
	_check("two areas of three stages, each ending with a guardian", Levels.STAGES.size() == 6 and Levels.STAGES[2]["boss"] == "toad" and Levels.STAGES[5]["boss"] == "owl" and Levels.STAGES[0]["area"] == 1 and Levels.STAGES[3]["area"] == 2)

func _test_art() -> void:
	var images: Dictionary = Art.build_images()
	var complete := true
	for key in ["hero_idle", "hero_run", "hero_jump", "hero_fall", "hero_throw", "hero_hurt", "hero_ride", "ram", "cinderling", "sootwing", "ventcrab", "rimebeetle", "driftwisp", "shardling", "toad", "owl", "moth", "flask", "resin", "wick", "bell", "spark", "glob", "icicle", "shard", "wave", "cinder", "lamp", "beacon", "vent", "column", "t1_top", "t2_top", "t1_fill", "t2_fill", "t2_ice", "t1_plat", "t2_plat", "t1_crumble", "t2_crumble", "t1_spike", "t2_spike", "t1_liquid", "t2_liquid", "mover1", "mover2", "sky1", "sky2", "far1", "far2", "near1", "near2", "hero_run_w", "toad_w", "owl_w"]:
		if not images.has(key) or (images[key] as Array).is_empty():
			complete = false
			push_error("no picture for %s" % key)
	_check("every picture the renderer asks for is built", complete)
	_check("the hero has several frames for each thing he does", (images["hero_run"] as Array).size() == 4 and (images["hero_idle"] as Array).size() == 2 and (images["hero_throw"] as Array).size() == 3 and (images["ram"] as Array).size() == 4)
	var both := true
	for key: String in Texts.TEXT:
		both = both and str(Texts.TEXT[key].get("zh", "")) != "" and str(Texts.TEXT[key].get("en", "")) != ""
	_check("every line the game writes exists in Chinese and English", both)

## The collision rules on a hand-made patch of tiles: a floor along row 6, a one-way ledge and a crumbling slab on row 3, a wall at column 9.
func _test_world() -> void:
	var world := World.new()
	world.width = 12
	world.tiles.resize(12 * World.ROWS)
	world.tiles.fill(World.EMPTY)
	for tx in 12:
		world.tiles[6 * 12 + tx] = World.SOLID
	world.tiles[3 * 12 + 2] = World.ONEWAY
	world.tiles[3 * 12 + 5] = World.CRUMBLE
	for ty in range(0, 6):
		world.tiles[ty * 12 + 9] = World.SOLID
	var body := Body.new()
	body.pos = Vector2(40.0, 20.0)
	for step in 120:
		body.vel.y = minf(body.vel.y + 880.0 * STEP, 420.0)
		world.move_body(body, STEP)
	_check("a falling body comes to rest on a one-way ledge", body.on_ground and is_equal_approx(body.pos.y, 48.0) and body.ground_tile == World.ONEWAY)
	body.pos = Vector2(40.0, 94.0)
	body.vel = Vector2(0.0, -330.0)
	var rose := 94.0
	for step in 120:
		body.vel.y = minf(body.vel.y + 880.0 * STEP, 420.0)
		world.move_body(body, STEP)
		rose = minf(rose, body.pos.y)
	_check("the same ledge lets a body through from below and catches it on the way down", rose < 44.0 and body.on_ground and is_equal_approx(body.pos.y, 48.0))
	body.pos = Vector2(120.0, 96.0)
	body.vel = Vector2(100.0, 0.0)
	for step in 60:
		body.vel.x = 100.0
		world.move_body(body, STEP)
	_check("a wall stops a body and reports it", body.pos.x < 144.0 - body.hw + 0.5 and body.pos.x > 136.0 and is_equal_approx(body.pos.y, 96.0))
	body.pos = Vector2(120.0, 90.0)
	body.vel = Vector2(0.0, -200.0)
	world.tiles[2 * 12 + 7] = World.SOLID
	for step in 30:
		world.move_body(body, STEP)
	_check("solid rock overhead stops a jump", is_equal_approx(body.pos.y, 48.0 + body.h) and body.vel.y == 0.0)
	_check("a crumbling slab holds until it is stepped on", world.standable(5, 3) and world.touch_crumble(5, 3) and not world.touch_crumble(5, 3))
	var fell: Array = world.step_crumbles(World.CRUMBLE_HOLD + 0.01, Rect2())
	_check("then it falls", fell == [3 * 12 + 5] and world.tile(5, 3) == World.EMPTY)
	world.step_crumbles(World.CRUMBLE_BACK, Rect2(80.0, 40.0, 10.0, 10.0))
	var blocked: bool = world.tile(5, 3) == World.EMPTY
	world.step_crumbles(0.1, Rect2())
	_check("and grows back once nothing stands in its place", blocked and world.tile(5, 3) == World.CRUMBLE)
	world.plats.append({"x": 0.0, "y": 0.0, "w": 40.0, "x0": 16.0, "y0": 80.0, "range": 80.0, "period": 4.0, "phase": 0.0, "axis": "x", "dx": 0.0, "dy": 0.0})
	world.step_plats(0.0)
	var left_end := float(world.plats[0]["x"])
	world.step_plats(2.0)
	_check("a moving platform swings between its two ends and says how far it moved", is_equal_approx(left_end, 16.0) and is_equal_approx(float(world.plats[0]["x"]), 96.0) and is_equal_approx(float(world.plats[0]["dx"]), 80.0))

# ---- rules ----

func _test_start() -> void:
	var game := _start()
	var first := game.snapshot()
	_check("a run starts on stage 1 of 6 with three lives and a full flame", first["stage"] == 1 and first["stages_total"] == 6 and first["lives"] == 3 and first["flame"] == 100 and first["flame_max"] == 100 and first["full_run"] == 1 and first["phase"] == "intro")
	_check("the HUD's per-player fields are reported for the one seat", (first["players"] as Array).size() == 1 and first["players"][0]["flame"] == 100 and first["players"][0]["lives"] == 3 and not first.has("boss_hp"))
	_check("the stage tune is playing and the effects are defined", game.audio.music_playing and game.audio.has_sound("jump") and game.audio.has_sound("boss_down"))
	_check("the stage is announced in the player's language", str(game.banner["title"]).contains("1-1") and str(game.banner["sub"]) == "烬原古道")
	game.free()
	game = _start({"difficulty": 1, "start": 4}, 7, "en")
	var eased := game.snapshot()
	_check("the options set the lives and the first stage, and a later start is marked as practice", eased["lives"] == 5 and eased["stage"] == 4 and eased["full_run"] == 0 and eased["difficulty"] == 1 and str(game.banner["sub"]) == "RIME HOLLOW")
	game.free()

func _test_movement() -> void:
	var game := _start()
	var floor_y := float(game.snapshot()["hero_y"])
	_hold(game, ["right"], 1.0)
	var moved := game.snapshot()
	_check("holding right runs along the ground and the camera follows later", float(moved["hero_x"]) > 120.0 and is_equal_approx(float(moved["hero_y"]), floor_y))
	_hold(game, ["left"], 3.0)
	_check("the left edge of the stage is a wall", float(game.snapshot()["hero_x"]) >= 5.0 and float(game.snapshot()["hero_x"]) < 8.0)
	_hold(game, [], 0.2)
	_hold(game, ["a"], 0.25)
	var high := floor_y - float(game.snapshot()["hero_y"])
	_hold(game, ["a"], 0.6)
	_check("a held jump rises about three tiles and comes back down to the ground", high > 44.0 and high < 60.0 and is_equal_approx(float(game.snapshot()["hero_y"]), floor_y) and int(game.audio.played.get("jump", 0)) == 1)
	_hold(game, [], 0.1)
	var top := 0.0
	game.feed(0, &"a", 1.0)
	game.advance(STEP * 4.0)
	game.feed(0, &"a", 0.0)
	for step in 40:
		game.advance(STEP)
		top = maxf(top, floor_y - float(game.snapshot()["hero_y"]))
	_check("letting go of jump early makes a short hop", top > 8.0 and top < 30.0)
	_hold(game, ["right"], 2.6)
	_check("the camera scrolls with the hero", float(game.snapshot()["camera_x"]) > 40.0)
	game.free()

func _test_sparks() -> void:
	var game := _start()
	_hold(game, [], 1.5)
	_hold(game, ["b"], STEP)
	_check("throwing puts a spark in the air", game.shots.size() == 1 and int(game.audio.played.get("throw", 0)) == 1)
	var level: float = game.shots[0]["vel"].y
	_hold(game, ["b"], 0.6)
	_check("at most three sparks fly at once and they burn out", game.shots.size() <= 3 and int(game.audio.played.get("throw", 0)) >= 3)
	_hold(game, [], 1.5)
	_hold(game, ["b", "up"], STEP)
	_check("holding up lobs the spark high", game.shots.size() == 1 and float(game.shots[0]["vel"].y) < level - 200.0)
	_hold(game, [], 1.5)
	var before := game.snapshot()
	_hold(game, ["right", "b"], 5.0)
	var after := game.snapshot()
	_check("a spark burns a cinderling down and pays for it", int(after["kills"]) >= 1 and int(after["score"]) >= 100 and int(game.audio.played.get("creature_down", 0)) >= 1)
	_check("glow moths on the way are collected and counted", int(after["moths"]) > int(before["moths"]))
	game.free()

func _test_flame_and_defeat() -> void:
	var game := _start({"difficulty": 3})
	var results := _results(game)
	_hold(game, [], 1.4)
	var lit := float(game.flame)
	_hold(game, [], 10.0)
	_check("the flame burns down by itself while the stage is live", is_equal_approx(lit, 100.0) and absf((lit - float(game.flame)) - 21.0) < 0.2)
	_hold(game, [], 41.0)
	var once := game.snapshot()
	_check("when the flame goes out a life is lost and the stage starts again with a full flame", once["deaths"] == 1 and once["lives"] == 1 and once["flame"] > 90 and float(once["hero_x"]) < 60.0 and int(game.audio.played.get("die", 0)) == 1)
	_hold(game, [], 51.5)
	var again := game.snapshot()
	_check("out of lives, a continue refills them", again["deaths"] == 2 and again["continues_used"] == 1 and again["continues"] == 0 and again["lives"] == 2 and results.is_empty())
	_hold(game, [], 115.0)
	_check("with no continue left the run is lost", results.size() == 1 and results[0]["defeated"] == true and results[0]["cleared"] == false and results[0]["deaths"] == 4 and results[0]["lives"] == 0 and results[0]["continues_used"] == 1 and not game.audio.music_playing)
	game.free()

func _test_pit_and_hits() -> void:
	var game := _start()
	_hold(game, ["right"], 6.0)
	var hurt := game.snapshot()
	_check("running into a creature costs a chunk of the flame", int(hurt["hits_taken"]) >= 1 and int(hurt["flame"]) < 100 - 22 and int(game.audio.played.get("hurt", 0)) >= 1)
	_hold(game, ["right"], 9.0)
	var fallen := game.snapshot()
	_check("a pit takes a life whatever the flame", int(fallen["deaths"]) == 1 and int(fallen["lives"]) == 2 and int(game.audio.played.get("splash", 0)) == 1)
	game.free()

	# The scripted player reaches the first lamp post; dying after that brings the hero back to it.
	game = _start()
	var lamp_x: float = game.lamps[0]["pos"].x
	_play(game, 60.0, func() -> bool: return bool(game.lamps[0]["lit"]))
	var flame_at_lamp := float(game.flame)
	_check("passing a lamp post lights it", game.lamps[0]["lit"] == true and game.checkpoint == 0 and int(game.audio.played.get("lamp", 0)) == 1 and flame_at_lamp > 60.0)
	var deaths_before: int = game.deaths
	_hold(game, [], 70.0)
	var back := game.snapshot()
	_check("after a death the hero comes back at the lamp he lit, not at the start", int(back["deaths"]) == deaths_before + 1 and absf(float(back["hero_x"]) - lamp_x) < 60.0)
	game.free()

func _test_stage_clear() -> void:
	var game := _start()
	var seen := {"mounted": false}
	var seconds := _play(game, 240.0, func() -> bool:
		seen["mounted"] = seen["mounted"] or game.hero.mounted
		return game.phase == "clear")
	var cleared := game.snapshot()
	print("  stage 1-1 took the scripted player %.0f s, %d deaths, flame %d, moths %d" % [seconds, cleared["deaths"], cleared["flame"], cleared["moths"]])
	_check("the scripted player reaches the beacon of stage 1-1", cleared["phase"] == "clear" and cleared["stages_cleared"] == 1 and int(game.audio.played.get("beacon", 0)) == 1)
	_check("the herding bell on the way puts him on the ashhorn", seen["mounted"] and int(game.audio.played.get("bell", 0)) >= 1)
	var before: int = cleared["score"]
	_hold(game, [], 3.2)
	var next := game.snapshot()
	_check("lighting the beacon pays a flame bonus and opens the next stage", next["stage"] == 2 and int(next["score"]) >= before + 500 and next["phase"] == "intro" and next["flame"] == 100 and float(next["hero_x"]) < 60.0)
	game.free()

func _test_guardians() -> void:
	var game := _start({"start": 3})
	var results := _results(game)
	_hold(game, [], 2.0)
	var fight := game.snapshot()
	_check("the guardian's health is reported while it stands", fight.has("boss_hp") and fight["boss_hp"] == fight["boss_max_hp"] and int(fight["boss_max_hp"]) == 36)
	_check("the guardian has its own tune", game.track == "boss" and game.audio.music_playing)
	var seconds := _play(game, 240.0, func() -> bool: return int(game.stage_i) == 3)
	var after := game.snapshot()
	print("  Magmaw took the scripted player %.0f s, %d deaths" % [seconds, after["deaths"]])
	_check("beating the toad clears the first area and leads into the hollow", after["stage"] == 4 and after["areas_cleared"] == 1 and not after.has("boss_hp") and int(after["score"]) >= 2000 and results.is_empty())
	game.free()

	game = _start({"start": 6})
	results = _results(game)
	seconds = _play(game, 300.0, func() -> bool: return not results.is_empty())
	print("  Rimewing took the scripted player %.0f s" % seconds)
	_check("beating the owl clears the run", results.size() == 1 and results[0]["cleared"] == true and results[0]["defeated"] == false and results[0]["areas_cleared"] == 1)
	_check("a run that began past the first stage is practice", results.size() == 1 and results[0]["full_run"] == 0)
	game.free()

func _test_full_run() -> void:
	var game := _start({"difficulty": 1}, 11)
	var results := _results(game)
	var marks: Array = []
	var seconds := _play(game, 1500.0, func() -> bool:
		if marks.size() < int(game.stage_i):
			marks.append(game.elapsed)
		return not results.is_empty())
	print("  full run by the scripted player: %.0f s, stage marks %s" % [seconds, str(marks)])
	if not results.is_empty():
		print("  result: cleared=%s deaths=%d continues_used=%d moths=%d kills=%d stomps=%d score=%d" % [results[0]["cleared"], results[0]["deaths"], results[0]["continues_used"], results[0]["moths"], results[0]["kills"], results[0]["mount_stomps"], results[0]["score"]])
	_check("one player can finish the whole trail from the first stage", results.size() == 1 and results[0]["cleared"] == true and results[0]["full_run"] == 1 and results[0]["areas_cleared"] == 2 and results[0]["stages_cleared"] == 6)
	_check("the result carries what the achievements read", results.size() == 1 and results[0].has("continues_used") and results[0].has("difficulty") and int(results[0]["moths"]) >= 40 and int(results[0]["kills"]) >= 20 and int(results[0]["mount_stomps"]) >= 1 and int(results[0]["score"]) > 10000)
	game.free()

func _test_determinism() -> void:
	var states: Array = []
	for attempt in 2:
		var game := _start({}, 77)
		_hold(game, ["right", "b"], 4.0)
		_hold(game, ["right", "a"], 0.5)
		_hold(game, ["right", "b"], 8.0)
		_play(game, 45.0, func() -> bool: return false)
		states.append(game.snapshot())
		game.free()
	_check("the same seed and the same inputs give the same run", states[0] == states[1] and float(states[0]["hero_x"]) > 300.0)

# ---- the scripted player ----

## Play until `done` says so or `limit` game seconds pass. Returns the seconds played.
func _play(game: GameModule, limit: float, done: Callable) -> float:
	var began: float = game.elapsed
	_bot_jump = false
	while game.is_running() and game.elapsed - began < limit:
		if done.call():
			break
		_drive(game)
		game.advance(STEP)
	for control: StringName in GameInput.CONTROLS:
		game.feed(0, control, 0.0)
	return game.elapsed - began

func _drive(game: GameModule) -> void:
	var keys := {"left": false, "right": false, "up": false, "a": false, "b": true}
	if not game.hero.dead and game.phase in ["intro", "play"]:
		if game.boss != null:
			_drive_fight(game, keys)
		else:
			_drive_trail(game, keys)
	_bot_jump = keys["a"]
	for key: String in keys:
		game.feed(0, StringName(key), 1.0 if keys[key] else 0.0)

func _col(x: float) -> int:
	return int(floor(x / World.TILE))

## The height of the first safe thing to stand on in the column of `x`, at or below `from_y`; a huge value over a pit or over spikes.
func _landing(game: GameModule, x: float, from_y: float) -> float:
	var world: RefCounted = game.world
	var best := 9999.0
	for plat: Dictionary in world.plats:
		if x > float(plat["x"]) + 2.0 and x < float(plat["x"]) + float(plat["w"]) - 2.0 and float(plat["y"]) >= from_y - 1.0:
			best = minf(best, float(plat["y"]))
	var column := _col(x)
	for ty in range(maxi(0, int(floor((from_y - 0.5) / World.TILE))), World.ROWS):
		if world.standable(column, ty):
			if float(ty * World.TILE) >= from_y - 1.0:
				if world.tile(column, ty - 1) != World.SPIKE:
					best = minf(best, float(ty * World.TILE))
				break
			if world.solid(column, ty):
				# The side of a step: not a place to land, but not a pit either.
				best = minf(best, float(ty * World.TILE))
				break
	return best

## Whether a jump from here can come down on something safe ahead.
func _can_reach(game: GameModule, x: float, feet: float, reach: float) -> bool:
	var distance := 10.0
	while distance <= reach:
		var top := _landing(game, x + distance, feet - 46.0)
		if top < 9000.0 and distance <= reach - maxf(0.0, feet - top) * 0.3:
			return true
		distance += 2.0
	return false

func _drive_trail(game: GameModule, keys: Dictionary) -> void:
	var hero: RefCounted = game.hero
	var world: RefCounted = game.world
	var x: float = hero.pos.x
	var feet: float = hero.pos.y
	var front: float = x + hero.hw
	keys["right"] = true
	if hero.on_ground:
		_bot_from = feet
		var jump := false
		var wall: bool = world.solid(_col(front + 5.0), int(floor((feet - 4.0) / World.TILE)))
		var danger := _landing(game, front + 5.0, feet) > 9000.0
		if wall:
			jump = true
		elif danger:
			if _can_reach(game, x, feet, 100.0 if hero.mounted else 60.0):
				jump = true
			else:
				keys["right"] = false
				# Nothing ahead to land on, but a ledge overhead: climb onto it.
				for up in [1, 2]:
					var code: int = world.tile(_col(x), int(floor((feet - 1.0) / World.TILE)) - up)
					jump = jump or code == World.ONEWAY or code == World.CRUMBLE
		for geyser: Dictionary in game.geysers:
			var ahead: float = geyser["pos"].x - x
			if ahead > 4.0 and ahead < 44.0 and absf(float(geyser["pos"].y) - feet) < 20.0 and fmod(game.stage_time + float(geyser["offset"]), game.GEYSER_PERIOD) > 1.15:
				keys["right"] = false
				jump = false
		for creature: RefCounted in game.creatures:
			var ahead: float = creature.pos.x - x
			# A driftwisp comes to him: stand, let it line up with the sparks, and lob while it is still overhead.
			if creature.kind == "d" and creature.awake and not creature.gone and ahead > 0.0 and ahead < 110.0 and hero.ground_tile != World.CRUMBLE:
				keys["right"] = false
				keys["up"] = creature.pos.y < feet - 30.0
				jump = false
			if creature.awake and not creature.gone and ahead > -4.0 and ahead < 30.0 and creature.pos.y > feet - 44.0 and creature.pos.y - creature.h < feet + 2.0:
				# Jump over it only if the jump comes down on something; otherwise hold the ground and keep throwing.
				var carry := 104.0 if hero.mounted else 66.0
				if _landing(game, x + carry, feet) < 9000.0 and _landing(game, x + carry + 10.0, feet) < 9000.0:
					jump = true
				elif not danger:
					keys["right"] = false
		# A press only counts when the button was up the step before.
		keys["a"] = jump and not _bot_jump
		if jump and _bot_jump:
			keys["a"] = false
	else:
		keys["a"] = hero.vel.y < 0.0
		var below := _landing(game, x, feet)
		# Over something safe with nothing safe beyond it: stop and come down here. On the way up that only holds for a ledge higher than where the jump began.
		if below < 9000.0 and (hero.vel.y > 0.0 or below < _bot_from - 4.0) and _landing(game, front + 7.0, feet) > 9000.0:
			keys["right"] = false
			keys["left"] = hero.vel.x > 30.0

func _drive_fight(game: GameModule, keys: Dictionary) -> void:
	var hero: RefCounted = game.hero
	var boss: RefCounted = game.boss
	var x: float = hero.pos.x
	var feet: float = hero.pos.y
	var gap: float = boss.pos.x - x
	var toward := "right" if gap > 0.0 else "left"
	var away := "left" if gap > 0.0 else "right"
	var jump := false
	var near := 110.0 if boss.kind == "toad" else 60.0
	var far := 190.0 if boss.kind == "toad" else 105.0
	if absf(gap) < near:
		# Backed against a wall, the only way out is past the guardian.
		var cornered := (away == "left" and x < 60.0) or (away == "right" and x > 484.0)
		keys[toward if cornered and boss.pos.y < feet - 30.0 else away] = true
	elif absf(gap) > far or hero.facing != (1 if gap > 0.0 else -1):
		keys[toward] = true
	if boss.kind == "toad":
		if boss.state == "air" and absf(gap) < 80.0 and boss.pos.y < feet - 20.0:
			keys["left"] = false
			keys["right"] = false
			keys["right" if (boss.vel.x < 0.0 and x < 470.0) or x < 70.0 else "left"] = true
	else:
		keys["up"] = boss.pos.y < feet - 40.0
		if boss.state == "swoop" and absf(gap) < 76.0 and boss.pos.y > feet - 50.0:
			jump = true
	for hazard: Dictionary in game.hazards:
		var at: Vector2 = hazard["pos"]
		var velocity: Vector2 = hazard["vel"]
		if absf(at.x - x) < 36.0 and at.y > feet - 60.0 and (velocity.x == 0.0 or (velocity.x > 0.0) == (at.x < x)):
			jump = true
	for icicle: Dictionary in game.icicles:
		var at: Vector2 = icicle["pos"]
		if absf(at.x - x) < 15.0:
			keys["left"] = at.x >= x and x > 50.0
			keys["right"] = not keys["left"]
	if hero.on_ground:
		keys["a"] = jump and not _bot_jump
	else:
		keys["a"] = hero.vel.y < 0.0

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
