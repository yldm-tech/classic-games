extends GameModule
## Part of a directory that is wrong on purpose; see ../README.md.

func _game_start(_config: Dictionary) -> void:
	pass

func _game_step(_delta: float) -> void:
	pass

func _game_snapshot() -> Dictionary:
	return {"time_left": 30.0, "lives": 3, "players": [{"lives": 3, "max_lives": 3}]}
