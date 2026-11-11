extends RefCounted

## The whole simulation of Brick Bastion: the tile grid, rovers, raiders, shells, supply chips, the beacon and the flow from sector to sector. It advances one fixed step at a time from main.gd's _game_step and never draws: main.gd, render.gd and fx.gd read its state.
##
## Positions are whole numbers in sixteenths of a pixel (UNIT per pixel), so a run is exact arithmetic: the same seed and the same inputs give the same run. A vehicle is a square box around its centre. Rovers drive on lanes half a cell apart, raiders on the cell centres, a boss (two cells wide) on the cell corners.

const Stages := preload("res://games/brick_bastion/stages.gd")

const UNIT := 16
const CELL := 256
const LANE := 128
const FIELD_W := Stages.COLS * CELL
const FIELD_H := Stages.ROWS * CELL
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_CONTROLS: Array[StringName] = [&"up", &"right", &"down", &"left"]

const ROVER_HALF := 112
const ROVER_SPEED := 13
const BOSS_HALF := 224
## A boss never drives below the top of this row.
const BOSS_FLOOR_ROW := 10
const SHOT_LONG := 48
const SHOT_WIDE := 32
## Half the width in which a shell damages tiles, so a shell flying along the seam of two cells bites both.
const SHOT_BLAST := 64
const CHIP_HALF := 96

const INTRO_STEPS := 130
const CLEARED_STEPS := 100
const TALLY_LINE_STEPS := 26
const TALLY_HOLD_STEPS := 170
const WON_STEPS := 210
const LOST_STEPS := 170
const BOSS_WARN_STEPS := 150
const RESPAWN_STEPS := 80
const SHIELD_SPAWN_STEPS := 180
const SHIELD_CHIP_STEPS := 600
const FREEZE_STEPS := 360
const FORT_STEPS := 900
const CHIP_STEPS := 840
const CORE_GRACE_STEPS := 180
## How far from the beacon's centre (in sixteenths of a pixel, counted along rows plus columns) its pulse destroys a raider, and how far it stalls one.
const PULSE_KILL_REACH := 896
const PULSE_STUN_REACH := 1792
const MAX_POWER := 3
const MAX_BRICKS := 5
const START_BRICKS := 3
const KILLS_PER_BRICK := 3
const EVENT_CAP := 256

const BOSS_NONE := 0
const BOSS_WARNING := 1
const BOSS_PRESENT := 2
const BOSS_DOWN := 3

## Rovers and beacon integrity by difficulty (easy, normal, hard), and how the gap between raider shots scales.
const LIVES := [5, 3, 2]
const CORE := [6, 4, 3]
## Reserve crews: how many times a lost sector may be taken up again before the run is lost.
const CREWS := [3, 2, 1]
const FIRE_SCALE := [1.35, 1.0, 0.8]

const CHIP_KINDS: Array[String] = ["coil", "coil", "coil", "aegis", "aegis", "stasis", "stasis", "mason", "mason", "surge", "spare"]

var rng: GameRng
var audio: GameAudio
var difficulty := 1
var active: Array[bool] = [false, false]
var stage := 0
var first_stage := 0
var phase := "intro"
var phase_t := 0
var tiles := PackedInt32Array()
var rovers: Array[Dictionary] = []
var raiders: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var chips: Array[Dictionary] = []
## What happened since the presentation last looked: explosions, sparks, pick-ups. fx.gd drains it once per frame; the simulation itself never reads it.
var events: Array[Dictionary] = []
var core := 3
var core_max := 3
var core_grace_t := 0
var core_hits := 0
var crews := 0
var crews_used := 0
var roster: Array[String] = []
var next_raider := 0
var destroyed := 0
var spawn_t := 0
var boss_state := BOSS_NONE
var boss_t := 0
var boss_hp := 0
var boss_max_hp := 0
var freeze_t := 0
var fort_t := 0
var kills := 0
var deaths := 0
var bricks_laid := 0
var chips_taken := 0
var bosses_down := 0
var stages_cleared := 0
var score_total := 0
var stage_kills := {}
var tally_lines: Array[Dictionary] = []
var tally_bonus := 0
## "" while the run goes on, then "cleared" or "defeated"; main.gd ends the run on it.
var outcome := ""
## Which tune should be playing: "", "stage", "dusk", "boss". main.gd follows it.
var music := ""
## Test knob: a positive value cuts every roster to this many raiders. Not a manifest option, so players never see it.
var quota := 0
var steps := 0
var _next_id := 1
var _block := 0

func setup(game_rng: GameRng, game_audio: GameAudio, config: Dictionary) -> void:
	rng = game_rng
	audio = game_audio
	var options: Dictionary = config.get("options", {})
	difficulty = clampi(int(options.get("difficulty", 1)), 0, 2)
	quota = maxi(0, int(options.get("quota", 0)))
	first_stage = clampi(int(options.get("start_stage", 1)) - 1, 0, Stages.count() - 1)
	core_max = CORE[difficulty]
	core = core_max
	core_grace_t = 0
	core_hits = 0
	crews = CREWS[difficulty]
	crews_used = 0
	kills = 0
	deaths = 0
	bricks_laid = 0
	chips_taken = 0
	bosses_down = 0
	stages_cleared = 0
	score_total = 0
	outcome = ""
	music = ""
	steps = 0
	_next_id = 1
	events.clear()
	rovers.clear()
	var players := int(config.get("players", 1))
	for slot in 2:
		active[slot] = slot < players
		rovers.append(_new_rover(slot))
	start_stage(first_stage)

