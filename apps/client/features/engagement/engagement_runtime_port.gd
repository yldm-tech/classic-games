class_name EngagementRuntimePort
extends RefCounted

var _gateway: Variant

func _init(gateway: Variant) -> void: _gateway = gateway

func record_play(game_id: String, duration_ms: int):
	if game_id == "": return _invalid("INVALID_GAME", "Game id is required")
	return await _gateway.record_play(game_id, maxi(0, duration_ms))

func submit_replay(game_id: String, duration_ms: int, frames: Array):
	if game_id == "" or duration_ms <= 0 or frames.size() < 1: return _invalid("INVALID_REPLAY", "Replay payload is incomplete")
	return await _gateway.submit_replay(game_id, duration_ms, frames)

func room_snapshot(room_id: String):
	if room_id == "": return _invalid("INVALID_ROOM", "Room id is required")
	return await _gateway.room_snapshot(room_id)

func submit_room_input(room_id: String, seq: int, movement: Vector2, fire: bool):
	if room_id == "" or seq <= 0: return _invalid("INVALID_INPUT", "Room input sequence must be positive")
	return await _gateway.submit_room_input(room_id, seq, movement.x, movement.y, fire)

func _invalid(code: String, message: String):
	return preload("res://core/http/api_result.gd").unexpected(code, message)
