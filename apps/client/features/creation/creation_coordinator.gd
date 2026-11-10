class_name CreationCoordinator
extends Node

const ApiResultScript := preload("res://core/http/api_result.gd")

var gateway: Variant
var store: CreationStore
var session: CreationSessionPort
var _operation_active := false
var _context_revision := 0
var _mod_context_revision := -1
var _mod_runtime_ref := ""

func _init(p_gateway: Variant, p_store: CreationStore, p_session: CreationSessionPort) -> void:
	gateway = p_gateway
	store = p_store
	session = p_session

func load_quota() -> bool:
	if gateway == null or not gateway.has_method("quota"):
		return false
	var result = await gateway.quota()
	if not result.ok or not result.data is Dictionary:
		return false
	store.quota = result.data.duplicate(true)
	store.changed.emit()
	return true

func load_runtime(runtime_ref: String) -> bool:
	if _operation_active: return false
	var parts := runtime_ref.split("@", false, 1)
	if parts.size() != 2:
		return _invalid("INVALID_RUNTIME", "Runtime must use name@version")
	if not _begin_operation("runtime"): return false
	var schema_result = await gateway.runtime_schema(parts[0], parts[1])
	if not schema_result.ok: return _finish_failure(schema_result)
	var baseline_result = await gateway.runtime_baseline(parts[0], parts[1])
	if not baseline_result.ok: return _finish_failure(baseline_result)
	if not schema_result.data is Dictionary or not baseline_result.data is Dictionary:
		return _finish_invalid("INVALID_RUNTIME_RESPONSE", "Runtime response must contain objects")
	if not session.load_baseline(runtime_ref, baseline_result.data):
		return _finish_invalid("INVALID_BASELINE", "Session rejected runtime baseline")
	store.runtime_ref = runtime_ref
	store.schema = schema_result.data.duplicate(true)
	store.baseline = baseline_result.data.duplicate(true)
	store.draft_id = ""
	store.saved_revision = session.revision()
	_reset_mod_cache()
	_context_revision += 1
	return _finish_ready()

func load_effective_dsl(mod_id: String) -> bool:
	return await _load_effective_dsl(mod_id, false)

func resume_draft(mod_id: String) -> bool:
	return await _load_effective_dsl(mod_id, true)

func import_document(runtime_ref: String, document: Dictionary) -> bool:
	if _operation_active: return false
	var parts := runtime_ref.split("@", false, 1)
	if parts.size() != 2: return _invalid("INVALID_RUNTIME", "Runtime must use name@version")
	if not _begin_operation("import_document"): return false
	var submitted_revision := session.revision()
	var validation_result = await gateway.validate_dsl(runtime_ref, document)
	if not validation_result.ok: return _finish_failure(validation_result)
	if session.revision() != submitted_revision:
		return _finish_invalid("STALE_SESSION", "Document changed while import validation was running")
	if not validation_result.data is Dictionary:
		return _finish_invalid("INVALID_VALIDATION", "Validation response must be an object")
	var schema_result = await gateway.runtime_schema(parts[0], parts[1])
	if not schema_result.ok: return _finish_failure(schema_result)
	var baseline_result = await gateway.runtime_baseline(parts[0], parts[1])
	if not baseline_result.ok: return _finish_failure(baseline_result)
	if session.revision() != submitted_revision:
		return _finish_invalid("STALE_SESSION", "Document changed while import dependencies were loading")
	if not schema_result.data is Dictionary or not baseline_result.data is Dictionary:
		return _finish_invalid("INVALID_RUNTIME_RESPONSE", "Runtime response must contain objects")
	if not session.load_baseline(runtime_ref, baseline_result.data):
		return _finish_invalid("INVALID_BASELINE", "Session rejected runtime baseline")
	if not session.apply_document(document):
		return _finish_invalid("DOCUMENT_REJECTED", "Session rejected imported document")
	store.runtime_ref = runtime_ref
	store.schema = schema_result.data.duplicate(true)
	store.baseline = baseline_result.data.duplicate(true)
	store.draft_id = ""
	store.saved_revision = 0
	_reset_mod_cache()
	_context_revision += 1
	store.validation = validation_result.data.duplicate(true)
	store.effective_dsl = document.duplicate(true)
	return _finish_ready()

