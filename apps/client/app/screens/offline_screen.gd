class_name OfflineScreen
extends ScreenBase

## Application-owned 断网兜底：仅呈现状态并发出重试意图。

signal retry

func _build() -> void:
	var card := Widgets.card(theme_name(), &"surface_raised")
	var col := Widgets.vbox(Tokens.SPACE_3)
	card.add_child(col)
	var title := Widgets.heading(txt("off_title"), 2, theme_name())
	title.name = "OffTitle"
	col.add_child(title)
	col.add_child(Widgets.body(txt("off_desc"), theme_name(), &"text_secondary"))
	var btn := Widgets.primary_button(txt("off_retry"), theme_name())
	btn.name = "RetryButton"
	btn.pressed.connect(func() -> void: retry.emit())
	col.add_child(btn)
	content.add_child(card)
