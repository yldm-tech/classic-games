extends SceneTree

const ApiResultScript := preload("res://core/http/api_result.gd")
const CreationApiScript := preload("res://features/creation/creation_api.gd")
const CreationStoreScript := preload("res://features/creation/creation_store.gd")
const CreationCoordinatorScript := preload("res://features/creation/creation_coordinator.gd")
const CreationSessionPortScript := preload("res://features/creation/creation_session_port.gd")
const CreatorSessionAdapterScript := preload("res://features/creation/creator_session_adapter.gd")

class Gate:
	extends RefCounted
	signal released

class FakeTransport:
	extends RefCounted
	var requests: Array[Dictionary] = []
	func request(method: int, path: String, body: Variant = null):
		requests.append({"method": method, "path": path, "body": body})
		return ApiResultScript.success(200, {})

class FakeSession:
	extends CreationSessionPort
	var document := {"player": {"sprite": "plane"}}
	var patches: Array = [[{"op": "replace", "path": "/player/sprite", "value": "cat"}]]
	var loaded_baseline: Dictionary = {}
	var loaded_runtime := ""
	var applied: Array = []
	var previews: Array = []
	var accept_patch := true
	var accept_load := true
	var current_revision := 1

	func can_load(_runtime_ref: String, _baseline: Dictionary, _document: Dictionary) -> bool:
		return accept_load

	func load_baseline(runtime_ref: String, baseline: Dictionary) -> bool:
		loaded_runtime = runtime_ref
		loaded_baseline = baseline.duplicate(true)
		document = baseline.duplicate(true)
		patches = []
		current_revision = 0
		return true
	func load_document(next: Dictionary) -> bool:
		document = next.duplicate(true)
		patches = []
		current_revision = 0
		return true
	func current() -> Dictionary: return document.duplicate(true)
	func apply_patch(ops: Array) -> bool:
		if not accept_patch: return false
		applied.append(ops.duplicate(true))
		patches.append(ops.duplicate(true))
		current_revision += 1
		return true
	func apply_document(next: Dictionary) -> bool:
		document = next.duplicate(true)
		patches.append([{"op": "replace", "path": "/player", "value": next.get("player", {})}])
		current_revision += 1
		return true
	func is_dirty() -> bool: return not patches.is_empty()
	func revision() -> int: return current_revision
	func patches_since_revision(base_revision: int) -> Array:
		var count := current_revision - base_revision
		return [] if count <= 0 else patches.slice(patches.size() - count)
	func record_patch(ops: Array) -> void:
		patches.append(ops.duplicate(true))
		current_revision += 1
	func preview(runtime_ref: String, dsl: Dictionary) -> bool:
		previews.append({"runtime": runtime_ref, "dsl": dsl.duplicate(true)})
		return true

