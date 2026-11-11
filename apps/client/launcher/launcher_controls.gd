class_name LauncherControls
extends RefCounted

## The launcher's interactive and custom-drawn widgets, as inner classes: Pressable (base), FocusRow, Tab, Glyph, GlyphHint, ArtCard, Tile, Icon, GradientRect.
## All of them are presentation only: they hold no game data, read no store, and report user intent through two signals, `hovered` (the mouse entered) and `activated` (left click). A screen owns the focus state and tells each widget how to look with set_focused / set_selected; the widgets never use Godot's own keyboard focus.
##
## These classes must not refer to LauncherControls by name: an inner class that names its own outer script creates a reference cycle Godot reports as leaked resources at exit, which fails the test runner.

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")

# ---- gradient ----

## A linear gradient through any number of stops, e.g. GradientRect.new([[0.0, c0], [0.5, c1], [1.0, c2]], true) for a left-to-right fade.
class GradientRect:
	extends Control

	var stops: Array = []
	var horizontal := false

	func _init(p_stops: Array, p_horizontal: bool = false) -> void:
		stops = p_stops
		horizontal = p_horizontal
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		for i in stops.size() - 1:
			var from: float = stops[i][0]
			var to: float = stops[i + 1][0]
			var a: Color = stops[i][1]
			var b: Color = stops[i + 1][1]
			if horizontal:
				draw_polygon(
					PackedVector2Array([Vector2(size.x * from, 0), Vector2(size.x * to, 0), Vector2(size.x * to, size.y), Vector2(size.x * from, size.y)]),
					PackedColorArray([a, b, b, a]))
			else:
				draw_polygon(
					PackedVector2Array([Vector2(0, size.y * from), Vector2(size.x, size.y * from), Vector2(size.x, size.y * to), Vector2(0, size.y * to)]),
					PackedColorArray([a, a, b, b]))

# ---- icons ----

