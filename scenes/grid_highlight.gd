class_name GridHighlight
extends Control

## Placement preview, drawn as an overlay above BagGrid's ItemLayer so the
## green/red cells stay visible even when something is already sitting there.

@export var valid_color := Color(0.44, 0.75, 0.45, 0.55)
@export var invalid_color := Color(0.78, 0.35, 0.33, 0.55)

var _cells: Array[Vector2i] = []
var _valid: bool = false


## Cells are grid coordinates; out-of-bounds ones are clipped away by the node.
func show_cells(cells: Array[Vector2i], valid: bool) -> void:
	_cells = cells
	_valid = valid
	queue_redraw()


func clear() -> void:
	if _cells.is_empty():
		return
	_cells = []
	queue_redraw()


func _draw() -> void:
	var color := valid_color if _valid else invalid_color
	for cell in _cells:
		var rect := Rect2(
			Vector2(cell) * BagGrid.CELL_SIZE + Vector2.ONE * 3,
			Vector2.ONE * (BagGrid.CELL_SIZE - 6)
		)
		draw_rect(rect, color)
