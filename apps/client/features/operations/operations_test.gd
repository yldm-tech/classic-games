extends SceneTree

const ApiResultScript:=preload("res://core/http/api_result.gd")
const ApiScript:=preload("res://features/operations/operations_api.gd")
const StoreScript:=preload("res://features/operations/operations_store.gd")
const CoordinatorScript:=preload("res://features/operations/operations_coordinator.gd")
const AccountScreenScript:=preload("res://features/operations/account_screen.gd")
const AppStateScript:=preload("res://shell/state/app_state.gd")

class Gate:
	extends RefCounted
	signal released

class IdentityPort:
	extends RefCounted
	var intents:Array=[]
	func send_code(phone:String)->bool:intents.append("send:"+phone);return true

class Transport:
	extends RefCounted
	var requests:Array=[]
	func request(method:int,path:String,body:Variant=null):requests.append({"method":method,"path":path,"body":body});return ApiResultScript.success(200,{})
class Gateway:
	extends RefCounted
	func security():return ApiResultScript.success(200,{"password_set":false})
	func notifications(_l):return ApiResultScript.success(200,{"master_default":true})
	func privacy(_l):return ApiResultScript.success(200,{"items":[]})
	func teen(_l):return ApiResultScript.success(200,{"default_enabled":false})
	func blocks():return ApiResultScript.success(200,{"items":[{"user_id":"u1"}]})
	func verification_status():return ApiResultScript.success(200,{"status":"pending"})
	func set_password(_p):return ApiResultScript.success(200,{"password_set":true})
	func change_phone(_p,_c):return ApiResultScript.success(200,{"phone_masked":"***"})
	func bind_oauth(_p,_c):return ApiResultScript.success(200,{"providers":["apple"]})
	func update_profile(p):return ApiResultScript.success(200,p)
	func submit_verification(_n,_i):return ApiResultScript.success(202,{"status":"pending"})
	func set_notification(_k,_v):return ApiResultScript.success(200,{})
	func set_privacy(_k,_v):return ApiResultScript.success(200,{})
	func set_teen(e,_p):return ApiResultScript.success(200,{"enabled":e})
	func report(_t,_i,_r):return ApiResultScript.success(201,{})
	func block_user(_i):return ApiResultScript.success(201,{})
	func unblock_user(_i):return ApiResultScript.success(204,null)
	func not_interested(_i):return ApiResultScript.success(200,{})
	func feedback(_c):return ApiResultScript.success(202,{})
	func track_event(_n,_s,_t,_d):return ApiResultScript.success(202,{})
	func delete_account():return ApiResultScript.success(204,null)
	func verification_queue():return ApiResultScript.success(200,{"items":[]})
	func decide_verification(_u,_a):return ApiResultScript.success(200,{"status":"verified"})
	var summary_result=ApiResultScript.success(200,{"fork_conversion":0.5,"ai_publish_rate":0.25,"max_fork_depth":3})
	func analytics_summary():return summary_result
	func public_meta():return ApiResultScript.success(200,{"environment":"development","ai":{"mode":"stub"},"sms":false,"oauth_providers":[],"payments":false,"admin_configured":false})

class RaceGateway:
	extends Gateway
	var security_gate:Gate
	var password_gate:Gate
	var delete_gate:Gate
	var security_result=ApiResultScript.success(200,{"password_set":false})
	var password_result=ApiResultScript.success(200,{"password_set":true})
	var delete_results:Array=[]
	var password_calls:=0
	var delete_calls:=0
	var analytics_result=ApiResultScript.success(202,{})
	var security_calls:=0
	func security():
		security_calls+=1
		if security_gate!=null:await security_gate.released
		return security_result
	func set_password(_p):
		password_calls+=1
		if password_gate!=null:await password_gate.released
		return password_result
	func delete_account():
		delete_calls+=1
		if delete_gate!=null:await delete_gate.released
		if not delete_results.is_empty():return delete_results.pop_front()
		return ApiResultScript.success(204,null)
	func track_event(_n,_s,_t,_d):return analytics_result

var passed:=0;var failed:=0
func _initialize()->void:
	await _api_contract();await _coordinator_contract();await _write_serialization_and_read_fence();await _session_invalidation_fences_old_work();await _error_contracts();await _delete_and_analytics_contracts();_account_screen_uses_identity_port();print("operations_test: %d passed, %d failed"%[passed,failed]);quit.call_deferred(0 if failed==0 else 1)
