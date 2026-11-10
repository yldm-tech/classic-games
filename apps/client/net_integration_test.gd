extends SceneTree

## 双端集成测试:Godot 客户端经 feature gateway 调用真·Go 后端 /ai/mod、/ai/validate。
## 需先起后端:  cd apps/server && PORT=8099 FORGEPLAY_SCHEMA_DIR=../../packages/schemas go run ./cmd/server
## 运行:        godot --headless --path apps/client --script res://net_integration_test.gd
## 后端地址可用环境变量 FORGEPLAY_API 覆盖(默认 http://127.0.0.1:8099)。

const HttpClientScript := preload("res://core/http/http_client.gd")
const IdentityApiScript := preload("res://features/identity/identity_api.gd")
const CatalogApiScript := preload("res://features/catalog/catalog_api.gd")
const CreationApiScript := preload("res://features/creation/creation_api.gd")
const CommunityApiScript := preload("res://features/community/community_api.gd")
const EngagementApiScript := preload("res://features/engagement/engagement_api.gd")
const CommerceApiScript := preload("res://features/commerce/commerce_api.gd")
const OperationsApiScript := preload("res://features/operations/operations_api.gd")
const OperationsStoreScript := preload("res://features/operations/operations_store.gd")
const OperationsCoordinatorScript := preload("res://features/operations/operations_coordinator.gd")

var _passed := 0
var _failed := 0

## Keeps the long-form end-to-end assertions readable while the transport is
## the feature-owned CreationApi/ApiResult contract rather than typed feature gateway.
class IntegrationCreationClient:
	extends RefCounted
	var gateway: CreationApi
	func _init(p_gateway: CreationApi) -> void: gateway = p_gateway
	func _wrap(result: Variant) -> Dictionary:
		return {"ok":result.ok, "status":result.status, "body":result.data,
			"error":{"code":result.code, "message":result.message}}
	func runtime_baseline(n:String,v:String): return _wrap(await gateway.runtime_baseline(n,v))
	func runtime_schema(n:String,v:String): return _wrap(await gateway.runtime_schema(n,v))
	func generate_mod(r:String,d:Dictionary,p:String): return _wrap(await gateway.generate_mod(r,d,p))
	func validate_dsl(r:String,d:Dictionary): return _wrap(await gateway.validate_dsl(r,d))
	func auto_balance(r:String,d:Dictionary,x:int): return _wrap(await gateway.auto_balance(r,d,x))
	func generate_structure(r:String,d:Dictionary,p:String,c:int,x:int): return _wrap(await gateway.generate_structure(r,d,p,c,x))
	func create_mod(r:String,parent:String,p:Array,proof:String=""): return _wrap(await gateway.create_mod(r,parent,p,proof))
	func effective_dsl(id:String): return _wrap(await gateway.effective_dsl(id))
	func fork_mod(id:String): return _wrap(await gateway.fork_mod(id))
	func save_draft(r:String,parent:String,p:Array,proof:String=""): return _wrap(await gateway.save_draft(r,parent,p,proof))
	func drafts(): return _wrap(await gateway.drafts())
	func update_draft(id:String,p:Array): return _wrap(await gateway.update_draft(id,p))
	func publish_draft(id:String,t:String,s:String="",tags:Array=[]): return _wrap(await gateway.publish_draft(id,t,s,tags))
	func publish_game(id:String,t:String,c:String=""): return _wrap(await gateway.publish_game(id,t,c))
	func game_dsl(id:String): return _wrap(await gateway.game_dsl(id))
	func fork_game(id:String): return _wrap(await gateway.fork_game(id))
	func moderation_queue(): return _wrap(await gateway.moderation_queue())
	func decide_game(id:String,a:bool): return _wrap(await gateway.decide_game(id,a))
	func my_games(lang:String): return _wrap(await gateway.my_games(lang))

