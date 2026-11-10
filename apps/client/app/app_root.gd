class_name AppRoot
extends Control

## 唯一应用装配根：构建 feature graph、登录/引导门、平台 chrome 与 Router 屏幕切换。
## → 数据接线 + Toast/更新弹窗/推送横幅。
## 各 feature 通过自己的 coordinator 拉取域数据；AppRoot 只负责编排跨域意图。
## 外部 gateway 可在构造时替换，供离线契约测试和平台适配使用。

const Tokens := preload("res://shell/design_system/theme/tokens.gd")
const Strings := preload("res://i18n/strings.gd")
const Widgets := preload("res://shell/design_system/components/widgets.gd")
const PlatformBridge := preload("res://platform/platform.gd")
const ScreenRegistryScript := preload("res://app/screen_registry.gd")
const ChromeControllerScript := preload("res://app/chrome/chrome_controller.gd")
const CatalogRetryControllerScript := preload("res://app/catalog_retry_controller.gd")
const TeenGuardScript := preload("res://app/teen_guard.gd")

const LOADING_SECS := 0.8

var state: Node
var router: Router
var identity: IdentityCoordinator
var catalog: CatalogCoordinator
var creation: CreationCoordinator
var creation_platform: CreationPlatformPort
var community: CommunityCoordinator
var engagement: EngagementCoordinator
var engagement_runtime: Variant
var commerce: CommerceCoordinator
var operations:OperationsCoordinator
var identity_http:HttpClient
var identity_store:IdentityStore
var catalog_store:CatalogStore
var creation_store:CreationStore
var creation_session:CreatorSessionAdapter
var community_store:CommunityStore
var engagement_store:EngagementStore
var commerce_store:CommerceStore
var operations_store:OperationsStore
var _account_gateways:Dictionary={}
var _account_http:Array[HttpClient]=[]
var _session_epoch:=0
var _account_rebuild_pending:=false

# 五个 Tab
var home: HomeScreen
var explore: ExploreScreen
var forge: ForgeScreen
var messages: MessagesScreen
var profile: ProfileScreen
# 入口/系统
var auth: AuthScreen
var onboarding: OnboardingScreen
var offline: OfflineScreen
var search: SearchScreen
# 子页(view 名 → {screen, title_key};见 _register)
var screen_registry: ScreenRegistry
var _views: Dictionary
var catalog_retry: CatalogRetryController

var detail: DetailScreen
var settings: SettingsScreen
var play_view: PlayView
var editor:EditorScreen
var _tracked_detail_id := ""
var _current_fork_depth := 0

const TAB_GLYPHS := ["⌂", "◎", "✦", "✉", "◉"]

## 布局形态:phone(底部 TabBar)/ rail(iPad 左侧竖排)/ desktop(侧栏+标题栏)。
## 真机由窗口尺寸驱动(_ready 接 size_changed);headless 测试直接 set_layout。
var layout := "phone"
var chrome_controller := ChromeControllerScript.new()

func _notification(what:int)->void:
	if what!=NOTIFICATION_PREDELETE:return
	if identity_http!=null:identity_http.cancel_all()
	for transport:HttpClient in _account_http:transport.cancel_all()
	# 常驻路由缓存中的 screen 切走后会从 _content 摘下，但仍由字段/_views 持有；
	# Node 引用不是所有权，Shell 销毁时必须显式释放这些离树页面。
	var cached:Array=[home,explore,forge,messages,profile,auth,onboarding,offline,search,detail,settings,play_view]
	for entry:Dictionary in _views.values():cached.append(entry.get("screen"))
	var seen:Dictionary={}
	for node:Variant in cached:
		if is_instance_valid(node) and node is Node and not seen.has(node.get_instance_id()):
			seen[node.get_instance_id()]=true
			if node.get_parent()==null:node.free()
	screen_registry.dispose_detached()

var _bg: ColorRect
var _statusbar: PanelContainer
var _appbar: PanelContainer
var _content: MarginContainer
var _tabbar: HBoxContainer
var _column: VBoxContainer
var _outer: VBoxContainer
var _main: HBoxContainer
var _rail: PanelContainer
var _sidebar: PanelContainer
var _toast: PanelContainer
var _toast_label: Label
var _overlay: PanelContainer        # 更新弹窗
var _push_banner: PanelContainer    # 推送横幅
var _push_shown := false
var _play_started_ms := 0

func _init(p_state:Node,base_url:String="",adapters:Dictionary={})->void:
	name="AppRoot"
	state = p_state
	_compose(base_url,adapters)
	_views = screen_registry.routes
	catalog_retry = CatalogRetryControllerScript.new(router)
	_connect_account_scope()
	if identity != null:
		identity.authenticated.connect(_on_identity_authenticated)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	# 布局骨架:[rail|sidebar] + 列(状态栏/应用栏/内容/TabBar)。桌面用系统原生窗口栏,不自绘标题栏。
	_outer = VBoxContainer.new()
	_outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outer.add_theme_constant_override("separation", 0)
	add_child(_outer)
	_main = Widgets.hbox(0)
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outer.add_child(_main)
	_rail = PanelContainer.new()
	_rail.visible = false
	_main.add_child(_rail)
	_sidebar = PanelContainer.new()
	_sidebar.visible = false
	_main.add_child(_sidebar)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 0)
	_main.add_child(_column)
	_statusbar = PanelContainer.new()
	_column.add_child(_statusbar)
	_appbar = PanelContainer.new()
	_column.add_child(_appbar)
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_%s" % side, Tokens.GUTTER)
	_column.add_child(_content)
	_tabbar = Widgets.hbox(0)
	_column.add_child(_tabbar)

	# Toast(z 最高,docs/19 原型 z 层教训)
	_toast = PanelContainer.new()
	_toast.visible = false
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position.y = -80
	_toast_label = Label.new()
	_toast.add_child(_toast_label)
	add_child(_toast)

	_make_screens()
	router.changed.connect(_sync)
	state.session_changed.connect(_sync)
	state.theme_changed.connect(func(_t: String) -> void: _render_chrome())
	state.locale_changed.connect(func(_l: String) -> void: _render_chrome())
	state.unread_changed.connect(func(_n: int) -> void: _render_chrome())
	# 游客直达首页:未登录则启动即建本地会话,首帧直进首页;登录改为按需(设置内登出回登录页)。
	if not state.authed:
		_enter_as_guest()
	_render_chrome()
	_sync()

func _compose(base_url:String,adapters:Dictionary)->void:
	router=Router.new()
	identity_http=HttpClient.new(base_url);identity_http.set_token(str(state.get("token")))
	var identity_gateway:Variant=adapters.get("identity",IdentityApi.new(identity_http))
	identity_store=IdentityStore.new();identity=IdentityCoordinator.new(identity_gateway,identity_store,state,[identity_http])
	_bind_refresh(identity_http)
	add_child(identity_http);add_child(identity_store);add_child(identity)
	_account_gateways={
		"catalog":adapters.catalog if adapters.has("catalog") else CatalogApi.new(_new_account_http(base_url)),
		"creation":adapters.creation if adapters.has("creation") else CreationApi.new(_new_account_http(base_url)),
		"community":adapters.community if adapters.has("community") else CommunityApi.new(_new_account_http(base_url)),
		"engagement":adapters.engagement if adapters.has("engagement") else EngagementApi.new(_new_account_http(base_url)),
		"commerce":adapters.commerce if adapters.has("commerce") else CommerceApi.new(_new_account_http(base_url)),
		"operations":adapters.operations if adapters.has("operations") else OperationsApi.new(_new_account_http(base_url)),
	}
	_create_account_scope()
	state.session_changed.connect(_on_app_session_changed)

func _new_account_http(base_url:String)->HttpClient:
	var transport:=HttpClient.new(base_url)
	transport.set_token(str(state.get("token")))
	_bind_refresh(transport)
	_account_http.append(transport);add_child(transport)
	return transport

func _bind_refresh(transport:HttpClient)->void:
	transport.set_refresh_handler(func():
		return await identity.refresh_session())

