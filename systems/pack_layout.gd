class_name PackLayout
extends RefCounted

## An immutable snapshot of the bag exactly as it was sent off: where each packed
## item sits, how it's turned, and what fills every cell. Item effects query this to
## decide their placement penalties (see ItemEffect), so the bag is worn by *how* it
## was packed, not just by the trip.
##
## Built once by BagGrid.snapshot() at send-off and thrown away after send-off wear —
## nothing keeps a reference, so it never drifts out of sync with the live board.
## Keyed by the ItemData instance, which is safe because the packed items in
## GameState are the very same instances the placed views hold (identity, not id).

## One placed item's footprint on the board. Internal — callers read it through the
## query helpers below rather than reaching for the record.
class Placement:
	var item: ItemData
	var origin: Vector2i
	var rotation_steps: int
	var cells: Array[Vector2i]

## ItemData -> Placement.
var _by_item: Dictionary = {}
## Vector2i -> ItemData, one entry per occupied cell, for neighbour / above lookups.
var _by_cell: Dictionary = {}


## Records one item's footprint. BagGrid calls this per placed view while building
## the snapshot; `cells` is the item's occupied cells (already rotated).
func add(item: ItemData, origin: Vector2i, rotation_steps: int, cells: Array[Vector2i]) -> void:
	var placement := Placement.new()
	placement.item = item
	placement.origin = origin
	placement.rotation_steps = rotation_steps
	placement.cells = cells
	_by_item[item] = placement
	for cell in cells:
		_by_cell[cell] = item


## How many quarter-turns the item was packed with, or -1 if it isn't on the board.
## 2 is upside down (see NoUpsideDownEffect).
func rotation_of(item: ItemData) -> int:
	if not _by_item.has(item):
		return -1
	return (_by_item[item] as Placement).rotation_steps


## The item occupying a cell, or null if that cell is empty (or off the board).
func item_at(cell: Vector2i) -> ItemData:
	return _by_cell.get(cell, null)


## Whether any packed item fills this cell. Off-board cells read as empty.
func is_filled(cell: Vector2i) -> bool:
	return _by_cell.has(cell)


## The distinct items edge-adjacent to the given item — anything sharing a cell wall
## with it, itself excluded. Diagonals don't count as neighbours. Pass `dirs` to look
## only across specific edges (e.g. [Vector2i.UP]); it defaults to all four sides.
func neighbours_of(item: ItemData, dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]) -> Array[ItemData]:
	var found: Array[ItemData] = []
	if not _by_item.has(item):
		return found
	var placement := _by_item[item] as Placement
	var own := {}
	for cell in placement.cells:
		own[cell] = true
	for cell in placement.cells:
		for dir in dirs:
			var neighbour_cell: Vector2i = cell + dir
			if own.has(neighbour_cell):
				continue
			var other: ItemData = _by_cell.get(neighbour_cell, null)
			if other != null and other != item and not found.has(other):
				found.append(other)
	return found


## The cells directly above the item's footprint, up to `rows` rows up — the space
## over its top edge in each column it spans. Used by "keep the space above clear".
## Cells off the top of the board are included (they simply read as empty).
func cells_above(item: ItemData, rows: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _by_item.has(item):
		return result
	var placement := _by_item[item] as Placement
	# Topmost occupied row per column — the cell just above that is the item's "air".
	var top_by_col := {}
	for cell in placement.cells:
		if not top_by_col.has(cell.x) or cell.y < top_by_col[cell.x]:
			top_by_col[cell.x] = cell.y
	for col in top_by_col:
		for step in range(1, maxi(rows, 1) + 1):
			result.append(Vector2i(col, top_by_col[col] - step))
	return result
