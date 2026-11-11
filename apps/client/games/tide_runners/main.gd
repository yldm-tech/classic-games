extends GameModule

## Tide Runners: a side-scrolling run-and-gun for one or two divers. This script owns the run: it loads the stages, steps the divers, their shots, the machines and the boss in a fixed order, and reports the state. The pieces live next to it: world.gd (tiles and collision), levels.gd (stage data), heroes.gd, foes.gd, bosses.gd (behaviour), sounds.gd (effects and music), gfx.gd (sprites) and view.gd (drawing).

const World := preload("res://games/tide_runners/world.gd")
const Levels := preload("res://games/tide_runners/levels.gd")
const Heroes := preload("res://games/tide_runners/heroes.gd")
const Foes := preload("res://games/tide_runners/foes.gd")
const Bosses := preload("res://games/tide_runners/bosses.gd")
const Sounds := preload("res://games/tide_runners/sounds.gd")
const Gfx := preload("res://games/tide_runners/gfx.gd")
const View := preload("res://games/tide_runners/view.gd")

const VIEW := Vector2(480.0, 270.0)
const START_LIVES := [5, 3, 2]
const CONTINUES := [4, 3, 2]
const PACE := [1.25, 1.0, 0.8]
const SHOT_SPEED := [0.85, 1.0, 1.15]
const BOSS_SCALE := [0.85, 1.0, 1.15]
const TIDE_SPEED := [4.0, 5.0, 6.5]
const TIDE_RESPITE := 72.0
const BOMB_GRAVITY := 300.0
const H_WATER := 246.0
const WEAPONS := 6
const SHIELD := 6
const ITEM_LIFE := 14.0
const EXTRA_LIFE_EVERY := 20000
const MODE_PLAY := 0
const MODE_CLEAR := 1
const MODE_OVER := 2

var world: World = World.new()
var difficulty := 1
var pace := 1.0
var shot_speed := 1.0
var boss_scale := 1.0
var start_lives := 3
var continues := 2
var continues_used := 0
var deaths := 0
var kills := 0
var bosses_down := 0
var weapons_seen := 0
var stage_index := 0
var mode := MODE_PLAY
var mode_t := 0.0
var intro_t := 0.0
var warn_t := 0.0
var go_t := 0.0
var over_t := -1.0
var flash := 0.0
var cam := Vector2.ZERO
var water_y := 0.0
var heroes: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var foe_shots: Array[Dictionary] = []
var foes: Array[Dictionary] = []
var items: Array[Dictionary] = []
var boss: Dictionary = {}
var boss_started := false
var foe_serial := 0
var spawned: Array = []
var zone_t: Array = []
var lock: Dictionary = {}
var lock_index := 0
## Presentation only, but stepped with the simulation so a replay looks the same: particles, blasts, floating labels, the banner and the shake.
var sparks: Array[Dictionary] = []
var blasts: Array[Dictionary] = []
var labels: Array[Dictionary] = []
var banner := ""
var banner_t := 0.0
var shake_power := 0.0
var fx_rng: GameRng = Rng.new(1)

var _camera: Camera2D
var _gfx: Gfx
var _view: View

func _game_start(config: Dictionary) -> void:
	var chosen: Dictionary = config["options"]
	difficulty = clampi(int(chosen.get("difficulty", 1)), 0, 2)
	pace = PACE[difficulty]
	shot_speed = SHOT_SPEED[difficulty]
	start_lives = maxi(1, int(chosen.get("_lives", START_LIVES[difficulty])))
	continues = int(chosen.get("_continues", CONTINUES[difficulty]))
	continues_used = 0
	deaths = 0
	kills = 0
	bosses_down = 0
	weapons_seen = 0
	foe_serial = 0
	over_t = -1.0
	flash = 0.0
	shake_power = 0.0
	banner = ""
	banner_t = 0.0
	fx_rng.reseed(int(config["seed"]) ^ 0x51DE)
	heroes.clear()
	for slot in MAX_PLAYERS:
		var h := Heroes.make(slot, start_lives)
		h["active"] = is_player_active(slot)
		h["out"] = not is_player_active(slot)
		h["seen"] = is_player_active(slot)
		heroes.append(h)
	if _camera == null:
		_camera = Camera2D.new()
		_camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		add_child(_camera)
	Sounds.define_all(audio)
	_load_stage(clampi(int(chosen.get("_stage", 0)), 0, Levels.STAGE_COUNT - 1))
	if int(chosen.get("_boss", 0)) == 1:
		_skip_to_boss()

