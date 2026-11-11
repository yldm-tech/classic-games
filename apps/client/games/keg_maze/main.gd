extends GameModule

## Keg Burrow: one or two mole diggers blast their way down nine levels of a mine. They set powder kegs that go off in a cross, break blocks to find gear and the lift hatch, clear out the creatures and ride the lift down before the air runs out. This script is the simulation; view.gd draws it, foes.gd moves the creatures, levels.gd builds the fields.

const Levels := preload("res://games/keg_maze/levels.gd")
const Actors := preload("res://games/keg_maze/actors.gd")
const Foes := preload("res://games/keg_maze/foes.gd")
const Sounds := preload("res://games/keg_maze/sounds.gd")
const View := preload("res://games/keg_maze/view.gd")

const DIR_CONTROLS: Array[StringName] = [GameInput.UP, GameInput.RIGHT, GameInput.DOWN, GameInput.LEFT]
const LIVES := [5, 3, 2]
const CONTINUES := [3, 2, 1]
const HERO_SPEED := 4.0
const BOOT_SPEED := 0.55
const MAX_CAP := 6
const MAX_BLAST := 7
const MAX_BOOTS := 3
const BASE_BLAST := 2
const FUSE := 2.4
## A keg wired to a detonator waits this long before it goes off by itself.
const REMOTE_FUSE := 8.0
## A keg reached by a blast goes off this much later, so that a chain runs visibly along the kegs.
const CHAIN_DELAY := 0.12
const FLAME_TIME := 0.5
const BURN_TIME := 0.45
const IMPACT_TIME := 0.3
const DEAD_TIME := 1.4
const RESPAWN_INVULN := 2.5
const START_INVULN := 1.0
const DAZE_REACH := 4
const DAZE_TIME := 3.0
const SHIELD_INVULN := 1.5
const INTRO_TIME := 2.0
const CLEAR_TIME := 2.8
const FINAL_CLEAR_TIME := 4.5
const CONTINUE_TIME := 2.6
const DEFEAT_TIME := 2.6
## The clock restarts at this many seconds after the air ran out and cost a life.
const OVERTIME := 45.0
const TOUCH := 0.62
const BOSS_TOUCH := 1.15
const FX_LIMIT := 240

var difficulty := 1
var max_lives := 3
var stage := 0
## Counts every field that was built, so the view knows when to redraw its backdrop.
var stage_serial := 0
var phase: int = Levels.Phase.INTRO
var phase_time := 0.0
var stage_time := 180.0
var time_left := 180.0
var grid := PackedInt32Array()
## What the blocks hide: cell index -> item name, or "exit".
var buried: Dictionary = {}
## Items lying on the floor: cell index -> item name.
var items: Dictionary = {}
var exit_cell := Vector2i(-1, -1)
var exit_visible := false
var exit_open := false
var starts: Array[Vector2i] = [Vector2i(1, 1), Vector2i(17, 13)]
var heroes: Array = []
var foes: Array = []
var kegs: Array = []
## Cells on fire: cell index -> Actors.Flame.
var flames: Dictionary = {}
## Blocks burning away: cell index -> seconds left.
var burning: Dictionary = {}
## Rocks on their way down: { cell, ttl, total }.
var hazards: Array = []
## Cells a rock has just hit: cell index -> seconds left.
var impacts: Dictionary = {}
var chain_serial := 0
var chain_size: Dictionary = {}
var chain_kills: Dictionary = {}
## Events for the view (bursts, shakes, floating scores). The simulation only writes them.
var fx: Array = []

var continues_left := 2
var continues_used := 0
var deaths := 0
var blast_deaths := 0
## Lives lost by cause ("blast", "foe", "rock", "time"), for tests and tuning.
var causes: Dictionary = {}
var best_chain := 0
var best_streak := 0
var kills := 0
var gems := 0
var crates_broken := 0
var pickups := 0
var bosses_beaten := 0
var stages_cleared := 0
## The time bonus paid for the level just cleared, for the banner.
var clear_bonus := 0
var _jingle: Array = []
var _view: Node2D

