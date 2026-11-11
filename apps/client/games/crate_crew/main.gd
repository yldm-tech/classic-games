extends GameModule

## Crate Crew: entry script. The skeleton reports the HUD fields; the simulation arrives in the following commits.

const STAGES := 4

func _game_start(_config: Dictionary) -> void:
	pass

func _game_step(_delta: float) -> void:
	pass

func _game_snapshot() -> Dictionary:
	var players: Array = []
	for slot in MAX_PLAYERS:
		players.append({"score": 0, "energy": 3, "max_energy": 3, "lives": 3})
	return {"stage": 1, "stages": STAGES, "gears": 0, "players": players}