func _new_rover(slot: int) -> Dictionary:
	return {"slot": slot, "team": 0, "kind": "rover", "x": 0, "y": 0, "dir": 0, "half": ROVER_HALF, "alive": false, "lives": LIVES[difficulty], "max_lives": LIVES[difficulty], "power": 0, "bricks": START_BRICKS, "score": 0, "kills": 0, "respawn_t": 0, "shield_t": 0, "fire_cd": 0, "spawn_t": 0, "tread": 0, "moving": false, "recoil_t": 0, "held": [], "boss": false}

func active_count() -> int:
	return int(active[0]) + int(active[1])

func stage_info() -> Dictionary:
	return Stages.STAGES[stage]

func foes_left() -> int:
	var left := roster.size() - destroyed
	if stage_info().has("boss") and boss_state != BOSS_DOWN:
		left += 1
	return left

# ---- stage flow ----

func start_stage(index: int) -> void:
	stage = index
	tiles = Stages.grid(index)
	roster = Stages.roster(index, active_count())
	if quota > 0 and roster.size() > quota:
		roster = roster.slice(0, quota)
	next_raider = 0
	destroyed = 0
	raiders.clear()
	shots.clear()
	chips.clear()
	boss_state = BOSS_NONE
	boss_t = 0
	boss_hp = 0
	boss_max_hp = 0
	freeze_t = 0
	fort_t = 0
	core_grace_t = 0
	stage_kills = {}
	tally_lines = []
	tally_bonus = 0
	spawn_t = 20
	phase = "intro"
	phase_t = INTRO_STEPS
	music = "dusk" if index % 2 == 1 else "stage"
	for rover in rovers:
		rover.alive = false
		rover.held = []
		if active[rover.slot] and rover.lives > 0:
			_place_rover(rover)
			# The sector banner already covers the arrival.
			rover.spawn_t = 0
	audio.play("intro")
	_emit({"t": "stage"})

func step(pads: Array) -> void:
	steps += 1
	match phase:
		"intro":
			phase_t -= 1
			if phase_t <= 0:
				phase = "play"
		"play":
			_step_timers()
			for rover in rovers:
				_step_rover(rover, pads[rover.slot])
			_step_spawner()
			for raider in raiders.duplicate():
				_step_raider(raider)
			_step_shots()
			_step_chips()
			_check_end()
		"cleared":
			for rover in rovers:
				_step_rover(rover, pads[rover.slot])
			_step_shots()
			phase_t -= 1
			if phase_t <= 0:
				_begin_tally()
		"tally":
			phase_t += 1
			var shown := (tally_lines.size() + 2) * TALLY_LINE_STEPS
			if phase_t == shown:
				audio.play("tally_done")
			elif phase_t < shown and phase_t % TALLY_LINE_STEPS == 0:
				audio.play("tally")
			var skip := false
			for slot in 2:
				if active[slot] and (pads[slot] as GameInput).just_pressed(GameInput.A):
					skip = true
			if phase_t >= shown + TALLY_HOLD_STEPS or (skip and phase_t > shown):
				if stage + 1 < Stages.count():
					start_stage(stage + 1)
				else:
					phase = "won"
					phase_t = WON_STEPS
					music = ""
					audio.play("victory")
					_emit({"t": "won"})
			elif skip:
				phase_t = shown
		"won":
			phase_t -= 1
			if phase_t <= 0:
				outcome = "cleared"
		"lost":
			phase_t -= 1
			if phase_t <= 0:
				if crews > 0:
					_relieve()
				else:
					outcome = "defeated"

func _step_timers() -> void:
	if core_grace_t > 0:
		core_grace_t -= 1
	if freeze_t > 0:
		freeze_t -= 1
		if freeze_t == 0:
			audio.play("thaw")
	if fort_t > 0:
		fort_t -= 1
		if fort_t == 0:
			for cell in Stages.CORE_RING:
				if tiles[cell.y * Stages.COLS + cell.x] == Stages.T_FORT:
					tiles[cell.y * Stages.COLS + cell.x] = Stages.T_BRICK
			audio.play("thaw")

func _check_end() -> void:
	if phase != "play":
		return
	var anyone := false
	for rover in rovers:
		if active[rover.slot] and (rover.alive or rover.lives > 0):
			anyone = true
	if not anyone:
		_lose()
		return
	if destroyed < roster.size():
		return
	if not stage_info().has("boss"):
		if raiders.is_empty():
			_clear_stage()
		return
	match boss_state:
		BOSS_NONE:
			if raiders.is_empty():
				boss_state = BOSS_WARNING
				boss_t = BOSS_WARN_STEPS
				music = "boss"
				audio.play("alarm")
				_emit({"t": "warning"})
		BOSS_WARNING:
			boss_t -= 1
			if boss_t % 40 == 0 and boss_t > 0:
				audio.play("alarm")
			if boss_t <= 0:
				_spawn_boss()
		BOSS_DOWN:
			if raiders.is_empty():
				_clear_stage()

func _clear_stage() -> void:
	phase = "cleared"
	phase_t = CLEARED_STEPS
	stages_cleared += 1
	music = ""
	for index in range(shots.size() - 1, -1, -1):
		if shots[index].team == 1:
			shots.remove_at(index)
	audio.play("stage_clear")
	_emit({"t": "cleared"})

## A reserve crew takes the sector over: it starts again from its opening with a mended beacon and full garages. The score stays.
func _relieve() -> void:
	crews -= 1
	crews_used += 1
	core = core_max
	for rover in rovers:
		rover.lives = rover.max_lives
		rover.power = 0
		rover.bricks = START_BRICKS
	start_stage(stage)

func _lose() -> void:
	phase = "lost"
	phase_t = LOST_STEPS
	music = ""
	audio.play("defeat")
	_emit({"t": "lost"})

