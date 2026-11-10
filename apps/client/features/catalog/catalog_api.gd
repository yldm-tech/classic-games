class_name CatalogApi
extends RefCounted

var _transport: Variant

func _init(transport: Variant) -> void:
	_transport = transport

func list_games(query: Dictionary):
	return await _transport.request(HTTPClient.METHOD_GET, _query_path("/api/v1/games", [
		["lang", query.get("lang", "zh")],
		["sort", query.get("sort", "")],
		["runtime", query.get("runtime", "")],
		["category", query.get("category", "")],
		["ai", query.get("ai", "")],
		["cursor", query.get("cursor", "")],
		["limit", query.get("limit", 0)],
	]))

func search_games(query: String, options: Dictionary):
	return await _transport.request(HTTPClient.METHOD_GET, _query_path("/api/v1/games", [
		["q", query],
		["lang", options.get("lang", "zh")],
		["category", options.get("category", "")],
		["ai", options.get("ai", "")],
		["cursor", options.get("cursor", "")],
		["limit", options.get("limit", 0)],
	]))

func game(game_id: String, lang: String = "zh"):
	return await _transport.request(
		HTTPClient.METHOD_GET,
		"/api/v1/games/%s?lang=%s" % [game_id.uri_encode(), lang.uri_encode()],
	)

func ranking(kind: String, options: Dictionary = {}):
	return await _transport.request(HTTPClient.METHOD_GET, _query_path("/api/v1/ranking", [
		["type", kind],
		["lang", options.get("lang", "zh")],
		["runtime", options.get("runtime", "")],
		["category", options.get("category", "")],
		["limit", options.get("limit", 0)],
	]))

func user_profile(user_id: String, lang: String = "zh"):
	return await _transport.request(
		HTTPClient.METHOD_GET,
		"/api/v1/users/%s/profile?lang=%s" % [user_id.uri_encode(), lang.uri_encode()],
	)

func user_games(user_id: String, kind: String, lang: String = "zh"):
	return await _transport.request(
		HTTPClient.METHOD_GET,
		"/api/v1/users/%s/games?type=%s&lang=%s" % [
			user_id.uri_encode(),
			kind.uri_encode(),
			lang.uri_encode(),
		],
	)

func game_lineage(game_id: String):
	return await _transport.request(HTTPClient.METHOD_GET, "/api/v1/games/%s/lineage" % game_id.uri_encode())

func game_fork_tree(game_id: String):
	return await _transport.request(HTTPClient.METHOD_GET, "/api/v1/games/%s/fork-tree" % game_id.uri_encode())

func mod_lineage(mod_id: String):
	return await _transport.request(HTTPClient.METHOD_GET, "/api/v1/mods/%s/lineage" % mod_id.uri_encode())

func _query_path(base: String, entries: Array) -> String:
	var parts: PackedStringArray = []
	for entry: Array in entries:
		var value: Variant = entry[1]
		if value == null or str(value) == "" or (value is int and value <= 0):
			continue
		parts.append("%s=%s" % [str(entry[0]).uri_encode(), str(value).uri_encode()])
	return base if parts.is_empty() else base + "?" + "&".join(parts)