func _create_account_scope()->void:
	catalog_store=CatalogStore.new();catalog=CatalogCoordinator.new(_account_gateways.catalog,catalog_store)
	creation_store=CreationStore.new();	creation_session=CreatorSessionAdapter.new(func(runtime_ref:String,dsl:Dictionary)->bool:
		_request_play({"id":"editor-test","title":"Editor Test","runtime":runtime_ref,"dsl":dsl.duplicate(true)});return true)
	var initial_runtime:="shooter@1.0.0";var initial_baseline:=_local_baseline(initial_runtime)
	creation_session.load_baseline(initial_runtime,initial_baseline);creation_store.runtime_ref=initial_runtime;creation_store.baseline=initial_baseline.duplicate(true)
	creation=CreationCoordinator.new(_account_gateways.creation,creation_store,creation_session)
	creation_platform=CreationPlatformPort.new(creation_session);creation_platform.document_imported.connect(_on_creation_document_imported)
	community_store=CommunityStore.new();community=CommunityCoordinator.new(_account_gateways.community,community_store)
	engagement_store=EngagementStore.new();engagement=EngagementCoordinator.new(_account_gateways.engagement,engagement_store,_load_library_collection);engagement_runtime=EngagementRuntimePort.new(_account_gateways.engagement)
	commerce_store=CommerceStore.new();commerce=CommerceCoordinator.new(_account_gateways.commerce,commerce_store)
	operations_store=OperationsStore.new();operations=OperationsCoordinator.new(_account_gateways.operations,operations_store,func():state.logout())
	screen_registry=ScreenRegistryScript.new()
	_register_factories()
	for child:Node in [catalog_store,catalog,creation_store,creation,creation_platform,community_store,community,engagement_store,engagement,commerce_store,commerce,operations_store,operations]:add_child(child)

func _connect_account_scope()->void:
	for feature:Variant in [catalog,community,engagement,commerce,operations]:
		feature.store.changed.connect(_on_feature_changed.bind(feature.store))

func _rebuild_account_scope()->void:
	_account_rebuild_pending=false
	# Account scope is replaced as one unit. This makes stale coroutines and every
	# screen-owned read model unreachable before another identity can render.
	for transport:HttpClient in _account_http:transport.cancel_all()
	for gateway:Variant in _account_gateways.values():
		if gateway!=null and gateway.has_method("cancel_all"):gateway.cancel_all()
	for child:Node in _content.get_children():
		if child is ScreenBase:_content.remove_child(child)
	screen_registry.dispose_detached()
	for node:Node in [catalog,creation,creation_platform,community,engagement,commerce,operations,catalog_store,creation_store,community_store,engagement_store,commerce_store,operations_store]:
		if is_instance_valid(node):
			if node.get_parent()==self:remove_child(node)
			node.free()
	_create_account_scope()
	_views=screen_registry.routes
	catalog_retry=CatalogRetryControllerScript.new(router)
	_connect_account_scope()
	_tracked_detail_id="";_current_fork_depth=0
	_make_screens()
	_sync()

func _register_factories()->void:
	screen_registry.register_factory("catalog.home",func()->Node:return HomeScreen.new(state,catalog))
	screen_registry.register_factory("catalog.explore",func()->Node:return ExploreScreen.new(state,catalog))
	screen_registry.register_factory("catalog.search",func()->Node:return SearchScreen.new(state,catalog))
	screen_registry.register_factory("catalog.profile",func()->Node:return ProfileScreen.new(state,catalog))
	screen_registry.register_factory("catalog.creator",func()->Node:return CreatorScreen.new(state,catalog,community))
	screen_registry.register_factory("catalog.detail",func()->Node:return DetailScreen.new(state,community,engagement,catalog))
	screen_registry.register_factory("catalog.trending",func()->Node:
		var screen:=ExploreScreen.new(state,catalog);screen.configure_ranking_page(1);return screen)
	screen_registry.register_factory("creation.forge",func()->Node:return ForgeScreen.new(state,creation))
	screen_registry.register_factory("creation.editor",func()->Node:return EditorScreen.new(state,creation,creation_session,creation_platform))
	screen_registry.register_factory("creation.studio",func()->Node:return StudioScreen.new(state,creation))
	screen_registry.register_factory("creation.publish",func()->Node:return PublishScreen.new(state,creation))
	screen_registry.register_factory("creation.review",func()->Node:return ReviewScreen.new(state,creation))
	screen_registry.register_factory("community.messages",func()->Node:return MessagesScreen.new(state,community))
	screen_registry.register_factory("community.chat",func()->Node:return ChatScreen.new(state,community))
	screen_registry.register_factory("community.follow",func()->Node:return FollowListScreen.new(state,community))
	screen_registry.register_factory("community.add_friend",func()->Node:return AddFriendScreen.new(state,community))
	screen_registry.register_factory("engagement.library",func()->Node:return LibraryScreen.new(state,engagement))
	screen_registry.register_factory("engagement.downloads",func()->Node:return DownloadsScreen.new(state,engagement))
	screen_registry.register_factory("engagement.history",func()->Node:return HistoryScreen.new(state,engagement))
	screen_registry.register_factory("engagement.live",func()->Node:return LiveScreen.new(state,engagement,community))
	screen_registry.register_factory("engagement.room",func()->Node:return RoomScreen.new(state,engagement))
	screen_registry.register_factory("engagement.replay",func()->Node:return ReplayScreen.new(state,engagement))
	screen_registry.register_factory("commerce.points",func()->Node:return PointsScreen.new(state,commerce))
	screen_registry.register_factory("commerce.shop",func()->Node:return ShopScreen.new(state,commerce))
	screen_registry.register_factory("commerce.membership",func()->Node:return MembershipScreen.new(state,commerce))
	screen_registry.register_factory("commerce.welfare",func()->Node:return WelfareScreen.new(state,commerce))
	screen_registry.register_factory("commerce.events",func()->Node:return EventsScreen.new(state,commerce))
	screen_registry.register_factory("commerce.achievements",func()->Node:return AchievementsScreen.new(state,commerce))
	screen_registry.register_factory("commerce.avatar",func()->Node:return AvatarScreen.new(state,commerce,_update_avatar_profile))
	screen_registry.register_factory("commerce.earnings",func()->Node:return EarningsScreen.new(state,commerce))
	screen_registry.register_factory("commerce.pay_result",func()->Node:return PayResultScreen.new(state))
	screen_registry.register_factory("operations.report",func()->Node:return ReportScreen.new(state,operations))
	screen_registry.register_factory("operations.blocklist",func()->Node:return BlocklistScreen.new(state,operations))
	screen_registry.register_factory("operations.notifications",func()->Node:return NotifPrefScreen.new(state,operations))
	screen_registry.register_factory("operations.privacy",func()->Node:return PrivacyScreen.new(state,operations))
	screen_registry.register_factory("operations.teen",func()->Node:return TeenScreen.new(state,operations))
	screen_registry.register_factory("operations.edit_profile",func()->Node:return EditProfileScreen.new(state,operations))
	screen_registry.register_factory("operations.verify",func()->Node:return VerifyScreen.new(state,operations))
	screen_registry.register_factory("operations.account",func()->Node:return AccountScreen.new(state,identity,operations))
	screen_registry.register_factory("operations.help",func()->Node:return HelpScreen.new(state,operations))
	screen_registry.register_factory("operations.analytics",func()->Node:return AnalyticsScreen.new(state,operations))
	screen_registry.register_factory("identity.auth",func()->Node:return AuthScreen.new(state,identity))
	screen_registry.register_factory("app.about",func()->Node:return AboutScreen.new(state,operations))
	screen_registry.register_factory("app.offline",func()->Node:return OfflineScreen.new(state))
	screen_registry.register_factory("app.onboarding",func()->Node:return OnboardingScreen.new(state))
	screen_registry.register_factory("app.settings",func()->Node:return SettingsScreen.new(state))
	screen_registry.register_factory("app.share",func()->Node:return ShareScreen.new(state))
	screen_registry.register_factory("app.play",func()->Node:return PlayView.new(state,engagement_runtime))

