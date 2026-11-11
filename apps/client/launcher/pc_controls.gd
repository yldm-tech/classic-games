class_name LauncherPcControls
extends RefCounted

## The widgets of PC mode, as inner classes: Clickable (base), Pill, IconButton, Check, SideRow, GameRow, LibraryCard, ListRow, AchievementCard, StatTile, Menu, SearchField, Flow, plus the Symbol icons and the Paint helpers.
## Like LauncherControls they are presentation only. They differ in what a desktop pointer needs: every Clickable shows hover and pressed states by itself, reports a right click (`context_requested`) and a double click (`double_clicked`), and can show a keyboard focus ring that LauncherPcMode moves around.
##
## These classes must not refer to LauncherPcControls by name (see the note in LauncherControls); they use the constants below and each other instead.

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")
const P := preload("res://launcher/pc_tokens.gd")

# ---- paint helpers ----

class Paint:
	static func box(fill: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: float = T.RADIUS) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(border_width)
		style.set_corner_radius_all(roundi(radius))
		style.anti_aliasing = true
		return style

	## A vertical scroll area with a thin always-readable scrollbar. The mouse wheel scrolls it wherever the pointer is inside.
	static func scroll() -> ScrollContainer:
		var area := ScrollContainer.new()
		area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		area.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var bar := area.get_v_scroll_bar()
		bar.custom_minimum_size = Vector2(P.SCROLLBAR_WIDTH, 0)
		var radius := P.SCROLLBAR_WIDTH / 2.0
		bar.add_theme_stylebox_override("scroll", box(T.fg(0.04), Color(0, 0, 0, 0), 0, radius))
		bar.add_theme_stylebox_override("scroll_focus", box(T.fg(0.04), Color(0, 0, 0, 0), 0, radius))
		bar.add_theme_stylebox_override("grabber", box(T.fg(0.22), Color(0, 0, 0, 0), 0, radius))
		bar.add_theme_stylebox_override("grabber_highlight", box(T.fg(0.36), Color(0, 0, 0, 0), 0, radius))
		bar.add_theme_stylebox_override("grabber_pressed", box(T.fg(0.5), Color(0, 0, 0, 0), 0, radius))
		return area

	## Key art clipped to a rounded rectangle.
	static func art(game_id: String, radius: float) -> Panel:
		var clip := Panel.new()
		clip.add_theme_stylebox_override("panel", box(T.CARD_BG, Color(0, 0, 0, 0), 0, radius))
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var picture := LauncherKeyArt.new(game_id)
		picture.name = "Art"
		clip.add_child(W.fill(picture))
		return clip

	## A label that is cut with an ellipsis instead of widening its parent.
	static func clipped(label: Label) -> Label:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return label

	static func heart() -> PackedVector2Array:
		var points := PackedVector2Array([Vector2(12, 21)])
		for i in 13:
			points.append(Vector2(7.9, 9.4) + Vector2.from_angle(deg_to_rad(150.0 + 15.0 * i)) * 4.7)
		for i in 13:
			points.append(Vector2(16.1, 9.4) + Vector2.from_angle(deg_to_rad(210.0 + 15.0 * i)) * 4.7)
		return points

# ---- icons ----

