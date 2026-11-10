class_name EditorScreen
extends ScreenBase

## 可视参数与完整 DSL JSON 编辑器。手工编辑统一写入 CreatorSession，复用撤销/重做与发布状态。

signal publish_requested

var levels := 3
var _level := 0
var params := [62.0, 40.0, 55.0]
var session: CreatorSessionAdapter
var coordinator: CreationCoordinator
var platform: CreationPlatformPort
var _dsl_text := ""
var _dsl_error := ""
var _synced_session_token := -1

func _init(p_state: Node, p_coordinator: CreationCoordinator = null, p_session: CreatorSessionAdapter = null, p_platform: CreationPlatformPort = null) -> void:
	coordinator = p_coordinator
	session = p_session
	platform = p_platform
	if coordinator != null: coordinator.store.changed.connect(_on_store_changed)
	_sync_dsl_text()
	super(p_state)

func _on_store_changed() -> void:
	if session != null and session.state_token() != _synced_session_token:
		_sync_dsl_text()
	rebuild.call_deferred()

func refresh() -> void:
	if coordinator == null:
		return
	await coordinator.load_quota()
	rebuild()

func set_session(value: CreatorSessionAdapter) -> void:
	session = value
	_sync_dsl_text()
	rebuild()

func _build() -> void:
	content.add_child(Widgets.caption(txt("ed_levels"), theme_name()))
	var flow := HFlowContainer.new()
	flow.name = "LevelChips"
	flow.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	flow.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	for i in levels:
		var c := Widgets.chip(txt_fmt("ed_level_fmt", [i + 1]), i == _level, theme_name())
		var idx := i
		c.pressed.connect(func() -> void:
			_level = idx
			rebuild())
		flow.add_child(c)
	var add := Widgets.chip(txt("ed_add"), false, theme_name(), true)
	add.name = "AddLevel"
	add.pressed.connect(func() -> void:
		levels += 1
		_level = levels - 1
		rebuild())
	flow.add_child(add)
	content.add_child(flow)

	content.add_child(Widgets.caption(txt("ed_params"), theme_name()))
	var card := Widgets.card(theme_name())
	card.name = "ParamCard"
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	var names: Array = txt("ed_param_names")
	for i in names.size():
		col.add_child(Widgets.caption(names[i], theme_name()))
		var slider := HSlider.new()
		slider.max_value = 100
		slider.value = params[i]
		var idx := i
		slider.value_changed.connect(func(v: float) -> void: params[idx] = v)
		col.add_child(slider)
	content.add_child(card)

	content.add_child(Widgets.caption(txt("ed_ai_design"), theme_name()))
	var quota_text := _quota_text()
	if quota_text != "":
		var quota := Widgets.caption(quota_text, theme_name())
		quota.name = "QuotaLabel"
		content.add_child(quota)
	var ai_card := Widgets.card(theme_name(), &"tint_volt")
	var ai_col := Widgets.vbox(Tokens.SPACE_2)
	ai_card.add_child(ai_col)
	var difficulty := SpinBox.new()
	difficulty.name = "DifficultySpin"
	difficulty.min_value = 1; difficulty.max_value = 5; difficulty.step = 1; difficulty.value = 3
	difficulty.prefix = txt("ed_difficulty") + " "
	ai_col.add_child(difficulty)
	var balance := Widgets.ai_button(txt("ed_auto_balance"), theme_name())
	balance.name = "AutoBalanceButton"
	balance.disabled = session == null
	balance.pressed.connect(func() -> void: _balance(int(difficulty.value)))
	ai_col.add_child(balance)
	var structure_prompt := LineEdit.new()
	structure_prompt.name = "StructurePromptEdit"
	structure_prompt.placeholder_text = txt("ed_structure_prompt")
	structure_prompt.text = txt("ed_structure_default")
	ai_col.add_child(structure_prompt)
	var count := SpinBox.new()
	count.name = "StructureCountSpin"
	count.min_value = 1; count.max_value = 8; count.step = 1; count.value = 3
	count.prefix = txt("ed_structure_count") + " "
	ai_col.add_child(count)
	var generate := Widgets.ai_button(txt("ed_generate_structure"), theme_name())
	generate.name = "GenerateStructureButton"
	generate.disabled = session == null
	generate.pressed.connect(func() -> void:
		var prompt := structure_prompt.text.strip_edges()
		if prompt != "": _structure(prompt, int(count.value), int(difficulty.value)))
	ai_col.add_child(generate)
	content.add_child(ai_card)
	if OS.get_name() in ["macOS", "Windows", "Linux"]:
		var desktop_actions := Widgets.hbox(Tokens.SPACE_2)
		var import_button := Widgets.secondary_button(txt("ed_import_dsl"), theme_name())
		import_button.name = "ImportDslButton"
		import_button.pressed.connect(func() -> void:
			if platform != null: platform.request_import())
		desktop_actions.add_child(import_button)
		var export_button := Widgets.secondary_button(txt("ed_export_dsl"), theme_name())
		export_button.name = "ExportDslButton"
		export_button.disabled = session == null
		export_button.pressed.connect(func() -> void:
			if platform != null: platform.export_document())
		desktop_actions.add_child(export_button)
		var preview_button := Widgets.secondary_button(txt("ed_preview_window"), theme_name())
		preview_button.name = "PreviewWindowButton"
		preview_button.disabled = session == null
		preview_button.pressed.connect(func() -> void:
			if platform != null: platform.preview_document())
		desktop_actions.add_child(preview_button)
		content.add_child(desktop_actions)

	content.add_child(Widgets.caption(txt("ed_dsl"), theme_name()))
	var dsl_edit := TextEdit.new()
	dsl_edit.name = "DslEdit"
	dsl_edit.custom_minimum_size.y = 320
	dsl_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	dsl_edit.text = _dsl_text
	dsl_edit.text_changed.connect(func() -> void: _dsl_text = dsl_edit.text)
	content.add_child(dsl_edit)
	if _dsl_error != "":
		var err := Widgets.caption(_dsl_error, theme_name())
		err.name = "DslError"
		content.add_child(err)
	var dsl_actions := Widgets.hbox(Tokens.SPACE_2)
	var apply := Widgets.primary_button(txt("ed_dsl_apply"), theme_name())
	apply.name = "ApplyDslButton"
	apply.disabled = session == null
	apply.pressed.connect(_apply_dsl)
	dsl_actions.add_child(apply)
	var undo := Widgets.secondary_button(txt("ed_undo"), theme_name())
	undo.name = "UndoButton"
	undo.disabled = session == null or not session.can_undo()
	undo.pressed.connect(func() -> void:
		session.undo()
		_sync_dsl_text()
		rebuild())
	dsl_actions.add_child(undo)
	var redo := Widgets.secondary_button(txt("ed_redo"), theme_name())
	redo.name = "RedoButton"
	redo.disabled = session == null or not session.can_redo()
	redo.pressed.connect(func() -> void:
		session.redo()
		_sync_dsl_text()
		rebuild())
	dsl_actions.add_child(redo)
	content.add_child(dsl_actions)

	var actions := Widgets.hbox(Tokens.SPACE_2)
	var test := Widgets.primary_button(txt("ed_test"), theme_name())
	test.name = "TestButton"
	test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test.pressed.connect(func() -> void:
		if coordinator != null: coordinator.preview(coordinator.store.runtime_ref))
	actions.add_child(test)
	var save := Widgets.secondary_button(txt("ed_save"), theme_name())
	save.name = "SaveButton"
	save.disabled = session == null or coordinator == null or session.revision() == coordinator.store.saved_revision
	save.pressed.connect(_save)
	actions.add_child(save)
	var pub := Widgets.ai_button(txt("ed_publish"), theme_name())
	pub.name = "PublishButton"
	pub.pressed.connect(func() -> void: publish_requested.emit())
	actions.add_child(pub)
	content.add_child(actions)

