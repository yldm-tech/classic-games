class_name CommerceCoordinator
extends Node

const ApiResultScript:=preload("res://core/http/api_result.gd")

signal payment_finished(session:Dictionary)

class ReadFlight:
	extends RefCounted
	signal completed(success:bool)
	var key:String
	var generation:int
	func _init(p_key:String,p_generation:int)->void:key=p_key;generation=p_generation

var gateway:Variant
var store:CommerceStore
var _read_generation:Dictionary={}
var _read_keys:Dictionary={}
var _read_inflight:Dictionary={}
var _payment_token:=0
var payment_waiter:=Callable()

func _init(p_gateway:Variant,p_store:CommerceStore,p_payment_waiter:=Callable())->void:
	gateway=p_gateway;store=p_store;payment_waiter=p_payment_waiter

func load_points()->bool:
	var ticket:=_read_ticket("points","");var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("points");var result=await gateway.points();var success:=false
	if _current("points",flight.generation) and _object(result,"INVALID_POINTS"):
		store.points=result.data.duplicate(true);store.balance=int(result.data.get("balance",store.balance));store.earnings=result.data.get("earnings",{}).duplicate(true);success=_complete("points",store.points)
	return _resolve_read("points",flight,success)

func load_shop(lang:String="zh")->bool:
	var ticket:=_read_ticket("shop",lang);var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("shop");var result=await gateway.shop(lang);var success:=false
	if _current("shop",flight.generation) and _object(result,"INVALID_SHOP"):store.shop=result.data.duplicate(true);success=_complete("shop",store.shop)
	return _resolve_read("shop",flight,success)

func load_membership(lang:String="zh")->bool:
	var ticket:=_read_ticket("membership",lang);var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("membership");var result=await gateway.membership(lang);var success:=false
	if _current("membership",flight.generation) and _object(result,"INVALID_MEMBERSHIP"):store.membership=result.data.duplicate(true);success=_complete("membership",store.membership)
	return _resolve_read("membership",flight,success)

func load_welfare(lang:String="zh")->bool:
	var ticket:=_read_ticket("welfare",lang);var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("welfare");var result=await gateway.welfare(lang);var success:=false
	if _current("welfare",flight.generation) and _object(result,"INVALID_WELFARE"):
		if result.data.get("quests",null) is Array:store.welfare=result.data.duplicate(true);success=_complete("welfare",store.welfare)
		else:_invalid("INVALID_WELFARE","Welfare quests must be an array")
	return _resolve_read("welfare",flight,success)

func load_events(lang:String="zh")->bool:
	var ticket:=_read_ticket("events",lang);var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("events");var result=await gateway.events(lang);var success:=false
	if _current("events",flight.generation) and _items(result,"INVALID_EVENTS"):
		var joined=await gateway.joined_events()
		if _current("events",flight.generation) and _object(joined,"INVALID_JOINED_EVENTS"):
			if joined.data.get("event_ids",null) is Array:
				store.events=result.data.items.duplicate(true);store.joined_event_ids=joined.data.event_ids.duplicate(true);success=_complete("events",store.events)
			else:_invalid("INVALID_JOINED_EVENTS","Joined event ids must be an array")
	return _resolve_read("events",flight,success)

func load_achievements(lang:String="zh")->bool:
	var ticket:=_read_ticket("achievements",lang);var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("achievements");var result=await gateway.achievements(lang);var success:=false
	if _current("achievements",flight.generation) and _items(result,"INVALID_ACHIEVEMENTS"):store.achievements=result.data.items.duplicate(true);success=_complete("achievements",store.achievements)
	return _resolve_read("achievements",flight,success)

func load_avatar(lang:String="zh")->bool:
	var ticket:=_read_ticket("avatar",lang);var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("avatar");var result=await gateway.avatar_catalog(lang);var success:=false
	if _current("avatar",flight.generation) and _items(result,"INVALID_AVATAR"):
		store.avatar_items=result.data.items.duplicate(true)
		for category:Dictionary in store.avatar_items:
			var id:=str(category.get("id",""));if id=="":continue
			store.equipped_by_category[id]=str(category.get("selected",""))
			for item:Dictionary in category.get("items",[]):
				if item.get("equipped",false):store.equipped_by_category[id]=str(item.get("id",""))
		success=_complete("avatar",store.avatar_items)
	return _resolve_read("avatar",flight,success)

