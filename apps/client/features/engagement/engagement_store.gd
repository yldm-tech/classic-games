class_name EngagementStore
extends Node

signal changed

var status := "idle"
var operation := ""
var error_kind := ""
var error_code := ""
var message := ""
var downloads: Array = []
var history_groups: Array = []
var live_items: Array = []
var room: Dictionary = {}
var replay: Dictionary = {}
var replay_leaderboard_by_game: Dictionary = {}
var library_items: Array = []
var library_kind := ""
var balance := 0
var download_pending: Dictionary = {}
var gift_pending := false
var room_pending := false
var history_pending := false
var downloads_revision := 0
var history_revision := 0
var live_revision := 0
var room_revision := 0
var replay_revision := 0
var library_revision := 0

func begin(next_operation: String) -> void:
	operation = next_operation; status = "loading"; _clear_error(); changed.emit()

func ready(next_status: String = "ready") -> void:
	status = next_status; _clear_error(); changed.emit()

func fail(result: Variant) -> void:
	status = "offline" if result.kind == "offline" else "error"
	error_kind = result.kind; error_code = result.code; message = result.message; changed.emit()

func touch() -> void: changed.emit()

func _clear_error() -> void:
	error_kind = ""; error_code = ""; message = ""
