extends GameModule

## Yarn Tumble: two knitters climb the Loom Tower one screen at a time. Yarn thrown from the needle wraps a creature a little more with every hit; a fully wrapped creature is a ball that can be pushed or kicked, and a kicked ball rolls down the ledges knocking out everything in its way. A floor is cleared when no creature is left.
##
## This script is only the glue between the host and three parts: World (the simulation), View (all drawing) and Sounds (effect and music definitions).

const World := preload("res://games/yarn_tumble/world.gd")
const View := preload("res://games/yarn_tumble/view.gd")
const Sounds := preload("res://games/yarn_tumble/sounds.gd")
const Hero := preload("res://games/yarn_tumble/hero.gd")

var world: World
var view: View

var _track := -1
var _jingle: Array = []
var _jingle_wait := 0

func _game_start(config: Dictionary) -> void:
	var chosen: Dictionary = config["options"]
	world = World.new()
	# "first_floor" is not in the manifest: the tests use it to reach a late floor without playing the whole tower.
	world.setup(rng, int(chosen.get("difficulty", 1)), int(config["players"]), int(chosen.get("first_floor", 1)))
	Sounds.define_all(audio)
	if view != null:
		view.free()
	view = View.new()
	view.setup(world, str(config["locale"]))
	add_child(view)
	_track = -1
	_jingle.clear()
	_jingle_wait = 0
	_hear()

func _game_step(delta: float) -> void:
	world.step(delta, [input(0), input(1)], active_players())
	_hear()
	score = world.total_score()
	if world.outcome == "cleared":
		finish(OUTCOME_CLEARED)
	elif world.outcome == "defeated":
		finish(OUTCOME_DEFEATED)

## Turn what the world just did into sound, and hand it to the view for effects.
func _hear() -> void:
	for event: Array in world.events:
		var sound: Array = Sounds.for_event(event)
		if sound[0] != "":
			audio.play(str(sound[0]), float(sound[1]))
		match str(event[0]):
			"clear":
				_jingle = Sounds.JINGLE_BOSS.duplicate() if world.is_boss_stage() else Sounds.JINGLE_CLEAR.duplicate()
				_jingle_wait = 0
			"stage":
				var track := Sounds.track_for(world.stage, world.is_boss_stage())
				if track != _track:
					_track = track
					audio.play_music(Sounds.music(track), -9.0)
			"boss_down":
				audio.stop_music()
				_track = -1
		view.notice(event)
	world.events.clear()
	if not _jingle.is_empty():
		_jingle_wait += 1
		if _jingle_wait >= int(_jingle[0][0]):
			audio.play("note", float(_jingle[0][1]))
			_jingle.pop_front()
			_jingle_wait = 0

func _game_frame(delta: float) -> void:
	view.animate(delta)

func _game_player_joined(slot: int) -> void:
	world.join(slot)

func _game_player_left(slot: int) -> void:
	world.leave(slot)

func _game_snapshot() -> Dictionary:
	var players: Array = []
	for hero in world.heroes:
		players.append({
			"score": hero.score, "lives": hero.lives, "max_lives": world.max_lives, "x": hero.x, "y": hero.y,
			"alive": hero.state == Hero.ALIVE, "powers": int(hero.long_needle) + int(hero.rapid) + int(hero.thick) + int(hero.swift),
		})
	var out := {
		"stage": world.stage, "stages_total": World.Levels.count(), "foes_left": world.foes.size(), "difficulty": world.difficulty,
		"deaths": world.deaths, "continues_left": world.continues, "continues_used": world.continues_used,
		"kos": world.kos, "best_roll": world.best_roll, "bosses_defeated": world.bosses_defeated, "gems": world.gems,
		"players": players,
	}
	if world.boss != null and world.boss.is_fighting():
		out["boss_hp"] = world.boss.hp
		out["boss_max_hp"] = world.boss.max_hp
	return out
