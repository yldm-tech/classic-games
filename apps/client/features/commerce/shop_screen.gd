class_name ShopScreen
extends ScreenBase

const PlatformBridge:=preload("res://platform/platform.gd")

## 商城:皮肤/道具用创作点兑换；充值只在非手机平台展示。

signal paid(order_desc: String, order_id: String)

var seg := 0
## 拥有态按「与语言无关的稳定 key」记(后端用服务端 id)。
## 避免按本地化名记导致切语言后同一皮肤显示可再买、重复扣点。
var owned: Dictionary = {}
var _pay_pick := -1   # 选中的充值档;>=0 时显示支付面板
var _channel := 0
## /shop 注入的商城内容(为空则回退 i18n 种子)。
var _data: Dictionary = {}
var commerce:CommerceCoordinator
func _init(p_state:Node,p_commerce:CommerceCoordinator=null)->void:
	commerce=p_commerce
	if commerce!=null:commerce.payment_finished.connect(_on_payment_finished)
	super(p_state)

## 首次展示拉商城内容:皮肤/道具/充值档 + 货币单位。
func refresh() -> void:
	if commerce == null:
		return
	var shop_ok: bool = await commerce.load_shop(state.locale)
	await commerce.load_payment_orders()
	if shop_ok:
		_data = commerce.store.shop
	rebuild()

## 充值得到的「创作点」单位名:有后端数据用后端,否则种子。
func _recharge_unit() -> String:
	if not _data.is_empty() and _data.has("recharge_unit"):
		return str(_data["recharge_unit"])
	return txt("recharge_unit")

## 法币符号:有后端数据用后端,否则种子。
func _currency_unit() -> String:
	if not _data.is_empty() and _data.has("currency_unit"):
		return str(_data["currency_unit"])
	return txt("price_unit")

func _build() -> void:
	var bal := Widgets.card(theme_name(), &"tint_ember")
	var brow := Widgets.hbox()
	bal.add_child(brow)
	var bl := Widgets.caption(txt("balance"), theme_name())
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(bl)
	var bval := Widgets.big_number(str(state.points), theme_name(), Tokens.FONT_H3)
	bval.name = "Balance"
	brow.add_child(bval)
	content.add_child(bal)

	var tabs:Array=(txt("shop_tabs") as Array).duplicate()
	if not PlatformBridge.payment_allowed():tabs= tabs.slice(0,2);seg=mini(seg,1)
	var seg_ctrl := Widgets.segment(tabs, seg, theme_name(), func(i: int) -> void:
		seg = i
		_pay_pick = -1
		rebuild())
	seg_ctrl.name = "ShopSeg"
	content.add_child(seg_ctrl)
	match seg:
		0: _build_skins()
		1: _build_items()
		2: _build_recharge()

func _redeem_row(label: String, price: int, key: String, pre_owned: bool = false, server_id: String = "") -> Control:
	var card := Widgets.card(theme_name())
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	var l := Widgets.body(label, theme_name())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(Widgets.caption("%d %s" % [price, txt("points_label")], theme_name()))
	var is_owned := owned.has(key) or pre_owned  # pre_owned = 服务端 owned 字段

	var btn := Widgets.secondary_button(txt("owned") if is_owned else txt("buy"), theme_name())
	btn.disabled = is_owned or state.points < price
	btn.pressed.connect(func() -> void:
		if commerce==null or server_id=="":_toast(txt("request_failed"));return
		if not await commerce.purchase(server_id): return
		state.add_points(commerce.store.balance-state.points)
		owned[key] = true
		_toast(txt("bought_toast"))
		rebuild())
	row.add_child(btn)
	return card

func _build_skins() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "SkinList"
	if not _data.is_empty() and _data.get("skins") is Array:
		for s: Dictionary in _data["skins"]:
			var nm := str(s.get("name", ""))
			# 用 skin_ 前缀命名空间,避免与道具(item_)共用 owned 字典时同 id 串拥有态。
			var sid:=str(s.get("id",nm));list.add_child(_redeem_row(nm,int(s.get("price",0)),"skin_"+sid,bool(s.get("owned",false)),sid))
	else:
		list.add_child(_empty_catalog())
	content.add_child(list)

func _build_items() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "ItemList"
	if not _data.is_empty() and _data.get("items") is Array:
		for s: Dictionary in _data["items"]:
			var nm := str(s.get("name", ""))
			var sid:=str(s.get("id",nm));list.add_child(_redeem_row(nm,int(s.get("price",0)),"item_"+sid,bool(s.get("owned",false)),sid))
	else:
		list.add_child(_empty_catalog())
	content.add_child(list)

## 充值档归一为 [{points:int, price:String}]:后端 {id,points,price} 或种子 [points, price]。
func _recharge_tiers() -> Array:
	if not _data.is_empty() and _data.get("recharge") is Array:
		var out: Array = []
		for t: Dictionary in _data["recharge"]:
			out.append({"id":str(t.get("id","")),"points": int(t.get("points", 0)), "price": str(t.get("price", ""))})
		return out
	return []

