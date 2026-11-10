extends SceneTree

## Shell UI 地基的 headless 自测:tokens 主题/字符串三语/路由状态机/全局状态/各屏结构与交互。
## 运行:godot --headless --path apps/client --script res://shell_ui_test.gd
## 视觉手感(渲染/滚动/IME)需真机,此处只钉「结构与逻辑」(同 spike_test 约定)。

const TokensT := preload("res://shell/design_system/theme/tokens.gd")
const StringsT := preload("res://i18n/strings.gd")
const AppStateScript := preload("res://shell/state/app_state.gd")
const RouterT := preload("res://shell/navigation/router.gd")
const HomeT := preload("res://features/catalog/home_screen.gd")
const ExploreT := preload("res://features/catalog/explore_screen.gd")
const ForgeT := preload("res://features/creation/forge_screen.gd")
const EditorT := preload("res://features/creation/editor_screen.gd")
const StudioT := preload("res://features/creation/studio_screen.gd")
const PublishT := preload("res://features/creation/publish_screen.gd")
const ReviewT := preload("res://features/creation/review_screen.gd")
const CreationStoreT := preload("res://features/creation/creation_store.gd")
const CreationCoordinatorT := preload("res://features/creation/creation_coordinator.gd")
const CreatorSessionAdapterT := preload("res://features/creation/creator_session_adapter.gd")
const ApiResultT := preload("res://core/http/api_result.gd")
const MessagesT := preload("res://features/community/messages_screen.gd")
const ProfileT := preload("res://features/catalog/profile_screen.gd")
const SearchT := preload("res://features/catalog/search_screen.gd")
const CreatorT := preload("res://features/catalog/creator_screen.gd")
const DetailT := preload("res://features/catalog/detail_screen.gd")
const CommunityStoreT := preload("res://features/community/community_store.gd")
const CommunityCoordinatorT := preload("res://features/community/community_coordinator.gd")
const EngagementStoreT := preload("res://features/engagement/engagement_store.gd")
const EngagementCoordinatorT := preload("res://features/engagement/engagement_coordinator.gd")
const EngagementRuntimePortT := preload("res://features/engagement/engagement_runtime_port.gd")
const CommerceStoreT := preload("res://features/commerce/commerce_store.gd")
const CommerceCoordinatorT := preload("res://features/commerce/commerce_coordinator.gd")
const OperationsStoreT:=preload("res://features/operations/operations_store.gd")
const OperationsCoordinatorT:=preload("res://features/operations/operations_coordinator.gd")
const ChatT := preload("res://features/community/chat_screen.gd")
const FollowT := preload("res://features/community/follow_list_screen.gd")
const AddFriendT := preload("res://features/community/add_friend_screen.gd")
const SettingsT := preload("res://app/screens/settings_screen.gd")
const PlayViewT := preload("res://app/screens/play_view.gd")
const AppRootT := preload("res://app/app_root.gd")
const CatalogT := preload("res://app/catalog_seed.gd")
const LibraryT := preload("res://features/engagement/library_screen.gd")
const ScreenRegistryT := preload("res://app/screen_registry.gd")
const TeenGuardT := preload("res://app/teen_guard.gd")

var _passed := 0
var _failed := 0

class FakeIdentityGateway:
	extends RefCounted
	func logout(): return ApiResultT.success(204, null)

class FakeCatalogGateway:
	extends RefCounted
	func user_games(_user_id:String,_kind:String,_lang:String):
		return ApiResultT.success(200,{"items":[]})

class FakeCreationGateway:
	extends RefCounted
	var fail_workspace := false
	func runtime_schema(_name: String, _version: String): return ApiResultT.success(200, {})
	func runtime_baseline(name: String, _version: String):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/%s/baseline.dsl.json" % name))
		return ApiResultT.success(200, parsed)
	func effective_dsl(_id: String):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/shooter/baseline.dsl.json"))
		return ApiResultT.success(200, parsed)
	func fork_mod(_id: String): return ApiResultT.success(201, {"id":"forked-draft"})
	func generate_mod(_runtime: String, dsl: Dictionary, _prompt: String):
		var next := dsl.duplicate(true); next["generated"] = true
		return ApiResultT.success(200, {"dsl_patch": [{"op":"add", "path":"/generated", "value":true}], "new_dsl": next})
	func validate_dsl(_runtime: String, _dsl: Dictionary): return ApiResultT.success(200, {"valid": true})
	func auto_balance(_runtime: String, dsl: Dictionary, _difficulty: int):
		return ApiResultT.success(200, {"dsl_patch": [{"op":"add", "path":"/balanced", "value":true}], "new_dsl": dsl.merged({"balanced":true}, true)})
	func generate_structure(_runtime: String, dsl: Dictionary, _prompt: String, _count: int, _difficulty: int):
		return ApiResultT.success(200, {"dsl_patch": [{"op":"add", "path":"/structured", "value":true}], "new_dsl": dsl.merged({"structured":true}, true)})
	func save_draft(_runtime: String, _parent: String, _patch: Array, _proof: String): return ApiResultT.success(201, {"id":"draft-1"})
	func update_draft(_id: String, _patch: Array): return ApiResultT.success(201, {"id":"draft-2"})
	func publish_draft(_id: String, _title: String, _summary: String, _tags: Array): return ApiResultT.success(201, {"id":"game-draft", "status":"reviewing"})
	func create_mod(_runtime: String, _parent: String, _patch: Array, _proof: String): return ApiResultT.success(201, {"id":"mod-1"})
	func publish_game(_mod: String, _title: String, _category: String): return ApiResultT.success(201, {"id":"game-1", "status":"reviewing"})
	func delist_game(_id: String): return ApiResultT.success(200, {"status":"delisted"})
	func resubmit_game(_id: String): return ApiResultT.success(200, {"status":"reviewing"})
	func my_games(_lang: String):
		return ApiResultT.offline("workspace failed") if fail_workspace else ApiResultT.success(200, {"items":[]})
	func drafts(): return ApiResultT.success(200, {"items":[]})
	func my_mods(): return ApiResultT.success(200, {"items":[]})
	func moderation_queue(_cursor: String = "", _limit: int = 20): return ApiResultT.success(200, {"items": []})
	func decide_game(_id: String, approve: bool): return ApiResultT.success(200, {"status": "published" if approve else "rejected"})

class FakeCommunityGateway:
	extends RefCounted
	func list_comments(_id:String): return ApiResultT.success(200, {"items":[]})
	func add_comment(_id:String, text:String): return ApiResultT.success(201, {"content":text})
	func community(_id:String): return ApiResultT.success(200, {"my_rating":0,"count":0,"average":0.0,"posts":[]})
	func rate_game(_id:String, value:int): return ApiResultT.success(200, {"my_rating":value,"count":1,"average":float(value)})
	func create_post(_id:String, text:String): return ApiResultT.success(201, {"content":text})
	func set_like(_id:String, liked:bool): return ApiResultT.success(200, {"liked":liked})
	func set_favorite(_id:String, _favorite:bool): return ApiResultT.success(200, {})
	func favorites(): return ApiResultT.success(200, {"items":[]})
	func activity(_lang:String): return ApiResultT.success(200, {"items":[]})
	func conversations(_lang:String): return ApiResultT.success(200, {"items":[]})
	func conversation_messages(_handle:String): return ApiResultT.success(200, {"items":[]})
	func send_message(_handle:String, text:String): return ApiResultT.success(201, {"items":[{"text":text,"mine":true}]})
	func set_follow(_handle:String, following:bool): return ApiResultT.success(200, {"following":following})
	func add_friend(handle:String): return ApiResultT.success(201, {"handle":handle})
	func follow(_kind:String, _lang:String): return ApiResultT.success(200, {"items":[]})
	func friend_suggestions(_lang:String): return ApiResultT.success(200, {"items":[]})
	func following(_id:String): return ApiResultT.success(200, {"items":[]})

class FakeEngagementGateway:
	extends RefCounted
	func downloads(_lang:String): return ApiResultT.success(200, {"items":[]})
	func history(_lang:String): return ApiResultT.success(200, {"groups":[]})
	func update_download(_id:String): return ApiResultT.success(200, {})
	func remove_download(_id:String): return ApiResultT.success(200, {})
	func clear_history(): return ApiResultT.success(200, {})
	func live(_lang:String): return ApiResultT.success(200, {"items":[]})
	func send_live_gift(_id:String): return ApiResultT.success(200, {"balance":0})
	func create_room(): return ApiResultT.success(201, {"id":"room","members":[]})
	func join_room(code:String): return ApiResultT.success(200, {"id":code,"members":[]})
	func get_room(id:String): return ApiResultT.success(200, {"id":id,"members":[]})
	func set_room_ready(id:String,_ready:bool): return ApiResultT.success(200, {"id":id,"members":[]})
	func start_room(id:String): return ApiResultT.success(200, {"id":id,"status":"started","members":[]})
	func replay(_game:String,_user:String): return ApiResultT.success(200, {"duration_ms":0,"frames":[]})
	func replay_leaderboard(_game:String): return ApiResultT.success(200, {"items":[]})
	func record_play(_game:String,_duration:int): return ApiResultT.success(201, {})
	func submit_replay(_game:String,_duration:int,_frames:Array): return ApiResultT.success(201, {})
	func room_snapshot(id:String): return ApiResultT.success(200, {"room_id":id,"tick":1,"players":[]})
	func submit_room_input(id:String,seq:int,_x:float,_y:float,_fire:bool): return ApiResultT.success(200, {"room_id":id,"tick":seq,"players":[]})