## Line icons drawn in a 24-unit box: "heart", "grid", "menu", "view", "monitor", "gamepad", and the achievement icons of draw_badge.
class Icon:
	extends Control

	## The kinds draw_badge knows.
	const BADGES: Array[String] = ["star", "bolt", "cup", "shield", "lock"]

	var kind := ""
	var color := T.FG

	func _init(p_kind: String, extent: float = 24.0, p_color: Color = T.FG) -> void:
		kind = p_kind
		color = p_color
		custom_minimum_size = Vector2(extent, extent)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var unit := minf(size.x, size.y) / 24.0
		draw_set_transform((size - Vector2(24, 24) * unit) / 2.0, 0.0, Vector2(unit, unit))
		var stroke := 1.6
		match kind:
			"heart":
				draw_circle(Vector2(8.7, 9.6), 3.9, color)
				draw_circle(Vector2(15.3, 9.6), 3.9, color)
				draw_colored_polygon(PackedVector2Array([Vector2(5.2, 11.4), Vector2(12, 7.6), Vector2(18.8, 11.4), Vector2(12, 20)]), color)
			"grid":
				for corner in [Vector2(3, 3), Vector2(14, 3), Vector2(3, 14), Vector2(14, 14)]:
					draw_rect(Rect2(corner, Vector2(7, 7)), color, false, stroke)
			"menu":
				for y in [7.0, 12.0, 17.0]:
					draw_line(Vector2(3, y), Vector2(21, y), color, 2.6)
			"view":
				draw_rect(Rect2(4, 5, 12, 9), color, false, 2.4)
				draw_rect(Rect2(9, 10, 12, 9), color, false, 2.4)
			"monitor":
				draw_rect(Rect2(3, 4, 18, 12), color, false, stroke)
				draw_line(Vector2(8, 20), Vector2(16, 20), color, stroke)
				draw_line(Vector2(12, 16), Vector2(12, 20), color, stroke)
			"gamepad":
				draw_polyline(PackedVector2Array([Vector2(6, 8), Vector2(18, 8), Vector2(21.5, 11), Vector2(22, 15), Vector2(20, 17), Vector2(17, 16.5), Vector2(15, 14), Vector2(9, 14), Vector2(7, 16.5), Vector2(4, 17), Vector2(2, 15), Vector2(2.5, 11), Vector2(6, 8)]), color, stroke, true)
				draw_line(Vector2(7, 10), Vector2(7, 12.6), color, stroke)
				draw_line(Vector2(5.7, 11.3), Vector2(8.3, 11.3), color, stroke)
				draw_circle(Vector2(17, 11.3), 1.0, color)
			_:
				draw_badge(self, kind, color, 1.8)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## The achievement icons (the catalog's `icon` field: "star", "bolt", "cup", "shield") and the "lock", as outlines in the 24-unit box. This is their only implementation: Icon draws them through it and so does PC mode's Symbol, each with its own stroke width. `canvas` must already be transformed to the 24-unit box. An unknown kind draws nothing.
	static func draw_badge(canvas: CanvasItem, p_kind: String, p_color: Color, stroke: float) -> void:
		match p_kind:
			"star":
				canvas.draw_polyline(PackedVector2Array([Vector2(12, 3), Vector2(14.6, 8.6), Vector2(20.7, 9.3), Vector2(16.2, 13.5), Vector2(17.4, 19.5), Vector2(12, 16.8), Vector2(6.6, 19.5), Vector2(7.8, 13.5), Vector2(3.3, 9.3), Vector2(9.4, 8.6), Vector2(12, 3)]), p_color, stroke, true)
			"bolt":
				canvas.draw_polyline(PackedVector2Array([Vector2(13, 2), Vector2(4, 14), Vector2(11, 14), Vector2(10, 22), Vector2(19, 10), Vector2(12, 10), Vector2(13, 2)]), p_color, stroke, true)
			"cup":
				canvas.draw_polyline(PackedVector2Array([Vector2(7, 8), Vector2(7, 4), Vector2(17, 4), Vector2(17, 8)]), p_color, stroke, true)
				canvas.draw_arc(Vector2(12, 8), 5.0, 0.0, PI, 24, p_color, stroke, true)
				canvas.draw_line(Vector2(7, 6), Vector2(4, 6), p_color, stroke, true)
				canvas.draw_arc(Vector2(7, 6), 3.0, PI / 2.0, PI, 12, p_color, stroke, true)
				canvas.draw_line(Vector2(17, 6), Vector2(20, 6), p_color, stroke, true)
				canvas.draw_arc(Vector2(17, 6), 3.0, 0.0, PI / 2.0, 12, p_color, stroke, true)
				canvas.draw_line(Vector2(12, 13), Vector2(12, 17), p_color, stroke, true)
				canvas.draw_line(Vector2(8, 20), Vector2(16, 20), p_color, stroke, true)
			"shield":
				var outline := PackedVector2Array([Vector2(12, 3), Vector2(20, 6), Vector2(20, 12)])
				for i in range(1, 9):
					outline.append(Vector2(20, 12).bezier_interpolate(Vector2(20, 17), Vector2(16.5, 20), Vector2(12, 21), i / 8.0))
				for i in range(1, 9):
					outline.append(Vector2(12, 21).bezier_interpolate(Vector2(7.5, 20), Vector2(4, 17), Vector2(4, 12), i / 8.0))
				outline.append_array(PackedVector2Array([Vector2(4, 6), Vector2(12, 3)]))
				canvas.draw_polyline(outline, p_color, stroke, true)
			"lock":
				canvas.draw_polyline(PackedVector2Array([Vector2(6, 11), Vector2(18, 11), Vector2(18, 20), Vector2(6, 20), Vector2(6, 11)]), p_color, stroke, true)
				canvas.draw_line(Vector2(8, 11), Vector2(8, 8), p_color, stroke, true)
				canvas.draw_arc(Vector2(12, 8), 4.0, PI, TAU, 16, p_color, stroke, true)
				canvas.draw_line(Vector2(16, 8), Vector2(16, 11), p_color, stroke, true)

