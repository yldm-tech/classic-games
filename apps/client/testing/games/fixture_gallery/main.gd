extends GameModule
## A walk along a lamp-lit lane, drawn with high-resolution art and scored with recorded audio: the fixture for everything fixture_duo and fixture_arena do not touch. A sprite atlas with a frame table and an animation, a tiled texture, smooth text, a looping music file, a stinger that ducks it, a sound effect from a file and effects from the preset library.

const SPEED := 120.0
const JUMP_SPEED := 260.0
const GRAVITY := 720.0
const GROUND := 300.0
const REACH := 26.0
const TIME_LIMIT := 60.0
const CLEAR_DELAY := 1.0

var sprites: GameSprites
var floor_tile: GameSprites
var text: GameText

var keeper := Vector2.ZERO
var lift := 0.0
var facing_left := false
var walking := false
var lamps: Array[Dictionary] = []
var lit := 0
var time_left := TIME_LIMIT
var clear_timer := -1.0

func _game_start(config: Dictionary) -> void:
	sprites = GameSprites.load_atlas("res://testing/games/fixture_gallery/art/keeper.json")
	floor_tile = GameSprites.load_image("res://testing/games/fixture_gallery/art/cobble.jpg", {"height": 64})
	text = GameText.new()
	keeper = Vector2(60.0, GROUND)
	lift = 0.0
	facing_left = false
	walking = false
	lamps.clear()
	lit = 0
	time_left = TIME_LIMIT
	clear_timer = -1.0
	var count := int(config["options"].get("lamps", 3))
	for index in count:
		lamps.append({"x": 160.0 + float(index) * (420.0 / float(maxi(1, count - 1))) + rng.float_range(-20.0, 20.0), "lit": false})
	audio.define("jump", GameSfx.preset("jump"))
	audio.define("land", GameSfx.preset("land"))
	audio.load_sound("chime", "res://testing/games/fixture_gallery/audio/chime.ogg", {"vary": 0.03})
	audio.load_music("village", "res://testing/games/fixture_gallery/audio/village.ogg")
	audio.load_stinger("clear", "res://testing/games/fixture_gallery/audio/clear.ogg")
	audio.play_track("village", 0.5)

func _game_step(delta: float) -> void:
	if clear_timer >= 0.0:
		clear_timer -= delta
		if clear_timer < 0.0:
			finish(OUTCOME_CLEARED, {"seconds_left": int(time_left)})
		return
	var pad := input(0)
	walking = absf(pad.move.x) > 0.1
	if walking:
		facing_left = pad.move.x < 0.0
		keeper.x = clampf(keeper.x + pad.move.x * SPEED * delta, 20.0, float(stage_size.x) - 20.0)
	if keeper.y >= GROUND and pad.just_pressed(GameInput.A):
		lift = -JUMP_SPEED
		audio.play("jump")
	if keeper.y < GROUND or lift < 0.0:
		lift += GRAVITY * delta
		keeper.y += lift * delta
		if keeper.y >= GROUND:
			keeper.y = GROUND
			lift = 0.0
			audio.play("land")
	for lamp in lamps:
		if not lamp["lit"] and absf(float(lamp["x"]) - keeper.x) < REACH:
			lamp["lit"] = true
			lit += 1
			score += 100
			audio.play("chime")
	time_left = maxf(0.0, time_left - delta)
	if lit == lamps.size():
		audio.play_stinger("clear")
		clear_timer = CLEAR_DELAY
	elif time_left <= 0.0:
		finish(OUTCOME_TIMED_OUT)

## The frame of the keeper right now. Derived from simulated time only, so a test can read it.
func keeper_frame() -> String:
	if keeper.y < GROUND:
		return "walk_0"
	return sprites.animation_frame("walk", elapsed) if walking else "idle"

func _game_snapshot() -> Dictionary:
	return {"time_left": time_left, "lit": lit, "lamps_total": lamps.size(), "keeper": keeper, "facing_left": facing_left, "frame": keeper_frame(), "players": [{"score": score}]}

func _game_frame(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var stage := Vector2(stage_size)
	draw_rect(Rect2(Vector2.ZERO, stage), Color("1b2440"))
	draw_rect(Rect2(0.0, stage.y * 0.45, stage.x, stage.y * 0.55), Color("243056"))
	floor_tile.draw_tiled(self, "main", Rect2(0.0, GROUND, stage.x, stage.y - GROUND), Vector2.ZERO, Vector2(keeper.x * 0.25, 0.0))
	for lamp in lamps:
		var at := Vector2(float(lamp["x"]), GROUND)
		draw_line(at, at + Vector2(0.0, -70.0), Color("3a4468"), 3.0, true)
		draw_circle(at + Vector2(0.0, -76.0), 9.0, Color("ffd060") if lamp["lit"] else Color("4a5478"), true, -1.0, true)
		if lamp["lit"]:
			draw_circle(at + Vector2(0.0, -76.0), 22.0, Color("ffd060", 0.18), true, -1.0, true)
	sprites.draw(self, keeper_frame(), keeper, facing_left)
	text.draw(self, Vector2(stage.x * 0.5, 96.0), "点亮每一盏灯" if locale == "zh" else "Light every lamp", 16, Color("f4e8c8"), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 600, 1.5, Color("10162c"))