## Line icons drawn in a 24-unit box: "search", "close", "play", "dots", "sliders", "grid", "list", "heart", "heart_line", "check", "chevron", "pad", and the achievement icons ("star", "bolt", "cup", "shield", "lock"), which LauncherControls.Icon.draw_badge draws for both modes.
class Symbol:
	extends Control

	var kind := "":
		set(value):
			kind = value
			queue_redraw()
	var color := T.FG:
		set(value):
			color = value
			queue_redraw()
	var stroke := 2.0

	func _init(p_kind: String, extent: float = 16.0, p_color: Color = T.FG, p_stroke: float = 2.0) -> void:
		kind = p_kind
		color = p_color
		stroke = p_stroke
		custom_minimum_size = Vector2(extent, extent)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _line(points: Array, closed: bool = false) -> void:
		var path := PackedVector2Array(points)
		if closed:
			path.append(path[0])
		draw_polyline(path, color, stroke, true)

	func _draw() -> void:
		var unit := minf(size.x, size.y) / 24.0
		draw_set_transform((size - Vector2(24, 24) * unit) / 2.0, 0.0, Vector2(unit, unit))
		match kind:
			"search":
				draw_arc(Vector2(11, 11), 7.0, 0.0, TAU, 40, color, stroke, true)
				_line([Vector2(16, 16), Vector2(20, 20)])
			"close":
				_line([Vector2(6, 6), Vector2(18, 18)])
				_line([Vector2(18, 6), Vector2(6, 18)])
			"play":
				draw_colored_polygon(PackedVector2Array([Vector2(6, 3.5), Vector2(20, 12), Vector2(6, 20.5)]), color)
			"dots":
				for x in [5.0, 12.0, 19.0]:
					draw_circle(Vector2(x, 12), 1.9, color, true, -1.0, true)
			"sliders":
				_line([Vector2(4, 7), Vector2(13, 7)])
				_line([Vector2(17, 7), Vector2(20, 7)])
				_line([Vector2(4, 17), Vector2(7, 17)])
				_line([Vector2(11, 17), Vector2(20, 17)])
				draw_arc(Vector2(15, 7), 2.0, 0.0, TAU, 20, color, stroke, true)
				draw_arc(Vector2(9, 17), 2.0, 0.0, TAU, 20, color, stroke, true)
			"grid":
				for corner in [Vector2(3, 3), Vector2(14, 3), Vector2(3, 14), Vector2(14, 14)]:
					draw_rect(Rect2(corner, Vector2(7, 7)), color, false, stroke)
			"list":
				for y in [6.0, 12.0, 18.0]:
					_line([Vector2(8, y), Vector2(21, y)])
					_line([Vector2(3, y), Vector2(4.2, y)])
			"heart":
				draw_colored_polygon(Paint.heart(), color)
			"heart_line":
				draw_polyline(Paint.heart() + PackedVector2Array([Vector2(12, 21)]), color, stroke * 0.85, true)
			"check":
				_line([Vector2(5, 12.5), Vector2(10, 17.5), Vector2(19, 7)])
			"chevron":
				_line([Vector2(7, 10), Vector2(12, 15), Vector2(17, 10)])
			"pad":
				draw_colored_polygon(PackedVector2Array([Vector2(6, 8), Vector2(18, 8), Vector2(21.5, 10.5), Vector2(22.5, 14.5), Vector2(20.5, 17), Vector2(17.5, 16.5), Vector2(15, 13.5), Vector2(9, 13.5), Vector2(6.5, 16.5), Vector2(3.5, 17), Vector2(1.5, 14.5), Vector2(2.5, 10.5)]), color)
			_:
				# The achievement icons have one implementation, shared with the console screens.
				LauncherControls.Icon.draw_badge(self, kind, color, stroke)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---- clickable base ----

## Base of every PC-mode button. On top of Pressable's `hovered` and `activated` it tracks the pointer (`hover`, `down`) for its own look, emits `context_requested` on a right click and, when `wants_double` is set, `double_clicked` in place of the second `activated` of a double click. `set_focus_ring` shows the keyboard focus outline.
class Clickable:
	extends LauncherControls.Pressable

	signal context_requested
	signal double_clicked

	var hover := false
	var down := false
	var focus_ring := false
	var wants_double := false

	var _double := false

	func _init() -> void:
		super()
		mouse_entered.connect(_on_pointer.bind(true))
		mouse_exited.connect(_on_pointer.bind(false))

	func _on_pointer(inside: bool) -> void:
		hover = inside
		if not inside:
			down = false
		_restyle()

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button == null:
			return
		if button.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			if not button.pressed:
				context_requested.emit()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		if button.pressed:
			down = true
			_double = button.double_click
			_restyle()
			return
		down = false
		_restyle()
		if not Rect2(Vector2.ZERO, size).has_point(button.position):
			return
		if _double and wants_double:
			double_clicked.emit()
		else:
			activated.emit()

	func set_focus_ring(on: bool) -> void:
		if focus_ring != on:
			focus_ring = on
			queue_redraw()

	## Update colours of children for the current hover / pressed / selected state. The default only repaints.
	func _restyle() -> void:
		queue_redraw()

	## Paint the background for the current state.
	func _paint() -> void:
		pass

	## Where the keyboard focus ring is drawn: along the inside of the edge by default.
	func _ring_rect() -> Rect2:
		return Rect2(Vector2.ZERO, size)

	func _draw() -> void:
		_paint()
		if focus_ring:
			draw_style_box(Paint.box(Color(0, 0, 0, 0), T.FG, roundi(P.FOCUS_RING), T.RADIUS + 2.0), _ring_rect())

# ---- text buttons ----