func _ready() -> void:
	# 自适应布局:窗口尺寸驱动 phone/rail/desktop + 横竖屏
	_update_layout_from_size()
	_sync()
	get_viewport().size_changed.connect(_update_layout_from_size)
	# 首页首载骨架(原型行为:0.7s 后换内容)
	home.show_skeleton()
	get_tree().create_timer(0.7).timeout.connect(home.finish_loading)
	# Headless runs validate composition only; starting fire-and-forget HTTP work there
	# leaves an awaiting coroutine when the scene is intentionally torn down immediately.
	if identity != null and state.authed and DisplayServer.get_name() != "headless":
		if state.token == "":
			identity.guest_login() # 游客本地会话补服务端 token
		else:
			_refresh_remote()  # 已登录用户:直接拉数据
		_load_teen_prefs()

## 按窗口宽度切布局形态,并同步 Router 的设备语义(闸门只对手机竖屏)。
func _update_layout_from_size() -> void:
	var win := get_viewport().get_visible_rect().size
	set_layout(chrome_controller.mode_for_width(win.x))
	router.resolve_orientation(win.y >= win.x)

func set_layout(mode: String) -> void:
	if mode == layout:
		return
	if not chrome_controller.set_mode(mode):
		return
	layout = chrome_controller.mode
	router.is_phone = layout == "phone"
	_apply_card_cols()
	_sync()

## 把卡片网格列数按布局喂给各屏(桌面 4 / iPad 3 / 手机 2),变化时重建。
## tab 屏构造期不在树上,无法自读窗口宽度,故由 AppRoot 统一驱动。
func _apply_card_cols() -> void:
	var c := 4 if layout == "desktop" else 3 if layout == "rail" else 2
	var screens: Array = [home, explore, profile, detail]
	if _views.has("creator"):
		screens.append(_views["creator"]["screen"])
	for scr in screens:
		if scr != null and scr.card_cols != c:
			scr.card_cols = c
			scr.rebuild()

## ESC / Android 返回键 → 统一返回(子页弹栈,tabs 不动)。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		handle_back()
		get_viewport().set_input_as_handled()

func handle_back() -> void:
	if state.authed and state.onboarded and router.view != Router.VIEW_TABS and router.view != Router.VIEW_PLAY:
		router.back()

# ── 屏幕构建与接线 ───────────────────────────────────────────
func _register(view_name: String, screen: ScreenBase, title_key: String) -> void:
	screen.toaster = show_toast
	screen_registry.register(view_name, screen, title_key)