class FakeCommerceGateway:
	extends RefCounted
	func points(): return ApiResultT.success(200,{"balance":0,"ledger":[],"earnings":{}})
	func shop(_lang:String): return ApiResultT.success(200,{})
	func membership(_lang:String): return ApiResultT.success(200,{})
	func welfare(_lang:String): return ApiResultT.success(200,{"quests":[]})
	func events(_lang:String): return ApiResultT.success(200,{"items":[]})
	func joined_events(): return ApiResultT.success(200,{"event_ids":[]})
	func achievements(_lang:String): return ApiResultT.success(200,{"items":[]})
	func avatar_catalog(_lang:String): return ApiResultT.success(200,{"items":[]})
	func request_withdrawal(amount:int): return ApiResultT.success(202,{"id":"w1","amount":amount,"status":"pending"})
	func withdrawals(): return ApiResultT.success(200,{"items":[]})
	func create_payment_order(product_id:String): return ApiResultT.success(201,{"id":"o1","product_id":product_id,"status":"pending"})
	func payment_orders(): return ApiResultT.success(200,{"items":[]})
	func payment_order(id:String): return ApiResultT.success(200,{"id":id,"status":"pending"})

class FakeOperationsGateway:
	extends RefCounted
	var calls:Dictionary={}
	var report_gate:SignalGate
	var unblock_gates:Dictionary={}
	var delete_gate:SignalGate
	var delete_result=ApiResultT.success(204,null)
	func report(_type:String,_id:String,reason:String):
		calls["report"]=reason
		if report_gate!=null:await report_gate.released
		return ApiResultT.success(201,{})
	func not_interested(id:String):calls["not_interested"]=id;return ApiResultT.success(200,{})
	func block_user(id:String):calls["block"]=id;return ApiResultT.success(201,{})
	func unblock_user(id:String):
		calls["unblock:"+id]=true
		if unblock_gates.has(id):await (unblock_gates[id] as SignalGate).released
		return ApiResultT.success(204,null)
	func delete_account():
		calls["delete_account"]=int(calls.get("delete_account",0))+1
		if delete_gate!=null:await delete_gate.released
		return delete_result
	func track_event(name:String,_session:String,_target:String,_depth:int):calls["event"]=name;return ApiResultT.success(202,{})
	func security(): return ApiResultT.success(200, {"phone_masked":"", "password_set":false, "providers":[]})
	func verification_status(): return ApiResultT.success(200, {"status":"not_submitted"})
	func verification_queue(): return ApiResultT.success(200, {"items":[]})
	func decide_verification(_id:String,_approve:bool): return ApiResultT.success(200, {"status":"verified"})
	func analytics_summary(): return ApiResultT.success(200, {"fork_conversion":0.4,"ai_publish_rate":0.2,"max_fork_depth":2,"game_viewers":10,"fork_starters":4,"ai_editors":3,"ai_publishers":1})
	func public_meta(): return ApiResultT.success(200, {"environment":"development","ai":{"mode":"stub"},"sms":false,"oauth_providers":[],"payments":false,"admin_configured":false})

class SignalGate:
	extends RefCounted
	signal released

func _initialize() -> void:
	_test_tokens()
	_test_strings()
	_test_router()
	_test_app_state()
	_test_screens()
	await _test_account_screens()
	await _test_creator_screens()
	await _test_social_screens()
	_test_commerce_screens()
	await _test_library_screens()
	await _test_app_root()

	print("shell_ui_test: %d passed, %d failed" % [_passed, _failed])
	var exit_code := 0 if _failed == 0 else 1
	_finish.call_deferred(exit_code)

func _finish(exit_code: int) -> void:
	# rebuild() 产生的 queue_free 节点先走完删除队列，再释放仍挂树的测试节点。
	await process_frame
	for child in root.get_children(): child.queue_free()
	await process_frame
	await process_frame
	quit(exit_code)

func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)

# ── A. 设计 token ───────────────────────────────────────────
func _test_tokens() -> void:
	_check("A 品牌主色 ember", TokensT.color(&"accent_primary") == Color("#FF4D1A"))
	_check("A AI 强调色 volt", TokensT.color(&"accent_ai") == Color("#C8FF3D"))
	_check("A 深浅主题背景不同", TokensT.color(&"bg_app", "dark") != TokensT.color(&"bg_app", "light"))
	_check("A 浅色主题主色加深(对比度)", TokensT.color(&"accent_primary", "light") == Color("#E83A0B"))

# ── B. 三语字符串 ────────────────────────────────────────────
func _test_strings() -> void:
	_check("B zh tab", StringsT.t("zh", "tabs")[0] == "首页")
	_check("B en tab", StringsT.t("en", "tabs")[0] == "Home")
	_check("B ja tab", StringsT.t("ja", "tabs")[0] == "ホーム")
	_check("B 游戏名本地化", StringsT.game_title("zh", "ashfall") == "灰烬王国"
		and StringsT.game_title("en", "ashfall") == "Ashfall Kingdom")
	_check("B 格式化文案", StringsT.fmt("zh", "forks_this_week", ["2100"]) == "本周 2100人二创")
	_check("B 未知 locale 回落 zh", StringsT.t("fr", "tabs")[0] == "首页")
	# 三语 key 集合一致(防补文案漏语言)
	var zh_keys: Array = StringsT.TABLE["zh"].keys()
	var same := true
	for loc in ["en", "ja"]:
		for k in zh_keys:
			if not StringsT.TABLE[loc].has(k):
				same = false
				push_error("缺 %s/%s" % [loc, k])
	_check("B 三语 key 对齐", same)

# ── C. 路由状态机(对照原型 useNav 语义) ─────────────────────
func _test_router() -> void:
	var r: Router = RouterT.new()
	_check("C 初始在 tabs", r.view == Router.VIEW_TABS and r.tab == 0)
	r.open_game(CatalogT.GAMES[0])
	_check("C 打开详情", r.view == Router.VIEW_DETAIL and r.game["id"] == "ember")
	# 手机竖屏开玩 → 横屏闸门 → 转屏 → 加载 → 游玩 → 退出回详情
	r.play(CatalogT.GAMES[0])
	_check("C 竖屏先闸门", r.view == Router.VIEW_ROTATE)
	r.rotate_and_play()
	_check("C 转屏进加载", r.view == Router.VIEW_LOADING and not r.is_portrait)
	r.enter_play()
	_check("C 进入游玩", r.view == Router.VIEW_PLAY)
	r.exit_play()
	_check("C 退出回详情", r.view == Router.VIEW_DETAIL)
	r.back()
	_check("C 详情返回 tabs", r.view == Router.VIEW_TABS and r.depth() == 0)
	# 桌面端直接进加载,无闸门
	var d: Router = RouterT.new()
	d.is_phone = false
	d.play(CatalogT.GAMES[1])
	_check("C 桌面跳过闸门", d.view == Router.VIEW_LOADING)
	# 闸门挂着时物理转屏 → 直接放行
	var p: Router = RouterT.new()
	p.play(CatalogT.GAMES[0])
	p.resolve_orientation(false)
	_check("C 物理转屏放行", p.view == Router.VIEW_PLAY)
	# 生成完成 → 以 AI 新作打开详情
	var f: Router = RouterT.new()
	f.forged("熔岩冲浪", "@real-user", "cyan")
	_check("C forged 进详情", f.view == Router.VIEW_DETAIL and f.game["id"] == "forged"
		and f.game["badge"] == "ai")
	_check("C forged 作者/调性取真实身份,不是演示账号", f.game["by"] == "@real-user" and f.game["tone"] == "cyan")

# ── D. 全局状态 ─────────────────────────────────────────────
func _test_app_state() -> void:
	var state: Node = AppStateScript.new()
	root.add_child(state)
	var bus := {"theme": "", "locale": "", "unread": -1}
	state.theme_changed.connect(func(t: String) -> void: bus["theme"] = t)
	state.locale_changed.connect(func(l: String) -> void: bus["locale"] = l)
	state.unread_changed.connect(func(n: int) -> void: bus["unread"] = n)
	state.set_theme("light")
	_check("D 主题切换 + 信号", state.theme == "light" and bus["theme"] == "light")
	state.set_theme("nope")
	_check("D 非法主题被拒", state.theme == "light")
	state.set_locale("ja")
	_check("D 语言切换 + 信号", state.locale == "ja" and bus["locale"] == "ja")
	_check("D 无权威通知时初始未读为零", state.unread() == 0)
	state.mark_read(0)
	state.mark_read(0)  # 幂等
	_check("D 不记录越界通知已读", state.unread() == 0 and not state.is_read(0))
	state.queue_free()
	var prefs: Node = AppStateScript.new()
	prefs.save_path = "user://classic_games_prefs_test.cfg"
	root.add_child(prefs)
	prefs.set_theme("light")
	prefs.set_locale("en")
	prefs.remember_search("volt")
	prefs.remember_search("ember")
	prefs.remember_search("volt")
	var restored: Node = AppStateScript.new()
	root.add_child(restored)
	restored.save_path = prefs.save_path
	restored.restore()
	_check("D 主题语言与最近搜索持久化", restored.theme == "light" and restored.locale == "en"
		and restored.search_recents == ["volt", "ember"])
	prefs.set_teen_enabled(true)
	prefs.add_teen_play_seconds(90)
	var teen_restored: Node = AppStateScript.new()
	root.add_child(teen_restored)
	teen_restored.save_path = prefs.save_path
	teen_restored.restore()
	_check("D 青少年开关与当日时长持久化", teen_restored.teen_enabled and teen_restored.teen_play_seconds_today() >= 90)
	teen_restored.queue_free()
	restored.queue_free()
	prefs.queue_free()