## A button with a caption and an optional icon in front. PRIMARY is the filled white call to action, OUTLINE the bordered secondary button, QUIET a smaller bordered one, LINK accent-coloured text, CHIP a filter chip that is filled while `on`.
class Pill:
	extends Clickable

	const PRIMARY := 0
	const OUTLINE := 1
	const QUIET := 2
	const LINK := 3
	const CHIP := 4

	var style := OUTLINE
	var on := false

	var _row: HBoxContainer
	var _label: Label
	var _note: Label
	var _icon: Symbol
	var _spacing := 0.0

	func _init(caption: String, p_style: int = OUTLINE, height: float = 36.0, font_size: int = P.SIZE_TEXT, pad: float = 16.0, icon_kind: String = "", spacing: float = 0.0) -> void:
		super()
		style = p_style
		_spacing = spacing
		custom_minimum_size = Vector2(0, height)
		set_padding(pad, 0)
		_row = W.hbox(8)
		_row.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(_row)
		if icon_kind != "":
			_icon = Symbol.new(icon_kind, font_size - 2.0)
			_row.add_child(_icon)
		_label = W.text(caption, font_size, 400, T.FG, spacing)
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(_label)
		_restyle()

	func caption() -> String:
		return _label.text

	func set_caption(text: String) -> void:
		_label.text = text

	## A dimmer second text after the caption (the count on a filter chip).
	func set_note(text: String) -> void:
		if _note == null:
			_note = W.text("", _label.label_settings.font_size, 400, T.FG, 0, true)
			_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_row.add_child(_note)
		_note.text = text
		_restyle()

	## A small bordered key name after the caption ("F11").
	func add_keycap(text: String) -> void:
		var cap := PanelContainer.new()
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var box := Paint.box(Color(0, 0, 0, 0), P.BORDER_STRONG, 1, 3.0)
		box.content_margin_left = 4
		box.content_margin_right = 4
		cap.add_theme_stylebox_override("panel", box)
		cap.add_child(W.text(text, P.SIZE_KEYCAP, 400, P.TEXT_MUTED, 0, true))
		_row.add_child(cap)

	## Add a trailing icon (the chevron of a dropdown).
	func add_trailing_icon(kind: String) -> void:
		_row.add_child(Symbol.new(kind, 14.0, P.TEXT_SOFT))

	func set_on(value: bool) -> void:
		on = value
		_restyle()

	func _ink() -> Color:
		match style:
			PRIMARY:
				return T.BG
			LINK:
				return P.ACCENT if not hover else T.FG
			CHIP:
				return T.BG if on else P.TEXT_BODY
			QUIET:
				return P.TEXT_BODY if not hover else T.FG
		return T.FG

	func _restyle() -> void:
		var ink := _ink()
		var size_px := _label.label_settings.font_size
		_label.label_settings = T.label_settings(size_px, 700 if style == PRIMARY else 400, ink, _spacing)
		if _icon != null:
			_icon.color = ink
		if _note != null:
			_note.label_settings = T.label_settings(size_px, 400, Color(ink, 0.7), 0, true)
		queue_redraw()

	## A white ring would vanish on the filled white button, so there it sits outside with a gap.
	func _ring_rect() -> Rect2:
		return Rect2(Vector2.ZERO, size).grow(4.0) if style == PRIMARY or (style == CHIP and on) else Rect2(Vector2.ZERO, size)

	func _paint() -> void:
		var fill := Color(0, 0, 0, 0)
		var border := Color(0, 0, 0, 0)
		match style:
			PRIMARY:
				fill = T.fg(0.8) if down else (Color.WHITE if hover else T.FG)
			OUTLINE:
				fill = T.fg(P.A_PRESSED) if down else (T.fg(0.08) if hover else T.bg(0.5))
				border = T.fg(0.6 if hover else 0.35)
			QUIET:
				fill = T.fg(P.A_PRESSED) if down else (T.fg(P.A_HOVER) if hover else Color(0, 0, 0, 0))
				border = P.BORDER_HOVER if hover else P.BORDER_STRONG
			LINK:
				fill = T.fg(P.A_HOVER) if hover else Color(0, 0, 0, 0)
			CHIP:
				if on:
					fill = Color.WHITE if hover else T.FG
					border = fill
				else:
					fill = T.fg(P.A_PRESSED) if down else (T.fg(P.A_HOVER) if hover else Color(0, 0, 0, 0))
					border = P.BORDER_HOVER if hover else P.BORDER_STRONG
		draw_style_box(Paint.box(fill, border, 1 if border.a > 0.0 else 0), Rect2(Vector2.ZERO, size))

