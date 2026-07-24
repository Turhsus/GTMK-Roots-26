@tool
class_name BagGrid
extends Control

## The bag board. Size is owned by the run (RunState.bag_tier → cols×rows); this
## node fills its editor rectangle with square cells that fit that board — smaller
## bags get larger cells inside the same frame. Owns cell <-> pixel math and the
## occupancy map. GameState owns *what* is packed; this knows *where*.

## Default / editor preview size when nothing has called resize_board yet.
const DEFAULT_COLS := 6
const DEFAULT_ROWS := 6

@export var background_color := Color("2c211b")
@export var cell_color := Color("3d2f26")
@export var line_color := Color("554236")

## Live board dimensions. Changed by resize_board (packing applies RunState).
var cols: int = DEFAULT_COLS
var rows: int = DEFAULT_ROWS

## Pixels per cell, derived from this node's rect and current cols/rows so cells
## stay square. Shared statically so DraggableItem and GridHighlight match the
## board without a reference here; _enter_tree seeds it before the tray's _ready.
var cell_size: float = 96.0
static var _shared_cell_size: float = 96.0


## The cell size every DraggableItem and the highlight must size themselves to.
static func current_cell_size() -> float:
	return _shared_cell_size

## Placed items are parented here so they inherit the grid's origin — their
## position is just cell_to_position(cell).
@onready var item_layer: Control = $ItemLayer
@onready var highlight: GridHighlight = $Highlight

## Vector2i -> DraggableItem, one entry per occupied cell.
var _occupancy: Dictionary = {}
## DraggableItem -> Array[Vector2i], so removal doesn't have to scan the board.
var _cells_by_view: Dictionary = {}


# Seed the shared cell size from the node's rect before anything reads it — this
# runs top-down as the scene enters the tree, ahead of the tray's _ready.
func _enter_tree() -> void:
	_recompute_cell_size()


func _ready() -> void:
	# The node's rect is the source of truth for cell size, so track its changes.
	resized.connect(_recompute_cell_size)
	_recompute_cell_size()
	# The editor only needs the live grid preview; the rest is runtime wiring.
	if Engine.is_editor_hint():
		return
	GameState.quest_changed.connect(_on_quest_changed)
	if GameState.current_quest != null:
		_on_quest_changed(GameState.current_quest)


## Sets the board to `new_cols` × `new_rows`, clears occupancy, and recomputes
## cell size. Caller must free or re-home any placed views first.
func resize_board(new_cols: int, new_rows: int) -> void:
	cols = maxi(new_cols, 1)
	rows = maxi(new_rows, 1)
	clear_board()
	_recompute_cell_size()
	queue_redraw()


## Top-left pixel of a cell, relative to the grid's own origin.
func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell) * cell_size


## The cell containing a point given in the grid's local space. May be out of
## bounds — callers check with is_in_bounds().
func position_to_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(floori(local_position.x / cell_size), floori(local_position.y / cell_size))


## The cell an item's top-left corner snaps to, for a point in local space.
## Rounds rather than floors so a shape half a cell over still lands where the
## player aimed.
func snap_to_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(roundi(local_position.x / cell_size), roundi(local_position.y / cell_size))


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


## Top-left cell of a placed item, or (-1, -1) if it isn't on the board.
func get_origin(view: DraggableItem) -> Vector2i:
	if not _cells_by_view.has(view):
		return Vector2i(-1, -1)
	var origin: Vector2i = _cells_by_view[view][0]
	for cell in _cells_by_view[view]:
		origin = Vector2i(mini(origin.x, cell.x), mini(origin.y, cell.y))
	return origin


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


## A quest switch only clears the board — bag size comes from RunState via
## PackingScene.resize_board, not from the quest.
func _on_quest_changed(quest: QuestData) -> void:
	if quest == null:
		return
	clear_board()
	queue_redraw()


## Derive square cell size from the node's rect and current cols/rows, then
## re-lay any placed items. Smaller boards get larger cells in the same frame.
func _recompute_cell_size() -> void:
	var derived := maxf(1.0, minf(size.x / float(cols), size.y / float(rows)))
	if is_equal_approx(derived, cell_size) and is_equal_approx(derived, _shared_cell_size):
		queue_redraw()
		return
	cell_size = derived
	_shared_cell_size = derived
	_relayout_placed()
	queue_redraw()


## Re-position and re-size every item currently on the board for the current cell
## size — its cells don't change, only how big and where each one is drawn.
func _relayout_placed() -> void:
	for view in _cells_by_view.keys():
		var origin: Vector2i = _cells_by_view[view][0]
		for cell in _cells_by_view[view]:
			origin = Vector2i(mini(origin.x, cell.x), mini(origin.y, cell.y))
		if view.has_method("setup"):
			view.setup(view.item)
		view.position = cell_to_position(origin)
		view.size = view.custom_minimum_size


func _draw() -> void:
	var board := Rect2(Vector2.ZERO, Vector2(cols, rows) * cell_size)
	draw_rect(board, background_color)
	for y in rows:
		for x in cols:
			var cell := Rect2(cell_to_position(Vector2i(x, y)) + Vector2.ONE * 3, Vector2.ONE * (cell_size - 6))
			draw_rect(cell, cell_color)
	for x in range(cols + 1):
		var at_x := x * cell_size
		draw_line(Vector2(at_x, 0), Vector2(at_x, board.size.y), line_color, 2.0)
	for y in range(rows + 1):
		var at_y := y * cell_size
		draw_line(Vector2(0, at_y), Vector2(board.size.x, at_y), line_color, 2.0)
