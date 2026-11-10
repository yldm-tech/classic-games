class_name OperationsApi
extends RefCounted

var transport:Variant
func _init(p_transport:Variant)->void:transport=p_transport

func security():return await _request_get("/api/v1/users/me/security")
func set_password(password:String):return await _post("/api/v1/users/me/password",{"password":password})
func change_phone(phone:String,code:String):return await _post("/api/v1/users/me/phone",{"phone":phone,"code":code})
func bind_oauth(provider:String,code:String):return await _post("/api/v1/users/me/oauth/bind",{"provider":provider,"code":code})
func delete_account():return await transport.request(HTTPClient.METHOD_DELETE,"/api/v1/users/me")
func update_profile(profile:Dictionary):return await transport.request(HTTPClient.METHOD_PATCH,"/api/v1/users/me",profile)
func submit_verification(name:String,id_number:String):return await _post("/api/v1/auth/realname",{"name":name,"id_number":id_number})
func verification_status():return await _request_get("/api/v1/users/me/verification")
func verification_queue():return await _request_get("/api/v1/verifications/queue")
func decide_verification(user_id:String,approve:bool):return await _post("/api/v1/users/%s/verification/decision"%user_id.uri_encode(),{"approve":approve})
func notifications(lang:String="zh"):return await _request_get("/api/v1/prefs/notifications?lang=%s"%lang.uri_encode())
func privacy(lang:String="zh"):return await _request_get("/api/v1/prefs/privacy?lang=%s"%lang.uri_encode())
func teen(lang:String="zh"):return await _request_get("/api/v1/prefs/teen?lang=%s"%lang.uri_encode())
func set_notification(key:String,value:bool):return await _post("/api/v1/prefs/notifications/%s"%key.uri_encode(),{"value":value})
func set_privacy(key:String,value:Variant):return await _post("/api/v1/prefs/privacy/%s"%key.uri_encode(),{"value":value})
func set_teen(enabled:bool,pin:String):return await _post("/api/v1/prefs/teen",{"enabled":enabled,"pin":pin})
func blocks():return await _request_get("/api/v1/blocks")
func report(target_type:String,target_id:String,reason:String):return await _post("/api/v1/report",{"target_type":target_type,"target_id":target_id,"reason":reason})
func block_user(user_id:String):return await _post("/api/v1/block/%s"%user_id.uri_encode(),{})
func unblock_user(user_id:String):return await transport.request(HTTPClient.METHOD_DELETE,"/api/v1/block/%s"%user_id.uri_encode())
func not_interested(game_id:String):return await _post("/api/v1/games/%s/not-interested"%game_id.uri_encode(),{})
func feedback(content:String):return await _post("/api/v1/feedback",{"content":content})
func track_event(name:String,session_id:String,target_id:String="",depth:int=0):
	return await _post("/api/v1/analytics/events",{"name":name,"session_id":session_id,"target_id":target_id,"depth":depth})
func analytics_summary():return await _request_get("/api/v1/analytics/summary")
func public_meta():return await _request_get("/api/v1/meta")

func _request_get(path:String):return await transport.request(HTTPClient.METHOD_GET,path)
func _post(path:String,body:Dictionary):return await transport.request(HTTPClient.METHOD_POST,path,body)