## A square button that shows one icon. OUTLINE is bordered (beside the hero buttons), PLAIN has no chrome until hovered, DISC is the dark circle on key art, SEGMENT one half of a two-way switch that is filled while `on`.
class IconButton:
	extends Clickable

	const OUTLINE := 0
	const PLAIN := 1
	const DISC := 2
	const SEGMENT := 3

	var style := OUTLINE
	var on := false
	var tint := T.FG

	var _icon: Symbol

	func _init(kind: String, extent: float = 48.0, icon_extent: float = 18.0, p_style: int = OUTLINE) -> void:
		super()
		style = p_style
		custom_minimum_size = Vector2(extent, extent)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icon = Symbol.new(kind, icon_extent)
		add_child(_icon)
		if style == PLAIN:
			tint = P.TEXT_SOFT
		_restyle()

	func set_icon(kind: String, color: Color) -> void:
		_icon.kind = kind
		tint = color
		_restyle()

	func icon_kind() -> String:
		return _icon.kind

	func set_on(value: bool) -> void:
		on = value
		_restyle()

	func _restyle() -> void:
		_icon.color = T.FG if style == PLAIN and hover and tint == P.TEXT_SOFT else tint
		queue_redraw()

	func _paint() -> void:
		var area := Rect2(Vector2.ZERO, size)
		match style:
			OUTLINE:
				draw_style_box(Paint.box(T.fg(P.A_PRESSED) if down else (T.fg(0.08) if hover else T.bg(0.5)), T.fg(0.6 if hover else 0.35), 1), area)
			PLAIN:
				if hover:
					draw_style_box(Paint.box(T.fg(P.A_PRESSED if down else 0.08)), area)
			DISC:
				draw_circle(size / 2.0, size.x / 2.0, T.bg(0.9 if hover else 0.7), true, -1.0, true)
			SEGMENT:
				if on or hover:
					draw_rect(area, T.fg(P.A_PRESSED if on else 0.08))

## A check box with its label.
class Check:
	extends Clickable

	var checked := false

	var _box: Control
	var _mark: Symbol

	func _init(caption: String) -> void:
		super()
		custom_minimum_size = Vector2(0, 30)
		set_padding(6, 0)
		var row := W.hbox(8)
		add_child(row)
		_box = Control.new()
		_box.custom_minimum_size = Vector2(16, 16)
		_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.draw.connect(_draw_box)
		row.add_child(_box)
		_mark = Symbol.new("check", 14.0, T.BG, 3.0)
		_mark.position = Vector2(1, 1)
		_mark.size = Vector2(14, 14)
		_box.add_child(_mark)
		var label := W.text(caption, P.SIZE_TEXT, 400, P.TEXT_SOFT)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		set_checked(false)

	func set_checked(value: bool) -> void:
		checked = value
		_mark.visible = value
		_box.queue_redraw()

	func _restyle() -> void:
		_box.queue_redraw()

	func _draw_box() -> void:
		var area := Rect2(Vector2.ZERO, _box.size)
		if checked:
			_box.draw_style_box(Paint.box(T.FG, T.FG, 1, 3.0), area)
		else:
			_box.draw_style_box(Paint.box(T.fg(P.A_HOVER) if hover else Color(0, 0, 0, 0), P.TEXT_MUTED if hover else P.BORDER_HOVER, 1, 3.0), area)

# ---- sidebar rows ----

## A sidebar navigation row: a label and a right-aligned count. Selected = tinted fill with a 3px bar on the left.
class SideRow:
	extends Clickable

	var selected := false
	var accent := false

	var _label: Label
	var _count: Label

	func _init(caption: String, p_accent: bool = false) -> void:
		super()
		accent = p_accent
		custom_minimum_size = Vector2(0, P.SIDE_ROW_HEIGHT)
		set_padding(12, 0)
		var row := W.hbox(8)
		add_child(row)
		_label = Paint.clipped(W.text(caption, P.SIZE_TEXT if accent else P.SIZE_ROW, 400, P.TEXT_BODY))
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_label)
		_count = W.text("", P.SIZE_NOTE, 400, P.TEXT_MUTED, 0, true)
		_count.name = "Count"
		_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_count)
		_restyle()

	func set_count(value: int) -> void:
		_count.text = str(value)

	func count_text() -> String:
		return _count.text

	func label_text() -> String:
		return _label.text

	func set_selected(value: bool) -> void:
		selected = value
		_restyle()

	func _restyle() -> void:
		var ink := P.ACCENT if accent else (T.FG if selected else P.TEXT_BODY)
		_label.label_settings = T.label_settings(_label.label_settings.font_size, 700 if selected and not accent else 400, ink)
		queue_redraw()

	func _paint() -> void:
		var area := Rect2(Vector2.ZERO, size)
		if selected:
			draw_style_box(Paint.box(T.fg(P.A_SELECTED)), area)
			draw_rect(Rect2(0, 0, P.SIDE_BAR, size.y), P.ACCENT if accent else T.FG)
		elif hover:
			draw_style_box(Paint.box(T.fg(P.A_PRESSED if down else P.A_HOVER)), area)

