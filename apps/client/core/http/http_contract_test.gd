extends SceneTree

const ApiResultScript := preload("res://core/http/api_result.gd")
const HttpClientScript := preload("res://core/http/http_client.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_result_kinds()
	_test_http_mapping()
	_test_request_construction()
	_test_cancellation()
	print("http_contract_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_result_kinds() -> void:
	var success = ApiResultScript.success(200, {"id": "game-1"})
	_check("success keeps payload", success.ok and success.kind == "success" and success.data.id == "game-1")

	var offline = ApiResultScript.offline("connection refused")
	_check("offline is explicit", not offline.ok and offline.kind == "offline" and offline.status == 0)

	var expected := {
		401: "unauthorized",
		400: "validation",
		422: "validation",
		409: "conflict",
		429: "rate_limited",
		500: "unexpected",
	}
	for status: int in expected:
		var result = ApiResultScript.failure_for_status(status, "EXAMPLE", "message")
		_check("status %d maps to %s" % [status, expected[status]], result.kind == expected[status])

func _test_http_mapping() -> void:
	var client = HttpClientScript.new("https://api.example.test")
	var success = client.decode_response(201, '{"id":"mod-1"}'.to_utf8_buffer())
	_check("client decodes success JSON", success.ok and success.status == 201 and success.data.id == "mod-1")

	var rejected = client.decode_response(
		422,
		'{"error":{"code":"DSL_INVALID","message":"invalid hp"}}'.to_utf8_buffer(),
	)
	_check("client decodes error envelope", not rejected.ok and rejected.kind == "validation")
	_check("client keeps error details", rejected.code == "DSL_INVALID" and rejected.message == "invalid hp")

	var malformed = client.decode_response(200, "not-json".to_utf8_buffer())
	_check("malformed JSON is unexpected", not malformed.ok and malformed.kind == "unexpected" and malformed.code == "INVALID_JSON")

	var transport = client.map_transport_failure(HTTPRequest.RESULT_CANT_CONNECT, 0)
	_check("transport failures are offline", not transport.ok and transport.kind == "offline")
	client.free()

func _test_request_construction() -> void:
	var client = HttpClientScript.new("https://api.example.test/")
	client.set_token("secret-token")
	var headers: PackedStringArray = client.build_headers(true)
	_check("bearer token is centralized", "Authorization: Bearer secret-token" in headers)
	_check("JSON content type is centralized", "Content-Type: application/json" in headers)
	_check("caller supplies endpoint path", client.build_url("/api/v1/games") == "https://api.example.test/api/v1/games")
	client.free()
	_check("https API is allowed", HttpClientScript.is_secure_base("https://api.forgeplay.app"))
	_check("loopback http is allowed", HttpClientScript.is_secure_base("http://127.0.0.1:8080"))
	_check("spoofed loopback host is rejected", not HttpClientScript.is_secure_base("http://127.0.0.1.evil.test"))
	_check("public http is rejected", not HttpClientScript.is_secure_base("http://api.example.test"))
	var blocked = HttpClientScript.new("http://api.example.test")
	var denied = blocked.reject_insecure_base()
	_check("cleartext request is offline", denied != null and not denied.ok and denied.code == "INSECURE_URL")
	blocked.free()
	var retry_client = HttpClientScript.new("https://api.example.test")
	var unauthorized = ApiResultScript.failure_for_status(401, "AUTH_REQUIRED", "expired")
	_check("401 without refresh handler is not retried", not retry_client.should_retry_unauthorized("/api/v1/games", unauthorized))
	retry_client.set_refresh_handler(func(): return true)
	_check("401 on API path can refresh", retry_client.should_retry_unauthorized("/api/v1/games", unauthorized))
	_check("401 on auth path does not refresh", not retry_client.should_retry_unauthorized("/api/v1/auth/refresh", unauthorized))
	retry_client.free()

func _test_cancellation() -> void:
	var client = HttpClientScript.new("https://api.example.test")
	root.add_child(client)
	var request := HTTPRequest.new()
	client.add_child(request)
	client._active_requests.append(request)
	var probe := {"result": null}
	_capture_cancellation(request, client, probe)
	client.cancel_all()
	_check("cancel_all resolves awaiters as offline", probe.result != null and probe.result.kind == "offline")
	_check("cancel_all clears active requests", client._active_requests.is_empty())
	client.free()

func _capture_cancellation(request: HTTPRequest, client: HttpClient, probe: Dictionary) -> void:
	var completed: Array = await request.request_completed
	probe.result = client.map_transport_failure(completed[0], completed[1])

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