func _api_contract()->void:
	var t:=Transport.new();var api=ApiScript.new(t)
	await api.security();await api.set_password("p");await api.change_phone("1","2");await api.bind_oauth("a","c");await api.delete_account();await api.update_profile({"name":"n"});await api.submit_verification("n","i");await api.verification_status();await api.notifications("ja");await api.privacy("ja");await api.teen("ja");await api.set_notification("a/b",true);await api.set_privacy("x",1);await api.set_teen(true,"1234");await api.blocks();await api.report("game","g","r");await api.block_user("u/1");await api.unblock_user("u/1");	await api.not_interested("g/1");await api.feedback("f");await api.track_event("view","s","g",2);	await api.verification_queue();await api.decide_verification("u/1",true);await api.analytics_summary();await api.public_meta()
	_check("operations api owns all remaining paths",t.requests.size()==25 and t.requests[11].path=="/api/v1/prefs/notifications/a%2Fb" and t.requests[16].path=="/api/v1/block/u%2F1" and t.requests[18].path=="/api/v1/games/g%2F1/not-interested")
	var methods:Array=t.requests.map(func(request):return request.method)
	_check("operations api preserves methods and write payloads",methods==[HTTPClient.METHOD_GET,HTTPClient.METHOD_POST,HTTPClient.METHOD_POST,HTTPClient.METHOD_POST,HTTPClient.METHOD_DELETE,HTTPClient.METHOD_PATCH,HTTPClient.METHOD_POST,HTTPClient.METHOD_GET,HTTPClient.METHOD_GET,HTTPClient.METHOD_GET,HTTPClient.METHOD_GET,HTTPClient.METHOD_POST,HTTPClient.METHOD_POST,HTTPClient.METHOD_POST,HTTPClient.METHOD_GET,HTTPClient.METHOD_POST,HTTPClient.METHOD_POST,HTTPClient.METHOD_DELETE,HTTPClient.METHOD_POST,HTTPClient.METHOD_POST,HTTPClient.METHOD_POST,HTTPClient.METHOD_GET,HTTPClient.METHOD_POST,HTTPClient.METHOD_GET,HTTPClient.METHOD_GET] and t.requests[2].body=={"phone":"1","code":"2"} and t.requests[15].body=={"target_type":"game","target_id":"g","reason":"r"} and t.requests[20].body=={"name":"view","session_id":"s","target_id":"g","depth":2} and t.requests[22].path=="/api/v1/users/u%2F1/verification/decision" and t.requests[23].path=="/api/v1/analytics/summary" and t.requests[24].path=="/api/v1/meta")
func _coordinator_contract()->void:
	var invalidated:={"value":false};var store=StoreScript.new();var c=CoordinatorScript.new(Gateway.new(),store,func():invalidated.value=true)
	_check("operations read models load",await c.load_security() and await c.load_notifications("zh") and await c.load_privacy("zh") and await c.load_teen("zh") and await c.load_blocks() and await c.load_verification() and await c.load_analytics_summary() and await c.load_meta())
	_check("operations analytics and meta are coordinator-owned",store.analytics.fork_conversion==0.5 and store.meta.ai.mode=="stub")
	store.security={"phone_masked":"***1234","providers":["apple"],"password_set":false};store.notifications={"master_key":"push_master","master_default":true,"groups":[{"items":[{"key":"comment","default":true}]}]};store.privacy={"note":"keep","items":[{"key":"online","default":true}]};store.teen={"title":"keep","rules":["rule"],"default_enabled":false}
	_check("operations account writes adopt server models",await c.set_password("p") and await c.change_phone("1","2") and await c.bind_oauth("apple","c") and await c.update_profile({"name":"n"}) and await c.submit_verification("n","i"))
	_check("operations preference and moderation writes complete",await c.set_notification("x",true) and await c.set_privacy("x",1) and await c.set_teen(true,"1234") and await c.report("game","g","r") and await c.block_user("u") and await c.unblock_user("u1") and store.blocks.is_empty() and await c.not_interested("g") and await c.submit_feedback("f") and await c.track_event("view"))
	_check("partial write acknowledgements preserve complete read models",store.security.has("phone_masked") and store.security.has("providers") and store.notifications.has("groups") and store.privacy.has("items") and store.teen.has("rules") and store.teen.default_enabled)
	_check("account deletion hands off session invalidation",await c.delete_account() and invalidated.value)
	c.free();store.free()