func _game_start(config: Dictionary) -> void:
	var chosen: Dictionary = config["options"]
	difficulty = clampi(int(chosen.get("difficulty", 1)), 0, 2)
	max_lives = int(LIVES[difficulty])
	continues_left = int(CONTINUES[difficulty])
	continues_used = 0
	deaths = 0
	blast_deaths = 0
	causes.clear()
	best_chain = 0
	best_streak = 0
	kills = 0
	gems = 0
	crates_broken = 0
	pickups = 0
	bosses_beaten = 0
	stages_cleared = 0
	stage_serial = 0
	fx.clear()
	_jingle.clear()
	heroes.clear()
	for slot in MAX_PLAYERS:
		var hero := Actors.Hero.new()
		hero.lives = max_lives
		heroes.append(hero)
	Sounds.define(audio)
	if _view == null:
		_view = View.new()
		_view.name = "View"
		add_child(_view)
	_view.call("attach", self)
	# "start_stage" is not in the manifest: the game menu never offers it. Tests use it to begin on a later level.
	_load_stage(clampi(int(chosen.get("start_stage", 1)), 1, Levels.STAGE_COUNT) - 1)

func _load_stage(index: int) -> void:
	stage = index
	stage_serial += 1
	var built := Levels.build(index, rng, difficulty)
	grid = built["grid"]
	buried = built["buried"]
	starts = built["starts"]
	exit_cell = built["exit"]
	exit_visible = built["exit_visible"]
	exit_open = false
	stage_time = built["time"]
	time_left = stage_time
	items.clear()
	kegs.clear()
	flames.clear()
	burning.clear()
	hazards.clear()
	impacts.clear()
	chain_size.clear()
	chain_kills.clear()
	foes.clear()
	for entry: Array in built["foes"]:
		foes.append(Foes.make(str(entry[0]), entry[1], index, difficulty, maxi(0, int(built["boss"]))))
	for slot in MAX_PLAYERS:
		var hero: Actors.Hero = heroes[slot]
		if not is_player_active(slot):
			continue
		# A digger who ran out of lives is hauled back up for the next level with a single life.
		if hero.out:
			hero.out = false
			hero.lives = 1
		_place(slot, START_INVULN)
	phase = Levels.Phase.INTRO
	phase_time = INTRO_TIME
	audio.play_music(Sounds.music(index))
	emit_fx("stage", Vector2i.ZERO)

func _place(slot: int, invuln: float = RESPAWN_INVULN) -> void:
	var hero: Actors.Hero = heroes[slot]
	hero.cell = starts[slot]
	hero.dir = Vector2i.ZERO
	hero.t = 0.0
	hero.face = Vector2i(0, 1)
	hero.pref = Vector2i.ZERO
	hero.dead = 0.0
	hero.invuln = invuln
	hero.act = 0.0

## The cage that brings a digger back down rattles the creatures near the start corner: they stand dazed and harmless for a moment, so that nobody loses a second life to one that was waiting there.
func _daze(around: Vector2i) -> void:
	for foe: Actors.Foe in foes:
		var spot := foe.spot()
		if foe.kind != "boss" and foe.dying <= 0.0 and absi(spot.x - around.x) + absi(spot.y - around.y) <= DAZE_REACH:
			foe.rest = maxf(foe.rest, DAZE_TIME)
			foe.charge = false
			emit_fx("daze", spot)

# ---- step ----

func _game_step(delta: float) -> void:
	_play_jingle(delta)
	match phase:
		Levels.Phase.INTRO:
			phase_time -= delta
			if phase_time <= 0.0:
				phase = Levels.Phase.PLAY
				audio.play("go")
		Levels.Phase.PLAY:
			_step_play(delta)
		Levels.Phase.CLEAR:
			_step_fire(delta)
			phase_time -= delta
			if phase_time <= 0.0:
				if stage >= Levels.STAGE_COUNT - 1:
					finish(OUTCOME_CLEARED)
				else:
					_load_stage(stage + 1)
		Levels.Phase.CONTINUE:
			_step_fire(delta)
			phase_time -= delta
			if phase_time <= 0.0:
				continues_left -= 1
				continues_used += 1
				for slot in active_players():
					var hero: Actors.Hero = heroes[slot]
					hero.out = false
					hero.lives = max_lives
				_load_stage(stage)
		Levels.Phase.DEFEAT:
			_step_fire(delta)
			phase_time -= delta
			if phase_time <= 0.0:
				finish(OUTCOME_DEFEATED)
	if fx.size() > FX_LIMIT:
		fx.clear()

func _step_play(delta: float) -> void:
	var before := ceili(time_left)
	time_left -= delta
	if time_left <= 0.0:
		_air_out()
	elif time_left <= 30.0 and ceili(time_left) != before:
		audio.play("tick", 1.0 if time_left > 10.0 else 1.3)
	for slot in active_players():
		_step_hero(slot, delta)
	Foes.step(self, delta)
	_step_kegs(delta)
	_step_fire(delta)
	_step_hazards(delta)
	_resolve_hits()
	if phase != Levels.Phase.PLAY:
		return
	if not exit_open and foes_left() == 0:
		exit_open = true
		audio.play("exit_open")
		emit_fx("exit_open", exit_cell)
	_check_exit()
	if phase == Levels.Phase.PLAY:
		_check_defeat()

