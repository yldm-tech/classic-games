class_name CommunityCoordinator
extends Node

const ApiResultScript := preload("res://core/http/api_result.gd")

class ReadFlight:
	extends RefCounted
	signal completed(success:bool)
	var key:String
	var generation:int
	func _init(p_key:String,p_generation:int)->void:key=p_key;generation=p_generation

var gateway: Variant
var store: CommunityStore
var _chat_generation := 0
var _inbox_generation:=0
var _inbox_key:=""
var _inbox_flight:ReadFlight

func _init(p_gateway: Variant, p_store: CommunityStore) -> void:
	gateway = p_gateway; store = p_store

func load_comments(game_id: String) -> bool:
	if game_id == "": return false
	store.begin("comments")
	var result = await gateway.list_comments(game_id)
	if not _items_result(result, "INVALID_COMMENTS"): return false
	store.comments_by_game[game_id] = result.data.items.duplicate(true); return _ready_collection(result.data.items)

func post_comment(game_id: String, content: String) -> bool:
	content = content.strip_edges()
	if game_id == "" or content == "": return false
	store.begin("post_comment")
	var result = await gateway.add_comment(game_id, content)
	if not _object_result(result, "INVALID_COMMENT"): return false
	var comments: Array = store.comments_by_game.get(game_id, []).duplicate(true)
	comments.push_front(result.data.duplicate(true))
	store.comments_by_game[game_id] = comments
	return _ready_collection(comments)

func load_community(game_id: String) -> bool:
	if game_id == "": return false
	store.begin("community")
	var result = await gateway.community(game_id)
	if not _object_result(result, "INVALID_COMMUNITY"): return false
	if not result.data.get("posts", []) is Array: return _invalid("INVALID_COMMUNITY", "Community posts must be an array")
	store.community_by_game[game_id] = result.data.duplicate(true); return _ready_collection(result.data.posts)

func rate_game(game_id: String, value: int) -> bool:
	if game_id == "" or value < 1 or value > 5: return false
	store.begin("rate")
	var result = await gateway.rate_game(game_id, value)
	if not _object_result(result, "INVALID_RATING"): return false
	var snapshot: Dictionary = store.community_by_game.get(game_id, {}).duplicate(true)
	for key: String in ["my_rating", "count", "average"]: snapshot[key] = result.data.get(key, snapshot.get(key, 0))
	store.community_by_game[game_id] = snapshot; return _finish_ready()

func create_post(game_id: String, content: String) -> bool:
	content = content.strip_edges()
	if game_id == "" or content == "": return false
	store.begin("create_post")
	var result = await gateway.create_post(game_id, content)
	if not _object_result(result, "INVALID_POST"): return false
	var snapshot: Dictionary = store.community_by_game.get(game_id, {}).duplicate(true)
	var posts: Array = snapshot.get("posts", []).duplicate(true); posts.push_front(result.data.duplicate(true)); snapshot["posts"] = posts
	store.community_by_game[game_id] = snapshot; return _finish_ready()

func set_like(game_id: String, liked: bool) -> bool:
	if game_id == "" or bool(store.like_pending_by_game.get(game_id, false)): return false
	var previous := bool(store.liked_by_game.get(game_id, false))
	store.like_pending_by_game[game_id] = true; store.liked_by_game[game_id] = liked; store.begin("like")
	var result = await gateway.set_like(game_id, liked)
	store.like_pending_by_game[game_id] = false
	if not result.ok:
		store.liked_by_game[game_id] = previous; store.fail(result); return false
	if not result.data is Dictionary:
		store.liked_by_game[game_id] = previous
		return _invalid("INVALID_LIKE", "Like response must be an object")
	store.liked_by_game[game_id] = bool(result.data.get("liked", liked))
	store.ready(); return true

func set_favorite(game_id: String, favorite: bool) -> bool:
	if game_id == "" or bool(store.favorite_pending_by_game.get(game_id, false)): return false
	var previous := is_favorite(game_id)
	store.favorite_pending_by_game[game_id] = true
	_set_favorite_id(game_id, favorite)
	store.begin("favorite")
	var result = await gateway.set_favorite(game_id, favorite)
	store.favorite_pending_by_game[game_id] = false
	if not result.ok:
		_set_favorite_id(game_id, previous); store.fail(result); return false
	if not result.data is Dictionary:
		_set_favorite_id(game_id, previous)
		return _invalid("INVALID_FAVORITE", "Favorite response must be an object")
	_set_favorite_id(game_id, bool(result.data.get("favorite", favorite)))
	return _finish_ready()

func is_favorite(game_id: String) -> bool:
	return game_id != "" and game_id in store.favorite_ids

func is_following(handle: String) -> bool:
	handle = handle.strip_edges()
	if handle == "": return false
	if store.follow_by_handle.has(handle):
		return bool(store.follow_by_handle[handle])
	for item: Variant in store.following:
		if item is Dictionary and str(item.get("handle", "")) == handle:
			return true
		if str(item) == handle:
			return true
	return false

