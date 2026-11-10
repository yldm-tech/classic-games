class_name CreationApi
extends RefCounted

var _transport: Variant

func _init(transport: Variant) -> void: _transport = transport

func quota():
	return await _request_get("/api/v1/ai/quota")
func generate_mod(runtime: String, dsl: Dictionary, prompt: String):
	return await _request_post("/api/v1/ai/mod", {"runtime": runtime, "current_dsl": dsl, "prompt": prompt})
func validate_dsl(runtime: String, dsl: Dictionary):
	return await _request_post("/api/v1/ai/validate", {"runtime": runtime, "dsl": dsl})
func auto_balance(runtime: String, dsl: Dictionary, difficulty: int):
	return await _request_post("/api/v1/ai/balance", {"runtime": runtime, "current_dsl": dsl, "target_difficulty": difficulty})
func generate_structure(runtime: String, dsl: Dictionary, prompt: String, count: int, difficulty: int):
	return await _request_post("/api/v1/ai/structure", {"runtime": runtime, "current_dsl": dsl, "prompt": prompt, "count": count, "difficulty": difficulty})
func runtime_schema(name: String, version: String):
	return await _request_get("/api/v1/runtimes/%s/%s/schema" % [name.uri_encode(), version.uri_encode()])
func runtime_baseline(name: String, version: String):
	return await _request_get("/api/v1/runtimes/%s/%s/baseline" % [name.uri_encode(), version.uri_encode()])
func create_mod(runtime: String, parent_id: String, patch: Array, proof: String = ""):
	return await _request_post("/api/v1/mods", {"runtime": runtime, "parent_id": parent_id, "patch": patch, "ai_provenance": proof})
func save_draft(runtime: String, parent_id: String, patch: Array, proof: String = ""):
	return await _request_post("/api/v1/mods", {"runtime": runtime, "parent_id": parent_id, "patch": patch, "ai_provenance": proof, "draft": true})
func drafts(): return await _request_get("/api/v1/drafts")
func update_draft(id: String, patch: Array):
	return await _transport.request(HTTPClient.METHOD_PUT, "/api/v1/drafts/%s" % id.uri_encode(), {"patch": patch})
func publish_draft(id: String, title: String, summary: String = "", tags: Array = []):
	return await _request_post("/api/v1/drafts/%s/publish" % id.uri_encode(), {"title": title, "summary": summary, "tags": tags})
func fork_mod(id: String): return await _request_post("/api/v1/mods/%s/fork" % id.uri_encode(), {})
func effective_dsl(id: String): return await _request_get("/api/v1/mods/%s/dsl" % id.uri_encode())
func game_dsl(id: String): return await _request_get("/api/v1/games/%s/dsl" % id.uri_encode())
func fork_game(id: String): return await _request_post("/api/v1/games/%s/fork" % id.uri_encode(), {})
func my_mods(): return await _request_get("/api/v1/mods/mine")
func my_games(lang: String = "zh"): return await _request_get("/api/v1/games/mine?lang=%s" % lang.uri_encode())
func publish_game(mod_id: String, title: String, category: String = ""):
	return await _request_post("/api/v1/games", {"mod_id": mod_id, "title": title, "category": category, "ai_generated": false})
func delist_game(id: String): return await _request_post("/api/v1/games/%s/delist" % id.uri_encode(), {})
func resubmit_game(id: String): return await _request_post("/api/v1/games/%s/resubmit" % id.uri_encode(), {})
func decide_game(id: String, approve: bool): return await _request_post("/api/v1/games/%s/decision" % id.uri_encode(), {"approve": approve})
func moderation_queue(cursor: String = "", limit: int = 20):
	return await _request_get("/api/v1/moderation/queue?cursor=%s&limit=%d" % [cursor.uri_encode(), limit])

func _request_get(path: String): return await _transport.request(HTTPClient.METHOD_GET, path)
func _request_post(path: String, body: Dictionary): return await _transport.request(HTTPClient.METHOD_POST, path, body)