func _step_hero(slot: int, delta: float) -> void:
	var hero: Actors.Hero = heroes[slot]
	if hero.out:
		return
	if hero.dead > 0.0:
		hero.dead -= delta
		if hero.dead <= 0.0:
			if hero.lives > 0:
				_place(slot)
				_daze(starts[slot])
				audio.play("respawn")
				emit_fx("join", starts[slot], slot)
			else:
				hero.out = true
		return
	hero.invuln = maxf(0.0, hero.invuln - delta)
	hero.act = maxf(0.0, hero.act - delta)
	var pad := input(slot)
	var held: Array[Vector2i] = []
	for d in 4:
		if pad.just_pressed(DIR_CONTROLS[d]):
			hero.pref = Levels.DIRS[d]
		if pad.is_down(DIR_CONTROLS[d]):
			held.append(Levels.DIRS[d])
	var want := Vector2i.ZERO
	if held.has(hero.pref):
		want = hero.pref
	elif not held.is_empty():
		want = held[0]
	if hero.dir == Vector2i.ZERO:
		if want != Vector2i.ZERO:
			hero.face = want
			if can_walk(hero.cell + want):
				hero.dir = want
				hero.t = 0.0
			else:
				# The direction pressed last is blocked: any other one that is held may go instead.
				for dir in held:
					if dir != want and can_walk(hero.cell + dir):
						hero.dir = dir
						hero.face = dir
						hero.t = 0.0
						break
	elif want == -hero.dir:
		hero.cell += hero.dir
		hero.dir = want
		hero.face = want
		hero.t = 1.0 - hero.t
	if hero.dir != Vector2i.ZERO:
		hero.t += (HERO_SPEED + BOOT_SPEED * float(hero.boots)) * delta
		hero.walk += delta
		if hero.t >= 1.0:
			hero.cell += hero.dir
			var left := hero.t - 1.0
			var next := Vector2i.ZERO
			if want != Vector2i.ZERO and can_walk(hero.cell + want):
				next = want
			else:
				# Holding two directions slides round a corner: the one that is blocked waits for the other.
				for dir in held:
					if dir != want and dir != -hero.dir and can_walk(hero.cell + dir):
						next = dir
						break
			hero.dir = next
			hero.t = left if next != Vector2i.ZERO else 0.0
			if next != Vector2i.ZERO:
				hero.face = next
			elif want != Vector2i.ZERO:
				hero.face = want
	else:
		hero.walk = 0.0
	var spot := hero.spot()
	var at := Levels.index(spot)
	if items.has(at):
		_collect(slot, at)
	if pad.just_pressed(GameInput.A):
		_set_keg(slot)
	if pad.just_pressed(GameInput.B) and hero.remote:
		_detonate(slot)

## Whether a digger may step into a cell: open floor without a keg on it.
func can_walk(cell: Vector2i) -> bool:
	return Levels.inside(cell) and grid[Levels.index(cell)] == Levels.FLOOR and keg_at(cell) == null

func keg_at(cell: Vector2i) -> Actors.Keg:
	for keg: Actors.Keg in kegs:
		if keg.cell == cell:
			return keg
	return null

func _kegs_of(slot: int) -> int:
	var count := 0
	for keg: Actors.Keg in kegs:
		if keg.owner == slot:
			count += 1
	return count

func _set_keg(slot: int) -> void:
	var hero: Actors.Hero = heroes[slot]
	var cell := hero.spot()
	if _kegs_of(slot) >= hero.cap or keg_at(cell) != null or grid[Levels.index(cell)] != Levels.FLOOR:
		audio.play("deny")
		return
	var keg := Actors.Keg.new()
	keg.cell = cell
	keg.owner = slot
	keg.blast = hero.blast
	keg.remote = hero.remote
	keg.fuse = REMOTE_FUSE if hero.remote else FUSE
	kegs.append(keg)
	hero.act = 0.18
	audio.play("place")
	emit_fx("place", cell)

## Set off the oldest keg of a digger who carries a detonator.
func _detonate(slot: int) -> void:
	for keg: Actors.Keg in kegs:
		if keg.owner == slot and keg.fuse > 0.0:
			keg.fuse = 0.0
			audio.play("detonate")
			return

