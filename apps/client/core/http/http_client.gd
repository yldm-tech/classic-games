class_name HttpClient
extends Node

const ApiResultScript := preload("res://core/http/api_result.gd")

var base_url: String
var timeout_seconds: float = 10.0
## Endpoints that block on the LLM provider while it generates. The server calls Anthropic inline in the request goroutine, so these routinely take far longer than the default budget; timing out at 10s aborted every generation client-side while the server ran to completion and still charged the user's daily quota, which made the product's headline feature unusable. Matched by prefix here rather than passed per call because seven test doubles implement request() with exactly three parameters.
const GENERATION_PATHS := ["/api/v1/ai/mod", "/api/v1/ai/structure", "/api/v1/ai/balance"]
var generation_timeout_seconds: float = 120.0
var _token: String = ""
var _active_requests: Array[HTTPRequest] = []
var _refresh_handler: Callable = Callable()

func _init(p_base_url: String) -> void:
	base_url = p_base_url
	while base_url.ends_with("/"):
		base_url = base_url.left(-1)

## Empty (offline tests), HTTPS, and loopback HTTP are allowed. Public
## cleartext would ship session tokens in the clear.
static func is_secure_base(url: String) -> bool:
	if url.is_empty() or url.begins_with("https://"):
		return true
	if not url.begins_with("http://"):
		return false
	var host := url.substr(7).split("/")[0].split("?")[0]
	if host.begins_with("["):
		return host.begins_with("[::1]")
	return host.split(":")[0] in ["127.0.0.1", "localhost"]

func reject_insecure_base() -> Variant:
	if is_secure_base(base_url):
		return null
	return ApiResultScript.offline("cleartext HTTP is not allowed", "INSECURE_URL")

## Generation endpoints wait on the provider; everything else keeps the short interactive budget.
func timeout_for(path: String) -> float:
	for generation_path: String in GENERATION_PATHS:
		if path.begins_with(generation_path):
			return generation_timeout_seconds
	return timeout_seconds

func set_refresh_handler(handler: Callable) -> void:
	_refresh_handler = handler

func should_retry_unauthorized(path: String, result: Variant) -> bool:
	if not _refresh_handler.is_valid() or result == null:
		return false
	if path.begins_with("/api/v1/auth/"):
		return false
	return int(result.status) == 401

func set_token(p_token: String) -> void:
	_token = p_token

func clear_token() -> void:
	_token = ""

func request(method: int, path: String, body: Variant = null):
	var decoded: Variant = await _exchange(method, path, body)
	if not should_retry_unauthorized(path, decoded):
		return decoded
	var refreshed: Variant = await _refresh_handler.call()
	if not bool(refreshed):
		return decoded
	return await _exchange(method, path, body)

func _exchange(method: int, path: String, body: Variant = null):
	var blocked: Variant = reject_insecure_base()
	if blocked != null:
		return blocked
	var http := HTTPRequest.new()
	_active_requests.append(http)
	http.timeout = timeout_for(path)
	add_child(http)

	var has_body := body != null
	var error: Error
	if has_body:
		error = http.request(build_url(path), build_headers(true), method, JSON.stringify(body))
	else:
		error = http.request(build_url(path), build_headers(false), method)
	if error != OK:
		_active_requests.erase(http)
		http.queue_free()
		return ApiResultScript.offline("HTTPRequest failed to start: %d" % error, "REQUEST_FAILED")

	var completed: Array = await http.request_completed
	_active_requests.erase(http)
	http.queue_free()
	var transport_status: int = completed[0]
	var response_status: int = completed[1]
	if transport_status != HTTPRequest.RESULT_SUCCESS:
		return map_transport_failure(transport_status, response_status)
	return decode_response(response_status, completed[3])

func cancel_all() -> void:
	var active := _active_requests.duplicate()
	_active_requests.clear()
	for http: HTTPRequest in active:
		if not is_instance_valid(http):
			continue
		http.cancel_request()
		http.request_completed.emit(
			HTTPRequest.RESULT_CANT_CONNECT,
			0,
			PackedStringArray(),
			PackedByteArray(),
		)

func build_url(path: String) -> String:
	if path.begins_with("/"):
		return base_url + path
	return base_url + "/" + path

func build_headers(has_body: bool) -> PackedStringArray:
	var headers := PackedStringArray(["Accept: application/json"])
	if _token != "":
		headers.append("Authorization: Bearer " + _token)
	if has_body:
		headers.append("Content-Type: application/json")
	return headers

func decode_response(response_status: int, response_body: PackedByteArray):
	var parsed: Variant = null
	if not response_body.is_empty():
		var json := JSON.new()
		var parse_error := json.parse(response_body.get_string_from_utf8())
		if parse_error != OK:
			return ApiResultScript.unexpected(
				"INVALID_JSON",
				"Server returned malformed JSON: %s" % json.get_error_message(),
				response_status,
			)
		parsed = json.data

	if response_status >= 200 and response_status < 300:
		return ApiResultScript.success(response_status, parsed)

	var error_envelope: Dictionary = {}
	if parsed is Dictionary and parsed.get("error") is Dictionary:
		error_envelope = parsed["error"]
	var code := str(error_envelope.get("code", "HTTP_%d" % response_status))
	var message := str(error_envelope.get("message", "HTTP request failed"))
	return ApiResultScript.failure_for_status(response_status, code, message, parsed)

func map_transport_failure(transport_status: int, response_status: int):
	return ApiResultScript.offline(
		"Network transport failed with result %d (HTTP %d)" % [transport_status, response_status],
	)
