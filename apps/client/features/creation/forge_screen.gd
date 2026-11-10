class_name ForgeScreen
extends ScreenBase

## 创作 = 「做一款游戏」(docs/16):AI prompt → 灵感 chips → 模板 → 改一版热门。
## 生成动作经 forge_requested 信号交给 AppRoot(走 net 层调 /ai/mod),
## 屏内只管输入与进度展示;分步进度由 set_step 驱动(对照原型 forgeSteps)。

signal generation_started(prompt: String)
signal generation_completed(prompt: String)
signal game_opened(game: Dictionary)
signal studio_requested

var _prompt_edit: TextEdit
var _forging := false
var _step := -1
var _user_edited := false  # 用户改过 prompt 才保留;否则语言切换时换成新语言的默认灵感
var runtime_ref := "shooter@1.0.0"
var _trending: Array = []
var coordinator: CreationCoordinator

func _init(p_state: Node, p_coordinator: CreationCoordinator = null) -> void:
	coordinator = p_coordinator
	super(p_state)

func refresh() -> void:
	if coordinator == null:
		return
	await coordinator.load_quota()
	rebuild()

## 生成中切步(0..3);-1 复位。AppRoot 在等待 AI 时驱动。
func set_step(step: int) -> void:
	_step = step
	_forging = step >= 0
	rebuild()

## AppRoot 拉到 /ranking 后注入真实热门作品(与 home_screen.bind_trending 同源)。
func bind_trending(items: Array) -> void:
	_trending = items
	rebuild()

func current_prompt() -> String:
	return _prompt_edit.text if _prompt_edit != null else ""

func _build() -> void:
	var keep := _prompt_edit.text if _user_edited and _prompt_edit != null and is_instance_valid(_prompt_edit) \
		else String(txt("forge_prompt"))
	_build_runtime_selector()
	_build_prompt(keep)
	if _forging:
		_build_progress()
	_build_chips()
	content.add_child(Widgets.divider(theme_name()))
	_build_templates()
	content.add_child(Widgets.divider(theme_name()))
	_build_remix()
	_build_studio_entry()
	_build_note()

func _build_runtime_selector() -> void:
	content.add_child(Widgets.caption(txt("runtime_label"), theme_name()))
	var selector := OptionButton.new()
	selector.name = "RuntimeSelector"
	var refs := ["shooter@1.0.0", "survivor@1.0.0", "tower_defense@1.0.0"]
	var labels := ["Shooter", "Survivor", "Tower Defense"]
	for i in refs.size():
		selector.add_item(labels[i]); selector.set_item_metadata(i, refs[i])
		if refs[i] == runtime_ref: selector.select(i)
	selector.disabled = _forging
	selector.item_selected.connect(func(index: int) -> void: runtime_ref = str(selector.get_item_metadata(index)))
	content.add_child(selector)

## 创作中心入口(做 → 管的闭环,不绕到「我的」)。
func _build_studio_entry() -> void:
	var entry := nav_row(txt("ql_studio"), txt("forge_studio_entry"), func() -> void: studio_requested.emit())
	entry.name = "StudioEntry"
	content.add_child(entry)

func _build_prompt(text: String) -> void:
	var card := Widgets.card(theme_name(), &"surface_input")
	var box := Widgets.vbox(Tokens.SPACE_2)
	card.add_child(box)
	_prompt_edit = TextEdit.new()
	_prompt_edit.name = "PromptEdit"
	_prompt_edit.text = text
	_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt_edit.custom_minimum_size = Vector2(0, 88)
	_prompt_edit.editable = not _forging
	_prompt_edit.add_theme_font_size_override("font_size", Tokens.FONT_MONO)
	_prompt_edit.add_theme_color_override("font_color", Tokens.color(&"text_primary", theme_name()))
	# 初值赋完再连信号:只有用户(或 chip/模板)改动才算「编辑过」
	_prompt_edit.text_changed.connect(func() -> void: _user_edited = true)
	box.add_child(_prompt_edit)
	var row := Widgets.hbox(Tokens.SPACE_2)
	row.add_child(Widgets.caption(txt("prompt_base"), theme_name()))
	row.add_child(Widgets.spacer())
	var go := Widgets.ai_button(txt("forging") if _forging else txt("forge_it"), theme_name())
	go.name = "ForgeButton"
	go.disabled = _forging
	go.pressed.connect(_generate)
	row.add_child(go)
	box.add_child(row)
	content.add_child(card)