func purchase(item_id:String)->bool:
	var key:="purchase:"+item_id
	if item_id=="" or _pending(key) or _pending("balance_transaction"):return false
	var resources:Array=["points", "shop"];_supersede(resources)
	_set_balance_pending(key,true);store.begin("purchase");var result=await gateway.purchase(item_id);_set_balance_pending(key,false);_supersede(resources)
	if not _object(result,"INVALID_PURCHASE"):return false
	_record_transaction(result.data);store.balance=int(result.data.get("balance",store.balance));if item_id not in store.owned_item_ids:store.owned_item_ids.append(item_id)
	return _finish("shop")

func checkin()->bool:
	var key:="checkin"
	if _pending(key) or _pending("balance_transaction"):return false
	var resources:Array=["points", "welfare"];_supersede(resources)
	_set_balance_pending(key,true);store.begin(key);var result=await gateway.checkin();_set_balance_pending(key,false);_supersede(resources)
	if not _object(result,"INVALID_CHECKIN"):return false
	_record_transaction(result.data);store.balance=int(result.data.get("balance",store.balance));var data:=store.welfare.duplicate(true);var check:Dictionary=data.get("checkin",{}).duplicate(true);check["checked"]=bool(result.data.get("checked",true));data["checkin"]=check;store.welfare=data
	return _finish("welfare")

func claim_quest(id:String)->bool:return await _claim("quest",id,gateway.claim_quest)
func claim_achievement(id:String)->bool:return await _claim("achievement",id,gateway.claim_achievement)

func _claim(kind:String,id:String,request:Callable)->bool:
	var key:=kind+":"+id
	if id=="" or _pending(key) or _pending("balance_transaction"):return false
	var resources:Array=["points", "welfare" if kind=="quest" else "achievements"];_supersede(resources)
	_set_balance_pending(key,true);store.begin("claim_"+kind);var result=await request.call(id);_set_balance_pending(key,false);_supersede(resources)
	if not _object(result,"INVALID_CLAIM"):return false
	_record_transaction(result.data);store.balance=int(result.data.get("balance",store.balance));var collection:Array=store.welfare.get("quests",[]) if kind=="quest" else store.achievements
	for item:Dictionary in collection:
		if str(item.get("id",""))==id:item["claimed"]=bool(result.data.get("claimed",true))
	return _finish("welfare" if kind=="quest" else "achievements")

func equip_avatar(category:String,item:String)->bool:
	var key:="equip:"+category
	if category=="" or item=="" or _pending(key):return false
	var resources:Array=["avatar"];_supersede(resources)
	var previous:=str(store.equipped_by_category.get(category,""));store.equipped_by_category[category]=item;_set_pending(key,true);store.begin("equip_avatar")
	var result=await gateway.equip_avatar(category,item);_set_pending(key,false);_supersede(resources)
	if not result.ok:store.equipped_by_category[category]=previous;store.fail(result);return false
	if not result.data is Dictionary:store.equipped_by_category[category]=previous;return _invalid("INVALID_EQUIP","Equip response must be an object")
	_record_transaction(result.data)
	return _finish("avatar")

func join_event(id:String)->bool:
	var key:="event:"+id
	if id=="" or id in store.joined_event_ids or _pending(key):return false
	var resources:Array=["events"];_supersede(resources)
	_set_pending(key,true);store.begin("join_event");var result=await gateway.join_event(id);_set_pending(key,false)
	_supersede(resources)
	if not _object(result,"INVALID_EVENT"):return false
	_record_transaction(result.data);store.joined_event_ids.append(id);return _finish("events")

func load_withdrawals()->bool:
	var ticket:=_read_ticket("withdrawals","");var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("withdrawals");var result=await gateway.withdrawals();var success:=false
	if _current("withdrawals",flight.generation) and _items(result,"INVALID_WITHDRAWALS"):
		store.withdrawals=result.data.items.duplicate(true);success=_complete("withdrawals",store.withdrawals)
	return _resolve_read("withdrawals",flight,success)