func _begin_tally() -> void:
	phase = "tally"
	phase_t = 0
	tally_lines = []
	for kind in Stages.TALLY_ORDER:
		var count := int(stage_kills.get(kind, 0))
		if count > 0:
			tally_lines.append({"kind": kind, "count": count, "points": count * int(Stages.KINDS[kind]["score"])})
	tally_bonus = 1000 + 300 * core
	var crew: Array[Dictionary] = []
	for rover in rovers:
		if active[rover.slot]:
			crew.append(rover)
	for index in crew.size():
		var share := tally_bonus / crew.size() + (tally_bonus % crew.size() if index == 0 else 0)
		crew[index].score += share
		# A knocked-out partner comes back for the next sector; everyone else gets a rover back.
		crew[index].lives = mini(int(crew[index].max_lives), int(crew[index].lives) + 1)
	score_total += tally_bonus
	core = mini(core_max, core + 1)

# ---- rovers ----

func join(slot: int) -> void:
	active[slot] = true
	var rover := rovers[slot]
	rover.held = []
	if phase in ["intro", "play", "cleared"] and rover.lives > 0 and not rover.alive:
		rover.respawn_t = 1

func leave(slot: int) -> void:
	active[slot] = false
	rovers[slot].alive = false

func _place_rover(rover: Dictionary) -> bool:
	var cell: Vector2i = Stages.PLAYER_CELLS[rover.slot]
	var x := cell.x * CELL + LANE
	var y := cell.y * CELL + LANE
	for raider in raiders:
		if absi(int(raider.x) - x) < int(raider.half) + ROVER_HALF and absi(int(raider.y) - y) < int(raider.half) + ROVER_HALF:
			return false
	rover.x = x
	rover.y = y
	rover.dir = 0
	rover.alive = true
	rover.moving = false
	rover.spawn_t = 20
	rover.shield_t = SHIELD_SPAWN_STEPS
	rover.fire_cd = 0
	rover.recoil_t = 0
	_emit({"t": "spawn", "x": x, "y": y})
	return true

func _step_rover(rover: Dictionary, pad: GameInput) -> void:
	if not active[rover.slot]:
		return
	if not rover.alive:
		if rover.lives > 0:
			rover.respawn_t -= 1
			if rover.respawn_t <= 0 and not _place_rover(rover):
				rover.respawn_t = 10
		return
	if rover.shield_t > 0:
		rover.shield_t -= 1
	if rover.fire_cd > 0:
		rover.fire_cd -= 1
	if rover.recoil_t > 0:
		rover.recoil_t -= 1
	# The direction pressed last wins, so rolling from one key to the next turns at once.
	var held: Array = rover.held
	for dir in 4:
		var down := pad.is_down(DIR_CONTROLS[dir])
		if down and not held.has(dir):
			held.append(dir)
		elif not down and held.has(dir):
			held.erase(dir)
	rover.moving = false
	if rover.spawn_t > 0:
		rover.spawn_t -= 1
		return
	if not held.is_empty():
		var want: int = held.back()
		if want != rover.dir:
			if want % 2 != int(rover.dir) % 2:
				_snap_to_lane(rover, want)
			rover.dir = want
		if _advance(rover, ROVER_SPEED):
			rover.moving = true
			rover.tread += 1
	if pad.is_down(GameInput.A) and rover.fire_cd <= 0:
		_rover_fire(rover)
	if pad.just_pressed(GameInput.B):
		_lay_brick(rover)

## Turning onto the other axis pulls the rover onto the nearest lane, so it lines up with gaps without pixel hunting.
func _snap_to_lane(rover: Dictionary, want: int) -> void:
	var x: int = rover.x
	var y: int = rover.y
	if want % 2 == 0:
		x = int(round(float(x) / LANE)) * LANE
	else:
		y = int(round(float(y) / LANE)) * LANE
	if _box_free(rover, x, y):
		rover.x = x
		rover.y = y

func _rover_fire(rover: Dictionary) -> void:
	var mine := 0
	for shot in shots:
		if shot.team == 0 and shot.owner == rover.slot:
			mine += 1
	if mine >= (2 if rover.power >= 2 else 1):
		return
	var power: int = rover.power
	_add_shot(rover, 0, 0, rover.slot, 62 if power >= 1 else 46, 3 if power >= 3 else (2 if power >= 2 else 1), 2 if power >= 3 else 1)
	rover.fire_cd = 13 if power >= 1 else 17
	rover.recoil_t = 6
	audio.play("fire")

func _lay_brick(rover: Dictionary) -> void:
	var step: Vector2i = DIRS[rover.dir]
	var col := int(rover.x) / CELL
	var row := int(rover.y) / CELL
	match int(rover.dir):
		0: row = (int(rover.y) - ROVER_HALF) / CELL - 1
		1: col = (int(rover.x) + ROVER_HALF + CELL - 1) / CELL
		2: row = (int(rover.y) + ROVER_HALF + CELL - 1) / CELL
		3: col = (int(rover.x) - ROVER_HALF) / CELL - 1
	var allowed: bool = rover.bricks > 0 and col >= 0 and row >= 0 and col < Stages.COLS and row < Stages.ROWS and step != Vector2i.ZERO
	if allowed:
		allowed = tiles[row * Stages.COLS + col] == Stages.T_EMPTY
	# The gates stay open: nobody bricks up where raiders arrive.
	if allowed and row <= 1 and (col in Stages.GATE_COLS or col == Stages.GATE_COLS[1] + 1):
		allowed = false
	if allowed:
		var cx := col * CELL + LANE
		var cy := row * CELL + LANE
		for other in _vehicles():
			if absi(int(other.x) - cx) < int(other.half) + LANE and absi(int(other.y) - cy) < int(other.half) + LANE:
				allowed = false
		for chip in chips:
			if absi(int(chip.x) - cx) < LANE and absi(int(chip.y) - cy) < LANE:
				allowed = false
	if not allowed:
		audio.play("deny")
		return
	tiles[row * Stages.COLS + col] = Stages.T_BRICK
	rover.bricks -= 1
	bricks_laid += 1
	audio.play("lay")
	_emit({"t": "lay", "x": col * CELL + LANE, "y": row * CELL + LANE})

