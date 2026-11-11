class_name LauncherGameWidgets
extends RefCounted

## Widgets shared by the game menu, the in-game HUD and the pause screen: KeyCap, Meter, HudChip, SliderRow, DialogButton, ConfirmDialog, Scrim, GameTitle, BackLink, AchievementRow, plus the factories for a stat cell, an eyebrow line and the controls table.
## Like LauncherControls they are presentation only and report intent through `hovered` / `activated` (or their own signals); the screen that owns them owns the focus.
##
## The inner classes must not refer to LauncherGameWidgets by name (see LauncherControls for why).

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")
const Guide := preload("res://launcher/launcher_game_guide.gd")

## Width reserved for the gamepad side of a controls row, so the glyphs of every row start on the same line.
const PAD_COLUMN := 150.0

# ---- factories ----

## A caption over a number, as in the records grid and the HUD.
static func stat_cell(label: String, value: String, align_end: bool = false) -> VBoxContainer:
	var cell := W.vbox(6)
	var caption := W.text(label, T.SIZE_SMALL, 400, T.fg(T.A_MUTED), 3)
	caption.name = "Label"
	cell.add_child(caption)
	var number := W.text(value, T.SIZE_STAT, 700, T.FG, 0, true)
	number.name = "Value"
	cell.add_child(number)
	if align_end:
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return cell

## The short rule followed by spaced Latin capitals that opens a hero column.
static func eyebrow(content: String) -> HBoxContainer:
	var row := W.hbox(14)
	var dash := W.rule(T.fg(T.A_MUTED))
	dash.custom_minimum_size = Vector2(40, 1)
	dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dash)
	var label := W.text(content, T.SIZE_SMALL, 600, T.fg(T.A_BODY), 5, true)
	label.name = "Meta"
	row.add_child(label)
	return row

static func gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

## The controls of a game as rows of "what it does · keyboard keys · gamepad buttons", read from LauncherGameGuide and the live InputMap.
static func controls_table(game_id: String, locale: String, row_height: float = T.PANE_ROW_HEIGHT) -> VBoxContainer:
	var table := W.vbox(0)
	table.name = "Controls"
	table.add_child(W.rule(T.fg(0.14)))
	for control: Dictionary in Guide.controls(game_id):
		var row := W.hbox(16)
		row.name = "Control_%s" % control["id"]
		row.custom_minimum_size = Vector2(0, row_height)
		var label := W.text(Guide.text(control, "name", locale), T.SIZE_PANE_ROW, 400, T.fg(T.A_STRONG), 2)
		label.name = "Label"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		var keys := W.hbox(6)
		keys.name = "Keys"
		for key in Guide.key_labels(control["actions"]):
			keys.add_child(KeyCap.new(key))
		if control.has("mouse"):
			keys.add_child(KeyCap.new(Guide.text(control, "mouse", locale)))
		row.add_child(keys)
		var pad := W.hbox(6)
		pad.name = "Pad"
		pad.custom_minimum_size = Vector2(PAD_COLUMN, 0)
		if control.has("pad"):
			var words := W.text(Guide.text(control, "pad", locale), T.SIZE_SUB, 400, T.fg(T.A_MUTED))
			words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pad.add_child(words)
		for glyph: StringName in control.get("glyphs", []):
			pad.add_child(LauncherControls.Glyph.new(glyph))
		row.add_child(pad)
		table.add_child(row)
		table.add_child(W.rule(T.fg(0.14)))
	return table

# ---- small pieces ----