func _new_state() -> Node:
	var s: Node = AppStateScript.new()
	s.save_path = "user://classic_games_test.cfg"  # 不污染真实存档
	root.add_child(s)
	return s

func _new_creation() -> Dictionary:
	var store = CreationStoreT.new()
	var session = CreatorSessionAdapterT.new()
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/shooter/baseline.dsl.json"))
	session.load_baseline("shooter@1.0.0", baseline)
	store.runtime_ref = "shooter@1.0.0"
	store.baseline = baseline.duplicate(true)
	var gateway := FakeCreationGateway.new()
	var coordinator = CreationCoordinatorT.new(gateway, store, session)
	root.add_child(store); root.add_child(coordinator)
	return {"gateway":gateway, "store":store, "session":session, "coordinator":coordinator}

func _new_community() -> Dictionary:
	var store = CommunityStoreT.new()
	var coordinator = CommunityCoordinatorT.new(FakeCommunityGateway.new(), store)
	root.add_child(store); root.add_child(coordinator)
	return {"store":store, "coordinator":coordinator}

func _click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)

# ── E. 各屏结构与交互 ────────────────────────────────────────
func _test_screens() -> void:
	var state := _new_state()
	var creation := _new_creation()

	# 首页:精选 hero 本地化、热门二创 4 卡、查看全部信号
	var home: HomeScreen = HomeT.new(state)
	root.add_child(home)
	_check("E 首页无 API 不展示假运营内容", home.find_child("HomeEmpty", true, false) != null)
	var home_empty_nav := {}
	home.explore_requested.connect(func() -> void: home_empty_nav["go"] = true)
	var home_cta := home.find_child("HomeEmpty", true, false).find_child("RetryButton", true, false) as Button
	if home_cta != null:
		home_cta.pressed.emit()
	_check("E 首页空态可去发现", home_empty_nav.get("go", false))
	home.bind_games([{"id":"real_home", "title":"真实首页游戏", "by":"@real"}])
	home.bind_trending([{"id":"real_home", "title":"真实首页游戏", "by":"@real"}])
	_check("E 首页展示注入的权威游戏", home.find_child("HeroTitle", true, false).text == "真实首页游戏"
		and home.find_child("TrendingGrid", true, false).get_child_count() == 1)
	home.show_skeleton()
	_check("E 首载骨架屏", home.find_child("SkeletonBlocks", true, false) != null)
	home.finish_loading()
	_check("E 骨架换内容", home.find_child("SkeletonBlocks", true, false) == null
		and home.find_child("HeroTitle", true, false) != null)
	var picked := {}
	home.explore_requested.connect(func() -> void: picked["explore"] = true)
	(home.find_child("SeeAll", true, false) as Button).pressed.emit()
	_check("E 查看全部→发现", picked.get("explore", false))

	# 发现:榜单 5 行、分类筛选、AI 过滤、服务端数据注入
	var explore: ExploreScreen = ExploreT.new(state)
	root.add_child(explore)
	_check("E 发现无 API 不展示假榜单", explore.find_child("RankList", true, false).get_child_count() == 1)
	_check("E 发现无 API 不展示假游戏", explore.find_child("EmptyNote", true, false) != null)
	explore._ai_only = true
	explore.rebuild()
	_check("E 空列表 AI 过滤仍为空", explore.find_child("EmptyNote", true, false) != null)
	explore._ai_only = false
	explore._cat = "Racing"
	explore.rebuild()
	_check("E 空列表分类仍为空", explore.find_child("EmptyNote", true, false) != null)
	explore._cat = "All"
	explore.bind_games([{"id": "srv1", "title": "服务端游戏", "author_id": "@u1", "likes": 3, "ai_generated": true}])
	_check("E 注入服务端列表", explore.find_child("GamesGrid", true, false).get_child_count() == 1)
	explore.bind_ranking(0, [{"id": "srv1", "title": "服务端游戏", "author_id": "@u1", "likes": 3, "rank": 1}])
	_check("E 注入服务端榜单", explore.find_child("RankList", true, false).get_child_count() == 1)
	_check("E 正在直播无 API 不展示假直播", explore.find_child("LiveRow", true, false).get_child_count() == 1)

	# 创作:默认 prompt、chip 追加、生成信号与分步进度
	var forge: ForgeScreen = ForgeT.new(state, creation.coordinator)
	root.add_child(forge)
	var prompt: TextEdit = forge.find_child("PromptEdit", true, false)
	var runtime_selector := forge.find_child("RuntimeSelector", true, false) as OptionButton
	_check("D 创作页可选择三种 Runtime", runtime_selector != null and runtime_selector.item_count == 3)
	if runtime_selector != null:
		runtime_selector.select(1); runtime_selector.item_selected.emit(1)
		_check("D 创作页 Runtime 选择生效", forge.runtime_ref == "survivor@1.0.0")
	_check("E 默认中文 prompt", prompt.text == "一个熔岩冲浪竞速,赛道会在身后慢慢熔掉")
	var chips := forge.find_child("PromptChips", true, false)
	(chips.get_child(1) as Button).pressed.emit()
	_check("E chip 追加", forge.current_prompt().ends_with(",Boss 战"))
	var forged := {}
	forge.generation_completed.connect(func(p: String) -> void: forged["prompt"] = p)
	(forge.find_child("ForgeButton", true, false) as Button).pressed.emit()
	_check("E 生成请求信号", forged.has("prompt"))
	forge.set_step(2)
	_check("E 生成进度展示", forge.find_child("ForgeProgress", true, false) != null)
	forge.set_step(-1)
	_check("E 进度复位", forge.find_child("ForgeProgress", true, false) == null)
	_check("E 创作中心入口", forge.find_child("StudioEntry", true, false) != null)
	_check("E 无热门数据时改一版区块空态,不回退种子游戏", forge.find_child("RemixList", true, false).find_child("EmptyNote", true, false) != null)
	forge.bind_trending([{"id": "real-hot-1"}, {"id": "real-hot-2"}])
	_check("E 改一版区块取真实热门数据", forge.find_child("RemixList", true, false).get_child_count() == 2)
	# prompt 未编辑 → 随语言切换换默认灵感;编辑过(上面 chip 追加过)→ 保留
	var forge2: ForgeScreen = ForgeT.new(state, creation.coordinator)
	root.add_child(forge2)
	state.set_locale("en")
	_check("E prompt 随语言切换", forge2.current_prompt() == "a lava-surfing racer where the track melts behind you")
	_check("E 编辑过的 prompt 保留", forge.current_prompt().ends_with("Boss 战"))
	state.set_locale("zh")

	# 消息:通知/私信/好友三段
	var messages: MessagesScreen = MessagesT.new(state)
	root.add_child(messages)
	var list := messages.find_child("ActivityList", true, false)
	_check("E 无 API 不展示假通知", list.get_child_count() == 1 and list.get_child(0).name == "EmptyNote")
	_check("E 通知空态不伪造未读数", state.unread() == 0)
	messages.seg = 1
	messages.rebuild()
	_check("E 私信无 API 不展示假会话", messages.find_child("ChatList", true, false).get_child_count() == 1
		and messages.find_child("EmptyNote", true, false) != null)
	messages.seg = 2
	messages.rebuild()
	_check("E 好友页不展示假请求和推荐", messages.find_child("RequestList", true, false).get_child_count() == 1
		and messages.find_child("SugList", true, false).get_child_count() == 1)
	var chat_nav := {}
	messages.add_friend_requested.connect(func() -> void: chat_nav["add"] = true)
	(messages.find_child("AddFriendButton", true, false) as Button).pressed.emit()
	_check("E 加好友入口", chat_nav.get("add", false))

	# 我的:身份卡、三段作品切换、设置入口
	var profile: ProfileScreen = ProfileT.new(state)
	root.add_child(profile)
	_check("E 身份卡昵称", profile.find_child("ProfileName", true, false).text == "@guest")
	_check("E 我的作品无 API 不展示假卡", profile.find_child("WorksGrid", true, false).get_child_count() == 1)
	profile._seg = 2
	profile.rebuild()
	_check("E 我的喜欢无 API 不展示假卡", profile.find_child("WorksGrid", true, false).get_child_count() == 1)
	var nav := {}
	profile.settings_requested.connect(func() -> void: nav["settings"] = true)
	_click(profile.find_child("SettingsRow", true, false))
	_check("E 设置入口", nav.get("settings", false))
	profile.entry_selected.connect(func(k: String) -> void: nav["entry"] = k)
	_click(profile.find_child("Entry_shop", true, false))
	_check("E 目录分组入口(商城)", nav.get("entry", "") == "shop")

	# 详情:标题/简介本地化、开玩信号、评论注入
	var detail: DetailScreen = DetailT.new(state)
	root.add_child(detail)
	detail.set_game(CatalogT.GAMES[0])
	_check("E 详情标题", detail.find_child("DetailTitle", true, false).text == "余烬漂移")
	var played := {}
	detail.play_requested.connect(func(g: Dictionary) -> void: played["id"] = g["id"])
	(detail.find_child("PlayButton", true, false) as Button).pressed.emit()
	_check("E 详情开玩信号", played.get("id", "") == "ember")
	_check("E 未声明 runtime 的摘要保留改一版", detail.find_child("ForkButton", true, false) != null)
	detail.set_game({"id": "ember", "title": "余烬漂移", "mod_id": "", "runtime": ""})
	_check("E 无 mod 的展示作品不提供改一版", detail.find_child("ForkButton", true, false) == null and detail.find_child("PlayButton", true, false) != null)
	var forked := {}
	detail.fork_requested.connect(func(g: Dictionary) -> void: forked["id"] = g["id"])
	detail.set_game({"id": "game_real", "title": "真实作品", "mod_id": "mod_real", "runtime": "shooter@1.0.0"})
	(detail.find_child("ForkButton", true, false) as Button).pressed.emit()
	_check("E 有 mod 的作品可改一版", forked.get("id", "") == "game_real")
	detail.set_game(CatalogT.GAMES[0])
	detail._tab = 1
	detail.rebuild()
	_check("E 评论无 API 不展示假评论", detail.find_child("CommentList", true, false).get_child_count() == 1)
	(detail.find_child("CommentEdit", true, false) as LineEdit).text = "手感真顺"
	(detail.find_child("CommentSend", true, false) as Button).pressed.emit()
	_check("E 评论无 API 不伪回显", detail.find_child("CommentList", true, false).get_child_count() == 1)
	detail.bind_comments([{"author_id": "@mei", "content": "好玩"}, {"author_id": "@bo", "content": "再改改"}])
	_check("E 评论注入覆盖回显", detail.find_child("CommentList", true, false).get_child_count() == 2)
	(detail.find_child("LikeButton", true, false) as Button).pressed.emit()
	_check("E 点赞无 API 不伪切换", not detail._liked)
	detail._tab = 2
	detail.rebuild()
	_check("E 排行无 API 不展示假分数", detail.find_child("ScoreList", true, false).get_child_count() == 1)
	var rep := {}
	detail.replay_requested.connect(func(uid:String,h: String, _g: Dictionary) -> void: rep["uid"] = uid;rep["h"] = h)
	_check("E 种子榜不提供查不中的假回放",detail.find_child("ReplayButton0",true,false)==null)
	detail._leaderboard=[{"user_id":"user_real","nickname":"Alice","score":42,"rank":1}];detail.rebuild()
	(detail.find_child("ReplayButton0",true,false) as Button).pressed.emit()
	_check("E 回放入口携带权威用户 ID",rep.get("uid","")=="user_real"&&rep.get("h","")=="Alice")
	state.profile["id"] = "user_real"
	detail.rebuild()
	_check("E 排行按 user_id 高亮自己", detail.find_child("ReplayButton0", true, false) == null)
	state.profile.erase("id")
	detail._tab = 3
	detail.rebuild()
	_check("E 圈子无 API 不展示假热帖", detail.find_child("PostList", true, false).get_child_count() == 1)
	(detail.find_child("PostEdit", true, false) as LineEdit).text = "顶一下"
	(detail.find_child("PostButton", true, false) as Button).pressed.emit()
	_check("E 圈子无 API 不伪造发帖", detail.find_child("PostList", true, false).get_child_count() == 1)
	var shared := {}
	detail.share_requested.connect(func(_g: Dictionary) -> void: shared["s"] = true)
	detail.more_requested.connect(func(_g: Dictionary) -> void: shared["m"] = true)
	(detail.find_child("ShareButton", true, false) as Button).pressed.emit()
	(detail.find_child("MoreButton", true, false) as Button).pressed.emit()
	_check("E 分享/更多入口", shared.get("s", false) and shared.get("m", false))
	detail._tab = 0
	detail.rebuild()
	var stars := detail.find_child("StarRow", true, false)
	_check("E 评分 5 星", stars != null and stars.get_child_count() == 5)
	(stars.get_child(3) as Button).pressed.emit()
	_check("E 评分无 API 不伪造成功", detail._rating == 0)
	_check("E 创作链无 API 不展示假谱系", detail.find_child("LineageChain", true, false) == null)
	(detail.find_child("FavoriteButton", true, false) as Button).pressed.emit()
	_check("E 收藏无 API 不伪切换", not detail._favorited)

	# 设置:语言/外观真开关、退出登录
	var settings: SettingsScreen = SettingsT.new(state)
	root.add_child(settings)
	(settings.find_child("ThemeSeg", true, false).get_child(1) as Button).pressed.emit()
	_check("E 外观开关切浅色", state.theme == "light")
	(settings.find_child("LangSeg", true, false).get_child(1) as Button).pressed.emit()
	_check("E 语言开关切 EN", state.locale == "en")
	state.login()
	(settings.find_child("LogoutButton", true, false) as Button).pressed.emit()
	_check("E 退出登录", not state.authed)
	_check("E 设置有分析入口", settings.find_child("AnalyticsRow", true, false) != null)
	state.set_theme("dark")
	state.set_locale("zh")

	# 游玩 HUD:计分实跳、加速翻倍、结算
	var play: PlayView = PlayViewT.new(state)
	root.add_child(play)
	play.set_game(CatalogT.GAMES[0])
	play._runtime.set_meta("score", 700)
	play._sync_runtime_hud()
	_check("E Shooter HUD 优先读取实时分数", play.play.score == 700)
	play._runtime.set_meta("score", 0)
	_check("E 游玩页挂载真实 Runtime", play.find_child("RuntimeViewport", true, false) is SubViewportContainer
		and play._runtime.has_node("Player/Weapon"))
	var survivor_dsl: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/survivor/baseline.dsl.json"))
	play.set_game({"id":"survivor-test","runtime":"survivor@1.0.0","dsl":survivor_dsl})
	_check("E 游玩入口按 runtime 构建 Survivor", play._runtime != null and play._runtime.name == "SurvivorRuntime")
	_check("E Survivor 不显示 Shooter 专属控件", play.find_child("BoostButton", true, false) == null and play.find_child("LapBar", true, false) == null)
	_check("E Survivor HUD 显示生命/等级", play.find_child("RuntimeStatus", true, false) != null and "生命" in (play.find_child("RuntimeStatus", true, false) as Label).text)
	_check("E Survivor 有本机触控方向", play.find_child("LocalLeftButton", true, false) != null)
	(play.find_child("LocalRightButton", true, false) as Button).button_down.emit()
	_check("E Survivor 触控写入 Runtime", play._runtime.get_meta("touch_move") == Vector2.RIGHT)
	play._sample_replay()
	var sampled_hero := play._runtime.get_node("Hero") as Node2D
	_check("E Survivor 回放采样 Hero", play._replay_frames.size() == 1 and float(play._replay_frames[0]["x"]) == sampled_hero.position.x)
	play._runtime.set_meta("summary", {"runtime":"survivor","score":40,"cleared":true,"defeated":false})
	play._process(0.1)
	_check("E Survivor 通用结算保留 Runtime 结果", play._phase == "result" and play._result.get("cleared", false) and play._result.get("score", 0) == 40)
	_check("E Survivor 结算显示通关", play.find_child("ResultOutcome", true, false) != null)
	play.set_game(CatalogT.GAMES[0])
	play._process(0.11)
	var sampled_player := play._runtime.get_node("Player") as Node2D
	_check("E 回放采样真实坐标", play._replay_frames.size() == 1
		and float(play._replay_frames[0]["x"]) == sampled_player.position.x
		and int(play._replay_frames[0]["at_ms"]) >= 100)
	sampled_player.take_damage(17)
	play._sync_runtime_hud()
	_check("E HUD/回放生命取 Runtime 真值",play.play.hp==83)
	_check("E Shooter HUD 显示真实生命", play.find_child("RuntimeStatus", true, false) != null and "83" in (play.find_child("RuntimeStatus", true, false) as Label).text)
	_check("E Shooter 有本机触控方向", play.find_child("LocalLeftButton", true, false) != null)
	(play.find_child("PauseButton", true, false) as Button).pressed.emit()
	_check("E 暂停显示运行时状态", play.find_child("PauseStatus", true, false) != null and "生命" in (play.find_child("PauseStatus", true, false) as Label).text)
	_check("E 暂停菜单保留从这里改一版", play.find_child("ForkHereButton", true, false) != null)
	play.game = {"id": "ember", "mod_id": "", "runtime": ""}
	play.rebuild()
	_check("E 无 mod 的展示作品暂停菜单不提供改一版", play.find_child("ForkHereButton", true, false) == null and play.find_child("ResumeButton", true, false) != null)
	play.game = CatalogT.GAMES[0]
	play.rebuild()
	(play.find_child("ResumeButton", true, false) as Button).pressed.emit()
	play.simulate(1.0)  # 2 次击杀 × 100
	_check("E 计分实跳", play.play.score == 200)
	(play.find_child("BoostButton", true, false) as Button).button_down.emit()
	play.simulate(0.5)  # 加速翻倍 +200
	_check("E 按住加速翻倍", play.play.score == 400)
	play.finish_run()
	_check("E 结算页", play.find_child("ResultCard", true, false) != null
		and play.find_child("ResultScore", true, false).text == "400")
	# 圈数推进 + 跑满 3 圈自动结算(每圈 10 杀)
	play.set_game(CatalogT.GAMES[0])
	_check("E 初始第 1 圈", play.lap() == 1 and play.find_child("LapBar", true, false) != null)
	play.simulate(7.5)  # 15 杀 → 第 2 圈
	_check("E 圈数推进", play.lap() == 2)
	play.simulate(7.5)  # 累计 30 杀 → 跑满自动结算
	_check("E 跑满自动结算", play.find_child("ResultCard", true, false) != null)
	state.profile["id"] = "host"
	play.set_game({"id":"network-test", "runtime":"shooter@1.0.0", "network_room_id":"room_test"})
	_check("E 联机房间加载权威 Runtime", play._runtime != null and play._runtime.name == "NetworkMatchRuntime")
	_check("E 联机 HUD 有移动/射击触控", play.find_child("NetworkLeftButton", true, false) != null and play.find_child("NetworkFireButton", true, false) != null)
	_check("E 联机局不能客户端自行结算", play.find_child("FinishButton", true, false) == null)
	_check("E 联机 HUD 不用本机方向键", play.find_child("LocalLeftButton", true, false) == null)
	var td_dsl: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/tower_defense/baseline.dsl.json"))
	play.set_game({"id":"td-test","runtime":"tower_defense@1.0.0","dsl":td_dsl})
	_check("E 塔防 HUD 显示金币与基地", play.find_child("RuntimeStatus", true, false) != null and "金币" in (play.find_child("RuntimeStatus", true, false) as Label).text and "基地" in (play.find_child("RuntimeStatus", true, false) as Label).text)
	_check("E 塔防 HUD 显示波次", "波次" in (play.find_child("RuntimeStatus", true, false) as Label).text)
	_check("E 塔防有建造栏无方向键", play.find_child("TowerBuildRow", true, false) != null and play.find_child("LocalLeftButton", true, false) == null)