func apply_document(runtime_ref: String, document: Dictionary) -> bool:
	if _operation_active: return false
	if runtime_ref == "" or runtime_ref != store.runtime_ref:
		return _invalid("RUNTIME_MISMATCH", "Edited document must keep the current runtime")
	if not _begin_operation("apply_document"): return false
	var submitted_revision := session.revision()
	var validation_result = await gateway.validate_dsl(runtime_ref, document)
	if not validation_result.ok: return _finish_failure(validation_result)
	if session.revision() != submitted_revision:
		return _finish_invalid("STALE_SESSION", "Document changed while edit validation was running")
	if not validation_result.data is Dictionary:
		return _finish_invalid("INVALID_VALIDATION", "Validation response must be an object")
	if not session.apply_document(document):
		return _finish_invalid("DOCUMENT_REJECTED", "Session rejected edited document")
	store.validation = validation_result.data.duplicate(true)
	store.effective_dsl = document.duplicate(true)
	return _finish_ready()

func load_work(work: Dictionary) -> bool:
	if _operation_active: return false
	var runtime_ref := str(work.get("runtime", ""))
	var parts := runtime_ref.split("@", false, 1)
	var is_draft := str(work.get("status", "")) == "draft"
	var mod_id := str(work.get("id", "")) if is_draft else str(work.get("mod_id", ""))
	if parts.size() != 2 or mod_id == "":
		return _invalid("INVALID_WORK", "Work must contain runtime and mod identity")
	if not _begin_operation("load_work"): return false
	var schema_result = await gateway.runtime_schema(parts[0], parts[1])
	if not schema_result.ok: return _finish_failure(schema_result)
	var baseline_result = await gateway.runtime_baseline(parts[0], parts[1])
	if not baseline_result.ok: return _finish_failure(baseline_result)
	var document_result = await gateway.effective_dsl(mod_id)
	if not document_result.ok: return _finish_failure(document_result)
	if not schema_result.data is Dictionary or not baseline_result.data is Dictionary or not document_result.data is Dictionary:
		return _finish_invalid("INVALID_WORK_RESPONSE", "Work dependencies must contain objects")
	if not session.can_load(runtime_ref, baseline_result.data, document_result.data):
		return _finish_invalid("WORK_REJECTED", "Session rejected work document")
	if not is_draft:
		var fork_result = await gateway.fork_mod(mod_id)
		if not fork_result.ok: return _finish_failure(fork_result)
		if not fork_result.data is Dictionary or str(fork_result.data.get("id", "")) == "":
			return _finish_invalid("INVALID_FORK", "Published work fork must contain id")
		mod_id = str(fork_result.data.id)
	if not session.load_baseline(runtime_ref, baseline_result.data) or not session.load_document(document_result.data):
		return _finish_invalid("WORK_REJECTED", "Session rejected work document")
	store.runtime_ref = runtime_ref
	store.schema = schema_result.data.duplicate(true)
	store.baseline = baseline_result.data.duplicate(true)
	store.effective_dsl = document_result.data.duplicate(true)
	store.draft_id = mod_id
	store.saved_revision = session.revision()
	_reset_mod_cache()
	_context_revision += 1
	return _finish_ready()

func _load_effective_dsl(mod_id: String, adopt_as_draft: bool) -> bool:
	if not _begin_operation("resume_draft" if adopt_as_draft else "effective_dsl"): return false
	var result = await gateway.effective_dsl(mod_id)
	if not result.ok: return _finish_failure(result)
	if not result.data is Dictionary or not session.load_document(result.data):
		return _finish_invalid("INVALID_EFFECTIVE_DSL", "Effective DSL was rejected")
	store.effective_dsl = result.data.duplicate(true)
	store.draft_id = mod_id if adopt_as_draft else ""
	store.saved_revision = session.revision()
	_reset_mod_cache()
	_context_revision += 1
	return _finish_ready()

