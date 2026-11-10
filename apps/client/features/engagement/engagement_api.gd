class_name EngagementApi
extends RefCounted

var _transport: Variant

func _init(transport: Variant) -> void: _transport = transport

func downloads(lang: String = "zh"): return await _request_get("/api/v1/downloads?lang=%s" % lang.uri_encode())
func history(lang: String = "zh"): return await _request_get("/api/v1/history?lang=%s" % lang.uri_encode())
func update_download(game_id: String): return await _post("/api/v1/downloads/%s/update" % game_id.uri_encode(), {})
func remove_download(game_id: String): return await _transport.request(HTTPClient.METHOD_DELETE, "/api/v1/downloads/%s" % game_id.uri_encode())
func clear_history(): return await _transport.request(HTTPClient.METHOD_DELETE, "/api/v1/history")
func record_play(game_id: String, duration_ms: int): return await _post("/api/v1/games/%s/played" % game_id.uri_encode(), {"duration_ms":maxi(0, duration_ms)})
func live(lang: String = "zh"): return await _request_get("/api/v1/live?lang=%s" % lang.uri_encode())
func send_live_gift(stream_id: String): return await _post("/api/v1/live/%s/gift" % stream_id.uri_encode(), {})
func create_room(): return await _post("/api/v1/rooms", {})
func join_room(code: String): return await _post("/api/v1/rooms/join", {"code":code})
func get_room(id: String): return await _request_get("/api/v1/rooms/%s" % id.uri_encode())
func set_room_ready(id: String, ready: bool): return await _post("/api/v1/rooms/%s/ready" % id.uri_encode(), {"ready":ready})
func start_room(id: String): return await _post("/api/v1/rooms/%s/start" % id.uri_encode(), {})
func room_snapshot(id: String): return await _request_get("/api/v1/rooms/%s/snapshot" % id.uri_encode())
func submit_room_input(id: String, seq: int, move_x: float, move_y: float, fire: bool):
	return await _post("/api/v1/rooms/%s/input" % id.uri_encode(), {"seq":seq,"move_x":move_x,"move_y":move_y,"fire":fire})
func replay(game_id: String, user_id: String): return await _request_get("/api/v1/games/%s/replays/%s" % [game_id.uri_encode(), user_id.uri_encode()])
func replay_leaderboard(game_id: String): return await _request_get("/api/v1/games/%s/replays/leaderboard" % game_id.uri_encode())
func submit_replay(game_id: String, duration_ms: int, frames: Array):
	return await _post("/api/v1/games/%s/replays" % game_id.uri_encode(), {"duration_ms":maxi(1, duration_ms),"frames":frames})

func _request_get(path: String): return await _transport.request(HTTPClient.METHOD_GET, path)
func _post(path: String, body: Dictionary): return await _transport.request(HTTPClient.METHOD_POST, path, body)