func _step_kegs(delta: float) -> void:
	for keg: Actors.Keg in kegs.duplicate():
		keg.age += delta
		keg.fuse -= delta
		if keg.fuse <= 0.0 and kegs.has(keg):
			_explode(keg)

func _explode(keg: Actors.Keg) -> void:
	kegs.erase(keg)
	if keg.chain == 0:
		chain_serial += 1
		keg.chain = chain_serial
	chain_size[keg.chain] = int(chain_size.get(keg.chain, 0)) + 1
	var links := int(chain_size[keg.chain])
	best_chain = maxi(best_chain, links)
	_add_flame(keg.cell, keg.owner, keg.chain, 0, -1)
	for d in 4:
		fire_line(keg.cell, d, keg.blast, keg.owner, keg.chain)
	audio.play("blast", 1.0 + 0.08 * float(mini(links, 6) - 1))
	audio.play("thump")
	if links >= 2:
		audio.play("chain", 1.0 + 0.12 * float(mini(links, 8) - 2))
	emit_fx("blast", keg.cell, links)

## Run fire from `from` (not included) for up to `reach` cells in direction index `d`. Rock stops it; a block stops it and starts to burn; a keg stops it and joins the chain.
func fire_line(from: Vector2i, d: int, reach: int, owner: int, chain: int) -> void:
	var last: Actors.Flame = null
	for step_index in range(1, reach + 1):
		var cell := from + Levels.DIRS[d] * step_index
		if not Levels.inside(cell):
			break
		var at := Levels.index(cell)
		var tile := grid[at]
		if tile == Levels.WALL or tile == Levels.BURNING:
			break
		if tile == Levels.CRATE:
			_burn(at, owner)
			break
		var other := keg_at(cell)
		if other != null:
			other.fuse = minf(other.fuse, CHAIN_DELAY)
			if other.chain == 0:
				other.chain = chain
			break
		last = _add_flame(cell, owner, chain, 2 - d % 2, -1)
	if last != null and last.axis != 0:
		last.tip = d

func _add_flame(cell: Vector2i, owner: int, chain: int, axis: int, tip: int) -> Actors.Flame:
	var at := Levels.index(cell)
	var flame: Actors.Flame = flames.get(at)
	if flame == null:
		flame = Actors.Flame.new()
		flame.axis = axis
		flame.tip = tip
		flame.owner = owner
		flame.chain = chain
		flames[at] = flame
	elif flame.axis != axis:
		# Two arms crossing look like the heart of a blast.
		flame.axis = 0
		flame.tip = -1
	else:
		flame.tip = -1
	flame.ttl = FLAME_TIME
	# A digger's fire takes over a cell that was only the boss's, so that it still harms the boss.
	if owner >= 0 or flame.owner < 0:
		flame.owner = owner
		flame.chain = chain
	return flame

func _burn(at: int, owner: int) -> void:
	grid[at] = Levels.BURNING
	burning[at] = BURN_TIME
	crates_broken += 1
	award(owner, 10, Vector2i(-1, -1))
	audio.play("crate")
	emit_fx("crate", Levels.cell_of(at))

func _step_fire(delta: float) -> void:
	for at: int in flames.keys():
		var flame: Actors.Flame = flames[at]
		flame.ttl -= delta
		if flame.ttl <= 0.0:
			flames.erase(at)
	for at: int in burning.keys():
		burning[at] = float(burning[at]) - delta
		if float(burning[at]) <= 0.0:
			burning.erase(at)
			grid[at] = Levels.FLOOR
			uncover(at)
	for at: int in impacts.keys():
		impacts[at] = float(impacts[at]) - delta
		if float(impacts[at]) <= 0.0:
			impacts.erase(at)

## A block is gone: whatever it hid comes into the open.
func uncover(at: int) -> void:
	if not buried.has(at):
		return
	var what := str(buried[at])
	buried.erase(at)
	if what == "exit":
		exit_visible = true
		audio.play("exit_found")
		emit_fx("exit_found", Levels.cell_of(at))
	else:
		items[at] = what
		emit_fx("reveal", Levels.cell_of(at))

func _step_hazards(delta: float) -> void:
	for hazard: Dictionary in hazards.duplicate():
		hazard["ttl"] = float(hazard["ttl"]) - delta
		if float(hazard["ttl"]) <= 0.0:
			hazards.erase(hazard)
			impacts[Levels.index(hazard["cell"])] = IMPACT_TIME
			audio.play("rock_fall")
			emit_fx("rock", hazard["cell"])

