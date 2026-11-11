class_name LauncherScrollGrid
extends Control

## A clipped grid of equally sized cells that scrolls by whole rows: the cover grid of the library and the achievement list.
##
## The screen owns which cell has focus; this control only places the cells it is given, keeps a requested cell inside the visible rows, and draws a thin position bar on its right when there are more rows than fit. `step()` answers where a direction leads from a cell, so every grid in the launcher has the same edge behaviour.
## The clip rectangle is PAD larger than the cells on every side, so a selected cell's ring and scale are not cut off. Place the control with place_at(), which takes the top-left corner of the first cell.
## Mouse wheel over the grid or any of its cells is reported with `wheeled` (-1 up, 1 down); the screen turns that into a focus move, the same as the stick would.

signal wheeled(step: int)

const In := preload("res://launcher/launcher_input.gd")

const PAD := 24.0
const BAR_GAP := 28.0
const BAR_WIDTH := 3.0

var columns := 1
var cell_size := Vector2.ZERO
var gap := Vector2.ZERO
var visible_rows := 1
## Index of the first row inside the clip rectangle.
var first_row := 0

var _clip: Control
var _content: Control
var _bar: _Bar
var _shown: Array[Control] = []
var _tween: Tween

func _init(p_columns: int, p_cell_size: Vector2, p_gap: Vector2, p_visible_rows: int) -> void:
	columns = maxi(1, p_columns)
	cell_size = p_cell_size
	gap = p_gap
	visible_rows = maxi(1, p_visible_rows)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := view_size()
	size = view + Vector2(PAD, PAD) * 2.0
	custom_minimum_size = size
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.clip_contents = true
	_clip.size = size
	_clip.gui_input.connect(_on_gui_input)
	add_child(_clip)
	_content = Control.new()
	_content.name = "Cells"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_content)
	_bar = _Bar.new()
	_bar.name = "Bar"
	_bar.position = Vector2(PAD + view.x + BAR_GAP, PAD)
	_bar.size = Vector2(BAR_WIDTH, view.y)
	_bar.visible = false
	add_child(_bar)

## Size of the visible cell area, without the padding.
func view_size() -> Vector2:
	return Vector2(columns * (cell_size.x + gap.x) - gap.x, visible_rows * (cell_size.y + gap.y) - gap.y)

## Put the top-left corner of the first cell at `origin` (in the parent's coordinates).
func place_at(origin: Vector2) -> void:
	position = origin - Vector2(PAD, PAD)

## Hand a cell to the grid. It stays hidden until layout() lists it.
func add_cell(cell: Control) -> void:
	cell.visible = false
	cell.gui_input.connect(_on_gui_input)
	_content.add_child(cell)

## Show exactly these cells, in this order, row by row. Cells added earlier and not listed are hidden.
func layout(cells: Array[Control]) -> void:
	for child in _content.get_children():
		(child as Control).visible = false
	_shown = cells
	for index in cells.size():
		var cell := cells[index]
		cell.position = Vector2(PAD + (index % columns) * (cell_size.x + gap.x), PAD + (index / columns) * (cell_size.y + gap.y))
		cell.size = cell_size
	first_row = clampi(first_row, 0, max_first_row())
	_apply(false)

func row_count() -> int:
	return ceili(float(_shown.size()) / float(columns))

func max_first_row() -> int:
	return maxi(0, row_count() - visible_rows)

func is_scrollable() -> bool:
	return row_count() > visible_rows

## Whether the cell at `index` is inside the visible rows.
func is_index_visible(index: int) -> bool:
	var row := index / columns
	return index >= 0 and index < _shown.size() and row >= first_row and row < first_row + visible_rows

## Scroll by the fewest rows that bring the cell at `index` into view.
func ensure_visible(index: int, animate: bool = true) -> void:
	if index < 0 or index >= _shown.size():
		return
	var row := index / columns
	var target := first_row
	if row < first_row:
		target = row
	elif row >= first_row + visible_rows:
		target = row - visible_rows + 1
	if target != first_row:
		first_row = target
		_apply(animate)

## The index a direction leads to from `index` in a grid of `count` cells, or -1 when that direction leaves the grid. Left and right stop at the row's ends; down onto a shorter last row lands on its last cell.
static func step(index: int, count: int, p_columns: int, action: StringName) -> int:
	if index < 0 or index >= count:
		return -1
	var column := index % p_columns
	var row := index / p_columns
	match action:
		In.LEFT:
			return index - 1 if column > 0 else -1
		In.RIGHT:
			return index + 1 if column < p_columns - 1 and index + 1 < count else -1
		In.UP:
			return index - p_columns if row > 0 else -1
		In.DOWN:
			if index + p_columns < count:
				return index + p_columns
			return count - 1 if (count - 1) / p_columns > row else -1
	return -1

func _apply(animate: bool) -> void:
	# One row above and below the visible ones stays drawn so a row sliding out is still there while it moves.
	for index in _shown.size():
		var row := index / columns
		_shown[index].visible = row >= first_row - 1 and row <= first_row + visible_rows
	var target := -first_row * (cell_size.y + gap.y)
	if _tween != null:
		_tween.kill()
		_tween = null
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(_content, "position:y", target, LauncherTokens.RESIZE_CARD).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.finished.connect(func() -> void: _tween = null)
	else:
		_content.position.y = target
	_bar.visible = is_scrollable()
	if _bar.visible:
		_bar.length = float(visible_rows) / float(row_count())
		_bar.start = float(first_row) / float(row_count())
		_bar.queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheeled.emit(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheeled.emit(1)

## Track with a thumb showing which share of the rows is in view.
class _Bar:
	extends Control

	var start := 0.0
	var length := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), LauncherTokens.fg(LauncherTokens.A_HAIRLINE))
		draw_rect(Rect2(0, size.y * start, size.x, size.y * length), LauncherTokens.fg(LauncherTokens.A_MUTED))