func _hit_rover(rover: Dictionary) -> void:
	if rover.shield_t > 0 or rover.spawn_t > 0:
		audio.play("deflect")
		_emit({"t": "spark", "x": rover.x, "y": rover.y})
		return
	rover.alive = false
	rover.lives -= 1
	rover.power = maxi(0, int(rover.power) - 1)
	rover.respawn_t = RESPAWN_STEPS
	deaths += 1
	audio.play("rover_down")
	_emit({"t": "boom", "x": rover.x, "y": rover.y, "size": 2, "slot": rover.slot})

# ---- raiders ----

func _step_spawner() -> void:
	# Nothing arrives while a Stasis chip holds the field.
	if freeze_t > 0:
		return
	spawn_t -= 1
	if spawn_t > 0:
		return
	var info := stage_info()
	if boss_state == BOSS_PRESENT:
		# A boss keeps calling escorts; they are not part of the sector's count.
		if raiders.size() < 3:
			spawn_raider(str(rng.pick(["grunt", "scout", "grunt", "gunner"])), -1, false, true)
		spawn_t = 260
		return
	if next_raider >= roster.size():
		return
	var on_field := 0
	for raider in raiders:
		if not raider.escort:
			on_field += 1
	if on_field >= int(info["limit"]) + (1 if active_count() > 1 else 0):
		spawn_t = 10
		return
	if spawn_raider(roster[next_raider], -1, Stages.is_carrier(next_raider), false).is_empty():
		spawn_t = 15
		return
	next_raider += 1
	spawn_t = int(info["gap"]) + rng.int_range(0, 30)

## Bring a raider in through a gate (`gate` -1 picks a free one at random). Returns the raider, or an empty dictionary when every gate is blocked.
func spawn_raider(kind: String, gate: int, carrier: bool, escort: bool) -> Dictionary:
	var open: Array = []
	for index in Stages.GATE_COLS.size():
		if gate >= 0 and index != gate:
			continue
		var x := Stages.GATE_COLS[index] * CELL + LANE
		var blocked := false
		for other in _vehicles():
			if absi(int(other.x) - x) < int(other.half) + ROVER_HALF and absi(int(other.y) - LANE) < int(other.half) + ROVER_HALF:
				blocked = true
		if not blocked:
			open.append(index)
	if open.is_empty():
		return {}
	var chosen: int = open[0] if open.size() == 1 else rng.pick(open)
	var raider := _new_raider(kind, Stages.GATE_COLS[chosen] * CELL + LANE, LANE)
	raider.carrier = carrier
	raider.escort = escort
	raiders.append(raider)
	audio.play("spawn")
	_emit({"t": "spawn", "x": raider.x, "y": raider.y})
	return raider

func _new_raider(kind: String, x: int, y: int) -> Dictionary:
	var spec: Dictionary = Stages.KINDS[kind]
	var is_boss := bool(spec.get("boss", false))
	var hp := int(spec["hp"])
	if is_boss and active_count() > 1:
		hp = hp * 3 / 2
	var raider := {"id": _next_id, "team": 1, "kind": kind, "x": x, "y": y, "dir": 2, "half": BOSS_HALF if is_boss else ROVER_HALF, "hp": hp, "max_hp": hp, "speed": int(spec["speed"]), "fire_cd": 0, "spawn_t": 90 if is_boss else 60, "stun_t": 0, "flash_t": 0, "tread": 0, "moving": false, "recoil_t": 0, "carrier": false, "escort": false, "blocked_t": 0, "patience": 12, "node": Vector2i(-1, -1), "boss": is_boss, "volley_t": int(spec.get("volley", 0)), "charge_t": 0, "enraged": false}
	_next_id += 1
	raider.fire_cd = _fire_gap(raider)
	return raider

func _spawn_boss() -> void:
	var kind := str(stage_info()["boss"])
	var raider := _new_raider(kind, (Stages.GATE_COLS[1] + 1) * CELL, CELL)
	raiders.append(raider)
	boss_state = BOSS_PRESENT
	boss_hp = raider.hp
	boss_max_hp = raider.max_hp
	spawn_t = 200
	audio.play("boss_in")
	_emit({"t": "boss_in", "x": raider.x, "y": raider.y})

func _fire_gap(raider: Dictionary) -> int:
	var gap: Array = Stages.KINDS[raider.kind]["fire"]
	return int(rng.int_range(int(gap[0]), int(gap[1])) * FIRE_SCALE[difficulty] * (1.0 if raider.boss else float(stage_info()["calm"])))