func _make_screens() -> void:
	# 入口/系统
	auth = screen_registry.build("identity.auth") as AuthScreen
	auth.toaster = show_toast
	onboarding = screen_registry.build("app.onboarding") as OnboardingScreen
	onboarding.toaster = show_toast
	onboarding.done.connect(func() -> void:
		state.finish_onboarding()
		_sync())
	offline = screen_registry.build("app.offline") as OfflineScreen
	offline.retry.connect(_retry_offline)
	_register("offline", offline, "off_title")
	search = screen_registry.build("catalog.search") as SearchScreen
	search.game_opened.connect(router.open_game)
	search.closed.connect(router.back)
	_register("search", search, "search")

	# 五个 Tab
	home = screen_registry.build("catalog.home") as HomeScreen
	home.game_opened.connect(router.open_game)
	home.play_requested.connect(_request_play)
	home.explore_requested.connect(func() -> void: router.set_tab(1))
	home.events_requested.connect(func() -> void: router.go("events"))
	home.trending_loaded.connect(func(items: Array) -> void: forge.bind_trending(items))
	explore = screen_registry.build("catalog.explore") as ExploreScreen
	explore.game_opened.connect(router.open_game)
	explore.live_opened.connect(func(live: Array) -> void:
		(_views["live"]["screen"] as LiveScreen).set_live(live)
		router.go("live"))
	# 飙升榜独立专页(侧栏 Trending):复用 ExploreScreen 的榜单渲染,只放飙升榜单,与发现 tab 区分
	var trending := screen_registry.build("catalog.trending") as ExploreScreen
	trending.game_opened.connect(router.open_game)
	_register("trending", trending, "side_trending")
	forge = screen_registry.build("creation.forge") as ForgeScreen
	forge.generation_started.connect(func(_prompt: String) -> void:
		if operations != null: operations.track_event("ai_edit_started", str(router.game.get("id", ""))))
	forge.generation_completed.connect(_on_generation_completed)
	forge.game_opened.connect(router.open_game)
	forge.studio_requested.connect(func() -> void: router.go("studio"))
	messages = screen_registry.build("community.messages") as MessagesScreen
	messages.chat_opened.connect(func(conversation: Dictionary) -> void:
		(_views["chat"]["screen"] as ChatScreen).set_conversation(conversation)
		router.go("chat"))
	messages.add_friend_requested.connect(func() -> void: router.go("addFriend"))
	profile = screen_registry.build("catalog.profile") as ProfileScreen
	profile.game_opened.connect(router.open_game)
	profile.settings_requested.connect(func() -> void: router.go(Router.VIEW_SETTINGS))
	profile.edit_requested.connect(func() -> void: router.go("editProfile"))
	profile.follow_requested.connect(func(tab: int) -> void:
		(_views["follow"]["screen"] as FollowListScreen).set_tab(tab)
		router.go("follow"))
	profile.points_requested.connect(func() -> void: router.go("points"))
	profile.entry_selected.connect(func(key: String) -> void: router.go(key))
	for tab_screen: ScreenBase in [home, explore, forge, messages, profile]:
		tab_screen.toaster = show_toast
	# 详情/设置/游玩(Router 固定 view)
	detail = screen_registry.build("catalog.detail") as DetailScreen
	detail.play_requested.connect(_request_play)
	detail.fork_requested.connect(_on_fork)
	detail.creator_opened.connect(_open_creator)
	detail.share_requested.connect(func(g: Dictionary) -> void:
		(_views["share"]["screen"] as ShareScreen).set_target(g)
		router.go("share"))
	detail.more_requested.connect(func(g: Dictionary) -> void:
		(_views["report"]["screen"] as ReportScreen).set_target(g)
		router.go("report"))
	detail.replay_requested.connect(func(user_id:String,handle: String, g: Dictionary) -> void:
		(_views["replay"]["screen"] as ReplayScreen).set_replay(handle, g,user_id)
		router.go("replay"))
	_register(Router.VIEW_DETAIL, detail, "")
	settings = screen_registry.build("app.settings") as SettingsScreen
	settings.logged_out.connect(func() -> void: router.back())
	settings.account_requested.connect(func() -> void: router.go("account"))
	settings.notif_requested.connect(func() -> void: router.go("notif"))
	settings.privacy_requested.connect(func() -> void: router.go("privacy"))
	settings.teen_requested.connect(func() -> void: router.go("teen"))
	settings.blocklist_requested.connect(func() -> void: router.go("blocklist"))
	settings.about_requested.connect(func() -> void: router.go("about"))
	settings.help_requested.connect(func() -> void: router.go("help"))
	settings.edit_profile_requested.connect(func() -> void: router.go("editProfile"))
	settings.analytics_requested.connect(func() -> void: router.go("analytics"))
	_register(Router.VIEW_SETTINGS, settings, "set_title")
	play_view = screen_registry.build("app.play") as PlayView
	play_view.toaster = show_toast
	play_view.exited.connect(router.exit_play)
	play_view.fork_here_requested.connect(func(g: Dictionary) -> void:
		router.exit_play()
		_on_fork(g))

	# 账号集群
	_register("editProfile",screen_registry.build("operations.edit_profile"),"edit_profile")
	var account := screen_registry.build("operations.account") as AccountScreen
	account.verify_requested.connect(func() -> void: router.go("verify"))
	_register("account", account, "acc_title")
	var verify := screen_registry.build("operations.verify") as VerifyScreen
	verify.verified.connect(router.back)
	_register("verify", verify, "verify_title")
	_register("points", screen_registry.build("commerce.points"), "points_title")
	_register("help",screen_registry.build("operations.help"),"help_title")
	_register("analytics",screen_registry.build("operations.analytics"),"analytics_title")
	_register("about", _wire(screen_registry.build("app.about") as AboutScreen), "about_title")
	_register("teen",screen_registry.build("operations.teen"),"teen_title")
	_register("blocklist",screen_registry.build("operations.blocklist"),"blk_title")
	_register("notif",screen_registry.build("operations.notifications"),"np_title")
	_register("privacy",screen_registry.build("operations.privacy"),"pv_title")

	# 创作集群
	var studio := screen_registry.build("creation.studio") as StudioScreen
	studio.edit_requested.connect(func(_work: Dictionary) -> void: router.go("editor"))
	studio.publish_requested.connect(func() -> void: router.go("publish"))
	studio.earnings_requested.connect(func() -> void: router.go("earnings"))
	studio.review_requested.connect(func(w: Dictionary) -> void:
		(_views["review"]["screen"] as ReviewScreen).set_review_state(true, str(w.get("id", "")))
		router.go("review"))
	studio.game_opened.connect(router.open_game)
	_register("studio", studio, "st_title")
	editor = screen_registry.build("creation.editor") as EditorScreen
	editor.publish_requested.connect(func() -> void: router.go("publish"))
	_register("editor", editor, "ed_title")
	var publish := screen_registry.build("creation.publish") as PublishScreen
	publish.submitted.connect(func(_title: String) -> void:
		if operations != null:
			operations.track_event("mod_published", str(creation.store.game_id))
		(_views["review"]["screen"] as ReviewScreen).set_review_state(false, creation.store.game_id)
		router.go("review"))
	_register("publish", publish, "pb_title")
	var review := screen_registry.build("creation.review") as ReviewScreen
	review.fix_requested.connect(func() -> void: router.go("editor"))
	_register("review", review, "rev_title")
	_register("earnings", screen_registry.build("commerce.earnings"), "ea_title")

	# 社交集群
	var creator := screen_registry.build("catalog.creator") as CreatorScreen
	creator.game_opened.connect(router.open_game)
	creator.follow_requested.connect(_on_creator_follow)
	_register("creator", creator, "")
	var chat := screen_registry.build("community.chat") as ChatScreen
	chat.room_requested.connect(func() -> void: router.go("room"))
	_register("chat", chat, "")
	_register("addFriend", screen_registry.build("community.add_friend"), "af_title")
	var follow := screen_registry.build("community.follow") as FollowListScreen
	follow.creator_opened.connect(_open_creator)
	_register("follow", follow, "")
	var room := screen_registry.build("engagement.room") as RoomScreen
	room.start_requested.connect(func(room_data: Dictionary) -> void:
		# 权威联机对局不绑定任何具体游戏(apps/server/internal/rooms 的 Room 模型本就没有 game_id),
		# 不借用某个种子游戏的身份(标题/作者)冒充,给一个如实的房间标签。
		var room_id := str(room_data.get("id", ""))
		var network_game := {"id": "room_%s" % room_id, "title": String(Strings.t(state.locale, "room_title")), "network_room_id": room_id}
		_request_play(network_game))
	_register("room", room, "room_title")

	# 商业/留存
	var shop := screen_registry.build("commerce.shop") as ShopScreen
	shop.paid.connect(_open_pay_result)
	_register("shop", shop, "shop_title")
	var membership := screen_registry.build("commerce.membership") as MembershipScreen
	membership.subscribed.connect(_open_pay_result)
	_register("membership", membership, "mem_title")
	var pay_result := screen_registry.build("commerce.pay_result") as PayResultScreen
	pay_result.done.connect(router.back)
	_register("payResult", pay_result, "pay_ok_title")
	_register("welfare", screen_registry.build("commerce.welfare"), "welfare_title")
	_register("events", screen_registry.build("commerce.events"), "ev_title")
	_register("achievements", screen_registry.build("commerce.achievements"), "ach_page_title")
	_register("avatar", screen_registry.build("commerce.avatar"), "av_title")

	# 库/全局
	var library := screen_registry.build("engagement.library") as LibraryScreen
	library.game_opened.connect(router.open_game)
	_register("library", library, "")  # 标题随集合切换,见 _subpage_title
	var downloads := screen_registry.build("engagement.downloads") as DownloadsScreen
	downloads.game_opened.connect(router.open_game)
	_register("downloads", downloads, "dl_title")
	var history := screen_registry.build("engagement.history") as HistoryScreen
	history.game_opened.connect(router.open_game)
	history.play_requested.connect(_request_play)
	# A completed run changes server history; force a fresh fetch the next time
	# this cached screen is shown instead of retaining its first-load snapshot.
	play_view.play_recorded.connect(func(_game_id: String) -> void:
		history._refreshed = false
		detail._refreshed = false)
	_register("history", history, "his_title")
	var live := screen_registry.build("engagement.live") as LiveScreen
	live.closed.connect(router.back)
	_register("live", live, "live_sec_title")
	var replay := screen_registry.build("engagement.replay") as ReplayScreen
	replay.closed.connect(router.back)
	_register("replay", replay, "rep_title")
	var report := screen_registry.build("operations.report") as ReportScreen
	report.action_completed.connect(_on_operations_action_completed)
	_register("report", report, "more_title")
	var share := screen_registry.build("app.share") as ShareScreen
	share.shared.connect(router.back)
	_register("share", share, "share_title")

func _wire(screen: ScreenBase) -> ScreenBase:
	screen.toaster = show_toast
	return screen

func tab_screens() -> Array:
	return [home, explore, forge, messages, profile]

func _open_creator(handle: String) -> void:
	(_views["creator"]["screen"] as CreatorScreen).set_creator(handle)
	router.go("creator")

func _open_pay_result(order_desc: String, order_id: String) -> void:
	(_views["payResult"]["screen"] as PayResultScreen).set_order(order_desc, order_id)
	router.go("payResult")