## A game in the sidebar list: thumbnail, name, one status line and a heart when it is a favourite.
class GameRow:
	extends Clickable

	var game_id := ""
	var selected := false

	var _name: Label
	var _status: Label
	var _heart: Symbol

	func _init(p_game_id: String) -> void:
		super()
		game_id = p_game_id
		wants_double = true
		set_padding(10, 8)
		var row := W.hbox(12)
		add_child(row)
		var thumb := Paint.art(p_game_id, 2.0)
		thumb.custom_minimum_size = P.THUMB_SIZE
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(thumb)
		var column := W.vbox(3)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(column)
		_name = Paint.clipped(W.text("", P.SIZE_ROW, 600))
		_name.name = "Name"
		column.add_child(_name)
		_status = Paint.clipped(W.text("", P.SIZE_NOTE, 400, P.TEXT_MUTED))
		_status.name = "Status"
		column.add_child(_status)
		_heart = Symbol.new("heart", 12.0, T.FAVORITE)
		_heart.name = "Favorite"
		row.add_child(_heart)

	func update(model: Dictionary) -> void:
		_name.text = str(model["name"])
		_status.text = str(model["status"])
		_heart.visible = bool(model["favorite"])
		selected = bool(model["selected"])
		queue_redraw()

	func name_text() -> String:
		return _name.text

	func status_text() -> String:
		return _status.text

	func is_favorite_shown() -> bool:
		return _heart.visible

	func _paint() -> void:
		var area := Rect2(Vector2.ZERO, size)
		if selected:
			draw_style_box(Paint.box(T.fg(P.A_SELECTED)), area)
			draw_rect(Rect2(0, 0, P.SIDE_BAR, size.y), T.FG)
		elif hover:
			draw_style_box(Paint.box(T.fg(P.A_PRESSED if down else P.A_HOVER)), area)

# ---- library items ----

## A game in the library grid: key art with the achievement progress along its bottom edge and a favourite button in the corner, then the name and one line of facts. Selected = white ring; the pointer adds a thin outline and reveals the favourite button.
class LibraryCard:
	extends Clickable

	signal favorite_pressed

	var game_id := ""
	var selected := false

	var _frame: Control
	var _progress: ColorRect
	var _outline: Control
	var _heart: IconButton
	var _name: Label
	var _meta: Label
	var _favorite := false

	func _init(p_game_id: String) -> void:
		super()
		game_id = p_game_id
		wants_double = true
		var column := W.vbox(10)
		add_child(column)
		_frame = Control.new()
		_frame.name = "Frame"
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_frame)
		var clip := Paint.art(p_game_id, T.RADIUS)
		_frame.add_child(W.fill(clip))
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
		_outline = Control.new()
		_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_outline.draw.connect(_draw_outline)
		_frame.add_child(W.fill(_outline))
		_heart = IconButton.new("heart_line", 32.0, 14.0, IconButton.DISC)
		_heart.name = "Favorite"
		# PASS keeps the card hovered while the pointer is on the button.
		_heart.mouse_filter = Control.MOUSE_FILTER_PASS
		_heart.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_heart.offset_left = -40
		_heart.offset_right = -8
		_heart.offset_top = 8
		_heart.offset_bottom = 40
		_heart.activated.connect(func() -> void: favorite_pressed.emit())
		_frame.add_child(_heart)
		var text := W.vbox(3)
		column.add_child(text)
		_name = Paint.clipped(W.text("", P.SIZE_NAME, 700, T.FG, 1))
		_name.name = "Name"
		text.add_child(_name)
		_meta = Paint.clipped(W.text("", P.SIZE_NOTE, 400, P.TEXT_MUTED))
		_meta.name = "Meta"
		text.add_child(_meta)
		_restyle()

	## Height of the card when it is `width` wide: 16:9 art plus the two text lines. Flow asks for it.
	func height_for(width: float) -> float:
		_frame.custom_minimum_size = Vector2(0, roundf(width * 9.0 / 16.0))
		return _frame.custom_minimum_size.y + P.CARD_TEXT_HEIGHT

	func update(model: Dictionary) -> void:
		_name.text = str(model["name"])
		_meta.text = str(model["meta"])
		_progress.anchor_right = clampf(float(model["ratio"]), 0.0, 1.0)
		_favorite = bool(model["favorite"])
		_heart.set_icon("heart" if _favorite else "heart_line", T.FAVORITE if _favorite else T.FG)
		selected = bool(model["selected"])
		_restyle()

	func name_text() -> String:
		return _name.text

	func meta_text() -> String:
		return _meta.text

	func progress() -> float:
		return _progress.anchor_right

	func is_favorite_shown() -> bool:
		return _heart.visible and _favorite

	func _restyle() -> void:
		_heart.visible = _favorite or hover
		_outline.queue_redraw()

	func _draw_outline() -> void:
		var area := Rect2(Vector2.ZERO, _outline.size)
		if selected:
			_outline.draw_rect(area.grow(T.CARD_RING_OFFSET + T.CARD_RING / 2.0), T.FG, false, T.CARD_RING)
		elif hover:
			_outline.draw_style_box(Paint.box(Color(0, 0, 0, 0), T.fg(0.45), 1), area)
		if focus_ring and not selected:
			_outline.draw_rect(area.grow(T.CARD_RING_OFFSET + T.CARD_RING / 2.0), T.fg(0.5), false, T.CARD_RING)

	func set_focus_ring(on: bool) -> void:
		focus_ring = on
		_outline.queue_redraw()

	func _draw() -> void:
		pass

