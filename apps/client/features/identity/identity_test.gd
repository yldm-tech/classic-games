extends SceneTree

const ApiResultScript := preload("res://core/http/api_result.gd")
const IdentityApiScript := preload("res://features/identity/identity_api.gd")
const IdentityStoreScript := preload("res://features/identity/identity_store.gd")
const IdentityCoordinatorScript := preload("res://features/identity/identity_coordinator.gd")
const AuthScreenScript := preload("res://features/identity/auth_screen.gd")
const AppStateScript := preload("res://shell/state/app_state.gd")

class FakeIdentityGateway:
	extends RefCounted
	signal send_released
	signal verify_released
	signal guest_released
	signal logout_released

	var send_result = ApiResultScript.success(202, {})
	var verify_result = ApiResultScript.success(200, {"token": "token-1", "user": {"id": "user-1", "nickname": "Ada"}})
	var guest_result = ApiResultScript.success(200, {"token": "guest-1", "user": {"id": "guest-user"}})
	var oauth_result = ApiResultScript.success(200, {"token": "oauth-1", "user": {"id": "oauth-user"}})
	var password_result = ApiResultScript.success(200, {"token": "password-1", "user": {"id": "password-user"}})
	var logout_result = ApiResultScript.success(204)
	var refresh_result = ApiResultScript.success(200, {"token": "token-2"})
	var hold_send := false
	var hold_verify := false
	var hold_guest := false
	var hold_logout := false
	var logout_token_probe := Callable()
	var logout_observed_token := ""
	var calls: Array[String] = []

	func send_code(phone: String):
		calls.append("send:" + phone)
		if hold_send:
			await send_released
		return send_result

	func verify_code(phone: String, code: String):
		calls.append("verify:%s:%s" % [phone, code])
		if hold_verify:
			await verify_released
		return verify_result

	func guest_login():
		calls.append("guest")
		if hold_guest:
			await guest_released
		return guest_result

	func oauth_exchange(provider: String, code: String):
		calls.append("oauth:%s:%s" % [provider, code])
		return oauth_result

	func password_login(phone: String, password: String):
		calls.append("password:%s:%s" % [phone, password])
		return password_result

	func logout():
		calls.append("logout")
		if logout_token_probe.is_valid():logout_observed_token=str(logout_token_probe.call())
		if hold_logout:
			await logout_released
		return logout_result

	func refresh_token():
		calls.append("refresh")
		return refresh_result

class FakeSession:
	extends Node
	signal session_changed
	var authed := false
	var token := ""
	var profile: Dictionary = {}

	func login(p_token: String = "", user: Dictionary = {}) -> void:
		authed = true
		token = p_token
		profile = user.duplicate(true)
		session_changed.emit()

	func logout() -> void:
		authed = false
		token = ""
		session_changed.emit()

class FakeTokenSink:
	extends RefCounted
	var token := ""

	func set_token(value: String) -> void:
		token = value

class FakeIdentityCoordinator:
	extends RefCounted
	var intents: Array[String] = []

	func send_code(phone: String) -> bool:
		intents.append("send:" + phone)
		return true

	func verify_code(phone: String, code: String) -> bool:
		intents.append("verify:%s:%s" % [phone, code])
		return true

	func guest_login() -> bool:
		intents.append("guest")
		return true

	func oauth_exchange(provider: String, code: String) -> bool:
		intents.append("oauth:%s:%s" % [provider, code])
		return true

	func password_login(phone: String, password: String) -> bool:
		intents.append("password:%s:%s" % [phone, password])
		return true