# ---- pressable base ----

## Base of every clickable widget: a margin container that emits `hovered` and `activated`. Children are laid out by the container and never take the mouse themselves.
class Pressable:
	extends MarginContainer

	signal hovered
	signal activated

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(func() -> void: hovered.emit())

	func set_padding(left: float, top: float = 0.0, right: float = -1.0, bottom: float = -1.0) -> void:
		add_theme_constant_override("margin_left", roundi(left))
		add_theme_constant_override("margin_top", roundi(top))
		add_theme_constant_override("margin_right", roundi(left if right < 0.0 else right))
		add_theme_constant_override("margin_bottom", roundi(top if bottom < 0.0 else bottom))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				accept_event()
				activated.emit()

# ---- focus row ----

## A menu row: label, optional caption with an optional thin progress bar under it, optional right-aligned trailing note. Focused = 4px white bar on the left plus a white gradient fading to the right (or a flat tint with `flat_fill`, as side-panel rows use).
class FocusRow:
	extends Pressable

	var focused := false
	var flat_fill := false
	var danger := false

	var _label: Label
	var _sub: Label
	var _bar: Control
	var _bar_fill: ColorRect
	var _trailing: Label
	var _fill := 0.0
	var _tween: Tween

	func _init(label: String, sub: String = "", font_size: int = T.SIZE_ROW, min_height: float = T.ROW_HEIGHT) -> void:
		super()
		custom_minimum_size = Vector2(0, min_height)
		set_padding(T.ROW_PADDING)
		var row := W.hbox(24)
		add_child(row)
		_label = W.text(label, font_size, 400, T.fg(T.A_ROW_IDLE), 2)
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_label)
		var column := W.vbox(6)
		column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(column)
		_sub = W.text(sub, T.SIZE_SUB, 400, T.fg(T.A_SUB_IDLE))
		_sub.name = "Sub"
		_sub.visible = sub != ""
		column.add_child(_sub)
		_bar = Control.new()
		_bar.name = "Progress"
		_bar.custom_minimum_size = Vector2(180, 3)
		_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.visible = false
		var track := ColorRect.new()
		track.color = T.fg(0.2)
		track.size = Vector2(180, 3)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.add_child(track)
		_bar_fill = ColorRect.new()
		_bar_fill.color = T.FG
		_bar_fill.size = Vector2(0, 3)
		_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.add_child(_bar_fill)
		column.add_child(_bar)
		_trailing = W.text("", T.SIZE_SMALL, 400, T.fg(0.45), 2, true)
		_trailing.name = "Trailing"
		_trailing.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
		_trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_trailing.visible = false
		row.add_child(_trailing)

	func set_text(label: String, sub: String = "") -> void:
		_label.text = label
		_sub.text = sub
		_sub.visible = sub != ""

	func label_text() -> String:
		return _label.text

	func sub_text() -> String:
		return _sub.text

	## Show the thin bar under the caption filled to `ratio` (0..1). A ratio of 0 or less hides it.
	func set_progress(ratio: float) -> void:
		_bar.visible = ratio > 0.0
		_bar_fill.size = Vector2(180.0 * clampf(ratio, 0.0, 1.0), 3)

	func progress_visible() -> bool:
		return _bar.visible

	func set_trailing(note: String) -> void:
		_trailing.text = note
		_trailing.visible = note != ""

	func set_focused(on: bool, animate: bool = true) -> void:
		if on == focused and _tween == null and _fill == (1.0 if on else 0.0):
			return
		focused = on
		var idle := T.DANGER if danger else T.fg(T.A_BODY if flat_fill else T.A_ROW_IDLE)
		W.restyle(_label, 700 if on and not flat_fill else 400, (T.DANGER if danger else T.FG) if on else idle, 2)
		W.restyle(_sub, 400, T.fg(T.A_BODY if on else T.A_SUB_IDLE))
		if _tween != null:
			_tween.kill()
			_tween = null
		var target := 1.0 if on else 0.0
		if animate and is_inside_tree():
			_tween = create_tween()
			_tween.tween_method(_set_fill, _fill, target, T.FADE_ROW)
			_tween.finished.connect(func() -> void: _tween = null)
		else:
			_set_fill(target)

	func _set_fill(value: float) -> void:
		_fill = value
		queue_redraw()

	func _draw() -> void:
		if _fill <= 0.0:
			return
		if flat_fill:
			draw_rect(Rect2(Vector2.ZERO, size), T.fg(0.1 * _fill))
		else:
			draw_polygon(
				PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
				PackedColorArray([T.fg(T.A_FOCUS_FILL * _fill), T.fg(0.0), T.fg(0.0), T.fg(T.A_FOCUS_FILL * _fill)]))
		draw_rect(Rect2(0, 0, T.FOCUS_BAR, size.y), T.fg(_fill))