func _empty_catalog() -> Control:
	return empty_note(txt("his_empty"))

func _build_recharge() -> void:
	if not PlatformBridge.payment_allowed():return
	var grid := GridContainer.new()
	grid.name = "RechargeGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	var tiers: Array = _recharge_tiers()
	if tiers.is_empty():
		grid.add_child(_empty_catalog())
	for i in tiers.size():
		var t: Dictionary = tiers[i]
		var card := Widgets.card(theme_name(), &"tint_ember" if i == _pay_pick else &"surface_card")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := Widgets.vbox(Tokens.SPACE_1)
		card.add_child(col)
		col.add_child(Widgets.big_number("%d %s" % [int(t["points"]), _recharge_unit()], theme_name(), Tokens.FONT_H4))
		col.add_child(Widgets.caption("%s%s" % [_currency_unit(), t["price"]], theme_name()))
		var idx := i
		card.gui_input.connect(func(ev: InputEvent) -> void:
			# 支付进行中禁止切档:否则 rebuild() 会 free 掉支付协程持有的按钮。
			if _payment_busy(): return
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_pay_pick = idx
				rebuild())
		grid.add_child(card)
	content.add_child(grid)

	_build_orders()
	if _pay_pick < 0:
		return
	# 支付半屏面板(渠道单选 + 立即支付)
	var t: Dictionary = tiers[_pay_pick]
	var pay := Widgets.card(theme_name(), &"surface_raised")
	pay.name = "PaySheet"
	var col := Widgets.vbox(Tokens.SPACE_3)
	pay.add_child(col)
	col.add_child(Widgets.heading(txt("pay_title"), 3, theme_name()))
	col.add_child(Widgets.segment(txt("pay_channels"), _channel, theme_name(), func(i: int) -> void:
		if _payment_busy(): return
		_channel = i
		rebuild()))
	var go := Widgets.primary_button("%s  %s%s" % [txt("pay_btn"), _currency_unit(), t["price"]], theme_name())
	go.name = "PayButton"
	go.disabled=not bool(PlatformBridge.capabilities()["payment"])
	go.tooltip_text="" if not go.disabled else txt("pay_unavailable")
	go.pressed.connect(func() -> void:
		if _payment_busy(): return
		if commerce == null: _toast(txt("request_failed")); return
		go.disabled = true
		var desc := "%d %s" % [int(t["points"]), _recharge_unit()]
		var started:=await commerce.start_payment_session(str(t.get("id","")),"points",desc,state.locale,
			func(product_id:String,order_id:String)->String:return PlatformBridge.start_payment(product_id,order_id))
		if not started:
			if is_instance_valid(go):go.disabled=false
			_toast(txt("request_failed"));return
		if commerce.payment_active():_toast(txt("pay_pending")))
	col.add_child(go)
	content.add_child(pay)

func _build_orders() -> void:
	if commerce == null:
		return
	content.add_child(Widgets.caption(txt("pay_orders"), theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "OrderList"
	var items: Array = _shop_orders()
	if items.is_empty():
		list.add_child(empty_note(txt("pay_orders_empty")))
	for item: Dictionary in items:
		var card := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		card.add_child(row)
		var l := Widgets.body(str(item.get("product_id", "")), theme_name())
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(Widgets.badge(_order_status(str(item.get("status", ""))), theme_name()))
		row.add_child(Widgets.caption(_when(str(item.get("created_at", ""))), theme_name()))
		list.add_child(card)
	content.add_child(list)

func _shop_orders() -> Array:
	var out: Array = []
	for item: Dictionary in commerce.store.order_items:
		var product_id := str(item.get("product_id", ""))
		if not product_id.begins_with("plan_"):
			out.append(item)
	return out

func _order_status(status: String) -> String:
	match status:
		"pending": return txt("pay_status_pending")
		"processing": return txt("pay_status_processing")
		"paid": return txt("pay_status_paid")
		"failed": return txt("pay_status_failed")
		"cancelled": return txt("pay_status_cancelled")
		_: return status

func _when(value: String) -> String:
	return value.substr(0, 10) if value.length() >= 10 else value

func _payment_busy()->bool:return commerce!=null and commerce.payment_active()

func _on_payment_finished(session:Dictionary)->void:
	if str(session.get("kind",""))!="points":return
	if bool(session.get("entitlement_synced",false)):state.add_points(commerce.store.balance-state.points)
	if not is_visible_in_tree():return
	if str(session.get("status",""))=="paid":
		_pay_pick=-1;rebuild();paid.emit(str(session.get("description","")),str(session.get("order_id","")))
	else:_toast(txt("pay_not_confirmed"));rebuild()