## A game in the library's list layout: thumbnail, name, genre, players, play time, achievement progress and a favourite button.
class ListRow:
	extends Clickable

	signal favorite_pressed

	var game_id := ""
	var selected := false

	var _name: Label
	var _genre: Label
	var _players: Label
	var _time: Label
	var _fill: ColorRect
	var _heart: IconButton
	var _favorite := false

	func _init(p_game_id: String) -> void:
		super()
		game_id = p_game_id
		wants_double = true
		set_padding(10, 8)
		var row := W.hbox(16)
		add_child(row)
		var thumb := Paint.art(p_game_id, 2.0)
		thumb.custom_minimum_size = P.LIST_THUMB_SIZE
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(thumb)
		_name = _cell(row, P.SIZE_NAME, 700, T.FG, 260.0)
		_name.name = "Name"
		_genre = _cell(row, P.SIZE_TEXT, 400, P.TEXT_SOFT, 180.0)
		_genre.name = "Genre"
		_players = _cell(row, P.SIZE_TEXT, 400, P.TEXT_SOFT, 80.0)
		_players.name = "Players"
		_time = _cell(row, P.SIZE_TEXT, 400, P.TEXT_SOFT, 130.0)
		_time.name = "Time"
		var bar := Control.new()
		bar.name = "Progress"
		bar.custom_minimum_size = Vector2(140, 4)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track := ColorRect.new()
		track.color = P.BORDER
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(W.fill(track))
		_fill = ColorRect.new()
		_fill.name = "Fill"
		_fill.color = T.FG
		_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fill.anchor_bottom = 1.0
		_fill.anchor_right = 0.0
		bar.add_child(_fill)
		row.add_child(bar)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(spacer)
		_heart = IconButton.new("heart_line", 36.0, 16.0, IconButton.PLAIN)
		_heart.name = "Favorite"
		_heart.mouse_filter = Control.MOUSE_FILTER_PASS
		_heart.activated.connect(func() -> void: favorite_pressed.emit())
		row.add_child(_heart)

	func _cell(row: HBoxContainer, font_size: int, weight: int, color: Color, width: float) -> Label:
		var label := W.text("", font_size, weight, color)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size = Vector2(width, 0)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		return label

	func update(model: Dictionary) -> void:
		_name.text = str(model["name"])
		_genre.text = str(model["genre"])
		_players.text = str(model["players"])
		_time.text = str(model["time"])
		_fill.anchor_right = clampf(float(model["ratio"]), 0.0, 1.0)
		_favorite = bool(model["favorite"])
		_heart.set_icon("heart" if _favorite else "heart_line", T.FAVORITE if _favorite else P.TEXT_SOFT)
		selected = bool(model["selected"])
		queue_redraw()

	func name_text() -> String:
		return _name.text

	func time_text() -> String:
		return _time.text

	func is_favorite_shown() -> bool:
		return _favorite

	func _paint() -> void:
		var area := Rect2(Vector2.ZERO, size)
		if selected:
			draw_style_box(Paint.box(T.fg(P.A_SELECTED)), area)
			draw_rect(Rect2(0, 0, P.SIDE_BAR, size.y), T.FG)
		else:
			draw_style_box(Paint.box(P.BORDER if down else (P.LINE if hover else P.FIELD_BG)), area)

# ---- detail pieces ----