func _step_raider(raider: Dictionary) -> void:
	if raider.flash_t > 0:
		raider.flash_t -= 1
	if raider.recoil_t > 0:
		raider.recoil_t -= 1
	raider.moving = false
	if raider.spawn_t > 0:
		raider.spawn_t -= 1
		return
	if freeze_t > 0:
		return
	if raider.stun_t > 0:
		raider.stun_t -= 1
		return
	if raider.boss and _step_boss(raider):
		return
	var lane := 0 if raider.boss else LANE
	var at_node: bool = posmod(int(raider.x) - lane, CELL) == 0 and posmod(int(raider.y) - lane, CELL) == 0
	if at_node:
		var cell := Vector2i(int(raider.x) / CELL, int(raider.y) / CELL)
		if cell != raider.node:
			raider.node = cell
			if rng.chance(0.3 if raider.kind == "scout" else 0.2):
				raider.dir = _pick_dir(raider, false)
	var ahead := _tiles_block(raider, int(raider.x) + DIRS[raider.dir].x * CELL, int(raider.y) + DIRS[raider.dir].y * CELL) if at_node else 0
	var moved := false
	if ahead == 0:
		moved = _advance_to_node(raider, lane)
	if moved:
		raider.moving = true
		raider.tread += 1
		raider.blocked_t = 0
	else:
		if raider.blocked_t == 0:
			raider.patience = rng.int_range(70, 150) if ahead == 1 else rng.int_range(8, 26)
		raider.blocked_t += 1
		# Brick in the way is shot through rather than driven around, most of the time.
		if ahead == 1 and raider.fire_cd > 24:
			raider.fire_cd = 24
		if raider.blocked_t >= raider.patience:
			raider.dir = _pick_dir(raider, true) if at_node else (int(raider.dir) + 2) % 4
			raider.blocked_t = 0
	raider.fire_cd -= 2 if _has_target(raider) else 1
	if raider.fire_cd <= 0:
		_raider_fire(raider)
		raider.fire_cd = _fire_gap(raider)

## A boss's own business: growing angrier, and the cross volley it stops to charge. Returns true while it stands still charging.
func _step_boss(raider: Dictionary) -> bool:
	boss_hp = raider.hp
	if not raider.enraged and raider.hp * 2 <= raider.max_hp:
		raider.enraged = true
		raider.speed += 2
		audio.play("enrage")
		_emit({"t": "enrage", "x": raider.x, "y": raider.y})
	if raider.charge_t > 0:
		raider.charge_t -= 1
		if raider.charge_t == 0:
			var spec: Dictionary = Stages.KINDS[raider.kind]
			for dir in 4:
				for side in [-96, 96]:
					_add_shot(raider, dir, side, raider.id, int(spec["shot_speed"]) + (8 if raider.enraged else 0), 3 if raider.kind == "dreadnought" else 2, 1)
			raider.recoil_t = 8
			audio.play("volley")
			_emit({"t": "shake", "amount": 3.0})
		return true
	raider.volley_t -= 1
	if raider.volley_t <= 0:
		raider.volley_t = int(Stages.KINDS[raider.kind]["volley"]) * (2 if not raider.enraged else 1) / 2 + rng.int_range(0, 40)
		raider.charge_t = 45
		audio.play("charge")
		return true
	return false

func _advance_to_node(raider: Dictionary, lane: int) -> bool:
	var step: Vector2i = DIRS[raider.dir]
	var along: int = raider.x if step.x != 0 else raider.y
	var rest := posmod(along - lane, CELL)
	var to_node := CELL if rest == 0 else (CELL - rest if step.x + step.y > 0 else rest)
	var distance := mini(int(raider.speed), to_node)
	if not _box_free(raider, int(raider.x) + step.x * distance, int(raider.y) + step.y * distance):
		return false
	raider.x += step.x * distance
	raider.y += step.y * distance
	if raider.boss:
		_crush(raider)
	return true

## Choose a heading at a node. Raiders drift down and towards the beacon, more stubbornly in later sectors; scouts go for the nearest rover instead half of the time, and a boss always does.
func _pick_dir(raider: Dictionary, forced: bool) -> int:
	var aggression := float(stage_info()["aggression"])
	var target := Vector2i((Stages.CORE_COL + 1) * CELL, (Stages.CORE_ROW + 1) * CELL)
	if raider.boss or (raider.kind == "scout" and rng.chance(0.5)):
		var nearest := 1 << 30
		for rover in rovers:
			if rover.alive:
				var away := absi(int(rover.x) - int(raider.x)) + absi(int(rover.y) - int(raider.y))
				if away < nearest:
					nearest = away
					target = Vector2i(rover.x, rover.y)
	var weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var total := 0.0
	for dir in 4:
		var step: Vector2i = DIRS[dir]
		var block := _tiles_block(raider, int(raider.x) + step.x * CELL, int(raider.y) + step.y * CELL)
		if block == 2:
			continue
		var weight := 1.0
		if step.y != 0 and signi(target.y - int(raider.y)) == step.y:
			weight += aggression * 1.5
		elif step.y < 0:
			weight *= 0.35
		if step.x != 0 and signi(target.x - int(raider.x)) == step.x:
			weight += aggression * (0.5 + 1.5 * float(raider.y) / float(FIELD_H))
		if block == 1:
			weight *= 0.6
		if dir == (int(raider.dir) + 2) % 4:
			weight *= 0.3
		if forced and dir == raider.dir:
			weight *= 0.25
		weights[dir] = weight
		total += weight
	if total <= 0.0:
		return raider.dir
	var roll := rng.unit() * total
	for dir in 4:
		roll -= weights[dir]
		if roll < 0.0 and weights[dir] > 0.0:
			return dir
	return raider.dir

## Whether a rover or the beacon sits in the raider's line of fire, which makes it shoot sooner.
func _has_target(raider: Dictionary) -> bool:
	var step: Vector2i = DIRS[raider.dir]
	var reach := int(raider.half) + 48
	for rover in rovers:
		if not rover.alive:
			continue
		var dx := int(rover.x) - int(raider.x)
		var dy := int(rover.y) - int(raider.y)
		if step.x != 0 and absi(dy) < reach and signi(dx) == step.x:
			return true
		if step.y != 0 and absi(dx) < reach and signi(dy) == step.y:
			return true
	if raider.boss:
		return false
	var core_x := (Stages.CORE_COL + 1) * CELL
	if step.y > 0 and absi(core_x - int(raider.x)) < CELL + reach - 48:
		return true
	return step.x != 0 and int(raider.y) > Stages.CORE_ROW * CELL - 48 and signi(core_x - int(raider.x)) == step.x

