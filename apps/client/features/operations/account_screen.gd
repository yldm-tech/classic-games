class_name AccountScreen
extends ScreenBase

## Operations-owned 账号与安全屏：手机/密码/第三方绑定/实名入口/注销。

signal verify_requested
const PlatformBridge:=preload("res://platform/platform.gd")
const ConfirmSheetScript:=preload("res://ui/patterns/confirm_sheet.gd")

var _confirm_delete := false
var _delete_pending:=false
var _mode:=""
var _security:={"phone_masked":"","password_set":false,"providers":[]}
var _verification: Dictionary = {}
var _kyc_queue: Array = []
var identity: Variant
var operations:OperationsCoordinator

func _init(p_state: Node, p_identity: Variant = null,p_operations:OperationsCoordinator=null) -> void:
	identity = p_identity
	operations=p_operations
	super(p_state)

func refresh()->void:
	if operations==null:
		return
	if await operations.load_security():
		_security=operations.store.security
	await operations.load_verification()
	_verification=operations.store.verification.duplicate(true)
	_kyc_queue=[]
	if await operations.load_verification_queue():
		_kyc_queue=operations.store.verification_queue.duplicate(true)
	rebuild()

func invalidate_session()->void:
	_security={};_confirm_delete=false;_delete_pending=false;_mode="";super.invalidate_session()

func _build() -> void:
	var phone_row:=nav_row(txt("acc_phone"),str(_security.get("phone_masked",txt("acc_phone_val"))),func()->void:_mode="phone";rebuild());phone_row.name="PhoneRow";content.add_child(phone_row)
	var password_row:=nav_row(txt("acc_pwd"),txt("acc_set") if _security.get("password_set",false) else txt("acc_unbound"),func()->void:_mode="password";rebuild());password_row.name="PasswordRow";content.add_child(password_row)
	_add_oauth_row(txt("acc_bind_wx"),_primary_provider())
	_add_oauth_row(txt("acc_bind_ap"),"apple")
	if _mode=="password":_build_password_form()
	elif _mode=="phone":_build_phone_form()
	var verify := nav_row(txt("acc_verify"), _verify_label(), func() -> void: verify_requested.emit())
	verify.name = "VerifyRow"
	content.add_child(verify)
	if not _kyc_queue.is_empty():
		content.add_child(Widgets.caption(txt("st_queue"), theme_name()))
		for item: Dictionary in _kyc_queue:
			_add_kyc_row(item)
	content.add_child(Widgets.divider(theme_name()))

	if not _confirm_delete:
		var del := Widgets.danger_button(txt("acc_delete"), theme_name())
		del.name = "DeleteButton"
		del.pressed.connect(func() -> void:
			_confirm_delete = true
			rebuild())
		content.add_child(del)
		return

	var confirm=ConfirmSheetScript.new();confirm.name="DeleteConfirm";confirm.configure(txt("acc_delete_title"),txt("acc_delete_desc"),txt("acc_delete_confirm"),txt("cancel"),theme_name())
	confirm.set_pending(_delete_pending)
	confirm.confirmed.connect(func() -> void:
		if _delete_pending:return
		_delete_pending=true;rebuild()
		if operations == null or not await operations.delete_account():_delete_pending=false;_toast(txt("request_failed"));rebuild();return
		_toast(txt("acc_delete_toast")))
	confirm.cancelled.connect(func() -> void:
		if _delete_pending:return
		_confirm_delete = false
		rebuild())
	content.add_child(confirm)

func _verify_label() -> String:
	match str(_verification.get("status", "not_submitted")):
		"verified":
			return txt("verified_tag")
		"pending":
			return txt("verify_pending_tag")
		"rejected":
			return txt("verify_rejected_tag")
		_:
			return txt("unverified_tag")

func _add_kyc_row(item: Dictionary) -> void:
	var user_id := str(item.get("user_id", ""))
	var row := Widgets.hbox(Tokens.SPACE_2)
	row.name = "Kyc_%s" % user_id
	row.add_child(Widgets.caption("%s · %s" % [user_id, str(item.get("id_masked", ""))], theme_name()))
	var approve := Widgets.primary_button(txt("mq_approve"), theme_name())
	approve.name = "KycApprove_%s" % user_id
	approve.pressed.connect(func() -> void:
		if operations == null: return
		if await operations.decide_verification(user_id, true):
			_kyc_queue = operations.store.verification_queue.duplicate(true)
			rebuild())
	row.add_child(approve)
	var reject := Widgets.danger_button(txt("mq_reject"), theme_name())
	reject.name = "KycReject_%s" % user_id
	reject.pressed.connect(func() -> void:
		if operations == null: return
		if await operations.decide_verification(user_id, false):
			_kyc_queue = operations.store.verification_queue.duplicate(true)
			rebuild())
	row.add_child(reject)
	content.add_child(row)

func _primary_provider()->String:return "wechat" if state.locale=="zh" else ("line" if state.locale=="ja" else "google")
func _add_oauth_row(label:String,provider:String)->void:
	var linked:bool=provider in _security.get("providers",[])
	var row:=nav_row(label,txt("acc_bound") if linked else txt("acc_unbound"),func()->void:
		if linked:return
		var code:=PlatformBridge.oauth_login(provider)
		if code=="" or operations==null:_toast(txt("oauth_unavailable"));return
		if await operations.bind_oauth(provider,code):_security=operations.store.security;_toast(txt("toast_saved"));rebuild()
		else:_toast(txt("request_failed")));row.name="OAuth_%s"%provider;content.add_child(row)

func _build_password_form()->void:
	var edit:=LineEdit.new();edit.name="PasswordEdit";edit.secret=true;edit.placeholder_text=txt("acc_password_ph");content.add_child(edit)
	var save:=Widgets.primary_button(txt("ep_save"),theme_name());save.name="PasswordSaveButton";save.pressed.connect(func()->void:
		if operations==null:return
		if await operations.set_password(edit.text):_security=operations.store.security;_mode="";_toast(txt("toast_saved"));rebuild()
		else:_toast(operations.store.message if operations.store.message!="" else txt("request_failed")));content.add_child(save)

func _build_phone_form()->void:
	var phone:=LineEdit.new();phone.name="NewPhoneEdit";phone.placeholder_text=txt("phone_ph");content.add_child(phone)
	var code:=LineEdit.new();code.name="PhoneCodeEdit";code.placeholder_text=txt("code_ph");content.add_child(code)
	var send:=Widgets.secondary_button(txt("get_code"),theme_name());send.name="PhoneCodeButton";send.pressed.connect(func()->void:
		if identity==null:return
		if not await identity.send_code(phone.text.strip_edges()):_toast(identity.store.message));content.add_child(send)
	var save:=Widgets.primary_button(txt("ep_save"),theme_name());save.name="PhoneSaveButton";save.pressed.connect(func()->void:
		if operations==null:return
		if await operations.change_phone(phone.text.strip_edges(),code.text.strip_edges()):_security=operations.store.security;_mode="";_toast(txt("toast_saved"));rebuild()
		else:_toast(txt("request_failed")));content.add_child(save)