## One achievement: an icon disc, the name, how it is earned, and whether (and when) it was unlocked. A locked one is dimmed.
class AchievementCard:
	extends PanelContainer

	var unlocked := false

	var _name: Label
	var _state: Label
	var _icon: Symbol

	func _init(p_icon_kind: String, title: String, description: String, state: String, p_unlocked: bool) -> void:
		unlocked = p_unlocked
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, P.ACHIEVEMENT_HEIGHT)
		var style := Paint.box(Color(0, 0, 0, 0), P.BORDER, 1)
		style.set_content_margin_all(12)
		add_theme_stylebox_override("panel", style)
		modulate.a = 1.0 if unlocked else 0.55
		var row := W.hbox(12)
		add_child(row)
		var disc := Control.new()
		disc.custom_minimum_size = Vector2(36, 36)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.draw.connect(func() -> void: disc.draw_circle(disc.size / 2.0, 18.0, T.FG if unlocked else P.LOCKED_BG, true, -1.0, true))
		row.add_child(disc)
		_icon = Symbol.new(p_icon_kind, 18.0, T.BG if unlocked else P.TEXT_MUTED)
		_icon.position = Vector2(9, 9)
		_icon.size = Vector2(18, 18)
		disc.add_child(_icon)
		var column := W.vbox(2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(column)
		_name = Paint.clipped(W.text(title, P.SIZE_TEXT, 700))
		_name.name = "Name"
		column.add_child(_name)
		column.add_child(Paint.clipped(W.text(description, P.SIZE_LABEL, 400, P.TEXT_SOFT)))
		_state = Paint.clipped(W.text(state, P.SIZE_LABEL, 400, P.TEXT_MUTED))
		_state.name = "State"
		column.add_child(_state)

	func icon_kind() -> String:
		return _icon.kind

	func height_for(_width: float) -> float:
		return P.ACHIEVEMENT_HEIGHT

	func name_text() -> String:
		return _name.text

	func state_text() -> String:
		return _state.text

## One number of a game's record with its caption.
class StatTile:
	extends PanelContainer

	var _value: Label

	func _init(caption: String, value: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, P.STAT_HEIGHT)
		var style := Paint.box(Color(0, 0, 0, 0), P.BORDER, 1)
		style.set_content_margin_all(16)
		add_theme_stylebox_override("panel", style)
		var column := W.vbox(8)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(column)
		column.add_child(W.text(caption, P.SIZE_NOTE, 400, P.TEXT_MUTED, 2))
		_value = Paint.clipped(W.text(value, P.SIZE_STAT, 800, T.FG, 0, true))
		_value.name = "Value"
		# A fixed line box: a value with Chinese in it ("今天 18:02") falls back to a taller face than plain digits.
		_value.custom_minimum_size = Vector2(0, 30)
		_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		column.add_child(_value)

	func height_for(_width: float) -> float:
		return P.STAT_HEIGHT

	func value_text() -> String:
		return _value.text

# ---- menu ----

## A popup menu: rows of text, optional separators (a null item), an optional tick. `index` is the row under keyboard focus; `picked` fires with the position of the chosen item in the list it was built from.
class Menu:
	extends PanelContainer

	signal picked(item: int)

	var index := 0

	var _rows: Array[MenuRow] = []
	var _items: Array[int] = []

	func _init(items: Array) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(P.MENU_WIDTH, 0)
		var style := Paint.box(P.MENU_BG, P.BORDER_STRONG, 1)
		style.set_content_margin_all(6)
		style.shadow_color = Color(0, 0, 0, 0.55)
		style.shadow_size = 40
		style.shadow_offset = Vector2(0, 16)
		add_theme_stylebox_override("panel", style)
		var column := W.vbox(0)
		add_child(column)
		for position_in_items in items.size():
			var item: Variant = items[position_in_items]
			if item == null:
				var gap := MarginContainer.new()
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				gap.add_theme_constant_override("margin_top", 4)
				gap.add_theme_constant_override("margin_bottom", 4)
				gap.add_child(W.rule(P.BORDER))
				column.add_child(gap)
				continue
			var row := MenuRow.new(str(item["label"]), bool(item.get("checked", false)))
			row.name = "Item%d" % _rows.size()
			var row_index := _rows.size()
			row.hovered.connect(func() -> void: set_index(row_index))
			row.activated.connect(func() -> void: picked.emit(position_in_items))
			column.add_child(row)
			_rows.append(row)
			_items.append(position_in_items)
		set_index(0)

	func count() -> int:
		return _rows.size()

	func labels() -> PackedStringArray:
		var out := PackedStringArray()
		for row in _rows:
			out.append(row.label_text())
		return out

	func set_index(value: int) -> void:
		index = posmod(value, maxi(1, _rows.size()))
		for i in _rows.size():
			_rows[i].set_current(i == index)

	func move(step: int) -> void:
		set_index(index + step)

	## Choose the row under keyboard focus.
	func pick_current() -> void:
		if not _rows.is_empty():
			picked.emit(_items[index])

class MenuRow:
	extends Clickable

	var current := false

	var _label: Label

	func _init(caption: String, checked: bool) -> void:
		super()
		custom_minimum_size = Vector2(0, P.MENU_ROW_HEIGHT)
		set_padding(12, 0)
		var row := W.hbox(8)
		add_child(row)
		_label = Paint.clipped(W.text(caption, P.SIZE_TEXT))
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_label)
		if checked:
			row.add_child(Symbol.new("check", 14.0))

	func label_text() -> String:
		return _label.text

	func set_current(on: bool) -> void:
		current = on
		queue_redraw()

	func _paint() -> void:
		if current or hover:
			draw_style_box(Paint.box(T.fg(P.A_PRESSED if down else 0.08), Color(0, 0, 0, 0), 0, 3.0), Rect2(Vector2.ZERO, size))