func _set_favorite_id(game_id: String, favorite: bool) -> void:
	if favorite and game_id not in store.favorite_ids:
		store.favorite_ids.append(game_id)
	if not favorite:
		store.favorite_ids.erase(game_id)

func load_favorites() -> bool:
	store.begin("favorites")
	var result = await gateway.favorites()
	if not _items_result(result, "INVALID_FAVORITES"): return false
	store.favorite_ids = result.data.items.duplicate(true); return _ready_collection(store.favorite_ids)

func load_inbox(lang: String = "zh") -> bool:
	if _inbox_key!=lang:_inbox_key=lang;_inbox_generation+=1
	var generation:=_inbox_generation
	if _inbox_flight!=null and _inbox_flight.key==lang and _inbox_flight.generation==generation:return await _inbox_flight.completed
	var flight:=ReadFlight.new(lang,generation);_inbox_flight=flight
	store.begin("inbox")
	var activity_result = await gateway.activity(lang)
	if generation!=_inbox_generation:return _resolve_inbox(flight,false)
	if not _items_result(activity_result, "INVALID_ACTIVITY"): return _resolve_inbox(flight,false)
	var conversations_result = await gateway.conversations(lang)
	if generation!=_inbox_generation:return _resolve_inbox(flight,false)
	if not _items_result(conversations_result, "INVALID_CONVERSATIONS"): return _resolve_inbox(flight,false)
	store.activity = activity_result.data.items.duplicate(true); store.conversations = conversations_result.data.items.duplicate(true)
	store.inbox_revision += 1
	var success:=_ready_collection(store.activity if not store.activity.is_empty() else store.conversations);return _resolve_inbox(flight,success)

func _resolve_inbox(flight:ReadFlight,success:bool)->bool:
	if _inbox_flight==flight:_inbox_flight=null
	flight.completed.emit(success);return success

func open_conversation(handle: String) -> bool:
	handle = handle.strip_edges(); if handle == "": return false
	_chat_generation += 1; var generation := _chat_generation; store.active_handle = handle; store.begin("messages")
	var result = await gateway.conversation_messages(handle)
	if generation != _chat_generation or store.active_handle != handle: return false
	if not _items_result(result, "INVALID_MESSAGES"): return false
	store.messages_by_handle[handle] = result.data.items.duplicate(true); return _ready_collection(result.data.items)

func send_message(handle: String, text: String) -> bool:
	handle = handle.strip_edges(); text = text.strip_edges()
	if handle == "" or text == "" or handle != store.active_handle or bool(store.send_pending_by_handle.get(handle, false)): return false
	var generation := _chat_generation; store.send_pending_by_handle[handle] = true; store.begin("send_message")
	var result = await gateway.send_message(handle, text)
	store.send_pending_by_handle[handle] = false
	if generation != _chat_generation or store.active_handle != handle: store.touch(); return false
	if not _items_result(result, "INVALID_MESSAGES"): return false
	store.messages_by_handle[handle] = result.data.items.duplicate(true); return _ready_collection(result.data.items)

func set_follow(handle: String, following: bool) -> bool:
	handle = handle.strip_edges(); if handle == "": return false
	store.begin("follow")
	var result = await gateway.set_follow(handle, following)
	if not result.ok: store.fail(result); return false
	store.follow_by_handle[handle] = following; return _finish_ready()

func add_friend(handle: String) -> bool:
	handle = handle.strip_edges(); if handle == "": return false
	store.begin("add_friend")
	var result = await gateway.add_friend(handle)
	if not _object_result(result, "INVALID_FRIEND"): return false
	store.added_friends[handle] = true; return _finish_ready()

func load_follow_lists(lang: String = "zh") -> bool:
	store.begin("follow_lists")
	var following_result = await gateway.follow("following", lang)
	if not _items_result(following_result, "INVALID_FOLLOW_LIST"): return false
	var followers_result = await gateway.follow("followers", lang)
	if not _items_result(followers_result, "INVALID_FOLLOW_LIST"): return false
	store.following = following_result.data.items.duplicate(true); store.followers = followers_result.data.items.duplicate(true)
	store.follow_revision += 1
	return _ready_collection(store.following if not store.following.is_empty() else store.followers)

func load_suggestions(lang: String = "zh") -> bool:
	store.begin("suggestions")
	var result = await gateway.friend_suggestions(lang)
	if not _items_result(result, "INVALID_SUGGESTIONS"): return false
	store.suggestions = result.data.items.duplicate(true); return _ready_collection(store.suggestions)

func load_following(user_id: String) -> bool:
	store.begin("user_following")
	var result = await gateway.following(user_id)
	if not _items_result(result, "INVALID_FOLLOWING"): return false
	store.following = result.data.items.duplicate(true); return _ready_collection(store.following)

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
