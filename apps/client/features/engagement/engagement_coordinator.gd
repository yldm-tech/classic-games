class_name EngagementCoordinator
extends Node

const ApiResultScript := preload("res://core/http/api_result.gd")

var gateway: Variant
var store: EngagementStore
var library_loader := Callable()
var _room_generation := 0
var _replay_generation := 0
var _leaderboard_generation_by_game: Dictionary = {}
var _downloads_load_generation := 0
var _history_generation := 0
var _library_generation := 0

func _init(p_gateway: Variant, p_store: EngagementStore, p_library_loader := Callable()) -> void:
	gateway = p_gateway; store = p_store; library_loader = p_library_loader

func load_library(kind: String, lang: String = "zh") -> bool:
	if kind not in ["games", "forks", "liked"] or not library_loader.is_valid(): return false
	_library_generation += 1; var generation := _library_generation; store.begin("library")
	var result: Variant = await library_loader.call(kind, lang)
	if generation != _library_generation: return false
	if not result is ApiResult: return _invalid("INVALID_LIBRARY", "Library loader must return ApiResult")
	if not _items_result(result, "INVALID_LIBRARY"): return false
	store.library_kind = kind; store.library_items = result.data.items.duplicate(true); store.library_revision += 1
	return _ready_collection(store.library_items)

func load_downloads(lang: String = "zh") -> bool:
	_downloads_load_generation += 1; var generation := _downloads_load_generation; store.begin("downloads")
	var result = await gateway.downloads(lang)
	if generation != _downloads_load_generation: return false
	if not _items_result(result, "INVALID_DOWNLOADS"): return false
	store.downloads = result.data.items.duplicate(true); store.downloads_revision += 1
	return _ready_collection(store.downloads)

func update_download(game_id: String) -> bool:
	if game_id == "" or bool(store.download_pending.get(game_id, false)): return false
	_downloads_load_generation += 1
	store.download_pending[game_id] = true; store.begin("update_download")
	var result = await gateway.update_download(game_id)
	store.download_pending.erase(game_id)
	if not result.ok: store.fail(result); return false
	for item: Dictionary in store.downloads:
		if str(item.get("game", {}).get("id", "")) == game_id: item["has_update"] = false
	store.downloads_revision += 1; return _finish_ready()

func remove_download(game_id: String) -> bool:
	if game_id == "" or bool(store.download_pending.get(game_id, false)): return false
	_downloads_load_generation += 1
	store.download_pending[game_id] = true; store.begin("remove_download")
	var result = await gateway.remove_download(game_id)
	store.download_pending.erase(game_id)
	if not result.ok: store.fail(result); return false
	store.downloads = store.downloads.filter(func(item: Variant) -> bool:
		return not item is Dictionary or str(item.get("game", {}).get("id", "")) != game_id)
	store.downloads_revision += 1; return _ready_collection(store.downloads)

func load_history(lang: String = "zh") -> bool:
	if store.history_pending: return false
	_history_generation += 1; var generation := _history_generation; store.begin("history")
	var result = await gateway.history(lang)
	if generation != _history_generation: return false
	if not _object_result(result, "INVALID_HISTORY"): return false
	if not result.data.get("groups", null) is Array: return _invalid("INVALID_HISTORY", "History groups must be an array")
	store.history_groups = result.data.groups.duplicate(true); store.history_revision += 1
	return _ready_collection(store.history_groups)

func clear_history() -> bool:
	if store.history_pending: return false
	_history_generation += 1; var generation := _history_generation
	store.history_pending = true; store.begin("clear_history")
	var result = await gateway.clear_history()
	if generation != _history_generation: return false
	store.history_pending = false
	if not result.ok: store.fail(result); return false
	store.history_groups = []; store.history_revision += 1; return _ready_collection([])

func load_live(lang: String = "zh") -> bool:
	store.begin("live")
	var result = await gateway.live(lang)
	if not _items_result(result, "INVALID_LIVE"): return false
	store.live_items = result.data.items.duplicate(true); store.live_revision += 1
	return _ready_collection(store.live_items)

func send_live_gift(stream_id: String) -> bool:
	if stream_id == "" or store.gift_pending: return false
	store.gift_pending = true; store.begin("live_gift")
	var result = await gateway.send_live_gift(stream_id)
	store.gift_pending = false
	if not _object_result(result, "INVALID_GIFT"): return false
	store.balance = int(result.data.get("balance", store.balance)); return _finish_ready()

