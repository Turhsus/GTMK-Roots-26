extends Control

## Packing screen: the bag on the left, the tray on the right. Until Main.tscn
## owns the flow (brief -> packing -> playout), this scene loads the quest
## itself so the grid and tray can be playtested on their own.
##
## It also drives the drag, because it is the only node that can see both the
## bag and the tray. A grabbed item is reparented to DragLayer (above
## everything, clipped by nothing), follows the mouse, and on release either
## snaps into the bag or goes home to the tray. This is deliberately hand-rolled
## grid math rather than Godot's _get_drag_data, which only understands
## rectangles.

const QUEST: QuestData = preload("res://data/quests/whisper_woods.tres")

@onready var quest_title: Label = %QuestTitle
@onready var bag_grid: BagGrid = %BagGrid
@onready var item_tray: ItemTray = %ItemTray
@onready var drag_layer: Control = %DragLayer

var _dragging: DraggableItem = null
## Where inside the item the player grabbed it, so it doesn't jump to a corner.
var _grab_offset := Vector2.ZERO
var _preview_origin := Vector2i.ZERO
var _preview_valid: bool = false


func _ready() -> void:
	set_process(false)
	quest_title.text = QUEST.title
	# Connect before the quest lands, or the tray's first populate goes unheard.
	item_tray.item_ready.connect(_on_item_ready)
	GameState.set_quest(QUEST)


func _process(_delta: float) -> void:
	if _dragging == null:
		return
	_dragging.global_position = get_global_mouse_position() - _grab_offset
	_update_preview()


## Runs ahead of the GUI so the drag owns the mouse: a Control under the cursor
## would otherwise eat the release that ends it.
func _input(event: InputEvent) -> void:
	if _dragging == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_rotate_dragged()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_end_drag(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_rotate_dragged()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag(true)
			get_viewport().set_input_as_handled()


func _on_item_ready(view: DraggableItem) -> void:
	view.grabbed.connect(_on_item_grabbed)


func _on_item_grabbed(view: DraggableItem, grab_offset: Vector2) -> void:
	if _dragging != null:
		return
	# Picking an item back up frees its cells and un-packs it; dropping it
	# re-adds it. A move across the bag is just those two halves.
	if bag_grid.remove(view):
		GameState.remove_item(view.item)
	_dragging = view
	view.set_dragging(true)
	# set_dragging() may have shrunk the item back to its shape box, so the grab
	# point the tray reported can now be outside it.
	_grab_offset = grab_offset.clamp(Vector2.ZERO, view.size)
	view.reparent(drag_layer, true)
	set_process(true)
	_update_preview()


func _rotate_dragged() -> void:
	_dragging.rotate_once()
	# The bounding box just changed shape; keep the grab inside it.
	_grab_offset = _grab_offset.clamp(Vector2.ZERO, _dragging.size)
	AudioManager.play("rotate")
	_update_preview()


## Snaps the dragged item's top-left to a cell and asks the bag whether it fits.
func _update_preview() -> void:
	var shape := _dragging.get_shape()
	_preview_origin = bag_grid.snap_global_to_cell(_dragging.global_position)
	_preview_valid = false
	var over_board := false
	for cell in BagGrid.cells_for(shape, _preview_origin):
		if bag_grid.is_in_bounds(cell):
			over_board = true
			break
	if not over_board:
		bag_grid.clear_preview()
		return
	_preview_valid = bag_grid.can_place(shape, _preview_origin)
	bag_grid.show_preview(shape, _preview_origin, _preview_valid)


## `attempt_drop` is false for a cancel (Escape), which always goes to the tray.
func _end_drag(attempt_drop: bool) -> void:
	var view := _dragging
	_dragging = null
	set_process(false)
	bag_grid.clear_preview()
	view.set_dragging(false)
	if attempt_drop and _preview_valid:
		bag_grid.place(view, _preview_origin)
		GameState.add_item(view.item)
		AudioManager.play("place")
		return
	if attempt_drop and _was_over_board(view):
		AudioManager.play("invalid")
	item_tray.adopt(view)


## Distinguishes "tried to place it and it didn't fit" from "carried it back to
## the tray on purpose" — only the first deserves the invalid sting.
func _was_over_board(view: DraggableItem) -> bool:
	for cell in BagGrid.cells_for(view.get_shape(), _preview_origin):
		if bag_grid.is_in_bounds(cell):
			return true
	return false
