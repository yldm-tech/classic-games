extends SceneTree

const ApiResultScript := preload("res://core/http/api_result.gd")
const CommunityApiScript := preload("res://features/community/community_api.gd")
const CommunityStoreScript := preload("res://features/community/community_store.gd")
const CommunityCoordinatorScript := preload("res://features/community/community_coordinator.gd")
const MessagesScreenScript:=preload("res://features/community/messages_screen.gd")
const AppStateScript:=preload("res://shell/state/app_state.gd")

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
	var like_result = ApiResultScript.success(200, {"liked":true})
	var like_gate: Gate
	var send_gate: Gate
	var activity_gate: Gate
	var activity_gates:Array=[]
	var activity_results:Array=[]
	var activity_calls:=0
	var conversation_results:Array=[]
	var conversation_calls:=0
	var send_calls := 0
	var message_gates: Dictionary = {}
	func list_comments(_game_id: String): return ApiResultScript.success(200, {"items":[{"content":"hello"}]})
	func add_comment(_game_id: String, content: String): return ApiResultScript.success(201, {"content":content})
	func community(_game_id: String): return ApiResultScript.success(200, {"my_rating":2, "count":1, "average":2.0, "posts":[]})
	func rate_game(_game_id: String, value: int): return ApiResultScript.success(200, {"my_rating":value, "count":2, "average":3.5})
	func create_post(_game_id: String, content: String): return ApiResultScript.success(201, {"id":"post-1", "content":content})
	func set_like(_game_id: String, _liked: bool):
		if like_gate != null: await like_gate.released
		return like_result
	func set_favorite(_game_id: String, _favorite: bool): return ApiResultScript.success(200, {})
	func favorites(): return ApiResultScript.success(200, {"items":["game-1"]})
	func activity(_lang: String):
		var index:=activity_calls;activity_calls+=1
		if index<activity_gates.size() and activity_gates[index]!=null:await (activity_gates[index] as Gate).released
		elif activity_gate != null: await activity_gate.released
		return activity_results[index] if index<activity_results.size() else ApiResultScript.success(200, {"items":[{"title":"notice"}]})
	func conversations(_lang: String):
		var index:=conversation_calls;conversation_calls+=1
		return conversation_results[index] if index<conversation_results.size() else ApiResultScript.success(200,{"items":[{"handle":"@a"}]})
	func conversation_messages(handle: String):
		if message_gates.has(handle): await (message_gates[handle] as Gate).released
		return ApiResultScript.success(200, {"items":[{"text":handle, "mine":false}]})
	func send_message(handle: String, text: String):
		send_calls += 1
		if send_gate != null: await send_gate.released
		return ApiResultScript.success(201, {"items":[{"text":text, "mine":true}], "handle":handle})
	func set_follow(_handle: String, following: bool): return ApiResultScript.success(200, {"following":following})
	func add_friend(handle: String): return ApiResultScript.success(201, {"handle":handle})
	func follow(kind: String, _lang: String): return ApiResultScript.success(200, {"items":[{"handle":"@" + kind}]})
	func friend_suggestions(_lang: String): return ApiResultScript.success(200, {"items":[{"handle":"@suggested"}]})
	func following(user_id: String): return ApiResultScript.success(200, {"items":[user_id]})

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await _test_api_owns_community_paths()
	await _test_comments_snapshot_rating_and_post()
	await _test_optimistic_like_rolls_back()
	await _test_inbox_follow_friend_and_favorites()
	await _test_same_locale_inbox_refresh_is_coalesced()
	await _test_inbox_refresh_rejects_stale_locale()
	await _test_stale_chat_response_is_rejected()
	await _test_like_and_send_writes_are_serialized()
	await _test_cross_resource_loads_keep_independent_revisions()
	await _test_messages_screen_renders_suggestions()
	print("community_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_api_owns_community_paths() -> void:
	var transport := FakeTransport.new()
	var api = CommunityApiScript.new(transport)
	await api.list_comments("game/1"); await api.add_comment("game/1", "hi")
	await api.community("game/1"); await api.rate_game("game/1", 4); await api.create_post("game/1", "post")
	await api.set_like("game/1", true); await api.set_like("game/1", false)
	await api.set_favorite("game/1", true); await api.set_favorite("game/1", false); await api.favorites()
	await api.activity("ja"); await api.conversations("ja"); await api.conversation_messages("@a/b"); await api.send_message("@a/b", "yo")
	await api.set_follow("@a/b", true); await api.set_follow("@a/b", false); await api.add_friend("@a/b")
	await api.follow("followers", "ja"); await api.friend_suggestions("ja"); await api.following("user/1")
	var paths: Array = transport.requests.map(func(request: Dictionary): return request.path)
	_check("community api owns encoded resource paths", paths == [
		"/api/v1/games/game%2F1/comments", "/api/v1/games/game%2F1/comments",
		"/api/v1/games/game%2F1/community", "/api/v1/games/game%2F1/community/rating", "/api/v1/games/game%2F1/community/posts",
		"/api/v1/games/game%2F1/like", "/api/v1/games/game%2F1/like", "/api/v1/games/game%2F1/favorite", "/api/v1/games/game%2F1/favorite", "/api/v1/favorites",
		"/api/v1/activity?lang=ja", "/api/v1/messages/conversations?lang=ja", "/api/v1/conversations/%40a%2Fb/messages", "/api/v1/conversations/%40a%2Fb/messages",
		"/api/v1/follow/%40a%2Fb", "/api/v1/follow/%40a%2Fb", "/api/v1/friends/%40a%2Fb", "/api/v1/follow?type=followers&lang=ja",
		"/api/v1/friends/suggestions?lang=ja", "/api/v1/users/user%2F1/following"])
	_check("community api preserves write methods", transport.requests[5].method == HTTPClient.METHOD_POST
		and transport.requests[6].method == HTTPClient.METHOD_DELETE and transport.requests[12].method == HTTPClient.METHOD_GET)

func _test_comments_snapshot_rating_and_post() -> void:
	var fixture := _fixture()
	_check("comments load and post are coordinator-owned", await fixture.coordinator.load_comments("game-1")
		and fixture.store.comments_by_game["game-1"][0].content == "hello"
		and await fixture.coordinator.post_comment("game-1", "new") and fixture.store.comments_by_game["game-1"][0].content == "new")
	_check("community snapshot rating and post are coordinator-owned", await fixture.coordinator.load_community("game-1")
		and await fixture.coordinator.rate_game("game-1", 5) and fixture.store.community_by_game["game-1"].my_rating == 5
		and await fixture.coordinator.create_post("game-1", "post") and fixture.store.community_by_game["game-1"].posts[0].content == "post")
	fixture.free_all.call()

func _test_optimistic_like_rolls_back() -> void:
	var fixture := _fixture()
	fixture.gateway.like_result = ApiResultScript.offline("down")
	fixture.gateway.like_gate = Gate.new()
	fixture.coordinator.set_like("game-1", true)
	_check("like updates optimistically before gateway completion", fixture.store.liked_by_game.get("game-1", false))
	fixture.gateway.like_gate.released.emit()
	await process_frame
	_check("failed optimistic like rolls back", not fixture.store.liked_by_game.get("game-1", false) and fixture.store.status == "offline")
	fixture.free_all.call()

func _test_inbox_follow_friend_and_favorites() -> void:
	var fixture := _fixture()
	_check("inbox loads activity and conversations", await fixture.coordinator.load_inbox("zh")
		and fixture.store.activity[0].title == "notice" and fixture.store.conversations[0].handle == "@a")
	_check("follow lists and friends are coordinator-owned", await fixture.coordinator.load_follow_lists("zh")
		and fixture.store.following[0].handle == "@following" and fixture.store.followers[0].handle == "@followers"
		and await fixture.coordinator.add_friend("@friend") and fixture.store.added_friends.has("@friend"))
	_check("favorites are coordinator-owned", await fixture.coordinator.load_favorites() and fixture.store.favorite_ids == ["game-1"])
	_check("follow list initializes is_following", fixture.coordinator.is_following("@following") and not fixture.coordinator.is_following("@unknown"))
	_check("favorite helper matches store ids", fixture.coordinator.is_favorite("game-1") and not fixture.coordinator.is_favorite("missing"))
	fixture.free_all.call()

func _test_same_locale_inbox_refresh_is_coalesced()->void:
	var fixture:=_fixture();var gate:=Gate.new();fixture.gateway.activity_gate=gate
	fixture.coordinator.load_inbox("zh");fixture.coordinator.load_inbox("zh");await process_frame
	_check("same-locale inbox waiters share one gateway flight",fixture.gateway.activity_calls==1 and fixture.gateway.conversation_calls==0)
	gate.released.emit();await process_frame;await process_frame
	_check("coalesced inbox flight commits once",fixture.gateway.activity_calls==1 and fixture.gateway.conversation_calls==1 and fixture.store.inbox_revision==1)
	fixture.free_all.call()

func _test_inbox_refresh_rejects_stale_locale()->void:
	var fixture:=_fixture();var old_gate:=Gate.new();fixture.gateway.activity_gates=[old_gate,null];fixture.gateway.activity_results=[ApiResultScript.success(200,{"items":[{"title":"old"}]}),ApiResultScript.success(200,{"items":[{"title":"new"}]})];fixture.gateway.conversation_results=[ApiResultScript.success(200,{"items":[{"handle":"@new"}]})]
	fixture.coordinator.load_inbox("zh");_check("new locale inbox can complete while old locale is pending",await fixture.coordinator.load_inbox("ja") and fixture.store.activity[0].title=="new")
	old_gate.released.emit();await process_frame;_check("stale inbox response cannot overwrite new locale or status",fixture.store.activity[0].title=="new" and fixture.store.status=="ready")
	fixture.free_all.call()
	var screen_fixture:=_fixture();var screen_gate:=Gate.new();screen_fixture.gateway.activity_gates=[screen_gate,null];screen_fixture.gateway.activity_results=[ApiResultScript.success(200,{"items":[{"title":"old"}]}),ApiResultScript.success(200,{"items":[{"title":"new"}]})];screen_fixture.gateway.conversation_results=[ApiResultScript.success(200,{"items":[]})];var state=AppStateScript.new();state.save_path="user://messages-race.cfg";var screen=MessagesScreenScript.new(state,screen_fixture.coordinator);root.add_child(screen);screen.refresh();await process_frame;state.locale="ja";screen.refresh();await process_frame;screen_gate.released.emit();await process_frame
	_check("messages async presentation ignores stale refresh completion",screen._async_state=="ready" and screen._activity[0].title=="new")
	screen.free();state.free();screen_fixture.free_all.call()

func _test_stale_chat_response_is_rejected() -> void:
	var fixture := _fixture()
	var old_gate := Gate.new(); fixture.gateway.message_gates["@old"] = old_gate
	fixture.coordinator.open_conversation("@old")
	_check("new chat can supersede an in-flight old chat", await fixture.coordinator.open_conversation("@new") and fixture.store.active_handle == "@new")
	old_gate.released.emit(); await process_frame
	_check("stale chat response cannot overwrite active bubbles", fixture.store.active_handle == "@new"
		and fixture.store.messages_by_handle["@new"][0].text == "@new" and not fixture.store.messages_by_handle.has("@old"))
	fixture.free_all.call()

func _test_like_and_send_writes_are_serialized() -> void:
	var fixture := _fixture()
	fixture.gateway.like_gate = Gate.new(); fixture.gateway.like_result = ApiResultScript.offline("down")
	fixture.coordinator.set_like("game-1", true)
	_check("a second like toggle is rejected while the first is pending", not await fixture.coordinator.set_like("game-1", false)
		and fixture.store.like_pending_by_game.get("game-1", false))
	fixture.gateway.like_gate.released.emit(); await process_frame
	_check("serialized failed like returns to confirmed state", not fixture.store.liked_by_game.get("game-1", false)
		and not fixture.store.like_pending_by_game.get("game-1", false))

	await fixture.coordinator.open_conversation("@a")
	fixture.gateway.send_gate = Gate.new(); fixture.coordinator.send_message("@a", "first")
	_check("a second send is rejected while the first is pending", not await fixture.coordinator.send_message("@a", "second")
		and fixture.gateway.send_calls == 1 and fixture.store.send_pending_by_handle.get("@a", false))
	fixture.gateway.send_gate.released.emit(); await process_frame
	_check("serialized send cannot be overwritten by an older response", fixture.store.messages_by_handle["@a"][0].text == "first"
		and not fixture.store.send_pending_by_handle.get("@a", false))
	fixture.free_all.call()

func _test_cross_resource_loads_keep_independent_revisions() -> void:
	var fixture := _fixture(); fixture.gateway.activity_gate = Gate.new()
	fixture.coordinator.load_inbox("zh")
	_check("follow list can complete while inbox is pending", await fixture.coordinator.load_follow_lists("zh")
		and fixture.store.follow_revision == 1 and fixture.store.inbox_revision == 0)
	fixture.gateway.activity_gate.released.emit(); await process_frame
	_check("inbox completion remains observable after another resource completes", fixture.store.inbox_revision == 1
		and fixture.store.follow_revision == 1 and fixture.store.activity[0].title == "notice")
	fixture.free_all.call()

func _test_messages_screen_renders_suggestions() -> void:
	var fixture := _fixture()
	var state = AppStateScript.new()
	state.save_path = "user://messages-suggestions.cfg"
	var screen = MessagesScreenScript.new(state, fixture.coordinator)
	root.add_child(screen)
	await screen.refresh()
	screen.seg = 2
	screen.rebuild()
	_check("messages friends tab renders coordinator suggestions", screen.find_child("SugHandle", true, false) != null
		and (screen.find_child("SugHandle", true, false) as Label).text == "@suggested")
	screen.free(); state.free(); fixture.free_all.call()

func _fixture() -> Dictionary:
	var gateway := FakeGateway.new(); var store = CommunityStoreScript.new(); var coordinator = CommunityCoordinatorScript.new(gateway, store)
	return {"gateway":gateway, "store":store, "coordinator":coordinator,
		"free_all":func() -> void: coordinator.free(); store.free()}

func _check(label: String, condition: bool) -> void:
	if condition: _passed += 1
	else: _failed += 1; push_error("FAIL: " + label)