func create_room() -> bool:
	if store.room_pending: return false
	_room_generation += 1; var generation := _room_generation
	store.room_pending = true; store.begin("create_room")
	var result = await gateway.create_room()
	if generation == _room_generation: store.room_pending = false
	return _accept_room_result(result, generation)

func join_room(code: String) -> bool:
	code = code.strip_edges(); if code == "" or store.room_pending: return false
	_room_generation += 1; var generation := _room_generation
	store.room_pending = true; store.begin("join_room")
	var result = await gateway.join_room(code)
	if generation == _room_generation: store.room_pending = false
	return _accept_room_result(result, generation)

func open_room(room_id: String) -> bool:
	room_id = room_id.strip_edges(); if room_id == "": return false
	_room_generation += 1; var generation := _room_generation; store.room_pending = true; store.begin("room")
	var result = await gateway.get_room(room_id)
	if generation == _room_generation: store.room_pending = false
	return _accept_room_result(result, generation, room_id)

func poll_room() -> bool:
	var room_id := str(store.room.get("id", "")); if room_id == "" or store.room_pending: return false
	var generation := _room_generation; store.room_pending = true
	var result = await gateway.get_room(room_id)
	if generation == _room_generation: store.room_pending = false
	return _accept_room_result(result, generation, room_id)

func set_room_ready(ready: bool) -> bool:
	var room_id := str(store.room.get("id", "")); if room_id == "" or store.room_pending: return false
	var generation := _room_generation; store.room_pending = true; store.begin("room_ready")
	var result = await gateway.set_room_ready(room_id, ready)
	if generation == _room_generation: store.room_pending = false
	return _accept_room_result(result, generation, room_id)

func start_room() -> bool:
	var room_id := str(store.room.get("id", "")); if room_id == "" or store.room_pending: return false
	var generation := _room_generation; store.room_pending = true; store.begin("start_room")
	var result = await gateway.start_room(room_id)
	if generation == _room_generation: store.room_pending = false
	return _accept_room_result(result, generation, room_id)

func load_replay(game_id: String, user_id: String) -> bool:
	if game_id == "" or user_id == "": return false
	_replay_generation += 1; var generation := _replay_generation; store.begin("replay")
	var result = await gateway.replay(game_id, user_id)
	if generation != _replay_generation: return false
	if not _object_result(result, "INVALID_REPLAY"): return false
	if not result.data.get("frames", null) is Array: return _invalid("INVALID_REPLAY", "Replay frames must be an array")
	store.replay = result.data.duplicate(true); store.replay_revision += 1; return _finish_ready()

func load_replay_leaderboard(game_id: String) -> bool:
	if game_id == "": return false
	var generation := int(_leaderboard_generation_by_game.get(game_id, 0)) + 1
	_leaderboard_generation_by_game[game_id] = generation; store.begin("replay_leaderboard")
	var result = await gateway.replay_leaderboard(game_id)
	if generation != int(_leaderboard_generation_by_game.get(game_id, 0)): return false
	if not _items_result(result, "INVALID_REPLAY_LEADERBOARD"): return false
	store.replay_leaderboard_by_game[game_id] = result.data.items.duplicate(true)
	return _ready_collection(store.replay_leaderboard_by_game[game_id])

func _accept_room_result(result: Variant, generation: int, expected_id: String = "") -> bool:
	if generation != _room_generation: return false
	if not _object_result(result, "INVALID_ROOM"): return false
	if not result.data.get("members", null) is Array: return _invalid("INVALID_ROOM", "Room members must be an array")
	if expected_id != "" and str(result.data.get("id", "")) != expected_id: return _invalid("INVALID_ROOM", "Room response id does not match request")
	store.room = result.data.duplicate(true); store.room_revision += 1; return _finish_ready()

func _items_result(result: Variant, code: String) -> bool:
	if not _object_result(result, code): return false
	if not result.data.get("items", null) is Array: return _invalid(code, "Response must contain items")
	return true

func _object_result(result: Variant, code: String) -> bool:
	if not result.ok: store.fail(result); return false
	if not result.data is Dictionary: return _invalid(code, "Response must be an object")
	return true

func _invalid(code: String, message: String) -> bool:
	store.fail(ApiResultScript.unexpected(code, message)); return false

func _finish_ready() -> bool: store.ready(); return true
func _ready_collection(items: Array) -> bool: store.ready("empty" if items.is_empty() else "ready"); return true