# ---- stages ----

func _load_stage(index: int) -> void:
	stage_index = index
	world.load_stage(Levels.stage(index))
	shots.clear()
	foe_shots.clear()
	foes.clear()
	items.clear()
	sparks.clear()
	blasts.clear()
	labels.clear()
	lock = {}
	lock_index = 0
	go_t = 0.0
	warn_t = 0.0
	boss_started = false
	mode = MODE_PLAY
	mode_t = 0.0
	intro_t = 3.0
	spawned = []
	spawned.resize((world.def["spawns"] as Array).size())
	spawned.fill(0)
	zone_t = []
	for zone: Array in world.def["zones"]:
		zone_t.append(float(zone[3]) * 0.6)
	cam = Vector2(0.0, world.height() - VIEW.y) if world.vertical else Vector2.ZERO
	water_y = world.height() + 40.0 if world.vertical else H_WATER
	boss_scale = BOSS_SCALE[difficulty] * (1.5 if player_count() > 1 else 1.0)
	boss = Bosses.make(self, int(world.def["boss"]))
	var start: Vector2 = world.def["start"]
	for h in heroes:
		if not h["active"]:
			continue
		# A diver who ran out of lives comes back for the next stage with two.
		if int(h["lives"]) <= 0:
			h["lives"] = 2
		_place(h, start.x + 26.0 * int(h["slot"]), start.y)
	audio.play_music(Sounds.stage_music(index))

func _place(h: Dictionary, x: float, y: float) -> void:
	h["x"] = x
	h["y"] = y
	h["vx"] = 0.0
	h["vy"] = 0.0
	h["ground"] = false
	h["prone"] = false
	h["alive"] = true
	h["out"] = false
	h["drop_t"] = 0.0
	h["dead_t"] = 0.0

## Test and capture aid, reached only through an option that no menu offers: start the stage at its boss arena.
func _skip_to_boss() -> void:
	spawned.fill(1)
	lock_index = (world.def["locks"] as Array).size()
	intro_t = 0.0
	if world.vertical:
		cam = Vector2.ZERO
		water_y = float(world.def["boss_row"]) * World.TILE + 12.0
		for h in heroes:
			if h["active"]:
				_place(h, 200.0 + 40.0 * int(h["slot"]), float(world.def["boss_row"]) * World.TILE)
	else:
		cam.x = float(world.def["boss_col"]) * World.TILE
		for h in heroes:
			if h["active"]:
				_place(h, cam.x + 70.0 + 26.0 * int(h["slot"]), 224.0)

# ---- one step ----

func _game_step(delta: float) -> void:
	intro_t = maxf(0.0, intro_t - delta)
	go_t = maxf(0.0, go_t - delta)
	flash = maxf(0.0, flash - delta)
	banner_t = maxf(0.0, banner_t - delta)
	shake_power = maxf(0.0, shake_power - 22.0 * delta)
	for h in heroes:
		if h["active"]:
			Heroes.step(self, h, input(int(h["slot"])), delta)
	_step_camera(delta)
	if mode == MODE_PLAY:
		Foes.direct(self, delta)
	Foes.step(self, delta)
	_step_boss(delta)
	_step_shots(delta)
	_step_foe_shots(delta)
	_step_items(delta)
	_step_contacts()
	_step_fx(delta)
	_step_flow(delta)

