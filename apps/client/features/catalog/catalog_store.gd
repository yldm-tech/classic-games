class_name CatalogStore
extends Node

signal changed

const IDLE := "idle"
const LOADING := "loading"
const READY := "ready"
const EMPTY := "empty"
const OFFLINE := "offline"
const UNAUTHORIZED := "unauthorized"
const VALIDATION_ERROR := "validation_error"
const ERROR := "error"

var status := IDLE
var paging := false
var query: Dictionary = {}
var items: Array = []
var next_cursor := ""
var detail: Dictionary = {}
var game_lineage: Array = []
var fork_tree: Dictionary = {}
var mod_lineage: Array = []
var ranking: Array = []
var profile: Dictionary = {}
var profile_games: Array = []
var error_kind := ""
var error_code := ""
var message := ""

func begin_collection(p_query: Dictionary) -> void:
	status = LOADING
	paging = false
	query = p_query.duplicate(true)
	items = []
	next_cursor = ""
	_clear_error()
	changed.emit()

func begin_paging() -> bool:
	if paging or next_cursor == "":
		return false
	paging = true
	_clear_error()
	changed.emit()
	return true

func complete_collection(data: Dictionary, append: bool) -> void:
	var received: Array = data.get("items", [])
	if append:
		items = _append_unique(items, received)
	else:
		items = received.duplicate(true)
	next_cursor = str(data.get("next_cursor", ""))
	paging = false
	status = EMPTY if items.is_empty() else READY
	_clear_error()
	changed.emit()

func begin_resource() -> void:
	status = LOADING
	_clear_error()
	changed.emit()

func complete_resource(slot: String, value: Variant) -> void:
	match slot:
		"detail":
			detail = (value as Dictionary).duplicate(true)
		"game_lineage":
			game_lineage = (value as Array).duplicate(true)
		"fork_tree":
			fork_tree = (value as Dictionary).duplicate(true)
		"mod_lineage":
			mod_lineage = (value as Array).duplicate(true)
		"ranking":
			ranking = (value as Array).duplicate(true)
		"profile":
			profile = (value as Dictionary).duplicate(true)
		"profile_games":
			profile_games = (value as Array).duplicate(true)
	status = EMPTY if value is Array and value.is_empty() else READY
	_clear_error()
	changed.emit()

func fail(result: Variant) -> void:
	paging = false
	error_kind = result.kind
	error_code = result.code
	message = result.message
	match result.kind:
		"offline":
			status = OFFLINE
		"unauthorized":
			status = UNAUTHORIZED
		"validation":
			status = VALIDATION_ERROR
		_:
			status = ERROR
	changed.emit()

func _append_unique(existing: Array, received: Array) -> Array:
	var merged := existing.duplicate(true)
	var seen: Dictionary = {}
	for item: Variant in merged:
		if item is Dictionary and str(item.get("id", "")) != "":
			seen[str(item.id)] = true
	for item: Variant in received:
		var id := str(item.get("id", "")) if item is Dictionary else ""
		if id != "" and seen.has(id):
			continue
		merged.append(item.duplicate(true) if item is Dictionary or item is Array else item)
		if id != "":
			seen[id] = true
	return merged

func _clear_error() -> void:
	error_kind = ""
	error_code = ""
	message = ""