func _resolve_hits() -> void:
	for foe: Actors.Foe in foes:
		if foe.dying > 0.0:
			continue
		for cell in foe.cells():
			var flame: Actors.Flame = flames.get(Levels.index(cell))
			if flame != null and flame.owner >= 0:
				Foes.damage(self, foe, flame.owner, flame.chain)
				break
	for slot in active_players():
		var hero: Actors.Hero = heroes[slot]
		if not hero.in_field():
			continue
		var at := Levels.index(hero.spot())
		if flames.has(at):
			_hurt(slot, "blast")
			continue
		if impacts.has(at):
			_hurt(slot, "rock")
			continue
		var here := hero.pos()
		for foe: Actors.Foe in foes:
			if foe.dying > 0.0 or foe.rest > 0.0 and foe.kind != "boss":
				continue
			var gap := (foe.pos() + Vector2(0.5, 0.5) * float(foe.size - 1)) - here
			var reach := BOSS_TOUCH if foe.size > 1 else TOUCH
			if absf(gap.x) < reach and absf(gap.y) < reach:
				_hurt(slot, "foe")
				break

## A digger was hit. A hard hat takes the first hit; `force` (the air running out) ignores both it and the blinking after a respawn.
func _hurt(slot: int, cause: String, force: bool = false) -> void:
	var hero: Actors.Hero = heroes[slot]
	if not hero.in_field():
		return
	if not force:
		if hero.invuln > 0.0:
			return
		if hero.shield:
			hero.shield = false
			hero.invuln = SHIELD_INVULN
			audio.play("shield")
			emit_fx("shield", hero.spot(), slot)
			return
	hero.lives -= 1
	deaths += 1
	causes[cause] = int(causes.get(cause, 0)) + 1
	if cause == "blast":
		blast_deaths += 1
	hero.cell = hero.spot()
	hero.dir = Vector2i.ZERO
	hero.t = 0.0
	hero.dead = DEAD_TIME
	# Some gear is dropped on the way out: the detonator and one step of reach. Kegs and boots stay.
	hero.remote = false
	hero.shield = false
	hero.blast = maxi(BASE_BLAST, hero.blast - 1)
	audio.play("hurt" if hero.lives > 0 else "out")
	emit_fx("hurt", hero.cell, slot)

func _air_out() -> void:
	time_left = OVERTIME
	audio.play("timeup")
	emit_fx("timeup", Vector2i.ZERO)
	for slot in active_players():
		_hurt(slot, "time", true)

func _collect(slot: int, at: int) -> void:
	var hero: Actors.Hero = heroes[slot]
	var what := str(items[at])
	items.erase(at)
	pickups += 1
	var points := 50
	var sound := "power"
	match what:
		"keg":
			hero.cap = mini(MAX_CAP, hero.cap + 1)
		"blast":
			hero.blast = mini(MAX_BLAST, hero.blast + 1)
		"boots":
			hero.boots = mini(MAX_BOOTS, hero.boots + 1)
		"remote":
			hero.remote = true
		"hat":
			hero.shield = true
		"heart":
			sound = "heart"
			if hero.lives < max_lives:
				hero.lives += 1
			else:
				points = 1000
		"clock":
			sound = "heart"
			time_left = minf(time_left + 30.0, stage_time + 30.0)
		"gem":
			sound = "gem"
			gems += 1
			points = 500
	audio.play(sound)
	award(slot, points, Levels.cell_of(at))
	emit_fx("pickup", Levels.cell_of(at), what)

func _check_exit() -> void:
	if not exit_open or not exit_visible:
		return
	for slot in active_players():
		var hero: Actors.Hero = heroes[slot]
		if hero.in_field() and hero.spot() == exit_cell:
			_clear_stage(slot)
			return

func _clear_stage(slot: int) -> void:
	stages_cleared += 1
	var last := stage >= Levels.STAGE_COUNT - 1
	phase = Levels.Phase.CLEAR
	phase_time = FINAL_CLEAR_TIME if last else CLEAR_TIME
	clear_bonus = ceili(maxf(0.0, time_left)) * 10
	award(slot, clear_bonus, exit_cell)
	kegs.clear()
	hazards.clear()
	audio.stop_music()
	_jingle = Sounds.jingle("victory" if last else "clear")
	emit_fx("clear", exit_cell)

