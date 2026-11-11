extends SceneTree

## Headless tests of Brick Bastion. They load the entry script directly, start it with a fixed seed, press controls with feed(), step with advance() and read snapshot(); a few set a scene up by writing into the simulation (a brick here, a raider there) and then play it through the controls.
##
## Whole sectors are played by a small pilot written below: it looks at the field the way a player does and answers only through feed(), so a clear it reaches is a clear the controls allow.
## Run: GODOT=/path/to/godot scripts/run-godot-test.sh res://games/brick_bastion/brick_bastion_test.gd '^brick_bastion_test: [0-9]+ passed, 0 failed$'

const Main := preload("res://games/brick_bastion/main.gd")
const Sim := preload("res://games/brick_bastion/sim.gd")
const Stages := preload("res://games/brick_bastion/stages.gd")
const Sprites := preload("res://games/brick_bastion/sprites.gd")
const Texts := preload("res://games/brick_bastion/texts.gd")

const STAGE_SIZE := Vector2i(480, 270)
const STEP := GameModule.STEP
const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const CONTROLS: Array[StringName] = [&"up", &"right", &"down", &"left"]

## Flip to play whole runs with the pilot and print how they went, for tuning. Never committed as true: the run then reports no tests and fails.
const BENCH := false

var _passed := 0
var _failed := 0
## What each pilot is doing between two looks at the field: the heading it holds and whether it fires.
var _pilots := [{"dir": -1, "fire": false, "wait": 0}, {"dir": -1, "fire": false, "wait": 0}]

func _initialize() -> void:
	if BENCH:
		_bench()
		quit.call_deferred(1)
		return
	_test_data()
	_test_start()
	_test_driving()
	_test_shells_and_bricks()
	_test_raiders_and_score()
	_test_losses()
	_test_chips()
	_test_sector_flow()
	_test_boss()
	_test_two_players()
	_test_full_run()
	_test_determinism()
	print("brick_bastion_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- helpers ----

func _start(players: int, seed_value: int, options: Dictionary = {}) -> GameModule:
	var game: GameModule = Main.new()
	root.add_child(game)
	game.start({"players": players, "seed": seed_value, "options": options, "stage_size": STAGE_SIZE})
	return game

## Start and wait out the sector's opening banner, so the next input drives.
func _start_playing(players: int, seed_value: int, options: Dictionary = {}) -> GameModule:
	var game := _start(players, seed_value, options)
	game.advance(Sim.INTRO_STEPS * STEP)
	return game

func _tap(game: GameModule, slot: int, control: StringName) -> void:
	game.feed(slot, control, 1.0)
	game.advance(STEP)
	game.feed(slot, control, 0.0)
	game.advance(STEP)

func _results(game: GameModule) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	game.finished.connect(func(result: Dictionary) -> void: results.append(result))
	return results

func _tile(game: GameModule, col: int, row: int) -> int:
	return game.sim.tiles[row * Stages.COLS + col]

func _set_tile(game: GameModule, col: int, row: int, code: int) -> void:
	game.sim.tiles[row * Stages.COLS + col] = code

## Put a raider on the field at a cell, already arrived. `still` freezes every raider so the scene holds while it is tested.
func _raider(game: GameModule, kind: String, col: int, row: int, still: bool = true) -> Dictionary:
	var raider: Dictionary = game.sim._new_raider(kind, col * Sim.CELL + Sim.LANE, row * Sim.CELL + Sim.LANE)
	raider.spawn_t = 0
	game.sim.raiders.append(raider)
	if still:
		game.sim.freeze_t = 100000
	return raider

func _shell(game: GameModule, col: int, row: int, dir: int, team: int) -> void:
	game.sim.shots.append({"x": col * Sim.CELL + Sim.LANE, "y": row * Sim.CELL + Sim.LANE, "dir": dir, "speed": 40, "team": team, "owner": 99, "power": 1, "dmg": 1, "dead": false})

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)

# ---- the pilot ----

## Whether nothing a shell cannot pass lies strictly between two cells of one row or column, and no part of the beacon's wall either (the pilot does not shoot its own wall down).
func _clear_line(sim: RefCounted, from: Vector2i, to: Vector2i) -> bool:
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cell := from + step
	while cell != to:
		var code: int = sim.tiles[cell.y * Stages.COLS + cell.x]
		if code in [Stages.T_PLATE, Stages.T_FORT, Stages.T_CORE] or cell in Stages.CORE_RING:
			return false
		cell += step
	return true