# ── G1. 入口/账号集群 ───────────────────────────────────────
func _test_account_screens() -> void:
	var state := _new_state()

	var auth := AuthScreen.new(state)
	root.add_child(auth)
	_check("G 登录页品牌 logo", auth.find_child("BrandLogo", true, false) != null)
	_check("G 登录页 slogan", auth.find_child("Slogan", true, false).text == "人人都能做游戏")
	(auth.find_child("PhoneEdit", true, false) as LineEdit).text = "13812342380"
	(auth.find_child("CodeEdit", true, false) as LineEdit).text = "246810"
	(auth.find_child("LoginButton", true, false) as Button).pressed.emit()
	_check("G 登录表单提供身份意图数据", auth.request_state() == {"phone": "13812342380", "code": "246810"})
	_check("G 游客入口存在", auth.find_child("GuestButton", true, false) is Button)
	_check("G 第三方按钮 3 个", auth.find_child("Socials", true, false).get_child_count() == 3)
	(auth.find_child("Socials", true, false).get_child(0) as Button).pressed.emit()
	_check("G 未配置第三方登录保持未认证", not state.authed)

	var ob := OnboardingScreen.new(state)
	root.add_child(ob)
	_check("G 引导步骤指示", ob.find_child("StepDots", true, false) != null)
	(ob.find_child("NextButton", true, false) as Button).pressed.emit()
	_check("G 引导第 2 步 9 标签", ob.find_child("TagFlow", true, false).get_child_count() == 9)
	_check("G 选满 3 个才能继续", (ob.find_child("NextButton", true, false) as Button).disabled)
	for i in 3:
		(ob.find_child("TagFlow", true, false).get_child(i) as Button).pressed.emit()
	_check("G 选 3 个后放行", not (ob.find_child("NextButton", true, false) as Button).disabled)
	(ob.find_child("NextButton", true, false) as Button).pressed.emit()
	var ob_done := {}
	ob.done.connect(func() -> void: ob_done["d"] = true)
	(ob.find_child("AllowButton", true, false) as Button).pressed.emit()
	_check("G 引导完成", ob_done.get("d", false))

	var off := OfflineScreen.new(state)
	root.add_child(off)
	var off_re := {}
	off.retry.connect(func() -> void: off_re["r"] = true)
	(off.find_child("RetryButton", true, false) as Button).pressed.emit()
	_check("G 断网重试信号", off_re.get("r", false))

	var search := SearchScreen.new(state)
	root.add_child(search)
	_check("G 热搜无权威数据不展示假词", search.find_child("HotFlow", true, false) == null)
	search.bind_hot(["ember"])
	_check("G 热搜只展示注入的权威词", search.find_child("HotFlow", true, false).get_child_count() == 1)
	search._query = "熔岩"
	search.rebuild()
	_check("G 服务端结果到达前不混入 Catalog 演示游戏充数", search.find_child("ResultList", true, false) == null)
	search.bind_games([{"id": "magma", "by": "@bo"}])  # 模拟发现页已加载的真实游戏列表(bind_games 同源)
	search.rebuild()
	_check("G 搜「熔岩」命中真实已加载列表", search.find_child("ResultList", true, false).get_child_count() >= 1)
	search._query = "zzzz"
	search.rebuild()
	_check("G 搜索空态", search.find_child("EmptyNote", true, false) != null)
	search._query = "熔岩"
	search.bind_search_results("熔岩", [])
	_check("G 服务端权威空搜索不回退种子", search.find_child("EmptyNote", true, false) != null and search.find_child("ResultList", true, false) == null)

	var ep := EditProfileScreen.new(state)
	root.add_child(ep)
	(ep.find_child("NameEdit", true, false) as LineEdit).text = "@koru2"
	(ep.find_child("SaveButton", true, false) as Button).pressed.emit()
	_check("G 编辑资料无 API 不伪造保存", state.profile["name"] != "@koru2")
	state.profile["name"] = "@guest"

	var acc := AccountScreen.new(state)
	root.add_child(acc)
	_click(acc.find_child("PasswordRow",true,false));_check("G 密码入口有真实表单",acc.find_child("PasswordEdit",true,false)!=null)
	acc._mode="";acc.rebuild();_click(acc.find_child("PhoneRow",true,false));_check("G 手机换绑入口有验证码表单",acc.find_child("PhoneCodeEdit",true,false)!=null)
	acc._mode="";acc.rebuild()
	(acc.find_child("DeleteButton", true, false) as Button).pressed.emit()
	_check("G 注销二次确认", acc.find_child("DeleteConfirm", true, false) != null)
	var delete_gateway:=FakeOperationsGateway.new();delete_gateway.delete_gate=SignalGate.new();delete_gateway.delete_result=ApiResultT.offline("delete failed")
	var delete_store:=OperationsStoreT.new();var delete_operations:=OperationsCoordinatorT.new(delete_gateway,delete_store)
	root.add_child(delete_store);root.add_child(delete_operations)
	var pending_acc:=AccountScreen.new(state,null,delete_operations);root.add_child(pending_acc)
	(pending_acc.find_child("DeleteButton",true,false) as Button).pressed.emit();(pending_acc.find_child("ConfirmButton",true,false) as Button).pressed.emit();await process_frame
	state.set_theme("light")
	_check("G 注销请求跨主题重建保持锁定",(pending_acc.find_child("ConfirmButton",true,false) as Button).disabled)
	delete_gateway.delete_gate.released.emit();await process_frame;await process_frame
	_check("G 注销失败后可重试",not (pending_acc.find_child("ConfirmButton",true,false) as Button).disabled and delete_gateway.calls.delete_account==1)
	state.set_theme("dark")

	var verify := VerifyScreen.new(state)
	root.add_child(verify)
	var v_done := {}
	verify.verified.connect(func() -> void: v_done["v"] = true)
	(verify.find_child("RealNameEdit", true, false) as LineEdit).text = "张三"
	(verify.find_child("IdEdit", true, false) as LineEdit).text = "110101200001010011"
	(verify.find_child("SubmitButton", true, false) as Button).pressed.emit()
	_check("G 实名认证无 API 不伪造成功", not v_done.get("v", false))

	var pts := PointsScreen.new(state)
	root.add_child(pts)
	_check("G 创作点余额接全局", pts.find_child("Balance", true, false).text == str(state.points))
	_check("G 创作点无 API 不展示假流水", pts.find_child("LedgerList", true, false).get_child_count() == 0)

	var help := HelpScreen.new(state)
	root.add_child(help)
	_click(help.find_child("FaqList", true, false).get_child(0))
	_check("G FAQ 展开", help._expanded.has(0))

	var about := AboutScreen.new(state)
	var opened:={"url":""};about.url_opener=func(url:String)->bool:opened["url"]=url;return true
	root.add_child(about)
	_check("G 关于页版本", "0.1.0" in about.find_child("BuildLabel", true, false).text)
	_check("G 关于页链接 5 条", about.find_child("LinkList", true, false).get_child_count() == 5)
	_click(about.find_child("AboutLink0",true,false));_check("G 关于链接执行真实 URL 打开",str(opened["url"]).begins_with("https://"))

	var teen := TeenScreen.new(state)
	root.add_child(teen)
	_check("G 青少年设置无 API 不展示假规则", teen.find_child("EmptyNote", true, false) != null and not teen.enabled)

	var blk := BlocklistScreen.new(state)
	root.add_child(blk)
	_check("G 黑名单无 API 不展示假用户", blk.find_child("EmptyNote", true, false) != null)

	var np := NotifPrefScreen.new(state)
	root.add_child(np)
	_check("G 通知设置无 API 不展示假偏好", np.find_child("EmptyNote", true, false) != null)

	var pv := PrivacyScreen.new(state)
	root.add_child(pv)
	_check("G 隐私无 API 不展示假偏好", pv.find_child("EmptyNote", true, false) != null)

