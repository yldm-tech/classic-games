extends GameModule

## The fixture module: the smallest game that uses every part of the module contract, so the tests can exercise the contract without depending on a shipped game. Two squares walk a level twice as wide as the stage (a camera follows them), hit a boss, lose lives, collect coins placed by the seeded RNG, against a countdown. It is not in the shipped catalog; tests point the catalog at this directory's parent.

const LEVEL_WIDTH := 960.0
const SPEED := 60.0
const START_LIVES := 3
const BOSS_HP := 5
const COINS := 3
const COLORS := [Color("5AB4FF"), Color("FFB454")]

var duration := 30.0
var time_left := 30.0
var boss_hp := BOSS_HP
var coins: Array[Vector2] = []
var collected := 0
var deaths := 0
var positions: Array[Vector2] = [Vector2(40, 200), Vector2(80, 200)]
var lives: Array[int] = [START_LIVES, START_LIVES]
var hits: Array[int] = [0, 0]
var scores: Array[int] = [0, 0]
## Journal of contract callbacks, read by the tests.
var events: Array[String] = []

var _camera: Camera2D

func _game_start(config: Dictionary) -> void:
	duration = float((config["options"] as Dictionary).get("duration", 30))
	time_left = duration
	boss_hp = BOSS_HP
	collected = 0
	deaths = 0
	positions = [Vector2(40, 200), Vector2(80, 200)]
	lives = [START_LIVES, START_LIVES]
	hits = [0, 0]
	scores = [0, 0]
	coins.clear()
	for index in COINS:
		coins.append(Vector2(rng.float_range(120.0, LEVEL_WIDTH - 40.0), 200.0))
	_camera = Camera2D.new()
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(_camera)
	audio.define("hit", {"wave": "square", "freq": 660, "freq_end": 220, "duration": 0.08})
	audio.define("coin", {"wave": "triangle", "freq": 880, "freq_end": 1320, "duration": 0.1})
	audio.play_music({"bpm": 140, "voices": [{"wave": "pulse", "volume": 0.3, "notes": [["C4", 1], ["E4", 1], ["G4", 1], ["-", 1]]}]})
	events.append("start:%d" % int(config["players"]))

func _game_step(delta: float) -> void:
	for slot in active_players():
		if lives[slot] <= 0:
			continue
		var pad := input(slot)
		positions[slot] += pad.move * SPEED * delta
		positions[slot].x = clampf(positions[slot].x, 8.0, LEVEL_WIDTH - 8.0)
		positions[slot].y = clampf(positions[slot].y, 8.0, float(stage_size.y) - 8.0)
		if pad.just_pressed(GameInput.A):
			boss_hp -= 1
			hits[slot] += 1
			scores[slot] += 100
			score += 100
			audio.play("hit")
		if pad.just_pressed(GameInput.B):
			lives[slot] -= 1
			deaths += 1
		for index in range(coins.size() - 1, -1, -1):
			if positions[slot].distance_to(coins[index]) < 10.0:
				coins.remove_at(index)
				collected += 1
				scores[slot] += 10
				score += 10
				audio.play("coin")
	time_left = maxf(0.0, time_left - delta)
	_follow()
	if boss_hp <= 0:
		finish(OUTCOME_CLEARED)
	elif _everyone_out():
		finish(OUTCOME_DEFEATED)
	elif time_left <= 0.0:
		finish(OUTCOME_TIMED_OUT)

func _everyone_out() -> bool:
	for slot in active_players():
		if lives[slot] > 0:
			return false
	return true

## The camera keeps the first living player in view; the level is twice as wide as the stage. It moves in the step, not in the frame, so where it is belongs to the simulation and a test can read it.
func _follow() -> void:
	var focus := positions[0]
	for slot in active_players():
		if lives[slot] > 0:
			focus = positions[slot]
			break
	_camera.position.x = clampf(focus.x - float(stage_size.x) / 2.0, 0.0, LEVEL_WIDTH - float(stage_size.x))

func _game_frame(_delta: float) -> void:
	queue_redraw()

func _game_snapshot() -> Dictionary:
	var players: Array = []
	for slot in MAX_PLAYERS:
		players.append({"score": scores[slot], "lives": lives[slot], "max_lives": START_LIVES, "hits": hits[slot], "x": positions[slot].x, "y": positions[slot].y})
	var out := {"time_left": time_left, "duration": duration, "coins": collected, "coins_total": COINS, "deaths": deaths, "players": players, "camera_x": _camera.position.x if _camera != null else 0.0}
	if boss_hp > 0:
		out["boss_hp"] = boss_hp
		out["boss_max_hp"] = BOSS_HP
	return out

func _game_player_joined(slot: int) -> void:
	positions[slot] = Vector2(40.0 + 40.0 * slot, 200.0)
	lives[slot] = START_LIVES
	events.append("joined:%d" % slot)

func _game_player_left(slot: int) -> void:
	events.append("left:%d" % slot)

func _game_paused(paused: bool) -> void:
	events.append("paused" if paused else "resumed")

func _draw() -> void:
	draw_rect(Rect2(0, 0, LEVEL_WIDTH, stage_size.y), Color("0B0A1A"))
	for column in int(LEVEL_WIDTH / 16.0):
		if column % 2 == 0:
			draw_rect(Rect2(column * 16.0, 216.0, 16.0, 54.0), Color("2A2466"))
	for coin in coins:
		draw_rect(Rect2(coin - Vector2(3, 3), Vector2(6, 6)), Color("FFD166"))
	if boss_hp > 0:
		draw_rect(Rect2(LEVEL_WIDTH - 64.0, 152.0, 40.0, 56.0), Color("FF6B7A"))
	for slot in active_players():
		if lives[slot] > 0:
			draw_rect(Rect2(positions[slot] - Vector2(8, 8), Vector2(16, 16)), COLORS[slot])