func _raider_fire(raider: Dictionary) -> void:
	var spec: Dictionary = Stages.KINDS[raider.kind]
	var mine := 0
	for shot in shots:
		if shot.team == 1 and shot.owner == raider.id:
			mine += 1
	if mine >= int(spec["shots"]):
		return
	var speed := int(spec["shot_speed"])
	var power := int(spec["shot_power"])
	if raider.boss:
		_add_shot(raider, raider.dir, -96, raider.id, speed, power, 1)
		_add_shot(raider, raider.dir, 96, raider.id, speed, power, 1)
		if raider.kind == "dreadnought" and raider.enraged:
			_add_shot(raider, raider.dir, 0, raider.id, speed + 10, 3, 1)
		audio.play("boss_fire")
	else:
		_add_shot(raider, raider.dir, 0, raider.id, speed, power, 1)
		audio.play("raider_fire")
	raider.recoil_t = 6

func _hit_raider(raider: Dictionary, shot: Dictionary) -> void:
	raider.hp -= int(shot.dmg)
	raider.flash_t = 6
	if raider.boss:
		boss_hp = maxi(0, raider.hp)
	if raider.hp <= 0:
		_destroy_raider(raider, shot.owner)
	else:
		audio.play("boss_hit" if raider.boss else "clank")
		_emit({"t": "spark", "x": shot.x, "y": shot.y})

func _destroy_raider(raider: Dictionary, slot: int) -> void:
	raiders.erase(raider)
	var points := int(Stages.KINDS[raider.kind]["score"])
	if slot == -2:
		# The beacon's pulse did it: the raider is gone, but that is nobody's kill.
		points = 0
	else:
		kills += 1
		stage_kills[raider.kind] = int(stage_kills.get(raider.kind, 0)) + 1
		score_total += points
	if slot == -2:
		pass
	elif slot >= 0 and slot < 2:
		var rover := rovers[slot]
		rover.score += points
		rover.kills += 1
		if rover.kills % KILLS_PER_BRICK == 0 and rover.bricks < MAX_BRICKS:
			rover.bricks += 1
	else:
		# Nobody's shell did it (a Surge chip): the points still count for the team, credited to the first rover in play.
		for rover in rovers:
			if active[rover.slot]:
				rover.score += points
				break
	if raider.boss:
		boss_state = BOSS_DOWN
		boss_hp = 0
		bosses_down += 1
		for index in range(shots.size() - 1, -1, -1):
			if shots[index].team == 1:
				shots.remove_at(index)
		for escort in raiders.duplicate():
			raiders.erase(escort)
			_emit({"t": "boom", "x": escort.x, "y": escort.y, "size": 1})
		audio.play("boss_down")
		_emit({"t": "boom", "x": raider.x, "y": raider.y, "size": 4})
		_emit({"t": "shake", "amount": 7.0})
	else:
		if not raider.escort:
			destroyed += 1
		audio.play("boom_big" if raider.kind == "bulwark" else "boom")
		_emit({"t": "boom", "x": raider.x, "y": raider.y, "size": 2 if raider.kind == "bulwark" else 1})
	if points > 0:
		_emit({"t": "points", "x": raider.x, "y": raider.y, "points": points})
	if raider.carrier:
		_drop_chip()

## A boss flattens the brick it drives over.
func _crush(raider: Dictionary) -> void:
	var half: int = raider.half
	for row in range((int(raider.y) - half) / CELL, (int(raider.y) + half - 1) / CELL + 1):
		for col in range((int(raider.x) - half) / CELL, (int(raider.x) + half - 1) / CELL + 1):
			var index := row * Stages.COLS + col
			if tiles[index] == Stages.T_BRICK or tiles[index] == Stages.T_CRACKED:
				tiles[index] = Stages.T_EMPTY
				audio.play("brick_break")
				_emit({"t": "brick", "x": col * CELL + LANE, "y": row * CELL + LANE, "broke": true})

# ---- movement and collision ----

func _vehicles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rover in rovers:
		if rover.alive:
			out.append(rover)
	out.append_array(raiders)
	return out

## What the tiles under a vehicle's box at (x, y) do to it: 0 nothing, 1 only brick in the way, 2 something it can never pass (plate, water, the beacon, the edge of the field). Brick does not stop a boss.
func _tiles_block(vehicle: Dictionary, x: int, y: int) -> int:
	var half: int = vehicle.half
	if x - half < 0 or y - half < 0 or x + half > FIELD_W or y + half > FIELD_H:
		return 2
	# The beacon's own field keeps the heaviest machines out of the rows around it.
	if vehicle.boss and y + half > BOSS_FLOOR_ROW * CELL:
		return 2
	var worst := 0
	for row in range((y - half) / CELL, (y + half - 1) / CELL + 1):
		for col in range((x - half) / CELL, (x + half - 1) / CELL + 1):
			match tiles[row * Stages.COLS + col]:
				Stages.T_BRICK, Stages.T_CRACKED:
					if not vehicle.boss:
						worst = maxi(worst, 1)
				Stages.T_PLATE, Stages.T_WATER, Stages.T_CORE, Stages.T_FORT:
					return 2
	return worst

