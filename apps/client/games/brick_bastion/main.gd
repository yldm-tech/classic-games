extends GameModule

## Brick Bastion: a top-down base defence on a grid. One or two sentinel rovers keep waves of raiders away from the beacon at the bottom of the field, across six hand-built sectors and two bosses.
##
## This script is the thin shell the host talks to. The rules live in sim.gd (stepped from _game_step, exact integer arithmetic on the seeded rng), the pictures in sprites.gd, the pixel lettering in glyphs.gd, the drawing in render.gd, particles and weather in fx.gd, sound in sounds.gd, sector layouts in stages.gd and the words in texts.gd.

const Sim := preload("res://games/brick_bastion/sim.gd")
const Stages := preload("res://games/brick_bastion/stages.gd")
const Sprites := preload("res://games/brick_bastion/sprites.gd")
const Render := preload("res://games/brick_bastion/render.gd")
const Fx := preload("res://games/brick_bastion/fx.gd")
const Sounds := preload("res://games/brick_bastion/sounds.gd")
const Glyphs := preload("res://games/brick_bastion/glyphs.gd")

var sim: RefCounted
var fx: RefCounted
var tex: Dictionary = {}
var ground_tex: Texture2D
var frame_tex: Texture2D
var font: SystemFont
var glyph_tex: Texture2D
var outline_tex: Texture2D
var glyph_columns: Dictionary = {}
var time := 0.0

var _music := ""
var _painted_theme := ""
var _runs: Dictionary = {}

func _game_start(config: Dictionary) -> void:
	sim = Sim.new()
	fx = Fx.new()
	time = 0.0
	_music = ""
	_painted_theme = ""
	if not audio.has_sound("fire"):
		Sounds.define_all(audio)
	sim.setup(rng, audio, config)
	_follow_music()

func _game_step(_delta: float) -> void:
	sim.step([input(0), input(1)])
	score = sim.score_total
	_follow_music()
	if sim.outcome == "cleared":
		finish(OUTCOME_CLEARED)
	elif sim.outcome == "defeated":
		finish(OUTCOME_DEFEATED)

## The simulation says which tune belongs to the moment; this starts it when that changes.
func _follow_music() -> void:
	if sim.music == _music:
		return
	_music = sim.music
	if _music == "":
		audio.stop_music()
	else:
		audio.play_music(Sounds.tune(_music), -9.0)

func _game_frame(delta: float) -> void:
	time += delta
	fx.consume(sim.events)
	sim.events.clear()
	fx.update(delta)
	queue_redraw()

func _game_snapshot() -> Dictionary:
	if sim == null:
		return {}
	var players: Array = []
	for slot in MAX_PLAYERS:
		var rover: Dictionary = sim.rovers[slot]
		players.append({"score": rover.score, "lives": rover.lives, "max_lives": rover.max_lives, "power": rover.power, "bricks": rover.bricks, "kills": rover.kills, "alive": rover.alive, "shielded": rover.shield_t > 0, "x": float(rover.x) / Sim.UNIT, "y": float(rover.y) / Sim.UNIT, "dir": rover.dir})
	var out := {
		"stage": sim.stage + 1, "stages": Stages.count(), "core": sim.core, "core_max": sim.core_max, "foes_left": sim.foes_left(),
		"kills": sim.kills, "deaths": sim.deaths, "core_hits": sim.core_hits, "bricks_laid": sim.bricks_laid, "chips": sim.chips_taken, "bosses_down": sim.bosses_down, "stages_cleared": sim.stages_cleared, "crews": sim.crews, "crews_used": sim.crews_used,
		"difficulty": sim.difficulty, "phase": sim.phase, "raiders": sim.raiders.size(), "digest": sim.digest(), "players": players,
	}
	if sim.boss_state == Sim.BOSS_PRESENT:
		out["boss_hp"] = sim.boss_hp
		out["boss_max_hp"] = sim.boss_max_hp
	return out

func _game_player_joined(slot: int) -> void:
	sim.join(slot)

func _game_player_left(slot: int) -> void:
	sim.leave(slot)

## A text split into pixel-lettering and system-font runs, remembered so that drawing the same words every frame does not split them again.
func text_runs(text: String) -> Array:
	if not _runs.has(text):
		if _runs.size() >= 256:
			_runs.clear()
		_runs[text] = Glyphs.runs(text)
	return _runs[text]

func _draw() -> void:
	if sim == null:
		return
	if font == null:
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Noto Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"])
		font.allow_system_fallback = true
		# Only Chinese goes through this font (Latin letters and digits have pixel glyphs of their own), and at this size it stays crisp without smoothing.
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.hinting = TextServer.HINTING_NORMAL
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font.font_weight = 600
		frame_tex = ImageTexture.create_from_image(Render.frame_image())
		var lettering := Glyphs.images()
		glyph_tex = ImageTexture.create_from_image(lettering["glyph"])
		outline_tex = ImageTexture.create_from_image(lettering["outline"])
		glyph_columns = Glyphs.columns()
	var theme := str(sim.stage_info()["theme"])
	if theme != _painted_theme:
		# A new sector: repaint the ground and the tiles in its colours, and change the weather.
		_painted_theme = theme
		tex = Sprites.build(theme)
		ground_tex = ImageTexture.create_from_image(Sprites.ground(theme, int(Render.FIELD_SIZE.x), int(Render.FIELD_SIZE.y)))
		fx.reset(theme)
	Render.draw(self, self)
