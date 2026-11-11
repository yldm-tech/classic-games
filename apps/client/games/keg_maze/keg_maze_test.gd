extends SceneTree

## Headless tests of Keg Burrow's rules. Players act through feed() like a real device would; where a test needs a known field it rearranges the blocks and creatures directly before the action starts. keg_maze_play_test.gd plays whole levels through inputs alone.
## Run: GODOT=/path/to/godot scripts/run-godot-test.sh res://games/keg_maze/keg_maze_test.gd '^keg_maze_test: [0-9]+ passed, 0 failed$'

const Main := preload("res://games/keg_maze/main.gd")
const Levels := preload("res://games/keg_maze/levels.gd")
const Actors := preload("res://games/keg_maze/actors.gd")
const Foes := preload("res://games/keg_maze/foes.gd")
const Sprites := preload("res://games/keg_maze/sprites.gd")
const Sounds := preload("res://games/keg_maze/sounds.gd")

const STEP := GameModule.STEP
const CELL_TIME := 0.25

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_data()
	_test_start()
	_test_movement()
	_test_keg_and_blocks()
	_test_blast_hurts()
	_test_chain_and_detonator()
	_test_foes_and_exit()
	_test_foe_kinds()
	_test_losing()
	_test_air()
	_test_two_players()
	_test_boss()
	_test_final_clear()
	_test_determinism()
	print("keg_maze_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- helpers ----

func _start(players: int, seed_value: int, options: Dictionary = {}) -> Main:
	var game: Main = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": Vector2i(480, 270)})
	return game

## Let the level's name card pass.
func _play(game: Main) -> void:
	while game.phase == Levels.Phase.INTRO:
		game.advance(STEP)

## A started game on an empty field: no blocks, nothing buried, no creatures. The lift stays hidden until a test puts it somewhere.
func _arena(players: int = 1, options: Dictionary = {}) -> Main:
	var game := _start(players, 11, options)
	for at in game.grid.size():
		if game.grid[at] == Levels.CRATE:
			game.grid[at] = Levels.FLOOR
	game.buried.clear()
	game.foes.clear()
	game.exit_cell = Vector2i(-1, -1)
	_play(game)
	return game

func _tap(game: Main, slot: int, control: StringName) -> void:
	game.feed(slot, control, 1.0)
	game.advance(STEP)
	game.feed(slot, control, 0.0)
	game.advance(STEP)

## Walk a whole number of cells: hold the direction until the last step is under way, then let it finish.
func _walk(game: Main, slot: int, control: StringName, cells: int) -> void:
	game.feed(slot, control, 1.0)
	game.advance((float(cells) - 0.5) * CELL_TIME)
	game.feed(slot, control, 0.0)
	game.advance(CELL_TIME)

func _wait_until(game: Main, moment: float) -> void:
	while game.elapsed < moment and game.is_running():
		game.advance(STEP)

func _spot(game: Main, slot: int) -> Vector2i:
	var player: Dictionary = game.snapshot()["players"][slot]
	return Vector2i(roundi(float(player["x"])), roundi(float(player["y"])))

func _foe(game: Main, kind: String, cell: Vector2i, still: bool = true) -> Actors.Foe:
	var foe := Foes.make(kind, cell, 0, 1)
	if still:
		foe.rest = 999.0
	game.foes.append(foe)
	return foe

func _results(game: Main) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	return results

# ---- tests ----

func _test_data() -> void:
	for line in Levels.problems():
		push_error(line)
	for line in Sprites.problems():
		push_error(line)
	_check("every level layout is well formed and fully connected", Levels.problems().is_empty())
	_check("every sprite row has the right width and known colours", Sprites.problems().is_empty())
	var rng := GameRng.new(1)
	var sound := true
	for seed_value in range(1, 13):
		for stage in Levels.STAGE_COUNT:
			rng.reseed(seed_value * 100 + stage)
			var built := Levels.build(stage, rng, 1)
			var spec: Dictionary = Levels.STAGES[stage]
			var wanted := 0
			for kind: String in spec["foes"]:
				wanted += int(spec["foes"][kind])
			if spec.has("boss"):
				wanted += 1
			var grid: PackedInt32Array = built["grid"]
			var buried: Dictionary = built["buried"]
			sound = sound and (built["foes"] as Array).size() == wanted
			sound = sound and buried.size() == (spec["loot"] as Array).size() + (0 if built["exit_visible"] else 1)
			for at: int in buried:
				sound = sound and grid[at] == Levels.CRATE
			for start: Vector2i in built["starts"]:
				for dir in Levels.DIRS:
					var near := start + dir
					sound = sound and (not Levels.inside(near) or grid[Levels.index(near)] != Levels.CRATE)
			for entry: Array in built["foes"]:
				sound = sound and grid[Levels.index(entry[1])] == Levels.FLOOR
			sound = sound and Levels.inside(built["exit"])
	_check("every level builds with its creatures, its loot under blocks, a lift and clear start corners, whatever the seed", sound)
	var tunes := true
	for stage in Levels.STAGE_COUNT:
		tunes = tunes and (Sounds.music(stage)["voices"] as Array).size() >= 3
	_check("every level has a tune of at least three voices, and the boss levels have their own", tunes and Sounds.music(5) == Sounds.music(8) and Sounds.music(5) != Sounds.music(4) and Sounds.music(0) != Sounds.music(3) and Sounds.music(3) != Sounds.music(6))

func _test_start() -> void:
	var game := _start(1, 3)
	var first := game.snapshot()
	_check("a run starts on level 1 of 9 with three lives, the level's clock and its creatures", first["stage"] == 1 and first["stages"] == 9 and first["players"][0]["lives"] == 3 and first["players"][0]["max_lives"] == 3 and is_equal_approx(float(first["time_left"]), 180.0) and first["foes"] == 3 and not first.has("boss_hp"))
	_check("both seats are reported even when one player plays", (first["players"] as Array).size() == 2 and first["player_count"] == 1)
	_check("the digger starts in the top-left corner with one keg and a reach of two", _spot(game, 0) == Vector2i(1, 1) and first["players"][0]["kegs"] == 1 and first["players"][0]["blast"] == 2)
	game.feed(0, &"right", 1.0)
	game.advance(1.0)
	_check("nothing moves while the level's name is up", _spot(game, 0) == Vector2i(1, 1) and is_equal_approx(float(game.snapshot()["time_left"]), 180.0))
	_check("the level's tune is playing", game.audio.music_playing)
	game.free()
	var easy := _start(1, 3, {"difficulty": 0})
	var hard := _start(1, 3, {"difficulty": 2})
	_check("difficulty changes lives, continues and the clock", easy.snapshot()["players"][0]["lives"] == 5 and hard.snapshot()["players"][0]["lives"] == 2 and easy.snapshot()["continues_left"] == 3 and hard.snapshot()["continues_left"] == 1 and float(easy.snapshot()["time_left"]) > float(hard.snapshot()["time_left"]))
	easy.free()
	hard.free()

func _test_movement() -> void:
	var game := _arena()
	_walk(game, 0, &"right", 4)
	_check("a digger walks four cells a second", _spot(game, 0) == Vector2i(5, 1))
	game.feed(0, &"up", 1.0)
	game.advance(0.5)
	game.feed(0, &"up", 0.0)
	_check("the outer rock cannot be entered", _spot(game, 0) == Vector2i(5, 1))
	game.feed(0, &"down", 1.0)
	game.advance(3.5)
	game.feed(0, &"down", 0.0)
	_check("an open column leads down to the far wall", _spot(game, 0) == Vector2i(5, 13))
	_walk(game, 0, &"left", 1)
	game.feed(0, &"up", 1.0)
	game.advance(1.0)
	game.feed(0, &"up", 0.0)
	_check("a pillar inside the field blocks the way", _spot(game, 0) == Vector2i(4, 13))
	game.grid[Levels.index(Vector2i(2, 13))] = Levels.CRATE
	game.feed(0, &"left", 1.0)
	game.advance(1.5)
	game.feed(0, &"left", 0.0)
	_check("a block cannot be walked through", _spot(game, 0) == Vector2i(3, 13))
	# Holding two directions under a pillar: up is blocked, so right carries the digger to the next opening, where up takes over.
	_walk(game, 0, &"right", 1)
	game.feed(0, &"right", 1.0)
	game.advance(STEP)
	game.feed(0, &"up", 1.0)
	game.advance(1.0)
	game.release_inputs()
	game.advance(CELL_TIME)
	var slid := _spot(game, 0)
	_check("holding two directions slides round a corner", slid.x == 5 and slid.y < 12)
	game.free()

func _test_keg_and_blocks() -> void:
	var game := _arena()
	var block := Vector2i(6, 1)
	game.grid[Levels.index(block)] = Levels.CRATE
	game.buried[Levels.index(block)] = "blast"
	_walk(game, 0, &"right", 4)
	var set_at: float = game.elapsed
	_tap(game, 0, &"a")
	_check("pressing A sets a keg under the digger", game.snapshot()["kegs_live"] == 1 and game.keg_at(Vector2i(5, 1)) != null and int(game.audio.played.get("place", 0)) == 1)
	_tap(game, 0, &"a")
	_check("only as many kegs as the digger carries can burn at once", game.snapshot()["kegs_live"] == 1 and int(game.audio.played.get("deny", 0)) == 1)
	_walk(game, 0, &"left", 3)
	game.feed(0, &"right", 1.0)
	game.advance(1.0)
	game.feed(0, &"right", 0.0)
	_check("a keg blocks the way once the digger has stepped off it", _spot(game, 0) == Vector2i(4, 1))
	_walk(game, 0, &"left", 2)
	_wait_until(game, set_at + Main.FUSE + 0.1)
	var cells := {}
	for at: int in game.flames:
		cells[Levels.cell_of(at)] = true
	_check("the keg goes off in a cross that rock stops", game.snapshot()["kegs_live"] == 0 and cells.size() == 5 and cells.has(Vector2i(5, 1)) and cells.has(Vector2i(3, 1)) and cells.has(Vector2i(4, 1)) and cells.has(Vector2i(5, 2)) and cells.has(Vector2i(5, 3)))
	_check("a block stops the fire and starts to burn", game.grid[Levels.index(block)] == Levels.BURNING and not cells.has(Vector2i(7, 1)) and game.snapshot()["crates"] == 1)
	_check("the digger was out of reach and is unharmed", game.snapshot()["players"][0]["lives"] == 3 and int(game.audio.played.get("blast", 0)) == 1)
	game.advance(0.6)
	_check("the burnt block leaves what it hid, and the fire dies down", game.grid[Levels.index(block)] == Levels.FLOOR and game.items.get(Levels.index(block)) == "blast" and game.snapshot()["flames"] == 0 and game.score == 10)
	game.feed(0, &"right", 1.0)
	game.advance(1.2)
	game.feed(0, &"right", 0.0)
	game.advance(CELL_TIME)
	var after := game.snapshot()
	_check("walking over an item picks it up", after["players"][0]["blast"] == 3 and after["pickups"] == 1 and game.items.is_empty() and game.score == 60 and after["players"][0]["score"] == 60)
	game.free()

func _test_blast_hurts() -> void:
	var game := _arena()
	var hero: Actors.Hero = game.heroes[0]
	hero.cap = 3
	hero.blast = 4
	hero.boots = 2
	hero.remote = true
	_tap(game, 0, &"b")
	game.advance(0.3)
	hero.remote = false
	_tap(game, 0, &"a")
	game.advance(Main.FUSE + 0.1)
	var hit := game.snapshot()
	_check("a digger caught in a blast loses a life", hit["players"][0]["lives"] == 2 and hit["deaths"] == 1 and hit["blast_deaths"] == 1 and int(game.audio.played.get("hurt", 0)) == 1)
	_check("and drops some gear", hit["players"][0]["kegs"] == 2 and hit["players"][0]["blast"] == 3 and hit["players"][0]["boots"] == 1)
	game.advance(Main.DEAD_TIME + 0.1)
	_check("then comes back at the start corner, blinking", _spot(game, 0) == Vector2i(1, 1) and hero.in_field() and hero.invuln > 1.0)
	game.advance(Main.RESPAWN_INVULN)
	_tap(game, 0, &"a")
	_walk(game, 0, &"right", 1)
	game.advance(Main.FUSE)
	_check("standing in the arm of a blast hurts as much as standing on the keg", game.snapshot()["players"][0]["lives"] == 1)
	game.free()

	game = _arena()
	hero = game.heroes[0]
	hero.shield = true
	_tap(game, 0, &"a")
	game.advance(Main.FUSE + 0.1)
	_check("a hard hat takes one hit instead of a life", game.snapshot()["players"][0]["lives"] == 3 and not hero.shield and game.snapshot()["deaths"] == 0 and int(game.audio.played.get("shield", 0)) == 1)
	game.free()

func _test_chain_and_detonator() -> void:
	var game := _arena()
	var hero: Actors.Hero = game.heroes[0]
	hero.cap = 3
	var first: float = game.elapsed
	_tap(game, 0, &"a")
	_walk(game, 0, &"right", 1)
	_tap(game, 0, &"a")
	_walk(game, 0, &"right", 1)
	_tap(game, 0, &"a")
	_walk(game, 0, &"down", 3)
	_check("three kegs are burning in a row", game.snapshot()["kegs_live"] == 3 and _spot(game, 0) == Vector2i(3, 4))
	_wait_until(game, first + Main.FUSE + 0.02)
	_check("the first keg goes off on its own fuse", game.snapshot()["kegs_live"] == 2 and game.snapshot()["best_chain"] == 1)
	_wait_until(game, first + Main.FUSE + 3.0 * Main.CHAIN_DELAY)
	var chained := game.snapshot()
	_check("its fire sets off the next keg, and that one the third, long before their own fuses", chained["kegs_live"] == 0 and chained["best_chain"] == 3 and int(game.audio.played.get("chain", 0)) == 2)
	_check("the digger stood clear of the whole chain", chained["players"][0]["lives"] == 3)
	game.free()

	game = _arena()
	hero = game.heroes[0]
	hero.remote = true
	_tap(game, 0, &"a")
	_walk(game, 0, &"right", 3)
	game.advance(Main.FUSE + 1.0)
	_check("a wired keg waits for the detonator", game.snapshot()["kegs_live"] == 1)
	_tap(game, 0, &"b")
	_check("B sets it off", game.snapshot()["kegs_live"] == 0 and game.snapshot()["flames"] > 0 and int(game.audio.played.get("detonate", 0)) == 1)
	game.free()

func _test_foes_and_exit() -> void:
	var game := _arena()
	_foe(game, "grub", Vector2i(3, 1))
	_foe(game, "grub", Vector2i(4, 1))
	_foe(game, "mite", Vector2i(9, 9))
	_walk(game, 0, &"right", 1)
	_tap(game, 0, &"a")
	_walk(game, 0, &"left", 1)
	_walk(game, 0, &"down", 2)
	game.advance(Main.FUSE)
	var after := game.snapshot()
	_check("one blast kills both grubs, and the second kill of a chain counts double", after["kills"] == 2 and after["best_streak"] == 2 and game.score == 300 and after["foes"] == 1)
	_check("the lift stays shut while a creature is left", not after["exit_open"])
	game.exit_cell = Vector2i(1, 5)
	game.exit_visible = true
	_walk(game, 0, &"down", 2)
	_check("standing on a shut lift does nothing", game.phase == Levels.Phase.PLAY and _spot(game, 0) == Vector2i(1, 5))
	_walk(game, 0, &"up", 1)
	(game.foes[0] as Actors.Foe).dying = 0.1
	game.advance(0.3)
	_check("the lift opens when the last creature is gone", game.snapshot()["exit_open"] and game.snapshot()["foes"] == 0 and int(game.audio.played.get("exit_open", 0)) == 1)
	var left := float(game.snapshot()["time_left"])
	_walk(game, 0, &"down", 1)
	var cleared := game.snapshot()
	_check("stepping into the open lift clears the level and pays for the time left", game.phase == Levels.Phase.CLEAR and cleared["stages_cleared"] == 1 and game.score >= 300 + int(left - 1.0) * 10 and game.score <= 300 + ceili(left) * 10)
	game.advance(Main.CLEAR_TIME + 0.1)
	var next := game.snapshot()
	_check("the next level begins with its own creatures and a full clock", next["stage"] == 2 and game.phase == Levels.Phase.INTRO and next["foes"] == 5 and is_equal_approx(float(next["time_left"]), 180.0) and _spot(game, 0) == Vector2i(1, 1))
	_check("score and gear carry over", game.score == cleared["score"] and next["players"][0]["lives"] == 3)
	game.free()

	game = _arena()
	var walker := _foe(game, "grub", Vector2i(3, 1))
	walker.speed = 0.0
	walker.rest = 0.0
	game.advance(Main.START_INVULN)
	_walk(game, 0, &"right", 1)
	_check("a creature one cell away does no harm", game.snapshot()["players"][0]["lives"] == 3)
	game.feed(0, &"right", 1.0)
	game.advance(0.3)
	game.feed(0, &"right", 0.0)
	var touched := game.snapshot()
	_check("touching a creature costs a life, and is not counted as a blast", touched["players"][0]["lives"] == 2 and touched["deaths"] == 1 and touched["blast_deaths"] == 0)
	game.free()

	# The lift is buried under a block until a blast uncovers it.
	game = _arena()
	var block := Vector2i(3, 1)
	game.grid[Levels.index(block)] = Levels.CRATE
	game.buried[Levels.index(block)] = "exit"
	game.exit_cell = block
	_walk(game, 0, &"right", 1)
	_tap(game, 0, &"a")
	_walk(game, 0, &"left", 1)
	_walk(game, 0, &"down", 2)
	_check("the buried lift is not shown", not game.snapshot()["exit_visible"])
	game.advance(Main.FUSE + 0.6)
	_check("blowing up its block uncovers the lift", game.snapshot()["exit_visible"] and int(game.audio.played.get("exit_found", 0)) == 1)
	game.free()

func _test_foe_kinds() -> void:
	# A cell boxed in by blocks: a grub stays put, a wisp drifts out through them.
	var game := _arena()
	for y in range(1, Levels.ROWS - 1):
		for x in range(3, Levels.COLS - 1):
			if game.grid[Levels.index(Vector2i(x, y))] == Levels.FLOOR:
				game.grid[Levels.index(Vector2i(x, y))] = Levels.CRATE
	for cell: Vector2i in [Vector2i(9, 7), Vector2i(9, 11)]:
		game.grid[Levels.index(cell)] = Levels.FLOOR
	var wisp := _foe(game, "wisp", Vector2i(9, 7), false)
	var grub := _foe(game, "grub", Vector2i(9, 11), false)
	game.advance(3.0)
	_check("a wisp passes through blocks and a grub does not", wisp.cell != Vector2i(9, 7) and grub.cell == Vector2i(9, 11))
	_check("a wisp never enters rock", game.grid[Levels.index(wisp.spot())] != Levels.WALL)
	game.free()

	game = _arena()
	var beetle := _foe(game, "beetle", Vector2i(13, 5), false)
	game.advance(2.5)
	_check("a beetle makes for the digger", absi(beetle.cell.x - 1) + absi(beetle.cell.y - 1) <= 12)
	game.free()

	game = _arena()
	var shell := _foe(game, "shell", Vector2i(7, 1), false)
	game.advance(0.2)
	_check("a stoneback charges down a clear line at a digger it can see", shell.charge and shell.dir == Vector2i(-1, 0) and int(game.audio.played.get("charge", 0)) == 1)
	game.free()

	game = _arena()
	shell = _foe(game, "shell", Vector2i(4, 1))
	for round_index in 2:
		_walk(game, 0, &"right", 1)
		_tap(game, 0, &"a")
		_walk(game, 0, &"left", 1)
		_walk(game, 0, &"down", 2)
		game.advance(Main.FUSE)
		if round_index == 0:
			_check("a stoneback survives the first blast with a cracked shell", shell.hp == 1 and shell.alive() and game.snapshot()["kills"] == 0)
			game.advance(1.0)
			_walk(game, 0, &"up", 2)
	_check("and falls to the second", game.snapshot()["kills"] == 1 and game.score == 500)
	game.free()

func _test_losing() -> void:
	var game := _arena()
	var results := _results(game)
	var hero: Actors.Hero = game.heroes[0]
	hero.lives = 1
	game.continues_left = 1
	_tap(game, 0, &"a")
	game.advance(Main.FUSE + Main.DEAD_TIME + 0.2)
	_check("losing the last life with a continue in hand spends it", game.phase == Levels.Phase.CONTINUE and results.is_empty() and game.snapshot()["players"][0]["out"])
	game.advance(Main.CONTINUE_TIME + 0.1)
	var again := game.snapshot()
	_check("the continue restarts the same level with full lives", again["stage"] == 1 and game.phase == Levels.Phase.INTRO and again["players"][0]["lives"] == 3 and again["continues_used"] == 1 and again["continues_left"] == 0 and not again["players"][0]["out"])
	_play(game)
	hero.lives = 1
	_tap(game, 0, &"a")
	game.advance(Main.FUSE + Main.DEAD_TIME + 0.2)
	_check("with no continue left the dig is lost, after a moment to see it", game.phase == Levels.Phase.DEFEAT and results.is_empty())
	game.advance(Main.DEFEAT_TIME + 0.1)
	_check("the run ends as a defeat with what happened in the result", results.size() == 1 and results[0]["defeated"] == true and results[0]["cleared"] == false and results[0]["deaths"] == 2 and results[0]["blast_deaths"] == 2 and results[0]["continues_used"] == 1 and not game.audio.music_playing)
	game.free()

func _test_air() -> void:
	var game := _arena()
	_foe(game, "grub", Vector2i(9, 9))
	game.time_left = 0.05
	game.advance(0.2)
	var after := game.snapshot()
	_check("running out of air costs a life and buys a little more time", after["players"][0]["lives"] == 2 and after["deaths"] == 1 and after["blast_deaths"] == 0 and float(after["time_left"]) > 40.0 and float(after["time_left"]) <= Main.OVERTIME and int(game.audio.played.get("timeup", 0)) == 1)
	game.free()

	game = _arena()
	_foe(game, "grub", Vector2i(9, 9))
	game.time_left = 20.5
	game.items[Levels.index(Vector2i(1, 2))] = "clock"
	game.advance(1.0)
	_walk(game, 0, &"down", 1)
	_check("the clock ticks when air is short, and a stopwatch adds half a minute", float(game.snapshot()["time_left"]) > 48.5 and int(game.audio.played.get("tick", 0)) >= 1)
	game.free()

func _test_two_players() -> void:
	var game := _arena(2)
	var first := game.snapshot()
	_check("two players start in opposite corners", _spot(game, 0) == Vector2i(1, 1) and _spot(game, 1) == Vector2i(17, 13) and first["player_count"] == 2)
	_walk(game, 1, &"left", 2)
	_check("each player moves by their own input", _spot(game, 0) == Vector2i(1, 1) and _spot(game, 1) == Vector2i(15, 13))
	_foe(game, "grub", Vector2i(13, 13))
	_tap(game, 1, &"a")
	_walk(game, 1, &"right", 2)
	_walk(game, 1, &"up", 2)
	game.advance(Main.FUSE)
	var scored := game.snapshot()
	_check("a kill is paid to the player whose keg it was, and the total is the sum", scored["players"][1]["score"] == 100 and scored["players"][0]["score"] == 0 and game.score == 100)
	# Player two walks over to player one and blows both of them up.
	var two: Actors.Hero = game.heroes[1]
	two.cell = Vector2i(2, 1)
	_tap(game, 1, &"a")
	game.advance(Main.FUSE + 0.1)
	var both := game.snapshot()
	_check("a blast hurts the partner too", both["players"][0]["lives"] == 2 and both["players"][1]["lives"] == 2 and both["blast_deaths"] == 2)
	game.advance(Main.DEAD_TIME + 0.2)
	two.lives = 1
	two.invuln = 0.0
	two.cell = Vector2i(17, 13)
	_tap(game, 1, &"a")
	game.advance(Main.FUSE + Main.DEAD_TIME + 0.3)
	_check("one player out of lives does not end the run while the other stands", game.phase == Levels.Phase.PLAY and game.snapshot()["players"][1]["out"] and not game.snapshot()["players"][0]["out"])
	game.exit_cell = Vector2i(1, 3)
	game.exit_visible = true
	_walk(game, 0, &"down", 2)
	_check("the player left standing can clear the level alone", game.phase == Levels.Phase.CLEAR)
	game.advance(Main.CLEAR_TIME + 0.1)
	var next := game.snapshot()
	_check("the partner is back for the next level with one life", next["stage"] == 2 and not next["players"][1]["out"] and next["players"][1]["lives"] == 1 and _spot(game, 1) == Vector2i(17, 13))
	_check("leaving takes player two off the field but keeps the seat in the snapshot", game.leave(1) and game.snapshot()["player_count"] == 1 and (game.snapshot()["players"] as Array).size() == 2)
	game.free()

	game = _arena(1)
	_check("a second player can join a run in progress", game.join(1) and game.snapshot()["player_count"] == 2 and _spot(game, 1) == Vector2i(17, 13) and game.snapshot()["players"][1]["lives"] == 3)
	_walk(game, 1, &"up", 2)
	_check("and plays at once", _spot(game, 1) == Vector2i(17, 11))
	game.leave(1)
	var results := _results(game)
	var hero: Actors.Hero = game.heroes[0]
	hero.lives = 1
	game.continues_left = 0
	_tap(game, 0, &"a")
	game.advance(Main.FUSE + Main.DEAD_TIME + Main.DEFEAT_TIME + 0.5)
	_check("after the partner left, the remaining player's last life decides the run", results.size() == 1 and results[0]["defeated"] == true and results[0]["player_count"] == 1)
	game.free()

func _test_boss() -> void:
	var game := _start(1, 5, {"start_stage": 6})
	var first := game.snapshot()
	_check("level 6 holds the Geode Claw, with its own bar and tune", first["stage"] == 6 and first["boss_hp"] == 6 and first["boss_max_hp"] == 6 and first["foes"] == 1 and first["exit_visible"] and not first["exit_open"])
	_play(game)
	game.advance(7.0)
	_check("left alone, the boss walks and brings rocks down", int(game.audio.played.get("rock_warn", 0)) >= 1 and (game.boss() as Actors.Foe).cell != Vector2i(8, 6))
	game.free()

	game = _start(1, 5, {"start_stage": 6})
	_play(game)
	var claw: Actors.Foe = game.boss()
	claw.cell = Vector2i(3, 1)
	claw.rest = 999.0
	for round_index in 2:
		_walk(game, 0, &"right", 1)
		_tap(game, 0, &"a")
		_walk(game, 0, &"left", 1)
		_walk(game, 0, &"down", 2)
		game.advance(Main.FUSE)
		if round_index == 0:
			_check("a blast that reaches any part of the boss takes one point off it", game.snapshot()["boss_hp"] == 5 and game.score == 300 and game.snapshot()["players"][0]["lives"] == 3)
			claw.hp = 1
			game.advance(1.2)
			_walk(game, 0, &"up", 2)
	var beaten := game.snapshot()
	_check("the last point brings it down", beaten["bosses_beaten"] == 1 and not beaten.has("boss_hp") and game.score == 300 + 5000 and int(game.audio.played.get("boss_die", 0)) == 1)
	game.advance(2.0)
	_check("and the lift opens", game.snapshot()["exit_open"] and game.snapshot()["foes"] == 0)
	_walk(game, 0, &"up", 2)
	_walk(game, 0, &"right", 8)
	_check("which leads on to level 7", game.phase == Levels.Phase.CLEAR)
	game.advance(Main.CLEAR_TIME + 0.1)
	_check("level 7 has no boss bar", game.snapshot()["stage"] == 7 and not game.snapshot().has("boss_hp"))
	game.free()

	# The Molten Claw spits fire along its rows and columns; it is nobody's fire, so it harms diggers only.
	game = _start(1, 5, {"start_stage": 9})
	_play(game)
	claw = game.boss()
	var bystander := _foe(game, "grub", Vector2i(11, 6))
	claw.cycle = 1
	claw.attack = 0.0
	claw.rest = 0.0
	(game.heroes[0] as Actors.Hero).cell = Vector2i(5, 6)
	(game.heroes[0] as Actors.Hero).invuln = 0.0
	game.advance(0.1)
	_check("the Molten Claw warns before it spits", claw.tell > 0.0 and game.snapshot()["flames"] == 0)
	game.advance(Foes.SPIT_TELL + 0.05)
	var burnt := game.snapshot()
	_check("its fire hurts a digger in line and spares its own kind", burnt["players"][0]["lives"] == 2 and burnt["flames"] > 0 and bystander.alive() and burnt["boss_hp"] == 10)
	game.free()

func _test_final_clear() -> void:
	var game := _start(1, 9, {"start_stage": 9})
	var results := _results(game)
	_play(game)
	var claw: Actors.Foe = game.boss()
	claw.cell = Vector2i(4, 1)
	claw.rest = 999.0
	claw.hp = 1
	_walk(game, 0, &"right", 1)
	_tap(game, 0, &"a")
	_walk(game, 0, &"left", 1)
	_walk(game, 0, &"down", 2)
	game.advance(Main.FUSE + 2.0)
	_walk(game, 0, &"up", 2)
	_walk(game, 0, &"right", 8)
	_check("the last lift is reached", game.phase == Levels.Phase.CLEAR and results.is_empty())
	game.advance(Main.FINAL_CLEAR_TIME + 0.1)
	var fields := true
	if results.size() == 1:
		for field: String in ["best_chain", "gems", "blast_deaths", "continues_used", "bosses_beaten", "stages_cleared", "deaths", "kills"]:
			fields = fields and results[0].has(field) and (results[0][field] is int or results[0][field] is float)
	_check("clearing level 9 clears the run", results.size() == 1 and results[0]["cleared"] == true and results[0]["defeated"] == false and results[0]["stage"] == 9 and results[0]["bosses_beaten"] == 1 and results[0]["score"] >= 10000)
	_check("the result carries every number the achievements read, at the top level", results.size() == 1 and fields and results[0]["blast_deaths"] == 0 and results[0]["continues_used"] == 0)
	game.free()

## Two runs fed the same pseudo-random button mashing must agree on everything.
func _test_determinism() -> void:
	var states: Array = []
	var grids: Array = []
	for attempt in 3:
		var game := _start(2, 77 if attempt < 2 else 78)
		grids.append(game.grid.duplicate())
		var tape := GameRng.new(4242)
		for tick in 900:
			if tick % 10 == 0:
				for slot in 2:
					for control: StringName in [&"up", &"down", &"left", &"right", &"a", &"b"]:
						game.feed(slot, control, 1.0 if tape.chance(0.3) else 0.0)
			game.advance(STEP)
		var state := game.snapshot()
		state["grid"] = game.grid.duplicate()
		state["foe_cells"] = game.foes.map(func(foe: Actors.Foe) -> Vector2i: return foe.cell)
		states.append(state)
		game.free()
	_check("the same seed and the same inputs give the same run", states[0] == states[1] and int(states[0]["crates"]) >= 1)
	_check("another seed lays the blocks out differently", grids[0] == grids[1] and grids[0] != grids[2])

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