class IntegrationCommunityClient:
	extends RefCounted
	var gateway: CommunityApi
	func _init(p_gateway: CommunityApi) -> void: gateway = p_gateway
	func _wrap(result: Variant) -> Dictionary:
		return {"ok":result.ok, "status":result.status, "body":result.data,
			"error":{"code":result.code, "message":result.message}}
	func set_follow(handle:String,value:bool): return _wrap(await gateway.set_follow(handle,value))
	func following(id:String): return _wrap(await gateway.following(id))
	func follow(kind:String,lang:String): return _wrap(await gateway.follow(kind,lang))
	func add_friend(handle:String): return _wrap(await gateway.add_friend(handle))
	func chats(lang:String): return _wrap(await gateway.conversations(lang))
	func send_conversation_message(handle:String,text:String): return _wrap(await gateway.send_message(handle,text))
	func activity(lang:String): return _wrap(await gateway.activity(lang))
	func comment(id:String,text:String): return _wrap(await gateway.add_comment(id,text))
	func like_game(id:String): return _wrap(await gateway.set_like(id,true))
	func favorite_game(id:String,value:bool=true): return _wrap(await gateway.set_favorite(id,value))
	func favorites(): return _wrap(await gateway.favorites())

class IntegrationEngagementClient:
	extends RefCounted
	var gateway: EngagementApi
	func _init(p_gateway: EngagementApi) -> void: gateway = p_gateway
	func _wrap(result: Variant) -> Dictionary:
		return {"ok":result.ok, "status":result.status, "body":result.data,
			"error":{"code":result.code, "message":result.message}}
	func create_room(): return _wrap(await gateway.create_room())
	func join_room(code:String): return _wrap(await gateway.join_room(code))
	func set_room_ready(id:String,value:bool): return _wrap(await gateway.set_room_ready(id,value))
	func start_room(id:String): return _wrap(await gateway.start_room(id))
	func submit_room_input(id:String,seq:int,x:float,y:float,fire:bool): return _wrap(await gateway.submit_room_input(id,seq,x,y,fire))
	func room_snapshot(id:String): return _wrap(await gateway.room_snapshot(id))
	func live(lang:String): return _wrap(await gateway.live(lang))
	func record_play(id:String,duration:int): return _wrap(await gateway.record_play(id,duration))
	func history(lang:String): return _wrap(await gateway.history(lang))

class IntegrationCommerceClient:
	extends RefCounted
	var gateway: CommerceApi
	func _init(p_gateway: CommerceApi) -> void: gateway = p_gateway
	func _wrap(result: Variant) -> Dictionary:
		return {"ok":result.ok,"status":result.status,"body":result.data,
			"error":{"code":result.code,"message":result.message}}
	func points(): return _wrap(await gateway.points())
	func welfare(lang:String): return _wrap(await gateway.welfare(lang))
	func achievements(lang:String): return _wrap(await gateway.achievements(lang))

class IntegrationOperationsClient:
	extends RefCounted
	var gateway:OperationsApi
	func _init(p_gateway:OperationsApi)->void:gateway=p_gateway
	func submit_verification(name:String,id_number:String)->Dictionary:
		var result=await gateway.submit_verification(name,id_number)
		return {"ok":result.ok,"status":result.status,"body":result.data,"error":{"code":result.code,"message":result.message}}

