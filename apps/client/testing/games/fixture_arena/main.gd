extends GameModule
## A single-screen arena: the run ends when every spark is cleared, and the achievements read fields of the result. Written from the contributor guide alone, as a check of the guide.

const SPEED := 150.0
const SHOT_SPEED := 420.0
const SPARK_SPEED := 40.0
const RADIUS := 8.0
const SPARK_RADIUS := 9.0
const MAX_HP := 3
const HURT_COOLDOWN := 1.0

var ship := Vector2.ZERO
var facing := Vector2.RIGHT
var hp := MAX_HP
var hurt_timer := 0.0
var shots: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var sparks_total := 0
var shots_fired := 0
var shots_hit := 0
var hits_taken := 0

func _game_start(config: Dictionary) -> void:
	ship = Vector2(stage_size) / 2.0
	sparks_total = int(config["options"].get("sparks", 8))
	for index in sparks_total:
		var angle := rng.float_range(0.0, TAU)
		var at := ship + Vector2.from_angle(angle) * rng.float_range(110.0, 160.0)
		sparks.append({"at": at, "dir": Vector2.from_angle(rng.float_range(0.0, TAU))})
	audio.define("shot", {"wave": "pulse", "freq": 880, "freq_end": 440, "duration": 0.08, "volume": 0.4})
	audio.define("pop", {"wave": "noise", "freq": 400, "duration": 0.12})
	audio.play_music({"bpm": 120, "voices": [{"wave": "triangle", "volume": 0.3, "notes": [["C3", 1], ["G3", 1], ["Eb3", 1], ["G3", 1]]}]})

func _game_step(delta: float) -> void:
	var pad := input(0)
	if pad.move.length() > 0.2:
		facing = pad.move.normalized()
	ship += pad.move * SPEED * delta
	ship = ship.clamp(Vector2(RADIUS, RADIUS), Vector2(stage_size) - Vector2(RADIUS, RADIUS))
	if pad.just_pressed(GameInput.A):
		shots.append({"at": ship, "dir": facing})
		shots_fired += 1
		audio.play("shot")
	hurt_timer = maxf(0.0, hurt_timer - delta)
	var bounds := Rect2(Vector2.ZERO, Vector2(stage_size))
	for spark in sparks:
		var at: Vector2 = spark["at"] + spark["dir"] * SPARK_SPEED * delta
		var dir: Vector2 = spark["dir"]
		if at.x < SPARK_RADIUS or at.x > stage_size.x - SPARK_RADIUS:
			dir.x = -dir.x
		if at.y < SPARK_RADIUS or at.y > stage_size.y - SPARK_RADIUS:
			dir.y = -dir.y
		spark["at"] = at.clamp(Vector2(SPARK_RADIUS, SPARK_RADIUS), Vector2(stage_size) - Vector2(SPARK_RADIUS, SPARK_RADIUS))
		spark["dir"] = dir
		if hurt_timer <= 0.0 and at.distance_to(ship) < RADIUS + SPARK_RADIUS:
			hp -= 1
			hits_taken += 1
			hurt_timer = HURT_COOLDOWN
	for shot_index in range(shots.size() - 1, -1, -1):
		var shot := shots[shot_index]
		shot["at"] = shot["at"] + shot["dir"] * SHOT_SPEED * delta
		var gone := not bounds.has_point(shot["at"])
		for spark_index in range(sparks.size() - 1, -1, -1):
			if (sparks[spark_index]["at"] as Vector2).distance_to(shot["at"]) < SPARK_RADIUS + 3.0:
				sparks.remove_at(spark_index)
				shots_hit += 1
				score += 50
				audio.play("pop")
				gone = true
				break
		if gone:
			shots.remove_at(shot_index)
	var extra := {"shots_fired": shots_fired, "shots_hit": shots_hit, "accuracy": _accuracy(), "hits_taken": hits_taken}
	if sparks.is_empty():
		finish(OUTCOME_CLEARED, extra)
	elif hp <= 0:
		finish(OUTCOME_DEFEATED, extra)

func _accuracy() -> int:
	return 0 if shots_fired == 0 else int(round(100.0 * shots_hit / shots_fired))

func _game_snapshot() -> Dictionary:
	var spark_positions: Array = []
	for spark in sparks:
		spark_positions.append(spark["at"])
	return {"hp": hp, "max_hp": MAX_HP, "sparks_left": sparks.size(), "sparks_total": sparks_total, "ship": ship, "spark_positions": spark_positions, "players": [{"score": score, "hp": hp, "max_hp": MAX_HP}]}

func _game_frame(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(stage_size)), Color("12060e"))
	draw_arc(Vector2(stage_size) / 2.0, 150.0, 0.0, TAU, 96, Color("3a1028"), 2.0, true)
	for spark in sparks:
		draw_circle(spark["at"], SPARK_RADIUS, Color("e85890"))
	for shot in shots:
		draw_circle(shot["at"], 3.0, Color.WHITE)
	var blink := hurt_timer > 0.0 and int(hurt_timer * 10.0) % 2 == 0
	draw_circle(ship, RADIUS, Color("70e0c0", 0.4 if blink else 1.0))
	draw_line(ship, ship + facing * 14.0, Color.WHITE, 2.0, true)
