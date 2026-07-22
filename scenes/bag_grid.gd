class_name BagGrid
extends Control

## The bag: a cols x rows board of 96 px cells, sized from the current quest.
## Owns the cell <-> pixel math and the occupancy map — which cell holds which
## item. GameState still owns *what* is packed; this only knows *where*.

const CELL_SIZE := 96

@export var background_color := Color("2c211b")
@export var cell_color := Color("3d2f26")
@export var line_color := Color("554236")

var cols: int = 6
var rows: int = 5

## Placed items are parented here so they inherit the grid's origin — their
## position is just cell_to_position(cell).
@onready var item_layer: Control = $ItemLayer
@onready var highlight: GridHighlight = $Highlight

## Vector2i -> DraggableItem, one entry per occupied cell.
var _occupancy: Dictionary = {}
## DraggableItem -> Array[Vector2i], so removal doesn't have to scan the board.
var _cells_by_view: Dictionary = {}


func _ready() -> void:
	GameState.quest_changed.connect(_on_quest_changed)
	if GameState.current_quest != null:
		_on_quest_changed(GameState.current_quest)
	else:
		_apply_size()


## Top-left pixel of a cell, relative to the grid's own origin.
func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL_SIZE


## The cell containing a point given in the grid's local space. May be out of
## bounds — callers check with is_in_bounds().
func position_to_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(floori(local_position.x / CELL_SIZE), floori(local_position.y / CELL_SIZE))


## The cell an item's top-left corner snaps to, for a point in local space.
## Rounds rather than floors so a shape half a cell over still lands where the
## player aimed.
func snap_to_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(roundi(local_position.x / CELL_SIZE), roundi(local_position.y / CELL_SIZE))


## Local-space point -> snapped origin cell, for a node anywhere in the tree.
func snap_global_to_cell(global_point: Vector2) -> Vector2i:
	return snap_to_cell(get_global_transform().affine_inverse() * global_point)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


## The board cells a shape would cover if its top-left sat at `origin`.
static func cells_for(shape: Array[Vector2i], origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in shape:
		cells.append(origin + offset)
	return cells


func is_cell_free(cell: Vector2i) -> bool:
	return not _occupancy.has(cell)


## True when every cell of `shape` at `origin` is on the board and empty. An
## item being dragged is already off the board, so there is nothing to ignore.
func can_place(shape: Array[Vector2i], origin: Vector2i) -> bool:
	if shape.is_empty():
		return false
	for cell in cells_for(shape, origin):
		if not is_in_bounds(cell) or not is_cell_free(cell):
			return false
	return true


## Parents `view` into the item layer at `origin` and claims its cells. Assumes
## can_place() already said yes.
func place(view: DraggableItem, origin: Vector2i) -> void:
	var cells := cells_for(view.get_shape(), origin)
	if view.get_parent() != item_layer:
		view.reparent(item_layer, false)
	view.position = cell_to_position(origin)
	view.size = view.custom_minimum_size
	_cells_by_view[view] = cells
	for cell in cells:
		_occupancy[cell] = view


## Frees the cells held by `view`. Returns false if it wasn't on the board, so
## callers can tell a re-drag from a fresh pick-up.
func remove(view: DraggableItem) -> bool:
	if not _cells_by_view.has(view):
		return false
	for cell in _cells_by_view[view]:
		_occupancy.erase(cell)
	_cells_by_view.erase(view)
	return true


func clear_board() -> void:
	_occupancy.clear()
	_cells_by_view.clear()


## Every item currently on the board, in placement order.
func get_placed_views() -> Array:
	return _cells_by_view.keys()


func show_preview(shape: Array[Vector2i], origin: Vector2i, valid: bool) -> void:
	highlight.show_cells(cells_for(shape, origin), valid)


func clear_preview() -> void:
	highlight.clear()


func _on_quest_changed(quest: QuestData) -> void:
	if quest == null:
		return
	var grid_size := quest.get_grid_size()
	cols = grid_size.x
	rows = grid_size.y
	clear_board()
	_apply_size()


func _apply_size() -> void:
	custom_minimum_size = Vector2(cols, rows) * CELL_SIZE
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	var board := Rect2(Vector2.ZERO, Vector2(cols, rows) * CELL_SIZE)
	draw_rect(board, background_color)
	for y in rows:
		for x in cols:
			var cell := Rect2(cell_to_position(Vector2i(x, y)) + Vector2.ONE * 3, Vector2.ONE * (CELL_SIZE - 6))
			draw_rect(cell, cell_color)
	for x in range(cols + 1):
		var at_x := x * CELL_SIZE
		draw_line(Vector2(at_x, 0), Vector2(at_x, board.size.y), line_color, 2.0)
	for y in range(rows + 1):
		var at_y := y * CELL_SIZE
		draw_line(Vector2(0, at_y), Vector2(board.size.x, at_y), line_color, 2.0)