func generate(prompt: String, runtime_ref: String) -> bool:
	if not _begin_operation("generate", "generating"): return false
	var submitted_revision := session.revision()
	return _complete_design(await gateway.generate_mod(runtime_ref, session.current(), prompt), submitted_revision)

func balance(difficulty: int, runtime_ref: String) -> bool:
	if not _begin_operation("balance", "generating"): return false
	var submitted_revision := session.revision()
	return _complete_design(await gateway.auto_balance(runtime_ref, session.current(), difficulty), submitted_revision)

func structure(prompt: String, count: int, difficulty: int, runtime_ref: String) -> bool:
	if not _begin_operation("structure", "generating"): return false
	var submitted_revision := session.revision()
	return _complete_design(await gateway.generate_structure(runtime_ref, session.current(), prompt, count, difficulty), submitted_revision)

func validate_current(runtime_ref: String) -> bool:
	if not _begin_operation("validate"): return false
	var submitted_revision := session.revision()
	var result = await gateway.validate_dsl(runtime_ref, session.current())
	if not result.ok: return _finish_failure(result)
	if session.revision() != submitted_revision:
		return _finish_invalid("STALE_SESSION", "Document changed while validation was running")
	if not result.data is Dictionary:
		return _finish_invalid("INVALID_VALIDATION", "Validation response must be an object")
	store.validation = result.data.duplicate(true)
	return _finish_ready()

func preview(runtime_ref: String) -> bool:
	return session.preview(runtime_ref, session.current())

func save_draft(runtime_ref: String) -> bool:
	if _operation_active: return false
	if not session.is_dirty(): return _invalid("CLEAN_DRAFT", "Draft has no changes")
	var patch := _flatten(session.patches_since_revision(store.saved_revision))
	if patch.is_empty(): return _invalid("EMPTY_PATCH", "Draft has no new patch")
	if not _begin_operation("save_draft", "saving"): return false
	var submitted_revision := session.revision()
	var result = await gateway.save_draft(runtime_ref, store.draft_id, patch, store.ai_provenance)
	return _complete_draft(result, submitted_revision)

func update_draft() -> bool:
	if _operation_active: return false
	if store.draft_id == "": return _invalid("MISSING_DRAFT", "Draft has not been created")
	var patch := _flatten(session.patches_since_revision(store.saved_revision))
	if patch.is_empty(): return _invalid("EMPTY_PATCH", "Draft has no new patch")
	if not _begin_operation("update_draft", "saving"): return false
	var submitted_revision := session.revision()
	return _complete_draft(await gateway.update_draft(store.draft_id, patch), submitted_revision)

func publish_draft(title: String, summary: String = "", tags: Array = []) -> bool:
	if _operation_active: return false
	if store.draft_id == "": return _invalid("MISSING_DRAFT", "Draft has not been created")
	if not _begin_operation("publish_draft", "publishing"): return false
	var result = await gateway.publish_draft(store.draft_id, title, summary, tags)
	if not result.ok: return _finish_failure(result)
	if not result.data is Dictionary or str(result.data.get("id", "")) == "" or str(result.data.get("status", "")) == "":
		return _finish_invalid("INVALID_PUBLISH", "Publish response must contain id and status")
	store.game_id = str(result.data.id)
	store.review_status = str(result.data.status)
	return _finish_ready()