func _step_camera(delta: float) -> void:
	var lead := -INF
	var rear := INF
	var top := INF
	var bottom := -INF
	for h in heroes:
		if h["active"] and h["alive"]:
			lead = maxf(lead, float(h["x"]))
			rear = minf(rear, float(h["x"]))
			top = minf(top, float(h["y"]))
			bottom = maxf(bottom, float(h["y"]))
	if world.vertical:
		if boss_started:
			cam.y = maxf(0.0, cam.y - 90.0 * delta)
		elif top < INF:
			# Follow the higher diver up, but never leave the lower one under the view.
			var target := maxf(top - 150.0, bottom - 236.0)
			cam.y = clampf(maxf(target, cam.y - 220.0 * delta), 0.0, cam.y)
		var floor_line := float(world.def["boss_row"]) * World.TILE + 12.0
		if intro_t <= 0.0 and mode == MODE_PLAY:
			water_y -= TIDE_SPEED[difficulty] * delta
		water_y = maxf(floor_line, minf(water_y, cam.y + VIEW.y + 40.0))
		return
	var limit := float(world.def["boss_col"]) * World.TILE
	var locks: Array = world.def["locks"]
	if not lock.is_empty():
		limit = cam.x
	elif lock_index < locks.size():
		limit = minf(limit, float(locks[lock_index][0]) * World.TILE)
	if lead > -INF:
		var target := minf(lead - 190.0, rear - 14.0)
		cam.x = clampf(minf(target, cam.x + 240.0 * delta), cam.x, maxf(cam.x, limit))

func _step_boss(delta: float) -> void:
	if boss.is_empty():
		return
	if not boss_started and mode == MODE_PLAY:
		var reached := false
		if world.vertical:
			for h in heroes:
				if h["active"] and h["alive"] and h["ground"] and float(h["y"]) <= float(world.def["boss_row"]) * World.TILE + 0.5:
					reached = true
		else:
			reached = cam.x >= float(world.def["boss_col"]) * World.TILE - 0.5
		if reached:
			boss_started = true
			warn_t = 2.4
			lock = {}
			audio.play_music(Sounds.boss_music())
			sfx("alarm")
	if boss_started and not boss["active"]:
		warn_t -= delta
		if warn_t <= 0.0:
			boss["active"] = true
	Bosses.step(self, boss, delta)

func _step_flow(delta: float) -> void:
	match mode:
		MODE_PLAY:
			if not boss.is_empty() and boss["dead"]:
				mode = MODE_CLEAR
				mode_t = 5.0
				bosses_down += 1
				audio.stop_music()
				sfx("fanfare")
				for h in heroes:
					if h["active"] and not h["out"]:
						add_score(int(h["slot"]), 2000 + 500 * int(h["lives"]))
				return
			var anyone := false
			for h in heroes:
				if h["active"] and not h["out"]:
					anyone = true
			if not anyone:
				mode = MODE_OVER
				mode_t = 1.6
		MODE_CLEAR:
			mode_t -= delta
			if mode_t <= 0.0:
				if stage_index + 1 < Levels.STAGE_COUNT:
					_load_stage(stage_index + 1)
				else:
					finish(OUTCOME_CLEARED)
		MODE_OVER:
			# A diver who joins while the run waits to continue keeps it going, and no continue is spent.
			for h in heroes:
				if h["active"] and not h["out"]:
					mode = MODE_PLAY
					return
			mode_t -= delta
			if mode_t > 0.0:
				return
			if continues <= 0:
				finish(OUTCOME_DEFEATED)
				return
			continues -= 1
			continues_used += 1
			mode = MODE_PLAY
			say("continue", 2.0)
			sfx("respawn")
			for h in heroes:
				if h["active"]:
					h["lives"] = start_lives
					respawn(h)

# ---- divers ----

func hero_box(h: Dictionary) -> Rect2:
	return Heroes.box(h)

## The x range a diver may stand in: the view, and never inside the first boss's hull.
func hero_bounds() -> Vector2:
	if world.vertical:
		return Vector2(21.0, 459.0)
	var right := cam.x + VIEW.x - 8.0
	if not boss.is_empty() and int(boss["kind"]) == 0 and not boss["dead"]:
		right = minf(right, float(boss["x"]) - 6.0)
	return Vector2(cam.x + 8.0, right)

