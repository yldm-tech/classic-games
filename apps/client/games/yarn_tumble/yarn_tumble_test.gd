extends SceneTree

## Headless tests of Yarn Tumble: the rules are driven through the same inputs a player has (feed + advance); where a test needs a particular situation it arranges the world's creatures directly and then plays it with real inputs.
## Run: GODOT=/path/to/godot scripts/run-godot-test.sh res://games/yarn_tumble/yarn_tumble_test.gd '^yarn_tumble_test: [0-9]+ passed, 0 failed$'

const Main := preload("res://games/yarn_tumble/main.gd")
const World := preload("res://games/yarn_tumble/world.gd")
const Hero := preload("res://games/yarn_tumble/hero.gd")
const Foe := preload("res://games/yarn_tumble/foe.gd")
const Item := preload("res://games/yarn_tumble/item.gd")
const Levels := preload("res://games/yarn_tumble/levels.gd")
const Sprites := preload("res://games/yarn_tumble/sprites.gd")
const Sounds := preload("res://games/yarn_tumble/sounds.gd")

const FLOOR_Y := 254.0

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_data()
	_test_start_and_movement()
	_test_wrap_and_unwrap()
	_test_kick_chain_and_clear()
	_test_ball_drops_between_ledges()
	_test_pickups()
	_test_lives_continues_and_defeat()
	_test_second_batch()
	_test_hurry()
	_test_guardian_and_victory()
	_test_two_players()
	_test_determinism()
	print("yarn_tumble_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- helpers ----

func _start(players: int, seed_value: int, options: Dictionary = {}) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": Vector2i(480, 270)})
	return game

func _w(game: GameModule) -> World:
	return game.get("world")

func _tap(game: GameModule, slot: int, control: StringName) -> void:
	game.feed(slot, control, 1.0)
	game.advance(GameModule.STEP)
	game.feed(slot, control, 0.0)
	game.advance(GameModule.STEP)

## Put one creature on the bottom floor, already roaming.
func _foe(game: GameModule, kind: String, x: float, facing: int = 1) -> Foe:
	var foe := Foe.new(kind)
	foe.x = x
	foe.y = FLOOR_Y
	foe.state = Foe.ROAM
	foe.facing = facing
	foe.ai_timer = 30.0
	_w(game).foes.append(foe)
	return foe

## Empty the floor and stand player one at `x` on the bottom floor, facing right, with no spawn protection.
func _arrange(game: GameModule, x: float) -> Hero:
	_w(game).foes.clear()
	var hero: Hero = _w(game).heroes[0]
	hero.state = Hero.ALIVE
	hero.x = x
	hero.y = FLOOR_Y
	hero.vx = 0.0
	hero.vy = 0.0
	hero.facing = 1
	hero.invuln = 0.0
	hero.cooldown = 0.0
	return hero

## Hold a control until the condition holds or the time runs out; returns whether it held.
func _hold_until(game: GameModule, slot: int, control: StringName, seconds: float, condition: Callable) -> bool:
	game.feed(slot, control, 1.0)
	var met := false
	for step in int(seconds * 60.0):
		game.advance(GameModule.STEP)
		if condition.call():
			met = true
			break
	game.feed(slot, control, 0.0)
	return met

# ---- tests ----

func _test_data() -> void:
	_check("every sprite row is as wide as its sprite", Sprites.problems().is_empty())
	var bosses := 0
	var kinds := {}
	var sound := true
	for def: Dictionary in Levels.STAGES:
		if def.has("boss"):
			bosses += 1
		sound = sound and (def["spawn"] as Array).size() == 2 and Levels.build(def).size() == Levels.COLS * Levels.ROWS
		var listed: Array = (def["foes"] as Array) + (def.get("more", []) as Array)
		for entry: Array in listed:
			kinds[entry[0]] = true
			sound = sound and Foe.KINDS.has(entry[0]) and int(entry[1]) >= 1 and int(entry[1]) <= 28
			if entry[0] != Foe.SNIP:
				# A walking creature has to start on something.
				sound = sound and Levels.build(def)[int(entry[2]) * Levels.COLS + int(entry[1])] != Levels.EMPTY
		for point: Array in def["spawn"]:
			sound = sound and Levels.build(def)[int(point[1]) * Levels.COLS + int(point[0])] == Levels.SOLID
	_check("the tower has fourteen floors, two of them guarded", Levels.count() == 14 and bosses == 2 and Levels.STAGES[6].has("boss") and Levels.STAGES[13].has("boss"))
	_check("every floor is well formed and all five pests appear", sound and kinds.size() == 5)
	var defined := true
	for track in 3:
		defined = defined and (Sounds.music(track)["voices"] as Array).size() == 3
	_check("three music loops are written", defined and Sounds.track_for(1, false) != Sounds.track_for(9, false) and Sounds.track_for(7, true) == 2)

func _test_start_and_movement() -> void:
	var game := _start(2, 11)
	var first := game.snapshot()
	_check("a run starts on floor 1 with full lives for both knitters", first["stage"] == 1 and first["stages_total"] == 14 and first["players"][0]["lives"] == 4 and first["players"][1]["lives"] == 4 and first["players"][0]["max_lives"] == 4 and first["foes_left"] == 3 and first["score"] == 0)
	_check("the stage music starts and no guardian bar shows", game.audio.music_playing and not first.has("boss_hp"))
	game.feed(0, &"left", 1.0)
	game.feed(1, &"right", 1.0)
	game.advance(0.5)
	var moved := game.snapshot()
	_check("each knitter moves by their own input", float(moved["players"][0]["x"]) < float(first["players"][0]["x"]) - 30.0 and float(moved["players"][1]["x"]) > float(first["players"][1]["x"]) + 30.0)
	_w(game).foes.clear()
	game.advance(6.0)
	_check("the side walls stop a knitter", is_equal_approx(float(game.snapshot()["players"][0]["x"]), 16.0 + 4.0 + 0.01) and _w(game).stage == 2)
	game.free()

	game = _start(1, 11)
	var hero := _arrange(game, 100.0)
	_tap(game, 0, &"a")
	_check("jumping asks for its sound and leaves the ground", int(game.audio.played.get("jump", 0)) == 1 and hero.y < FLOOR_Y and not hero.on_ground)
	game.advance(0.8)
	game.feed(0, &"a", 1.0)
	game.advance(1.0)
	game.feed(0, &"a", 0.0)
	game.advance(GameModule.STEP)
	_check("a held jump from the floor lands on the ledge three tiles up", hero.on_ground and is_equal_approx(hero.y, 13.0 * 16.0 - 2.0))
	game.feed(0, &"down", 1.0)
	_tap(game, 0, &"a")
	game.feed(0, &"down", 0.0)
	game.advance(0.6)
	_check("down and jump drops through a ledge back to the floor", hero.on_ground and is_equal_approx(hero.y, FLOOR_Y))
	game.feed(0, &"down", 1.0)
	_tap(game, 0, &"a")
	game.feed(0, &"down", 0.0)
	game.advance(0.05)
	_check("the solid floor cannot be dropped through", hero.y <= FLOOR_Y)
	game.free()

	game = _start(1, 11, {"first_floor": 5})
	hero = _arrange(game, 7.5 * 16.0)
	hero.y = 250.0
	hero.on_ground = false
	game.advance(1.2)
	_check("whoever falls into a pit comes back from the top", hero.state == Hero.ALIVE and hero.on_ground and hero.y < FLOOR_Y)
	game.free()

func _test_wrap_and_unwrap() -> void:
	var game := _start(1, 21)
	var hero := _arrange(game, 200.0)
	var moth := _foe(game, Foe.MOTH, 232.0)
	_tap(game, 0, &"b")
	game.advance(0.2)
	_check("one hit of yarn winds a pest once and stops it", moth.state == Foe.WRAP and moth.wrap == 1 and hero.score == 10 and int(game.audio.played.get("wrap", 0)) == 1)
	var held_x := moth.x
	game.advance(1.0)
	_check("a half-wound pest stays where it is and cannot hurt", is_equal_approx(moth.x, held_x) and hero.state == Hero.ALIVE)
	game.advance(1.5)
	_check("left alone it wriggles free, angry", moth.state == Foe.ROAM and moth.wrap == 0 and moth.angry and int(game.audio.played.get("free", 0)) == 1)
	moth.x = 232.0
	moth.facing = 1
	var balled := _hold_until(game, 0, &"b", 2.0, func() -> bool: return moth.state == Foe.BALL)
	_check("three hits finish the ball", balled and moth.wrap == moth.need and moth.need == 3 and int(game.audio.played.get("ball", 0)) == 1)
	_check("the ball is worth its points", hero.score == 10 + 10 * 3 + 90)
	var ball_x := moth.x
	hero.x = moth.x - 9.0
	game.feed(0, &"right", 1.0)
	game.advance(0.5)
	game.feed(0, &"right", 0.0)
	_check("walking into a ball pushes it along", moth.state == Foe.BALL and moth.x > ball_x + 15.0)
	hero.x = 60.0
	game.advance(World.BALL_TIME[1])
	_check("a ball left too long loosens again", moth.state == Foe.WRAP and moth.wrap == moth.need - 1)
	game.free()

func _test_kick_chain_and_clear() -> void:
	var game := _start(1, 31)
	var hero := _arrange(game, 200.0)
	var ball := _foe(game, Foe.MOTH, 226.0)
	var second := _foe(game, Foe.SPRING, 320.0)
	var third := _foe(game, Foe.PIN, 400.0)
	second.ai_timer = 30.0
	third.ai_timer = 30.0
	third.facing = -1
	_hold_until(game, 0, &"b", 2.0, func() -> bool: return ball.state == Foe.BALL)
	game.advance(0.3)
	var before := hero.score
	_tap(game, 0, &"b")
	game.advance(0.05)
	_check("yarn on a finished ball kicks it away", ball.state == Foe.ROLL and ball.dir == 1 and int(game.audio.played.get("kick", 0)) == 1)
	game.advance(1.6)
	_check("the rolling ball knocks out everything in its way and turns at the wall", _w(game).foes.size() == 1 and ball.state == Foe.ROLL and ball.dir == -1 and ball.chain == 2)
	game.advance(2.6)
	var state := game.snapshot()
	_check("it bursts on the second wall of the floor", _w(game).foes.is_empty() and state["kos"] == 3 and state["best_roll"] == 3)
	_check("each pest in the chain is worth more than the last", hero.score - before == 1000 + 2000 + 500 + _w(game).last_bonus and int(game.audio.played.get("ko", 0)) == 2 and int(game.audio.played.get("burst", 0)) == 1)
	var kinds := {}
	for item: Item in _w(game).pickups:
		kinds[item.kind] = true
	_check("chained knock-outs drop a button, a thimble and a power-up", kinds.has("button") and kinds.has("thimble") and _w(game).pickups.size() == 3)
	_check("an empty floor is cleared with a bonus", _w(game).phase == World.CLEAR and _w(game).last_bonus >= 3500 and int(game.audio.played.get("note", 0)) >= 1)
	game.advance(3.0)
	_check("and the knitters climb to the next floor", game.snapshot()["stage"] == 2 and _w(game).phase == World.PLAY and _w(game).foes.size() == 4 and game.snapshot()["score"] == hero.score)
	game.free()

func _test_ball_drops_between_ledges() -> void:
	var game := _start(1, 41)
	var hero := _arrange(game, 100.0)
	hero.y = 13.0 * 16.0 - 2.0
	var ball := _foe(game, Foe.MOTH, 126.0)
	ball.y = hero.y
	var below := _foe(game, Foe.MOTH, 300.0)
	_hold_until(game, 0, &"b", 2.0, func() -> bool: return ball.state == Foe.BALL)
	game.advance(0.3)
	_tap(game, 0, &"b")
	var fell := false
	for step in 120:
		game.advance(GameModule.STEP)
		if ball.state == Foe.ROLL and ball.on_ground and is_equal_approx(ball.y, FLOOR_Y):
			fell = true
			break
	_check("a ball kicked off a ledge falls to the floor below and keeps rolling", fell and ball.dir == 1)
	game.advance(5.0)
	_check("and takes the pest down there with it", below.state == Foe.GONE and _w(game).best_roll == 2)
	game.free()

func _test_pickups() -> void:
	var game := _start(1, 51)
	var hero := _arrange(game, 200.0)
	_foe(game, Foe.MOTH, 420.0).facing = 1
	_w(game).drop("spool", 200.0, FLOOR_Y)
	_w(game).drop("long", 200.0, FLOOR_Y)
	game.advance(0.8)
	_check("touching a pick-up takes it", _w(game).pickups.is_empty() and hero.score == 2000 + 100 and hero.long_needle and game.snapshot()["gems"] == 1 and game.snapshot()["players"][0]["powers"] == 1)
	_w(game).drop("button", 470.0, FLOOR_Y)
	_check("nothing drops under the pause chip in the bottom right corner", _w(game).pickups.size() == 1 and is_equal_approx(_w(game).pickups[0].x, World.DROP_MAX_X))
	_w(game).pickups.clear()
	_tap(game, 0, &"b")
	var reach := 0.0
	for step in 40:
		if not _w(game).shots.is_empty():
			reach = maxf(reach, float(_w(game).shots[0]["x"]) - hero.x)
		game.advance(GameModule.STEP)
	_check("the long needle throws yarn further", reach > 80.0)
	hero.lives = 1
	_w(game).drop(Item.HEART, 200.0, FLOOR_Y)
	game.advance(0.8)
	_check("a heart patch gives a life back", hero.lives == 2)
	game.free()

func _test_lives_continues_and_defeat() -> void:
	var game := _start(1, 61, {"difficulty": 0})
	_check("the easy setting gives five lives and five continues", game.snapshot()["players"][0]["lives"] == 5 and game.snapshot()["continues_left"] == 5 and game.snapshot()["difficulty"] == 0)
	game.free()

	game = _start(1, 61)
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	var hero := _arrange(game, 200.0)
	hero.thick = true
	_foe(game, Foe.MOTH, 203.0)
	game.advance(GameModule.STEP)
	_check("touching a roaming pest costs a life and the power-ups", hero.state == Hero.DYING and hero.lives == 3 and not hero.thick and game.snapshot()["deaths"] == 1 and int(game.audio.played.get("hurt", 0)) == 1)
	_w(game).foes.clear()
	_foe(game, Foe.MOTH, 440.0)
	game.advance(1.5)
	_check("the knitter comes back at the start point, protected for a moment", hero.state == Hero.ALIVE and hero.invuln > 0.0 and is_equal_approx(hero.x, 12.5 * 16.0))
	hero.lives = 1
	hero.invuln = 0.0
	_foe(game, Foe.MOTH, hero.x + 2.0)
	game.advance(GameModule.STEP)
	_w(game).foes.remove_at(1)
	game.advance(1.5)
	_check("the last life spent uses a continue", hero.state == Hero.ALIVE and hero.lives == 4 and game.snapshot()["continues_left"] == 2 and game.snapshot()["continues_used"] == 1 and results.is_empty())
	_w(game).continues = 0
	hero.lives = 1
	hero.invuln = 0.0
	_foe(game, Foe.MOTH, hero.x + 2.0)
	game.advance(5.0)
	_check("with no lives and no continues the run is lost", results.size() == 1 and results[0]["defeated"] == true and results[0]["cleared"] == false and results[0]["deaths"] == 3 and results[0]["stage"] == 1 and not game.audio.music_playing)
	game.free()

func _test_second_batch() -> void:
	var game := _start(1, 75, {"first_floor": 5})
	var world := _w(game)
	var first := world.foes.size()
	_check("an upper floor holds a second batch back", world.pending.size() == 3 and game.snapshot()["foes_left"] == first + 3)
	for foe: Foe in world.foes:
		foe.state = Foe.GONE
	game.advance(0.1)
	_check("which drops in when the first is gone, instead of the floor being cleared", world.phase == World.PLAY and world.foes.size() == 3 and world.pending.is_empty() and world.foes[0].state == Foe.SPAWN)
	var hero := _arrange(game, 200.0)
	var late := _foe(game, Foe.MOTH, 202.0)
	late.state = Foe.SPAWN
	late.timer = 0.5
	game.advance(0.3)
	_check("a pest that is still appearing cannot hurt", hero.state == Hero.ALIVE)
	game.advance(0.4)
	_check("but can as soon as it is there", hero.state == Hero.DYING)
	game.free()

func _test_hurry() -> void:
	var game := _start(1, 71)
	var hero := _arrange(game, 30.0)
	var moth := _foe(game, Foe.MOTH, 300.0)
	moth.state = Foe.SPAWN
	moth.timer = 500.0
	game.advance(World.HURRY_AT[1] + 0.1)
	_check("a floor that drags on calls for a hurry", _w(game).hurry and int(game.audio.played.get("hurry", 0)) == 1 and _w(game).spark == null)
	game.advance(14.0)
	var spark := _w(game).spark
	_check("then a static spark comes hunting", spark != null)
	var distance := absf(spark.x - hero.x) + absf(spark.y - hero.y)
	game.advance(2.0)
	_check("and closes in on the knitter", absf(spark.x - hero.x) + absf(spark.y - hero.y) < distance - 40.0)
	game.advance(12.0)
	_check("its touch costs a life", game.snapshot()["deaths"] >= 1)
	game.free()

	game = _start(1, 72, {"first_floor": 13})
	var crowd := _w(game).foes.size() + _w(game).pending.size()
	for foe: Foe in _w(game).foes:
		foe.timer = 500.0
	_check("a crowded floor is given longer before the hurry call", crowd == 17 and is_equal_approx(_w(game).hurry_limit, World.HURRY_AT[1] + World.HURRY_PER_FOE * (crowd - World.HURRY_FREE_FOES)))
	game.advance(World.HURRY_AT[1] + 20.0)
	_check("so the call does not come at the usual time", not _w(game).hurry)
	game.advance(_w(game).hurry_limit - World.HURRY_AT[1] - 20.0 + 0.1)
	_check("but does come when the longer time is up", _w(game).hurry)
	game.free()

func _test_guardian_and_victory() -> void:
	var game := _start(1, 81, {"first_floor": 7})
	game.advance(3.0)
	var boss := _w(game).boss
	var state := game.snapshot()
	_check("floor 7 is guarded: the bar shows and the guardian music plays", boss != null and state["boss_hp"] == 50 and state["boss_max_hp"] == 50 and _w(game).is_boss_stage())
	var hero := _arrange(game, 190.0)
	_w(game).hazards.clear()
	boss.state = "rest"
	boss.timer = 30.0
	boss.x = 240.0
	boss.y = FLOOR_Y
	_tap(game, 0, &"b")
	game.advance(0.3)
	_check("yarn chips at a guardian", boss.hp == 49 and int(game.audio.played.get("boss_hit", 0)) == 1)
	hero.x = 150.0
	var ball := _foe(game, Foe.MOTH, 176.0)
	_hold_until(game, 0, &"b", 2.0, func() -> bool: return ball.state == Foe.BALL)
	game.advance(0.3)
	_tap(game, 0, &"b")
	game.advance(0.5)
	_check("a rolling ball hits it hard and bursts", boss.hp == 39 and ball.state == Foe.GONE and boss.state == "hurt" and _w(game).kos == 1)
	boss.state = "rest"
	boss.timer = 30.0
	boss.y = FLOOR_Y
	boss.hp = 1
	hero.x = 190.0
	hero.invuln = 0.0
	_w(game).foes.clear()
	_foe(game, Foe.MOTH, 60.0).facing = -1
	_tap(game, 0, &"b")
	game.advance(0.3)
	_check("a beaten guardian takes its brood with it", boss.state == "dying" and _w(game).foes.is_empty() and not game.snapshot().has("boss_hp"))
	game.advance(3.0)
	_check("and is counted", game.snapshot()["bosses_defeated"] == 1 and _w(game).boss == null and _w(game).phase == World.CLEAR)
	var patch: Item = _w(game).pickups[0] if _w(game).pickups.size() == 1 else null
	_check("it leaves one heart patch for the lone knitter", patch != null and patch.kind == Item.HEART)
	hero.lives = 2
	hero.x = patch.x if patch != null else hero.x
	game.advance(1.0)
	_check("which can still be picked up before the climb", hero.lives == 3 and _w(game).pickups.is_empty())
	game.advance(4.5)
	_check("the tower goes on above it", game.snapshot()["stage"] == 8)
	game.free()

	game = _start(1, 82, {"first_floor": 14, "difficulty": 2})
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	game.advance(3.0)
	boss = _w(game).boss
	_check("the last guardian is tougher on Hard", boss != null and boss.kind == 1 and boss.max_hp == 84)
	hero = _arrange(game, 150.0)
	_w(game).hazards.clear()
	boss.state = "recover"
	boss.timer = 30.0
	boss.x = 200.0
	boss.hp = 1
	_tap(game, 0, &"b")
	game.advance(12.0)
	_check("beating it clears the run", results.size() == 1 and results[0]["cleared"] == true and results[0]["defeated"] == false and results[0]["stage"] == 14 and results[0]["bosses_defeated"] == 1)
	_check("the result carries what the achievements read", results[0]["difficulty"] == 2 and results[0]["continues_used"] == 0 and results[0]["player_count"] == 1 and results[0].has("best_roll") and results[0].has("kos") and results[0]["score"] >= 20000)
	game.free()

func _test_two_players() -> void:
	var game := _start(1, 91)
	_check("a lone run has an empty second seat in the snapshot", (game.snapshot()["players"] as Array).size() == 2 and game.snapshot()["players"][1]["lives"] == 0 and _w(game).heroes[1].state == Hero.ABSENT)
	_w(game).foes.clear()
	_foe(game, Foe.MOTH, 440.0).state = Foe.WRAP
	_check("player two can join a run in progress", game.join(1) and _w(game).heroes[1].state == Hero.ALIVE and game.snapshot()["players"][1]["lives"] == 4 and game.snapshot()["player_count"] == 2)
	var second: Hero = _w(game).heroes[1]
	var from_x := second.x
	game.feed(1, &"left", 1.0)
	game.advance(0.3)
	game.feed(1, &"left", 0.0)
	_check("and plays with their own controls", second.x < from_x - 15.0)
	second.x = 300.0
	second.facing = 1
	second.invuln = 0.0
	var moth := _foe(game, Foe.MOTH, 330.0)
	_tap(game, 1, &"b")
	game.advance(0.2)
	_check("player two's yarn scores for player two", moth.wrap == 1 and moth.owner == 1 and game.snapshot()["players"][1]["score"] == 10 and game.snapshot()["players"][0]["score"] == 0 and game.snapshot()["score"] == 10)
	_w(game).continues = 0
	var first: Hero = _w(game).heroes[0]
	first.lives = 1
	first.invuln = 0.0
	var killer := _foe(game, Foe.MOTH, first.x + 2.0)
	game.advance(GameModule.STEP)
	killer.state = Foe.GONE
	game.advance(2.0)
	_check("one knitter out of lives does not end a shared run", first.state == Hero.OUT and game.is_running() and _w(game).phase == World.PLAY)
	for foe: Foe in _w(game).foes:
		foe.state = Foe.GONE
	game.advance(3.5)
	_check("the partner carries them to the next floor, where they return with one life", _w(game).stage == 2 and first.state == Hero.ALIVE and first.lives == 1)
	_check("player two can leave again", game.leave(1) and second.state == Hero.ABSENT and game.snapshot()["player_count"] == 1 and (game.snapshot()["players"] as Array).size() == 2)
	second.lives = 2
	_check("coming back does not refill the lives the seat had", game.join(1) and second.state == Hero.ALIVE and second.lives == 2)
	game.leave(1)
	second.lives = 0
	_w(game).continues = 1
	_check("a seat with no lives left comes back on a continue", game.join(1) and second.state == Hero.ALIVE and second.lives == 4 and _w(game).continues == 0 and _w(game).continues_used == 1)
	game.leave(1)
	second.lives = 0
	_check("and with no continue either it waits for the next floor", game.join(1) and second.state == Hero.OUT and game.is_running())
	_foe(game, Foe.MOTH, 440.0).state = Foe.WRAP
	game.advance(0.2)
	for foe: Foe in _w(game).foes:
		foe.state = Foe.GONE
	game.advance(3.5)
	_check("where it returns with one life", _w(game).stage == 3 and second.state == Hero.ALIVE and second.lives == 1)
	game.free()

func _test_determinism() -> void:
	var digests: Array[String] = []
	for seed_value: int in [5, 5, 6]:
		var game := _start(2, seed_value)
		var script := [[1.0, "right+b", "left+b"], [0.4, "right+a", "left+a"], [1.5, "left+b", "right+b"], [0.5, "a", "a"], [2.0, "right+b", "b"], [0.3, "left+a", "right+a"], [3.0, "left+b", "right+b"], [4.0, "b", "left+b"]]
		for part: Array in script:
			for slot in 2:
				for control: StringName in GameInput.CONTROLS:
					game.feed(slot, control, 1.0 if str(part[1 + slot]).split("+").has(String(control)) else 0.0)
			game.advance(float(part[0]))
		var digest := str(game.snapshot())
		for foe: Foe in _w(game).foes:
			digest += "|%s %.3f %.3f %d %d" % [foe.kind, foe.x, foe.y, foe.state, foe.wrap]
		digests.append(digest)
		game.free()
	_check("the same seed and the same inputs give the same run", digests[0] == digests[1])
	_check("another seed gives another run", digests[0] != digests[2])

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