# ── G2. 创作集群 ────────────────────────────────────────────
func _test_creator_screens() -> void:
	var state := _new_state()
	var creation := _new_creation()

	var studio := StudioT.new(state, creation.coordinator)
	root.add_child(studio)
	_check("G 创作中心无权威数据不展示假作品", studio.find_child("EmptyNote", true, false) != null)
	studio.set_works([{"id":"owned_review", "mod_id":"owned-mod", "runtime":"shooter@1.0.0", "title":"真实审核作品", "status":"reviewing", "plays":7, "forks":2}],
		[{"id":"draft_1", "runtime":"shooter@1.0.0", "draft":true}])
	_check("G 创作中心展示服务端作品与草稿", studio.find_child("WorkList", true, false).get_child_count() == 2
		and studio.find_child("ReviewButton", true, false) != null)
	var nav := {}
	studio.review_requested.connect(func(_w: Dictionary) -> void: nav["rev"] = true)
	(studio.find_child("ReviewButton", true, false) as Button).pressed.emit()
	_check("G 审核进度入口", nav.get("rev", false))
	# 每一行的「编辑」按钮必须带上那一行自己的作品,不能不管点哪行都跳到同一个空白编辑器。
	var edited := {}
	studio.edit_requested.connect(func(w: Dictionary) -> void: edited["id"] = w.get("id", ""))
	var edit_buttons := studio.find_children("EditButton", "", true, false)
	_check("G 创作中心每行各有编辑按钮", edit_buttons.size() == 2)
	(edit_buttons[0] as Button).pressed.emit()
	_check("G 编辑携带审核作品自己的 id", edited.get("id", "") == "owned_review")
	(edit_buttons[1] as Button).pressed.emit()
	_check("G 编辑携带草稿自己的 id,不是上一行残留", edited.get("id", "") == "draft_1")
	studio._review_queue = [{"id": "queue_game", "title": "待审作品"}]
	studio.rebuild()
	_check("G 审核队列可裁决", studio.find_child("QueueApprove_queue_game", true, false) != null)
	studio._refreshed = true
	creation.store.operation = "save_draft"
	creation.store.status = "ready"
	creation.store.changed.emit()
	_check("G 创作写操作使 Studio 缓存失效", not studio._refreshed)
	studio._refreshed = true
	creation.gateway.fail_workspace = true
	await studio.refresh()
	_check("G Studio 刷新失败后允许重试", not studio._refreshed)
	creation.gateway.fail_workspace = false

	var editor := EditorT.new(state, creation.coordinator, creation.session)
	var editor_session = creation.session
	root.add_child(editor)
	_check("G 编辑器首次挂载同步当前 DSL", JSON.parse_string((editor.find_child("DslEdit", true, false) as TextEdit).text) == editor_session.current())
	var pending_text := "{\"pending\": true}"
	var pending_edit := editor.find_child("DslEdit", true, false) as TextEdit
	pending_edit.text = pending_text
	pending_edit.text_changed.emit()
	for status: String in ["loading", "offline", "ready"]:
		creation.store.status = status
		creation.store.operation = "validate"
		creation.store.changed.emit()
	_check("G 网络与无关状态变化保留未提交 DSL", editor._dsl_text == pending_text)
	var switched_document: Dictionary = editor_session.current()
	switched_document["player"]["sprite"] = "switched"
	editor_session.load_document(switched_document)
	creation.store.changed.emit()
	_check("G 编辑器随创作上下文同步 DSL", JSON.parse_string(editor._dsl_text) == switched_document)
	editor_session.load_baseline("shooter@1.0.0", creation.store.baseline)
	creation.store.changed.emit()
	for operation: String in StudioT.WORKSPACE_MUTATIONS:
		studio._refreshed = true
		creation.store.operation = operation
		creation.store.status = "ready"
		creation.store.changed.emit()
		_check("G Studio 缓存覆盖创作写操作 %s" % operation, not studio._refreshed)
	var survivor_edit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/survivor/baseline.dsl.json"))
	_check("G DSL 编辑校验使用文档自身 Runtime", editor._runtime_ref_for(survivor_edit) == "survivor@1.0.0")
	_check("G DSL 编辑拒绝跨 Runtime 手改", not editor._matches_session_runtime(survivor_edit)
		and editor._matches_session_runtime(editor_session.current()))
	_check("G 编辑器暴露自动平衡与结构生成", editor.find_child("AutoBalanceButton", true, false) is Button
		and editor.find_child("GenerateStructureButton", true, false) is Button)
	_check("G 编辑器暴露桌面文件与多窗口入口", editor.find_child("ImportDslButton", true, false) is Button
		and editor.find_child("ExportDslButton", true, false) is Button and editor.find_child("PreviewWindowButton", true, false) is Button)
	(editor.find_child("AutoBalanceButton", true, false) as Button).pressed.emit()
	(editor.find_child("GenerateStructureButton", true, false) as Button).pressed.emit()
	_check("G AI 设计工具经 coordinator 应用", editor_session.current().get("balanced", false)
		and editor_session.current().get("structured", false))
	(editor.find_child("AddLevel", true, false) as Button).pressed.emit()
	_check("G 编辑器新增关卡", editor.levels == 4
		and editor.find_child("LevelChips", true, false).get_child_count() == 5)  # 4 关 + 新增钮
	var dsl_edit := editor.find_child("DslEdit", true, false) as TextEdit
	var edited_dsl: Dictionary = editor_session.current()
	edited_dsl["player"]["sprite"] = "cat"
	dsl_edit.text = JSON.stringify(edited_dsl)
	dsl_edit.text_changed.emit()
	(editor.find_child("ApplyDslButton", true, false) as Button).pressed.emit()
	_check("G DSL 编辑器应用到创作会话", editor_session.current()["player"]["sprite"] == "cat")
	(editor.find_child("UndoButton", true, false) as Button).pressed.emit()
	_check("G DSL 编辑器撤销", editor_session.current()["player"]["sprite"] == "plane")
	_check("G AI 改动仍保持可保存", not (editor.find_child("SaveButton", true, false) as Button).disabled)
	(editor.find_child("RedoButton", true, false) as Button).pressed.emit()
	(editor.find_child("SaveButton", true, false) as Button).pressed.emit()
	_check("G 草稿保存交给 creation coordinator", creation.store.draft_id == "draft-2")

	var pub := PublishT.new(state, creation.coordinator)
	root.add_child(pub)
	var p_done := {}
	pub.submitted.connect(func(t: String) -> void: p_done["t"] = t)
	(pub.find_child("SubmitButton", true, false) as Button).pressed.emit()
	_check("G 空标题不提交", not p_done.has("t"))
	(pub.find_child("TitleEdit", true, false) as LineEdit).text = "熔岩新作"
	(pub.find_child("SubmitButton", true, false) as Button).pressed.emit()
	_check("G 发布提交", p_done.get("t", "") == "熔岩新作")

	var rev := ReviewT.new(state, creation.coordinator)
	root.add_child(rev)
	rev.set_review_state(true, "game-1")
	_check("G 审核时间线 3 步", rev.find_child("Timeline", true, false).get_child_count() == 3)
	_check("G 驳回卡 + 理由", rev.find_child("RejectedCard", true, false) != null)
	(rev.find_child("ResubmitButton", true, false) as Button).pressed.emit()
	_check("G 重新提交经 creation coordinator 成功", rev.resubmitted)

	var ea := EarningsScreen.new(state)
	root.add_child(ea)
	_check("G 收益无权威数据归零", ea.find_child("TotalLabel", true, false).text == "0")
	_check("G 收益无权威数据不展示假流水", ea.find_child("LedgerList", true, false).get_child_count() == 0)
	_check("G 收益无 API 不展示假兑换", ea.find_child("WithdrawalList", true, false).get_child_count() == 1)
	_check("G 收益空态禁用兑换", (ea.find_child("WithdrawButton", true, false) as Button).disabled)
	var commerce_store = CommerceStoreT.new()
	var commerce = CommerceCoordinatorT.new(FakeCommerceGateway.new(), commerce_store)
	root.add_child(commerce_store); root.add_child(commerce)
	commerce_store.earnings = {"total": 240}
	commerce_store.withdrawals = [{"id":"w1","amount":120,"status":"pending","created_at":"2026-08-24T00:00:00Z"}]
	var bound_ea := EarningsScreen.new(state, commerce)
	root.add_child(bound_ea)
	_check("G 收益待处理兑换禁用按钮", (bound_ea.find_child("WithdrawButton", true, false) as Button).disabled)
	_check("G 收益展示真实兑换记录", bound_ea.find_child("WithdrawalList", true, false).get_child_count() == 1)
	_check("G 收益待处理横幅", bound_ea.find_child("PendingBanner", true, false) != null)