## Whether a vehicle may stand at (x, y). Two vehicles that already overlap (one just arrived on top of the other) may always drive apart.
func _box_free(vehicle: Dictionary, x: int, y: int) -> bool:
	if _tiles_block(vehicle, x, y) != 0:
		return false
	for other in _vehicles():
		if other == vehicle or (other.team == 1 and other.spawn_t > 0) or (vehicle.team == 1 and vehicle.spawn_t > 0):
			continue
		var reach: int = int(vehicle.half) + int(other.half)
		if absi(x - int(other.x)) < reach and absi(y - int(other.y)) < reach:
			var was_over: bool = absi(int(vehicle.x) - int(other.x)) < reach and absi(int(vehicle.y) - int(other.y)) < reach
			var closer: bool = absi(x - int(other.x)) + absi(y - int(other.y)) < absi(int(vehicle.x) - int(other.x)) + absi(int(vehicle.y) - int(other.y))
			if not was_over or closer:
				return false
	return true

## Drive a rover up to `distance` along its heading, stopping flush against whatever is in the way.
func _advance(vehicle: Dictionary, distance: int) -> bool:
	var step: Vector2i = DIRS[vehicle.dir]
	var reach := distance
	while reach > 0:
		if _box_free(vehicle, int(vehicle.x) + step.x * reach, int(vehicle.y) + step.y * reach):
			vehicle.x += step.x * reach
			vehicle.y += step.y * reach
			return true
		reach = reach / 2
	return false

# ---- shells ----

func _add_shot(from: Dictionary, dir: int, side: int, owner: int, speed: int, power: int, dmg: int) -> void:
	var heading: int = from.dir if from.team == 0 else dir
	var step: Vector2i = DIRS[heading]
	var x: int = int(from.x) + step.x * int(from.half) + absi(step.y) * side
	var y: int = int(from.y) + step.y * int(from.half) + absi(step.x) * side
	shots.append({"x": x, "y": y, "dir": heading, "speed": speed, "team": from.team, "owner": owner, "power": power, "dmg": dmg, "dead": false})
	_emit({"t": "muzzle", "x": x, "y": y, "dir": heading})

func _step_shots() -> void:
	for shot in shots:
		if shot.dead:
			continue
		var step: Vector2i = DIRS[shot.dir]
		shot.x += step.x * int(shot.speed)
		shot.y += step.y * int(shot.speed)
		if shot.x < 0 or shot.y < 0 or shot.x >= FIELD_W or shot.y >= FIELD_H:
			shot.dead = true
			_emit({"t": "spark", "x": clampi(shot.x, 0, FIELD_W - 1), "y": clampi(shot.y, 0, FIELD_H - 1)})
			continue
		if _shot_hits_tiles(shot):
			shot.dead = true
			continue
		var wide := SHOT_WIDE if step.x == 0 else SHOT_LONG
		var tall := SHOT_LONG if step.x == 0 else SHOT_WIDE
		if shot.team == 0:
			for raider in raiders:
				if raider.spawn_t <= 0 and absi(int(shot.x) - int(raider.x)) < int(raider.half) + wide and absi(int(shot.y) - int(raider.y)) < int(raider.half) + tall:
					shot.dead = true
					_hit_raider(raider, shot)
					break
		else:
			for rover in rovers:
				if rover.alive and absi(int(shot.x) - int(rover.x)) < ROVER_HALF + wide and absi(int(shot.y) - int(rover.y)) < ROVER_HALF + tall:
					shot.dead = true
					_hit_rover(rover)
					break
	# Shells of the two sides knock each other out of the air.
	for first in shots:
		if first.dead or first.team != 0:
			continue
		for second in shots:
			if second.dead or second.team != 1:
				continue
			var reach := SHOT_LONG * 2 + (int(first.speed) + int(second.speed)) / 2
			if absi(int(first.x) - int(second.x)) < reach and absi(int(first.y) - int(second.y)) < reach and (absi(int(first.x) - int(second.x)) < SHOT_WIDE * 2 + 16 or absi(int(first.y) - int(second.y)) < SHOT_WIDE * 2 + 16):
				first.dead = true
				second.dead = true
				audio.play("deflect")
				_emit({"t": "spark", "x": first.x, "y": first.y})
				break
	for index in range(shots.size() - 1, -1, -1):
		if shots[index].dead:
			shots.remove_at(index)

func _shot_hits_tiles(shot: Dictionary) -> bool:
	var step: Vector2i = DIRS[shot.dir]
	var front_x: int = clampi(int(shot.x) + step.x * SHOT_LONG, 0, FIELD_W - 1)
	var front_y: int = clampi(int(shot.y) + step.y * SHOT_LONG, 0, FIELD_H - 1)
	var hit := false
	var seen := -1
	for side in [-SHOT_BLAST, SHOT_BLAST - 1]:
		var px: int = clampi(front_x + absi(step.y) * side, 0, FIELD_W - 1)
		var py: int = clampi(front_y + absi(step.x) * side, 0, FIELD_H - 1)
		var index: int = (py / CELL) * Stages.COLS + px / CELL
		if index == seen:
			continue
		seen = index
		var cx: int = (index % Stages.COLS) * CELL + LANE
		var cy: int = (index / Stages.COLS) * CELL + LANE
		match tiles[index]:
			Stages.T_BRICK:
				hit = true
				if shot.power >= 2:
					tiles[index] = Stages.T_EMPTY
					audio.play("brick_break")
					_emit({"t": "brick", "x": cx, "y": cy, "broke": true})
				else:
					tiles[index] = Stages.T_CRACKED
					audio.play("brick_hit")
					_emit({"t": "brick", "x": cx, "y": cy, "broke": false})
			Stages.T_CRACKED:
				hit = true
				tiles[index] = Stages.T_EMPTY
				audio.play("brick_break")
				_emit({"t": "brick", "x": cx, "y": cy, "broke": true})
			Stages.T_PLATE:
				hit = true
				if shot.power >= 3:
					tiles[index] = Stages.T_EMPTY
					audio.play("plate_break")
					_emit({"t": "plate", "x": cx, "y": cy, "broke": true})
				else:
					audio.play("plate_hit")
					_emit({"t": "spark", "x": shot.x, "y": shot.y})
			Stages.T_FORT:
				hit = true
				audio.play("plate_hit")
				_emit({"t": "spark", "x": shot.x, "y": shot.y})
			Stages.T_CORE:
				hit = true
				if shot.team == 1:
					_hit_core()
				else:
					_emit({"t": "spark", "x": shot.x, "y": shot.y})
	return hit