func submit_for_review(title: String, summary: String, tags: Array, category: String, runtime_ref: String) -> bool:
	if store.draft_id == "":
		return await publish_game(title, category, runtime_ref)
	if _operation_active: return false
	var patch := _flatten(session.patches_since_revision(store.saved_revision))
	if not _begin_operation("submit_for_review", "publishing"): return false
	var submitted_revision := session.revision()
	if not patch.is_empty():
		var update_result = await gateway.update_draft(store.draft_id, patch)
		if not update_result.ok: return _finish_failure(update_result)
		if not update_result.data is Dictionary or str(update_result.data.get("id", "")) == "":
			return _finish_invalid("INVALID_DRAFT", "Draft update response must contain id")
		store.draft_id = str(update_result.data.id)
		store.saved_revision = submitted_revision
		if session.revision() != submitted_revision:
			return _finish_invalid("STALE_SESSION", "Document changed while draft was being prepared for review")
	var result = await gateway.publish_draft(store.draft_id, title, summary, tags)
	if not result.ok: return _finish_failure(result)
	if not result.data is Dictionary or str(result.data.get("id", "")) == "" or str(result.data.get("status", "")) == "":
		return _finish_invalid("INVALID_PUBLISH", "Publish response must contain id and status")
	store.game_id = str(result.data.id)
	store.review_status = str(result.data.status)
	return _finish_ready()

func fork_mod(id: String) -> bool:
	if not _begin_operation("fork_mod"): return false
	return _complete_fork(await gateway.fork_mod(id))

func fork_game(id: String) -> bool:
	if not _begin_operation("fork_game"): return false
	return _complete_fork(await gateway.fork_game(id))

func publish_game(title: String, category: String, runtime_ref: String) -> bool:
	if _operation_active: return false
	if store.draft_id != "": return _invalid("DRAFT_REQUIRES_PUBLISH", "Drafts must use the draft publish lifecycle")
	var patch := _flatten(session.patches_since_revision(0))
	if patch.is_empty(): return _invalid("EMPTY_PATCH", "Game has no authored patch")
	if not _begin_operation("publish_game", "publishing"): return false
	var submitted_revision := session.revision()
	if store.mod_id == "" or store.mod_revision != submitted_revision or _mod_context_revision != _context_revision or _mod_runtime_ref != runtime_ref:
		var mod_result = await gateway.create_mod(runtime_ref, "", patch, store.ai_provenance)
		if not mod_result.ok: return _finish_failure(mod_result)
		if not mod_result.data is Dictionary or str(mod_result.data.get("id", "")) == "":
			return _finish_invalid("INVALID_MOD", "Mod response must contain id")
		store.mod_id = str(mod_result.data.id)
		store.mod_revision = submitted_revision
		_mod_context_revision = _context_revision
		_mod_runtime_ref = runtime_ref
		if session.revision() != submitted_revision:
			return _finish_invalid("STALE_SESSION", "Document changed while mod was being prepared for publish")
	var result = await gateway.publish_game(store.mod_id, title, category)
	if not result.ok: return _finish_failure(result)
	if not result.data is Dictionary or str(result.data.get("id", "")) == "" or str(result.data.get("status", "")) == "":
		return _finish_invalid("INVALID_GAME", "Game response must contain id and status")
	store.game_id = str(result.data.id)
	store.review_status = str(result.data.get("status", ""))
	return _finish_ready()

func delist(id: String) -> bool:
	if not _begin_operation("delist"): return false
	return _complete_review(await gateway.delist_game(id))

func resubmit(id: String) -> bool:
	if not _begin_operation("resubmit"): return false
	return _complete_review(await gateway.resubmit_game(id))

func decide(id: String, approve: bool) -> bool:
	if not _begin_operation("decide"): return false
	return _complete_review(await gateway.decide_game(id, approve))

func load_review_queue(cursor: String = "", limit: int = 20) -> bool:
	if not _begin_operation("review_queue"): return false
	var result = await gateway.moderation_queue(cursor, limit)
	if not result.ok:
		if result.status == 403 or result.kind == "unauthorized":
			store.review_queue = []
			return _finish_ready("ready")
		return _finish_failure(result)
	if not result.data is Dictionary or not result.data.get("items", []) is Array:
		return _finish_invalid("INVALID_REVIEW_QUEUE", "Review queue must contain items")
	store.review_queue = result.data.items.duplicate(true)
	return _finish_ready("empty" if store.review_queue.is_empty() else "ready")

