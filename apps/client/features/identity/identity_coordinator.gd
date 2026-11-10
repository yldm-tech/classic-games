class_name IdentityCoordinator
extends Node

signal authenticated(flow: String)

const ApiResultScript := preload("res://core/http/api_result.gd")

var gateway: Variant
var store: IdentityStore
var session: Node
var token_sinks: Array
var _was_authenticated := false
var _auth_epoch := 0
var _refresh_flight: RefreshFlight

class RefreshFlight:
	extends RefCounted
	signal completed(success: bool)

func _init(p_gateway: Variant, p_store: IdentityStore, p_session: Node, p_token_sinks: Array = []) -> void:
	gateway = p_gateway
	store = p_store
	session = p_session
	token_sinks = p_token_sinks
	_was_authenticated = bool(session.get("authed"))
	if session.has_signal("session_changed"):
		session.session_changed.connect(_on_session_changed)

func send_code(phone: String) -> bool:
	if not store.begin_send_code():
		return false
	var epoch:=_auth_epoch
	var result = await gateway.send_code(phone) if gateway != null else ApiResultScript.offline("Identity service unavailable")
	if epoch!=_auth_epoch:
		return false
	if not result.ok:
		_fail(result)
		return false
	store.complete_send_code()
	return true

func verify_code(phone: String, code: String) -> bool:
	if not store.begin_authentication():
		return false
	_auth_epoch+=1
	var epoch := _auth_epoch
	var result = await gateway.verify_code(phone, code) if gateway != null else ApiResultScript.offline("Identity service unavailable")
	return _complete_login(result, "sms", epoch)

func guest_login() -> bool:
	if not store.begin_authentication():
		return false
	_auth_epoch+=1
	var epoch := _auth_epoch
	var result = await gateway.guest_login() if gateway != null else ApiResultScript.offline("Identity service unavailable")
	return _complete_login(result, "guest", epoch)

func oauth_exchange(provider: String, code: String) -> bool:
	if not store.begin_authentication():
		return false
	_auth_epoch+=1
	var epoch := _auth_epoch
	var result = await gateway.oauth_exchange(provider, code) if gateway != null else ApiResultScript.offline("Identity service unavailable")
	return _complete_login(result, "oauth", epoch)

func password_login(phone: String, password: String) -> bool:
	if not store.begin_authentication():
		return false
	_auth_epoch+=1
	var epoch := _auth_epoch
	var result = await gateway.password_login(phone, password) if gateway != null else ApiResultScript.offline("Identity service unavailable")
	return _complete_login(result, "password", epoch)

func refresh_session() -> bool:
	if _refresh_flight != null:
		return await _refresh_flight.completed
	if gateway == null or not gateway.has_method("refresh_token"):
		return false
	if str(session.get("token")) == "":
		return false
	var flight := RefreshFlight.new()
	_refresh_flight = flight
	var epoch := _auth_epoch
	var result = await gateway.refresh_token()
	var ok := false
	if epoch == _auth_epoch:
		ok = _apply_refreshed_session(result)
	if _refresh_flight == flight:
		_refresh_flight = null
	flight.completed.emit(ok)
	return ok

func _apply_refreshed_session(result: Variant) -> bool:
	if not result.ok:
		if result.kind == "unauthorized":
			session.logout()
		return false
	if not result.data is Dictionary:
		return false
	var token := str(result.data.get("token", ""))
	if token == "":
		return false
	var user: Dictionary = result.data.get("user", {})
	if user.is_empty() and session.get("profile") is Dictionary:
		user = (session.get("profile") as Dictionary).duplicate(true)
	for sink: Variant in token_sinks:
		if sink != null and sink.has_method("set_token"):
			sink.set_token(token)
	session.login(token, user)
	_was_authenticated = true
	store.complete_authentication({"token": token, "user": user})
	return true

func _complete_login(result: Variant, flow: String, epoch: int) -> bool:
	if epoch != _auth_epoch:
		return false
	if not result.ok:
		_fail(result)
		return false
	if not result.data is Dictionary:
		_fail(ApiResultScript.unexpected("INVALID_SESSION", "Identity response did not contain a session", result.status))
		return false
	var token := str(result.data.get("token", ""))
	var user: Dictionary = result.data.get("user", {})
	for sink: Variant in token_sinks:
		if sink != null and sink.has_method("set_token"):
			sink.set_token(token)
	session.login(token, user)
	_was_authenticated = true
	store.complete_authentication({"token": token, "user": user})
	authenticated.emit(flow)
	return true

func _fail(result: Variant) -> void:
	store.fail(result)

func _on_session_changed() -> void:
	var is_authenticated := bool(session.get("authed"))
	if not is_authenticated:
		_auth_epoch += 1
		store.reset()
	if _was_authenticated and not is_authenticated:
		_was_authenticated = false
		# Starting the coroutine snapshots the old Authorization header before
		# local sinks are cleared. Completion never writes token state.
		_logout_remote()
	else:
		_was_authenticated = is_authenticated
	if not is_authenticated:
		_clear_token_sinks()

func _logout_remote() -> void:
	if gateway != null:
		await gateway.logout()

func _clear_token_sinks() -> void:
	for sink: Variant in token_sinks:
		if sink != null and sink.has_method("set_token"):
			sink.set_token("")