# ── chrome ─────────────────────────────────────────────────
func _render_chrome() -> void:
	_bg.color = Tokens.color(&"bg_app", state.theme)
	theme = Widgets.app_theme(state.theme)  # 级联:输入框/进度条全树统一设计系统样式
	var toast_style := Widgets.card_style(state.theme, &"surface_raised", Tokens.RADIUS_PILL)
	toast_style.set_content_margin_all(Tokens.SPACE_3)
	toast_style.content_margin_left = Tokens.SPACE_5
	toast_style.content_margin_right = Tokens.SPACE_5
	_toast.add_theme_stylebox_override("panel", toast_style)
	_toast_label.add_theme_color_override("font_color", Tokens.color(&"text_primary", state.theme))
	_toast_label.add_theme_font_size_override("font_size", Tokens.FONT_BODY)

	# 状态栏(手机 chrome:时间 + 信号/电池;iPad/桌面 chrome 待真机批次)
	for c in _statusbar.get_children():
		_statusbar.remove_child(c)
		c.queue_free()
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Tokens.color(&"bg_app", state.theme)
	sb_style.content_margin_left = Tokens.SPACE_4
	sb_style.content_margin_right = Tokens.SPACE_4
	sb_style.content_margin_top = Tokens.SPACE_1
	sb_style.content_margin_bottom = Tokens.SPACE_1
	_statusbar.add_theme_stylebox_override("panel", sb_style)
	var sb_row := Widgets.hbox()
	var now := Time.get_time_dict_from_system()
	var clock := Label.new()
	clock.name = "StatusClock"
	clock.text = "%d:%02d" % [now["hour"], now["minute"]]
	clock.add_theme_font_size_override("font_size", Tokens.FONT_BODY_SM)
	clock.add_theme_color_override("font_color", Tokens.color(&"text_primary", state.theme))
	sb_row.add_child(clock)
	sb_row.add_child(Widgets.spacer())
	var glyphs := Label.new()
	glyphs.text = "▖▌▉ ▮"
	glyphs.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	glyphs.add_theme_color_override("font_color", Tokens.color(&"text_secondary", state.theme))
	sb_row.add_child(glyphs)
	_statusbar.add_child(sb_row)

	# 应用栏:tabs 首页放 logo、其余页标题;子页放「‹ 返回 + 标题」
	# 摘树后延迟释放:本函数常由按钮 pressed 回调触发,立即 free 会砸到发信号中的按钮
	for c in _appbar.get_children():
		_appbar.remove_child(c)
		c.queue_free()
	var bar := Widgets.hbox(Tokens.SPACE_3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"bg_app", state.theme)
	sb.set_content_margin_all(Tokens.SPACE_3)
	_appbar.add_theme_stylebox_override("panel", sb)

	var in_tabs := router.view == Router.VIEW_TABS
	if layout == "desktop" and in_tabs:
		# 桌面 PaneHeader(对照原型):大标题 + AI 徽章 + ⌘K 搜索框 + 头像
		_fill_pane_header(bar)
	else:
		if not in_tabs:
			var back := Button.new()
			back.name = "BackButton"
			back.text = "‹"
			back.flat = true
			back.custom_minimum_size = Vector2(Tokens.HIT_MIN, 0)
			back.add_theme_color_override("font_color", Tokens.color(&"text_primary", state.theme))
			back.add_theme_font_size_override("font_size", Tokens.FONT_H2)
			back.pressed.connect(router.back)
			bar.add_child(back)
		if in_tabs and router.tab == 0:
			# 双色品牌 logo:Classic(主文字色)+ Games(熔炉橙红)
			var logo := Widgets.brand_logo(state.theme, Tokens.FONT_H3)
			logo.name = "AppBarTitle"
			bar.add_child(logo)
		else:
			var title := Label.new()
			title.name = "AppBarTitle"
			title.text = _pane_title(router.tab) if in_tabs else _subpage_title()
			title.add_theme_font_size_override("font_size", Tokens.FONT_H3)
			title.add_theme_color_override("font_color", Tokens.color(&"text_primary", state.theme))
			bar.add_child(title)
		if in_tabs and router.tab == 2:
			bar.add_child(Widgets.badge("AI", state.theme, true))
		bar.add_child(Widgets.spacer())
		if in_tabs and router.tab <= 1:
			var search_btn := Button.new()
			search_btn.name = "SearchButton"
			search_btn.text = "⌕"
			search_btn.flat = true
			search_btn.custom_minimum_size = Vector2(Tokens.HIT_MIN, 0)
			search_btn.add_theme_color_override("font_color", Tokens.color(&"text_primary", state.theme))
			search_btn.add_theme_font_size_override("font_size", Tokens.FONT_H3)
			search_btn.pressed.connect(func() -> void: router.go("search"))
			bar.add_child(search_btn)
	_appbar.add_child(bar)

	# TabBar:5 个 tab,中间「创作」为 AI 强调,消息带未读数
	for c in _tabbar.get_children():
		_tabbar.remove_child(c)
		c.queue_free()
	var tabs: Array = Strings.t(state.locale, "tabs")
	var pane_titles: Array = Strings.t(state.locale, "pane_titles")
	var labels := [tabs[0], tabs[1], pane_titles[2], tabs[2], tabs[3]]
	for i in labels.size():
		var on := i == router.tab
		var b := Button.new()
		b.name = "Tab%d" % i
		b.text = "%s %s" % [TAB_GLYPHS[i], labels[i]]
		b.flat = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, Tokens.HIT_MIN + 8)
		var tone: StringName = (&"accent_ai" if i == 2 else &"accent_primary") if on else &"text_muted"
		b.add_theme_color_override("font_color", Tokens.color(tone, state.theme))
		b.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
		if i == 3 and state.unread() > 0:
			# 未读红点徽章(叠按钮右上,docs/19 数字徽章不换行)
			var dot := Widgets.unread_dot(state.unread(), state.theme)
			dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			dot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			dot.offset_right = -Tokens.SPACE_2
			dot.offset_top = Tokens.SPACE_1
			b.add_child(dot)
		var idx := i
		b.pressed.connect(func() -> void:
			if router.view != Router.VIEW_TABS:
				router.view = Router.VIEW_TABS
			router.set_tab(idx)
			_sync())
		_tabbar.add_child(b)

	if layout == "rail":
		_render_rail(labels)
	elif layout == "desktop":
		_render_sidebar(labels)
	# 桌面用系统原生窗口栏,把当前页名写到原生标题上
	if is_inside_tree() and OS.has_feature("pc"):
		get_window().title = "Classic Games — %s" % _window_title()

## iPad 左侧 rail:竖排 5 tab(glyph 大字 + 标签),消息带未读红点。
func _render_rail(labels: Array) -> void:
	for c in _rail.get_children():
		_rail.remove_child(c)
		c.queue_free()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"bg_sunken", state.theme)
	sb.set_content_margin_all(Tokens.SPACE_2)
	_rail.add_theme_stylebox_override("panel", sb)
	var col := Widgets.vbox(Tokens.SPACE_2)
	col.name = "RailItems"
	for i in labels.size():
		var on := i == router.tab
		var b := Button.new()
		b.name = "Rail%d" % i
		b.text = "%s\n%s" % [TAB_GLYPHS[i], labels[i]]
		b.flat = true
		b.custom_minimum_size = Vector2(72, 56)
		var tone: StringName = (&"accent_ai" if i == 2 else &"accent_primary") if on else &"text_muted"
		b.add_theme_color_override("font_color", Tokens.color(tone, state.theme))
		b.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
		if i == 3 and state.unread() > 0:
			var dot := Widgets.unread_dot(state.unread(), state.theme)
			dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			dot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			dot.offset_right = -Tokens.SPACE_1
			b.add_child(dot)
		var idx := i
		b.pressed.connect(func() -> void: _go_tab(idx))
		col.add_child(b)
	_rail.add_child(col)

func _window_title() -> String:
	if router.view == Router.VIEW_DETAIL:
		return GameCard.title_of(router.game, state.locale)
	return _pane_title(router.tab)

## 桌面 PaneHeader 内容(对照原型 LargeApp PaneHeader):大标题 + AI 徽章 + ⌘K 搜索框 + 头像。
func _fill_pane_header(bar: HBoxContainer) -> void:
	var title := Label.new()
	title.name = "AppBarTitle"
	title.text = _pane_title(router.tab)
	title.add_theme_font_size_override("font_size", Tokens.FONT_H1)
	title.add_theme_color_override("font_color", Tokens.color(&"text_primary", state.theme))
	bar.add_child(title)
	if router.tab == 2:
		bar.add_child(Widgets.badge("AI", state.theme, true))
	bar.add_child(Widgets.spacer())
	bar.add_child(_search_field())
	bar.add_child(_avatar_chip())

## ⌘K 搜索框(对照原型 .fp-input):surface_input 底 + 细描边,点开全局搜索。
func _search_field() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "DesktopSearch"
	box.custom_minimum_size = Vector2(280, 38)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var isb := StyleBoxFlat.new()
	isb.bg_color = Tokens.color(&"surface_input", state.theme)
	isb.set_corner_radius_all(Tokens.RADIUS_SM)
	isb.border_color = Tokens.color(&"border_subtle", state.theme)
	isb.set_border_width_all(1)
	isb.content_margin_left = Tokens.SPACE_4
	isb.content_margin_right = Tokens.SPACE_3
	box.add_theme_stylebox_override("panel", isb)
	var row := Widgets.hbox(Tokens.SPACE_2)
	var mag := Widgets.caption("⌕", state.theme, &"text_muted")
	mag.add_theme_font_size_override("font_size", Tokens.FONT_H4)
	row.add_child(mag)
	var ph := Widgets.caption(String(Strings.t(state.locale, "search")), state.theme, &"text_muted")
	ph.clip_text = true
	ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ph)
	# ⌘K 提示标签(.fp-vtag)
	var tag := PanelContainer.new()
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Tokens.color(&"surface_raised", state.theme)
	tsb.set_corner_radius_all(Tokens.RADIUS_XS)
	tsb.content_margin_left = 6
	tsb.content_margin_right = 6
	tsb.content_margin_top = 2
	tsb.content_margin_bottom = 2
	tag.add_theme_stylebox_override("panel", tsb)
	var tl := Label.new()
	tl.text = "⌘K"
	tl.add_theme_font_size_override("font_size", Tokens.FONT_MONO_SM)
	tl.add_theme_color_override("font_color", Tokens.color(&"text_muted", state.theme))
	tag.add_child(tl)
	row.add_child(tag)
	box.add_child(row)
	box.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			router.go("search"))
	return box

