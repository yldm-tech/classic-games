class_name CommunityStore
extends Node

signal changed

var status := "idle"
var operation := ""
var error_kind := ""
var error_code := ""
var message := ""
var comments_by_game: Dictionary = {}
var community_by_game: Dictionary = {}
var liked_by_game: Dictionary = {}
var like_pending_by_game: Dictionary = {}
var favorite_ids: Array = []
var favorite_pending_by_game: Dictionary = {}
var activity: Array = []
var conversations: Array = []
var active_handle := ""
var messages_by_handle: Dictionary = {}
var send_pending_by_handle: Dictionary = {}
var following: Array = []
var followers: Array = []
var suggestions: Array = []
var follow_by_handle: Dictionary = {}
var added_friends: Dictionary = {}
var inbox_revision := 0
var follow_revision := 0

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
