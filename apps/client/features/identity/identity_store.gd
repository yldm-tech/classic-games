class_name IdentityStore
extends Node

signal changed

const READY := "ready"
const SENDING_CODE := "sending_code"
const AUTHENTICATING := "authenticating"
const AUTHENTICATED := "authenticated"
const UNAUTHORIZED := "unauthorized"
const VALIDATION_ERROR := "validation_error"
const OFFLINE := "offline"
const ERROR := "error"

var status := READY
var code_sent := false
var session: Dictionary = {}
var error_kind := ""
var error_code := ""
var message := ""

func begin_send_code() -> bool:
	if status == SENDING_CODE:
		return false
	_set_status(SENDING_CODE)
	code_sent = false
	_clear_error()
	changed.emit()
	return true

func complete_send_code() -> void:
	status = READY
	code_sent = true
	_clear_error()
	changed.emit()

func begin_authentication() -> bool:
	if status == AUTHENTICATING:
		return false
	_set_status(AUTHENTICATING)
	_clear_error()
	changed.emit()
	return true

func complete_authentication(p_session: Dictionary) -> void:
	status = AUTHENTICATED
	session = p_session.duplicate(true)
	_clear_error()
	changed.emit()

func reset() -> void:
	status = READY
	code_sent = false
	session.clear()
	_clear_error()
	changed.emit()

func fail(result: Variant) -> void:
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

func _set_status(value: String) -> void:
	status = value

func _clear_error() -> void:
	error_kind = ""
	error_code = ""
	message = ""
