class_name OperationsCoordinator
extends Node

const ApiResultScript:=preload("res://core/http/api_result.gd")
const ACCOUNT_RESOURCES:=["security","notifications","privacy","teen","blocks","profile","verification","verification_queue","analytics"]

class ReadFlight:
	extends RefCounted
	signal completed(success:bool)
	var key:String
	var generation:int
	func _init(p_key:String,p_generation:int)->void:key=p_key;generation=p_generation

var gateway:Variant
var store:OperationsStore
var session_invalidator:Callable
var analytics_session_id:String
var _read_generation:Dictionary={}
var _read_keys:Dictionary={}
var _read_inflight:Dictionary={}
var _pending:Dictionary={}
var _epoch:=0

func _init(p_gateway:Variant,p_store:OperationsStore,p_session_invalidator:=Callable())->void:
	gateway=p_gateway;store=p_store;session_invalidator=p_session_invalidator;analytics_session_id=Crypto.new().generate_random_bytes(16).hex_encode()

func load_security()->bool:return await _load_object("security","",gateway.security,func(data):store.security=data)
func load_notifications(lang:String)->bool:return await _load_object("notifications",lang,func():return await gateway.notifications(lang),func(data):store.notifications=data)
func load_privacy(lang:String)->bool:return await _load_object("privacy",lang,func():return await gateway.privacy(lang),func(data):store.privacy=data)
func load_teen(lang:String)->bool:return await _load_object("teen",lang,func():return await gateway.teen(lang),func(data):store.teen=data)
func load_blocks()->bool:
	var ticket:=_read_ticket("blocks","");var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("blocks");var result=await gateway.blocks();var success:=false
	if _current("blocks",flight.generation) and _object(result,"INVALID_BLOCKS"):
		if result.data.get("items",null) is Array:store.blocks=result.data.items.duplicate(true);store.ready(store.blocks.is_empty());success=true
		else:_invalid("INVALID_BLOCKS","Blocks must contain items")
	return _resolve_read("blocks",flight,success)
func load_verification()->bool:return await _load_object("verification","",gateway.verification_status,func(data):store.verification=data)
func load_verification_queue()->bool:
	var ticket:=_read_ticket("verification_queue","");var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("verification_queue");var result=await gateway.verification_queue();var success:=false
	if _current("verification_queue",flight.generation):
		if result.ok and result.data is Dictionary and result.data.get("items",null) is Array:
			store.verification_queue=result.data.items.duplicate(true);store.ready(store.verification_queue.is_empty());success=true
		elif result.status==403 or result.kind=="unauthorized":
			store.verification_queue=[];store.ready();success=false
		else:store.fail(result)
	return _resolve_read("verification_queue",flight,success)
func load_analytics_summary()->bool:
	var ticket:=_read_ticket("analytics","");var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("analytics");var result=await gateway.analytics_summary();var success:=false
	if _current("analytics",flight.generation):
		if result.ok and result.data is Dictionary:
			store.analytics=result.data.duplicate(true);store.ready(store.analytics.is_empty());success=true
		elif result.status==403 or result.kind=="unauthorized":
			store.analytics={};store.ready();success=false
		else:store.fail(result)
	return _resolve_read("analytics",flight,success)
func load_meta()->bool:return await _load_object("meta","",gateway.public_meta,func(data):store.meta=data)
func decide_verification(user_id:String,approve:bool)->bool:
	return await _write("verification_decision","verification_queue","verification_decision",func():return await gateway.decide_verification(user_id,approve),func(_data):
		store.verification_queue=store.verification_queue.filter(func(item):return str(item.get("user_id",""))!=user_id))

func set_password(password:String)->bool:return await _write("password","security","security_write",func():return await gateway.set_password(password),func(data):store.security.merge(data,true))
func change_phone(phone:String,code:String)->bool:return await _write("phone","security","security_write",func():return await gateway.change_phone(phone,code),func(data):store.security.merge(data,true))
func bind_oauth(provider:String,code:String)->bool:return await _write("oauth","security","security_write",func():return await gateway.bind_oauth(provider,code),func(data):store.security.merge(data,true))
func update_profile(profile:Dictionary)->bool:return await _write("profile","profile","profile_write",func():return await gateway.update_profile(profile),func(data):store.profile.merge(data,true))
func submit_verification(name:String,id_number:String)->bool:return await _write("verification","verification","verification_write",func():return await gateway.submit_verification(name,id_number),func(data):store.verification.merge(data,true))
func set_notification(key:String,value:bool)->bool:return await _write("notification","notifications","notifications_write",func():return await gateway.set_notification(key,value),func(data):
	_set_notification_model(key,value))
func set_privacy(key:String,value:Variant)->bool:return await _write("privacy","privacy","privacy_write",func():return await gateway.set_privacy(key,value),func(data):
	_set_privacy_model(key,value))
func set_teen(enabled:bool,pin:String)->bool:return await _write("teen","teen","teen_write",func():return await gateway.set_teen(enabled,pin),func(data):
	store.teen["default_enabled"]=enabled)