## 头像圆片(对照原型 .fp-avatar):熔炉橙底 + 白字首字母。
func _avatar_chip() -> PanelContainer:
	var av := PanelContainer.new()
	av.name = "AppBarAvatar"
	av.custom_minimum_size = Vector2(34, 34)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var asb := StyleBoxFlat.new()
	asb.bg_color = Tokens.color(&"accent_primary", state.theme)
	asb.set_corner_radius_all(Tokens.RADIUS_PILL)
	av.add_theme_stylebox_override("panel", asb)
	var l := Label.new()
	l.text = String(state.profile.get("name", "@K")).trim_prefix("@").left(1).to_upper()
	l.add_theme_font_size_override("font_size", Tokens.FONT_BODY_SM)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(l)
	av.mouse_filter = Control.MOUSE_FILTER_STOP
	av.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	av.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_go_tab(4))
	return av

## 桌面侧栏(对照原型 .fp-sidebar):宽 240、右侧 1px 分隔线;
## 品牌 logo + 创作 CTA + Browse/Library 两组导航。选中项填 tint_ember 圆角,Activity 带未读角标。
func _render_sidebar(labels: Array) -> void:
	for c in _sidebar.get_children():
		_sidebar.remove_child(c)
		c.queue_free()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"bg_sunken", state.theme)
	sb.set_content_margin_all(Tokens.SPACE_3)
	sb.border_color = Tokens.color(&"border_subtle", state.theme)
	sb.border_width_right = 1
	_sidebar.add_theme_stylebox_override("panel", sb)
	var col := Widgets.vbox(Tokens.SPACE_1)
	col.name = "SidebarItems"
	col.custom_minimum_size = Vector2(216, 0)  # +左右内边距各 12 = 240,对照原型
	# 品牌 logo
	var logo := MarginContainer.new()
	logo.add_theme_constant_override("margin_left", Tokens.SPACE_2)
	logo.add_theme_constant_override("margin_top", Tokens.SPACE_1)
	logo.add_theme_constant_override("margin_bottom", Tokens.SPACE_2)
	logo.add_child(Widgets.brand_logo(state.theme))
	col.add_child(logo)
	# 创作 CTA
	var cta := Widgets.primary_button("%s  %s" % [TAB_GLYPHS[2], Strings.t(state.locale, "side_btn")], state.theme)
	cta.name = "SideForge"
	cta.pressed.connect(func() -> void: _go_tab(2))
	col.add_child(cta)
	# Browse 组:首页 / 发现 / 飙升榜 / 消息。发现=热门榜,飙升榜深链到飙升榜(否则两项都跳发现页、看着一样)。
	col.add_child(_side_head(String(Strings.t(state.locale, "side_browse"))))
	var on_tabs := router.view == Router.VIEW_TABS
	# [glyph, label, callback, active, badge]
	var browse := [
		[TAB_GLYPHS[0], String(labels[0]), (func() -> void: _go_tab(0)), on_tabs and router.tab == 0, 0],
		[TAB_GLYPHS[1], String(labels[1]), (func() -> void: _go_tab(1)), on_tabs and router.tab == 1, 0],
		["↗", String(Strings.t(state.locale, "side_trending")), (func() -> void: router.go("trending")), router.view == "trending", 0],
		[TAB_GLYPHS[3], String(labels[3]), (func() -> void: _go_tab(3)), on_tabs and router.tab == 3, state.unread()],
	]
	for pos in browse.size():
		var entry: Array = browse[pos]
		var item := _side_item(String(entry[0]), String(entry[1]), bool(entry[3]), entry[2], int(entry[4]))
		item.name = "Side%d" % pos
		col.add_child(item)
	# Library 组:我的作品 / 我的二创 / 我喜欢的 / 最近玩过
	col.add_child(_side_head(String(Strings.t(state.locale, "side_library"))))
	var library := [
		["◉", "side_my_games", func() -> void: _open_library("games")],
		["✦", "side_my_forks", func() -> void: _open_library("forks")],
		["♥", "side_liked", func() -> void: _open_library("liked")],
		["◷", "side_recent", func() -> void: router.go("history")],
	]
	for entry: Array in library:
		col.add_child(_side_item(String(entry[0]), String(Strings.t(state.locale, entry[1])),
			false, entry[2], 0))
	_sidebar.add_child(col)

## 侧栏分组标题(对照原型 .fp-side-head):micro 大写、muted,上留白对齐项左内边距。
func _side_head(text: String) -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", Tokens.SPACE_3)
	wrap.add_theme_constant_override("margin_top", Tokens.SPACE_3)
	wrap.add_theme_constant_override("margin_bottom", Tokens.SPACE_1)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	l.add_theme_color_override("font_color", Tokens.color(&"text_muted", state.theme))
	wrap.add_child(l)
	return wrap