## A keyboard key: outlined cap with a heavier bottom edge.
class KeyCap:
	extends Control

	var caption := ""

	func _init(p_caption: String) -> void:
		caption = p_caption
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var width := ceilf(T.font(700, 0, true).get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T.SIZE_BODY).x)
		custom_minimum_size = Vector2(maxf(44.0, width + 20.0), T.KEYCAP_HEIGHT)

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_color = T.fg(0.4)
		box.set_border_width_all(1)
		box.border_width_bottom = 3
		box.set_corner_radius_all(roundi(T.RADIUS))
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var face := T.font(700, 0, true)
		var extent := face.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T.SIZE_BODY)
		var baseline := (size.y - 2.0 - face.get_height(T.SIZE_BODY)) / 2.0 + face.get_ascent(T.SIZE_BODY)
		draw_string(face, Vector2((size.x - extent.x) / 2.0, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T.SIZE_BODY, T.FG)

## A small outlined tag for a short note inside a chip (a key name, a cost, a countdown).
class Tag:
	extends Control

	var caption := "":
		set(value):
			if value == caption:
				return
			caption = value
			_fit()
			queue_redraw()

	func _init(p_caption: String = "") -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption = p_caption
		_fit()

	func _fit() -> void:
		var width := ceilf(T.font(800, 0, true).get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T.SIZE_MICRO).x)
		custom_minimum_size = Vector2(width + 12.0, 20.0)

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_color = T.fg(0.6)
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var face := T.font(800, 0, true)
		var extent := face.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T.SIZE_MICRO)
		var baseline := (size.y - face.get_height(T.SIZE_MICRO)) / 2.0 + face.get_ascent(T.SIZE_MICRO)
		draw_string(face, Vector2((size.x - extent.x) / 2.0, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T.SIZE_MICRO, T.fg(0.9))

## A thin horizontal bar filled to `ratio` (0..1).
class Meter:
	extends Control

	var color := T.FG
	var ratio := 0.0:
		set(value):
			ratio = clampf(value, 0.0, 1.0)
			queue_redraw()

	func _init(width: float, p_color: Color = T.FG) -> void:
		color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(width, T.METER_HEIGHT)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), T.fg(0.22))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), color)

## An outlined HUD button over the game: optional glyph, caption, optional tag. `active` lights it (a selected tower, a held ability); `dimmed` fades it (not affordable, recharging).
class HudChip:
	extends LauncherControls.Pressable

	var active := false
	var dimmed := false

	var _label: Label
	var _tag: Tag

	func _init(caption: String, note: String = "", glyph: StringName = &"", height: float = T.HUD_CHIP_HEIGHT) -> void:
		super()
		custom_minimum_size = Vector2(0, height)
		set_padding(16, 0)
		var row := W.hbox(10)
		add_child(row)
		if glyph != &"":
			row.add_child(LauncherControls.Glyph.new(glyph))
		_label = W.text(caption, T.SIZE_TOAST, 400, T.FG, 2)
		_label.name = "Label"
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_label)
		_tag = Tag.new(note)
		_tag.name = "Tag"
		_tag.visible = note != ""
		row.add_child(_tag)

	func caption() -> String:
		return _label.text

	func note() -> String:
		return _tag.caption if _tag.visible else ""

	func set_note(value: String) -> void:
		_tag.caption = value
		_tag.visible = value != ""

	func set_state(p_active: bool, p_dimmed: bool = false) -> void:
		if p_active == active and p_dimmed == dimmed:
			return
		active = p_active
		dimmed = p_dimmed
		modulate.a = 0.45 if dimmed and not active else 1.0
		W.restyle(_label, 700 if active else 400, T.FG, 2)
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(T.FG, 0.18) if active else T.HUD_CHIP_BG
		box.border_color = T.FG if active else T.fg(T.A_CHIP_BORDER)
		box.set_border_width_all(2 if active else 1)
		box.set_corner_radius_all(roundi(T.RADIUS))
		draw_style_box(box, Rect2(Vector2.ZERO, size))

## A focus row whose right side is a segmented slider with its number. Left and right change it while the row is focused (the screen calls set_value); clicking a segment emits value_picked.
class SliderRow:
	extends LauncherControls.FocusRow

	signal value_picked(value: int)

	var steps := 10
	var value := 0

	var _fills: Array[ColorRect] = []
	var _number: Label

	func _init(label: String, p_steps: int, font_size: int = T.SIZE_ROW, min_height: float = T.ROW_HEIGHT) -> void:
		super(label, "", font_size, min_height)
		steps = p_steps
		var holder := W.hbox(0)
		holder.name = "Slider"
		holder.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
		holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		get_child(0).add_child(holder)
		for index in steps:
			var segment := LauncherControls.Pressable.new()
			segment.name = "Segment%d" % (index + 1)
			segment.custom_minimum_size = Vector2(T.SLIDER_SEGMENT.x + 4.0, 44)
			var fill := ColorRect.new()
			fill.custom_minimum_size = T.SLIDER_SEGMENT
			fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			segment.add_child(fill)
			# Clicking the segment that is already the value steps one down, so the slider can reach zero with the mouse.
			segment.activated.connect(func() -> void: value_picked.emit(index if value == index + 1 else index + 1))
			segment.hovered.connect(func() -> void: hovered.emit())
			holder.add_child(segment)
			_fills.append(fill)
		_number = W.text("0", T.SIZE_TOAST, 600, T.FG, 0, true)
		_number.name = "Number"
		_number.custom_minimum_size = Vector2(44, 0)
		_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_child(_number)
		set_value(0)

	func set_value(p_value: int) -> void:
		value = clampi(p_value, 0, steps)
		for index in _fills.size():
			_fills[index].color = T.FG if index < value else T.fg(0.22)
		_number.text = str(value)