# ── G3. 社交集群 ────────────────────────────────────────────
func _test_social_screens() -> void:
	var state := _new_state()

	var creator := CreatorScreen.new(state)
	root.add_child(creator)
	_check("G 创作者未指定 handle 不冒充演示账号", creator.find_child("CreatorName", true, false) == null)
	creator.set_creator("@talia")
	_check("G 创作者主页", creator.find_child("CreatorName", true, false).text == "@talia")
	_check("G 创作者无权威作品不回退精选", creator.find_child("WorksGrid", true, false).get_child_count() == 1)
	(creator.find_child("FollowButton", true, false) as Button).pressed.emit()
	_check("G 关注无 API 不伪切换", not creator.following)

	var chat := ChatScreen.new(state)
	root.add_child(chat)
	chat.set_conversation({"handle":"@bob"})
	_check("G 聊天对象来自真实会话", chat.find_child("FriendName", true, false).text == "@bob")
	(chat.find_child("MsgEdit", true, false) as LineEdit).text = "今晚冲榜"
	(chat.find_child("SendButton", true, false) as Button).pressed.emit()
	_check("G 发消息无 API 不伪发送或对方消息", chat.bubbles.size() == 0)

	var af := AddFriendScreen.new(state)
	root.add_child(af)
	_check("G 扫码解析 handle", af._handle_from_qr("@mei") == "@mei")
	_check("G 扫码解析主页 URL", af._handle_from_qr("https://forgeplay.app/u/%40mei") == "@mei")
	_check("G 扫码拒绝外域", af._handle_from_qr("https://evil.example/u/%40mei") == "")
	_check("G 扫码拒绝查询注入", af._handle_from_qr("https://forgeplay.app/u/%40mei?admin=1") == "")
	_check("G 扫码拒绝特殊字符", af._handle_from_qr("@mei<script>") == "")
	_check("G 扫码拒绝控制字符", af._handle_from_qr("@mei\nadmin") == "")
	_check("G 加好友无查询时不展示假推荐", af.find_child("EmptyNote", true, false) != null)
	(af.find_child("SearchEdit", true, false) as LineEdit).text = "@real_user"
	(af.find_child("SearchEdit", true, false) as LineEdit).text_changed.emit("@real_user")
	_check("G 合法 handle 生成真实添加入口", af.find_child("AddHandleButton", true, false) != null)
	var qr_image := af.find_child("QrImage", true, false) as TextureRect
	_check("G 我的二维码", qr_image != null and qr_image.texture != null
		and qr_image.tooltip_text.begins_with("https://forgeplay.app/u/"))
	_check("G 无扫码插件时明确禁用", (af.find_child("ScanButton", true, false) as Button).disabled)

	var fl := FollowListScreen.new(state)
	root.add_child(fl)
	_check("G 关注列表无 API 不展示假用户", fl.find_child("EmptyNote", true, false) != null)
	fl.set_tab(1)
	_check("G 粉丝列表无 API 不展示假用户", fl.find_child("EmptyNote", true, false) != null)

	var community := _new_community()
	var bound_chat := ChatT.new(state, community.coordinator)
	root.add_child(bound_chat)
	bound_chat.set_conversation({"handle":"@real"})
	await process_frame
	(bound_chat.find_child("MsgEdit", true, false) as LineEdit).text = "真实消息"
	(bound_chat.find_child("SendButton", true, false) as Button).pressed.emit()
	await process_frame
	_check("G 聊天屏经 community coordinator 发送并回显", bound_chat.bubbles == [["真实消息", true]])
	var bound_follow := FollowT.new(state, community.coordinator)
	root.add_child(bound_follow)
	await bound_follow.refresh()
	_check("G 关注屏经 community coordinator 读取权威空态", bound_follow.find_child("EmptyNote", true, false) != null)

	var room := RoomScreen.new(state)
	root.add_child(room)
	_check("G 房间 4 槽位", room.find_child("SlotGrid", true, false).get_child_count() == 4)
	_check("G 房间支持输入码加入", room.find_child("JoinCodeEdit", true, false) is LineEdit and room.find_child("JoinRoomButton", true, false) is Button)
	_check("G 未就绪不能开始", (room.find_child("StartButton", true, false) as Button).disabled)
	(room.find_child("ReadyButton", true, false) as Button).pressed.emit()
	_check("G 房间无 API 不伪造就绪", (room.find_child("StartButton", true, false) as Button).disabled)
	state.profile["id"] = "guest"
	room.room = {"id":"room_test", "code":"ABC123", "host_id":"host", "status":"waiting", "members":[
		{"user_id":"host", "ready":true}, {"user_id":"guest", "ready":true}]}
	room.rebuild()
	_check("G 非房主即使全员就绪也不能发起开局", (room.find_child("StartButton", true, false) as Button).disabled)