func _build_progress() -> void:
	var card := Widgets.card(theme_name())
	card.name = "ForgeProgress"
	var box := Widgets.vbox(Tokens.SPACE_2)
	card.add_child(box)
	var steps: Array = txt("forge_steps")
	for i in steps.size():
		var row := Widgets.hbox(Tokens.SPACE_2)
		var dot := Label.new()
		dot.text = "✓" if _step > i else "✦"
		dot.add_theme_color_override("font_color",
			Tokens.color(&"accent_ai" if _step >= i else &"text_muted", theme_name()))
		row.add_child(dot)
		var lbl := Widgets.body(steps[i], theme_name(), &"text_primary" if _step >= i else &"text_muted")
		row.add_child(lbl)
		box.add_child(row)
	content.add_child(card)

func _build_chips() -> void:
	var chips := HFlowContainer.new()
	chips.name = "PromptChips"
	chips.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	chips.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	var labels: Array = txt("chips")
	# 第一枚「随机灵感」整段替换 prompt,其余往后追加(对照原型)
	var surprise := Widgets.chip(labels[0], false, theme_name(), true)
	surprise.pressed.connect(func() -> void:
		_user_edited = true  # 程序赋值不触发 text_changed,显式标记
		_prompt_edit.text = txt("surprise_prompt"))
	chips.add_child(surprise)
	for i in range(1, labels.size()):
		var c := Widgets.chip("+ %s" % labels[i], false, theme_name())
		var word: String = labels[i]
		c.pressed.connect(func() -> void:
			_user_edited = true
			var sep: String = txt("chip_sep")
			_prompt_edit.text = word if _prompt_edit.text.is_empty() else _prompt_edit.text + sep + word)
		chips.add_child(c)
	content.add_child(chips)

func _build_templates() -> void:
	content.add_child(Widgets.caption(txt("tpl_title"), theme_name()))
	var grid := GridContainer.new()
	grid.name = "Templates"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	for tpl: Array in txt("templates"):
		var b := Widgets.secondary_button(tpl[0], theme_name())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 每个模板各自的起始 prompt(tpl[2]);缺失则回退通用 forge_prompt。
		var tpl_prompt: String = str(tpl[2]) if tpl.size() > 2 else str(txt("forge_prompt"))
		b.pressed.connect(func() -> void:
			_user_edited = true
			_prompt_edit.text = tpl_prompt)
		grid.add_child(b)
	content.add_child(grid)

func _build_remix() -> void:
	content.add_child(Widgets.caption(txt("or_remix"), theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "RemixList"
	var games: Array = _trending.slice(0, 3)
	for game: Dictionary in games:
		list.add_child(GameCard.build(game, state.locale, theme_name(), func(g: Dictionary) -> void: game_opened.emit(g)))
	if games.is_empty():
		list.add_child(empty_note(txt("remix_empty")))
	content.add_child(list)

func _build_note() -> void:
	var quota_text := _quota_text()
	if quota_text != "":
		var quota := Widgets.caption(quota_text, theme_name())
		quota.name = "QuotaLabel"
		content.add_child(quota)
	var note := Widgets.card(theme_name(), &"surface_raised")
	note.add_child(Widgets.caption(txt("forge_note"), theme_name(), &"text_secondary"))
	content.add_child(note)

func _quota_text() -> String:
	if coordinator == null or coordinator.store.quota.is_empty():
		return ""
	var remaining := int(coordinator.store.quota.get("remaining", 0))
	var limit := int(coordinator.store.quota.get("limit", 0))
	if remaining <= 0:
		return txt("ai_quota_empty")
	return txt_fmt("ai_quota_fmt", [str(remaining), str(limit)])

func _generate() -> void:
	if _forging or coordinator == null: return
	var prompt := _prompt_edit.text
	generation_started.emit(prompt)
	set_step(0)
	var ok := true
	if coordinator.store.runtime_ref != runtime_ref:
		ok = await coordinator.load_runtime(runtime_ref)
	if ok: ok = await coordinator.generate(prompt, runtime_ref)
	set_step(-1)
	if ok: generation_completed.emit(prompt)
	else: _toast(txt("forge_failed"))
