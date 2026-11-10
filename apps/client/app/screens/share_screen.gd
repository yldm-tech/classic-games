class_name ShareScreen
extends ScreenBase

## Application-owned 分享面板：渠道本地化，平台动作经 PlatformBridge。

signal shared

var target: Dictionary = {}
const PlatformBridge := preload("res://platform/platform.gd")

func set_target(game: Dictionary) -> void:
	target = game
	rebuild()

func _build() -> void:
	content.add_child(Widgets.heading(txt("share_title"), 3, theme_name()))
	var grid := GridContainer.new()
	grid.name = "ChannelGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_2)
	var channels: Array = txt("share_channels")
	var channel_ids := _channel_ids()
	for i in channels.size():
		var b := Widgets.secondary_button(channels[i], theme_name())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ch: String = channels[i]
		b.pressed.connect(func() -> void:
			var url := CatalogLinks.game_url(str(target.get("id", "")))
			var title := GameCard.title_of(target, state.locale)
			if PlatformBridge.share(channel_ids[i], url, title):
				_toast(txt_fmt("toast_shared_fmt", [ch]))
				shared.emit()
			else:
				_toast(txt("share_failed")))
		grid.add_child(b)
	content.add_child(grid)

func _channel_ids() -> Array:
	match state.locale:
		"zh": return ["wechat", "wechat_moments", "qq", "copy"]
		"ja": return ["line", "x", "discord", "copy"]
		_: return ["messages", "x", "discord", "copy"]