func _check_defeat() -> void:
	for slot in active_players():
		var hero: Actors.Hero = heroes[slot]
		if not hero.out:
			return
	audio.stop_music()
	if continues_left > 0:
		phase = Levels.Phase.CONTINUE
		phase_time = CONTINUE_TIME
		_jingle = Sounds.jingle("continue")
	else:
		phase = Levels.Phase.DEFEAT
		phase_time = DEFEAT_TIME
		_jingle = Sounds.jingle("defeat")

func _play_jingle(delta: float) -> void:
	for note: Array in _jingle.duplicate():
		note[0] = float(note[0]) - delta
		if float(note[0]) <= 0.0:
			audio.play(str(note[1]), float(note[2]))
			_jingle.erase(note)

# ---- shared with foes.gd and the view ----

## Points for a player; `cell` is where the floating number appears (off the field for none). A blast that belongs to nobody scores nothing.
func award(slot: int, points: int, cell: Vector2i) -> void:
	if slot < 0 or slot >= MAX_PLAYERS or points <= 0:
		return
	var hero: Actors.Hero = heroes[slot]
	hero.score += points
	var total := 0
	for each: Actors.Hero in heroes:
		total += each.score
	score = total
	if cell.x >= 0 and points >= 100:
		emit_fx("points", cell, points)

func emit_fx(kind: String, cell: Vector2i, extra: Variant = null) -> void:
	fx.append({"kind": kind, "cell": cell, "extra": extra})

func foes_left() -> int:
	var count := 0
	for foe: Actors.Foe in foes:
		if foe.dying <= 0.0:
			count += 1
	return count

func boss() -> Actors.Foe:
	for foe: Actors.Foe in foes:
		if foe.kind == "boss" and foe.dying <= 0.0:
			return foe
	return null

## Whether a digger who is on the field stands on this cell.
func hero_on(cell: Vector2i) -> bool:
	for slot in active_players():
		var hero: Actors.Hero = heroes[slot]
		if hero.in_field() and hero.spot() == cell:
			return true
	return false

## The cell of the digger nearest to `cell`, or (-1, -1) when nobody is on the field.
func nearest_hero(cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_steps := 9999
	for slot in active_players():
		var hero: Actors.Hero = heroes[slot]
		if not hero.in_field():
			continue
		var spot := hero.spot()
		var steps := absi(spot.x - cell.x) + absi(spot.y - cell.y)
		if steps < best_steps:
			best_steps = steps
			best = spot
	return best

# ---- contract ----

func _game_player_joined(slot: int) -> void:
	# A fresh digger with fresh gear; the points of an earlier visit stay on the board.
	var hero := Actors.Hero.new()
	hero.lives = max_lives
	hero.score = (heroes[slot] as Actors.Hero).score
	heroes[slot] = hero
	_place(slot)
	audio.play("respawn")
	emit_fx("join", starts[slot], slot)

func _game_player_left(slot: int) -> void:
	var hero: Actors.Hero = heroes[slot]
	hero.dir = Vector2i.ZERO
	hero.t = 0.0
	emit_fx("hurt", hero.cell, slot)

func _game_frame(delta: float) -> void:
	_view.call("frame", delta)

func _game_snapshot() -> Dictionary:
	var players: Array = []
	for slot in MAX_PLAYERS:
		if slot >= heroes.size():
			players.append({"score": 0, "lives": 0, "max_lives": max_lives})
			continue
		var hero: Actors.Hero = heroes[slot]
		var here := hero.pos()
		players.append({
			"score": hero.score, "lives": maxi(0, hero.lives), "max_lives": max_lives, "kegs": hero.cap, "blast": hero.blast, "boots": hero.boots,
			"remote": hero.remote, "shield": hero.shield, "out": hero.out, "x": here.x, "y": here.y,
		})
	var out := {
		"time_left": maxf(0.0, time_left), "stage": stage + 1, "stages": Levels.STAGE_COUNT, "foes": foes_left(), "phase": phase,
		"kegs_live": kegs.size(), "flames": flames.size(), "exit_open": exit_open, "exit_visible": exit_visible,
		"deaths": deaths, "blast_deaths": blast_deaths, "best_chain": best_chain, "best_streak": best_streak, "kills": kills, "gems": gems, "crates": crates_broken, "pickups": pickups,
		"continues_left": continues_left, "continues_used": continues_used, "bosses_beaten": bosses_beaten, "stages_cleared": stages_cleared, "players": players,
	}
	var chief := boss()
	if chief != null:
		out["boss_hp"] = chief.hp
		out["boss_max_hp"] = chief.max_hp
	return out