## A dialog button. Primary = filled white, secondary = outlined. Focused = the white ring a selected card has.
class DialogButton:
	extends LauncherControls.Pressable

	var primary := false
	var focused := false

	func _init(caption: String, p_primary: bool = false) -> void:
		super()
		primary = p_primary
		custom_minimum_size = Vector2(0, T.DIALOG_BUTTON_HEIGHT)
		set_padding(26, 0)
		var label := W.text(caption, T.SIZE_DIALOG_BODY, 700 if primary else 400, T.BG if primary else T.FG, 1)
		label.name = "Label"
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(label)

	func set_focused(on: bool) -> void:
		focused = on
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = T.FG if primary else Color(0, 0, 0, 0)
		box.border_color = T.fg(0.4)
		box.set_border_width_all(0 if primary else 1)
		box.set_corner_radius_all(roundi(T.RADIUS))
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		if focused:
			draw_rect(Rect2(Vector2.ZERO, size).grow(T.CARD_RING_OFFSET + T.CARD_RING / 2.0), T.FG, false, T.CARD_RING)

## Dimmed click-away area under a dialog or over a paused game.
class Scrim:
	extends LauncherControls.Pressable

	var alpha := 0.7

	func _init(p_alpha: float = T.A_SCRIM_DIALOG) -> void:
		super()
		alpha = p_alpha
		mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), T.deep(alpha))

## A yes/no question over everything. Focus starts on cancel, so a stray confirm press never does the destructive thing. The screen that shows it forwards actions to handle_action and listens to `confirmed` / `cancelled`.
class ConfirmDialog:
	extends Control

	signal confirmed
	signal cancelled

	const FOCUS_CANCEL := 0
	const FOCUS_CONFIRM := 1

	var focus := FOCUS_CANCEL

	var _buttons: Array[DialogButton] = []

	func _init(title: String, body: String, confirm_caption: String, cancel_caption: String) -> void:
		name = "ConfirmDialog"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var scrim := Scrim.new(T.A_SCRIM_DIALOG)
		scrim.name = "DialogScrim"
		scrim.activated.connect(func() -> void: cancelled.emit())
		add_child(W.fill(scrim))
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(W.fill(center))
		var panel := PanelContainer.new()
		panel.name = "Panel"
		panel.custom_minimum_size = Vector2(T.DIALOG_WIDTH, 0)
		var style := StyleBoxFlat.new()
		style.bg_color = T.DIALOG_BG
		style.border_color = T.fg(T.A_RULE)
		style.set_border_width_all(1)
		style.set_corner_radius_all(roundi(T.RADIUS))
		style.content_margin_left = 44
		style.content_margin_right = 44
		style.content_margin_top = 40
		style.content_margin_bottom = 40
		panel.add_theme_stylebox_override("panel", style)
		center.add_child(panel)
		var column := W.vbox(16)
		panel.add_child(column)
		var heading := W.text(title, T.SIZE_DIALOG_TITLE, 900, T.FG, 3)
		heading.name = "Title"
		column.add_child(heading)
		var text := W.text(body, T.SIZE_DIALOG_BODY, 400, T.fg(0.8))
		text.name = "Body"
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(T.DIALOG_WIDTH - 88.0, 0)
		text.label_settings.line_spacing = 10
		column.add_child(text)
		var buttons := W.hbox(12)
		buttons.alignment = BoxContainer.ALIGNMENT_END
		var lift := MarginContainer.new()
		lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lift.add_theme_constant_override("margin_top", 12)
		lift.add_child(buttons)
		column.add_child(lift)
		var cancel := DialogButton.new(cancel_caption)
		cancel.name = "Cancel"
		cancel.hovered.connect(func() -> void: _focus(FOCUS_CANCEL))
		cancel.activated.connect(func() -> void: cancelled.emit())
		buttons.add_child(cancel)
		var confirm := DialogButton.new(confirm_caption, true)
		confirm.name = "Confirm"
		confirm.hovered.connect(func() -> void: _focus(FOCUS_CONFIRM))
		confirm.activated.connect(func() -> void: confirmed.emit())
		buttons.add_child(confirm)
		_buttons = [cancel, confirm]
		_focus(FOCUS_CANCEL)

	func _focus(index: int) -> void:
		focus = index
		for i in _buttons.size():
			_buttons[i].set_focused(i == focus)

	## The dialog is modal: it uses every action.
	func handle_action(action: StringName) -> bool:
		match action:
			LauncherInput.LEFT, LauncherInput.UP:
				_focus(FOCUS_CANCEL)
			LauncherInput.RIGHT, LauncherInput.DOWN:
				_focus(FOCUS_CONFIRM)
			LauncherInput.ACCEPT:
				if focus == FOCUS_CONFIRM:
					confirmed.emit()
				else:
					cancelled.emit()
			LauncherInput.BACK, LauncherInput.MENU:
				cancelled.emit()
		return true

