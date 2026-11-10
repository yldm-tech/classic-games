class_name LibraryScreen
extends ScreenBase

## 我的库子页:我的作品 / 我的二创 / 我喜欢的——各自独立一页,只放对应作品网格。
## (侧栏三项原先都跳「我的」tab,身份卡/数据/等级一模一样、只有底部段控不同,看着没区别;
##  改为各自一个有标题的子页,三项才有不同去处。)

signal game_opened(game: Dictionary)

# kind → {对应作品 id 列表, 标题 key}。id 与 ProfileScreen 作品段一致。
const COLLECTIONS := {
	"games": {"title": "side_my_games"},
	"forks": {"title": "side_my_forks"},
	"liked": {"title": "side_liked"},
}

var kind := "games"
var cols := 2
## 服务端 /users/:id/games 注入的作品；未加载完成前不渲染占位卡。
var _server: Array = []
var _loaded := false
var engagement: EngagementCoordinator

func _init(p_state: Node, p_engagement: EngagementCoordinator = null) -> void:
	engagement = p_engagement
	super(p_state)

func title_key() -> String:
	return COLLECTIONS[kind]["title"]

## 由 AppRoot 在导航前调用:选集合 + 按布局给列数。切集合先清掉上一份服务端数据。
func set_collection(p_kind: String, p_cols: int = 2) -> void:
	kind = p_kind if COLLECTIONS.has(p_kind) else "games"
	cols = maxi(1, p_cols)
	_server = []
	_loaded = false
	rebuild()

## AppRoot 拉到该集合的真实作品后注入。
func bind_games(items: Array) -> void:
	_server = items
	_loaded = true
	rebuild()

func refresh() -> void:
	await load_collection()

func load_collection() -> void:
	var requested_kind := kind
	if engagement != null and await engagement.load_library(requested_kind, state.locale) and kind == requested_kind:
		bind_games(engagement.store.library_items)

func _build() -> void:
	var grid := GridContainer.new()
	grid.name = "LibraryGrid"
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_3)
	if _loaded:
		for g: Dictionary in _server:
			grid.add_child(GameCard.build(g, state.locale, theme_name(),
				func(gg: Dictionary) -> void: game_opened.emit(gg)))
		if _server.is_empty():
			grid.add_child(empty_note(txt("works_empty")))
	content.add_child(grid)
