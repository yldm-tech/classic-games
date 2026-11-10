class_name NetworkMatchSession
extends RefCounted

## 权威房间会话：客户端只发送带单调序号的输入，并只接纳服务器递增 tick 快照。

signal snapshot_updated(snapshot: Dictionary)
signal match_finished(snapshot: Dictionary)

var runtime_port: Variant
var room_id := ""
var user_id := ""
var current_tick := -1
var snapshot: Dictionary = {}
var _next_seq := 0
var request_pending := false
var _generation := 0

func configure(p_runtime_port: Variant, p_room_id: String, p_user_id: String) -> void:
	_generation += 1
	runtime_port = p_runtime_port
	room_id = p_room_id
	user_id = p_user_id
	current_tick = -1
	snapshot = {}
	_next_seq = 0
	request_pending = false

func cancel() -> void:
	_generation += 1
	room_id = ""
	request_pending = false

func active() -> bool:
	return room_id != ""

func apply_snapshot(value: Dictionary) -> bool:
	if str(value.get("room_id", "")) != room_id:
		return false
	var tick := int(value.get("tick", -1))
	if tick <= current_tick:
		return false
	if value.get("players", null) is not Array:
		return false
	current_tick = tick
	snapshot = value.duplicate(true)
	var mine := local_player()
	if not mine.is_empty():
		_next_seq = maxi(_next_seq, int(mine.get("last_seq", 0)))
	snapshot_updated.emit(snapshot)
	if str(snapshot.get("status", "")) == "finished":
		match_finished.emit(snapshot)
	return true

func local_player() -> Dictionary:
	for value: Variant in snapshot.get("players", []):
		if value is Dictionary and str(value.get("user_id", "")) == user_id:
			return value
	return {}

func submit_input(move: Vector2, fire: bool) -> bool:
	if runtime_port == null or not active() or request_pending:
		return false
	request_pending = true
	_next_seq += 1
	var generation := _generation; var requested_room := room_id
	var response = await runtime_port.submit_room_input(requested_room, _next_seq, move, fire)
	if generation != _generation or requested_room != room_id: return false
	request_pending = false
	if not response.ok or not response.data is Dictionary:
		return false
	return apply_snapshot(response.data)

func poll() -> bool:
	if runtime_port == null or not active() or request_pending:
		return false
	request_pending = true
	var generation := _generation; var requested_room := room_id
	var response = await runtime_port.room_snapshot(requested_room)
	if generation != _generation or requested_room != room_id: return false
	request_pending = false
	if not response.ok or not response.data is Dictionary:
		return false
	return apply_snapshot(response.data)
