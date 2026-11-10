extends SceneTree

const ApiResultScript := preload("res://core/http/api_result.gd")
const EngagementApiScript := preload("res://features/engagement/engagement_api.gd")
const EngagementStoreScript := preload("res://features/engagement/engagement_store.gd")
const EngagementCoordinatorScript := preload("res://features/engagement/engagement_coordinator.gd")
const EngagementRuntimePortScript := preload("res://features/engagement/engagement_runtime_port.gd")
const NetworkMatchSessionScript := preload("res://runtime/network_match_session.gd")

class Gate:
	extends RefCounted
	signal released

class FakeTransport:
	extends RefCounted
	var requests: Array[Dictionary] = []
	func request(method: int, path: String, body: Variant = null):
		requests.append({"method":method, "path":path, "body":body})
		return ApiResultScript.success(200, {})

class FakeGateway:
	extends RefCounted
	var room_gates: Dictionary = {}
	var replay_gates: Dictionary = {}
	var leaderboard_gates: Dictionary = {}
	var remove_gates: Dictionary = {}
	var history_gate: Gate
	var room_calls: Dictionary = {}
	var gift_gate: Gate
	var gift_calls := 0
	func downloads(_lang: String): return ApiResultScript.success(200, {"items":[{"game":{"id":"g1"},"size_mb":12,"has_update":true}]})
	func history(_lang: String):
		if history_gate != null: await history_gate.released
		return ApiResultScript.success(200, {"groups":[{"group":"today","items":[{"game":{"id":"g1"},"minutes_played":2}]}]})
	func update_download(game_id: String): return ApiResultScript.success(200, {"game_id":game_id})
	func remove_download(game_id: String):
		if remove_gates.has(game_id): await (remove_gates[game_id] as Gate).released
		return ApiResultScript.success(200, {"game_id":game_id})
	func clear_history(): return ApiResultScript.success(200, {})
	func live(_lang: String): return ApiResultScript.success(200, {"items":[{"game_id":"g1"}]})
	func send_live_gift(_stream_id: String):
		gift_calls += 1
		if gift_gate != null: await gift_gate.released
		return ApiResultScript.success(200, {"balance":90})
	func create_room(): return ApiResultScript.success(201, _room("new", 1))
	func join_room(code: String): return ApiResultScript.success(200, _room(code, 1))
	func get_room(id: String):
		room_calls[id] = int(room_calls.get(id, 0)) + 1
		if room_gates.has(id): await (room_gates[id] as Gate).released
		return ApiResultScript.success(200, _room(id, 2))
	func set_room_ready(id: String, ready: bool):
		var value := _room(id, 3); value.members[0].ready = ready; return ApiResultScript.success(200, value)
	func start_room(id: String): var value := _room(id, 4); value.status = "started"; return ApiResultScript.success(200, value)
	func replay(game_id: String, user_id: String):
		var key := game_id + ":" + user_id
		if replay_gates.has(key): await (replay_gates[key] as Gate).released
		return ApiResultScript.success(200, {"duration_ms":1000,"frames":[{"at_ms":0},{"at_ms":1000}],"key":key})
	func replay_leaderboard(game_id: String):
		if leaderboard_gates.has(game_id): await (leaderboard_gates[game_id] as Gate).released
		return ApiResultScript.success(200, {"items":[{"user_id":game_id}]})
	func record_play(_game_id: String, _duration_ms: int): return ApiResultScript.success(201, {})
	func submit_replay(_game_id: String, _duration_ms: int, _frames: Array): return ApiResultScript.success(201, {})
	func room_snapshot(id: String): return ApiResultScript.success(200, {"room_id":id,"tick":2,"players":[]})
	func submit_room_input(id: String, seq: int, _x: float, _y: float, _fire: bool): return ApiResultScript.success(200, {"room_id":id,"tick":seq,"players":[]})
	func _room(id: String, revision: int) -> Dictionary:
		return {"id":id,"code":id,"host_id":"u1","status":"waiting","revision":revision,"members":[{"user_id":"u1","ready":false}]}

