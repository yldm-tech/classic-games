class_name PayResultScreen
extends ScreenBase

## 支付结果页:成功态 + 订单描述 + 订单号 + 完成。

signal done

var order_desc := ""
var order_no := ""

## id 是后端真实订单 id(POST /payments/orders 返回、支付成功后已验证的那一笔),
## 不再本地伪造——伪造的号码看着像真订单号,但对不上任何服务端记录,客服/对账没法用。
func set_order(desc: String, id: String) -> void:
	order_desc = desc
	order_no = id
	rebuild()

func _build() -> void:
	var card := Widgets.card(theme_name(), &"tint_success")
	card.name = "ResultCard"
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	var title := Widgets.heading(txt("pay_ok_title"), 2, theme_name())
	title.name = "PayOkTitle"
	col.add_child(title)
	if order_desc != "":
		col.add_child(Widgets.body(order_desc, theme_name()))
	col.add_child(Widgets.caption("%s  %s" % [txt("pay_order_no"), order_no], theme_name()))
	var ok := Widgets.primary_button(txt("pay_done"), theme_name())
	ok.name = "DoneButton"
	ok.pressed.connect(func() -> void: done.emit())
	col.add_child(ok)
	content.add_child(card)