func load_payment_orders()->bool:
	var ticket:=_read_ticket("orders","");var flight:ReadFlight=ticket.flight
	if not ticket.owner:return await flight.completed
	store.begin("orders");var result=await gateway.payment_orders();var success:=false
	if _current("orders",flight.generation) and _items(result,"INVALID_ORDERS"):
		store.order_items=result.data.items.duplicate(true)
		for item:Dictionary in store.order_items:
			var id:=str(item.get("id",""));if id=="":continue
			store.orders[id]=item.duplicate(true)
		success=_complete("orders",store.order_items)
	return _resolve_read("orders",flight,success)

func available_earnings()->int:
	var total:=int(store.earnings.get("total",0));var reserved:=0
	for item:Dictionary in store.withdrawals:
		if str(item.get("status","")) in ["pending","paid"]:reserved+=int(item.get("amount",0))
	return maxi(0,total-reserved)

func has_pending_withdrawal()->bool:
	for item:Dictionary in store.withdrawals:
		if str(item.get("status",""))=="pending":return true
	return str(store.last_withdrawal.get("status",""))=="pending"

func request_withdrawal(amount:int)->bool:
	var key:="withdrawal"
	if amount<=0 or _pending(key):return false
	var resources:Array=["points","withdrawals"];_supersede(resources)
	_set_pending(key,true);store.begin(key);var result=await gateway.request_withdrawal(amount);_set_pending(key,false)
	_supersede(resources)
	if not _object(result,"INVALID_WITHDRAWAL"):return false
	_record_transaction(result.data);store.last_withdrawal=result.data.duplicate(true)
	_prepend_item("withdrawals",result.data);store.bump("withdrawals");return _finish("earnings")

func create_payment_order(product_id:String)->bool:
	var key:="payment_order"
	if product_id=="" or _pending(key) or _pending("payment_session"):return false
	_set_pending(key,true);store.begin("create_order");var result=await gateway.create_payment_order(product_id);_set_pending(key,false)
	if not _object(result,"INVALID_ORDER"):return false
	var id:=str(result.data.get("id",""));if id=="":return _invalid("INVALID_ORDER","Order id is required")
	_record_transaction(result.data);_adopt_order(result.data);return _finish("orders")

func start_payment_session(product_id:String,kind:String,description:String,lang:String,native_starter:Callable)->bool:
	if product_id=="" or kind not in ["points","membership"] or not native_starter.is_valid() or _pending("payment_session") or _pending("payment_order"):return false
	_payment_token+=1;var token:=_payment_token
	_set_pending("payment_session",true)
	store.payment_session={"token":token,"product_id":product_id,"kind":kind,"description":description,"lang":lang,"status":"creating"}
	store.begin("create_order")
	var result=await gateway.create_payment_order(product_id)
	if token!=_payment_token:return false
	if not _object(result,"INVALID_ORDER"):_finish_payment(token,"failed",false,false);return false
	var order_id:=str(result.data.get("id",""))
	if order_id=="":_invalid("INVALID_ORDER","Order id is required");_finish_payment(token,"failed",false,false);return false
	_adopt_order(result.data)
	store.payment_session={"token":token,"product_id":product_id,"kind":kind,"description":description,"lang":lang,
		"order_id":order_id,"status":"native_pending","entitlement_synced":false}
	var transaction_id:=str(native_starter.call(product_id,order_id))
	if transaction_id=="":_finish_payment(token,"failed",false,false);return false
	store.payment_session={"token":token,"product_id":product_id,"kind":kind,"description":description,"lang":lang,
		"order_id":order_id,"transaction_id":transaction_id,"status":"pending","entitlement_synced":false}
	store.touch();_monitor_payment(token)
	return true

func refresh_payment_order(id:String)->bool:
	if id=="":return false
	var result=await gateway.payment_order(id)
	if not _object(result,"INVALID_ORDER"):return false
	if str(result.data.get("id",""))!=id:return _invalid("INVALID_ORDER","Order response id does not match request")
	var current:Dictionary=store.orders.get(id,{})
	if str(current.get("status","")) in ["paid","failed","cancelled"]:return true
	_adopt_order(result.data);return _finish("orders")