class GatedRuntimePort:
	extends RefCounted
	var gate := Gate.new()
	func submit_room_input(room_id: String, seq: int, _move: Vector2, _fire: bool):
		await gate.released
		return ApiResultScript.success(200, {"room_id":room_id,"tick":seq,"players":[]})
	func room_snapshot(room_id: String): return ApiResultScript.success(200, {"room_id":room_id,"tick":1,"players":[]})

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await _test_api_owns_engagement_paths()
	await _test_collections_and_serialized_writes()
	await _test_stale_room_and_replay_responses_are_rejected()
	await _test_stale_leaderboard_response_is_rejected()
	await _test_runtime_port_preserves_api_results()
	await _test_cancelled_runtime_session_rejects_late_response()
	await _test_history_clear_and_download_deletes_are_race_safe()
	await _test_library_port_preserves_failure()
	print("engagement_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_api_owns_engagement_paths() -> void:
	var transport := FakeTransport.new(); var api = EngagementApiScript.new(transport)
	await api.downloads("ja"); await api.history("ja"); await api.update_download("g/1"); await api.remove_download("g/1"); await api.clear_history()
	await api.record_play("g/1", -5); await api.live("ja"); await api.send_live_gift("s/1")
	await api.create_room(); await api.join_room("ABC"); await api.get_room("r/1"); await api.set_room_ready("r/1", true); await api.start_room("r/1")
	await api.room_snapshot("r/1"); await api.submit_room_input("r/1", 2, 1.0, -1.0, true)
	await api.replay("g/1", "u/1"); await api.replay_leaderboard("g/1"); await api.submit_replay("g/1", 10, [])
	var paths: Array = transport.requests.map(func(request: Dictionary): return request.path)
	_check("engagement api owns encoded paths", paths == [
		"/api/v1/downloads?lang=ja", "/api/v1/history?lang=ja", "/api/v1/downloads/g%2F1/update", "/api/v1/downloads/g%2F1", "/api/v1/history",
		"/api/v1/games/g%2F1/played", "/api/v1/live?lang=ja", "/api/v1/live/s%2F1/gift", "/api/v1/rooms", "/api/v1/rooms/join",
		"/api/v1/rooms/r%2F1", "/api/v1/rooms/r%2F1/ready", "/api/v1/rooms/r%2F1/start", "/api/v1/rooms/r%2F1/snapshot", "/api/v1/rooms/r%2F1/input",
		"/api/v1/games/g%2F1/replays/u%2F1", "/api/v1/games/g%2F1/replays/leaderboard", "/api/v1/games/g%2F1/replays"])
	_check("play duration is clamped at the boundary", transport.requests[5].body.duration_ms == 0)

func _test_collections_and_serialized_writes() -> void:
	var fixture := _fixture()
	_check("downloads history and live become feature state", await fixture.coordinator.load_downloads("zh") and await fixture.coordinator.load_history("zh")
		and await fixture.coordinator.load_live("zh") and fixture.store.downloads[0].game.id == "g1" and fixture.store.history_groups[0].group == "today")
	_check("download update and removal mutate confirmed state", await fixture.coordinator.update_download("g1")
		and not fixture.store.downloads[0].has_update and await fixture.coordinator.remove_download("g1") and fixture.store.downloads.is_empty())
	fixture.gateway.gift_gate = Gate.new(); fixture.coordinator.send_live_gift("stream")
	_check("duplicate gifts are rejected while pending", not await fixture.coordinator.send_live_gift("stream") and fixture.gateway.gift_calls == 1)
	fixture.gateway.gift_gate.released.emit(); await process_frame
	_check("gift completion updates confirmed balance", fixture.store.balance == 90 and not fixture.store.gift_pending)
	fixture.free_all.call()

func _test_stale_room_and_replay_responses_are_rejected() -> void:
	var fixture := _fixture(); var old_room_gate := Gate.new(); fixture.gateway.room_gates.old = old_room_gate
	fixture.coordinator.open_room("old")
	_check("a newer room supersedes an in-flight poll", await fixture.coordinator.open_room("new") and fixture.store.room.id == "new")
	old_room_gate.released.emit(); await process_frame
	_check("stale room response cannot replace current room", fixture.store.room.id == "new")
	var opening_gate := Gate.new(); fixture.gateway.room_gates.opening = opening_gate
	fixture.coordinator.open_room("opening")
	_check("room polling is rejected while another room is opening", not await fixture.coordinator.poll_room()
		and int(fixture.gateway.room_calls.get("new", 0)) == 1)
	opening_gate.released.emit(); await process_frame
	_check("opening room remains authoritative after polling attempt", fixture.store.room.id == "opening")
	var old_replay_gate := Gate.new(); fixture.gateway.replay_gates["g1:old"] = old_replay_gate
	fixture.coordinator.load_replay("g1", "old")
	_check("a newer replay supersedes an in-flight load", await fixture.coordinator.load_replay("g1", "new") and fixture.store.replay.key == "g1:new")
	old_replay_gate.released.emit(); await process_frame
	_check("stale replay response cannot replace current replay", fixture.store.replay.key == "g1:new")
	fixture.free_all.call()

func _test_runtime_port_preserves_api_results() -> void:
	var gateway := FakeGateway.new(); var port = EngagementRuntimePortScript.new(gateway)
	var input = await port.submit_room_input("room", 3, Vector2(1, -1), true)
	_check("runtime port exposes ApiResult and monotonic payload", input.ok and input.data.tick == 3)
	_check("runtime port owns play and replay writes", (await port.record_play("g1", 4)).ok and (await port.submit_replay("g1", 5, [{"at_ms":0}])).ok)

func _test_stale_leaderboard_response_is_rejected() -> void:
	var fixture := _fixture(); var old_gate := Gate.new(); fixture.gateway.leaderboard_gates.old = old_gate
	fixture.coordinator.load_replay_leaderboard("old")
	_check("new leaderboard supersedes an in-flight old game", await fixture.coordinator.load_replay_leaderboard("new")
		and fixture.store.replay_leaderboard_by_game.new[0].user_id == "new")
	old_gate.released.emit(); await process_frame
	_check("different games keep independent leaderboard generations", fixture.store.replay_leaderboard_by_game.old[0].user_id == "old"
		and fixture.store.replay_leaderboard_by_game.new[0].user_id == "new")
	fixture.free_all.call()

func _test_cancelled_runtime_session_rejects_late_response() -> void:
	var port := GatedRuntimePort.new(); var session = NetworkMatchSessionScript.new(); var updates := {"count":0}
	session.configure(port, "old-room", "u1"); session.snapshot_updated.connect(func(_snapshot: Dictionary): updates.count += 1)
	session.submit_input(Vector2.ONE, false)
	session.cancel(); session.configure(port, "new-room", "u1"); port.gate.released.emit(); await process_frame
	_check("cancelled match response cannot update a newer runtime", updates.count == 0 and session.room_id == "new-room" and session.current_tick == -1)

func _test_history_clear_and_download_deletes_are_race_safe() -> void:
	var fixture := _fixture(); fixture.gateway.history_gate = Gate.new()
	fixture.coordinator.load_history("zh")
	_check("clear history can supersede an in-flight load", await fixture.coordinator.clear_history() and fixture.store.history_groups.is_empty())
	fixture.gateway.history_gate.released.emit(); await process_frame
	_check("stale history load cannot restore cleared records", fixture.store.history_groups.is_empty())
	fixture.store.downloads = [{"game":{"id":"a"}}, {"game":{"id":"b"}}]
	fixture.gateway.remove_gates.a = Gate.new(); fixture.gateway.remove_gates.b = Gate.new()
	fixture.coordinator.remove_download("a"); fixture.coordinator.remove_download("b")
	fixture.gateway.remove_gates.b.released.emit(); await process_frame
	fixture.gateway.remove_gates.a.released.emit(); await process_frame
	_check("concurrent download deletes reconcile by id", fixture.store.downloads.is_empty())
	fixture.free_all.call()

func _test_library_port_preserves_failure() -> void:
	var gateway := FakeGateway.new(); var store = EngagementStoreScript.new()
	var failed = EngagementCoordinatorScript.new(gateway, store,
		func(_kind: String, _lang: String): return ApiResultScript.offline("down"))
	_check("library port preserves downstream failure", not await failed.load_library("games") and store.status == "offline")
	failed.free(); store.free()
	store = EngagementStoreScript.new()
	var empty = EngagementCoordinatorScript.new(gateway, store,
		func(_kind: String, _lang: String): return ApiResultScript.success(200, {"items":[]}))
	_check("library port distinguishes a valid empty collection", await empty.load_library("games") and store.status == "empty")
	empty.free(); store.free()

func _fixture() -> Dictionary:
	var gateway := FakeGateway.new(); var store = EngagementStoreScript.new(); var coordinator = EngagementCoordinatorScript.new(gateway, store)
	return {"gateway":gateway, "store":store, "coordinator":coordinator,
		"free_all":func() -> void: coordinator.free(); store.free()}

func _check(label: String, condition: bool) -> void:
	if condition: _passed += 1
	else: _failed += 1; push_error("FAIL: " + label)
