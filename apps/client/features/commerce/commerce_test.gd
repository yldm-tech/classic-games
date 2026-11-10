extends SceneTree

const ApiResultScript := preload("res://core/http/api_result.gd")
const CommerceApiScript := preload("res://features/commerce/commerce_api.gd")
const CommerceStoreScript := preload("res://features/commerce/commerce_store.gd")
const CommerceCoordinatorScript := preload("res://features/commerce/commerce_coordinator.gd")
const ShopScreenScript := preload("res://features/commerce/shop_screen.gd")
const MembershipScreenScript := preload("res://features/commerce/membership_screen.gd")
const AppStateScript := preload("res://shell/state/app_state.gd")

class Gate:
	extends RefCounted
	signal released

class RetryWaiter:
	extends RefCounted
	signal released
	func wait()->void:await released

class FakeTransport:
	extends RefCounted
	var requests: Array[Dictionary] = []
	func request(method: int, path: String, body: Variant = null):
		requests.append({"method":method,"path":path,"body":body})
		return ApiResultScript.success(200, {})

class FakeGateway:
	extends RefCounted
	var gates: Dictionary = {}
	var calls: Dictionary = {}
	var equip_result = ApiResultScript.success(200, {"equipped":true})
	var payment_status := "paid"
	var points_results:Array=[]
	func _wait(key: String) -> void:
		calls[key] = int(calls.get(key, 0)) + 1
		if gates.has(key): await (gates[key] as Gate).released
	func points():
		await _wait("load:points")
		if not points_results.is_empty():return points_results.pop_front()
		return ApiResultScript.success(200, {"balance":100,"ledger":[],"earnings":{"total":50,"weekly":[1],"ledger":[]}})
	func shop(_lang:String): return ApiResultScript.success(200, {"skins":[],"items":[],"recharge":[]})
	func membership(_lang:String): return ApiResultScript.success(200, {"active":true,"plans":[],"perks":[]})
	func welfare(_lang:String): return ApiResultScript.success(200, {"checkin":{"checked":false},"quests":[{"id":"q1","claimed":false}],"invite":{}})
	func events(_lang:String): return ApiResultScript.success(200, {"items":[{"id":"e1"}]})
	func joined_events(): return ApiResultScript.success(200, {"event_ids":[]})
	func achievements(_lang:String): return ApiResultScript.success(200, {"items":[{"id":"a1","claimed":false}]})
	func avatar_catalog(_lang:String): return ApiResultScript.success(200, {"items":[{"id":"hair","selected":"old"}]})
	func purchase(id:String): await _wait("purchase:"+id); return ApiResultScript.success(200, {"balance":80,"owned":true})
	func checkin(): await _wait("checkin"); return ApiResultScript.success(200, {"balance":110,"checked":true,"reward":10})
	func claim_quest(id:String): await _wait("quest:"+id); return ApiResultScript.success(200, {"balance":120,"claimed":true})
	func claim_achievement(id:String): await _wait("achievement:"+id); return ApiResultScript.success(200, {"balance":130,"claimed":true})
	func equip_avatar(category:String,item:String): await _wait("equip:"+category); return equip_result
	func join_event(id:String): await _wait("event:"+id); return ApiResultScript.success(200, {"id":id,"joined":true})
	func request_withdrawal(amount:int): await _wait("withdrawal"); return ApiResultScript.success(202, {"id":"w1","amount":amount,"status":"pending"})
	func withdrawals(): await _wait("load:withdrawals"); return ApiResultScript.success(200, {"items":[{"id":"w0","amount":80,"status":"paid"}]})
	func create_payment_order(product:String): await _wait("order:"+product); return ApiResultScript.success(201, {"id":"o1","product_id":product,"status":"pending"})
	func payment_orders(): await _wait("load:orders"); return ApiResultScript.success(200, {"items":[{"id":"o0","product_id":"tier_60","status":"paid"}]})
	func payment_order(id:String): await _wait("payment:"+id); return ApiResultScript.success(200, {"id":id,"status":payment_status})

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await _test_api_owns_commerce_paths()
	await _test_loads_and_confirmed_transactions()
	await _test_duplicate_writes_and_optimistic_rollback()
	await _test_writes_supersede_stale_reads()
	await _test_shared_reads_do_not_cancel_consumers()
	await _test_payment_order_refresh_is_keyed()
	await _test_payment_session_owns_lifecycle_and_syncs_entitlement()
	await _test_payment_presentation_survives_rebuild_without_hidden_navigation()
	await _test_payment_retries_sync_and_waits_for_terminal()
	print("commerce_test: %d passed, %d failed" % [_passed,_failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_api_owns_commerce_paths() -> void:
	var transport := FakeTransport.new(); var api = CommerceApiScript.new(transport)
	await api.points(); await api.shop("ja"); await api.membership("ja"); await api.welfare("ja"); await api.events("ja"); await api.joined_events()
	await api.achievements("ja"); await api.avatar_catalog("ja"); await api.purchase("i/1"); await api.checkin(); await api.claim_quest("q/1")
	await api.claim_achievement("a/1"); await api.equip_avatar("hair/type","item/1"); await api.join_event("e/1"); await api.request_withdrawal(20)
	await api.create_payment_order("p/1"); await api.payment_orders(); await api.payment_order("o/1"); await api.withdrawals()
	var paths: Array = transport.requests.map(func(r:Dictionary): return r.path)
	_check("commerce api owns encoded paths", paths == ["/api/v1/points","/api/v1/shop?lang=ja","/api/v1/membership?lang=ja","/api/v1/welfare?lang=ja",
		"/api/v1/events?lang=ja","/api/v1/events/joined","/api/v1/achievements?lang=ja","/api/v1/avatar?lang=ja","/api/v1/shop/purchase/i%2F1",
		"/api/v1/welfare/checkin","/api/v1/welfare/quests/q%2F1/claim","/api/v1/achievements/a%2F1/claim","/api/v1/avatar/equip",
		"/api/v1/events/e%2F1/join","/api/v1/earnings/withdrawals","/api/v1/payments/orders","/api/v1/payments/orders","/api/v1/payments/orders/o%2F1",
		"/api/v1/earnings/withdrawals"])
	_check("commerce api preserves transactional payloads", transport.requests[12].body == {"category":"hair/type","item":"item/1"}
		and transport.requests[14].body.amount == 20 and transport.requests[15].body.product_id == "p/1")

func _test_loads_and_confirmed_transactions() -> void:
	var f := _fixture()
	_check("commerce read models load", await f.coordinator.load_points() and await f.coordinator.load_shop("zh")
		and await f.coordinator.load_membership("zh") and await f.coordinator.load_welfare("zh")
		and await f.coordinator.load_events("zh") and await f.coordinator.load_achievements("zh") and await f.coordinator.load_avatar("zh")
		and await f.coordinator.load_withdrawals() and await f.coordinator.load_payment_orders())
	_check("purchase checkin and claims adopt server balance", await f.coordinator.purchase("i1") and f.store.balance == 80
		and await f.coordinator.checkin() and await f.coordinator.claim_quest("q1") and await f.coordinator.claim_achievement("a1") and f.store.balance == 130)
	_check("participation and withdrawal are confirmed", await f.coordinator.join_event("e1") and "e1" in f.store.joined_event_ids
		and await f.coordinator.request_withdrawal(20) and f.store.last_withdrawal.id == "w1"
		and f.store.withdrawals[0].id == "w1" and f.coordinator.has_pending_withdrawal())
	f.store.earnings={"total":500};f.store.withdrawals=[{"id":"w0","amount":80,"status":"paid"},{"id":"w1","amount":20,"status":"pending"}]
	_check("available earnings subtract reserved withdrawals", f.coordinator.available_earnings() == 400)
	_check("order list keeps loaded history", f.store.order_items[0].id == "o0")
	f.free_all.call()

func _test_duplicate_writes_and_optimistic_rollback() -> void:
	var f := _fixture(); f.gateway.gates["purchase:i1"] = Gate.new(); f.coordinator.purchase("i1")
	_check("duplicate purchase is rejected", not await f.coordinator.purchase("i1") and int(f.gateway.calls.get("purchase:i1",0)) == 1)
	_check("balance mutations are serialized across transaction types", not await f.coordinator.checkin())
	f.gateway.gates["purchase:i1"].released.emit(); await process_frame
	f.store.equipped_by_category.hair = "old"; f.gateway.equip_result = ApiResultScript.offline("down"); f.gateway.gates["equip:hair"] = Gate.new()
	f.coordinator.equip_avatar("hair","new")
	_check("avatar equip is optimistic", f.store.equipped_by_category.hair == "new")
	f.gateway.gates["equip:hair"].released.emit(); await process_frame
	_check("failed optimistic equip rolls back", f.store.equipped_by_category.hair == "old" and f.store.status == "offline")
	f.free_all.call()

func _test_payment_order_refresh_is_keyed() -> void:
	var f := _fixture(); f.gateway.gates["order:monthly"] = Gate.new(); f.coordinator.create_payment_order("monthly")
	_check("payment order creation is globally serialized", not await f.coordinator.create_payment_order("annual"))
	_check("session api shares the public order creation lock", not await f.coordinator.start_payment_session(
		"annual","membership","Annual","zh",func(_p:String,_o:String):return "native"))
	f.gateway.gates["order:monthly"].released.emit(); await process_frame
	_check("created order is stored by id", f.store.orders.o1.status == "pending" and f.store.order_items[0].id == "o1")
	_check("payment refresh adopts terminal state", await f.coordinator.refresh_payment_order("o1") and f.store.orders.o1.status == "paid")
	f.gateway.payment_status="failed";await f.coordinator.refresh_payment_order("o1")
	_check("payment terminal state is monotonic", f.store.orders.o1.status == "paid")
	f.free_all.call()
	var native_failure:=_fixture()
	_check("native payment refusal rejects the session", not await native_failure.coordinator.start_payment_session(
		"monthly","points","100 points","zh",func(_p:String,_o:String):return ""))
	_check("native refusal retains a traceable order and failed session", native_failure.store.orders.has("o1")
		and native_failure.store.payment_session.order_id=="o1" and native_failure.store.payment_session.status=="failed")
	native_failure.free_all.call()

func _test_payment_session_owns_lifecycle_and_syncs_entitlement() -> void:
	var f := _fixture(); f.gateway.gates["load:points"] = Gate.new();f.coordinator.load_points();f.gateway.gates["payment:o1"] = Gate.new()
	_check("payment session starts independently of presentation nodes", await f.coordinator.start_payment_session(
		"monthly", "points", "100 points", "zh", func(_product:String,_order:String)->String:return "native-1"))
	_check("active payment session keeps a global lock", f.store.payment_session.status == "pending"
		and not await f.coordinator.start_payment_session("annual", "membership", "Annual", "zh", func(_p:String,_o:String)->String:return "native-2"))
	f.store.touch()
	_check("presentation rebuild cannot clear payment ownership", f.store.payment_session.transaction_id == "native-1")
	f.gateway.gates["payment:o1"].released.emit();await process_frame;f.gateway.gates["load:points"].released.emit();await process_frame; await process_frame
	_check("paid session reaches a terminal state", f.store.payment_session.status == "paid" and not f.store.pending.has("payment_session"))
	_check("paid points entitlement is refreshed before completion", f.store.balance == 100 and f.store.payment_session.entitlement_synced)
	_check("payment entitlement sync fences an older resource read", int(f.store.revisions.get("points",0))==1)
	f.free_all.call()

func _test_shared_reads_do_not_cancel_consumers() -> void:
	var f := _fixture(); f.gateway.gates["load:points"] = Gate.new()
	f.coordinator.load_points(); f.coordinator.load_points()
	f.gateway.gates["load:points"].released.emit(); await process_frame; await process_frame
	_check("same-resource consumers share one authoritative request", int(f.store.revisions.get("points",0)) == 1
		and int(f.gateway.calls.get("load:points",0))==1)
	f.free_all.call()

func _test_payment_retries_sync_and_waits_for_terminal() -> void:
	var waiter:=RetryWaiter.new();var f:=_fixture(waiter.wait)
	f.gateway.points_results=[ApiResultScript.unexpected("TEMP","retry"),ApiResultScript.success(200,{"balance":150,"ledger":[],"earnings":{}})]
	await f.coordinator.start_payment_session("monthly","points","150 points","zh",func(_p:String,_o:String):return "native")
	await process_frame;await process_frame
	_check("paid order keeps its lock while entitlement sync is pending", f.store.payment_session.status=="paid_sync_pending" and f.coordinator.payment_active())
	waiter.released.emit();await process_frame;await process_frame
	_check("entitlement sync retries before payment completion", f.store.payment_session.status=="paid" and f.store.balance==150 and not f.coordinator.payment_active())
	f.free_all.call()

	waiter=RetryWaiter.new();f=_fixture(waiter.wait);f.gateway.payment_status="pending"
	await f.coordinator.start_payment_session("monthly","points","100 points","zh",func(_p:String,_o:String):return "native")
	await process_frame
	_check("non-terminal server order retains global payment lock", f.coordinator.payment_active()
		and not await f.coordinator.start_payment_session("annual","membership","Annual","zh",func(_p:String,_o:String):return "other"))
	f.gateway.payment_status="paid";waiter.released.emit();await process_frame;await process_frame
	_check("server terminal state releases the payment lock", f.store.payment_session.status=="paid" and not f.coordinator.payment_active())
	f.free_all.call()

func _test_payment_presentation_survives_rebuild_without_hidden_navigation() -> void:
	var state=AppStateScript.new();state.save_path="user://commerce-payment-test.cfg"
	var gateway=FakeGateway.new();var store=CommerceStoreScript.new();var coordinator=CommerceCoordinatorScript.new(gateway,store)
	var screen=ShopScreenScript.new(state,coordinator);var completions:={"count":0};screen.paid.connect(func(_d:String,_o:String):completions.count+=1)
	get_root().add_child(state);get_root().add_child(store);get_root().add_child(coordinator);get_root().add_child(screen)
	gateway.gates["payment:o1"]=Gate.new();await coordinator.start_payment_session("monthly","points","100 points","zh",func(_p:String,_o:String):return "native")
	screen.rebuild();gateway.gates["payment:o1"].released.emit();await process_frame;await process_frame
	_check("visible rebuilt screen observes stable payment completion", completions.count==1 and state.points==100)
	get_root().remove_child(screen);screen.free();coordinator.free();store.free();state.free()

	state=AppStateScript.new();state.save_path="user://commerce-hidden-payment-test.cfg";gateway=FakeGateway.new();store=CommerceStoreScript.new();coordinator=CommerceCoordinatorScript.new(gateway,store)
	var membership=MembershipScreenScript.new(state,coordinator);var subscriptions:={"count":0};membership.subscribed.connect(func(_d:String,_o:String):subscriptions.count+=1)
	get_root().add_child(state);get_root().add_child(store);get_root().add_child(coordinator);get_root().add_child(membership)
	gateway.gates["payment:o1"]=Gate.new();await coordinator.start_payment_session("annual","membership","Annual","zh",func(_p:String,_o:String):return "native")
	get_root().remove_child(membership);gateway.gates["payment:o1"].released.emit();await process_frame;await process_frame
	_check("hidden screen syncs entitlement without hijacking navigation", subscriptions.count==0 and state.member)
	membership.free();coordinator.free();store.free();state.free()

func _test_writes_supersede_stale_reads() -> void:
	var f := _fixture(); f.gateway.gates["load:points"] = Gate.new(); f.coordinator.load_points()
	_check("confirmed transaction completes while an older balance read waits", await f.coordinator.purchase("i1") and f.store.balance == 80)
	f.gateway.gates["load:points"].released.emit(); await process_frame
	_check("late balance read cannot overwrite a confirmed transaction", f.store.balance == 80)
	_check("transaction response is retained for presentation", f.store.last_transaction.balance == 80)
	f.free_all.call()
	var during := _fixture(); during.gateway.gates["purchase:i1"] = Gate.new(); during.coordinator.purchase("i1")
	during.gateway.gates["load:points"] = Gate.new(); during.coordinator.load_points()
	during.gateway.gates["purchase:i1"].released.emit(); await process_frame
	_check("transaction can finish while a newer read is in flight", during.store.balance == 80)
	during.gateway.gates["load:points"].released.emit(); await process_frame
	_check("read started during a transaction cannot overwrite its confirmation", during.store.balance == 80)
	during.free_all.call()

func _fixture(waiter:=Callable()) -> Dictionary:
	var gateway := FakeGateway.new(); var store = CommerceStoreScript.new(); var coordinator = CommerceCoordinatorScript.new(gateway,store,waiter)
	return {"gateway":gateway,"store":store,"coordinator":coordinator,"free_all":func(): coordinator.free();store.free()}

func _check(label:String,condition:bool) -> void:
	if condition:_passed+=1
	else:_failed+=1;push_error("FAIL: "+label)
