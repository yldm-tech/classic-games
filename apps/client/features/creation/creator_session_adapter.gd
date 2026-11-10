class_name CreatorSessionAdapter
extends CreationSessionPort

const CreatorSessionScript := preload("res://shell/creator_session.gd")

var _session: CreatorSession
var _runtime_ref := ""
var _revision := 0
var _state_token := 0
var _documents: Dictionary = {}
var _preview_handler: Callable

func _init(preview_handler: Callable = Callable()) -> void:
	_preview_handler = preview_handler

func can_load(runtime_ref: String, baseline: Dictionary, document: Dictionary) -> bool:
	if runtime_ref == "" or baseline.is_empty() or document.is_empty(): return false
	var probe: CreatorSession = CreatorSessionScript.new(baseline)
	return probe.apply_document(document)

func load_baseline(runtime_ref: String, baseline: Dictionary) -> bool:
	if baseline.is_empty(): return false
	_runtime_ref = runtime_ref
	_session = CreatorSessionScript.new(baseline)
	_reset_revisions()
	_state_token += 1
	return true

func load_document(document: Dictionary) -> bool:
	if document.is_empty(): return false
	_session = CreatorSessionScript.new(document)
	_reset_revisions()
	_state_token += 1
	return true

func current() -> Dictionary:
	return _session.current() if _session != null else {}

func apply_patch(ops: Array) -> bool:
	if _session == null or not _session.apply_patch(ops): return false
	_record_revision()
	return true

func apply_document(document: Dictionary) -> bool:
	if _session == null: return false
	var previous: Dictionary = current()
	if not _session.apply_document(document): return false
	if current() == previous: return true
	_record_revision()
	return true

func is_dirty() -> bool:
	return _session != null and _session.is_dirty()

func state_token() -> int:
	return _state_token

func revision() -> int:
	return _revision

func patches_since_revision(base_revision: int) -> Array:
	if not _documents.has(base_revision): return []
	var ops := _diff_documents(_documents[base_revision], current())
	return [] if ops.is_empty() else [ops]

func preview(runtime_ref: String, dsl: Dictionary) -> bool:
	return _preview_handler.is_valid() and bool(_preview_handler.call(runtime_ref, dsl))

func set_preview_handler(handler: Callable) -> void:
	_preview_handler = handler

func runtime_ref() -> String:
	return _runtime_ref

func can_undo() -> bool:
	return _session != null and _session.can_undo()

func can_redo() -> bool:
	return _session != null and _session.can_redo()

func undo() -> bool:
	if not can_undo(): return false
	_session.undo()
	_record_revision()
	return true

func redo() -> bool:
	if not can_redo(): return false
	_session.redo()
	_record_revision()
	return true

func step_count() -> int:
	return _session.step_count() if _session != null else 0

func _reset_revisions() -> void:
	_revision = 0
	_documents = {0: current().duplicate(true)}

func _record_revision() -> void:
	_revision += 1
	_state_token += 1
	_documents[_revision] = current().duplicate(true)

func _diff_documents(previous: Dictionary, next: Dictionary) -> Array:
	var ops: Array = []
	for key: Variant in previous.keys():
		if not next.has(key):
			ops.append({"op": "remove", "path": "/%s" % _escape_pointer(str(key))})
	for key: Variant in next.keys():
		var path := "/%s" % _escape_pointer(str(key))
		if not previous.has(key):
			ops.append({"op": "add", "path": path, "value": next[key]})
		elif previous[key] != next[key]:
			ops.append({"op": "replace", "path": path, "value": next[key]})
	return ops

func _escape_pointer(key: String) -> String:
	return key.replace("~", "~0").replace("/", "~1")
