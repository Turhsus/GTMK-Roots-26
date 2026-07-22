class_name DraggableItem
extends Control

## One item on screen. It is exactly its shape's bounding box in size, so a 2x1
## item is 192x96 and its top-left corner lines up with a grid cell corner.
## The node reports a grab and then does as it is told — PackingScene owns the
## drag itself, since only it can see both the bag and the tray.

signal grabbed(view: DraggableItem, grab_offset: Vector2)

var item: ItemData
## 90-degree clockwise turns applied to `item.shape`.
var rotation_steps: int = 0
var is_dragging: bool = false

@onready var icon: TextureRect = $Icon


func setup(source: ItemData) -> void:
	item = source
	if is_node_ready():
		_refresh()


func _ready() -> void:
	_refresh()


## The shape this item currently occupies, after rotation.
func get_shape() -> Array[Vector2i]:
	if item == null:
		return []
	return ItemData.rotate_shape(item.shape, rotation_steps)


func rotate_once() -> void:
	rotation_steps = posmod(rotation_steps + 1, 4)
	_refresh()


func reset_rotation() -> void:
	if rotation_steps == 0:
		return
	rotation_steps = 0
	_refresh()


## While dragging the node lives on the drag layer and must not swallow the
## mouse, or the release that ends the drag never reaches PackingScene.
func set_dragging(value: bool) -> void:
	is_dragging = value
	mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	modulate.a = 0.85 if value else 1.0
	if value:
		# The tray's flow container stretches rows to their tallest item, so an
		# item can leave it wider or taller than its shape. Off the container,
		# size must be the shape box again or the snap lands a cell off.
		_refresh()


func _gui_input(event: InputEvent) -> void:
	if is_dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		grabbed.emit(self, event.position)


func _refresh() -> void:
	if item == null:
		return
	custom_minimum_size = Vector2(ItemData.get_shape_size(get_shape())) * BagGrid.CELL_SIZE
	size = custom_minimum_size
	icon.texture = item.icon
	# The art is drawn for the unrotated shape, so the icon keeps its original
	# box and spins inside ours — a 2x1 sprite turned 90 degrees fills our 1x2.
	var art_size := Vector2(item.get_size()) * BagGrid.CELL_SIZE
	icon.size = art_size
	icon.pivot_offset = art_size * 0.5
	icon.rotation_degrees = rotation_steps * 90.0
	icon.position = (size - art_size) * 0.5
	tooltip_text = "%s\n%s" % [item.display_name, item.flavor]