# ---- tab ----

## A top-level or in-page tab. Selected = bold white text with a 3px white underline along the bottom edge.
class Tab:
	extends Pressable

	var selected := false
	var idle_alpha := T.A_MUTED

	var _label: Label

	func _init(title: String, font_size: int = T.SIZE_NAV, height: float = T.NAV_HEIGHT) -> void:
		super()
		custom_minimum_size = Vector2(0, height)
		set_padding(18)
		_label = W.text(title, font_size, 400, T.fg(idle_alpha), 3)
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(_label)

	func set_title(title: String) -> void:
		_label.text = title

	var _count: Label

	## Show a small number after the title (how many items the tab holds).
	func set_count(count: int) -> void:
		if _count == null:
			var row := W.hbox(8)
			remove_child(_label)
			add_child(row)
			row.add_child(_label)
			_count = W.text("", T.SIZE_SUB, 400, T.fg(T.A_MUTED), 0, true)
			_count.name = "Count"
			_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(_count)
		_count.text = str(count)

	func count_text() -> String:
		return _count.text if _count != null else ""

	func set_selected(on: bool) -> void:
		selected = on
		W.restyle(_label, 700 if on else 400, T.FG if on else T.fg(idle_alpha), 3)
		queue_redraw()

	func _draw() -> void:
		if selected:
			draw_rect(Rect2(0, size.y - T.TAB_UNDERLINE, size.x, T.TAB_UNDERLINE), T.FG)

# ---- glyphs ----

