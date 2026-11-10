class_name IdentityApi
extends RefCounted

var _transport: Variant

func _init(transport: Variant) -> void:
	_transport = transport

func send_code(phone: String):
	return await _transport.request(HTTPClient.METHOD_POST, "/api/v1/auth/sms/send", {"phone": phone})

func verify_code(phone: String, code: String):
	return await _transport.request(
		HTTPClient.METHOD_POST,
		"/api/v1/auth/sms/verify",
		{"phone": phone, "code": code},
	)

func guest_login():
	return await _transport.request(HTTPClient.METHOD_POST, "/api/v1/auth/guest", {})

func oauth_exchange(provider: String, code: String):
	return await _transport.request(
		HTTPClient.METHOD_POST,
		"/api/v1/auth/oauth/%s" % provider.uri_encode(),
		{"code": code},
	)

func password_login(phone: String, password: String):
	return await _transport.request(
		HTTPClient.METHOD_POST,
		"/api/v1/auth/password/login",
		{"phone": phone, "password": password},
	)

func logout():
	return await _transport.request(HTTPClient.METHOD_POST, "/api/v1/auth/logout", {})

func refresh_token():
	return await _transport.request(HTTPClient.METHOD_POST, "/api/v1/auth/refresh", {})