func _sync_dsl_text() -> void:
	if session != null:
		_dsl_text = JSON.stringify(session.current(), "  ", true)
		_synced_session_token = session.state_token()
	_dsl_error = ""

func _runtime_ref_for(value: Dictionary) -> String:
	var meta: Variant = value.get("meta")
	if meta is not Dictionary: return ""
	var name := str(meta.get("runtime", "")); var version := str(meta.get("runtime_version", ""))
	return "%s@%s" % [name, version] if name != "" and version != "" else ""

func _matches_session_runtime(value: Dictionary) -> bool:
	return session != null and _runtime_ref_for(value) == _runtime_ref_for(session.current())

func _apply_dsl() -> void:
	var json := JSON.new()
	if json.parse(_dsl_text) != OK:
		_dsl_error = txt_fmt("ed_dsl_parse_error", [json.get_error_line(), json.get_error_message()])
		rebuild()
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		_dsl_error = txt("ed_dsl_object_error")
		rebuild()
		return
	if not _matches_session_runtime(json.data):
		_dsl_error = txt_fmt("ed_dsl_validation_error", ["RUNTIME_MISMATCH"])
		rebuild()
		return
	var runtime_ref := _runtime_ref_for(json.data)
	if coordinator == null or runtime_ref == "" or not await coordinator.apply_document(runtime_ref, json.data):
		_dsl_error = txt("ed_dsl_apply_error")
		rebuild()
		return
	_sync_dsl_text()
	_toast(txt("ed_dsl_applied"))
	rebuild()

func _balance(difficulty: int) -> void:
	if coordinator == null: return
	if await coordinator.balance(difficulty, coordinator.store.runtime_ref):
		_sync_dsl_text(); _toast(txt("ed_ai_applied")); rebuild()
	else: _toast(txt("forge_failed"))

func _structure(prompt: String, count: int, difficulty: int) -> void:
	if coordinator == null: return
	if await coordinator.structure(prompt, count, difficulty, coordinator.store.runtime_ref):
		_sync_dsl_text(); _toast(txt("ed_ai_applied")); rebuild()
	else: _toast(txt("forge_failed"))

func _save() -> void:
	if coordinator == null: return
	var ok: bool
	if coordinator.store.draft_id != "": ok = await coordinator.update_draft()
	else: ok = await coordinator.save_draft(coordinator.store.runtime_ref)
	_toast(txt("ed_saved_toast") if ok else txt("forge_failed"))

func _quota_text() -> String:
	if coordinator == null or coordinator.store.quota.is_empty():
		return ""
	var remaining := int(coordinator.store.quota.get("remaining", 0))
	var limit := int(coordinator.store.quota.get("limit", 0))
	if remaining <= 0:
		return txt("ai_quota_empty")
	return txt_fmt("ai_quota_fmt", [str(remaining), str(limit)])