func _initialize() -> void:
	var base_url := "http://127.0.0.1:8099"
	if OS.has_environment("FORGEPLAY_API"):
		base_url = OS.get_environment("FORGEPLAY_API")

	var baseline := _load_json("res://runtime/shooter/baseline.dsl.json")
	var identity_http := HttpClientScript.new(base_url)
	root.add_child(identity_http)
	var identity := IdentityApiScript.new(identity_http)
	var catalog := CatalogApiScript.new(identity_http)
	var creation := IntegrationCreationClient.new(CreationApiScript.new(identity_http))
	var community := IntegrationCommunityClient.new(CommunityApiScript.new(identity_http))
	var engagement := IntegrationEngagementClient.new(EngagementApiScript.new(identity_http))
	var commerce := IntegrationCommerceClient.new(CommerceApiScript.new(identity_http))
	var operations:=IntegrationOperationsClient.new(OperationsApiScript.new(identity_http))
	var operations_store:=OperationsStoreScript.new();var operations_coordinator:=OperationsCoordinatorScript.new(OperationsApiScript.new(identity_http),operations_store)
	root.add_child(operations_store);root.add_child(operations_coordinator)
	# _initialize 里刚加入的节点要等一帧才真正 inside_tree,HTTPRequest 才能发起。
	await process_frame

	# 0. 游客登录:换取 token(写接口/审核裁决都需鉴权;后端开了 FORGEPLAY_DEV_ADMIN 让登录用户可裁决)
	var guest = await identity.guest_login()
	_check("游客登录 → 200 且拿到 token", guest.ok and guest.data.get("token", "") != "")
	identity_http.set_token(guest.data.get("token", ""))
	var me_id := str(guest.data.get("user", {}).get("id", ""))
	_check("operations 安全写入合并真实部分响应",await operations_coordinator.load_security() and await operations_coordinator.set_password("Integration123!") and operations_store.security.has("phone_masked") and operations_store.security.has("providers") and operations_store.security.get("password_set",false))
	_check("operations 通知写入保留完整元数据",await operations_coordinator.load_notifications("zh") and await operations_coordinator.set_notification("push_master",false) and operations_store.notifications.has("groups") and not operations_store.notifications.get("master_default",true))
	_check("operations 隐私写入保留完整元数据",await operations_coordinator.load_privacy("zh") and await operations_coordinator.set_privacy("show_online_status",false) and operations_store.privacy.has("items"))
	_check("operations 青少年写入保留规则模型",await operations_coordinator.load_teen("zh") and await operations_coordinator.set_teen(true,"1234") and operations_store.teen.has("rules") and operations_store.teen.get("default_enabled",false))
	# Teen mode must be off again before the play, room and replay checks below: the server's play guard applies a 22:00-08:00 curfew to teen accounts using its own clock, so leaving it on fails those checks whenever the suite runs at night.
	_check("operations 青少年模式可凭 PIN 关闭",await operations_coordinator.set_teen(false,"1234") and not operations_store.teen.get("default_enabled",true))

	# 双账号权威联机：大厅握手后，输入只由服务端推进，双方读取同一持久化快照。
	var room_identity_http := HttpClientScript.new(base_url)
	root.add_child(room_identity_http)
	var room_identity := IdentityApiScript.new(room_identity_http)
	var room_guest_login = await room_identity.guest_login()
	room_identity_http.set_token(room_guest_login.data.get("token", ""))
	var room_guest_engagement := IntegrationEngagementClient.new(EngagementApiScript.new(room_identity_http))
	var created_room: Dictionary = await engagement.create_room()
	var joined_room: Dictionary = await room_guest_engagement.join_room(str(created_room["body"].get("code", "")))
	var room_id := str(created_room["body"].get("id", ""))
	var host_ready: Dictionary = await engagement.set_room_ready(room_id, true)
	var guest_ready: Dictionary = await room_guest_engagement.set_room_ready(room_id, true)
	var started_room: Dictionary = await engagement.start_room(room_id)
	_check("双账号房间创建/加入/全员准备/开局", room_guest_login.ok and created_room["status"] == 201
		and joined_room["ok"] and joined_room["body"].get("members", []).size() == 2
		and host_ready["ok"] and guest_ready["ok"] and started_room["body"].get("status", "") == "started")
	var submitted_input: Dictionary = await engagement.submit_room_input(room_id, 1, 1.0, -1.0, true)
	var guest_snapshot: Dictionary = await room_guest_engagement.room_snapshot(room_id)
	var guest_id := str(room_guest_login.data.get("user", {}).get("id", ""))
	var guest_health := -1
	for player: Dictionary in guest_snapshot["body"].get("players", []):
		if str(player.get("user_id", "")) == guest_id: guest_health = int(player.get("health", -1))
	_check("A 输入后 B 读取同一权威 tick/生命", submitted_input["ok"] and guest_snapshot["ok"]
		and int(submitted_input["body"].get("tick", 0)) == 1 and int(guest_snapshot["body"].get("tick", 0)) == 1 and guest_health == 90)
	var stale_input: Dictionary = await engagement.submit_room_input(room_id, 1, 0.0, 0.0, false)
	_check("重复输入序号被服务端拒绝", not stale_input["ok"] and stale_input["status"] == 409)

	var follow_user: Dictionary = await community.set_follow("integration_target", true)
	var following_users: Dictionary = await community.following(me_id)
	_check("标准用户关注路径与 following 列表一致", follow_user["ok"] and following_users["ok"] and following_users["body"].get("items", []).any(func(x): return x.get("handle", "") == "integration_target"))
	var follow_screen_data: Dictionary = await community.follow("following", "zh")
	_check("关注页只返回当前用户真实关系", follow_screen_data["ok"] and follow_screen_data["body"].get("items", []).size() == 1
		and follow_screen_data["body"]["items"][0].get("handle", "") == "integration_target")
	var oauth_unconfigured = await identity.oauth_exchange("unknown", "code")
	_check("OAuth 标准路径无供应商时明确 503", not oauth_unconfigured.ok and oauth_unconfigured.status == 503)
	var realname: Dictionary = await operations.submit_verification("集成测试", "11010519491231002X")
	_check("实名标准路径进入 pending", realname["status"] == 202 and realname["body"].get("status", "") == "pending")
	var added_friend: Dictionary = await community.add_friend("@integration_friend")
	var conversations: Dictionary = await community.chats("zh")
	var sent_message: Dictionary = await community.send_conversation_message("@integration_friend", "integration message")
	_check("标准会话路径来自真实好友并只回显真实写入消息", added_friend["ok"] and conversations["ok"]
		and conversations["body"].get("items", []).size() == 1 and conversations["body"]["items"][0].get("handle", "") == "@integration_friend"
		and sent_message["status"] == 201
		and sent_message["body"].get("items", []).size() == 1 and sent_message["body"]["items"][0].get("text", "") == "integration message")
	var activity: Dictionary = await community.activity("zh")
	_check("新账号通知为空且不注入演示通知", activity["ok"] and activity["body"].get("items", []).is_empty())
	var initial_points: Dictionary = await commerce.points()
	var initial_welfare: Dictionary = await commerce.welfare("zh")
	var initial_live: Dictionary = await engagement.live("zh")
	var honest_quests: bool = initial_welfare["body"].get("quests", []).all(func(q): return int(q.get("progress", -1)) == 0)
	_check("新账号创作点/收益/福利不注入历史假数据", initial_points["ok"] and initial_welfare["ok"]
		and initial_points["body"].get("ledger", []).is_empty()
		and int(initial_points["body"].get("earnings", {}).get("total", -1)) == 0
		and initial_points["body"].get("earnings", {}).get("ledger", []).is_empty()
		and int(initial_welfare["body"].get("checkin", {}).get("streak", -1)) == 0 and honest_quests
		and str(initial_welfare["body"].get("invite", {}).get("code", "")).begins_with("FP-"))
	_check("新账号发现页不注入演示直播", initial_live["ok"] and initial_live["body"].get("items", []).is_empty())

	var survivor_baseline: Dictionary = await creation.runtime_baseline("survivor", "1.0.0")
	_check("Runtime baseline API 返回 Survivor DSL", survivor_baseline["ok"] and survivor_baseline["body"].get("meta", {}).get("runtime") == "survivor")
	var tower_schema: Dictionary = await creation.runtime_schema("tower_defense", "1.0.0")
	_check("Runtime schema API 返回 Tower Defense schema", tower_schema["ok"] and tower_schema["body"].get("title", "").contains("Tower Defense"))
	var survivor_ai: Dictionary = await creation.generate_mod("survivor@1.0.0", survivor_baseline["body"], "换成法师")
	_check("Survivor AI 生成真实改动并通过 Schema", survivor_ai["ok"] and survivor_ai["body"].get("dsl_patch", []).size() > 0 and survivor_ai["body"].get("new_dsl", {}).get("hero", {}).get("sprite", "") == "mage")
	var tower_baseline: Dictionary = await creation.runtime_baseline("tower_defense", "1.0.0")
	var tower_ai: Dictionary = await creation.generate_mod("tower_defense@1.0.0", tower_baseline["body"], "换成沙漠")
	_check("Tower AI 生成真实改动并通过 Schema", tower_ai["ok"] and tower_ai["body"].get("dsl_patch", []).size() > 0 and tower_ai["body"].get("new_dsl", {}).get("stage", {}).get("background", "") == "desert")

	var design_inputs := [
		["shooter", baseline, "enemies"],
		["survivor", survivor_baseline["body"], "waves"],
		["tower_defense", tower_baseline["body"], "waves"],
	]
	for spec: Array in design_inputs:
		var runtime_name := str(spec[0]); var current: Dictionary = spec[1]; var structure_key := str(spec[2])
		var balanced: Dictionary = await creation.auto_balance(runtime_name + "@1.0.0", current, 5)
		_check("%s 自动平衡多参数且压力指标提升" % runtime_name, balanced["ok"]
			and balanced["body"].get("dsl_patch", []).size() >= 3
			and float(balanced["body"].get("metrics", {}).get("after", 0)) > float(balanced["body"].get("metrics", {}).get("before", 0)))
		var structured: Dictionary = await creation.generate_structure(runtime_name + "@1.0.0", current, "冰霜夜袭", 3, 4)
		var before_count := (current.get(structure_key, {}) as Dictionary).size()
		var after_count := (structured.get("body", {}).get("new_dsl", {}).get(structure_key, {}) as Dictionary).size()
		_check("%s AI 生成 3 个合法结构节点" % runtime_name, structured["ok"]
			and structured["body"].get("generated_keys", []).size() == 3 and after_count == before_count + 3)

	# 1. /ai/mod —— 客户端 → 后端 → apply → schema 校验 → 回传 new_dsl
	var r1: Dictionary = await creation.generate_mod("shooter@1.0.0", baseline, "把飞机换成猫")
	_check("/ai/mod 200 成功", r1["ok"] and r1["status"] == 200)
	var has_new_dsl: bool = typeof(r1.get("body")) == TYPE_DICTIONARY and r1["body"].has("new_dsl")
	_check("/ai/mod 返回 new_dsl", has_new_dsl)
	if has_new_dsl:
		_check("new_dsl 是合法 DSL(含 player)", r1["body"]["new_dsl"].has("player"))

	# 2. /ai/validate 合法
	var r2: Dictionary = await creation.validate_dsl("shooter@1.0.0", baseline)
	_check("/ai/validate 合法 → 200", r2["ok"] and r2["status"] == 200)

	# 3. /ai/validate 非法(hp 越界)→ 422 DSL_INVALID,且错误信封被正确解析
	var bad := baseline.duplicate(true)
	bad["player"]["hp"] = 9999
	var r3: Dictionary = await creation.validate_dsl("shooter@1.0.0", bad)
	_check("/ai/validate 非法 → 422", not r3["ok"] and r3["status"] == 422)
	_check("错误信封 code=DSL_INVALID", r3["error"].get("code") == "DSL_INVALID")

	# 4. Fork 全流程(客户端 → 服务端):建根 mod → 取生效 DSL → Fork → 建子 → 验证补丁链
	var sprite_patch := [{"op": "replace", "path": "/player/sprite", "value": "cat"}]
	var m1: Dictionary = await creation.create_mod("shooter@1.0.0", "", sprite_patch)
	_check("建根 mod → 201", m1["status"] == 201)
	var root_id: String = m1["body"].get("id", "")

	var d1: Dictionary = await creation.effective_dsl(root_id)
	_check("根 mod 生效 DSL sprite=cat", d1["ok"] and d1["body"]["player"]["sprite"] == "cat")

	var fk: Dictionary = await creation.fork_mod(root_id)
	_check("Fork → 201 且 parent 正确", fk["status"] == 201 and fk["body"]["parent_id"] == root_id)

	var bird_patch := [{"op": "add", "path": "/enemies/bird_1",
		"value": {"type": "bird", "behavior": "sine", "count": 10, "hp": 15, "speed": 12}}]
	var m2: Dictionary = await creation.create_mod("shooter@1.0.0", fk["body"]["id"], bird_patch)
	_check("在 Fork 上建子 → 201", m2["status"] == 201)

	var d2: Dictionary = await creation.effective_dsl(m2["body"]["id"])
	var ok_chain: bool = d2["ok"] \
		and d2["body"]["player"]["sprite"] == "cat" \
		and d2["body"]["enemies"].has("bird_1")
	_check("子 mod 生效 DSL = 继承 cat + 本级 bird(补丁链跨端一致)", ok_chain)

	var draft: Dictionary = await creation.save_draft("shooter@1.0.0", "", [])
	var draft_list: Dictionary = await creation.drafts()
	_check("标准草稿列表包含新草稿", draft["status"] == 201 and draft["body"].get("id", "") in draft_list["body"].get("items", []).map(func(x): return x.get("id", "")))
	var draft_saved: Dictionary = await creation.update_draft(draft["body"].get("id", ""), sprite_patch)
	_check("PUT 草稿创建不可变新版本", draft_saved["status"] == 201 and draft_saved["body"].get("parent_id", "") == draft["body"].get("id", ""))
	var draft_pub: Dictionary = await creation.publish_draft(draft_saved["body"].get("id", ""), "草稿发布")
	_check("草稿标准发布进入审核", draft_pub["status"] == 201 and draft_pub["body"].get("status", "") == "reviewing")

	# 5. 创作+社交+榜单闭环:发布 → 审核 → 列表 → 评论 → 点赞 → 榜单
	var pub: Dictionary = await creation.publish_game(root_id, "电光狂奔", "arcade")
	_check("发布游戏 → 201 reviewing", pub["status"] == 201 and pub["body"]["status"] == "reviewing")
	var game_id: String = pub["body"].get("id", "")
	var game_dsl: Dictionary = await creation.game_dsl(game_id)
	_check("游戏资源直接返回生效 DSL", game_dsl["ok"] and game_dsl["body"].get("player", {}).get("sprite") == "cat")
	var game_lineage = await catalog.game_lineage(game_id)
	_check("游戏资源直接返回创作链", game_lineage.ok and game_lineage.data.get("items", []).size() == 1)
	var game_tree = await catalog.game_fork_tree(game_id)
	_check("游戏资源直接返回 Fork Tree", game_tree.ok and game_tree.data.get("node", {}).get("id", "") == root_id)
	var game_fork: Dictionary = await creation.fork_game(game_id)
	_check("从游戏资源直接 Fork 草稿", game_fork["status"] == 201 and game_fork["body"].get("parent_id", "") == root_id)
	var queue: Dictionary = await creation.moderation_queue()
	var queued := false
	if queue["ok"]:
		for item in queue["body"].get("items", []):
			if item.get("id", "") == game_id: queued = true
	_check("管理员审核队列包含 reviewing 游戏", queued)

	var dec: Dictionary = await creation.decide_game(game_id, true)
	_check("审核通过 → 200", dec["ok"])

	var games = await catalog.list_games({})
	_check("已发布列表含该游戏", games.ok and games.data["items"].size() >= 1)
	var filtered_games = await catalog.list_games({"lang": "zh", "sort": "new", "runtime": "shooter", "category": "arcade"})
	_check("游戏发现按可信 Runtime 与分类筛选", filtered_games.ok and filtered_games.data.get("items", []).any(func(x): return x.get("id", "") == game_id and x.get("runtime", "") == "shooter@1.0.0"))
	var searched_games = await catalog.search_games("电光", {"lang": "zh", "category": "arcade", "ai": "false"})
	_check("服务端 q+cat+ai 组合搜索命中", searched_games.ok and searched_games.data.get("items", []).any(func(x): return x.get("id", "") == game_id))
	var played: Dictionary = await engagement.record_play(game_id, 65000)
	var played_history: Dictionary = await engagement.history("zh")
	var played_detail = await catalog.game(game_id, "zh")
	var history_has_game := false
	if played_history["ok"]:
		for group in played_history["body"].get("groups",[]):
			if group.get("items",[]).any(func(x): return x.get("game",{}).get("id","") == game_id and int(x.get("minutes_played",0)) == 2): history_has_game = true
	_check("游玩结算写历史并原子增加 plays", played["ok"] and history_has_game and int(played_detail.data.get("plays",0)) == 1)
	var mine: Dictionary = await creation.my_games("zh")
	_check("创作中心读取本人作品真实进入/二创统计", mine["ok"] and mine["body"].get("items", []).any(
		func(x): return x.get("id", "") == game_id and int(x.get("plays", 0)) == 1 and int(x.get("forks", 0)) == 1))

	var cm: Dictionary = await community.comment(game_id, "好玩")
	_check("评论 → 201(作者由 token 注入)", cm["status"] == 201)
	var progressed_welfare: Dictionary = await commerce.welfare("zh")
	var progressed_achievements: Dictionary = await commerce.achievements("zh")
	var progress_by_id := {}
	for q in progressed_welfare["body"].get("quests", []): progress_by_id[str(q.get("id", ""))] = int(q.get("progress", 0))
	for a in progressed_achievements["body"].get("items", []): progress_by_id[str(a.get("id", ""))] = int(a.get("progress", 0))
	_check("服务端确认动作推进真实任务与成就", progressed_welfare["ok"] and progressed_achievements["ok"]
		and progress_by_id.get("quest_play_3", 0) == 1 and progress_by_id.get("quest_comment_1", 0) == 1
		and progress_by_id.get("quest_remix_1", 0) >= 1 and progress_by_id.get("ach_remix_pro", 0) >= 1
		and progress_by_id.get("ach_first_launch", 0) == 1 and progress_by_id.get("ach_social_butterfly", 0) == 1)

	var lk: Dictionary = await community.like_game(game_id)
	_check("点赞 → count=1", lk["ok"] and lk["body"]["count"] == 1)
	var real_profile = await catalog.user_profile(me_id, "zh")
	var real_works = await catalog.user_games(me_id, "works", "zh")
	_check("真实用户主页聚合作品/进入/二创/获赞", real_profile.ok and real_works.ok
		and real_works.data.get("items", []).size() == 1
		and int(real_profile.data.get("works", 0)) == 1 and int(real_profile.data.get("plays", 0)) == 1
		and int(real_profile.data.get("forks", 0)) == 1 and int(real_profile.data.get("likes", 0)) == 1)
	var fav: Dictionary = await community.favorite_game(game_id)
	var favs: Dictionary = await community.favorites()
	_check("收藏并从我的收藏读取", fav["ok"] and favs["ok"] and game_id in favs["body"].get("items", []))
	var unfav: Dictionary = await community.favorite_game(game_id, false)
	_check("取消收藏真实落库", unfav["ok"])

	var rk = await catalog.ranking("hot")
	var on_board := false
	if rk.ok:
		for item in rk.data["items"]:
			if item["id"] == game_id:
				on_board = true
	_check("热门榜含该游戏(跨域聚合 games+点赞)", on_board)
	var filtered_rank = await catalog.ranking("hot", {"lang": "zh", "runtime": "shooter", "category": "arcade"})
	_check("榜单按 Runtime 与分类筛选", filtered_rank.ok and filtered_rank.data.get("items", []).any(func(x): return x.get("id", "") == game_id))

	print("\n=== 集成结果: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