func can_drop(y: float) -> bool:
	return not (world.vertical and boss_started and y >= float(world.def["boss_row"]) * World.TILE - 1.0)

func water_line() -> float:
	return water_y

func drown_line() -> float:
	return water_y + (8.0 if world.vertical else 16.0)

func nearest_hero(x: float, y: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for h in heroes:
		if not (h["active"] and h["alive"]):
			continue
		var distance := Vector2(float(h["x"]) - x, float(h["y"]) - y).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = h
	return best

func in_view(x: float, y: float, margin: float) -> bool:
	return Rect2(cam, VIEW).grow(margin).has_point(Vector2(x, y))

## Something touched a diver. A fresh diver is safe for a moment and a bubble shield takes one hit.
func hit_hero(h: Dictionary) -> void:
	if not h["alive"] or float(h["inv"]) > 0.0:
		return
	if h["shield"]:
		h["shield"] = false
		h["inv"] = 1.2
		sfx("shield_pop")
		_burst(float(h["x"]), float(h["y"]) - 10.0, 10, "4", 90.0)
		return
	_lose_life(h)

## A diver went into the water: no shield helps.
func fell(h: Dictionary) -> void:
	if h["alive"]:
		sfx("splash")
		_lose_life(h)

func _lose_life(h: Dictionary) -> void:
	h["alive"] = false
	h["dead_t"] = Heroes.DEATH_TIME
	h["lives"] = int(h["lives"]) - 1
	h["weapon"] = 0
	h["shield"] = false
	h["prone"] = false
	h["vx"] = -int(h["face"]) * 44.0
	h["vy"] = -190.0
	deaths += 1
	sfx("die")
	shake(6.0)
	flash = maxf(flash, 0.12)
	_burst(float(h["x"]), float(h["y"]) - 10.0, 14, "f", 130.0)

func respawn(h: Dictionary) -> void:
	var at := _find_spawn()
	if world.vertical and not boss_started:
		# The tide falls back under a diver who returns. Without that it stood at their feet, and the same water that took one life took the next before they could climb.
		water_y = maxf(water_y, at.y + TIDE_RESPITE)
	_place(h, at.x, at.y)
	h["ground"] = true
	h["inv"] = Heroes.RESPAWN_SAFE
	h["weapon"] = 0
	sfx("respawn")

## A dry place in the view for a diver to come back at: low, away from the water and with head room.
func _find_spawn() -> Vector2:
	var best := Vector2(cam.x + 100.0, cam.y + 80.0)
	var best_score := -INF
	var wanted_x := cam.x + (240.0 if world.vertical else 110.0)
	for column in range(floori((cam.x + 24.0) / World.TILE), floori((cam.x + 440.0) / World.TILE) + 1):
		# In the tower the water may have taken the lower half of the view, so the search starts higher there (still under the HUD).
		for row in range(floori((cam.y + (56.0 if world.vertical else 100.0)) / World.TILE), floori((cam.y + 262.0) / World.TILE) + 1):
			if world.cell(column, row) == World.EMPTY or world.cell(column, row - 1) != World.EMPTY or world.cell(column, row - 2) != World.EMPTY:
				continue
			var y := float(row * World.TILE)
			if y > water_line() - 20.0:
				continue
			var x := float(column * World.TILE) + 8.0
			var bounds := hero_bounds()
			if x < bounds.x or x > bounds.y:
				continue
			var rating := -absf(x - wanted_x) + (y - cam.y) * 0.4
			if rating > best_score:
				best_score = rating
				best = Vector2(x, y)
	return best

func add_score(slot: int, points: int) -> void:
	var h := heroes[clampi(slot, 0, MAX_PLAYERS - 1)]
	h["score"] = int(h["score"]) + points
	score += points
	if int(h["score"]) >= int(h["next_life"]):
		h["next_life"] = int(h["next_life"]) + EXTRA_LIFE_EVERY
		if h["active"] and not h["out"]:
			h["lives"] = int(h["lives"]) + 1
			sfx("extra_life")
			_label(float(h["x"]), float(h["y"]) - 30.0, "1up")

# ---- shots ----

func fire(h: Dictionary) -> void:
	var origin := Heroes.muzzle(h)
	var aim: Vector2i = h["aim"]
	var dir := Vector2(float(h["face"]), 0.0) if h["prone"] else Vector2(aim).normalized()
	var slot: int = h["slot"]
	match int(h["weapon"]):
		0:
			_shot(origin, dir * 330.0, "rivet", 1, slot)
		1:
			for turn: float in [-0.2, 0.0, 0.2]:
				_shot(origin, dir.rotated(turn) * 300.0, "fork", 1, slot)
		2:
			for side: float in [-1.0, 1.0]:
				var wave := _shot(origin, dir * 250.0, "arc", 1, slot)
				wave["pierce"] = true
				wave["ph"] = side
		3:
			_shot(origin, dir * 200.0 + Vector2(0.0, -70.0), "limpet", 4, slot)
		4:
			var lance := _shot(origin, dir * 520.0, "lance", 3, slot)
			lance["pierce"] = true
		5:
			var disc := _shot(origin, dir * 240.0, "disc", 2, slot)
			disc["bounce"] = 3
			disc["life"] = 2.4
	sfx("shot%d" % int(h["weapon"]))
	_burst(origin.x, origin.y, 1, "f", 20.0)

func _shot(at: Vector2, velocity: Vector2, kind: String, damage: int, slot: int) -> Dictionary:
	var shot := {"x": at.x, "y": at.y, "bx": at.x, "by": at.y, "vx": velocity.x, "vy": velocity.y, "k": kind, "dmg": damage, "slot": slot, "life": 1.6, "pierce": false, "hits": [], "ph": 0.0, "t": 0.0, "bounce": 0}
	shots.append(shot)
	return shot

func _step_shots(delta: float) -> void:
	for index in range(shots.size() - 1, -1, -1):
		var shot := shots[index]
		var kind: String = shot["k"]
		var before := Vector2(float(shot["x"]), float(shot["y"]))
		shot["t"] = float(shot["t"]) + delta
		shot["life"] = float(shot["life"]) - delta
		if kind == "limpet":
			shot["vy"] = float(shot["vy"]) + 420.0 * delta
		var velocity := Vector2(float(shot["vx"]), float(shot["vy"]))
		shot["bx"] = float(shot["bx"]) + velocity.x * delta
		shot["by"] = float(shot["by"]) + velocity.y * delta
		var at := Vector2(float(shot["bx"]), float(shot["by"]))
		if kind == "arc":
			at += Vector2(-velocity.y, velocity.x).normalized() * sin(float(shot["t"]) * 18.0) * 9.0 * float(shot["ph"])
		var spent := float(shot["life"]) <= 0.0
		var blocked := world.solid_at(at.x, at.y) or (kind == "limpet" and velocity.y > 0.0 and world.landing(at.x - 1.0, at.x + 1.0, before.y, at.y, false) < INF)
		var outside := not in_view(at.x, at.y, 10.0)
		if (blocked or outside) and kind == "disc" and int(shot["bounce"]) > 0:
			# The skipper disc turns back off walls and off the edges of the view.
			var flip_x := world.solid_at(at.x, before.y) or at.x < cam.x - 10.0 or at.x > cam.x + VIEW.x + 10.0
			var flip_y := world.solid_at(before.x, at.y) or at.y < cam.y - 10.0 or at.y > cam.y + VIEW.y + 10.0
			if not flip_x and not flip_y:
				flip_x = true
				flip_y = true
			if flip_x:
				shot["vx"] = -velocity.x
			if flip_y:
				shot["vy"] = -velocity.y
			shot["bounce"] = int(shot["bounce"]) - 1
			shot["bx"] = before.x
			shot["by"] = before.y
			at = before
			sfx("clang")
		elif blocked:
			spent = true
			_burst(before.x, before.y, 3, "5", 60.0)
		elif outside:
			shots.remove_at(index)
			continue
		shot["x"] = at.x
		shot["y"] = at.y
		if not spent:
			spent = _shot_strikes(shot, at)
		if spent:
			if kind == "limpet":
				_explode(shot, at)
			shots.remove_at(index)

## Test a diver's shot against the machines and the boss. Returns true when the shot is used up.
func _shot_strikes(shot: Dictionary, at: Vector2) -> bool:
	var slot: int = shot["slot"]
	var hits: Array = shot["hits"]
	for foe in foes:
		if not Foes.exposed(foe) or not Foes.box(foe).grow(3.0).has_point(at) or hits.has(foe["id"]):
			continue
		if shot["k"] == "limpet":
			return true
		Foes.hurt(self, foe, int(shot["dmg"]), slot)
		_burst(at.x, at.y, 4, "f", 80.0)
		if not shot["pierce"]:
			return true
		hits.append(foe["id"])
	if boss.is_empty():
		return false
	if shot["k"] == "limpet":
		# The charge only has to touch: _explode deals its damage.
		return Bosses.hit(self, boss, at, 3.0, 0, slot) != Bosses.MISS
	var result := Bosses.hit(self, boss, at, 3.0, int(shot["dmg"]), slot)
	if result == Bosses.HURT:
		_burst(at.x, at.y, 5, "f", 90.0)
	elif result == Bosses.DEFLECTED:
		_burst(at.x, at.y, 3, "j", 70.0)
		sfx("clang")
	return result != Bosses.MISS

## A limpet charge goes off: everything close takes its damage.
func _explode(shot: Dictionary, at: Vector2) -> void:
	boom(at.x, at.y, 26.0)
	sfx("boom_small")
	shake(2.0)
	var slot: int = shot["slot"]
	for foe in foes:
		if Foes.exposed(foe) and Foes.box(foe).grow(26.0).has_point(at):
			Foes.hurt(self, foe, int(shot["dmg"]), slot)
	if not boss.is_empty():
		Bosses.hit(self, boss, at, 22.0, int(shot["dmg"]), slot)

func foe_shot(x: float, y: float, vx: float, vy: float, kind: String) -> void:
	foe_shots.append({"x": x, "y": y, "vx": vx, "vy": vy, "k": kind, "t": 0.0})

func clear_foe_shots() -> void:
	for shot in foe_shots:
		_burst(float(shot["x"]), float(shot["y"]), 2, "n", 40.0)
	foe_shots.clear()

func _step_foe_shots(delta: float) -> void:
	for index in range(foe_shots.size() - 1, -1, -1):
		var shot := foe_shots[index]
		var kind: String = shot["k"]
		var before_y: float = shot["y"]
		shot["t"] = float(shot["t"]) + delta
		if kind == "bomb":
			shot["vy"] = minf(260.0, float(shot["vy"]) + BOMB_GRAVITY * delta)
		shot["x"] = float(shot["x"]) + float(shot["vx"]) * delta
		shot["y"] = float(shot["y"]) + float(shot["vy"]) * delta
		var at := Vector2(float(shot["x"]), float(shot["y"]))
		var gone := not in_view(at.x, at.y, 40.0)
		if world.solid_at(at.x, at.y) or (kind == "bomb" and float(shot["vy"]) > 0.0 and world.landing(at.x - 1.0, at.x + 1.0, before_y, at.y, false) < INF):
			gone = true
			if kind == "bomb":
				boom(at.x, at.y - 2.0, 9.0)
				sfx("thud")
			else:
				_burst(at.x, at.y, 3, "n", 50.0)
		if not gone:
			for h in heroes:
				if h["active"] and h["alive"] and Heroes.box(h).grow(1.5).has_point(at):
					gone = float(h["inv"]) <= 0.0
					hit_hero(h)
					break
		if gone:
			foe_shots.remove_at(index)

# ---- canisters ----

func drop_item(x: float, y: float, kind: int) -> void:
	if kind <= 0:
		return
	items.append({"x": x, "y": y, "vy": -80.0, "k": kind, "t": ITEM_LIFE, "ground": false})

func _step_items(delta: float) -> void:
	for index in range(items.size() - 1, -1, -1):
		var item := items[index]
		item["t"] = float(item["t"]) - delta
		if not item["ground"]:
			var vy := minf(200.0, float(item["vy"]) + 300.0 * delta)
			var y: float = item["y"]
			var next_y := y + vy * delta
			var top := world.landing(float(item["x"]) - 5.0, float(item["x"]) + 5.0, y, next_y, false) if vy > 0.0 else INF
			if top < INF:
				item["y"] = top
				item["ground"] = true
			else:
				item["y"] = next_y
			item["vy"] = vy
		var gone := float(item["t"]) <= 0.0
		if float(item["y"]) > water_line() + 2.0:
			splash(float(item["x"]), water_line())
			gone = true
		var area := Rect2(float(item["x"]) - 7.0, float(item["y"]) - 13.0, 14.0, 13.0)
		for h in heroes:
			if gone or not (h["active"] and h["alive"]) or not area.intersects(Heroes.box(h)):
				continue
			_take(h, int(item["k"]))
			gone = true
		if gone:
			items.remove_at(index)

func _take(h: Dictionary, kind: int) -> void:
	if kind == SHIELD:
		h["shield"] = true
	else:
		h["weapon"] = kind
		weapons_seen |= 1 << kind
	add_score(int(h["slot"]), 300)
	sfx("pickup")
	_label(float(h["x"]), float(h["y"]) - 30.0, "w%d" % kind)

func weapons_tried() -> int:
	var count := 0
	for kind in range(1, WEAPONS):
		if weapons_seen & (1 << kind) != 0:
			count += 1
	return count

## A machine that touches a diver costs a life.
func _step_contacts() -> void:
	for h in heroes:
		if not (h["active"] and h["alive"]):
			continue
		var body := Heroes.box(h)
		for foe in foes:
			if Foes.exposed(foe) and not Foes.PASSIVE.has(foe["k"]) and Foes.box(foe).grow(-1.0).intersects(body):
				hit_hero(h)
				break

func boss_live() -> bool:
	return boss_started

# ---- sound and effects ----

func sfx(sound: String) -> void:
	audio.play(sound)

func say(key: String, seconds: float) -> void:
	banner = key
	banner_t = seconds

func shake(power: float) -> void:
	shake_power = maxf(shake_power, power)

func _label(x: float, y: float, key: String) -> void:
	labels.append({"x": x, "y": y, "t": 1.4, "key": key})

func _burst(x: float, y: float, count: int, colour: String, speed: float) -> void:
	for index in count:
		var dir := Vector2.from_angle(fx_rng.float_range(0.0, TAU)) * fx_rng.float_range(0.3, 1.0) * speed
		sparks.append({"x": x, "y": y, "vx": dir.x, "vy": dir.y, "t": fx_rng.float_range(0.15, 0.45), "c": colour, "g": 200.0})

func boom(x: float, y: float, radius: float) -> void:
	blasts.append({"x": x, "y": y, "r": radius, "t": 0.0, "life": 0.32})
	_burst(x, y, int(radius * 0.6), "e", radius * 7.0)
	_burst(x, y, int(radius * 0.3), "h", radius * 4.0)

func dust(x: float, y: float) -> void:
	for index in 4:
		sparks.append({"x": x + fx_rng.float_range(-4.0, 4.0), "y": y - 1.0, "vx": fx_rng.float_range(-30.0, 30.0), "vy": fx_rng.float_range(-30.0, -8.0), "t": 0.3, "c": "j", "g": 60.0})

func splash(x: float, y: float) -> void:
	for index in 9:
		sparks.append({"x": x + fx_rng.float_range(-5.0, 5.0), "y": y, "vx": fx_rng.float_range(-50.0, 50.0), "vy": fx_rng.float_range(-150.0, -60.0), "t": fx_rng.float_range(0.3, 0.6), "c": "4" if index % 2 == 0 else "5", "g": 420.0})

func bubble(x: float, y: float) -> void:
	sparks.append({"x": x, "y": y, "vx": fx_rng.float_range(-6.0, 6.0), "vy": -26.0, "t": 0.5, "c": "5", "g": 0.0})

func _step_fx(delta: float) -> void:
	for index in range(sparks.size() - 1, -1, -1):
		var spark := sparks[index]
		spark["t"] = float(spark["t"]) - delta
		if float(spark["t"]) <= 0.0:
			sparks.remove_at(index)
			continue
		spark["vy"] = float(spark["vy"]) + float(spark["g"]) * delta
		spark["x"] = float(spark["x"]) + float(spark["vx"]) * delta
		spark["y"] = float(spark["y"]) + float(spark["vy"]) * delta
	for index in range(blasts.size() - 1, -1, -1):
		blasts[index]["t"] = float(blasts[index]["t"]) + delta
		if float(blasts[index]["t"]) >= float(blasts[index]["life"]):
			blasts.remove_at(index)
	for index in range(labels.size() - 1, -1, -1):
		labels[index]["t"] = float(labels[index]["t"]) - delta
		labels[index]["y"] = float(labels[index]["y"]) - 14.0 * delta
		if float(labels[index]["t"]) <= 0.0:
			labels.remove_at(index)

# ---- contract ----

## A first join starts with full lives. A diver who left and comes back keeps the score and the lives they left with, so leaving is not a way to refill; with none left they wait for the next stage or continue like anyone else who is out.
func _game_player_joined(slot: int) -> void:
	var h := heroes[slot]
	h["active"] = true
	if not h["seen"]:
		h["seen"] = true
		h["lives"] = start_lives
	if int(h["lives"]) > 0:
		respawn(h)

func _game_player_left(slot: int) -> void:
	var h := heroes[slot]
	h["active"] = false
	h["alive"] = false
	h["out"] = true

func _game_snapshot() -> Dictionary:
	var players: Array = []
	for slot in MAX_PLAYERS:
		if slot < heroes.size():
			var h := heroes[slot]
			players.append({"score": h["score"], "lives": maxi(0, int(h["lives"])), "max_lives": maxi(start_lives, int(h["lives"])), "weapon": h["weapon"], "shield": h["shield"], "alive": h["alive"], "x": h["x"], "y": h["y"], "prone": h["prone"], "ground": h["ground"]})
		else:
			players.append({"score": 0, "lives": 0, "max_lives": start_lives, "weapon": 0, "shield": false, "alive": false, "x": 0.0, "y": 0.0, "prone": false, "ground": false})
	var out := {
		"stage": stage_index + 1, "stages_total": Levels.STAGE_COUNT, "continues": continues, "continues_used": continues_used, "deaths": deaths, "kills": kills,
		"bosses_down": bosses_down, "weapons_tried": weapons_tried(), "difficulty": difficulty, "players": players, "camera_x": cam.x, "camera_y": cam.y, "water_y": water_y,
		"foes": foes.size(), "shots": shots.size(), "foe_shots": foe_shots.size(), "items": items.size(), "boss_active": not boss.is_empty() and bool(boss["active"]), "stage_clear": mode == MODE_CLEAR,
	}
	if boss_started and not boss.is_empty() and not boss["dead"] and float(boss["dying"]) < 0.0:
		out["boss_hp"] = Bosses.hp(boss)
		out["boss_max_hp"] = Bosses.max_hp(boss)
	return out

func _game_frame(delta: float) -> void:
	if _gfx == null:
		_gfx = Gfx.new()
		_gfx.build()
		_view = View.new(_gfx)
	_view.frame(self, delta)
	_camera.position = (cam + _view.shake_offset(shake_power)).round()
	queue_redraw()

func _draw() -> void:
	if _view != null:
		_view.draw(self)
