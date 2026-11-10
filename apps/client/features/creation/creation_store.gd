class_name CreationStore
extends Node

signal changed

var status := "idle"
var operation := ""
var generating := false
var saving := false
var publishing := false
var error_kind := ""
var error_code := ""
var message := ""
var runtime_ref := ""
var schema: Dictionary = {}
var baseline: Dictionary = {}
var effective_dsl: Dictionary = {}
var validation: Dictionary = {}
var last_patch: Array = []
var ai_provenance := ""
var draft_id := ""
var saved_revision := 0
var mod_id := ""
var mod_revision := -1
var game_id := ""
var review_status := ""
var review_queue: Array = []
var workspace_games: Array = []
var workspace_drafts: Array = []
var workspace_mods: Array = []
var quota: Dictionary = {}

func begin(next_operation: String, generation: bool = false) -> void:
	operation = next_operation
	status = "loading"
	if generation: generating = true
	_clear_error()
	changed.emit()

func ready(next_status: String = "ready", finish_generation: bool = false) -> void:
	status = next_status
	if finish_generation: generating = false
	_clear_error()
	changed.emit()

func fail(result: Variant, finish_generation: bool = false) -> void:
	status = "offline" if result.kind == "offline" else "error"
	if finish_generation: generating = false
	error_kind = result.kind
	error_code = result.code
	message = result.message
	changed.emit()

func _clear_error() -> void:
	error_kind = ""
	error_code = ""
	message = ""