# ---- search field ----

## The search box: a magnifier, a real text field (`edit`) and a clear button while there is text. It is the one place in the launcher that takes Godot's keyboard focus, because typing needs it.
class SearchField:
	extends PanelContainer

	signal clear_pressed

	var edit: LineEdit

	var _clear: IconButton

	func _init(placeholder: String) -> void:
		custom_minimum_size = Vector2(0, P.SEARCH_HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_PASS
		var row := W.hbox(10)
		add_child(row)
		row.add_child(Symbol.new("search", 15.0, P.TEXT_MUTED))
		edit = LineEdit.new()
		edit.name = "Edit"
		edit.placeholder_text = placeholder
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Focus by click or by LauncherPcMode only: with FOCUS_ALL the engine's own Tab navigation would take the key before the launcher sees it.
		edit.focus_mode = Control.FOCUS_CLICK
		edit.context_menu_enabled = false
		edit.caret_blink = true
		edit.select_all_on_focus = true
		edit.add_theme_font_override("font", T.font(400))
		edit.add_theme_font_size_override("font_size", P.SIZE_TEXT)
		edit.add_theme_color_override("font_color", T.FG)
		edit.add_theme_color_override("font_placeholder_color", P.TEXT_MUTED)
		edit.add_theme_color_override("caret_color", T.FG)
		edit.add_theme_color_override("selection_color", T.fg(0.25))
		for box in ["normal", "focus", "read_only"]:
			edit.add_theme_stylebox_override(box, StyleBoxEmpty.new())
		edit.focus_entered.connect(_sync)
		edit.focus_exited.connect(_sync)
		edit.text_changed.connect(func(_text: String) -> void: _sync())
		row.add_child(edit)
		_clear = IconButton.new("close", 24.0, 12.0, IconButton.PLAIN)
		_clear.name = "Clear"
		_clear.activated.connect(func() -> void: clear_pressed.emit())
		row.add_child(_clear)
		_sync()

	func set_text(value: String) -> void:
		if edit.text != value:
			edit.text = value
			edit.caret_column = value.length()
		_sync()

	func _sync() -> void:
		_clear.visible = edit.text != ""
		var style := Paint.box(P.FIELD_BG, T.fg(0.5) if edit.has_focus() else P.BORDER, 1)
		style.content_margin_left = 12
		style.content_margin_right = 8
		add_theme_stylebox_override("panel", style)

# ---- flow layout ----

## Lays its children out in equal columns, as many as fit at `min_cell` width, and grows downwards. A child's height is `fixed_height`, or what its height_for(width) answers. `columns` is the count of the last layout, which keyboard navigation reads.
class Flow:
	extends Container

	var min_cell := P.CARD_MIN_WIDTH
	var gap := P.GRID_GAP
	var row_gap := P.GRID_GAP
	var max_columns := 0
	var fixed_height := 0.0
	var columns := 1

	var _height := 0.0

	func _init(p_min_cell: float = P.CARD_MIN_WIDTH, p_gap: float = P.GRID_GAP, p_row_gap: float = P.GRID_GAP, p_fixed_height: float = 0.0, p_max_columns: int = 0) -> void:
		min_cell = p_min_cell
		gap = p_gap
		row_gap = p_row_gap
		fixed_height = p_fixed_height
		max_columns = p_max_columns
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			_layout()

	## Columns that fit in `width`.
	func columns_for(width: float) -> int:
		var fit := maxi(1, floori((width + gap) / (min_cell + gap)))
		return mini(fit, max_columns) if max_columns > 0 else fit

	func _layout() -> void:
		columns = columns_for(size.x)
		var cell := floorf((size.x - gap * (columns - 1)) / columns)
		var y := 0.0
		var row_height := 0.0
		var placed := 0
		for child in get_children():
			var item := child as Control
			if item == null or not item.visible:
				continue
			var column := placed % columns
			if column == 0 and placed > 0:
				y += row_height + row_gap
				row_height = 0.0
			var height: float = fixed_height if fixed_height > 0.0 else float(item.call("height_for", cell))
			fit_child_in_rect(item, Rect2(column * (cell + gap), y, cell, height))
			row_height = maxf(row_height, height)
			placed += 1
		var total := y + row_height
		if not is_equal_approx(total, _height):
			_height = total
			update_minimum_size()

	func _get_minimum_size() -> Vector2:
		return Vector2(0, _height)