# ---- the beacon ----

func _hit_core() -> void:
	if core_grace_t > 0 or phase != "play":
		return
	core -= 1
	core_hits += 1
	core_grace_t = CORE_GRACE_STEPS
	var core_x := (Stages.CORE_COL + 1) * CELL
	var core_y := (Stages.CORE_ROW + 1) * CELL
	# The beacon answers a hit with a pulse: raider shells in the air are gone, a raider right at the wall is destroyed (nobody scores for it), and raiders a little further out stall for a moment.
	for shot in shots:
		if shot.team == 1:
			shot.dead = true
	for raider in raiders.duplicate():
		if raider.boss:
			continue
		var away: int = absi(int(raider.x) - core_x) + absi(int(raider.y) - core_y)
		if away < PULSE_KILL_REACH:
			_destroy_raider(raider, -2)
		elif away < PULSE_STUN_REACH:
			raider.stun_t = 150
	_emit({"t": "core_hit", "x": core_x, "y": core_y})
	_emit({"t": "shake", "amount": 5.0})
	if core <= 0:
		core = 0
		audio.play("core_lost")
		_emit({"t": "boom", "x": core_x, "y": core_y, "size": 4})
		_lose()
	else:
		audio.play("core_hit")

# ---- supply chips ----

func _drop_chip() -> void:
	var free: Array[Vector2i] = []
	for row in range(2, Stages.ROWS - 1):
		for col in Stages.COLS:
			if tiles[row * Stages.COLS + col] != Stages.T_EMPTY:
				continue
			var taken := false
			for chip in chips:
				if int(chip.x) / CELL == col and int(chip.y) / CELL == row:
					taken = true
			if not taken:
				free.append(Vector2i(col, row))
	if free.is_empty():
		return
	var cell: Vector2i = rng.pick(free)
	var kind: String = rng.pick(CHIP_KINDS)
	chips.append({"kind": kind, "x": cell.x * CELL + LANE, "y": cell.y * CELL + LANE, "t": CHIP_STEPS})
	audio.play("chip_drop")
	_emit({"t": "chip_drop", "x": cell.x * CELL + LANE, "y": cell.y * CELL + LANE})

func _step_chips() -> void:
	for index in range(chips.size() - 1, -1, -1):
		var chip := chips[index]
		chip.t -= 1
		var taker := {}
		for rover in rovers:
			if rover.alive and absi(int(rover.x) - int(chip.x)) < ROVER_HALF + CHIP_HALF and absi(int(rover.y) - int(chip.y)) < ROVER_HALF + CHIP_HALF:
				taker = rover
				break
		if not taker.is_empty():
			chips.remove_at(index)
			take_chip(taker, chip.kind)
		elif chip.t <= 0:
			chips.remove_at(index)

## Apply a supply chip to the rover that drove over it.
func take_chip(rover: Dictionary, kind: String) -> void:
	chips_taken += 1
	var points := 300
	match kind:
		"coil":
			if rover.power < MAX_POWER:
				rover.power += 1
			else:
				points = 800
			audio.play("power")
		"aegis":
			rover.shield_t = SHIELD_CHIP_STEPS
			audio.play("shield")
		"stasis":
			freeze_t = FREEZE_STEPS
			audio.play("freeze")
		"mason":
			fort_t = FORT_STEPS
			for cell in Stages.CORE_RING:
				tiles[cell.y * Stages.COLS + cell.x] = Stages.T_FORT
			rover.bricks = mini(MAX_BRICKS, int(rover.bricks) + 2)
			audio.play("fortify")
		"surge":
			for raider in raiders.duplicate():
				if raider.boss:
					raider.hp = maxi(1, int(raider.hp) - 6)
					raider.flash_t = 10
					boss_hp = raider.hp
				else:
					_destroy_raider(raider, -1)
			audio.play("surge")
			_emit({"t": "surge"})
			_emit({"t": "shake", "amount": 6.0})
		"spare":
			if rover.lives < rover.max_lives:
				rover.lives += 1
			else:
				points = 1000
			audio.play("life")
	rover.score += points
	score_total += points
	_emit({"t": "chip_take", "x": rover.x, "y": rover.y, "kind": kind, "slot": rover.slot})
	_emit({"t": "points", "x": rover.x, "y": rover.y, "points": points})

# ---- reporting ----

func _emit(event: Dictionary) -> void:
	events.append(event)
	if events.size() > EVENT_CAP:
		events.pop_front()

## A number that changes whenever anything in the simulation does. Two runs with the same seed and inputs report the same digest at every step.
func digest() -> int:
	var value := steps * 31 + score_total
	for rover in rovers:
		value = (value * 131 + int(rover.x) * 7 + int(rover.y) * 13 + int(rover.dir) + int(rover.lives) * 17 + int(rover.alive)) & 0x7FFFFFFF
	for raider in raiders:
		value = (value * 131 + int(raider.x) * 7 + int(raider.y) * 13 + int(raider.dir) + int(raider.hp) * 17) & 0x7FFFFFFF
	for shot in shots:
		value = (value * 131 + int(shot.x) * 7 + int(shot.y) * 13 + int(shot.dir)) & 0x7FFFFFFF
	for tile in tiles:
		value = (value * 31 + tile) & 0x7FFFFFFF
	return (value * 31 + rng.state()) & 0x7FFFFFFF