class FakeTransport:
	extends RefCounted
	var requests: Array[Dictionary] = []

	func request(method: int, path: String, body: Variant = null):
		requests.append({"method": method, "path": path, "body": body})
		return ApiResultScript.success(200, {"token": "transport-token", "user": {"id": "transport-user"}})

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await _test_gateway_owns_endpoint_paths()
	await _test_send_code_transition()
	await _test_successful_login_updates_session()
	await _test_all_authentication_flows_update_session()
	await _test_failure_states_are_distinct()
	await _test_duplicate_submit_is_rejected()
	await _test_stale_send_code_cannot_overwrite_new_login()
	await _test_logout_clears_transport_token()
	await _test_stale_login_cannot_restore_logged_out_session()
	await _test_old_logout_cannot_clear_new_login_token()
	_test_screen_delegates_intents()
	await _test_refresh_rotates_token()
	await _test_failed_refresh_logs_out()
	print("identity_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_gateway_owns_endpoint_paths() -> void:
	var transport := FakeTransport.new()
	var gateway = IdentityApiScript.new(transport)
	await gateway.send_code("13812342380")
	await gateway.verify_code("13812342380", "246810")
	await gateway.guest_login()
	await gateway.oauth_exchange("google", "oauth-code")
	await gateway.password_login("13812342380", "password")
	await gateway.logout()
	await gateway.refresh_token()
	var paths: Array = transport.requests.map(func(entry: Dictionary): return entry.path)
	_check("identity gateway owns all endpoint paths", paths == [
		"/api/v1/auth/sms/send",
		"/api/v1/auth/sms/verify",
		"/api/v1/auth/guest",
		"/api/v1/auth/oauth/google",
		"/api/v1/auth/password/login",
		"/api/v1/auth/logout",
		"/api/v1/auth/refresh",
	])
	_check("identity gateway maps request DTOs", transport.requests[1].body == {"phone": "13812342380", "code": "246810"})

func _test_send_code_transition() -> void:
	var fixture := _fixture()
	fixture.gateway.hold_send = true
	fixture.coordinator.send_code("13812342380")
	_check("send code enters pending state", fixture.store.status == "sending_code")
	fixture.gateway.send_released.emit()
	await process_frame
	_check("send code success becomes ready", fixture.store.status == "ready" and fixture.store.code_sent)
	fixture.free_all.call()

func _test_successful_login_updates_session() -> void:
	var fixture := _fixture()
	var accepted: bool = await fixture.coordinator.verify_code("13812342380", "246810")
	_check("login succeeds", accepted and fixture.store.status == "authenticated")
	_check("login updates session", fixture.session.authed and fixture.session.token == "token-1" and fixture.session.profile.id == "user-1")
	_check("login updates every token sink", fixture.token_sink.token == "token-1")
	fixture.free_all.call()

func _test_all_authentication_flows_update_session() -> void:
	var fixture := _fixture()
	var guest_ok: bool = await fixture.coordinator.guest_login()
	var oauth_ok: bool = await fixture.coordinator.oauth_exchange("google", "oauth-code")
	var password_ok: bool = await fixture.coordinator.password_login("13812342380", "password")
	_check("guest, OAuth, and password flows succeed", guest_ok and oauth_ok and password_ok)
	_check("latest authentication replaces session", fixture.session.token == "password-1" and fixture.token_sink.token == "password-1")
	fixture.free_all.call()

func _test_failure_states_are_distinct() -> void:
	var cases := [
		[ApiResultScript.failure_for_status(401, "AUTH_INVALID", "bad code"), "unauthorized"],
		[ApiResultScript.failure_for_status(422, "PHONE_INVALID", "bad phone"), "validation_error"],
		[ApiResultScript.offline("no network"), "offline"],
	]
	for test_case: Array in cases:
		var fixture := _fixture()
		fixture.gateway.verify_result = test_case[0]
		var accepted: bool = await fixture.coordinator.verify_code("13812342380", "bad")
		_check("%s failure is rejected" % test_case[1], not accepted)
		_check("%s has distinct store state" % test_case[1], fixture.store.status == test_case[1])
		fixture.free_all.call()

func _test_duplicate_submit_is_rejected() -> void:
	var fixture := _fixture()
	fixture.gateway.hold_verify = true
	fixture.coordinator.verify_code("13812342380", "246810")
	_check("first submit is pending", fixture.store.status == "authenticating")
	var duplicate: bool = await fixture.coordinator.verify_code("13812342380", "246810")
	_check("duplicate submit is rejected", not duplicate and fixture.gateway.calls.count("verify:13812342380:246810") == 1)
	fixture.gateway.verify_released.emit()
	await process_frame
	fixture.free_all.call()

func _test_stale_send_code_cannot_overwrite_new_login() -> void:
	var fixture:=_fixture()
	fixture.gateway.hold_send=true
	fixture.coordinator.send_code("13812342380")
	var logged_in:bool=await fixture.coordinator.password_login("13812342380","password")
	fixture.gateway.send_released.emit()
	await process_frame
	_check("stale send-code completion cannot overwrite a newer login",logged_in and fixture.store.status==IdentityStoreScript.AUTHENTICATED and fixture.session.token=="password-1")
	fixture.free_all.call()

func _test_logout_clears_transport_token() -> void:
	var fixture := _fixture()
	await fixture.coordinator.verify_code("13812342380", "246810")
	fixture.session.logout()
	await process_frame
	_check("logout reaches identity gateway", fixture.gateway.calls.count("logout") == 1)
	_check("logout clears transport token", fixture.token_sink.token == "")
	fixture.free_all.call()

func _test_stale_login_cannot_restore_logged_out_session() -> void:
	var fixture := _fixture()
	fixture.gateway.hold_guest = true
	fixture.coordinator.guest_login()
	fixture.session.logout()
	fixture.gateway.guest_released.emit()
	await process_frame
	_check("stale authentication cannot restore a logged-out session", not fixture.session.authed and fixture.token_sink.token == "")
	fixture.free_all.call()

func _test_old_logout_cannot_clear_new_login_token() -> void:
	var fixture := _fixture()
	await fixture.coordinator.verify_code("13812342380", "246810")
	fixture.gateway.hold_logout = true
	fixture.session.logout()
	await process_frame
	_check("remote logout starts with the previous bearer token",fixture.gateway.logout_observed_token=="token-1" and fixture.token_sink.token=="")
	var logged_in: bool = await fixture.coordinator.password_login("13812342380", "new-password")
	fixture.gateway.logout_released.emit()
	await process_frame
	_check("old logout completion cannot clear a newer login token", logged_in and fixture.session.token == "password-1" and fixture.token_sink.token == "password-1")
	fixture.free_all.call()

func _test_refresh_rotates_token() -> void:
	var fixture := _fixture()
	await fixture.coordinator.verify_code("13812342380", "246810")
	var ok: bool = await fixture.coordinator.refresh_session()
	_check("refresh replaces the bearer token", ok and fixture.session.token == "token-2" and fixture.token_sink.token == "token-2")
	_check("refresh keeps the existing profile", fixture.session.profile.id == "user-1")
	fixture.free_all.call()

func _test_failed_refresh_logs_out() -> void:
	var fixture := _fixture()
	await fixture.coordinator.verify_code("13812342380", "246810")
	fixture.gateway.refresh_result = ApiResultScript.failure_for_status(401, "AUTH_REQUIRED", "expired")
	var ok: bool = await fixture.coordinator.refresh_session()
	_check("failed refresh logs out honestly", not ok and not fixture.session.authed and fixture.token_sink.token == "")
	fixture.free_all.call()

func _test_screen_delegates_intents() -> void:
	var state = AppStateScript.new()
	state.save_path = "user://identity-screen-test.cfg"
	var coordinator := FakeIdentityCoordinator.new()
	var screen = AuthScreenScript.new(state, coordinator)
	root.add_child(screen)
	(screen.find_child("PhoneEdit", true, false) as LineEdit).text = "13812342380"
	(screen.find_child("CodeEdit", true, false) as LineEdit).text = "246810"
	(screen.find_child("GetCodeButton", true, false) as Button).pressed.emit()
	(screen.find_child("LoginButton", true, false) as Button).pressed.emit()
	(screen.find_child("GuestButton", true, false) as Button).pressed.emit()
	_check("screen emits send intent without URL", "send:13812342380" in coordinator.intents)
	_check("screen emits login intent without URL", "verify:13812342380:246810" in coordinator.intents)
	_check("screen emits guest intent without URL", "guest" in coordinator.intents)
	_check("screen source has no endpoint paths", not FileAccess.get_file_as_string("res://features/identity/auth_screen.gd").contains("/api/"))
	screen.free()
	state.free()

func _fixture() -> Dictionary:
	var gateway := FakeIdentityGateway.new()
	var store = IdentityStoreScript.new()
	var session := FakeSession.new()
	var token_sink := FakeTokenSink.new()
	var coordinator = IdentityCoordinatorScript.new(gateway, store, session, [token_sink])
	gateway.logout_token_probe=func():return token_sink.token
	return {
		"gateway": gateway,
		"store": store,
		"session": session,
		"token_sink": token_sink,
		"coordinator": coordinator,
		"free_all": func() -> void:
			coordinator.free()
			store.free()
			session.free(),
	}

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
