class_name LauncherSettingsControls
extends RefCounted

## Widgets of the Settings screen, as inner classes: SettingRow (one row of any kind), Switch, Segments, Arrow, OutlineButton, RowList (the clipped, scrolled column of rows) and KeyCapture (the one place that reads raw key events, for rebinding).
## Like LauncherControls they are presentation only: the screen owns focus and values and tells each widget how to look; the widgets report intent through signals.
##
## These classes must not refer to LauncherSettingsControls by name (an inner class naming its own outer script leaks at exit); they use the consts below and each other's bare names.

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")

const KIND_CHOICE := &"choice"
const KIND_TOGGLE := &"toggle"
const KIND_SLIDER := &"slider"
const KIND_ACTION := &"action"
const KIND_INFO := &"info"

## Start alpha of a focused settings row's gradient and the alpha of the hairline under every row.
const A_ROW_FILL := 0.12
const A_ROW_RULE := 0.14
const A_SEGMENT_IDLE := 0.22
const ARROW_BOX := 48.0
const VALUE_MIN_WIDTH := 200.0

# ---- small parts ----

## A solid triangle pointing left (-1) or right (1): the previous / next buttons of a choice row.
class Arrow:
	extends LauncherControls.Pressable

	var direction := 1

	func _init(p_direction: int) -> void:
		super()
		direction = p_direction
		custom_minimum_size = Vector2(ARROW_BOX, ARROW_BOX)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var center := size / 2.0
		var tip := Vector2(6.0 * direction, 0)
		draw_colored_polygon(PackedVector2Array([center + tip, center - tip + Vector2(0, -7), center - tip + Vector2(0, 7)]), T.FG)

## The pill of a toggle row: outlined when off, filled with the knob on the right when on.
class Switch:
	extends Control

	var on := false

	func _init() -> void:
		custom_minimum_size = T.SWITCH_SIZE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_on(value: bool) -> void:
		on = value
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = T.FG if on else Color(0, 0, 0, 0)
		box.border_color = T.FG
		box.set_border_width_all(2)
		box.set_corner_radius_all(roundi(size.y / 2.0))
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		draw_circle(Vector2(size.x - 15.0 if on else 15.0, size.y / 2.0), 10.0, T.BG if on else T.FG, true, -1.0, true)

class _Segment:
	extends LauncherControls.Pressable

	var filled := false

	func _init() -> void:
		super()
		custom_minimum_size = Vector2(T.SEGMENT_SIZE.x + 4.0, T.BUTTON_HEIGHT)

	func _draw() -> void:
		draw_rect(Rect2(Vector2(0, (size.y - T.SEGMENT_SIZE.y) / 2.0), T.SEGMENT_SIZE), T.FG if filled else T.fg(A_SEGMENT_IDLE))

## The ten blocks of a slider row. Clicking block n emits picked(n); clicking the last filled block emits picked(n - 1), so every value from 0 can be reached with the mouse.
class Segments:
	extends HBoxContainer

	signal picked(step: int)
	signal hovered

	var step := 0

	var _blocks: Array[_Segment] = []

	func _init(count: int) -> void:
		add_theme_constant_override("separation", 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for index in count:
			var block := _Segment.new()
			block.activated.connect(func() -> void: picked.emit(index if index + 1 == step else index + 1))
			block.hovered.connect(func() -> void: hovered.emit())
			add_child(block)
			_blocks.append(block)

	func set_step(value: int) -> void:
		step = value
		for index in _blocks.size():
			_blocks[index].filled = index < value
			_blocks[index].queue_redraw()

## An outlined button with a caption. `danger` tints it red, `filled` paints it solid (the destructive choice of a dialog), set_focused draws a white ring around it.
class OutlineButton:
	extends LauncherControls.Pressable

	var danger := false
	var filled := false
	var focused := false

	var _label: Label

	func _init(caption: String, height: float = T.BUTTON_HEIGHT, font_size: int = T.SIZE_TOAST, p_danger: bool = false, p_filled: bool = false) -> void:
		super()
		danger = p_danger
		filled = p_filled
		custom_minimum_size = Vector2(0, height)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		set_padding(22 if height <= T.BUTTON_HEIGHT else 26, 0)
		var color := T.BG if filled else (T.DANGER if danger else T.FG)
		_label = W.text(caption, font_size, 700 if filled else 400, color, 2)
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_label)

	func caption() -> String:
		return _label.text

	func set_caption(text: String) -> void:
		_label.text = text

	func set_focused(on: bool) -> void:
		focused = on
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = T.DANGER if filled else Color(0, 0, 0, 0)
		box.border_color = T.DANGER if danger else T.fg(0.5)
		box.set_border_width_all(0 if filled else 1)
		box.set_corner_radius_all(roundi(T.RADIUS))
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		if focused:
			draw_rect(Rect2(Vector2.ZERO, size).grow(T.CARD_RING_OFFSET + T.CARD_RING / 2.0), T.FG, false, T.CARD_RING)