class FakeGateway:
	extends RefCounted
	var generation_gate: Gate
	var validation_gate: Gate
	var save_gate: Gate
	var runtime_gate: Gate
	var create_gate: Gate
	var calls: Array[String] = []
	var save_parents: Array[String] = []
	var create_parents: Array[String] = []
	var published_draft_ids: Array[String] = []
	var create_mod_calls := 0
	var publish_game_calls := 0
	var fork_mod_calls := 0
	var publish_results: Array = []
	var generation_result: Variant
	var effective_result: Variant
	func runtime_schema(_name: String, _version: String):
		if runtime_gate != null: await runtime_gate.released
		return ApiResultScript.success(200, {"title": "schema"})
	func runtime_baseline(_name: String, _version: String): return ApiResultScript.success(200, {"player": {"sprite": "plane"}})
	func effective_dsl(_id: String):
		return effective_result if effective_result != null else ApiResultScript.success(200, {"player": {"sprite": "cat"}})
	func generate_mod(_runtime: String, _dsl: Dictionary, _prompt: String):
		calls.append("generate")
		if generation_gate != null: await generation_gate.released
		if generation_result != null: return generation_result
		return ApiResultScript.success(200, {"dsl_patch": [{"op": "replace", "path": "/player/sprite", "value": "mage"}], "new_dsl": {"player": {"sprite": "mage"}}, "provenance": "proof"})
	func validate_dsl(_runtime: String, _dsl: Dictionary):
		if validation_gate != null: await validation_gate.released
		return ApiResultScript.success(200, {"valid": true})
	func auto_balance(_runtime: String, _dsl: Dictionary, _difficulty: int): return ApiResultScript.success(200, {"dsl_patch": [{"op": "add", "path": "/difficulty", "value": 5}], "new_dsl": {"difficulty": 5}})
	func generate_structure(_runtime: String, _dsl: Dictionary, _prompt: String, _count: int, _difficulty: int): return ApiResultScript.success(200, {"dsl_patch": [{"op": "add", "path": "/waves", "value": {}}], "new_dsl": {"waves": {}}})
	func save_draft(_runtime: String, parent: String, _patch: Array, _proof: String):
		save_parents.append(parent)
		if save_gate != null: await save_gate.released
		return ApiResultScript.success(201, {"id": "draft-1"})
	func update_draft(_id: String, _patch: Array): return ApiResultScript.success(201, {"id": "draft-2", "parent_id": "draft-1"})
	func publish_draft(id: String, _title: String, _summary: String, _tags: Array):
		published_draft_ids.append(id)
		return ApiResultScript.success(201, {"id": "game-draft", "status": "reviewing"})
	func fork_mod(_id: String):
		fork_mod_calls += 1
		return ApiResultScript.success(201, {"id": "mod-fork"})
	func fork_game(_id: String): return ApiResultScript.success(201, {"id": "game-fork"})
	func create_mod(_runtime: String, parent: String, _patch: Array, _proof: String):
		create_mod_calls += 1
		create_parents.append(parent)
		if create_gate != null: await create_gate.released
		return ApiResultScript.success(201, {"id": "mod-1"})
	func publish_game(_mod: String, _title: String, _category: String):
		publish_game_calls += 1
		return publish_results.pop_front() if not publish_results.is_empty() else ApiResultScript.success(201, {"id": "game-1", "status": "reviewing"})
	func delist_game(_id: String): return ApiResultScript.success(200, {"status": "delisted"})
	func resubmit_game(_id: String): return ApiResultScript.success(200, {"status": "reviewing"})
	func decide_game(_id: String, _approve: bool): return ApiResultScript.success(200, {"status": "published"})
	func moderation_queue(_cursor: String, _limit: int): return ApiResultScript.success(200, {"items": [{"id": "game-1"}]})
	func my_games(_lang: String): return ApiResultScript.success(200, {"items": [{"id": "game-1"}]})
	func drafts(): return ApiResultScript.success(200, {"items": [{"id": "draft-1"}]})
	func my_mods(): return ApiResultScript.success(200, {"items": [{"id": "mod-1"}]})
	func quota(): return ApiResultScript.success(200, {"used": 2, "remaining": 18, "limit": 20})

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await _test_gateway_owns_creation_paths()
	await _test_runtime_generation_and_preview_workflow()
	await _test_import_and_work_loading_are_coordinator_owned()
	await _test_published_work_is_preflighted_before_fork()
	await _test_concurrent_generation_is_rejected()
	await _test_local_edits_reject_stale_ai_results()
	await _test_generation_failures_release_the_lock()
	await _test_async_context_switches_are_serialized()
	await _test_save_tokens_and_fork_chain()
	await _test_undo_and_branch_edits_have_new_revisions()
	await _test_draft_publish_and_review_workflow()
	await _test_publish_retry_reuses_mod()
	await _test_local_edit_before_publish_stage_is_stale()
	await _test_existing_draft_publish_preserves_parent_chain()
	await _test_real_session_adapter_tracks_undo_branches()
	print("creation_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_gateway_owns_creation_paths() -> void:
	var transport := FakeTransport.new()
	var api = CreationApiScript.new(transport)
	await api.runtime_schema("tower defense", "1.0.0")
	await api.runtime_baseline("survivor", "1.0.0")
	await api.generate_mod("shooter@1.0.0", {}, "cat")
	await api.validate_dsl("shooter@1.0.0", {})
	await api.auto_balance("shooter@1.0.0", {}, 5)
	await api.generate_structure("shooter@1.0.0", {}, "waves", 3, 4)
	await api.create_mod("shooter@1.0.0", "parent", [], "proof")
	await api.save_draft("shooter@1.0.0", "parent", [], "proof")
	await api.drafts()
	await api.update_draft("draft/1", [])
	await api.publish_draft("draft/1", "title", "summary", ["tag"])
	await api.fork_mod("mod/1")
	await api.effective_dsl("mod/1")
	await api.game_dsl("game/1")
	await api.fork_game("game/1")
	await api.my_mods()
	await api.my_games("ja")
	await api.publish_game("mod/1", "title", "arcade")
	await api.delist_game("game/1")
	await api.resubmit_game("game/1")
	await api.decide_game("game/1", true)
	await api.moderation_queue("next page", 20)
	await api.quota()
	var paths: Array = transport.requests.map(func(request: Dictionary): return request.path)
	_check("creation gateway owns runtime and AI paths", paths.slice(0, 6) == [
		"/api/v1/runtimes/tower%20defense/1.0.0/schema", "/api/v1/runtimes/survivor/1.0.0/baseline",
		"/api/v1/ai/mod", "/api/v1/ai/validate", "/api/v1/ai/balance", "/api/v1/ai/structure"])
	_check("creation gateway owns draft and fork paths", paths.slice(6, 15) == [
		"/api/v1/mods", "/api/v1/mods", "/api/v1/drafts", "/api/v1/drafts/draft%2F1",
		"/api/v1/drafts/draft%2F1/publish", "/api/v1/mods/mod%2F1/fork", "/api/v1/mods/mod%2F1/dsl",
		"/api/v1/games/game%2F1/dsl", "/api/v1/games/game%2F1/fork"])
	_check("creation gateway owns publish and review paths", paths.slice(15) == [
		"/api/v1/mods/mine", "/api/v1/games/mine?lang=ja", "/api/v1/games",
		"/api/v1/games/game%2F1/delist", "/api/v1/games/game%2F1/resubmit",
		"/api/v1/games/game%2F1/decision", "/api/v1/moderation/queue?cursor=next%20page&limit=20",
		"/api/v1/ai/quota"])
	_check("creation gateway uses write methods", transport.requests[9].method == HTTPClient.METHOD_PUT
		and transport.requests[8].method == HTTPClient.METHOD_GET and transport.requests[17].method == HTTPClient.METHOD_POST)
	_check("creation gateway distinguishes draft and publish payloads", transport.requests[7].body.draft == true
		and transport.requests[17].body.ai_generated == false and transport.requests[20].body.approve == true)
	_check("creation gateway preserves AI payload contracts",
		transport.requests[2].body == {"runtime": "shooter@1.0.0", "current_dsl": {}, "prompt": "cat"}
		and transport.requests[3].body == {"runtime": "shooter@1.0.0", "dsl": {}}
		and transport.requests[4].body == {"runtime": "shooter@1.0.0", "current_dsl": {}, "target_difficulty": 5}
		and transport.requests[5].body == {"runtime": "shooter@1.0.0", "current_dsl": {}, "prompt": "waves", "count": 3, "difficulty": 4})
	_check("creation gateway preserves immutable draft payload contracts",
		transport.requests[6].body == {"runtime": "shooter@1.0.0", "parent_id": "parent", "patch": [], "ai_provenance": "proof"}
		and transport.requests[7].body == {"runtime": "shooter@1.0.0", "parent_id": "parent", "patch": [], "ai_provenance": "proof", "draft": true}
		and transport.requests[9].body == {"patch": []}
		and transport.requests[10].body == {"title": "title", "summary": "summary", "tags": ["tag"]})
	_check("creation gateway preserves game payload contracts",
		transport.requests[17].body == {"mod_id": "mod/1", "title": "title", "category": "arcade", "ai_generated": false}
		and transport.requests[20].body == {"approve": true})

func _test_runtime_generation_and_preview_workflow() -> void:
	var fixture := _fixture()
	_check("runtime graph loads schema and baseline", await fixture.coordinator.load_runtime("shooter@1.0.0") and fixture.store.schema.title == "schema" and fixture.session.loaded_runtime == "shooter@1.0.0")
	_check("effective DSL loads through the session port", await fixture.coordinator.load_effective_dsl("mod-1") and fixture.session.document.player.sprite == "cat")
	_check("AI generation applies patch and provenance", await fixture.coordinator.generate("make mage", "shooter@1.0.0") and fixture.session.applied.size() == 1 and fixture.store.ai_provenance == "proof")
	_check("validation has explicit ready state", await fixture.coordinator.validate_current("shooter@1.0.0") and fixture.store.validation.valid)
	_check("balance and structure apply through one workflow", await fixture.coordinator.balance(5, "shooter@1.0.0") and await fixture.coordinator.structure("waves", 3, 4, "shooter@1.0.0") and fixture.session.applied.size() == 3)
	_check("preview is delegated through the session port", fixture.coordinator.preview("shooter@1.0.0") and fixture.session.previews.size() == 1)
	_check("quota is a read-only coordinator surface", await fixture.coordinator.load_quota() and fixture.store.quota.remaining == 18)
	fixture.free_all.call()

func _test_import_and_work_loading_are_coordinator_owned() -> void:
	var fixture := _fixture()
	var imported := {"meta": {"runtime": "survivor", "runtime_version": "1.0.0"}, "player": {"sprite": "hero"}}
	_check("coordinator imports a validated runtime document", await fixture.coordinator.import_document("survivor@1.0.0", imported)
		and fixture.store.runtime_ref == "survivor@1.0.0" and fixture.session.current().player.sprite == "hero")
	var work := {"id": "draft-9", "status": "draft", "runtime": "shooter@1.0.0"}
	_check("coordinator opens a draft as its immutable parent", await fixture.coordinator.load_work(work)
		and fixture.store.draft_id == "draft-9" and fixture.store.runtime_ref == "shooter@1.0.0")
	var published := {"id": "game-9", "mod_id": "published-mod", "status": "published", "runtime": "shooter@1.0.0"}
	_check("opening published work forks an immutable editing draft", await fixture.coordinator.load_work(published)
		and fixture.store.draft_id == "mod-fork")
	var root_document := {"meta": {"runtime":"shooter", "runtime_version":"1.0.0"}, "player":{"sprite":"root"}}
	_check("external import starts a new root even on the same runtime", await fixture.coordinator.import_document("shooter@1.0.0", root_document)
		and fixture.store.draft_id == "" and fixture.store.saved_revision == 0)
	fixture.free_all.call()

func _test_published_work_is_preflighted_before_fork() -> void:
	var published := {"id": "game-9", "mod_id": "published-mod", "status": "published", "runtime": "shooter@1.0.0"}
	var fixture := _fixture()
	fixture.gateway.effective_result = ApiResultScript.offline("read failed")
	_check("published work read failure does not create an orphan fork",
		not await fixture.coordinator.load_work(published) and fixture.gateway.fork_mod_calls == 0)
	fixture.free_all.call()

	fixture = _fixture()
	fixture.gateway.effective_result = ApiResultScript.success(200, [])
	_check("malformed published work does not create an orphan fork",
		not await fixture.coordinator.load_work(published) and fixture.gateway.fork_mod_calls == 0)
	fixture.free_all.call()

	fixture = _fixture()
	fixture.session.accept_load = false
	_check("session-rejected published work does not create an orphan fork",
		not await fixture.coordinator.load_work(published) and fixture.gateway.fork_mod_calls == 0)
	fixture.free_all.call()

func _test_concurrent_generation_is_rejected() -> void:
	var fixture := _fixture()
	var gate := Gate.new()
	fixture.gateway.generation_gate = gate
	fixture.coordinator.generate("first", "shooter@1.0.0")
	var interleaved_validation: bool = await fixture.coordinator.validate_current("shooter@1.0.0")
	var duplicate: bool = await fixture.coordinator.generate("second", "shooter@1.0.0")
	_check("interleaved operations cannot release generation lock", not interleaved_validation and not duplicate and fixture.gateway.calls == ["generate"])
	gate.released.emit()
	await process_frame
	fixture.free_all.call()

func _test_local_edits_reject_stale_ai_results() -> void:
	var fixture := _fixture()
	var generation_gate := Gate.new()
	fixture.gateway.generation_gate = generation_gate
	fixture.coordinator.generate("stale", "shooter@1.0.0")
	fixture.session.record_patch([{"op": "replace", "path": "/player/sprite", "value": "local"}])
	generation_gate.released.emit()
	await process_frame
	_check("local edits reject stale generation patches", fixture.store.error_code == "STALE_SESSION" and fixture.session.applied.is_empty() and not fixture.store.generating)
	var validation_gate := Gate.new()
	fixture.gateway.validation_gate = validation_gate
	fixture.coordinator.validate_current("shooter@1.0.0")
	fixture.session.record_patch([{"op": "add", "path": "/local", "value": true}])
	validation_gate.released.emit()
	await process_frame
	_check("local edits reject stale validation results", fixture.store.error_code == "STALE_SESSION" and fixture.store.validation.is_empty())
	fixture.free_all.call()

func _test_generation_failures_release_the_lock() -> void:
	var fixture := _fixture()
	fixture.gateway.generation_result = ApiResultScript.offline("network down")
	_check("generation failure has explicit offline state", not await fixture.coordinator.generate("first", "shooter@1.0.0") and fixture.store.status == "offline" and not fixture.store.generating)
	fixture.gateway.generation_result = ApiResultScript.success(200, {"dsl_patch": []})
	_check("malformed design response is rejected", not await fixture.coordinator.generate("second", "shooter@1.0.0") and fixture.store.error_code == "INVALID_DESIGN")
	fixture.gateway.generation_result = ApiResultScript.success(200, {"dsl_patch": [{"op": "add", "path": "/x", "value": 1}], "new_dsl": {"x": 1}})
	fixture.session.accept_patch = false
	_check("session rejection is surfaced", not await fixture.coordinator.generate("third", "shooter@1.0.0") and fixture.store.error_code == "PATCH_REJECTED")
	fixture.free_all.call()

func _test_async_context_switches_are_serialized() -> void:
	var fixture := _fixture()
	var runtime_gate := Gate.new()
	fixture.gateway.runtime_gate = runtime_gate
	fixture.coordinator.load_runtime("shooter@1.0.0")
	_check("generation cannot cross an in-flight runtime load", not await fixture.coordinator.generate("stale", "shooter@1.0.0"))
	runtime_gate.released.emit()
	await process_frame
	var save_gate := Gate.new()
	fixture.gateway.save_gate = save_gate
	fixture.session.record_patch([{"op": "add", "path": "/saved", "value": true}])
	fixture.coordinator.save_draft("shooter@1.0.0")
	_check("context switches cannot cross an in-flight save", not await fixture.coordinator.load_runtime("survivor@1.0.0") and not await fixture.coordinator.fork_game("game-1"))
	save_gate.released.emit()
	await process_frame
	fixture.free_all.call()

func _test_save_tokens_and_fork_chain() -> void:
	var fixture := _fixture()
	var gate := Gate.new()
	fixture.gateway.save_gate = gate
	fixture.coordinator.save_draft("shooter@1.0.0")
	fixture.session.record_patch([{"op": "add", "path": "/late", "value": true}])
	gate.released.emit()
	await process_frame
	_check("save response only advances submitted revision", fixture.store.saved_revision == 1 and fixture.session.revision() == 2)
	fixture.gateway.save_gate = null
	_check("edits made during save remain pending", await fixture.coordinator.update_draft() and fixture.store.saved_revision == 2)
	await fixture.coordinator.fork_game("game-1")
	fixture.session.record_patch([{"op": "add", "path": "/fork-edit", "value": true}])
	await fixture.coordinator.save_draft("shooter@1.0.0")
	_check("fork draft id becomes immutable save parent", fixture.gateway.save_parents.back() == "game-fork")
	fixture.free_all.call()

func _test_undo_and_branch_edits_have_new_revisions() -> void:
	var fixture := _fixture()
	_check("initial draft save records a revision", await fixture.coordinator.save_draft("shooter@1.0.0"))
	fixture.session.record_patch([{"op": "replace", "path": "/player/sprite", "value": "plane"}])
	_check("undo after save remains persistable", await fixture.coordinator.update_draft() and fixture.store.saved_revision == 2)
	fixture.free_all.call()

func _test_draft_publish_and_review_workflow() -> void:
	var fixture := _fixture()
	_check("dirty session saves immutable draft", await fixture.coordinator.save_draft("shooter@1.0.0") and fixture.store.draft_id == "draft-1" and fixture.store.saved_revision == fixture.session.revision())
	fixture.session.record_patch([{"op": "add", "path": "/waves", "value": {}}])
	_check("draft update advances immutable id", await fixture.coordinator.update_draft() and fixture.store.draft_id == "draft-2")
	_check("draft publish enters review", await fixture.coordinator.publish_draft("title", "summary", ["tag"]) and fixture.store.review_status == "reviewing")
	_check("mod and game forks are owned", await fixture.coordinator.fork_mod("mod-1") and await fixture.coordinator.fork_game("game-1"))
	_check("forked draft publishes through the draft lifecycle", await fixture.coordinator.submit_for_review("title", "", [], "arcade", "shooter@1.0.0") and fixture.store.game_id == "game-draft")
	_check("delist resubmit and decision update review state", await fixture.coordinator.delist("game-1") and await fixture.coordinator.resubmit("game-1") and await fixture.coordinator.decide("game-1", true) and fixture.store.review_status == "published")
	_check("moderation queue is normalized", await fixture.coordinator.load_review_queue() and fixture.store.review_queue[0].id == "game-1")
	_check("studio workspace is coordinator-owned", await fixture.coordinator.load_workspace() and fixture.store.workspace_games[0].id == "game-1" and fixture.store.workspace_drafts[0].id == "draft-1")
	fixture.free_all.call()

func _test_publish_retry_reuses_mod() -> void:
	var fixture := _fixture()
	fixture.gateway.publish_results = [ApiResultScript.offline("network down"), ApiResultScript.success(201, {"id": "game-1", "status": "reviewing"})]
	_check("publish exposes second-stage failure", not await fixture.coordinator.publish_game("title", "arcade", "shooter@1.0.0") and fixture.store.mod_id == "mod-1")
	_check("publish retry reuses the created mod", await fixture.coordinator.publish_game("title", "arcade", "shooter@1.0.0") and fixture.gateway.create_mod_calls == 1)
	_check("changing runtime invalidates the publish cache", await fixture.coordinator.publish_game("title", "arcade", "survivor@1.0.0") and fixture.gateway.create_mod_calls == 2)
	await fixture.coordinator.load_effective_dsl("another-mod")
	fixture.session.record_patch([{"op": "add", "path": "/new-context", "value": true}])
	_check("loading a new context invalidates the publish cache", await fixture.coordinator.publish_game("title", "arcade", "shooter@1.0.0") and fixture.gateway.create_mod_calls == 3)
	fixture.free_all.call()

func _test_local_edit_before_publish_stage_is_stale() -> void:
	var fixture := _fixture()
	var gate := Gate.new()
	fixture.gateway.create_gate = gate
	fixture.coordinator.publish_game("title", "arcade", "shooter@1.0.0")
	fixture.session.record_patch([{"op":"add", "path":"/late-publish", "value":true}])
	gate.released.emit()
	await process_frame
	_check("local edits stop stale mod before game publish", fixture.store.error_code == "STALE_SESSION" and fixture.gateway.publish_game_calls == 0)
	fixture.gateway.create_gate = null
	_check("retry publishes a mod for the latest revision", await fixture.coordinator.publish_game("title", "arcade", "shooter@1.0.0") and fixture.gateway.create_mod_calls == 2)
	fixture.free_all.call()

func _test_existing_draft_publish_preserves_parent_chain() -> void:
	var fixture := _fixture()
	await fixture.coordinator.load_work({"id":"draft-parent", "status":"draft", "runtime":"shooter@1.0.0"})
	_check("unchanged draft uses the draft publish lifecycle", await fixture.coordinator.submit_for_review("title", "summary", ["tag"], "arcade", "shooter@1.0.0")
		and fixture.gateway.create_mod_calls == 0 and fixture.gateway.published_draft_ids == ["draft-parent"])
	fixture.free_all.call()
	fixture = _fixture()
	await fixture.coordinator.load_work({"id":"draft-parent", "status":"draft", "runtime":"shooter@1.0.0"})
	fixture.session.record_patch([{"op":"add", "path":"/child", "value":true}])
	_check("edited draft saves an immutable draft child before publish", await fixture.coordinator.submit_for_review("title", "summary", ["tag"], "arcade", "shooter@1.0.0")
		and fixture.gateway.create_mod_calls == 0 and fixture.gateway.published_draft_ids == ["draft-2"])
	fixture.free_all.call()

func _test_real_session_adapter_tracks_undo_branches() -> void:
	var adapter = CreatorSessionAdapterScript.new()
	var baseline := {"meta": {"runtime": "shooter", "runtime_version": "1.0.0"}, "player": {"sprite": "plane"}}
	_check("real adapter loads a clean origin", adapter.load_baseline("shooter@1.0.0", baseline) and adapter.revision() == 0 and not adapter.is_dirty())
	adapter.apply_patch([{"op": "replace", "path": "/player/sprite", "value": "cat"}])
	var saved_revision: int = adapter.revision()
	adapter.undo()
	_check("undo advances monotonic revision", adapter.revision() > saved_revision and adapter.current().player.sprite == "plane")
	var undo_delta: Array = adapter.patches_since_revision(saved_revision)
	_check("undo produces a delta from the saved document", undo_delta.size() == 1 and not undo_delta[0].is_empty())
	adapter.apply_patch([{"op": "replace", "path": "/player/sprite", "value": "dragon"}])
	_check("branch edits keep advancing revision", adapter.revision() > saved_revision + 1 and adapter.current().player.sprite == "dragon")

func _fixture() -> Dictionary:
	var gateway := FakeGateway.new()
	var store = CreationStoreScript.new()
	var session = FakeSession.new()
	var coordinator = CreationCoordinatorScript.new(gateway, store, session)
	return {"gateway": gateway, "store": store, "session": session, "coordinator": coordinator,
		"free_all": func() -> void: coordinator.free(); store.free()}

func _check(label: String, condition: bool) -> void:
	if condition: _passed += 1
	else: _failed += 1; push_error("FAIL: " + label)
