class_name CommerceApi
extends RefCounted

var _transport: Variant
func _init(transport: Variant) -> void: _transport = transport

func points(): return await _request_get("/api/v1/points")
func shop(lang:String="zh"): return await _request_get("/api/v1/shop?lang=%s"%lang.uri_encode())
func membership(lang:String="zh"): return await _request_get("/api/v1/membership?lang=%s"%lang.uri_encode())
func welfare(lang:String="zh"): return await _request_get("/api/v1/welfare?lang=%s"%lang.uri_encode())
func events(lang:String="zh"): return await _request_get("/api/v1/events?lang=%s"%lang.uri_encode())
func joined_events(): return await _request_get("/api/v1/events/joined")
func achievements(lang:String="zh"): return await _request_get("/api/v1/achievements?lang=%s"%lang.uri_encode())
func avatar_catalog(lang:String="zh"): return await _request_get("/api/v1/avatar?lang=%s"%lang.uri_encode())
func purchase(id:String): return await _post("/api/v1/shop/purchase/%s"%id.uri_encode(),{})
func checkin(): return await _post("/api/v1/welfare/checkin",{})
func claim_quest(id:String): return await _post("/api/v1/welfare/quests/%s/claim"%id.uri_encode(),{})
func claim_achievement(id:String): return await _post("/api/v1/achievements/%s/claim"%id.uri_encode(),{})
func equip_avatar(category:String,item:String): return await _post("/api/v1/avatar/equip",{"category":category,"item":item})
func join_event(id:String): return await _post("/api/v1/events/%s/join"%id.uri_encode(),{})
func request_withdrawal(amount:int): return await _post("/api/v1/earnings/withdrawals",{"amount":amount})
func withdrawals(): return await _request_get("/api/v1/earnings/withdrawals")
func create_payment_order(product_id:String): return await _post("/api/v1/payments/orders",{"product_id":product_id})
func payment_orders(): return await _request_get("/api/v1/payments/orders")
func payment_order(id:String): return await _request_get("/api/v1/payments/orders/%s"%id.uri_encode())

func _request_get(path:String): return await _transport.request(HTTPClient.METHOD_GET,path)
func _post(path:String,body:Dictionary): return await _transport.request(HTTPClient.METHOD_POST,path,body)