func payment_active()->bool:return _pending("payment_session")

func _monitor_payment(token:int)->void:
	while token==_payment_token and int(store.payment_session.get("token",-1))==token:
		if token!=_payment_token or int(store.payment_session.get("token",-1))!=token:return
		var order_id:=str(store.payment_session.get("order_id",""))
		if await refresh_payment_order(order_id):
			var order:Dictionary=store.orders.get(order_id,{})
			var status:=str(order.get("status","pending"))
			if status=="paid":
				await _sync_payment_entitlement_until_ready(token);return
			if status in ["failed","cancelled"]:_finish_payment(token,status,false);return
		await _wait_for_payment_condition()

func _sync_payment_entitlement_until_ready(token:int)->void:
	while token==_payment_token and int(store.payment_session.get("token",-1))==token:
		var session:=store.payment_session.duplicate(true);session["status"]="paid_sync_pending";store.payment_session=session;store.touch()
		var kind:=str(session.get("kind",""));var lang:=str(session.get("lang","zh"));var resources:Array=[kind];_supersede(resources)
		var synced:=await load_points() if kind=="points" else await load_membership(lang)
		_supersede(resources)
		if synced:_finish_payment(token,"paid",true);return
		await _wait_for_payment_condition()

func _wait_for_payment_condition()->void:
	if payment_waiter.is_valid():await payment_waiter.call();return
	await get_tree().create_timer(1.0).timeout

func _finish_payment(token:int,status:String,synced:bool,notify_completion:bool=true)->void:
	if token!=_payment_token or int(store.payment_session.get("token",-1))!=token:return
	var session:=store.payment_session.duplicate(true);session["status"]=status;session["entitlement_synced"]=synced
	store.payment_session=session;_set_pending("payment_session",false);store.touch()
	if notify_completion:payment_finished.emit(session.duplicate(true))

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
	var value:=int(_read_generation.get(resource,0))+1
	_read_generation[resource]=value
	return value

func _current(resource:String,generation:int)->bool:
	return int(_read_generation.get(resource,0))==generation

func _pending(key:String)->bool:
	return bool(store.pending.get(key,false))

func _set_pending(key:String,value:bool)->void:
	if value:store.pending[key]=true
	else:store.pending.erase(key)

func _set_balance_pending(key:String,value:bool)->void:
	_set_pending(key,value);_set_pending("balance_transaction",value)

func _supersede(resources:Array)->void:
	for resource:String in resources:_next(resource)

func _record_transaction(data:Dictionary)->void:
	store.last_transaction=data.duplicate(true)

func _adopt_order(data:Dictionary)->void:
	var id:=str(data.get("id",""));if id=="":return
	store.orders[id]=data.duplicate(true);store.last_order_id=id
	_prepend_item("order_items",data)

func _prepend_item(field:String,data:Dictionary)->void:
	var id:=str(data.get("id",""))
	var current:Array=store.withdrawals if field=="withdrawals" else store.order_items
	var next:Array=[]
	if id!="":next.append(data.duplicate(true))
	for item:Dictionary in current:
		if id=="" or str(item.get("id",""))!=id:next.append(item)
	if field=="withdrawals":store.withdrawals=next
	else:store.order_items=next

func _finish(resource:String)->bool:
	store.bump(resource);store.ready();return true

func _complete(resource:String,value:Variant)->bool:
	store.bump(resource);store.ready("empty" if (value is Array or value is Dictionary) and value.is_empty() else "ready");return true

func _items(result:Variant,code:String)->bool:
	if not _object(result,code):return false
	if not result.data.get("items",null) is Array:return _invalid(code,"Response must contain items")
	return true

func _object(result:Variant,code:String)->bool:
	if not result.ok:store.fail(result);return false
	if not result.data is Dictionary:return _invalid(code,"Response must be an object")
	return true

func _invalid(code:String,message:String)->bool:
	store.fail(ApiResultScript.unexpected(code,message));return false
