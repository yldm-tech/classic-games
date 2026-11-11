extends GameModule

## Crate Crew: two small red squirrels chase the crow that stole their winter acorns, through a kitchen, a toy shop, a sewer and a treehouse, with nothing but what they can lift. This entry script joins the parts: world.gd simulates (the map between levels included), render.gd draws, sounds.gd holds the effects and names the music of each place. All play happens in _game_step; _game_frame only animates.

const World := preload("res://games/crate_crew/world.gd")
const Levels := preload("res://games/crate_crew/levels.gd")
const Render := preload("res://games/crate_crew/render.gd")
const Sounds := preload("res://games/crate_crew/sounds.gd")

var world: World
var _view: Render
var _first_map := true

func _game_start(config: Dictionary) -> void:
	var chosen: Dictionary = config["options"]
	world = World.new(rng, int(chosen.get("difficulty", 2)))
	for slot in active_players():
		world.heroes[slot]["active"] = true
	_first_map = true
	Sounds.define_all(audio)
	# "level" (an index into Levels.LEVELS, from 1) and "flag" let the tests and screenshots begin at a level or one of its flags; the menu never offers them.
	var start_at := int(chosen.get("level", 0))
	if start_at > 0:
		var id: String = Levels.LEVELS[clampi(start_at - 1, 0, Levels.LEVELS.size() - 1)]
		world.node = Levels.parent_of(id)
		world.start_level(id, int(chosen.get("flag", 0)) - 1)
	else:
		world.open_map()
	if _view == null:
		_view = Render.new()
		_view.name = "View"
		add_child(_view)
	_view.setup(world, locale)
	_view.players = player_count()
	audio.play_track(_track(), 0.0)
	world.events.clear()

## The music for what is on screen now.
func _track() -> String:
	if world.phase == World.P_MAP:
		return "title" if _first_map else "map"
	if not world.boss.is_empty():
		return "boss"
	return world.theme

func _game_step(delta: float) -> void:
	world.step([input(0), input(1)], delta)
	for event in world.events:
		var name := str(event["name"])
		if Sounds.has_effect(name):
			audio.play(name)
		match name:
			"map":
				audio.play_track(_track())
			"map_pick":
				_first_map = false
			"level_start":
				audio.play_track(_track(), 0.6)
			"boss_down":
				audio.stop_music(1.0)
			"level_clear":
				# The last boss ends the run: its fanfare takes the music with it. After any other level the map's tune comes in under the tail of the short one.
				if bool(event.get("final", false)):
					audio.play_stinger("victory", GameAudio.STINGER_STOP)
				else:
					audio.play_stinger("clear", GameAudio.STINGER_STOP)
			"continue":
				audio.stop_music(0.4)
			"game_over":
				audio.play_stinger("gameover", GameAudio.STINGER_STOP)
		_view.note(event)
	world.events.clear()
	score = int(world.heroes[0]["score"]) + int(world.heroes[1]["score"])
	if world.phase == World.P_WON:
		finish(OUTCOME_CLEARED)
	elif world.phase == World.P_LOST:
		finish(OUTCOME_DEFEATED)

func _game_frame(delta: float) -> void:
	_view.players = player_count()
	_view.advance(delta)

func _game_snapshot() -> Dictionary:
	var players: Array = []
	var hearts := int(world.rules["hearts"]) if world != null else 3
	for slot in MAX_PLAYERS:
		var hero: Dictionary = world.heroes[slot] if world != null else {}
		var playing := bool(hero.get("active", false))
		players.append({
			"score": int(hero.get("score", 0)), "hearts": int(hero.get("hearts", 0)) if playing and (int(hero.get("state", World.H_OUT)) != World.H_OUT or world.phase == World.P_MAP) else 0, "max_hearts": hearts,
			"lives": maxi(0, int(hero.get("lives", 0))) if playing else 0, "x": float(hero.get("x", 0.0)), "y": float(hero.get("y", 0.0)), "state": int(hero.get("state", World.H_OUT)),
			"carrying": hero.get("carry") != null, "hiding": bool(hero.get("hide", false)), "ground": bool(hero.get("ground", false)),
		})
	if world == null:
		return {"level": 1, "levels": Levels.ROUTE_LENGTH, "acorns": 0, "acorns_per_life": World.ACORNS_PER_LIFE, "players": players}
	# Which level of the route this is: the one being played, or on the map the one about to be picked.
	var done := world.route.size()
	var number := done if world.phase == World.P_CLEAR or world.phase == World.P_WON else done + 1
	var out := {
		"level": clampi(number, 1, Levels.ROUTE_LENGTH), "levels": Levels.ROUTE_LENGTH, "acorns": world.acorns, "acorns_per_life": World.ACORNS_PER_LIFE, "acorns_total": world.acorns_total,
		"continues_left": world.continues_left, "continues_used": world.continues_used, "bosses_beaten": world.bosses_beaten, "deaths": world.deaths, "foes_beaten": world.foes_beaten,
		"buddy_hits": world.buddy_hits, "crates_broken": world.crates_broken, "secrets": world.secrets.size(), "stacks": world.stacks, "difficulty": world.difficulty,
		"phase": world.phase, "node": world.node, "level_id": world.level_id, "camera_x": world.camera.x, "camera_y": world.camera.y, "players": players,
	}
	if not world.boss.is_empty() and bool(world.boss["alive"]) and world.phase != World.P_MAP:
		out["boss_hp"] = maxi(0, int(world.boss["hp"]))
		out["boss_max_hp"] = int(world.boss["max_hp"])
		out["boss_phase"] = int(world.boss["phase"])
	return out

func _game_player_joined(slot: int) -> void:
	world.add_hero(slot)
	_view.players = player_count()

func _game_player_left(slot: int) -> void:
	world.remove_hero(slot)
	_view.players = player_count()
