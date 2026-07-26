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

## The playable board this snapshot was taken from, in cells — the run's current bag
## tier, not the 6x6 frame it is drawn inside (see BagGrid). Only free_cell_count()
## needs it: "how much room is left" is meaningless without knowing how much there was.
## Left at 0 by anything that builds a layout by hand (the tests, a hypothetical
## packing), which reads as "nobody measured a board" rather than "no room".
## Named `board_*` rather than `cols`/`rows` because `cells_above` already takes a
## `rows` argument meaning something else entirely.
var board_cols: int = 0
var board_rows: int = 0

## ItemData -> Placement.
var _by_item: Dictionary = {}
## Vector2i -> ItemData, one entry per occupied cell, for neighbour / above lookups.
var _by_cell: Dictionary = {}


## Records the playable board size. BagGrid.snapshot() calls this from the current
## bag tier before adding any placement.
func set_board_size(new_cols: int, new_rows: int) -> void:
	board_cols = maxi(new_cols, 0)
	board_rows = maxi(new_rows, 0)


## How many playable cells nothing is packed in, or -1 when no board size was recorded
## (see board_cols/board_rows) — an unmeasured board has to read as "unknown" so a
## hand-built layout can't accidentally fail a quest's room requirement.
##
## The one implementation of this count: the live packing readout and the send-off
## verdict both read it off a snapshot, so the number the player is shown while packing
## is by construction the number the quest is judged against.
func free_cell_count() -> int:
	if board_cols <= 0 or board_rows <= 0:
		return -1
	var filled := 0
	for cell in _by_cell:
		if cell.x >= 0 and cell.y >= 0 and cell.x < board_cols and cell.y < board_rows:
			filled += 1
	return maxi(board_cols * board_rows - filled, 0)


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


## Every item on the board, in the order they were recorded. What a whole-bag rule
## reads instead of walking cells — "is there anything sharp in here at all", which
## no neighbour or column query can answer (see NoTraitInBagEffect).
func packed_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	items.assign(_by_item.keys())
	return items


## Whether this item is on the board at all. A rule that fires on the *absence* of
## something has to ask first: an item still sitting in the tray has no neighbours
## either, and must read as dormant rather than as a violation (see
## RequiresAdjacentTraitEffect).
func contains(item: ItemData) -> bool:
	return _by_item.has(item)


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


## The cells inside this item's own bounding box that its shape does *not* fill — the
## hollow of a C- or U-shaped item: the helmet's crown, the boot's opening. Read off
## the placed cells, so it is already turned with the item and needs no rotation math
## of its own. Empty for a solid rectangle, and for an item that isn't on the board.
func hollow_cells(item: ItemData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _by_item.has(item):
		return result
	var placement := _by_item[item] as Placement
	if placement.cells.is_empty():
		return result
	var own := {}
	var top_left: Vector2i = placement.cells[0]
	var bottom_right: Vector2i = placement.cells[0]
	for cell in placement.cells:
		own[cell] = true
		top_left = Vector2i(mini(top_left.x, cell.x), mini(top_left.y, cell.y))
		bottom_right = Vector2i(maxi(bottom_right.x, cell.x), maxi(bottom_right.y, cell.y))
	for y in range(top_left.y, bottom_right.y + 1):
		for x in range(top_left.x, bottom_right.x + 1):
			var cell := Vector2i(x, y)
			if not own.has(cell):
				result.append(cell)
	return result


## The distinct items packed *inside* this one — every cell they occupy falls in its
## hollow (see hollow_cells). What a nesting rule reads: the apple in the helmet, the
## knife in the boot. Something merely poking into the opening is not "within" and is
## left out, so a rule can't be half-claimed by an item that mostly sits outside (see
## ContainsItemEffect).
func items_within(item: ItemData) -> Array[ItemData]:
	var found: Array[ItemData] = []
	var hollow := {}
	for cell in hollow_cells(item):
		hollow[cell] = true
	for cell in hollow:
		var other: ItemData = _by_cell.get(cell, null)
		if other == null or other == item or found.has(other):
			continue
		if _is_covered_by(other, hollow):
			found.append(other)
	return found


## Whether every cell `item` occupies is in `cells` (a set keyed by Vector2i).
func _is_covered_by(item: ItemData, cells: Dictionary) -> bool:
	if not _by_item.has(item):
		return false
	for cell in (_by_item[item] as Placement).cells:
		if not cells.has(cell):
			return false
	return true


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
