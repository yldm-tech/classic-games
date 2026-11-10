class_name MembershipScreen
extends ScreenBase

const PlatformBridge:=preload("res://platform/platform.gd")

## 会员 Classic Games+:权益展示；订阅支付只在非手机平台展示。

signal subscribed(order_desc: String, order_id: String)

var plan := 0
## /membership 注入的会员内容。无数据时空态。
var _data: Dictionary = {}
var commerce:CommerceCoordinator
func _init(p_state:Node,p_commerce:CommerceCoordinator=null)->void:
	commerce=p_commerce
	if commerce!=null:commerce.payment_finished.connect(_on_payment_finished)
	super(p_state)

## 首次展示拉会员内容:权益清单 + 月卡/年卡 + 文案。
func refresh() -> void:
	if commerce == null:
		return
	var membership_ok: bool = await commerce.load_membership(state.locale)
	await commerce.load_payment_orders()
	if membership_ok:
		_data = commerce.store.membership
		state.member = bool(_data.get("active", false))
		state.persist()
	rebuild()

## 标语:有后端数据用后端,否则种子。
func _tagline() -> String:
	if not _data.is_empty() and _data.has("tagline"):
		return str(_data["tagline"])
	return txt("mem_tagline")

func _note() -> String:
	if not _data.is_empty() and _data.has("note"):
		return str(_data["note"])
	return txt("mem_note")

## 权益清单来自后端 perks。
func _perks() -> Array:
	if not _data.is_empty() and _data.get("perks") is Array:
		return _data["perks"]
	return []

## 套餐归一为 [{name,price,period,badge}]。
func _plans() -> Array:
	# Empty plans stay empty. Subscribe is a no-op when the list is vacant.
	if not _data.is_empty() and _data.get("plans") is Array and not (_data["plans"] as Array).is_empty():
		var out: Array = []
		for p: Dictionary in _data["plans"]:
			out.append({"id": str(p.get("id", "")), "name": str(p.get("name", "")), "price": str(p.get("price", "")),
				"period": str(p.get("period", "")), "badge": str(p.get("badge", ""))})
		return out
	return []

func _build() -> void:
	if _data.is_empty():
		content.add_child(empty_note(txt("his_empty")))
		return
	var head := Widgets.card(theme_name(), &"tint_ember")
	var col := Widgets.vbox(Tokens.SPACE_2)
	head.add_child(col)
	var row := Widgets.hbox(Tokens.SPACE_2)
	row.add_child(Widgets.heading("Classic Games+", 2, theme_name()))
	row.add_child(Widgets.badge(txt("mem_badge"), theme_name()))
	col.add_child(row)
	col.add_child(Widgets.body(_tagline(), theme_name(), &"text_secondary"))
	content.add_child(head)

	var perks := Widgets.vbox(Tokens.SPACE_2)
	perks.name = "PerkList"
	for p: String in _perks():
		var card := Widgets.card(theme_name())
		card.add_child(Widgets.caption("✓  %s" % p, theme_name(), &"text_secondary"))
		perks.add_child(card)
	content.add_child(perks)
	if not PlatformBridge.payment_allowed():
		content.add_child(Widgets.caption(txt("pay_unavailable"),theme_name()));return

	var plans := Widgets.hbox(Tokens.SPACE_3)
	plans.name = "PlanRow"
	var items: Array = _plans()
	for i in items.size():
		var p: Dictionary = items[i]
		var card := Widgets.card(theme_name(), &"tint_ember" if i == plan else &"surface_card")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pc := Widgets.vbox(Tokens.SPACE_1)
		card.add_child(pc)
		pc.add_child(Widgets.body(p["name"], theme_name()))
		pc.add_child(Widgets.big_number("%s%s" % [p["price"], p["period"]], theme_name(), Tokens.FONT_H3))
		if p["badge"] != "":
			pc.add_child(Widgets.badge(p["badge"], theme_name(), true))
		var idx := i
		card.gui_input.connect(func(ev: InputEvent) -> void:
			# 支付进行中禁止切换套餐:否则 rebuild() 会 free 掉支付协程持有的按钮,并改动 plan。
			if _payment_busy(): return
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				plan = idx
				rebuild())
		plans.add_child(card)
	content.add_child(plans)

	var sub := Widgets.primary_button(txt("mem_sub"), theme_name())
	sub.name = "SubscribeButton"
	sub.disabled=not bool(PlatformBridge.capabilities()["payment"])
	sub.tooltip_text="" if not sub.disabled else txt("pay_unavailable")
	sub.pressed.connect(func() -> void:
		if _payment_busy(): return
		# 防御:无可订阅套餐或选中下标越界时不订阅,避免崩溃。
		var plan_list: Array = _plans()
		if plan < 0 or plan >= plan_list.size(): return
		if commerce == null: _toast(txt("request_failed")); return
		# 固定本次下单的套餐:后续 start_payment / emit 都用 chosen,避免 await 期间 plan 被切换导致
		# 服务端订单与商店实际扣款商品不一致。
		var chosen: Dictionary = plan_list[plan]
		var chosen_id := str(chosen.get("id",""))
		sub.disabled = true
		var description:="Classic Games+ %s" % str(chosen.get("name",""))
		var started:=await commerce.start_payment_session(chosen_id,"membership",description,state.locale,
			func(product_id:String,order_id:String)->String:return PlatformBridge.start_payment(product_id,order_id))
		if not started:
			if is_instance_valid(sub):sub.disabled=false
			_toast(txt("request_failed"));return
		if commerce.payment_active():_toast(txt("pay_pending")))
	content.add_child(sub)
	content.add_child(Widgets.caption(_note(), theme_name()))
	_build_orders()

func _build_orders() -> void:
	if commerce == null:
		return
	content.add_child(Widgets.caption(txt("pay_orders"), theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "OrderList"
	var items: Array = []
	for item: Dictionary in commerce.store.order_items:
		if str(item.get("product_id", "")).begins_with("plan_"):
			items.append(item)
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
		list.add_child(card)
	content.add_child(list)

func _order_status(status: String) -> String:
	match status:
		"pending": return txt("pay_status_pending")
		"processing": return txt("pay_status_processing")
		"paid": return txt("pay_status_paid")
		"failed": return txt("pay_status_failed")
		"cancelled": return txt("pay_status_cancelled")
		_: return status

func _payment_busy()->bool:return commerce!=null and commerce.payment_active()

func _on_payment_finished(session:Dictionary)->void:
	if str(session.get("kind",""))!="membership":return
	if bool(session.get("entitlement_synced",false)):
		_data=commerce.store.membership;state.member=bool(_data.get("active",false));state.persist()
	if not is_visible_in_tree():return
	if str(session.get("status",""))=="paid":rebuild();subscribed.emit(str(session.get("description","")),str(session.get("order_id","")))
	else:_toast(txt("pay_not_confirmed"));rebuild()