func load_workspace(lang: String = "zh") -> bool:
	if not _begin_operation("workspace"): return false
	var games_result = await gateway.my_games(lang)
	if not games_result.ok: return _finish_failure(games_result)
	var drafts_result = await gateway.drafts()
	if not drafts_result.ok: return _finish_failure(drafts_result)
	var mods_result = await gateway.my_mods()
	if not mods_result.ok: return _finish_failure(mods_result)
	for result: Variant in [games_result, drafts_result, mods_result]:
		if not result.data is Dictionary or not result.data.get("items", []) is Array:
			return _finish_invalid("INVALID_WORKSPACE", "Workspace response must contain items")
	store.workspace_games = games_result.data.items.duplicate(true)
	store.workspace_drafts = drafts_result.data.items.duplicate(true)
	store.workspace_mods = mods_result.data.items.duplicate(true)
	return _finish_ready("empty" if store.workspace_games.is_empty() and store.workspace_drafts.is_empty() else "ready")

func _begin_operation(operation: String, kind: String = "") -> bool:
	if _operation_active: return false
	_operation_active = true
	store.generating = kind == "generating"
	store.saving = kind == "saving"
	store.publishing = kind == "publishing"
	store.begin(operation)
	return true

func _complete_design(result: Variant, submitted_revision: int) -> bool:
	if not result.ok: return _finish_failure(result)
	if session.revision() != submitted_revision:
		return _finish_invalid("STALE_SESSION", "Document changed while generation was running")
	if not result.data is Dictionary or not result.data.get("dsl_patch", []) is Array or not result.data.has("new_dsl") or not result.data.new_dsl is Dictionary:
		return _finish_invalid("INVALID_DESIGN", "Design response must contain dsl_patch and new_dsl")
	var patch: Array = result.data.dsl_patch
	if not session.apply_patch(patch):
		return _finish_invalid("PATCH_REJECTED", "Session rejected generated patch")
	store.last_patch = patch.duplicate(true)
	store.effective_dsl = result.data.new_dsl.duplicate(true)
	store.ai_provenance = str(result.data.get("provenance", store.ai_provenance))
	return _finish_ready()

func _complete_draft(result: Variant, submitted_revision: int) -> bool:
	if not result.ok: return _finish_failure(result)
	if not result.data is Dictionary or str(result.data.get("id", "")) == "":
		return _finish_invalid("INVALID_DRAFT", "Draft response must contain id")
	store.draft_id = str(result.data.id)
	store.saved_revision = submitted_revision
	return _finish_ready()

func _complete_fork(result: Variant) -> bool:
	if not result.ok: return _finish_failure(result)
	if not result.data is Dictionary or str(result.data.get("id", "")) == "":
		return _finish_invalid("INVALID_FORK", "Fork response must contain id")
	store.draft_id = str(result.data.id)
	store.saved_revision = session.revision()
	_reset_mod_cache()
	_context_revision += 1
	return _finish_ready()

func _complete_review(result: Variant) -> bool:
	if not result.ok: return _finish_failure(result)
	if not result.data is Dictionary or str(result.data.get("status", "")) == "":
		return _finish_invalid("INVALID_REVIEW", "Review response must contain status")
	store.review_status = str(result.data.status)
	return _finish_ready()

func _flatten(batches: Array) -> Array:
	var flattened: Array = []
	for batch: Array in batches: flattened.append_array(batch)
	return flattened

func _reset_mod_cache() -> void:
	store.mod_id = ""
	store.mod_revision = -1
	_mod_context_revision = -1
	_mod_runtime_ref = ""

func _release_operation() -> void:
	_operation_active = false
	store.generating = false
	store.saving = false
	store.publishing = false

func _finish_ready(status: String = "ready") -> bool:
	_release_operation()
	store.ready(status)
	return true

func _invalid(code: String, message: String) -> bool:
	store.fail(ApiResultScript.unexpected(code, message))
	return false

func _finish_invalid(code: String, message: String) -> bool:
	_release_operation()
	return _invalid(code, message)

func _finish_failure(result: Variant) -> bool:
	_release_operation()
	store.fail(result)
	return false