# ── G4. 商业/留存 ───────────────────────────────────────────
func _test_commerce_screens() -> void:
	var state := _new_state()

	var shop := ShopScreen.new(state)
	root.add_child(shop)
	_check("G 商城无 API 不展示假商品", shop.find_child("SkinList", true, false).get_child_count() == 1)
	var before: int = state.points
	var paid := {}
	shop.paid.connect(func(d: String, _order_id: String) -> void: paid["d"] = d)
	_check("G 商城空态不伪造充值", state.points == before and not paid.has("d"))

	var mem := MembershipScreen.new(state)
	root.add_child(mem)
	_check("G 会员无 API 不展示假套餐权益", mem.find_child("EmptyNote", true, false) != null)
	mem._data = {"plans":[{"id":"plan_monthly", "name":"Monthly", "price":"18", "period":"/mo", "badge":""}], "perks":[]}
	_check("G 会员套餐保留支付产品 ID", mem._plans()[0].get("id", "") == "plan_monthly")
	var sub := {}
	mem.subscribed.connect(func(d: String, _order_id: String) -> void: sub["d"] = d)
	_check("G 会员空态不伪造会员", not state.member and not sub.has("d"))

	var pr := PayResultScreen.new(state)
	root.add_child(pr)
	pr.set_order("300 创作点", "order_abc123")
	_check("G 支付结果页", pr.find_child("PayOkTitle", true, false).text == "支付成功")
	_check("G 支付结果页展示真实订单号,不再本地伪造", pr.order_no == "order_abc123")

	var wf := WelfareScreen.new(state)
	root.add_child(wf)
	before = state.points
	_check("G 福利无 API 显示空态", wf.find_child("EmptyNote", true, false) != null)
	_check("G 福利空态不伪领奖", not wf.checked and state.points == before)

	var ev := EventsScreen.new(state)
	root.add_child(ev)
	_check("G 活动无 API 不展示假活动", ev.find_child("EventList", true, false).get_child_count() == 1)

	var ach := AchievementsScreen.new(state)
	root.add_child(ach)
	_check("G 成就无 API 不展示假进度", ach.find_child("EmptyNote", true, false) != null)

	var av := AvatarScreen.new(state)
	root.add_child(av)
	_check("G 装扮无 API 不展示假目录", av.find_child("CatalogEmpty", true, false) != null)
	av.frame_tone = "ocean"
	(av.find_child("SaveButton", true, false) as Button).pressed.emit()
	_check("G 装扮无 API 不伪保存", state.profile["tone"] != "ocean")
	state.profile["tone"] = "ember"

# ── G5. 库/全局 ─────────────────────────────────────────────
func _test_library_screens() -> void:
	var state := _new_state()

	var dl := DownloadsScreen.new(state)
	root.add_child(dl)
	_check("G 下载无 API 不展示假包体", dl.find_child("EmptyNote", true, false) != null)

	var his := HistoryScreen.new(state)
	root.add_child(his)
	_check("G 历史无 API 不展示假记录", his.find_child("EmptyNote", true, false) != null)
	his.clear_all()
	_check("G 历史无 API 不伪清空成功", his.find_child("EmptyNote", true, false) != null)

	var live := LiveScreen.new(state)
	root.add_child(live)
	live.set_live(["@mei", "冲周榜第 1,来抄作业", 1342, "ember"])
	_check("G 直播间标题", "@mei" in live.find_child("LiveTitle", true, false).text)
	live.push_danmu("666")
	_check("G 弹幕只追加真实输入", live.danmu.size() == 1)

	var rep := ReplayScreen.new(state)
	root.add_child(rep)
	rep.set_replay("@talia", CatalogT.GAMES[0])
	(rep.find_child("PlayPauseButton", true, false) as Button).pressed.emit()
	_check("G 无轨迹不伪造回放", not rep.playing and (rep.find_child("PlayPauseButton", true, false) as Button).disabled)
	rep.frames=[{"at_ms":0,"x":1.0,"y":2.0,"hp":100,"score":0},{"at_ms":1000,"x":3.0,"y":4.0,"hp":80,"score":50}]
	rep.duration_ms=1000;rep.rebuild()
	_check("G 真实回放遥测", rep.find_child("ReplayTelemetry",true,false)!=null and rep.find_child("ReplayStage",true,false)!=null and rep.find_child("ReplayGhost",true,false)!=null)
	var mid: Dictionary = rep._frame_at(500)
	_check("G 回放位置插值", is_equal_approx(float(mid.get("x", 0)), 2.0) and is_equal_approx(float(mid.get("y", 0)), 3.0) and int(mid.get("hp", 0)) == 100)
	_check("G 回放首帧遥测格式", (rep.find_child("ReplayTelemetry", true, false) as Label).text == "x 1.0 · y 2.0 · HP 100 · 0")
	(rep.find_child("PlayPauseButton",true,false) as Button).pressed.emit()
	_check("G 有轨迹允许播放",rep.playing)

	var operations_store=OperationsStoreT.new();var operations_gateway=FakeOperationsGateway.new();var operations=OperationsCoordinatorT.new(operations_gateway,operations_store)
	root.add_child(operations_store);root.add_child(operations)
	var report := ReportScreen.new(state,operations)
	root.add_child(report)
	report.set_target(CatalogT.GAMES[0])
	_check("G 举报理由 4 条 + 未选禁用", report.find_child("ReasonList", true, false).get_child_count() == 4
		and (report.find_child("SubmitButton", true, false) as Button).disabled)
	_click(report.find_child("ReasonList", true, false).get_child(1))
	operations_gateway.report_gate=SignalGate.new()
	(report.find_child("SubmitButton", true, false) as Button).pressed.emit();await process_frame
	_check("G 举报面板提交期间锁住所有互斥动作",(report.find_child("BlockButton",true,false) as Button).disabled and (report.find_child("NotInterestedButton",true,false) as Button).disabled)
	(report.find_child("BlockButton",true,false) as Button).pressed.emit()
	operations_gateway.report_gate.released.emit()
	await process_frame
	_check("G 举报提交带理由且不会并发屏蔽", operations_gateway.calls.get("report","") == "抄袭 / 搬运他人作品" and not operations_gateway.calls.has("block"))
	report.set_target({"id":"game-id","by":"@handle","author_id":"user-id"})
	(report.find_child("BlockButton",true,false) as Button).pressed.emit();await process_frame
	_check("G 屏蔽使用稳定 author_id 而非展示 handle",operations_gateway.calls.get("block","")=="user-id")
	report.set_target({"id":"game-id","by":"@handle","author_id":"user-id"})
	(report.find_child("NotInterestedButton",true,false) as Button).pressed.emit()
	await process_frame
	_check("G 不感兴趣交给 operations API 链路",operations_gateway.calls.has("not_interested"))

	var blocklist:=BlocklistScreen.new(state,operations);root.add_child(blocklist);blocklist.entries=[["u1",""],["u2",""]];operations_store.blocks=[{"user_id":"u1"},{"user_id":"u2"}];operations_gateway.unblock_gates={"u1":SignalGate.new(),"u2":SignalGate.new()};blocklist.rebuild()
	var block_cards:=blocklist.find_child("BlockList",true,false);(block_cards.get_child(0).find_children("*","Button",true,false)[0] as Button).pressed.emit();(block_cards.get_child(1).find_children("*","Button",true,false)[0] as Button).pressed.emit();await process_frame
	(operations_gateway.unblock_gates.u2 as SignalGate).released.emit();await process_frame;(operations_gateway.unblock_gates.u1 as SignalGate).released.emit();await process_frame
	_check("G 并发解除屏蔽按 user_id 对账而非陈旧下标",blocklist.entries.is_empty() and operations_store.blocks.is_empty())

	var share := ShareScreen.new(state)
	root.add_child(share)
	share.set_target(CatalogT.GAMES[0])
	_check("G 分享渠道 4 个", share.find_child("ChannelGrid", true, false).get_child_count() == 4)
	var share_done := {}
	share.shared.connect(func() -> void: share_done["ok"] = true)
	(share.find_child("ChannelGrid", true, false).get_child(3) as Button).pressed.emit()
	_check("G 复制链接执行后才报分享成功", share_done.get("ok", false))

