class_name VerifyScreen
extends ScreenBase

## 实名认证：提交进入 pending，管理员裁决后变为 verified/rejected。

signal verified
var operations:OperationsCoordinator
var _status: Dictionary = {}

func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

func refresh() -> void:
	if operations == null:
		return
	if await operations.load_verification():
		_status = operations.store.verification.duplicate(true)
		rebuild()

func _build() -> void:
	var status := str(_status.get("status", "not_submitted"))
	content.add_child(Widgets.body(txt("verify_desc"), theme_name(), &"text_secondary"))
	if status == "verified":
		content.add_child(Widgets.badge(txt("verified_tag"), theme_name(), true))
		if str(_status.get("id_masked", "")) != "":
			content.add_child(Widgets.caption(str(_status.get("id_masked")), theme_name()))
		return
	if status == "pending":
		content.add_child(Widgets.badge(txt("verify_pending_tag"), theme_name(), true))
		content.add_child(Widgets.caption(txt("verify_pending_toast"), theme_name()))
		return
	if status == "rejected":
		content.add_child(Widgets.badge(txt("verify_rejected_tag"), theme_name()))
		content.add_child(Widgets.caption(txt("verify_rejected_hint"), theme_name(), &"text_secondary"))
	content.add_child(Widgets.caption(txt("verify_name"), theme_name()))
	var name_edit := LineEdit.new()
	name_edit.name = "RealNameEdit"
	name_edit.placeholder_text = txt("verify_name_ph")
	content.add_child(name_edit)
	content.add_child(Widgets.caption(txt("verify_id"), theme_name()))
	var id_edit := LineEdit.new()
	id_edit.name = "IdEdit"
	id_edit.placeholder_text = txt("verify_id_ph")
	content.add_child(id_edit)
	var submit := Widgets.primary_button(txt("verify_btn"), theme_name())
	submit.name = "SubmitButton"
	submit.pressed.connect(func() -> void:
		if name_edit.text.strip_edges() == "" or id_edit.text.strip_edges().length() < 6:
			_toast(txt("verify_invalid_toast"))
			return
		if operations == null:
			_toast(txt("request_failed"))
			return
		submit.disabled = true
		var submitted:=await operations.submit_verification(name_edit.text.strip_edges(), id_edit.text.strip_edges())
		submit.disabled = false
		if submitted:
			id_edit.text = ""
			_status = operations.store.verification.duplicate(true)
			_toast(txt("verify_pending_toast"))
			rebuild()
			verified.emit()
		else:
			_toast(txt("request_failed")))
	content.add_child(submit)