## A game's display title: heavy type in the game's colour with its hard drop shadow and a soft glow behind, scaled down to stay inside `width`.
class GameTitle:
	extends Control

	var _label: Label
	var _glow: _Glow

	func _init(width: float, height: float) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(width, height)
		_glow = _Glow.new()
		add_child(_glow)
		_label = Label.new()
		_label.name = "Title"
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func text() -> String:
		return _label.text

	func show_title(content: String, color: Color, shadow: Color, glow: Color, max_size: int) -> void:
		var font_size := max_size
		var settings := T.label_settings(font_size, 900, color, 6)
		while font_size > 48 and settings.font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > custom_minimum_size.x:
			font_size -= 4
		settings.font_size = font_size
		settings.shadow_color = shadow
		settings.shadow_offset = Vector2(0, 4)
		settings.shadow_size = 0
		settings.add_stacked_shadow()
		settings.set_stacked_shadow_offset(0, Vector2(0, 10))
		settings.set_stacked_shadow_color(0, Color(0, 0, 0, 0.35))
		settings.set_stacked_shadow_outline_size(0, 0)
		_label.label_settings = settings
		_label.text = content
		_label.reset_size()
		_label.position = Vector2(0, (custom_minimum_size.y - _label.size.y) / 2.0)
		_glow.color = glow
		_glow.position = Vector2(-80, -50)
		_glow.size = Vector2(_label.size.x + 160, custom_minimum_size.y + 100)
		_glow.queue_redraw()

class _Glow:
	extends Control

	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size / 2.0
		var inner := Color(color, 0.2)
		var outer := Color(color, 0.0)
		var segments := 48
		for i in segments:
			var a := Vector2.from_angle(TAU * float(i) / segments) * center
			var b := Vector2.from_angle(TAU * float(i + 1) / segments) * center
			draw_polygon(PackedVector2Array([center, center + a, center + b]), PackedColorArray([inner, outer, outer]))

## "‹ Back" at the top left of a screen that has no top navigation.
class BackLink:
	extends LauncherControls.Pressable

	func _init(caption: String) -> void:
		super()
		custom_minimum_size = Vector2(0, 44)
		set_padding(30, 0, 0, 0)
		var label := W.text(caption, T.SIZE_BODY, 400, T.fg(0.8), 3)
		label.name = "Label"
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(label)

	func _draw() -> void:
		var middle := size.y / 2.0
		draw_polyline(PackedVector2Array([Vector2(13, middle - 6), Vector2(7, middle), Vector2(13, middle + 6)]), T.fg(0.8), 1.8, true)

## One achievement: a medal that is filled once unlocked, the name, the description, and when it was unlocked.
class AchievementRow:
	extends HBoxContainer

	var unlocked := false

	func _init(title: String, description: String, state: String, p_unlocked: bool) -> void:
		unlocked = p_unlocked
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 16)
		custom_minimum_size = Vector2(0, 64)
		add_child(_Medal.new(unlocked))
		var column := W.vbox(4)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(column)
		var heading := W.text(title, T.SIZE_PANE_ROW, 700 if unlocked else 400, T.FG if unlocked else T.fg(T.A_MUTED), 1)
		heading.name = "Name"
		column.add_child(heading)
		var body := W.text(description, T.SIZE_SUB, 400, T.fg(T.A_BODY if unlocked else T.A_SUB_IDLE))
		body.name = "Desc"
		column.add_child(body)
		var note := W.text(state, T.SIZE_SMALL, 400, T.fg(T.A_MUTED if unlocked else T.A_SUB_IDLE), 1)
		note.name = "State"
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(note)

class _Medal:
	extends Control

	var filled := false

	func _init(p_filled: bool) -> void:
		filled = p_filled
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(32, 32)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var center := size / 2.0
		if filled:
			draw_circle(center, 15.0, T.FG)
			draw_polyline(PackedVector2Array([center + Vector2(-6, 0), center + Vector2(-2, 5), center + Vector2(7, -5)]), T.BG, 2.6, true)
		else:
			draw_arc(center, 14.0, 0.0, TAU, 48, T.fg(0.3), 1.5, true)
