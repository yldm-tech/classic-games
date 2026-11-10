class_name ApiResult
extends RefCounted

const SUCCESS := "success"
const OFFLINE := "offline"
const UNAUTHORIZED := "unauthorized"
const VALIDATION := "validation"
const CONFLICT := "conflict"
const RATE_LIMITED := "rate_limited"
const UNEXPECTED := "unexpected"

var ok: bool
var kind: String
var status: int
var data: Variant
var code: String
var message: String

func _init(
	p_ok: bool,
	p_kind: String,
	p_status: int,
	p_data: Variant = null,
	p_code: String = "",
	p_message: String = "",
) -> void:
	ok = p_ok
	kind = p_kind
	status = p_status
	data = p_data
	code = p_code
	message = p_message

static func success(p_status: int, p_data: Variant = null) -> ApiResult:
	return ApiResult.new(true, SUCCESS, p_status, p_data)

static func offline(p_message: String, p_code: String = "NETWORK_ERROR") -> ApiResult:
	return ApiResult.new(false, OFFLINE, 0, null, p_code, p_message)

static func failure_for_status(
	p_status: int,
	p_code: String,
	p_message: String,
	p_data: Variant = null,
) -> ApiResult:
	return ApiResult.new(false, kind_for_status(p_status), p_status, p_data, p_code, p_message)

static func unexpected(p_code: String, p_message: String, p_status: int = 0) -> ApiResult:
	return ApiResult.new(false, UNEXPECTED, p_status, null, p_code, p_message)

static func kind_for_status(p_status: int) -> String:
	match p_status:
		401, 403:
			return UNAUTHORIZED
		400, 422:
			return VALIDATION
		409:
			return CONFLICT
		429:
			return RATE_LIMITED
		_:
			return UNEXPECTED