## 侧栏导航项(对照原型 .fp-side-item):图标 + 标签,高 38、圆角 sm。
## 图标/标签/角标各自独立、纵向居中(放进一个铺满按钮的行),避免 glyph 和 CJK 同串共基线导致错位。
## 选中:tint_ember 底 + accent 文字;hover:浮起表面。
func _side_item(glyph: String, label: String, active: bool, on_press: Callable, badge_count: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(0, 38)
	var fg: StringName = &"accent_primary" if active else &"text_secondary"
	var base := StyleBoxFlat.new()
	base.set_corner_radius_all(Tokens.RADIUS_SM)
	base.bg_color = Tokens.color(&"tint_ember", state.theme) if active else Color(0, 0, 0, 0)
	var hover := base.duplicate()
	if not active:
		hover.bg_color = Tokens.color(&"surface_raised", state.theme)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(on_press)
	# 内容行:铺满按钮、纵向居中;鼠标事件交给按钮处理
	var row := Widgets.hbox(Tokens.SPACE_2)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = Tokens.SPACE_3
	row.offset_right = -Tokens.SPACE_3
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Label.new()
	ic.text = glyph
	ic.custom_minimum_size = Vector2(20, 0)  # 定宽图标列 → 各项标签左缘对齐
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	ic.add_theme_color_override("font_color", Tokens.color(fg, state.theme))
	row.add_child(ic)
	var lab := Label.new()
	lab.text = label
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	lab.add_theme_color_override("font_color", Tokens.color(fg, state.theme))
	row.add_child(lab)
	if badge_count > 0:
		var dot := Widgets.unread_dot(badge_count, state.theme)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
	b.add_child(row)
	return b

func _go_tab(index: int) -> void:
	if router.view != Router.VIEW_TABS:
		router.view = Router.VIEW_TABS
	router.set_tab(index)
	_sync()

func _pane_title(tab: int) -> String:
	if tab == 4:
		var handle := str(state.profile.get("name", "")).strip_edges()
		return handle if handle != "" else String(Strings.t(state.locale, "tabs")[3])
	var titles: Array = Strings.t(state.locale, "pane_titles")
	if tab >= 0 and tab < titles.size():
		return String(titles[tab])
	return ""

func _request_play(game: Dictionary) -> void:
	var reason := TeenGuardScript.block_reason(state.teen_enabled, TeenGuardScript.local_hour(), state.teen_play_seconds_today())
	if reason != "":
		show_toast(Strings.t(state.locale, reason))
		return
	router.play(game)

func _track_play_session(view: Control) -> void:
	var playing := view == play_view
	if playing and _play_started_ms == 0:
		_play_started_ms = Time.get_ticks_msec()
		return
	if playing or _play_started_ms == 0:
		return
	var elapsed := int((Time.get_ticks_msec() - _play_started_ms) / 1000.0)
	_play_started_ms = 0
	state.add_teen_play_seconds(elapsed)

func _load_teen_prefs() -> void:
	if operations == null or not state.authed or DisplayServer.get_name() == "headless":
		return
	if await operations.load_teen(state.locale):
		state.set_teen_enabled(bool(operations.store.teen.get("default_enabled", false)))

## 侧栏「我的作品/二创/喜欢」→ 各自独立子页。列数随布局。
## 空列表保持空态，等 /users/:id/games 注入后再渲染卡片。
func _open_library(kind: String) -> void:
	var cols := 4 if layout == "desktop" else 3 if layout == "rail" else 2
	var lib := _views["library"]["screen"] as LibraryScreen
	lib.set_collection(kind, cols)
	router.go("library")
	lib.load_collection()

func _subpage_title() -> String:
	match router.view:
		Router.VIEW_DETAIL:
			return GameCard.title_of(router.game, state.locale)
		"creator":
			return (_views["creator"]["screen"] as CreatorScreen).handle
		"library":
			return Strings.t(state.locale, (_views["library"]["screen"] as LibraryScreen).title_key())
		"chat":
			return ""
		"follow":
			return ""
		_:
			if _views.has(router.view) and _views[router.view]["title"] != "":
				return Strings.t(state.locale, _views[router.view]["title"])
	return ""

# ── 视图切换 ────────────────────────────────────────────────
func _sync() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		if not c is ScreenBase:
			c.queue_free()  # rotate/loading 等临时视图即建即弃;屏幕实例常驻复用
	var view: Control
	# 会话门:未登录 → 登录页;未引导 → 引导(对照原型 App 根逻辑)
	if not state.authed:
		view = auth
	elif not state.onboarded:
		view = onboarding
	else:
		match router.view:
			Router.VIEW_TABS:
				view = tab_screens()[router.tab]
			Router.VIEW_ROTATE:
				view = _build_rotate_gate()
			Router.VIEW_LOADING:
				view = _build_loading()
			Router.VIEW_PLAY:
				if play_view.game != router.game:
					play_view.set_game(router.game)
				view = play_view
			Router.VIEW_DETAIL:
				if detail.game != router.game:
					detail.set_game(router.game)
				var detail_id := str(router.game.get("id", ""))
				if operations != null and detail_id != "" and detail_id != _tracked_detail_id:
					_tracked_detail_id = detail_id
					operations.track_event("game_viewed", detail_id)
				view = detail
			_:
				if _views.has(router.view):
					view = _views[router.view]["screen"]
				else:
					push_warning("未注册视图: %s,回落 tabs" % router.view)
					view = tab_screens()[router.tab]
	_content.add_child(view)
	# 屏幕首次展示时拉自己的后端数据(子类覆盖 refresh();默认空操作)
	if view is ScreenBase and is_inside_tree() and DisplayServer.get_name() != "headless" and not (view as ScreenBase)._refreshed:
		(view as ScreenBase)._refreshed = true
		(view as ScreenBase).refresh()
	# 切屏淡入(--dur-med;headless 无帧时跳过,真机生效)
	if is_inside_tree():
		view.modulate.a = 0.0
		var tween := view.create_tween()
		tween.tween_property(view, "modulate:a", 1.0, Tokens.DUR_MED)
	if view == search:
		search.focus_input()
	var gated := view == auth or view == onboarding
	var fullscreen := router.view in [Router.VIEW_PLAY, Router.VIEW_LOADING, Router.VIEW_ROTATE]
	# 显隐按布局形态(docs/16:全屏只留游戏;chrome 随平台切换)
	_tabbar.visible = layout == "phone" and router.view == Router.VIEW_TABS and not gated
	_rail.visible = layout == "rail" and not gated and not fullscreen
	_sidebar.visible = layout == "desktop" and not gated and not fullscreen
	_appbar.visible = not gated and not fullscreen
	_statusbar.visible = layout != "desktop" and not fullscreen
	_render_chrome()
	_track_play_session(view)
	# Prototype auto-update modal is not a shipping updater. Real releases
	# go through store / GitHub; do not block first paint with fake notes.

func _build_rotate_gate() -> Control:
	var card := Widgets.card(state.theme, &"surface_raised")
	var col := Widgets.vbox(Tokens.SPACE_4)
	card.add_child(col)
	col.add_child(Widgets.heading(Strings.t(state.locale, "rotate_title"), 2, state.theme))
	col.add_child(Widgets.body(Strings.fmt(state.locale, "rotate_body",
		[GameCard.title_of(router.game, state.locale)]), state.theme, &"text_secondary"))
	# 真机上由平台转屏信号触发 router.resolve_orientation;此按钮等价于「把设备横过来」
	var go := Widgets.primary_button(Strings.t(state.locale, "play_now"), state.theme)
	go.pressed.connect(router.rotate_and_play)
	col.add_child(go)
	var back := Widgets.secondary_button(Strings.t(state.locale, "back_to_detail"), state.theme)
	back.pressed.connect(router.back)
	col.add_child(back)
	return card

func _build_loading() -> Control:
	var card := Widgets.card(state.theme)
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	col.add_child(Widgets.heading("%s 《%s》…" % [Strings.t(state.locale, "load_hint"),
		GameCard.title_of(router.game, state.locale)], 3, state.theme))
	var bar := ProgressBar.new()
	bar.indeterminate = true
	col.add_child(bar)
	if is_inside_tree():
		get_tree().create_timer(LOADING_SECS).timeout.connect(func() -> void:
			if router.view == Router.VIEW_LOADING:
				router.enter_play())
	return card

# ── Toast / 弹窗 / 横幅 ──────────────────────────────────────
func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	if is_inside_tree():
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if _toast_label.text == text:
				_toast.visible = false)

## Optional "check for updates" dialog. It opens GitHub Releases rather than
## claiming a fake in-app version bump.
func show_update_modal() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	# 遮罩:压暗整屏(含 chrome),拦截背景点击;只能按钮关闭(与原型一致)
	_overlay = PanelContainer.new()
	_overlay.name = "UpdateModal"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := StyleBoxFlat.new()
	scrim.bg_color = Color(Color("#0A0809"), 0.6)
	_overlay.add_theme_stylebox_override("panel", scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	# 定宽对话框(原型 width:300、radius-xl、padding space-6)
	var dialog := PanelContainer.new()
	dialog.custom_minimum_size = Vector2(300, 0)
	var dsb := Widgets.card_style(state.theme, &"surface_raised", Tokens.RADIUS_XL)
	dsb.set_content_margin_all(Tokens.SPACE_6)
	dialog.add_theme_stylebox_override("panel", dsb)
	center.add_child(dialog)
	var col := Widgets.vbox(Tokens.SPACE_4)
	dialog.add_child(col)
	var badge_row := Widgets.hbox(0)
	badge_row.add_child(Widgets.badge("NEW", state.theme, true))
	badge_row.add_child(Widgets.spacer())
	col.add_child(badge_row)
	col.add_child(Widgets.heading(Strings.t(state.locale, "up_title"), 3, state.theme))
	var items := Widgets.vbox(Tokens.SPACE_2)
	for item: String in Strings.t(state.locale, "up_items"):
		items.add_child(Widgets.caption("✓  %s" % item, state.theme, &"text_secondary"))
	col.add_child(items)
	var go := Widgets.primary_button(Strings.t(state.locale, "up_btn"), state.theme)
	go.name = "UpdateButton"
	go.pressed.connect(func() -> void:
		if PlatformBridge.open_url("https://github.com/yldm-tech/classic-games/releases"):
			show_toast(Strings.t(state.locale, "up_toast"));_close_overlay()
		else:show_toast(Strings.t(state.locale,"request_failed")))
	col.add_child(go)
	var later := Widgets.secondary_button(Strings.t(state.locale, "up_later"), state.theme)
	later.name = "LaterButton"
	later.pressed.connect(_close_overlay)
	col.add_child(later)
	add_child(_overlay)

func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		remove_child(_overlay)
		_overlay.queue_free()
		_overlay = null

## Inbox preview banner. Tests may show it; production does not auto-raise it.
func show_push_banner() -> void:
	if _push_shown:
		return
	_push_shown = true
	_push_banner = Widgets.card(state.theme, &"surface_raised")
	_push_banner.name = "PushBanner"
	_push_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_push_banner.position.y = -96
	var row := Widgets.hbox(Tokens.SPACE_2)
	_push_banner.add_child(row)
	var text := Widgets.caption("%s %s · %s" % [Strings.t(state.locale, "push_from"),
		Strings.t(state.locale, "push_text"), Strings.t(state.locale, "push_action")], state.theme)
	row.add_child(text)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(_close_push)
	row.add_child(close)
	_push_banner.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_push()
			router.go("room"))
	add_child(_push_banner)