## The picture of one gamepad button: a ring with a letter for A/B/X/Y, a rounded box for the shoulder buttons and triggers, a ring with an icon for Menu and View.
class Glyph:
	extends Control

	var action: StringName

	func _init(p_action: StringName) -> void:
		action = p_action
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		custom_minimum_size = Vector2(_width(), T.GLYPH_SIZE)

	func _is_box() -> bool:
		return action in [LauncherInput.LB, LauncherInput.RB, LauncherInput.LT, LauncherInput.RT]

	func _width() -> float:
		if not _is_box():
			return T.GLYPH_SIZE
		var caption := str(LauncherInput.GLYPH_TEXT[action])
		return ceilf(T.font(800, 0, true).get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T.SIZE_MICRO).x) + 14.0 + 3.0

	func _draw() -> void:
		var caption := str(LauncherInput.GLYPH_TEXT.get(action, ""))
		if _is_box():
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0, 0, 0, 0)
			# The design's 1.5px border at 70% white; a 2px border needs less alpha to carry the same weight.
			box.border_color = T.fg(0.55)
			box.set_border_width_all(2)
			box.set_corner_radius_all(roundi(T.RADIUS))
			box.anti_aliasing = true
			draw_style_box(box, Rect2(Vector2.ZERO, size))
			_draw_caption(caption, T.SIZE_MICRO, T.fg(0.85))
			return
		draw_arc(size / 2.0, T.GLYPH_SIZE / 2.0 - 1.0, 0.0, TAU, 48, T.FG, 2.0, true)
		if caption != "":
			_draw_caption(caption, T.SIZE_SMALL, T.FG)
		elif action == LauncherInput.MENU:
			for y in [-3.0, 0.0, 3.0]:
				draw_line(size / 2.0 + Vector2(-5, y), size / 2.0 + Vector2(5, y), T.FG, 1.6)
		elif action == LauncherInput.VIEW:
			draw_rect(Rect2(size / 2.0 + Vector2(-6, -5), Vector2(8, 6)), T.FG, false, 1.5)
			draw_rect(Rect2(size / 2.0 + Vector2(-2, -1), Vector2(8, 6)), T.FG, false, 1.5)

	func _draw_caption(caption: String, font_size: int, color: Color) -> void:
		var face := T.font(800, 0, true)
		var extent := face.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := (size.y - face.get_height(font_size)) / 2.0 + face.get_ascent(font_size)
		draw_string(face, Vector2((size.x - extent.x) / 2.0, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## A footer hint: glyph followed by what the button does. Clicking it emits `activated`; LauncherScreen.set_footer routes that to handle_action, so a click and the real button do the same thing.
class GlyphHint:
	extends Pressable

	var action: StringName

	var _label: Label

	func _init(p_action: StringName, caption: String) -> void:
		super()
		action = p_action
		custom_minimum_size = Vector2(0, T.FOOTER_HEIGHT)
		set_padding(12)
		var row := W.hbox(10)
		add_child(row)
		row.add_child(Glyph.new(p_action))
		_label = W.text(caption, T.SIZE_BODY, 400, T.fg(T.A_STRONG), 1)
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_label)

	func caption() -> String:
		return _label.text

# ---- game card ----

## Key-art card for a shelf: art with a progress bar along its bottom edge and an optional favourite badge, then the name and a short note underneath. Selected = larger, fully opaque, with a white ring.
class ArtCard:
	extends Pressable

	var game_id := ""
	var selected := false

	var _frame: Control
	var _art: LauncherKeyArt
	var _progress: ColorRect
	var _badge: Control
	var _ring: Control
	var _name: Label
	var _note: Label
	var _tween: Tween

	func _init(p_game_id: String, title: String = "", note: String = "") -> void:
		super()
		game_id = p_game_id
		size_flags_vertical = Control.SIZE_SHRINK_END
		modulate.a = 0.6
		var column := W.vbox(12)
		add_child(column)
		_frame = Control.new()
		_frame.name = "Frame"
		_frame.custom_minimum_size = T.CARD_SIZE
		_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_frame)
		var shadow := Panel.new()
		var shadow_style := StyleBoxFlat.new()
		shadow_style.bg_color = T.CARD_BG
		shadow_style.set_corner_radius_all(roundi(T.RADIUS))
		shadow_style.shadow_color = Color(0, 0, 0, 0.6)
		shadow_style.shadow_size = 40
		shadow_style.shadow_offset = Vector2(0, 20)
		shadow.add_theme_stylebox_override("panel", shadow_style)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(W.fill(shadow))
		var clip := Panel.new()
		var clip_style := StyleBoxFlat.new()
		clip_style.bg_color = T.CARD_BG
		clip_style.set_corner_radius_all(roundi(T.RADIUS))
		clip.add_theme_stylebox_override("panel", clip_style)
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(W.fill(clip))
		_art = LauncherKeyArt.new(p_game_id)
		_art.name = "Art"
		clip.add_child(W.fill(_art))
		var track := ColorRect.new()
		track.color = Color(0, 0, 0, 0.5)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		track.offset_top = -4
		clip.add_child(track)
		_progress = ColorRect.new()
		_progress.name = "Progress"
		_progress.color = T.FG
		_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress.anchor_top = 1.0
		_progress.anchor_bottom = 1.0
		_progress.anchor_right = 0.0
		_progress.offset_top = -4
		clip.add_child(_progress)
		_badge = _FavoriteBadge.new()
		_badge.name = "Favorite"
		_badge.visible = false
		_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_badge.offset_left = -38
		_badge.offset_right = -10
		_badge.offset_top = 10
		_badge.offset_bottom = 38
		clip.add_child(_badge)
		# The ring is the last child of the frame so the card's drop shadow cannot dim it.
		_ring = _Ring.new()
		_ring.visible = false
		_frame.add_child(W.fill(_ring))
		var caption := W.hbox(10)
		column.add_child(caption)
		_name = W.text(title, T.SIZE_BODY, 500, T.FG, 2)
		_name.name = "Name"
		caption.add_child(_name)
		_note = W.text(note, T.SIZE_SMALL, 400, T.fg(T.A_FAINT))
		_note.name = "Note"
		_note.size_flags_vertical = Control.SIZE_SHRINK_END
		caption.add_child(_note)

	func set_caption(title: String, note: String) -> void:
		_name.text = title
		_note.text = note

	func note_text() -> String:
		return _note.text

	## Fill of the bar along the bottom of the art, 0..1.
	func set_progress(ratio: float) -> void:
		_progress.anchor_right = clampf(ratio, 0.0, 1.0)

	func progress() -> float:
		return _progress.anchor_right

	func set_favorite(on: bool) -> void:
		_badge.visible = on

	func is_favorite_shown() -> bool:
		return _badge.visible

	func set_selected(on: bool, animate: bool = true) -> void:
		selected = on
		var extent := T.CARD_SIZE_SELECTED if on else T.CARD_SIZE
		var alpha := 1.0 if on else 0.6
		if _tween != null:
			_tween.kill()
			_tween = null
		if animate and is_inside_tree():
			_tween = create_tween().set_parallel(true)
			_tween.tween_property(_frame, "custom_minimum_size", extent, T.RESIZE_CARD)
			_tween.tween_property(self, "modulate:a", alpha, T.RESIZE_CARD)
			_tween.finished.connect(func() -> void: _tween = null)
		else:
			_frame.custom_minimum_size = extent
			modulate.a = alpha
		_ring.visible = on

