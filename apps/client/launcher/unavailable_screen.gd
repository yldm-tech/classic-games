class_name LauncherUnavailableScreen
extends LauncherScreen

## Stands in for a screen that has not been built yet (see LauncherRoot.SCREENS) and says so plainly. It keeps the top-level tabs and the back button working while the real screens are added one by one.

func build() -> void:
	var scrim := ColorRect.new()
	scrim.color = T.deep(0.78)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(scrim))
	var column := W.vbox(16)
	column.position = Vector2(T.MARGIN, 300)
	add_child(column)
	var title := W.text(t("launcher.unavailable.title"), T.SIZE_PANEL_TITLE, 900, T.FG, 4)
	title.name = "Title"
	column.add_child(title)
	column.add_child(W.text(t("launcher.unavailable.body"), T.SIZE_TAGLINE, 300, T.fg(T.A_BODY), 1))

func on_enter(_args: Dictionary) -> void:
	set_footer([[In.BACK, t("launcher.common.back")]])

func shows_nav() -> bool:
	return screen_id in LauncherRoot.NAV_TABS

func backdrop() -> Dictionary:
	var recents := shell.store.recents()
	var game: String = recents[0] if not recents.is_empty() and LauncherCatalog.has(recents[0]) else LauncherCatalog.ids()[0]
	return {"layer": &"blur", "game": game}