func _close_push() -> void:
	if _push_banner != null and is_instance_valid(_push_banner):
		remove_child(_push_banner)
		_push_banner.queue_free()
		_push_banner = null

# ── 跨域应用编排 ────────────────────────────────────────────
func _refresh_remote() -> void:
	if not is_inside_tree() or not state.authed:
		return
	var epoch:=_session_epoch
	var engagement_scope:=engagement
	var commerce_scope:=commerce
	var history_loaded:bool=engagement_scope!=null and await engagement_scope.load_history(state.locale)
	if epoch!=_session_epoch or not state.authed:return
	if history_loaded:home.bind_history(engagement_scope.store.history_groups)
	var events_loaded:bool=commerce_scope!=null and await commerce_scope.load_events(state.locale)
	if epoch!=_session_epoch or not state.authed:return
	if events_loaded:home.bind_events(commerce_scope.store.events)
	var live_loaded:bool=engagement_scope!=null and await engagement_scope.load_live(state.locale)
	if epoch!=_session_epoch or not state.authed:return
	if live_loaded:explore.bind_live(engagement_scope.store.live_items)

## 游客直达首页(对照设计稿的游客入口):同步建本地会话并跳过引导墙,首帧直接渲染首页。
## guest token 在 _ready 里由 IdentityCoordinator 补齐。
func _enter_as_guest() -> void:
	state.onboarded = true
	state.login()

func _on_identity_authenticated(_flow: String) -> void:
	if is_inside_tree():
		_refresh_remote()
		_load_teen_prefs()

func _on_feature_changed(feature_store: Variant) -> void:
	if not state.authed:
		return
	if feature_store.status == "offline" and router.view != "offline":
		router.go("offline")

func _retry_offline() -> void:
	var screens: Array[ScreenBase] = [home, explore, profile, detail, messages,
		_views["creator"]["screen"], _views["trending"]["screen"],
		_views["chat"]["screen"], _views["follow"]["screen"], _views["library"]["screen"],
		_views["downloads"]["screen"], _views["history"]["screen"], _views["room"]["screen"], _views["replay"]["screen"],
		_views["points"]["screen"], _views["shop"]["screen"], _views["membership"]["screen"], _views["welfare"]["screen"],
		_views["events"]["screen"], _views["achievements"]["screen"], _views["avatar"]["screen"], _views["earnings"]["screen"],
		_views["report"]["screen"], _views["blocklist"]["screen"], _views["notif"]["screen"], _views["privacy"]["screen"],
		_views["teen"]["screen"], _views["editProfile"]["screen"], _views["account"]["screen"], _views["verify"]["screen"], _views["help"]["screen"], _views["analytics"]["screen"]]
	catalog_retry.retry(screens, search, _refresh_remote)

func invalidate_operations_session()->void:
	for route:String in ["report","blocklist","notif","privacy","teen","editProfile","account","verify","help","analytics"]:
		var screen:Variant=_views.get(route,{}).get("screen")
		if screen is ScreenBase:screen.invalidate_session()

func _on_creator_follow(handle: String, following: bool) -> void:
	if community == null:
		show_toast(Strings.t(state.locale, "request_failed"))
		return
	if await community.set_follow(handle, following):
		_apply_creator_follow(handle, following)

func _apply_creator_follow(handle: String, following: bool) -> void:
	if not _views.has("creator"):
		return
	var creator := _views["creator"]["screen"] as CreatorScreen
	if creator.handle == handle:
		creator.set_following(following)

func _on_operations_action_completed(action:String)->void:
	var key:="report_done_toast" if action=="report" else ("blocked_toast" if action=="block" else "ni_toast")
	show_toast(Strings.t(state.locale,key));router.back()
	if action=="not_interested":_refresh_remote()

## 改一版:服务端游戏走 /mods/:id/fork 出草稿;并切到创作 tab(以该作为基底继续改)。
func _on_fork(game: Dictionary) -> void:
	if creation == null or not game.has("id") or not await creation.fork_game(str(game.id)):
		show_toast(Strings.t(state.locale, "forge_failed")); return
	if operations != null: await operations.track_event("fork_started", str(game.id))
	var child_id := creation.store.draft_id
	var runtime_ref := str(game.get("runtime", creation.store.runtime_ref))
	if child_id == "" or not await creation.load_work({"id":child_id, "status":"draft", "runtime":runtime_ref}):
		show_toast(Strings.t(state.locale, "forge_failed")); return
	if child_id != "" and catalog != null and await catalog.load_mod_lineage(child_id):
		_current_fork_depth = catalog.store.mod_lineage.size() - 1
	show_toast(Strings.t(state.locale, "toast_forked"))
	router.view = Router.VIEW_TABS
	router.set_tab(2)
	_sync()

func _on_generation_completed(prompt: String) -> void:
	router.forged(prompt, str(state.profile.get("id", state.profile.get("name", ""))), str(state.profile.get("tone", "ember")))
	router.game["dsl"] = creation.session.current()

func _load_library_collection(kind:String,lang:String):
	if kind=="liked":
		if not await community.load_favorites():return _store_failure(community.store)
		var favorites:Array=[]
		for game_id:Variant in community.store.favorite_ids:
			if not await catalog.load_game(str(game_id),lang):return _store_failure(catalog.store)
			favorites.append(catalog.store.detail.duplicate(true))
		return ApiResult.success(200,{"items":favorites})
	var collection_type:="works" if kind=="games" else kind
	var user_id:=str(state.profile.get("id",state.profile.get("name","")))
	if not await catalog.load_user_games(user_id,collection_type,lang):return _store_failure(catalog.store)
	return ApiResult.success(200,{"items":catalog.store.profile_games.duplicate(true)})

func _store_failure(feature_store:Variant):
	var kind:=str(feature_store.error_kind)
	if kind=="offline":return ApiResult.offline(str(feature_store.message),str(feature_store.error_code))
	return ApiResult.new(false,kind if kind!="" else "unexpected",0,null,str(feature_store.error_code),str(feature_store.message))

func _update_avatar_profile(profile:Dictionary):
	if await operations.update_profile(profile):return ApiResult.success(200,operations_store.profile.duplicate(true))
	return _store_failure(operations_store)

func _on_app_session_changed()->void:
	_session_epoch+=1
	for transport:HttpClient in _account_http:transport.set_token(str(state.get("token")))
	if not state.authed and not _account_rebuild_pending:
		_account_rebuild_pending=true
		_rebuild_account_scope.call_deferred()

func _local_baseline(runtime_ref:String)->Dictionary:
	var runtime_name:=runtime_ref.split("@")[0]
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://runtime/%s/baseline.dsl.json"%runtime_name))
	return parsed if parsed is Dictionary else {}

func _on_creation_document_imported(document:Dictionary)->void:
	var meta:Variant=document.get("meta",{})
	if not meta is Dictionary:return
	var runtime_ref:="%s@%s"%[str(meta.get("runtime","")),str(meta.get("runtime_version",""))]
	if await creation.import_document(runtime_ref,document):router.go("editor")