## White outline drawn just outside its parent's rectangle, leaving a gap: the selected state of a card or tile.
class _Ring:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size).grow(T.CARD_RING_OFFSET + T.CARD_RING / 2.0), T.FG, false, T.CARD_RING)

class _FavoriteBadge:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var heart := Icon.new("heart", 14.0, T.FAVORITE)
		heart.position = Vector2(7, 7)
		heart.size = Vector2(14, 14)
		add_child(heart)

	func _draw() -> void:
		draw_circle(size / 2.0, size.x / 2.0, T.bg(0.7))

# ---- tile ----

## An outlined shelf tile with an icon and a title, plus a caption underneath (the "all games" entry at the end of a shelf).
class Tile:
	extends Pressable

	var focused := false

	var _box: Panel
	var _ring: Control
	var _caption: Label

	func _init(icon_kind: String, title: String, caption: String = "") -> void:
		super()
		size_flags_vertical = Control.SIZE_SHRINK_END
		var column := W.vbox(12)
		add_child(column)
		_box = Panel.new()
		_box.name = "Box"
		_box.custom_minimum_size = T.CARD_SIZE
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = T.fg(0.06)
		style.border_color = T.fg(0.3)
		style.set_border_width_all(1)
		style.set_corner_radius_all(roundi(T.RADIUS))
		_box.add_theme_stylebox_override("panel", style)
		column.add_child(_box)
		_ring = _Ring.new()
		_ring.visible = false
		_box.add_child(W.fill(_ring))
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(W.fill(center))
		var inner := W.vbox(10)
		center.add_child(inner)
		var icon := Icon.new(icon_kind, 28.0)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		inner.add_child(icon)
		var label := W.text(title, T.SIZE_TOAST, 400, T.FG, 3)
		label.name = "Title"
		inner.add_child(label)
		_caption = W.text(caption, T.SIZE_SMALL, 400, T.fg(T.A_FAINT), 1)
		_caption.name = "Caption"
		column.add_child(_caption)

	func caption_text() -> String:
		return _caption.text

	func set_focused(on: bool) -> void:
		focused = on
		_ring.visible = on
