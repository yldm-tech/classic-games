class_name WelfareScreen
extends ScreenBase

## 福利中心(「整理杂物间」后签到/任务/邀请的统一收纳处,docs/16):
## 7 天签到(递增奖励,今天高亮)、今日任务(进度+领取)、邀请卡。奖励入 AppState.points。

var checked := false
var claimed: Dictionary = {}
## /welfare 注入的福利内容(为空则回退种子常量/i18n)。
var _data: Dictionary = {}
var commerce:CommerceCoordinator
func _init(p_state:Node,p_commerce:CommerceCoordinator=null)->void:commerce=p_commerce;super(p_state)

## 首次展示拉福利内容:签到 + 任务 + 邀请。
func refresh() -> void:
	if commerce!=null and await commerce.load_welfare(state.locale):
		_data = commerce.store.welfare
		checked=bool(_data.get("checkin",{}).get("checked",false))
		for q:Dictionary in _data.get("quests",[]):
			if q.get("claimed",false): claimed[str(q.get("id",""))]=true
		rebuild()

## 7 天递增奖励:后端 checkin.rewards 或种子 REWARDS。
func _rewards() -> Array:
	if not _data.is_empty() and _data.get("checkin") is Dictionary and _data["checkin"].get("rewards") is Array:
		return _data["checkin"]["rewards"]
	return []

## 已连签天数:后端 checkin.streak 或种子 STREAK。
func _streak() -> int:
	if not _data.is_empty() and _data.get("checkin") is Dictionary and _data["checkin"].has("streak"):
		return int(_data["checkin"]["streak"])
	return 0

## 任务归一为 [{title,progress,target,reward}](后端对象 或 种子 [title,progress,target,reward])。
func _quests() -> Array:
	if not _data.is_empty() and _data.get("quests") is Array:
		var out: Array = []
		for q: Dictionary in _data["quests"]:
			out.append({"id":str(q.get("id","")),"title": str(q.get("title", "")), "progress": int(q.get("progress", 0)),
				"target": int(q.get("target", 0)), "reward": int(q.get("reward", 0)),"claimed":bool(q.get("claimed",false))})
		return out
	return []

## 邀请码:后端 invite.code 或种子 INVITE_CODE。
func _invite_code() -> String:
	if not _data.is_empty() and _data.get("invite") is Dictionary and _data["invite"].has("code"):
		return str(_data["invite"]["code"])
	return ""

## 邀请标题:后端 invite.title 或种子 i18n。
func _invite_title() -> String:
	if not _data.is_empty() and _data.get("invite") is Dictionary and _data["invite"].has("title"):
		return str(_data["invite"]["title"])
	return txt("invite_title")

## 邀请说明:后端 invite.desc 或种子 i18n。
func _invite_desc() -> String:
	if not _data.is_empty() and _data.get("invite") is Dictionary and _data["invite"].has("desc"):
		return str(_data["invite"]["desc"])
	return txt("invite_desc")

func _build() -> void:
	if _data.is_empty():
		content.add_child(empty_note(txt("his_empty")))
		return
	# 签到卡
	var card := Widgets.card(theme_name())
	card.name = "CheckinCard"
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	var head := Widgets.hbox()
	var t := Widgets.body(txt("checkin_title"), theme_name())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var streak := _streak()
	var rewards := _rewards()
	head.add_child(Widgets.caption(txt_fmt("checkin_streak_fmt", [streak + (1 if checked else 0)]), theme_name()))
	col.add_child(head)
	var days := Widgets.hbox(Tokens.SPACE_1)
	days.name = "DayRow"
	for i in 7:
		var done := i < streak or (i == streak and checked)
		var today := i == streak and not checked
		var cell := Widgets.card(theme_name(), &"tint_ember" if today or done else &"surface_input")
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cc := Widgets.vbox(0)
		cell.add_child(cc)
		var d := Widgets.caption(txt_fmt("checkin_day_fmt", [i + 1]), theme_name(),
			&"accent_primary" if today else &"text_muted")
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cc.add_child(d)
		# 后端 rewards 可能少于 7 项:越界则显 0,不崩(line 103 同样做了越界保护)。
		var rday := int(rewards[i]) if i < rewards.size() else 0
		var r := Widgets.caption("+%d" % rday, theme_name(), &"text_secondary" if done or today else &"text_muted")
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cc.add_child(r)
		days.add_child(cell)
	col.add_child(days)
	var btn := Widgets.primary_button(txt("checkin_done") if checked else txt("checkin_btn"), theme_name())
	btn.name = "CheckinButton"
	btn.disabled = checked
	var today_reward := int(rewards[streak]) if streak < rewards.size() else 0
	btn.pressed.connect(func() -> void:
		if commerce==null:_toast(txt("request_failed"));return
		if not await commerce.checkin():return
		state.add_points(commerce.store.balance-state.points)
		checked = true
		_toast(txt_fmt("checkin_toast_fmt", [int(commerce.store.last_transaction.get("reward", today_reward))]))
		rebuild())
	col.add_child(btn)
	content.add_child(card)

	# 今日任务
	content.add_child(Widgets.caption(txt("quest_title"), theme_name()))
	var quests := Widgets.vbox(Tokens.SPACE_2)
	quests.name = "QuestList"
	var items: Array = _quests()
	for i in items.size():
		var q: Dictionary = items[i]
		var qc := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		qc.add_child(row)
		var info := Widgets.vbox(Tokens.SPACE_1)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Widgets.body(q["title"], theme_name())
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(label)
		var bar := ProgressBar.new()
		bar.max_value = q["target"]
		bar.value = q["progress"]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		info.add_child(bar)
		row.add_child(info)
		var claim_key:Variant=q.get("id",i);var can_claim: bool = q["progress"] >= q["target"] and not claimed.has(claim_key)
		var claim := Widgets.secondary_button(txt("quest_claimed") if claimed.has(claim_key) else "%s +%d" % [txt("quest_claim"), int(q["reward"])], theme_name())
		claim.disabled = not can_claim
		var idx: Variant = claim_key
		var reward := int(q["reward"])
		claim.pressed.connect(func() -> void:
			if commerce==null:_toast(txt("request_failed"));return
			if not await commerce.claim_quest(str(q.get("id",""))):return
			state.add_points(commerce.store.balance-state.points)
			claimed[idx] = true
			_toast(txt_fmt("quest_toast_fmt", [int(commerce.store.last_transaction.get("reward", reward))]))
			rebuild())
		row.add_child(claim)
		quests.add_child(qc)
	content.add_child(quests)

	# 邀请卡
	var inv := Widgets.card(theme_name(), &"tint_volt")
	inv.name = "InviteCard"
	var ic := Widgets.vbox(Tokens.SPACE_2)
	inv.add_child(ic)
	ic.add_child(Widgets.body(_invite_title(), theme_name()))
	ic.add_child(Widgets.caption(_invite_desc(), theme_name(), &"text_secondary"))
	var code := _invite_code()
	ic.add_child(Widgets.big_number(code, theme_name(), Tokens.FONT_H3))
	var copy := Widgets.secondary_button(txt("invite_btn"), theme_name())
	copy.name = "CopyButton"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
		_toast(txt("toast_copied")))
	ic.add_child(copy)
	content.add_child(inv)