func _write_serialization_and_read_fence()->void:
	var gateway:=RaceGateway.new();var store=StoreScript.new();var c=CoordinatorScript.new(gateway,store)
	store.security={"password_set":false,"version":"initial"};gateway.security_gate=Gate.new();gateway.security_result=ApiResultScript.success(200,{"password_set":false,"version":"stale"})
	c.load_security();await process_frame
	_check("confirmed write completes while an older read is pending",await c.set_password("new"))
	gateway.security_gate.released.emit();await process_frame
	_check("older security read cannot overwrite a confirmed write",store.security.get("password_set",false) and store.security.get("version")!="stale")
	gateway.security_gate=Gate.new();gateway.security_result=ApiResultScript.success(200,{"password_set":true,"version":"shared"});c.load_security();await process_frame
	gateway.security_gate.released.emit.call_deferred()
	_check("identical concurrent reads share one request and result",await c.load_security() and gateway.security_calls==2 and store.security.version=="shared")
	gateway.password_gate=Gate.new();c.set_password("first");await process_frame
	gateway.password_gate.released.emit.call_deferred()
	_check("duplicate security writes are rejected while pending",not await c.set_password("second") and gateway.password_calls==2)
	await process_frame;c.free();store.free()

func _session_invalidation_fences_old_work()->void:
	var gateway:=RaceGateway.new();var store=StoreScript.new();var c=CoordinatorScript.new(gateway,store)
	store.security={"phone_masked":"old"};gateway.security_gate=Gate.new();gateway.security_result=ApiResultScript.success(200,{"phone_masked":"stale"});c.load_security();await process_frame
	c.invalidate_session()
	_check("session invalidation clears account-scoped operations state",store.status=="idle" and store.security.is_empty() and store.blocks.is_empty())
	gateway.security_gate.released.emit();await process_frame
	_check("pre-logout reads cannot repopulate a later session",store.security.is_empty())
	c.free();store.free()

func _error_contracts()->void:
	var gateway:=RaceGateway.new();var store=StoreScript.new();var c=CoordinatorScript.new(gateway,store)
	gateway.security_result=ApiResultScript.success(200,[])
	_check("object reads reject malformed success payloads",not await c.load_security() and store.error_code=="INVALID_SECURITY")
	gateway.security_result=ApiResultScript.offline("network down")
	_check("offline reads retain their distinct state",not await c.load_security() and store.status=="offline")
	gateway.password_result=ApiResultScript.success(200,[])
	_check("object writes reject malformed success payloads",not await c.set_password("new") and store.error_code=="INVALID_PASSWORD")
	c.free();store.free()

func _delete_and_analytics_contracts()->void:
	var invalidations:={"count":0};var gateway:=RaceGateway.new();var store=StoreScript.new();var c=CoordinatorScript.new(gateway,store,func():invalidations.count+=1)
	gateway.delete_results=[ApiResultScript.failure_for_status(409,"ACTIVE_ORDER","pending"),ApiResultScript.success(204,null)]
	_check("failed account deletion preserves the session",not await c.delete_account() and invalidations.count==0)
	_check("confirmed account deletion invalidates exactly once",await c.delete_account() and invalidations.count==1)
	store.ready();gateway.analytics_result=ApiResultScript.offline("telemetry unavailable")
	_check("best-effort analytics failure does not poison operations UI state",not await c.track_event("view") and store.status=="ready")
	var deny=Gateway.new();deny.summary_result=ApiResultScript.failure_for_status(403,"FORBIDDEN","admin only")
	var deny_store=StoreScript.new();var deny_c=CoordinatorScript.new(deny,deny_store)
	_check("non-admin analytics summary is an empty ready state",not await deny_c.load_analytics_summary() and deny_store.analytics.is_empty() and deny_store.status=="ready")
	deny_c.free();deny_store.free()
	gateway.delete_gate=Gate.new();c.delete_account();await process_frame;gateway.delete_gate.released.emit.call_deferred()
	_check("duplicate account deletion is rejected while pending",not await c.delete_account() and gateway.delete_calls==3)
	await process_frame;c.free();store.free()
func _account_screen_uses_identity_port()->void:
	var state=AppStateScript.new();state.save_path="user://operations-account-screen-test.cfg";var identity:=IdentityPort.new();var screen=AccountScreenScript.new(state,identity);root.add_child(screen)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;screen.find_child("PhoneRow",true,false).gui_input.emit(click)
	(screen.find_child("NewPhoneEdit",true,false) as LineEdit).text="13900000000";(screen.find_child("PhoneCodeButton",true,false) as Button).pressed.emit()
	_check("operations account screen delegates phone verification to identity port","send:13900000000" in identity.intents)
	screen.free();state.free()
func _check(label:String,condition:bool)->void:
	if condition:passed+=1
	else:failed+=1;push_error("FAIL: "+label)
