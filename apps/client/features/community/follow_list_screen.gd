class_name FollowListScreen
extends ScreenBase

## 关注/粉丝列表:两段切换,行点击进创作者主页。

signal creator_opened(handle: String)

var seg := 0
## 服务端 /follow 注入的两段权威名单。每项 {handle,mutual,note}。
var _following: Array = []
var _followers: Array = []
var coordinator: CommunityCoordinator
var _follow_revision := 0

func _init(p_state: Node, p_coordinator: CommunityCoordinator = null) -> void:
	coordinator = p_coordinator
	if coordinator != null: coordinator.store.changed.connect(_on_store_changed)
	super(p_state)

func set_tab(i: int) -> void:
	seg = i
	rebuild()

## 首次展示时拉两段名单。
func refresh() -> void:
	if coordinator != null: await coordinator.load_follow_lists(state.locale)

func _on_store_changed() -> void:
	if coordinator.store.follow_revision == _follow_revision: return
	_follow_revision = coordinator.store.follow_revision
	_following = coordinator.store.following.duplicate(true)
	_followers = coordinator.store.followers.duplicate(true)
	rebuild.call_deferred()

func _build() -> void:
	var seg_ctrl := Widgets.segment(txt("follow_tabs"), seg, theme_name(), func(i: int) -> void:
		seg = i
		rebuild())
	seg_ctrl.name = "FollowSeg"
	content.add_child(seg_ctrl)

	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "PeopleList"
	var server: Array = _following if seg == 0 else _followers
	for it: Dictionary in server:
		list.add_child(_person_row(str(it.get("handle", "")), str(it.get("note", "")), bool(it.get("mutual", false))))
	if server.is_empty():
		list.add_child(empty_note(txt("his_empty")))
	content.add_child(list)

func _person_row(handle: String, note: String, mutual: bool) -> Control:
	var card := Widgets.card(theme_name())
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	row.add_child(Widgets.avatar(handle, theme_name(), 36))
	var col := Widgets.vbox(Tokens.SPACE_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Widgets.body(handle, theme_name()))
	col.add_child(Widgets.caption(note, theme_name()))
	row.add_child(col)
	if mutual:
		row.add_child(Widgets.badge(txt("following"), theme_name()))
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			creator_opened.emit(handle))
	return card