func report(target_type:String,id:String,reason:String)->bool:return await _simple("report","report_action",func():return await gateway.report(target_type,id,reason))
func block_user(id:String)->bool:return await _simple("block","report_action",func():return await gateway.block_user(id),["blocks"])
func unblock_user(id:String)->bool:
	return await _simple("unblock","unblock:"+id,func():return await gateway.unblock_user(id),["blocks"],func():store.blocks=store.blocks.filter(func(item):return str(item.get("user_id",""))!=id))
func not_interested(id:String)->bool:return await _simple("not_interested","report_action",func():return await gateway.not_interested(id))
func submit_feedback(content:String)->bool:return await _simple("feedback","feedback",func():return await gateway.feedback(content))
func track_event(name:String,target_id:String="",depth:int=0)->bool:
	var epoch:=_epoch;var result=await gateway.track_event(name,analytics_session_id,target_id,depth)
	return epoch==_epoch and result.ok
func delete_account()->bool:
	if not await _simple("delete_account","delete_account",gateway.delete_account):return false
	if session_invalidator.is_valid():session_invalidator.call()
	return true

func invalidate_session()->void:
	_epoch+=1;_supersede(ACCOUNT_RESOURCES);_read_keys.clear();_read_inflight.clear();_pending.clear();store.reset()

func _load_object(resource:String,key:String,request:Callable,accept:Callable)->bool:
	var ticket:=_read_ticket(resource,key);var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin(resource);var result=await request.call();var success:=false
	if _current(resource,flight.generation) and _object(result,"INVALID_"+resource.to_upper()):
		var data:Dictionary=result.data.duplicate(true);accept.call(data);store.ready(data.is_empty());success=true
	return _resolve_read(resource,flight,success)
func _write(operation:String,resource:String,pending_key:String,request:Callable,accept:Callable)->bool:
	if _is_pending(pending_key):return false
	var epoch:=_epoch;_set_pending(pending_key,epoch);_next(resource);store.begin(operation);var result=await request.call();_release_pending(pending_key,epoch)
	if epoch!=_epoch:return false
	_next(resource)
	if not _object(result,"INVALID_"+operation.to_upper()):return false
	accept.call(result.data.duplicate(true));store.ready();return true
func _simple(operation:String,pending_key:String,request:Callable,resources:Array=[],accept:=Callable())->bool:
	if _is_pending(pending_key):return false
	var epoch:=_epoch;_set_pending(pending_key,epoch);_supersede(resources);store.begin(operation);var result=await request.call();_release_pending(pending_key,epoch)
	if epoch!=_epoch:return false
	_supersede(resources)
	if not result.ok:store.fail(result);return false
	if accept.is_valid():accept.call()
	store.ready();return true
func _read_ticket(resource:String,key:String)->Dictionary:
	var generation:=int(_read_generation.get(resource,0))
	if not _read_keys.has(resource):_read_keys[resource]=key
	elif str(_read_keys[resource])!=key:_read_keys[resource]=key;generation=_next(resource)
	var existing:Variant=_read_inflight.get(resource)
	if existing is ReadFlight and existing.key==key and existing.generation==generation:return {"owner":false,"flight":existing}
	var flight:=ReadFlight.new(key,generation);_read_inflight[resource]=flight;return {"owner":true,"flight":flight}
func _resolve_read(resource:String,flight:ReadFlight,success:bool)->bool:
	if _read_inflight.get(resource)==flight:_read_inflight.erase(resource)
	flight.completed.emit(success);return success
func _next(resource:String)->int:
	var value:=int(_read_generation.get(resource,0))+1;_read_generation[resource]=value;return value
func _current(resource:String,generation:int)->bool:return int(_read_generation.get(resource,0))==generation
func _supersede(resources:Array)->void:
	for resource:String in resources:_next(resource)
func _is_pending(key:String)->bool:return _pending.has(key)
func _set_pending(key:String,epoch:int)->void:_pending[key]=epoch
func _release_pending(key:String,epoch:int)->void:
	if int(_pending.get(key,-1))==epoch:_pending.erase(key)
func _set_notification_model(key:String,value:bool)->void:
	if str(store.notifications.get("master_key",""))==key:store.notifications["master_default"]=value
	var groups:Array=store.notifications.get("groups",[])
	for group:Dictionary in groups:
		for item:Dictionary in group.get("items",[]):
			if str(item.get("key",""))==key:item["default"]=value
func _set_privacy_model(key:String,value:Variant)->void:
	var items:Array=store.privacy.get("items",[])
	for item:Dictionary in items:
		if str(item.get("key",""))==key:
			if str(item.get("kind",""))=="segment":item["default_index"]=int(value)
			else:item["default"]=bool(value)
func _object(result:Variant,code:String)->bool:
	if not result.ok:store.fail(result);return false
	if not result.data is Dictionary:return _invalid(code,"Response must be an object")
	return true
func _invalid(code:String,message:String)->bool:store.fail(ApiResultScript.unexpected(code,message));return false