# ── F. AppRoot 装配(登录门 + 种子内容接线) ──────────────────
func _test_app_root() -> void:
	var state := _new_state()
	var application:AppRoot=AppRootT.new(state,"",{
		"identity":FakeIdentityGateway.new(),
		"catalog":FakeCatalogGateway.new(),
		"creation":FakeCreationGateway.new(),
		"community":FakeCommunityGateway.new(),
		"engagement":FakeEngagementGateway.new(),
		"commerce":FakeCommerceGateway.new(),
		"operations":FakeOperationsGateway.new(),
	})
	root.add_child(application)
	var router:Router=application.router
	application.set_layout("phone")
	router.resolve_orientation(true)
	# 会话门:未登录 → 登录页;登录后未引导 → 引导;完成 → 首页
	# 游客直达:未登录启动即自动建会话(api=null 时为本地会话),直进首页且跳过引导墙
	_check("F 游客直达首页", application._content.get_child(0) is HomeScreen and state.authed and state.onboarded)
	# 登出 → 回登录页(按需登录入口);重新登录直接进首页(已引导,不再走 onboarding)
	router.go("settings")
	(application.settings.find_child("LogoutButton",true,false) as Button).pressed.emit()
	await process_frame
	_check("F 登出回登录页", application._content.get_child(0) is AuthScreen)
	state.login()
	application._sync()
	var engagement_runtime=application.engagement_runtime
	var creation:={"session":application.creation_session,"store":application.creation_store}
	_check("F 重新登录进首页", application._content.get_child(0) is HomeScreen)
	_check("F 首次进 tabs 不弹演示更新", application.find_child("UpdateModal", true, false) == null)
	application.show_update_modal()
	_check("F 显式更新弹窗仍可打开", application.find_child("UpdateModal", true, false) != null)
	(application.find_child("LaterButton", true, false) as Button).pressed.emit()
	application.show_push_banner()
	_check("F 推送横幅", application.find_child("PushBanner", true, false) != null)
	application._close_push()
	_check("F 状态栏时钟", application.find_child("StatusClock", true, false) != null)
	_check("F TabBar 图标前缀", (application._tabbar.get_child(0) as Button).text.begins_with("⌂"))
	_check("F 全局 Theme 级联(输入框样式)", application.theme != null
		and application.theme.has_stylebox("normal", "LineEdit"))
	state.set_theme("light")
	_check("F 主题切换 Theme 跟随", (application.theme.get_stylebox("normal", "LineEdit") as StyleBoxFlat).bg_color == Color("#F4F0ED"))
	state.set_theme("dark")
	_check("F 无通知时不伪造未读红点", application._tabbar.get_child(3).find_child("UnreadDot", true, false) == null)
	(application._tabbar.get_child(1) as Button).pressed.emit()
	_check("F 切到发现", application._content.get_child(0) is ExploreScreen)
	router.open_game(CatalogT.GAMES[4])
	_check("F 详情接线", application._content.get_child(0) is DetailScreen
		and application.detail.game["id"] == "cinder")
	_check("F 详情隐藏 TabBar", not application._tabbar.visible)
	router.back()
	(application._tabbar.get_child(4) as Button).pressed.emit()
	application.profile.settings_requested.emit()
	_check("F 设置接线", application._content.get_child(0) is SettingsScreen)
	router.back()
	# 开玩链路:详情 → 闸门 → 转屏 → 加载 → 进游戏(PlayView 持有该游戏)
	router.play(CatalogT.GAMES[0])
	_check("F 闸门视图", router.view == Router.VIEW_ROTATE)
	router.rotate_and_play()
	router.enter_play()
	_check("F 游玩接线", application._content.get_child(0) is PlayView
		and application.play_view.game["id"] == "ember")
	_check("F PlayView 显式注入 engagement runtime port", application.play_view.engagement_runtime == engagement_runtime)
	var cached_history: HistoryScreen = application._views["history"]["screen"]
	cached_history._refreshed = true
	application.detail._refreshed = true
	application.play_view.play_recorded.emit("ember")
	_check("F 游玩上报后使历史缓存失效", not cached_history._refreshed)
	_check("F 游玩上报后使详情排行缓存失效", not application.detail._refreshed)
	# ESC/返回键:退出游戏回详情后,统一返回回 tabs
	router.exit_play()
	application.handle_back()
	_check("F ESC 统一返回", router.view == Router.VIEW_TABS)
	# 创作会话基线已加载(forge 流的 current_dsl 来源)
	_check("F 创作基线就绪", not creation.session.current().is_empty())
	var survivor_editor_dsl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/survivor/baseline.dsl.json"))
	creation.session.load_baseline("survivor@1.0.0", survivor_editor_dsl)
	creation.store.runtime_ref = "survivor@1.0.0"
	application.editor.set_session(creation.session)
	(application.editor.find_child("TestButton", true, false) as Button).pressed.emit()
	_check("F 编辑器测试运行当前 Runtime 与 DSL", router.game.get("runtime", "") == "survivor@1.0.0"
		and router.game.get("dsl", {}).get("waves", {}).size() == survivor_editor_dsl.get("waves", {}).size())
	router.back()
	# 自适应 chrome:desktop → 侧栏,无底部 TabBar(标题栏用系统原生,不自绘),开玩无闸门
	application.set_layout("desktop")
	_check("F 桌面侧栏", application._sidebar.visible and not application._tabbar.visible)
	var avatar := application.find_child("AppBarAvatar", true, false) as Control
	var avatar_click := InputEventMouseButton.new()
	avatar_click.pressed = true
	avatar_click.button_index = MOUSE_BUTTON_LEFT
	avatar.gui_input.emit(avatar_click)
	_check("F 桌面头像进我的", router.tab == 4 and application._content.get_child(0) is ProfileT)
	state.teen_enabled = true
	state.teen_play_secs = TeenGuardT.DAILY_LIMIT_SECS
	state.teen_day = "%04d-%02d-%02d" % [
		int(Time.get_datetime_dict_from_system().year),
		int(Time.get_datetime_dict_from_system().month),
		int(Time.get_datetime_dict_from_system().day),
	]
	var play_blocked := {"n": 0}
	application.router.changed.connect(func() -> void: play_blocked["n"] += 1)
	application._request_play(CatalogT.GAMES[0])
	_check("F 青少年时长上限拦截开玩", application.router.view != Router.VIEW_ROTATE
		and application.router.view != Router.VIEW_LOADING
		and application.router.view != Router.VIEW_PLAY)
	state.teen_enabled = false
	(application.find_child("Side1", true, false) as Button).pressed.emit()
	_check("F 侧栏导航切发现", router.tab == 1 and application._content.get_child(0) is ExploreScreen)
	# 「我的作品/二创/喜欢」各开独立子页(避免三项点开都是同一个「我的」页)
	application._open_library("forks")
	var lib := application._content.get_child(0)
	_check("F 侧栏库目录开独立子页", router.view == "library" and is_instance_of(lib, LibraryT)
		and lib.kind == "forks")
	lib.set_collection("liked", 4)
	lib.bind_games([])
	_check("F 已加载的空收藏不回退种子", lib.find_child("LibraryGrid", true, false).find_child("EmptyNote", true, false) != null)
	router.back()
	# 飙升榜是独立专页(榜单专页模式),不是发现 tab
	router.go("trending")
	var trd := application._content.get_child(0)
	_check("F 飙升榜独立专页", router.view == "trending"
		and trd is ExploreScreen and (trd as ExploreScreen).ranking_only)
	router.back()
	router.play(CatalogT.GAMES[0])
	_check("F 桌面开玩无闸门", router.view == Router.VIEW_LOADING)
	router.enter_play()
	router.exit_play()
	router.back()
	application.set_layout("rail")
	_check("F iPad rail 5 项", application._rail.visible
		and application.find_child("RailItems", true, false).get_child_count() == 5)
	application.set_layout("phone")
	_check("F 回手机布局", application._tabbar.visible and not application._rail.visible and router.is_phone)
	router.go("account")
	var account:=application._content.get_child(0) as AccountScreen
	(account.find_child("DeleteButton",true,false) as Button).pressed.emit()
	(account.find_child("ConfirmButton",true,false) as Button).pressed.emit()
	await process_frame
	await process_frame
	_check("F 删除账号完成后安全重建账号 scope",not state.authed and application._content.get_child(0) is AuthScreen)
