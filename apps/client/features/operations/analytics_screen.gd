class_name AnalyticsScreen
extends ScreenBase

## Operations-owned admin analytics. 403 is an empty state, not a fake dashboard.

var operations: OperationsCoordinator
var _summary: Dictionary = {}
var _forbidden := false

func _init(p_state: Node, p_operations: OperationsCoordinator = null) -> void:
	operations = p_operations
	super(p_state)

func refresh() -> void:
	if operations == null:
		return
	var loaded: bool = await operations.load_analytics_summary()
	_summary = operations.store.analytics.duplicate(true)
	_forbidden = not loaded and operations.store.status == "ready"
	if not loaded:
		_summary = {}
	rebuild()

func invalidate_session() -> void:
	_summary = {}
	_forbidden = false
	super.invalidate_session()

func _build() -> void:
	content.add_child(Widgets.heading(txt("analytics_title"), 2, theme_name()))
	if _summary.is_empty():
		content.add_child(empty_note(txt("analytics_empty") if _forbidden or operations != null else txt("request_failed")))
		return
	var grid := GridContainer.new()
	grid.name = "AnalyticsGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	var i18n := preload("res://i18n/i18n.gd")
	var rows: Array = [
		["analytics_viewers", i18n.format_number(int(_summary.get("game_viewers", 0)), state.locale)],
		["analytics_forks", i18n.format_number(int(_summary.get("fork_starters", 0)), state.locale)],
		["analytics_fork_rate", _pct(_summary.get("fork_conversion", 0.0))],
		["analytics_ai_edits", i18n.format_number(int(_summary.get("ai_editors", 0)), state.locale)],
		["analytics_ai_pubs", i18n.format_number(int(_summary.get("ai_publishers", 0)), state.locale)],
		["analytics_ai_rate", _pct(_summary.get("ai_publish_rate", 0.0))],
		["analytics_depth", i18n.format_number(int(_summary.get("max_fork_depth", 0)), state.locale)],
	]
	for row: Array in rows:
		grid.add_child(Widgets.kpi_card(str(row[1]), txt(str(row[0])), theme_name()))
	content.add_child(grid)

func _pct(value: Variant) -> String:
	return "%.0f%%" % (float(value) * 100.0)
