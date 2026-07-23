class_name DraggableItem
extends Control

## One item on screen. It is exactly its shape's bounding box in size, so a 2x1
## item is 192x96 and its top-left corner lines up with a grid cell corner.
## The node reports a grab and then does as it is told — PackingScene owns the
## drag itself, since only it can see both the bag and the tray.

signal grabbed(view: DraggableItem, grab_offset: Vector2)
## Emitted on a plain click — a press and release that never turns into a drag.
## PackingScene answers it with the stats menu, the same panel the hover tooltip
## shows, so the player can inspect an item without picking it up.
signal clicked(view: DraggableItem)

const HOVER_LIFT := Vector2(0, -6)
## How far the mouse may travel while the button is held before the press stops
## being a click and becomes a drag.
const DRAG_THRESHOLD := 6.0

var item: ItemData
## 90-degree clockwise turns applied to `item.shape`.
var rotation_steps: int = 0
var is_dragging: bool = false

## A left button is down but hasn't moved far enough to drag yet: releasing now
## is a click, crossing DRAG_THRESHOLD starts the drag.
var _press_active := false
var _press_position := Vector2.ZERO

## All juice animates the icon, never this Control: the node's position and size
## are grid truth (snapping, tests), so cosmetic motion lives in an offset the
## icon adds on top of its resting spot.
var juice_offset := Vector2.ZERO:
	set(value):
		juice_offset = value
		if icon != null:
			icon.position = _icon_base + juice_offset

## Where the icon sits when nothing is animating, recomputed by _refresh().
var _icon_base := Vector2.ZERO
## Continuous target angle. Accumulates 90 per rotate so three quarter-turns
## then a fourth spins forward instead of unwinding 270 degrees back to 0.
var _rot_target := 0.0
var _offset_tween: Tween
var _rot_tween: Tween

@onready var icon: TextureRect = $Icon


func setup(source: ItemData) -> void:
	item = source
	if is_node_ready():
		_refresh()


func _ready() -> void:
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))
	_refresh()


## The shape this item currently occupies, after rotation.
func get_shape() -> Array[Vector2i]:
	if item == null:
		return []
	return ItemData.rotate_shape(item.shape, rotation_steps)


func rotate_once() -> void:
	rotation_steps = posmod(rotation_steps + 1, 4)
	_rot_target += 90.0
	_refresh()
	_kill(_rot_tween)
	_rot_tween = create_tween()
	_rot_tween.tween_property(icon, "rotation_degrees", _rot_target, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func reset_rotation() -> void:
	if rotation_steps == 0 and _rot_target == 0.0:
		return
	rotation_steps = 0
	_kill(_rot_tween)
	_rot_target = 0.0
	_refresh()


## While dragging the node lives on the drag layer and must not swallow the
## mouse, or the release that ends the drag never reaches PackingScene.
func set_dragging(value: bool) -> void:
	is_dragging = value
	mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	modulate.a = 0.85 if value else 1.0
	if value:
		# A lifted or mid-shake icon must not carry its offset into the drag.
		_kill(_offset_tween)
		juice_offset = Vector2.ZERO
		# The tray's flow container stretches rows to their tallest item, so an
		# item can leave it wider or taller than its shape. Off the container,
		# size must be the shape box again or the snap lands a cell off.
		_refresh()


## Slides the icon in from where the item visually was when the player let go,
## so a placement reads as a snap instead of a teleport. The node itself is
## already sitting on its cell — only the icon travels.
func play_snap_from(from_global: Vector2) -> void:
	_kill(_offset_tween)
	juice_offset = from_global - global_position
	_offset_tween = create_tween()
	_offset_tween.tween_property(self, "juice_offset", Vector2.ZERO, 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A quick left-right wobble for a drop that didn't fit.
func play_shake() -> void:
	_kill(_offset_tween)
	juice_offset = Vector2.ZERO
	_offset_tween = create_tween()
	for shove in [8.0, -7.0, 5.0, -3.0, 0.0]:
		_offset_tween.tween_property(self, "juice_offset:x", shove, 0.045)


func _gui_input(event: InputEvent) -> void:
	if is_dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			accept_event()
			_press_active = true
			_press_position = event.position
		elif _press_active:
			# Let go without ever crossing the drag threshold: treat it as a
			# click and open the stats menu instead of moving the item.
			accept_event()
			_press_active = false
			clicked.emit(self)
	elif event is InputEventMouseMotion and _press_active:
		if event.position.distance_to(_press_position) > DRAG_THRESHOLD:
			_press_active = false
			grabbed.emit(self, _press_position)


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
	# The rotate tween owns the angle while it runs; everyone else lands it.
	if _rot_tween == null or not _rot_tween.is_running():
		icon.rotation_degrees = _rot_target
	_icon_base = (size - art_size) * 0.5
	icon.position = _icon_base + juice_offset
	# Non-empty so Godot's hover timer arms; the shown content is built by
	# _make_custom_tooltip() below, not from this string.
	tooltip_text = item.display_name


## Godot calls this when the hover tooltip is due (after the project's tooltip
## delay). Returning the shared panel makes the hover tooltip and the click menu
## literally the same view of the item.
func _make_custom_tooltip(_for_text: String) -> Object:
	return build_info_panel(item)


## The "what would this add" panel: the item's name, every stat it contributes,
## and its flavor line. Static so PackingScene can raise the very same panel on a
## click without redoing the layout.
static func build_info_panel(source: ItemData) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.08, 0.98)
	style.border_color = Color(0.55, 0.42, 0.26)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = source.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	box.add_child(name_label)

	var stat_added := false
	var stats := source.get_stats()
	for key in GameState.STAT_KEYS:
		var value := int(stats.get(key, 0))
		if value == 0:
			continue
		stat_added = true
		var row := Label.new()
		row.text = "%s %+d" % [key.capitalize(), value]
		row.add_theme_color_override("font_color", Color("7aa356"))
		box.add_child(row)
	if not stat_added:
		var none_label := Label.new()
		none_label.text = "No stat bonus"
		none_label.add_theme_color_override("font_color", Color("9a8f80"))
		box.add_child(none_label)

	# Durability — how many more trips this copy has in it. Single-use items say so;
	# sturdier ones show trips left out of the total.
	var dura := Label.new()
	if source.max_durability > 1:
		if source.durability >= 0 and source.durability < source.max_durability:
			dura.text = "Durability: %d of %d trips left" % [source.durability, source.max_durability]
		else:
			dura.text = "Durability: lasts %d trips" % source.max_durability
	else:
		dura.text = "Single use"
	dura.add_theme_color_override("font_color", Color("9a8f80"))
	box.add_child(dura)

	if source.flavor != "":
		var flavor := Label.new()
		flavor.text = source.flavor
		flavor.add_theme_color_override("font_color", Color("c9bba8"))
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor.custom_minimum_size.x = 220
		box.add_child(flavor)

	return panel


func _on_hover_changed(hovered: bool) -> void:
	if is_dragging or icon == null:
		return
	_kill(_offset_tween)
	_offset_tween = create_tween()
	_offset_tween.tween_property(self, "juice_offset", HOVER_LIFT if hovered else Vector2.ZERO, 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