## The cells a raider covers: one, or four for a boss.
func _cells_of(raider: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var size := 2 if raider.boss else 1
	var corner := Vector2i((int(raider.x) - int(raider.half)) / Sim.CELL, (int(raider.y) - int(raider.half)) / Sim.CELL)
	for part_x in size:
		for part_y in size:
			out.append(Vector2i(clampi(corner.x + part_x, 0, Stages.COLS - 1), clampi(corner.y + part_y, 0, Stages.ROWS - 1)))
	return out

## Whether shooting back along a shell's path would hit the beacon's own wall first (the shell came from behind it), in which case the pilot does not shoot.
func _wall_behind(sim: RefCounted, here: Vector2i, heading: Vector2i) -> bool:
	var cell := here - heading
	for reach in 3:
		if cell.x < 0 or cell.y < 0 or cell.x >= Stages.COLS or cell.y >= Stages.ROWS:
			return false
		if cell in Stages.CORE_RING or sim.tiles[cell.y * Stages.COLS + cell.x] == Stages.T_CORE:
			return true
		cell -= heading
	return false

## One look at the field for one rover: shoot down a shell coming head-on, else pick the raider that matters most, line up with it and fire, else drive towards a cell that lines up, shooting brick out of the way.
func _pilot_think(game: GameModule, slot: int) -> void:
	var sim: RefCounted = game.sim
	var rover: Dictionary = sim.rovers[slot]
	var pilot: Dictionary = _pilots[slot]
	pilot.dir = -1
	pilot.fire = false
	if not rover.alive:
		return
	pilot.wait = 0
	_pilot_plan(sim, slot, rover, pilot)
	if pilot.wait == 1:
		return
	# Never drive into a shell's path: if the plan is not safe, take the first thing that is.
	if rover.shield_t > 40 or _safe(sim, rover, pilot.dir):
		return
	for other: int in [-1, (int(rover.dir) + 1) % 4, (int(rover.dir) + 3) % 4, (int(rover.dir) + 2) % 4, int(rover.dir)]:
		if other != pilot.dir and _safe(sim, rover, other):
			pilot.dir = other
			return

## Whether the rover stays clear of every raider shell for the next moments if it holds this heading (-1 stands still).
func _safe(sim: RefCounted, rover: Dictionary, dir: int) -> bool:
	var x: int = rover.x
	var y: int = rover.y
	var step := Vector2i.ZERO if dir < 0 else NEIGHBOURS[dir]
	# Turning onto the other axis pulls the rover onto the nearest lane first.
	if dir >= 0 and dir % 2 != int(rover.dir) % 2:
		if dir % 2 == 0:
			x = int(round(float(x) / Sim.LANE)) * Sim.LANE
		else:
			y = int(round(float(y) / Sim.LANE)) * Sim.LANE
	for moment in range(1, 28):
		if dir >= 0 and sim._box_free(rover, x + step.x * Sim.ROVER_SPEED, y + step.y * Sim.ROVER_SPEED):
			x += step.x * Sim.ROVER_SPEED
			y += step.y * Sim.ROVER_SPEED
		for shot: Dictionary in sim.shots:
			if shot.team != 1:
				continue
			var heading: Vector2i = NEIGHBOURS[shot.dir]
			if absi(int(shot.x) + heading.x * int(shot.speed) * moment - x) < Sim.ROVER_HALF + 56 and absi(int(shot.y) + heading.y * int(shot.speed) * moment - y) < Sim.ROVER_HALF + 56:
				return false
	return true

func _pilot_plan(sim: RefCounted, slot: int, rover: Dictionary, pilot: Dictionary) -> void:
	var here := Vector2i(int(rover.x) / Sim.CELL, int(rover.y) / Sim.CELL)
	var core := Vector2i(Stages.CORE_COL, Stages.CORE_ROW)
	# A shell coming straight at the rover: shoot it down if the gun is free, step out of its lane otherwise.
	var loaded := true
	for shot: Dictionary in sim.shots:
		if shot.team == 0 and shot.owner == slot:
			loaded = false
	for shot: Dictionary in sim.shots:
		if shot.team != 1:
			continue
		var heading: Vector2i = NEIGHBOURS[shot.dir]
		var along: int = (int(rover.x) - int(shot.x)) * heading.x + (int(rover.y) - int(shot.y)) * heading.y
		# How far the rover's centre sits to the side of the shell's path (signed, along the heading turned a quarter clockwise).
		var offset: int = (int(rover.x) - int(shot.x)) * -heading.y + (int(rover.y) - int(shot.y)) * heading.x
		if along <= 0 or along > 5 * Sim.CELL or absi(offset) >= Sim.ROVER_HALF + 44:
			continue
		if loaded and absi(offset) < 64 and not _wall_behind(sim, here, heading):
			pilot.dir = (int(shot.dir) + 2) % 4
			pilot.fire = true
			pilot.wait = 1
			return
	# Any raider lined up with a clear view: turn to the nearest and fire.
	var nearest := 1 << 30
	for raider: Dictionary in sim.raiders:
		for cell in _cells_of(raider):
			var away: int = absi(cell.x - here.x) + absi(cell.y - here.y)
			if (cell.x == here.x or cell.y == here.y) and cell != here and away < nearest and _clear_line(sim, here, cell):
				nearest = away
				pilot.dir = NEIGHBOURS.find(Vector2i(signi(cell.x - here.x), signi(cell.y - here.y)))
				pilot.fire = true
	if pilot.fire:
		return
	# Otherwise mind the beacon: go for the raider closest to it once it is near, pick up a chip when nothing presses, and wait in front of the beacon the rest of the time.
	var threat := {}
	var closest := 1 << 30
	for raider: Dictionary in sim.raiders:
		var to_core: int = absi(int(raider.x) / Sim.CELL - core.x) + absi(int(raider.y) / Sim.CELL - core.y)
		if to_core < closest:
			closest = to_core
			threat = raider
	var goals := {}
	var chip_cell := Vector2i(-1, -1)
	for chip: Dictionary in sim.chips:
		var cell := Vector2i(int(chip.x) / Sim.CELL, int(chip.y) / Sim.CELL)
		if closest > 7 and absi(cell.x - here.x) + absi(cell.y - here.y) <= 10:
			chip_cell = cell
	if chip_cell.x >= 0:
		goals[chip_cell] = true
	elif not threat.is_empty() and (closest <= 10 or threat.boss or sim.next_raider >= sim.roster.size()):
		for cell in _cells_of(threat):
			for col in Stages.COLS:
				if _clear_line(sim, Vector2i(col, cell.y), cell):
					goals[Vector2i(col, cell.y)] = true
			for row in Stages.ROWS:
				if _clear_line(sim, Vector2i(cell.x, row), cell):
					goals[Vector2i(cell.x, row)] = true
	else:
		goals[Vector2i(Stages.PLAYER_CELLS[slot].x, Stages.CORE_ROW - 1)] = true
	var next := _first_step(sim, here, goals)
	if next == here:
		return
	var centre := Vector2i(here.x * Sim.CELL + Sim.LANE, here.y * Sim.CELL + Sim.LANE)
	# Get square in the cell before leaving it sideways, so the turn lands on the lane.
	if next.x != here.x and absi(int(rover.y) - centre.y) >= 60:
		pilot.dir = 2 if int(rover.y) < centre.y else 0
	elif next.y != here.y and absi(int(rover.x) - centre.x) >= 60:
		pilot.dir = 1 if int(rover.x) < centre.x else 3
	else:
		pilot.dir = NEIGHBOURS.find(next - here)
		var code: int = sim.tiles[next.y * Stages.COLS + next.x]
		pilot.fire = code in [Stages.T_BRICK, Stages.T_CRACKED] and not next in Stages.CORE_RING

## The neighbouring cell on a shortest way from `from` to any goal cell, over ground, thicket and brick.
func _first_step(sim: RefCounted, from: Vector2i, goals: Dictionary) -> Vector2i:
	if goals.has(from) or goals.is_empty():
		return from
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if goals.has(cell):
			while came[cell] != from:
				cell = came[cell]
			return cell
		for step in NEIGHBOURS:
			var next := cell + step
			if next.x < 0 or next.y < 0 or next.x >= Stages.COLS or next.y >= Stages.ROWS or came.has(next):
				continue
			if sim.tiles[next.y * Stages.COLS + next.x] in [Stages.T_PLATE, Stages.T_WATER, Stages.T_CORE, Stages.T_FORT] or next in Stages.CORE_RING:
				continue
			came[next] = cell
			queue.append(next)
	return from

## Let the pilots play for up to `seconds`, stopping early when `until` says so. They look at the field every few steps and hold what they decided in between.
func _pilot_play(game: GameModule, slots: Array, seconds: float, until: Callable) -> void:
	var steps := int(seconds / STEP)
	for step in steps:
		if not game.is_running() or until.call():
			break
		for slot: int in slots:
			if step % 2 == 0:
				_pilot_think(game, slot)
			var pilot: Dictionary = _pilots[slot]
			for dir in 4:
				game.feed(slot, CONTROLS[dir], 1.0 if pilot.dir == dir else 0.0)
			# In the tally the fire button moves on, so it is tapped rather than held.
			game.feed(slot, &"a", 1.0 if (pilot.fire or (game.sim.phase == "tally" and step % 8 < 4)) else 0.0)
		game.advance(STEP)
	for slot: int in slots:
		for control in [&"up", &"right", &"down", &"left", &"a"]:
			game.feed(slot, control, 0.0)

func _bench() -> void:
	for setup: Array in [[1, 0, 5], [1, 0, 6], [1, 0, 7], [1, 1, 5], [1, 1, 6], [1, 1, 7], [1, 2, 5], [1, 2, 6], [2, 1, 5], [2, 1, 6]]:
		var game := _start(int(setup[0]), int(setup[2]), {"difficulty": int(setup[1])})
		var marks := PackedStringArray()
		var stage := 1
		var slots: Array = [0, 1] if int(setup[0]) == 2 else [0]
		while game.is_running() and game.elapsed < 2400.0:
			_pilot_play(game, slots, 5.0, func() -> bool: return false)
			if int(game.sim.stage) + 1 != stage:
				marks.append("s%d@%d" % [stage, int(game.elapsed)])
				stage = int(game.sim.stage) + 1
		var state := game.snapshot()
		print("bench players=%d difficulty=%d seed=%d: %s at %ds, stage %d, cleared %d, deaths %d, core hits %d, core %d, score %d, chips %d, boss %d hp %d, left %d, crews used %d | %s" % [setup[0], setup[1], setup[2], state["phase"], int(game.elapsed), state["stage"], state["stages_cleared"], state["deaths"], state["core_hits"], state["core"], state["score"], state["chips"], game.sim.boss_state, game.sim.boss_hp, state["foes_left"], state["crews_used"], " ".join(marks)])
		game.free()

# ---- tests ----

func _test_data() -> void:
	_check("the six sectors are sound: " + ", ".join(Stages.problems()), Stages.problems().is_empty() and Stages.count() == 6)
	_check("the sprite rows are sound: " + ", ".join(Sprites.problems()), Sprites.problems().is_empty())
	_check("every text has both languages: " + ", ".join(Texts.problems()), Texts.problems().is_empty())
	var layouts := {}
	for index in Stages.count():
		layouts["".join(PackedStringArray(Stages.STAGES[index]["map"]))] = true
	_check("no two sectors share a layout, and the field is not square", layouts.size() == Stages.count() and Stages.COLS != Stages.ROWS)
	var pictures := Sprites.images("moss")
	_check("every vehicle has two rolling frames and a flash frame for each heading", pictures.has("rover0_3_1") and pictures.has("rover1_0_w") and pictures.has("dreadnought_2_0") and (pictures["crusher_1_0"] as Image).get_width() == 32 and (pictures["scout_0_0"] as Image).get_width() == 16)
	_check("the two tread frames differ and the two rovers wear different colours", (pictures["grunt_0_0"] as Image).get_data() != (pictures["grunt_0_1"] as Image).get_data() and (pictures["rover0_0_0"] as Image).get_data() != (pictures["rover1_0_0"] as Image).get_data())

func _test_start() -> void:
	var game := _start(2, 3)
	var first := game.snapshot()
	_check("a run opens on sector 1 of 6 with its banner up", first["stage"] == 1 and first["stages"] == 6 and first["phase"] == "intro")
	_check("normal difficulty gives three rovers each, a beacon of four and two reserve crews", first["players"][0]["lives"] == 3 and first["players"][1]["lives"] == 3 and first["players"][0]["max_lives"] == 3 and first["core"] == 4 and first["core_max"] == 4 and first["difficulty"] == 1 and first["crews"] == 2)
	_check("two players face a longer column than one", first["foes_left"] == 20)
	_check("both rovers start beside the beacon with three bricks and no upgrades", first["players"][0]["alive"] and first["players"][1]["alive"] and first["players"][0]["x"] < first["players"][1]["x"] and first["players"][0]["bricks"] == 3 and first["players"][0]["power"] == 0)
	_check("the stage tune is playing", game.audio.music_playing)
	game.free()
	game = _start(1, 3, {"difficulty": 0})
	var easy := game.snapshot()
	_check("easy gives five rovers, a beacon of six and three reserve crews, and one player a column of sixteen", easy["players"][0]["lives"] == 5 and easy["core_max"] == 6 and easy["crews"] == 3 and easy["foes_left"] == 16 and easy["player_count"] == 1)
	_check("the second seat is reported even when nobody sits in it", (easy["players"] as Array).size() == 2 and easy["players"][1]["alive"] == false)
	game.free()
	game = _start(1, 3, {"difficulty": 2})
	_check("hard gives two rovers, a beacon of three and one reserve crew", game.snapshot()["players"][0]["lives"] == 2 and game.snapshot()["core_max"] == 3 and game.snapshot()["crews"] == 1)
	game.free()

func _test_driving() -> void:
	var game := _start(2, 5)
	var before := game.snapshot()
	game.feed(0, &"right", 1.0)
	game.advance(0.5)
	_check("nothing moves while the sector banner is up", game.snapshot()["players"][0]["x"] == before["players"][0]["x"])
	game.advance(Sim.INTRO_STEPS * STEP)
	game.feed(1, &"left", 1.0)
	game.advance(0.5)
	var moved := game.snapshot()
	_check("each rover drives by its own controls", moved["players"][0]["x"] > before["players"][0]["x"] and moved["players"][1]["x"] < before["players"][1]["x"] and moved["players"][0]["dir"] == 1 and moved["players"][1]["dir"] == 3)
	game.feed(0, &"right", 0.0)
	game.feed(1, &"left", 0.0)
	game.advance(0.2)
	var still := game.snapshot()
	game.advance(0.3)
	_check("a rover stands still when nothing is held", game.snapshot()["players"][0]["x"] == still["players"][0]["x"])
	game.free()

	# Sector 1: the column above player one's start is open ground up to a plate in row 7.
	game = _start_playing(1, 5)
	game.sim.freeze_t = 100000
	game.feed(0, &"up", 1.0)
	game.advance(6.0)
	_check("plate stops a rover flush against it", is_equal_approx(float(game.snapshot()["players"][0]["y"]), 8.0 * 16.0 + 7.0) and _tile(game, 5, 7) == Stages.T_PLATE)
	game.feed(0, &"a", 1.0)
	game.advance(2.0)
	game.feed(0, &"a", 0.0)
	_check("plate shrugs off a basic shell", _tile(game, 5, 7) == Stages.T_PLATE and int(game.audio.played.get("plate_hit", 0)) >= 2)
	game.feed(0, &"up", 0.0)
	game.feed(0, &"left", 1.0)
	game.advance(8.0)
	game.feed(0, &"left", 0.0)
	_check("the edge of the field stops a rover", is_equal_approx(float(game.snapshot()["players"][0]["x"]), 7.0))
	game.free()

	game = _start_playing(1, 5, {"start_stage": 2})
	game.sim.freeze_t = 100000
	# Sector 2: the water band crosses rows 4 and 5; column 5 is a ford, column 6 is water.
	game.feed(0, &"right", 1.0)
	game.advance(0.4)
	game.feed(0, &"right", 0.0)
	game.feed(0, &"up", 1.0)
	game.advance(8.0)
	var blocked := game.snapshot()
	_check("water stops a rover", float(blocked["players"][0]["y"]) > 6.0 * 16.0 and _tile(game, 6, 5) == Stages.T_WATER)
	game.feed(0, &"a", 1.0)
	game.advance(1.5)
	_check("a shell flies over water", int(game.audio.played.get("brick_hit", 0)) + int(game.audio.played.get("brick_break", 0)) >= 1)
	game.free()

	game = _start_playing(2, 5)
	game.sim.freeze_t = 100000
	game.feed(0, &"up", 1.0)
	game.advance(0.35)
	game.feed(0, &"up", 0.0)
	_set_tile(game, 7, 12, Stages.T_EMPTY)
	game.feed(0, &"right", 1.0)
	game.advance(4.0)
	_check("the beacon is solid: a rover cannot drive into it", is_equal_approx(float(game.snapshot()["players"][0]["x"]), 8.0 * 16.0 - 7.0) and int(float(game.snapshot()["players"][0]["y"])) / 16 == 12)
	game.free()

func _test_shells_and_bricks() -> void:
	var game := _start_playing(1, 9)
	game.sim.freeze_t = 100000
	_set_tile(game, 5, 11, Stages.T_BRICK)
	_tap(game, 0, &"a")
	game.advance(0.6)
	_check("a first shell cracks a brick", _tile(game, 5, 11) == Stages.T_CRACKED and int(game.audio.played.get("brick_hit", 0)) == 1 and int(game.audio.played.get("fire", 0)) == 1)
	_tap(game, 0, &"a")
	game.advance(0.6)
	_check("a second shell breaks it", _tile(game, 5, 11) == Stages.T_EMPTY and int(game.audio.played.get("brick_break", 0)) == 1)
	game.feed(0, &"a", 1.0)
	game.advance(STEP * 3)
	_check("a basic rover has one shell in the air at a time", game.sim.shots.size() == 1)
	game.feed(0, &"a", 0.0)
	game.advance(2.0)

	_tap(game, 0, &"b")
	var laid := game.snapshot()
	_check("the brick button lays a brick in the cell ahead and spends one", _tile(game, 5, 12) == Stages.T_BRICK and laid["players"][0]["bricks"] == 2 and laid["bricks_laid"] == 1 and int(game.audio.played.get("lay", 0)) == 1)
	_tap(game, 0, &"b")
	_check("no brick goes where something already stands", game.snapshot()["players"][0]["bricks"] == 2 and int(game.audio.played.get("deny", 0)) == 1)
	game.sim.rovers[0].power = 2
	_tap(game, 0, &"a")
	game.advance(0.4)
	_check("level-two fire breaks a brick in one shell", _tile(game, 5, 12) == Stages.T_EMPTY)
	game.feed(0, &"a", 1.0)
	game.advance(STEP * 20)
	_check("and keeps two shells in the air", game.sim.shots.size() == 2)
	game.feed(0, &"a", 0.0)
	game.sim.rovers[0].power = 3
	game.feed(0, &"up", 1.0)
	game.advance(6.0)
	game.feed(0, &"up", 0.0)
	_tap(game, 0, &"a")
	game.advance(0.5)
	_check("level-three fire breaks plate", _tile(game, 5, 7) == Stages.T_EMPTY and int(game.audio.played.get("plate_break", 0)) == 1)
	game.free()

	game = _start_playing(1, 9)
	game.sim.freeze_t = 100000
	_shell(game, 5, 8, 2, 1)
	game.feed(0, &"a", 1.0)
	game.advance(1.2)
	game.feed(0, &"a", 0.0)
	_check("shells of the two sides knock each other down", int(game.audio.played.get("deflect", 0)) >= 1 and game.snapshot()["players"][0]["lives"] == 3 and game.snapshot()["deaths"] == 0)
	game.free()

func _test_raiders_and_score() -> void:
	var game := _start_playing(1, 11)
	_raider(game, "grunt", 5, 9)
	var foes: int = game.snapshot()["foes_left"]
	_tap(game, 0, &"a")
	game.advance(1.0)
	var after := game.snapshot()
	_check("destroying a raider scores for the rover that did it", after["kills"] == 1 and after["score"] == 100 and after["players"][0]["score"] == 100 and after["players"][0]["kills"] == 1 and after["foes_left"] == foes - 1 and int(game.audio.played.get("boom", 0)) == 1)
	var bulwark := _raider(game, "bulwark", 5, 9)
	for shell in 3:
		_tap(game, 0, &"a")
		game.advance(0.8)
	_check("an armoured raider takes three shells and still stands", game.sim.raiders.has(bulwark) and bulwark.hp == 1 and int(game.audio.played.get("clank", 0)) == 3)
	_tap(game, 0, &"a")
	game.advance(0.8)
	_check("and falls to the fourth, for more points", not game.sim.raiders.has(bulwark) and game.snapshot()["score"] == 500)
	_tap(game, 0, &"a")
	game.advance(0.8)
	game.free()

	game = _start_playing(1, 11)
	var carrier := _raider(game, "scout", 5, 9)
	carrier.carrier = true
	_tap(game, 0, &"a")
	game.advance(1.0)
	_check("a raider that carries supplies leaves a chip on open ground", game.sim.chips.size() == 1 and _tile(game, int(game.sim.chips[0].x) / Sim.CELL, int(game.sim.chips[0].y) / Sim.CELL) == Stages.T_EMPTY)
	game.sim.rovers[0].kills = 2
	_raider(game, "grunt", 5, 9)
	var bricks: int = game.snapshot()["players"][0]["bricks"]
	_tap(game, 0, &"a")
	game.advance(1.0)
	_check("every third kill earns a brick", game.snapshot()["players"][0]["bricks"] == bricks + 1)
	game.free()

	# Left alone, raiders arrive through the gates, move, shoot, and never leave the field or enter anything solid.
	game = _start_playing(1, 13)
	game.sim.rovers[0].shield_t = 100000
	game.sim.core_grace_t = 100000
	var seen_kinds := {}
	var legal := true
	var moved := false
	for second in 30:
		game.advance(1.0)
		game.sim.core_grace_t = 100000
		for raider: Dictionary in game.sim.raiders:
			seen_kinds[raider.kind] = true
			if int(raider.y) > Sim.LANE:
				moved = true
			if game.sim._tiles_block(raider, raider.x, raider.y) != 0:
				legal = false
	_check("raiders come in by themselves, drive and fire", moved and not seen_kinds.is_empty() and int(game.audio.played.get("raider_fire", 0)) > 3 and int(game.audio.played.get("spawn", 0)) >= 3)
	_check("no raider ever stands in a wall, in water or off the field", legal)
	_check("no more raiders are on the field than the sector allows", game.sim.raiders.size() <= int(Stages.STAGES[0]["limit"]))
	game.free()

func _test_losses() -> void:
	var game := _start_playing(1, 17)
	var results := _results(game)
	game.sim.freeze_t = 100000
	_shell(game, 5, 9, 2, 1)
	game.advance(1.2)
	_check("a rover that has just arrived is shielded", game.snapshot()["players"][0]["lives"] == 3 and game.snapshot()["players"][0]["shielded"] and int(game.audio.played.get("deflect", 0)) == 1)
	game.sim.rovers[0].shield_t = 0
	game.sim.rovers[0].power = 2
	_shell(game, 5, 9, 2, 1)
	game.advance(1.2)
	var hit := game.snapshot()
	_check("a raider's shell destroys an unshielded rover and costs one of its upgrades", hit["players"][0]["lives"] == 2 and hit["players"][0]["alive"] == false and hit["deaths"] == 1 and hit["players"][0]["power"] == 1 and int(game.audio.played.get("rover_down", 0)) == 1)
	game.advance(Sim.RESPAWN_STEPS * STEP + 0.5)
	var back := game.snapshot()
	_check("it comes back at its start, shielded", back["players"][0]["alive"] and back["players"][0]["shielded"] and is_equal_approx(float(back["players"][0]["x"]), 5.0 * 16.0 + 8.0))
	var squatter := _raider(game, "grunt", 5, 13)
	game.sim.rovers[0].shield_t = 0
	game.sim.rovers[0].x = 3 * Sim.CELL + Sim.LANE
	_shell(game, 3, 9, 2, 1)
	game.advance(1.2 + Sim.RESPAWN_STEPS * STEP + 0.5)
	_check("with a raider parked on its start, a rover comes back one cell above instead", game.snapshot()["players"][0]["alive"] and is_equal_approx(float(game.snapshot()["players"][0]["y"]), 12.0 * 16.0 + 8.0) and is_equal_approx(float(game.snapshot()["players"][0]["x"]), 5.0 * 16.0 + 8.0))
	game.sim.raiders.erase(squatter)
	game.sim.rovers[0].lives = 1
	game.sim.rovers[0].shield_t = 0
	game.sim.rovers[0].score = 700
	game.sim.score_total = 700
	game.sim.core = 2
	_shell(game, 5, 8, 2, 1)
	game.advance(1.2)
	_check("the last rover going down stops play, and nothing is decided until the wreck has been seen", game.snapshot()["phase"] == "lost" and results.is_empty())
	game.advance(Sim.LOST_STEPS * STEP + 0.1)
	var relieved := game.snapshot()
	_check("a reserve crew takes the sector over from its opening: full garage, mended beacon, the score kept", results.is_empty() and relieved["phase"] == "intro" and relieved["stage"] == 1 and relieved["crews"] == 1 and relieved["crews_used"] == 1 and relieved["players"][0]["lives"] == 3 and relieved["players"][0]["alive"] and relieved["core"] == 4 and relieved["score"] == 700 and relieved["foes_left"] == 16)
	game.advance(Sim.INTRO_STEPS * STEP)
	game.sim.freeze_t = 100000
	game.sim.crews = 0
	game.sim.rovers[0].lives = 1
	game.sim.rovers[0].shield_t = 0
	_shell(game, 5, 9, 2, 1)
	game.advance(1.2 + Sim.LOST_STEPS * STEP)
	_check("with no crew left, losing every rover is a defeat", results.size() == 1 and results[0]["defeated"] == true and results[0]["cleared"] == false and results[0]["deaths"] == 4 and results[0]["core"] == 4 and results[0]["crews_used"] == 1)
	game.free()

	game = _start_playing(1, 17)
	results = _results(game)
	game.sim.freeze_t = 100000
	game.sim.crews = 0
	game.sim.core = 3
	_set_tile(game, 8, 11, Stages.T_EMPTY)
	_shell(game, 8, 10, 2, 0)
	game.advance(1.0)
	_check("a rover's own shell does not hurt the beacon", game.snapshot()["core"] == 3 and game.snapshot()["core_hits"] == 0)
	var raider := _raider(game, "grunt", 10, 10)
	var at_wall := _raider(game, "grunt", 6, 12)
	var kills_before: int = game.sim.kills
	var left_before: int = game.sim.foes_left()
	_shell(game, 8, 10, 2, 1)
	_shell(game, 9, 5, 2, 1)
	game.advance(1.0)
	var struck := game.snapshot()
	_check("a raider's shell costs the beacon one point of integrity", struck["core"] == 2 and struck["core_hits"] == 1 and int(game.audio.played.get("core_hit", 0)) == 1)
	_check("the beacon's pulse clears raider shells and stalls raiders near it", game.sim.shots.is_empty() and raider.stun_t > 0)
	_check("a raider right at the wall is destroyed by the pulse, which is nobody's kill", not game.sim.raiders.has(at_wall) and game.sim.kills == kills_before and game.sim.foes_left() == left_before - 1 and struck["score"] == 0)
	_shell(game, 8, 10, 2, 1)
	game.advance(0.5)
	_check("for a moment afterwards the beacon cannot be hit again", game.snapshot()["core"] == 2)
	game.advance(Sim.CORE_GRACE_STEPS * STEP)
	_shell(game, 8, 10, 2, 1)
	game.advance(Sim.CORE_GRACE_STEPS * STEP + 1.0)
	_shell(game, 8, 10, 2, 1)
	game.advance(1.0)
	_check("the beacon going dark ends play", game.snapshot()["core"] == 0 and game.snapshot()["phase"] == "lost" and int(game.audio.played.get("core_lost", 0)) == 1)
	game.advance(Sim.LOST_STEPS * STEP + 0.1)
	_check("losing the beacon is a defeat even with rovers left", results.size() == 1 and results[0]["defeated"] == true and results[0]["core_hits"] == 3 and results[0]["players"][0]["lives"] == 3 and not game.audio.music_playing)
	game.free()

func _test_chips() -> void:
	var game := _start_playing(1, 19)
	var rover: Dictionary = game.sim.rovers[0]
	game.sim.chips.append({"kind": "coil", "x": rover.x, "y": int(rover.y) - Sim.CELL, "t": 600})
	game.feed(0, &"up", 1.0)
	game.advance(0.4)
	game.feed(0, &"up", 0.0)
	var took := game.snapshot()
	_check("driving over a chip takes it: firepower up, points, a sound", took["players"][0]["power"] == 1 and took["chips"] == 1 and took["score"] == 300 and game.sim.chips.is_empty() and int(game.audio.played.get("power", 0)) == 1)
	rover.shield_t = 0
	game.sim.take_chip(rover, "aegis")
	_check("aegis shields the rover", game.snapshot()["players"][0]["shielded"])
	var grunt := _raider(game, "grunt", 3, 5, false)
	var stood := Vector2i(grunt.x, grunt.y)
	game.sim.take_chip(rover, "stasis")
	game.advance(2.0)
	_check("stasis stalls every raider", Vector2i(grunt.x, grunt.y) == stood and game.sim.freeze_t > 0)
	game.advance(Sim.FREEZE_STEPS * STEP)
	_check("and wears off", game.sim.freeze_t == 0)
	game.sim.freeze_t = 100000
	var bricks: int = rover.bricks
	rover.bricks = 2
	game.sim.take_chip(rover, "mason")
	_check("mason turns the beacon's wall to plate and hands over two bricks", _tile(game, 7, 12) == Stages.T_FORT and _tile(game, 9, 11) == Stages.T_FORT and rover.bricks == 4 and bricks >= 0)
	_shell(game, 8, 8, 2, 1)
	game.advance(1.0)
	_check("the fortified wall stops a raider's shell", _tile(game, 8, 11) == Stages.T_FORT and game.snapshot()["core"] == 4 and game.snapshot()["core_hits"] == 0)
	game.advance(Sim.FORT_STEPS * STEP)
	_check("and turns back into fresh brick", _tile(game, 8, 11) == Stages.T_BRICK and _tile(game, 10, 13) == Stages.T_BRICK)
	_raider(game, "bulwark", 12, 3)
	var before: int = game.snapshot()["kills"]
	game.sim.take_chip(rover, "surge")
	_check("surge destroys every raider on the field", game.sim.raiders.is_empty() and game.snapshot()["kills"] >= before + 2)
	rover.lives = 2
	game.sim.take_chip(rover, "spare")
	game.sim.take_chip(rover, "spare")
	_check("a spare rover adds one, up to the full garage", game.snapshot()["players"][0]["lives"] == 3)
	rover.power = 3
	game.advance(STEP)
	var score: int = game.snapshot()["score"]
	game.sim.take_chip(rover, "coil")
	game.advance(STEP)
	_check("a coil at full firepower pays points instead", rover.power == 3 and game.snapshot()["score"] == score + 800)
	game.sim.chips.append({"kind": "coil", "x": Sim.LANE, "y": 5 * Sim.CELL + Sim.LANE, "t": 30})
	game.advance(1.0)
	_check("a chip nobody takes disappears", game.sim.chips.is_empty())
	game.free()

func _test_sector_flow() -> void:
	var game := _start(1, 23, {"quota": 2, "difficulty": 0})
	var results := _results(game)
	_check("the test knob shortens the column", game.snapshot()["foes_left"] == 2)
	game.sim.core = 3
	game.sim.rovers[0].lives = 3
	_pilot_play(game, [0], 120.0, func() -> bool: return game.sim.phase == "tally")
	var tally := game.snapshot()
	_check("destroying the whole column holds the sector", tally["phase"] == "tally" and tally["stages_cleared"] == 1 and tally["kills"] == 2 and tally["foes_left"] == 0 and int(game.audio.played.get("stage_clear", 0)) == 1)
	_check("the tally lists what was destroyed and pays a bonus for the beacon", game.sim.tally_lines.size() >= 1 and int(game.sim.tally_bonus) == 1000 + 300 * 3 and tally["score"] >= 200 + 1900)
	_check("holding a sector mends the beacon by one and returns a rover", tally["core"] == 4 and tally["players"][0]["lives"] == 4)
	_check("the tune stops for the tally", not game.audio.music_playing)
	game.advance(STEP * 4)
	_pilot_play(game, [0], 20.0, func() -> bool: return game.sim.phase != "tally")
	var next := game.snapshot()
	_check("after the tally the next sector opens with a fresh field and its own tune", next["stage"] == 2 and next["phase"] == "intro" and next["foes_left"] == 2 and game.audio.music_playing and _tile(game, 0, 4) == Stages.T_WATER and results.is_empty())
	game.free()

func _test_boss() -> void:
	var game := _start(1, 29, {"quota": 1, "difficulty": 0, "start_stage": 3})
	var results := _results(game)
	_check("a boss sector counts its boss among what is left", game.snapshot()["foes_left"] == 2 and game.snapshot()["stage"] == 3 and not game.snapshot().has("boss_hp"))
	_pilot_play(game, [0], 120.0, func() -> bool: return game.sim.boss_state == Sim.BOSS_PRESENT)
	var arrived := game.snapshot()
	_check("when the column is gone the alarm sounds and the boss arrives with its own tune", arrived.has("boss_hp") and arrived["boss_hp"] == arrived["boss_max_hp"] and arrived["boss_max_hp"] == 22 and int(game.audio.played.get("alarm", 0)) >= 1 and int(game.audio.played.get("boss_in", 0)) == 1 and game.audio.music_playing)
	var boss: Dictionary = game.sim.raiders[0]
	_check("a boss is two cells wide", boss.boss and int(boss.half) == Sim.BOSS_HALF)
	_pilot_play(game, [0], 400.0, func() -> bool: return game.sim.boss_state == Sim.BOSS_DOWN or game.sim.phase == "lost")
	var down := game.snapshot()
	_check("the boss can be destroyed with shells alone", down["bosses_down"] == 1 and not down.has("boss_hp") and down["score"] >= 3000 and int(game.audio.played.get("boss_down", 0)) == 1)
	_check("it charged its cross volley and grew angry on the way", int(game.audio.played.get("charge", 0)) >= 1 and int(game.audio.played.get("volley", 0)) >= 1 and int(game.audio.played.get("enrage", 0)) == 1)
	_pilot_play(game, [0], 30.0, func() -> bool: return game.sim.phase == "tally")
	_check("and its fall holds the sector", game.snapshot()["phase"] == "tally" and game.snapshot()["stages_cleared"] == 1 and results.is_empty())
	game.free()

	game = _start_playing(1, 29, {"start_stage": 3})
	game.sim.destroyed = game.sim.roster.size()
	game.sim.next_raider = game.sim.roster.size()
	game.sim.rovers[0].shield_t = 100000
	game.advance(Sim.BOSS_WARN_STEPS * STEP + 3.0)
	_set_tile(game, 8, 2, Stages.T_BRICK)
	_set_tile(game, 9, 2, Stages.T_BRICK)
	var crusher: Dictionary = game.sim.raiders[0]
	crusher.dir = 2
	crusher.volley_t = 100000
	game.sim.rng.reseed(4)
	game.advance(2.0)
	_check("a boss flattens brick it drives over", _tile(game, 8, 2) == Stages.T_EMPTY or int(crusher.y) == Sim.CELL)
	game.free()

func _test_two_players() -> void:
	var game := _start_playing(1, 31)
	game.sim.freeze_t = 100000
	_check("one player: the second rover is not on the field", game.snapshot()["players"][1]["alive"] == false and game.snapshot()["active_players"] == [0])
	_check("a second player can join a live run", game.join(1))
	game.advance(0.2)
	var joined := game.snapshot()
	_check("the newcomer arrives at their own start with a full garage", joined["players"][1]["alive"] and joined["players"][1]["lives"] == 3 and joined["player_count"] == 2 and float(joined["players"][1]["x"]) > float(joined["players"][0]["x"]))
	game.feed(1, &"up", 1.0)
	game.advance(0.5)
	game.feed(1, &"up", 0.0)
	_check("and drives by player two's controls only", float(game.snapshot()["players"][1]["y"]) < float(joined["players"][1]["y"]) and game.snapshot()["players"][0]["y"] == joined["players"][0]["y"])
	_raider(game, "grunt", 12, 9)
	_tap(game, 1, &"a")
	game.advance(1.5)
	var scored := game.snapshot()
	_check("each player keeps their own score and the run's score is the sum", scored["players"][1]["score"] == 100 and scored["players"][0]["score"] == 0 and scored["score"] == 100)
	_check("the second player can leave again", game.leave(1))
	game.advance(0.2)
	var left := game.snapshot()
	_check("their rover is off the field, their seat is still reported", left["players"][1]["alive"] == false and left["active_players"] == [0] and (left["players"] as Array).size() == 2 and left["players"][1]["score"] == 100)
	game.free()

	# One partner out of rovers does not end the run, and comes back when the sector is held.
	game = _start(2, 31, {"quota": 2, "difficulty": 0})
	var results := _results(game)
	game.advance(Sim.INTRO_STEPS * STEP)
	game.sim.rovers[1].lives = 1
	game.sim.rovers[1].shield_t = 0
	_shell(game, 12, 10, 2, 1)
	game.advance(1.0)
	_check("a partner without rovers is out while the other plays on", game.snapshot()["players"][1]["lives"] == 0 and game.snapshot()["phase"] == "play" and results.is_empty())
	_pilot_play(game, [0], 120.0, func() -> bool: return game.sim.phase == "tally")
	_check("holding the sector brings the partner back with one rover", game.snapshot()["phase"] == "tally" and game.snapshot()["players"][1]["lives"] == 1)
	game.advance(STEP * 4)
	_pilot_play(game, [0], 20.0, func() -> bool: return game.sim.phase == "play")
	_check("and they are on the field in the next sector", game.snapshot()["players"][1]["alive"] and game.snapshot()["stage"] == 2)
	game.free()

func _test_full_run() -> void:
	# Six sectors and both bosses with a short column, played through the controls alone: first by one player, then by two.
	var game := _start(1, 37, {"quota": 2, "difficulty": 0})
	var results := _results(game)
	_pilot_play(game, [0], 1500.0, func() -> bool: return false)
	_check("one player alone can hold all six sectors", results.size() == 1 and results[0]["cleared"] == true and results[0]["defeated"] == false and results[0]["stages_cleared"] == 6 and results[0]["bosses_down"] == 2 and results[0]["stage"] == 6)
	if results.size() == 1:
		_check("the result carries what the achievements read", results[0].has("core_hits") and results[0].has("bricks_laid") and results[0]["difficulty"] == 0 and results[0]["player_count"] == 1 and results[0]["score"] > 9000 + 6 * 1000 and results[0]["kills"] >= 14)
		_check("the fanfare played and the music stopped", int(game.audio.played.get("victory", 0)) == 1 and not game.audio.music_playing)
	game.free()

	game = _start(2, 41, {"quota": 2, "difficulty": 0})
	results = _results(game)
	_pilot_play(game, [0, 1], 1500.0, func() -> bool: return false)
	_check("two players can hold all six sectors together", results.size() == 1 and results[0]["cleared"] == true and results[0]["player_count"] == 2 and results[0]["stages_cleared"] == 6)
	if results.size() == 1:
		_check("the run's score is the two players' scores together", results[0]["score"] == int(results[0]["players"][0]["score"]) + int(results[0]["players"][1]["score"]) and int(results[0]["players"][1]["score"]) > 0)
	game.free()

func _test_determinism() -> void:
	var digests: Array = []
	var states: Array = []
	for attempt in 2:
		var game := _start(2, 77)
		_pilot_play(game, [0, 1], 45.0, func() -> bool: return false)
		digests.append(game.snapshot()["digest"])
		states.append(game.snapshot())
		game.free()
	_check("the same seed and the same inputs give the same run", digests[0] == digests[1] and states[0] == states[1] and float(states[0]["elapsed"]) > 40.0)
	var other := _start(2, 78)
	_pilot_play(other, [0, 1], 45.0, func() -> bool: return false)
	_check("another seed gives another run", other.snapshot()["digest"] != digests[0])
	other.free()

	var again := _start(1, 77)
	again.advance(20.0)
	var first: Dictionary = again.snapshot()
	again.start({"players": 1, "seed": 77, "options": {}, "stage_size": STAGE_SIZE})
	again.advance(20.0)
	_check("starting the same instance again plays the same run from the top", again.snapshot() == first)
	again.free()
