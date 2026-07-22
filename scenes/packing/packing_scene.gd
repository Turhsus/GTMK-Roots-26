class_name PackingScene
extends Control

## Packing screen: the bag on the left, the tray on the right. Main owns the
## flow and sets the quest before this scene enters the tree; if nobody has
## (running PackingScene.tscn on its own, or the test harness), it loads the
## quest itself so the grid and tray can still be playtested standalone.
##
## It also drives the drag, because it is the only node that can see both the
## bag and the tray. A grabbed item is reparented to DragLayer (above
## everything, clipped by nothing), follows the mouse, and on release either
## snaps into the bag or goes home to the tray. This is deliberately hand-rolled
## grid math rather than Godot's _get_drag_data, which only understands
## rectangles.

## Raised when the player is done packing. Main turns it into a playout; the
## bag is left exactly as packed so the log can be built from it.
signal sent_off

const QUEST: QuestData = preload("res://data/quests/whisper_woods.tres")

@onready var quest_title: Label = %QuestTitle
@onready var bag_grid: BagGrid = %BagGrid
@onready var item_tray: ItemTray = %ItemTray
@onready var drag_layer: Control = %DragLayer
@onready var send_button: Button = %SendButton

var _dragging: DraggableItem = null
## Where inside the item the player grabbed it, so it doesn't jump to a corner.
var _grab_offset := Vector2.ZERO
var _preview_origin := Vector2i.ZERO
var _preview_valid: bool = false


func _ready() -> void:
	set_process(false)
	item_tray.item_ready.connect(_on_item_ready)
	# The tray is a child, so its _ready() ran before this one. If the quest was
	# already set by then (Main does that), it has *already* populated and fired
	# item_ready for every item into an empty signal. Sweep up what is there.
	for view in item_tray.item_container.get_children():
		_on_item_ready(view)
	GameState.quest_changed.connect(_on_quest_changed)
	send_button.pressed.connect(_on_send_pressed)
	if GameState.current_quest == null:
		GameState.set_quest(QUEST)
	else:
		_on_quest_changed(GameState.current_quest)


## Empties the bag and puts every item back in the tray — this is "Pack again".
## The views are the same nodes throughout, so returning them is a reparent.
func reset_packing() -> void:
	for view in bag_grid.get_placed_views():
		item_tray.adopt(view)
	bag_grid.clear_board()
	bag_grid.clear_preview()
	GameState.reset_packing()


func _on_quest_changed(quest: QuestData) -> void:
	if quest == null:
		return
	quest_title.text = quest.title


func _on_send_pressed() -> void:
	AudioManager.play("send")
	sent_off.emit()


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


## Idempotent: an item can arrive both through the signal and through the
## catch-up sweep in _ready(), and connecting twice would start two drags.
func _on_item_ready(view: DraggableItem) -> void:
	if not view.grabbed.is_connected(_on_item_grabbed):
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
		var released_at := view.global_position
		bag_grid.place(view, _preview_origin)
		GameState.add_item(view.item)
		view.play_snap_from(released_at)
		AudioManager.play("place")
		return
	var rejected := attempt_drop and _was_over_board(view)
	if rejected:
		AudioManager.play("invalid")
	item_tray.adopt(view)
	if rejected:
		# After adopt, so the tray's re-layout doesn't swallow the wobble.
		view.play_shake()


## Distinguishes "tried to place it and it didn't fit" from "carried it back to
## the tray on purpose" — only the first deserves the invalid sting.
func _was_over_board(view: DraggableItem) -> bool:
	for cell in BagGrid.cells_for(view.get_shape(), _preview_origin):
		if bag_grid.is_in_bounds(cell):
			return true
	return false
