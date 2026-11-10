class_name AuthScreen
extends ScreenBase

## 登录/注册:品牌 slogan + 手机验证码登录(60s 倒计时、未注册自动建号)+ 第三方 + 游客。
## 用户操作只形成身份意图，由 IdentityCoordinator 编排；本屏不知道 URL、token 或响应信封。

const PlatformBridge := preload("res://platform/platform.gd")

const CODE_COOLDOWN := 60

var _phone: LineEdit
var _code: LineEdit
var _cooldown := 0
var _code_btn: Button
var _tick_gen := 0  # 倒计时代次:每次 start_cooldown 自增,作废上一条 tick 链(防 rebuild/重复点按导致双链跳秒)
var identity: Variant

func _init(p_state: Node, p_identity: Variant = null) -> void:
	identity = p_identity
	super(p_state)

func request_state() -> Dictionary:
	return {"phone": _phone.text.strip_edges(), "code": _code.text.strip_edges()}

## 发码后的倒计时(AppRoot 在 /auth/sms/send 成功后调用;timer 驱动重渲)。
func start_cooldown() -> void:
	_cooldown = CODE_COOLDOWN
	_tick_gen += 1
	_tick(_tick_gen)

func _tick(gen: int) -> void:
	if gen != _tick_gen:
		return  # 已有更新的倒计时启动,本链作废
	if _code_btn != null and is_instance_valid(_code_btn):
		_code_btn.text = txt_fmt("code_again_fmt", [_cooldown]) if _cooldown > 0 else txt("get_code")
		_code_btn.disabled = _cooldown > 0
	if _cooldown > 0 and is_inside_tree():
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if gen != _tick_gen:
				return
			_cooldown -= 1
			_tick(gen))

func _build() -> void:
	var logo_wrap := CenterContainer.new()
	logo_wrap.name = "BrandLogo"
	logo_wrap.add_child(Widgets.brand_logo(theme_name(), Tokens.FONT_H1))
	content.add_child(logo_wrap)
	var slogan := Widgets.body(txt("auth_slogan"), theme_name(), &"text_secondary")
	slogan.name = "Slogan"
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(slogan)

	var card := Widgets.card(theme_name())
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	col.add_child(Widgets.heading(txt("auth_title"), 3, theme_name()))
	_phone = LineEdit.new()
	_phone.name = "PhoneEdit"
	_phone.placeholder_text = txt("phone_ph")
	col.add_child(_phone)
	var code_row := Widgets.hbox(Tokens.SPACE_2)
	_code = LineEdit.new()
	_code.name = "CodeEdit"
	_code.placeholder_text = txt("code_ph")
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 验证码框回车即提交身份意图。
	_code.text_submitted.connect(func(_t: String) -> void:
		_verify_identity())
	code_row.add_child(_code)
	_code_btn = Widgets.secondary_button(txt("get_code"), theme_name())
	_code_btn.name = "GetCodeButton"
	# 仅协调器确认发码成功才通过 code_sent 启动冷却。
	_code_btn.pressed.connect(func() -> void:
		_send_code())
	code_row.add_child(_code_btn)
	col.add_child(code_row)
	var login := Widgets.primary_button(txt("login_btn"), theme_name())
	login.name = "LoginButton"
	login.pressed.connect(_verify_identity)
	col.add_child(login)
	var password:=LineEdit.new();password.name="PasswordLoginEdit";password.secret=true;password.placeholder_text=txt("acc_password_ph");col.add_child(password)
	var password_login:=Widgets.secondary_button(txt("password_login"),theme_name());password_login.name="PasswordLoginButton";password_login.pressed.connect(func()->void:_password_identity(password.text));col.add_child(password_login)
	col.add_child(Widgets.caption(txt("auth_note"), theme_name()))
	content.add_child(card)

	content.add_child(Widgets.caption(txt("other_login"), theme_name()))
	var socials := Widgets.hbox(Tokens.SPACE_2)
	socials.name = "Socials"
	for s: String in txt("socials"):
		var b := Widgets.secondary_button(s, theme_name())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var provider := _oauth_provider(s)
		b.pressed.connect(func() -> void:
			var code := PlatformBridge.oauth_login(provider)
			if code != "":
				_oauth_identity(provider, code)
			else:
				_toast(txt("oauth_unavailable")))
		socials.add_child(b)
	content.add_child(socials)

	var guest := Button.new()
	guest.name = "GuestButton"
	guest.text = txt("guest_btn")
	guest.flat = true
	guest.add_theme_color_override("font_color", Tokens.color(&"text_muted", theme_name()))
	guest.pressed.connect(_guest_identity)
	content.add_child(guest)

func _send_code() -> void:
	var phone := _phone.text.strip_edges()
	if identity == null or phone == "":
		return
	if await identity.send_code(phone):
		start_cooldown()
	else:
		_toast(identity.store.message)

func _verify_identity() -> void:
	if identity != null and not await identity.verify_code(_phone.text.strip_edges(), _code.text.strip_edges()):
		_toast(identity.store.message)

func _password_identity(password: String) -> void:
	if identity != null and not await identity.password_login(_phone.text.strip_edges(), password):
		_toast(identity.store.message)

func _oauth_identity(provider: String, code: String) -> void:
	if identity != null and not await identity.oauth_exchange(provider, code):
		_toast(identity.store.message)

func _guest_identity() -> void:
	if identity != null and not await identity.guest_login():
		_toast(identity.store.message)

func _oauth_provider(label:String)->String:
	match label.to_lower():
		"微信": return "wechat"
		"qq": return "qq"
		"line": return "line"
		"discord": return "discord"
		"google": return "google"
		_: return "apple"
