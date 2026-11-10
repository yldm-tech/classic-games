class_name GameCard
extends RefCounted

## Presentation-only 游戏卡：真实封面图、标题、作者、数据行与徽章。
## 封面用 assets/covers/ 的真实素材(docs/19 教训:不用字母占位);
## 仅 AI 刚生成、还没有封面的作品保留字母缩写兜底(原型同此约定)。

const Tokens := preload("res://shell/design_system/theme/tokens.gd")
const Strings := preload("res://i18n/strings.gd")
const Widgets := preload("res://shell/design_system/components/widgets.gd")

## 色调兜底(无封面时的底色,对照原型 tone)。
const TONES := {
	"ember": Color("#3A1608"), "moss": Color("#1D2A12"), "ocean": Color("#0E2233"),
	"plum": Color("#2A1430"), "steel": Color("#22262B"), "rust": Color("#33200E"),
}

## 标题:服务端数据带 title 字段直接用;原型种子游戏按语言取 Strings。
static func title_of(game: Dictionary, locale: String) -> String:
	if game.has("title"):
		return game["title"]
	if game.get("id", "") == "forged":
		return Strings.t(locale, "forged_title")
	return Strings.game_title(locale, game.get("id", ""))

## Whether Fork is offered for the game. The games API reports an empty "runtime" for a catalogue entry with no mod behind it (the showcase games of a development backend), and the backend refuses to fork one with GAME_HAS_NO_MOD. A summary without a "runtime" key (library and history items, local cards) says nothing either way, so it stays forkable.
static func forkable(game: Dictionary) -> bool:
	return not game.has("runtime") or str(game["runtime"]) != ""

static func desc_of(game: Dictionary, locale: String) -> String:
	if game.has("summary"):
		return game["summary"]
	if game.get("id", "") == "forged":
		return Strings.fmt(locale, "forged_desc", [game.get("prompt", "")])
	return Strings.game_desc(locale, game.get("id", ""))

## 封面:有素材给 TextureRect(运行时加载,不依赖 import),否则 tone 底 + 缩写。
static func cover(game: Dictionary, height: float) -> Control:
	return _rounded(_raw_cover(game, height), height)

static func _raw_cover(game: Dictionary, height: float) -> Control:
	var id: String = game.get("id", "")
	var path := "res://assets/covers/%s.png" % id
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			var tex := TextureRect.new()
			tex.texture = ImageTexture.create_from_image(img)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex.custom_minimum_size = Vector2(0, height)
			tex.clip_contents = true
			return tex
	var fallback := ColorRect.new()
	fallback.color = TONES.get(game.get("tone", "steel"), TONES["steel"])
	fallback.custom_minimum_size = Vector2(0, height)
	var glyph := Label.new()
	glyph.text = title_of(game, Strings.DEFAULT_LOCALE).left(2).to_upper() if not game.has("title") else String(game["title"]).left(2).to_upper()
	glyph.add_theme_font_size_override("font_size", Tokens.FONT_H2)
	glyph.add_theme_color_override("font_color", Color("#F2EDEC"))
	glyph.set_anchors_preset(Control.PRESET_CENTER)
	fallback.add_child(glyph)
	return fallback

static func _rounded(inner: Control, height: float = 0.0) -> Control:
	var host := PanelContainer.new()
	host.clip_contents = true
	if height > 0.0:
		host.custom_minimum_size = Vector2(0, height)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(Tokens.RADIUS_MD)
	sb.set_content_margin_all(0)
	host.add_theme_stylebox_override("panel", sb)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(inner)
	return host

## 宽度驱动、锁 16:10 的封面(对照原型 .fp-gamecard .cover { aspect-ratio: 16/10 })。
## 栅格卡用此变体:高度随单元格宽度按比例回算(Godot 容器不原生支持 aspect-ratio),桌面变宽也不被压扁。
static func cover_fill(game: Dictionary, ratio: float = 1.6) -> Control:
	var inner: Control = null
	var id: String = game.get("id", "")
	var path := "res://assets/covers/%s.png" % id
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			var tex := TextureRect.new()
			tex.texture = ImageTexture.create_from_image(img)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			inner = tex
	if inner == null:
		var fb := ColorRect.new()
		fb.color = TONES.get(game.get("tone", "steel"), TONES["steel"])
		var glyph := Label.new()
		glyph.text = title_of(game, Strings.DEFAULT_LOCALE).left(2).to_upper() if not game.has("title") else String(game["title"]).left(2).to_upper()
		glyph.add_theme_font_size_override("font_size", Tokens.FONT_H2)
		glyph.set_anchors_preset(Control.PRESET_CENTER)
		fb.add_child(glyph)
		inner = fb
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.clip_contents = true
	var host := _rounded(inner)
	# 宽度变了就按比例回算高度;加阈值收敛,避免布局抖动
	host.resized.connect(func() -> void:
		var h := host.size.x / ratio
		if absf(host.custom_minimum_size.y - h) > 0.5:
			host.custom_minimum_size.y = h)
	return host

## 栅格卡:封面 + 标题/作者 + 数据(玩过/二创,或服务端的点赞数)。on_open 点击回调。
static func build(game: Dictionary, locale: String, theme: String, on_open: Callable) -> Control:
	var card := Widgets.card(theme)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := Widgets.vbox(Tokens.SPACE_2)
	card.add_child(box)
	box.add_child(cover_fill(game))

	var title_row := Widgets.hbox(Tokens.SPACE_2)
	var title := Label.new()
	title.text = title_of(game, locale)
	title.add_theme_font_size_override("font_size", Tokens.FONT_H5)
	title.add_theme_color_override("font_color", Tokens.color(&"text_primary", theme))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if game.get("badge", "") == "ai" or game.get("ai_generated", false):
		title_row.add_child(Widgets.badge(Strings.t(locale, "forged_badge"), theme, true))
	elif game.get("badge", "") == "live":
		title_row.add_child(Widgets.badge(Strings.t(locale, "live"), theme))
	box.add_child(title_row)

	var by: String = game.get("by", game.get("author_id", ""))
	if by != "":
		box.add_child(Widgets.caption(Strings.fmt(locale, "by_fmt", [by]), theme))
	box.add_child(Widgets.caption(stats_line(game, locale), theme, &"text_secondary"))

	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on_open.call(game))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	return card

## 数据行:种子数据有 plays/forks;服务端游戏暂只有 likes(榜单)——按有什么显示什么。
static func stats_line(game: Dictionary, locale: String) -> String:
	var i18n := preload("res://i18n/i18n.gd")
	var parts: PackedStringArray = []
	if game.has("plays"):
		parts.append("%s %s" % [i18n.format_number(int(game["plays"]), locale), Strings.t(locale, "plays")])
	if game.has("forks"):
		parts.append("%s %s" % [i18n.format_number(int(game["forks"]), locale), Strings.t(locale, "forks_n")])
	if parts.is_empty() and game.has("likes"):
		parts.append("♥ %s" % i18n.format_number(int(game["likes"]), locale))
	return " · ".join(parts)
