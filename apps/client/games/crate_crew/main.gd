extends GameModule

## Crate Crew: two small repair robots cross a runaway workshop with nothing but what they can lift. This entry script joins the parts: world.gd simulates, render.gd draws, sounds.gd holds the effects and tunes. All play happens in _game_step; _game_frame only animates.

const World := preload("res://games/crate_crew/world.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Render := preload("res://games/crate_crew/render.gd")
const Sounds := preload("res://games/crate_crew/sounds.gd")

## Events that are heard under their own name.
const HEARD := ["jump", "land", "lift", "put_down", "throw", "throw_up", "break", "clang", "poof", "thud", "foe_hit", "foe_out", "hop", "shot", "drop", "rev", "hurt", "die", "respawn", "gear", "battery", "chip", "cog", "flag", "chute", "stage_start", "stage_clear", "boss_start", "boss_spit", "boss_inhale", "boss_charge", "boss_slam", "boss_hit", "boss_angry", "boss_burst", "boss_down", "continue", "game_over"]

var world: World
var _view: Render
var _music := ""

func _game_start(config: Dictionary) -> void:
	var chosen: Dictionary = config["options"]
	world = World.new(rng, int(chosen.get("difficulty", 2)))
	for slot in active_players():
		world.heroes[slot]["active"] = true
	# "stage" and "flag" let the tests begin at a later stage or at one of its flags; the menu never offers them.
	world.load_stage(clampi(int(chosen.get("stage", 1)) - 1, 0, Levels.COUNT - 1), int(chosen.get("flag", 0)) - 1)
	if _view == null:
		_view = Render.new()
		_view.name = "View"
		add_child(_view)
	_view.setup(world, locale)
	_view.players = player_count()
	Sounds.define_all(audio)
	_music = ""
	_play_music("stage%d" % (world.stage % 2))

func _game_step(delta: float) -> void:
	world.step([input(0), input(1)], delta)
	for event in world.events:
		var name := str(event["name"])
		if name in HEARD:
			audio.play(name)
		match name:
			"boss_start":
				_play_music("boss")
			"stage_start":
				_play_music("stage%d" % (world.stage % 2))
			"boss_down", "game_over", "continue":
				audio.stop_music()
				_music = ""
		_view.note(event)
	world.events.clear()
	score = int(world.heroes[0]["score"]) + int(world.heroes[1]["score"])
	if world.phase == World.P_WON:
		finish(OUTCOME_CLEARED)
	elif world.phase == World.P_LOST:
		finish(OUTCOME_DEFEATED)

func _play_music(which: String) -> void:
	if which == _music:
		return
	_music = which
	match which:
		"boss":
			audio.play_music(Sounds.boss_music(), -7.0)
		"stage1":
			audio.play_music(Sounds.stage_music(1), -8.0)
		_:
			audio.play_music(Sounds.stage_music(0), -8.0)

func _game_frame(delta: float) -> void:
	_view.players = player_count()
	_view.advance(delta)

func _game_snapshot() -> Dictionary:
	var players: Array = []
	for slot in MAX_PLAYERS:
		var hero: Dictionary = world.heroes[slot] if world != null else {}
		players.append({
			"score": int(hero.get("score", 0)), "energy": int(hero.get("energy", 0)) if bool(hero.get("active", false)) else 0, "max_energy": int(world.rules["energy"]) if world != null else 3,
			"lives": maxi(0, int(hero.get("lives", 0))) if bool(hero.get("active", false)) else 0, "x": float(hero.get("x", 0.0)), "y": float(hero.get("y", 0.0)), "state": int(hero.get("state", World.H_OUT)),
			"carrying": hero.get("carry") != null, "hiding": bool(hero.get("hide", false)), "ground": bool(hero.get("ground", false)),
		})
	if world == null:
		return {"stage": 1, "stages": Levels.COUNT, "gears": 0, "players": players}
	var out := {
		"stage": world.stage + 1, "stages": Levels.COUNT, "gears": world.gears, "golden_cogs": world.golden_cogs, "continues_left": world.continues_left, "continues_used": world.continues_used,
		"bosses_beaten": world.bosses_beaten, "deaths": world.deaths, "foes_beaten": world.foes_beaten, "buddy_hits": world.buddy_hits, "crates_broken": world.crates_broken, "difficulty": world.difficulty,
		"phase": world.phase, "camera_x": world.camera.x, "camera_y": world.camera.y, "players": players,
	}
	if world.boss_fight and not world.boss.is_empty() and bool(world.boss["alive"]):
		out["boss_hp"] = maxi(0, int(world.boss["hp"]))
		out["boss_max_hp"] = int(world.boss["max_hp"])
	return out

func _game_player_joined(slot: int) -> void:
	world.add_hero(slot)
	_view.players = player_count()

func _game_player_left(slot: int) -> void:
	world.remove_hero(slot)
	_view.players = player_count()