# ---- setting row ----

## One row of the settings list: the label on the left and, on the right, the control of its kind: a choice between two arrows, a switch, ten slider blocks, an outlined action button (optionally preceded by a note), or a plain value.
## Clicking the row emits `activated`; the arrows emit stepped(-1 / 1) and the slider blocks picked(step). Focused = 4px white bar on the left plus a gradient fading to the right.
class SettingRow:
	extends LauncherControls.Pressable

	signal stepped(direction: int)
	signal picked(step: int)

	var kind: StringName
	var focused := false

	var _label: Label
	var _value: Label
	var _switch: Switch
	var _segments: Segments
	var _button: OutlineButton
	var _fill := 0.0
	var _tween: Tween

	func _init(p_kind: StringName, label: String, danger: bool = false) -> void:
		super()
		kind = p_kind
		# PASS lets the mouse wheel reach the list behind the row.
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(0, T.SETTING_ROW_HEIGHT)
		set_padding(T.ROW_PADDING, 0, 20, 0)
		var row := W.hbox(6)
		add_child(row)
		_label = W.text(label, T.SIZE_SETTING_ROW, 400, T.fg(T.A_BODY), 2)
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_label)
		match kind:
			KIND_CHOICE:
				var previous := Arrow.new(-1)
				previous.name = "Previous"
				previous.activated.connect(func() -> void: stepped.emit(-1))
				previous.hovered.connect(func() -> void: hovered.emit())
				row.add_child(previous)
				_value = _value_label(T.SIZE_SETTING_VALUE, 600, VALUE_MIN_WIDTH, HORIZONTAL_ALIGNMENT_CENTER)
				row.add_child(_value)
				var next := Arrow.new(1)
				next.name = "Next"
				next.activated.connect(func() -> void: stepped.emit(1))
				next.hovered.connect(func() -> void: hovered.emit())
				row.add_child(next)
			KIND_TOGGLE:
				_value = _value_label(T.SIZE_NAV, 400, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
				row.add_child(_value)
				row.add_child(_spacer(8))
				_switch = Switch.new()
				_switch.name = "Switch"
				row.add_child(_switch)
				row.add_child(_spacer(2))
			KIND_SLIDER:
				_segments = Segments.new(LauncherSettings.VOLUME_STEPS)
				_segments.name = "Segments"
				_segments.picked.connect(func(step: int) -> void: picked.emit(step))
				_segments.hovered.connect(func() -> void: hovered.emit())
				row.add_child(_segments)
				_value = _value_label(T.SIZE_HELP, 600, 40.0, HORIZONTAL_ALIGNMENT_RIGHT, true)
				row.add_child(_value)
			KIND_ACTION:
				_value = _value_label(T.SIZE_SETTING_VALUE, 600, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
				_value.visible = false
				row.add_child(_value)
				row.add_child(_spacer(12))
				_button = OutlineButton.new("", T.BUTTON_HEIGHT, T.SIZE_TOAST, danger)
				_button.name = "Button"
				_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(_button)
			_:
				_value = _value_label(T.SIZE_SETTING_VALUE, 400, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
				_value.label_settings.font_color = T.fg(T.A_BODY)
				row.add_child(_value)
				row.add_child(_spacer(2))

	func _value_label(font_size: int, weight: int, min_width: float, alignment: HorizontalAlignment, latin: bool = false) -> Label:
		var label := W.text("", font_size, weight, T.FG, 0, latin)
		label.name = "Value"
		label.custom_minimum_size = Vector2(min_width, 0)
		label.horizontal_alignment = alignment
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return label

	func _spacer(width: float) -> Control:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(width, 0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return spacer

	func label_text() -> String:
		return _label.text

	## The text shown as the row's value: the chosen option, On/Off, the slider step, the note of an action row, or the plain value.
	func value_text() -> String:
		return _value.text

	func set_value(text: String) -> void:
		_value.text = text
		if kind == KIND_ACTION:
			_value.visible = text != ""

	func set_on(on: bool) -> void:
		_switch.set_on(on)

	func is_on() -> bool:
		return _switch.on

	func set_step(step: int) -> void:
		_segments.set_step(step)
		_value.text = str(step)

	func step() -> int:
		return _segments.step

	func set_button(caption: String) -> void:
		_button.set_caption(caption)

	func button_text() -> String:
		return _button.caption()

	func set_focused(on: bool, animate: bool = true) -> void:
		if on == focused and _tween == null and _fill == (1.0 if on else 0.0):
			return
		focused = on
		W.restyle(_label, 700 if on else 400, T.FG if on else T.fg(T.A_BODY), 2)
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
		draw_rect(Rect2(0, size.y - 1.0, size.x, 1.0), T.fg(A_ROW_RULE))
		if _fill <= 0.0:
			return
		draw_polygon(
			PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
			PackedColorArray([T.fg(A_ROW_FILL * _fill), T.fg(0.0), T.fg(0.0), T.fg(A_ROW_FILL * _fill)]))
		draw_rect(Rect2(0, 0, T.FOCUS_BAR, size.y), T.fg(_fill))

# ---- row list ----

## The column of rows, clipped to a whole number of rows and scrolled by the screen (it follows the focused row). The mouse wheel emits `wheel` with -1 or 1; a thumb on the right edge shows where the window is when the rows do not all fit.
class RowList:
	extends Control

	signal wheel(direction: int)

	var column: VBoxContainer
	var first_visible := 0
	var visible_rows := 0
	## Engine.get_process_frames() of the last scroll that moved the rows; see moved_recently.
	var _scrolled_frame := -1000

	func _init(p_visible_rows: int) -> void:
		visible_rows = p_visible_rows
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
		column = W.vbox(0)
		column.name = "Column"
		add_child(column)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			column.size.x = size.x

	func row_count() -> int:
		return column.get_child_count()

	## Scroll so that row `index` is inside the window.
	func reveal(index: int) -> void:
		if index < first_visible:
			scroll_to(index)
		elif index >= first_visible + visible_rows:
			scroll_to(index - visible_rows + 1)

	## True for a few frames after the rows moved. Rows that slide under a resting mouse report `hovered` although the pointer did not move; the screen ignores hover while this holds, so scrolling with the keys or the wheel does not hand focus to whatever row ends up under the pointer.
	func moved_recently() -> bool:
		return Engine.get_process_frames() - _scrolled_frame <= 2

	func scroll_to(first: int) -> void:
		var target := clampi(first, 0, maxi(0, row_count() - visible_rows))
		if target != first_visible:
			_scrolled_frame = Engine.get_process_frames()
		first_visible = target
		column.position = Vector2(0, -first_visible * T.SETTING_ROW_HEIGHT)
		column.size.x = size.x
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				accept_event()
				wheel.emit(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				accept_event()
				wheel.emit(1)

	func _draw() -> void:
		var count := row_count()
		if count <= visible_rows:
			return
		var track := size.y
		draw_rect(Rect2(size.x - 3.0, 0, 3.0, track), T.fg(T.A_HAIRLINE))
		draw_rect(Rect2(size.x - 3.0, track * float(first_visible) / float(count), 3.0, track * float(visible_rows) / float(count)), T.fg(T.A_FAINT))

# ---- key capture ----

## Full-rect layer that is mounted while the Settings screen waits for the key of a rebinding. It takes every key event before the shell sees it: Escape cancels, any other key press is reported by its physical keycode. Gamepad and mouse input are left alone.
class KeyCapture:
	extends Control

	signal captured(keycode: int)
	signal cancelled

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _input(event: InputEvent) -> void:
		if not event is InputEventKey:
			return
		get_viewport().set_input_as_handled()
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			cancelled.emit()
		else:
			captured.emit(int(key.physical_keycode))

## Dimmed click-away area behind a dialog.
class Scrim:
	extends LauncherControls.Pressable

	func _init() -> void:
		super()
		mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), T.deep(0.7))
