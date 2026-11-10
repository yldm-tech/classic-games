class_name CatalogCoordinator
extends Node

const ApiResultScript := preload("res://core/http/api_result.gd")

var gateway: Variant
var store: CatalogStore
var _collection_generation := 0

func _init(p_gateway: Variant, p_store: CatalogStore) -> void:
	gateway = p_gateway
	store = p_store

func load_games(query: Dictionary = {}) -> bool:
	_collection_generation += 1
	var generation := _collection_generation
	var normalized := query.duplicate(true)
	if not normalized.has("lang"):
		normalized["lang"] = "zh"
	store.begin_collection(normalized)
	var result = await gateway.list_games(normalized) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	if generation != _collection_generation:
		return false
	return _complete_collection(result, false)

func load_next_page() -> bool:
	if not store.begin_paging():
		return false
	var generation := _collection_generation
	var next_query := store.query.duplicate(true)
	next_query["cursor"] = store.next_cursor
	var result
	if str(next_query.get("q", "")) != "":
		var search_options := next_query.duplicate(true)
		var search_query := str(search_options.get("q", ""))
		search_options.erase("q")
		result = await gateway.search_games(search_query, search_options)
	else:
		result = await gateway.list_games(next_query)
	if generation != _collection_generation:
		return false
	return _complete_collection(result, true)

## Loads a page for a screen-owned query without relying on the shared store's last query.
func load_page(query:Dictionary,cursor:String)->Dictionary:
	if cursor=="":return {"ok":false,"items":[],"next_cursor":""}
	var owned:=query.duplicate(true);owned["cursor"]=cursor
	return await fetch_collection(owned)

## Returns a consumer-owned collection snapshot without committing shared list state.
func fetch_collection(query:Dictionary)->Dictionary:
	var owned:=query.duplicate(true)
	if gateway==null:return {"ok":false,"items":[],"next_cursor":str(owned.get("cursor","")),"kind":"offline","message":"Catalog service unavailable"}
	var result
	if str(owned.get("q",""))!="":
		var q:=str(owned.get("q",""));owned.erase("q");result=await gateway.search_games(q,owned)
	else:result=await gateway.list_games(owned)
	if not result.ok:return {"ok":false,"items":[],"next_cursor":str(owned.get("cursor","")),"kind":result.kind,"message":result.message}
	if not result.data is Dictionary or not result.data.get("items",null) is Array:
		return {"ok":false,"items":[],"next_cursor":str(owned.get("cursor","")),"kind":"unexpected","message":"Catalog response did not contain an item collection"}
	return {"ok":true,"items":result.data.items.duplicate(true),"next_cursor":str(result.data.get("next_cursor",""))}

func search(raw_query: String, options: Dictionary = {}) -> bool:
	var normalized_query := raw_query.strip_edges()
	if normalized_query == "":
		return await load_games(options)
	_collection_generation += 1
	var generation := _collection_generation
	var owned_query := options.duplicate(true)
	owned_query["q"] = normalized_query
	if not owned_query.has("lang"):
		owned_query["lang"] = "zh"
	store.begin_collection(owned_query)
	var gateway_options := owned_query.duplicate(true)
	gateway_options.erase("q")
	var result = await gateway.search_games(normalized_query, gateway_options) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	if generation != _collection_generation:
		return false
	return _complete_collection(result, false)

func load_game(game_id: String, lang: String = "zh") -> bool:
	store.begin_resource()
	var result = await gateway.game(game_id, lang) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	return _complete_resource("detail", result, false)

func load_game_lineage(game_id: String) -> bool:
	store.begin_resource()
	var result = await gateway.game_lineage(game_id) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	return _complete_resource("game_lineage", result, true)

func load_game_fork_tree(game_id: String) -> bool:
	store.begin_resource()
	var result = await gateway.game_fork_tree(game_id) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	return _complete_resource("fork_tree", result, false)

func load_mod_lineage(mod_id: String) -> bool:
	store.begin_resource()
	var result = await gateway.mod_lineage(mod_id) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	return _complete_resource("mod_lineage", result, true)

func load_ranking(kind: String, options: Dictionary = {}) -> bool:
	store.begin_resource()
	var result = await gateway.ranking(kind, options) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	return _complete_resource("ranking", result, true)

func load_profile(user_id: String, lang: String = "zh") -> bool:
	store.begin_resource()
	var result = await gateway.user_profile(user_id, lang) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	return _complete_resource("profile", result, false)

func load_user_games(user_id: String, kind: String, lang: String = "zh") -> bool:
	store.begin_resource()
	var result = await gateway.user_games(user_id, kind, lang) if gateway != null else ApiResultScript.offline("Catalog service unavailable")
	return _complete_resource("profile_games", result, true)

func _complete_collection(result: Variant, append: bool) -> bool:
	if not result.ok:
		store.fail(result)
		return false
	if not result.data is Dictionary or not result.data.get("items", []) is Array:
		store.fail(ApiResultScript.unexpected("INVALID_CATALOG_COLLECTION", "Catalog response did not contain an item collection", result.status))
		return false
	store.complete_collection(result.data, append)
	return true

func _complete_resource(slot: String, result: Variant, unwrap_items: bool) -> bool:
	if not result.ok:
		store.fail(result)
		return false
	if not result.data is Dictionary:
		store.fail(ApiResultScript.unexpected("INVALID_CATALOG_RESOURCE", "Catalog response did not contain an object", result.status))
		return false
	var value: Variant = result.data.get("items", null) if unwrap_items else result.data
	if unwrap_items and not value is Array:
		store.fail(ApiResultScript.unexpected("INVALID_CATALOG_RESOURCE", "Catalog response did not contain items", result.status))
		return false
	store.complete_resource(slot, value)
	return true
