class_name CommunityApi
extends RefCounted

var _transport: Variant

func _init(transport: Variant) -> void: _transport = transport

func list_comments(game_id: String): return await _request_get("/api/v1/games/%s/comments" % game_id.uri_encode())
func add_comment(game_id: String, content: String): return await _post("/api/v1/games/%s/comments" % game_id.uri_encode(), {"content":content})
func community(game_id: String): return await _request_get("/api/v1/games/%s/community" % game_id.uri_encode())
func rate_game(game_id: String, value: int): return await _post("/api/v1/games/%s/community/rating" % game_id.uri_encode(), {"value":value})
func create_post(game_id: String, content: String): return await _post("/api/v1/games/%s/community/posts" % game_id.uri_encode(), {"content":content})
func set_like(game_id: String, liked: bool):
	var path := "/api/v1/games/%s/like" % game_id.uri_encode()
	return await _transport.request(HTTPClient.METHOD_POST if liked else HTTPClient.METHOD_DELETE, path, {} if liked else null)
func set_favorite(game_id: String, favorite: bool):
	var path := "/api/v1/games/%s/favorite" % game_id.uri_encode()
	return await _transport.request(HTTPClient.METHOD_POST if favorite else HTTPClient.METHOD_DELETE, path, {} if favorite else null)
func favorites(): return await _request_get("/api/v1/favorites")
func activity(lang: String = "zh"): return await _request_get("/api/v1/activity?lang=%s" % lang.uri_encode())
func conversations(lang: String = "zh"): return await _request_get("/api/v1/messages/conversations?lang=%s" % lang.uri_encode())
func conversation_messages(handle: String): return await _request_get("/api/v1/conversations/%s/messages" % handle.uri_encode())
func send_message(handle: String, text: String): return await _post("/api/v1/conversations/%s/messages" % handle.uri_encode(), {"text":text})
func set_follow(handle: String, following: bool):
	var path := "/api/v1/follow/%s" % handle.uri_encode()
	return await _transport.request(HTTPClient.METHOD_POST if following else HTTPClient.METHOD_DELETE, path, {} if following else null)
func add_friend(handle: String): return await _post("/api/v1/friends/%s" % handle.uri_encode(), {})
func follow(kind: String, lang: String = "zh"): return await _request_get("/api/v1/follow?type=%s&lang=%s" % [kind.uri_encode(), lang.uri_encode()])
func friend_suggestions(lang: String = "zh"): return await _request_get("/api/v1/friends/suggestions?lang=%s" % lang.uri_encode())
func following(user_id: String): return await _request_get("/api/v1/users/%s/following" % user_id.uri_encode())

func _request_get(path: String): return await _transport.request(HTTPClient.METHOD_GET, path)
func _post(path: String, body: Dictionary): return await _transport.request(HTTPClient.METHOD_POST, path, body)
