class_name EarningsScreen
extends ScreenBase

## 收益中心:累计收益 + 近 7 天柱状 + 分成流水 + 兑换现金。
## 数据由 /points 的 earnings 子对象注入；缺失时展示真实零值，不伪造收益。

## /points 注入的收益子对象 earnings；缺失数据按真实零值展示。
var _earnings: Dictionary = {}
var commerce:CommerceCoordinator
func _init(p_state:Node,p_commerce:CommerceCoordinator=null)->void:commerce=p_commerce;super(p_state)

## 首次展示拉创作点数据与提现记录。收益缺失按真实零值展示。
func refresh() -> void:
	if commerce == null:
		return
	var points_ok: bool = await commerce.load_points()
	await commerce.load_withdrawals()
	if points_ok:
		_earnings = commerce.store.earnings
	rebuild()

func _available() -> int:
	return commerce.available_earnings() if commerce != null else int(_earnings.get("total", 0))

func _withdrawals() -> Array:
	return commerce.store.withdrawals if commerce != null else []

func _has_pending() -> bool:
	return commerce.has_pending_withdrawal() if commerce != null else false

## 累计收益展示串。
func _total_text() -> String:
	var i18n := preload("res://i18n/i18n.gd")
	return i18n.format_number(int(_earnings.get("total", 0)), state.locale)

## 近 7 天柱状数据。
func _weekly() -> Array:
	if not _earnings.is_empty() and _earnings.get("weekly") is Array:
		return _earnings["weekly"]
	return [0, 0, 0, 0, 0, 0, 0]

## 分成流水归一为 [{label,amount,when}]。
func _ledger() -> Array:
	if not _earnings.is_empty() and _earnings.get("ledger") is Array:
		var out: Array = []
		for e: Dictionary in _earnings["ledger"]:
			out.append({"label": str(e.get("label", "")), "amount": int(e.get("amount", 0)), "when": str(e.get("when", ""))})
		return out
	return []

func _build() -> void:
	var card := Widgets.card(theme_name(), &"tint_ember")
	var col := Widgets.vbox(Tokens.SPACE_1)
	card.add_child(col)
	col.add_child(Widgets.caption(txt("ea_total"), theme_name()))
	var total := Widgets.big_number(_total_text(), theme_name(), Tokens.FONT_DISPLAY)
	total.name = "TotalLabel"
	col.add_child(total)
	content.add_child(card)

	content.add_child(Widgets.caption(txt("ea_weekly"), theme_name()))
	var bars := Widgets.hbox(Tokens.SPACE_2)
	bars.name = "WeeklyBars"
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	var weekly := _weekly()
	var peak := float(weekly.max())
	if peak <= 0.0:
		peak = 1.0
	for v in weekly:
		var bar_col := Widgets.vbox(0)
		bar_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_col.alignment = BoxContainer.ALIGNMENT_END
		var bar := ColorRect.new()
		bar.color = Tokens.color(&"accent_primary", theme_name())
		bar.custom_minimum_size = Vector2(0, 64.0 * float(v) / peak)
		bar_col.add_child(bar)
		bar_col.custom_minimum_size = Vector2(0, 64)
		bars.add_child(bar_col)
	content.add_child(bars)

	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "LedgerList"
	for item: Dictionary in _ledger():
		var row_card := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		row_card.add_child(row)
		var l := Widgets.body(item["label"], theme_name())
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var n := Label.new()
		n.text = "+%d" % int(item["amount"])
		n.add_theme_color_override("font_color", Tokens.color(&"status_success", theme_name()))
		row.add_child(n)
		row.add_child(Widgets.caption(item["when"], theme_name()))
		list.add_child(row_card)
	content.add_child(list)

	content.add_child(Widgets.caption(txt("ea_withdrawals"), theme_name()))
	var wd_list := Widgets.vbox(Tokens.SPACE_2)
	wd_list.name = "WithdrawalList"
	var rows: Array = _withdrawals()
	if rows.is_empty():
		wd_list.add_child(empty_note(txt("ea_wd_empty")))
	for item: Dictionary in rows:
		var row_card := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		row_card.add_child(row)
		var l := Widgets.body("%d %s" % [int(item.get("amount", 0)), txt("points_label")], theme_name())
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(Widgets.badge(_wd_status(str(item.get("status", ""))), theme_name()))
		row.add_child(Widgets.caption(_when(str(item.get("created_at", ""))), theme_name()))
		wd_list.add_child(row_card)
	content.add_child(wd_list)

	var available := _available()
	var pending := _has_pending()
	if pending:
		var banner := Widgets.caption(txt("ea_withdraw_pending"), theme_name())
		banner.name = "PendingBanner"
		content.add_child(banner)
	elif available < 100:
		content.add_child(Widgets.caption(txt("ea_withdraw_min"), theme_name()))
	var withdraw := Widgets.primary_button(txt("ea_withdraw"), theme_name())
	withdraw.name = "WithdrawButton"
	withdraw.disabled = pending or available < 100
	withdraw.pressed.connect(func() -> void:
		if commerce == null: _toast(txt("request_failed")); return
		var amount := commerce.available_earnings()
		if amount < 100 or commerce.has_pending_withdrawal(): _toast(txt("request_failed")); return
		withdraw.disabled = true
		if await commerce.request_withdrawal(amount):
			_toast(txt("ea_withdraw_toast")); rebuild()
		else: withdraw.disabled = false; _toast(txt("request_failed")))
	content.add_child(withdraw)

func _wd_status(status: String) -> String:
	match status:
		"pending": return txt("ea_wd_pending")
		"paid": return txt("ea_wd_paid")
		"failed": return txt("ea_wd_failed")
		_: return status

func _when(value: String) -> String:
	return value.substr(0, 10) if value.length() >= 10 else value
