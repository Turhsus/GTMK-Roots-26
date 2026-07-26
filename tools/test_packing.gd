extends Node

## Throwaway harness: exercises the packing drag end-to-end without a mouse.
## Run: godot --headless --path . res://tools/TestPacking.tscn
## (a scene, not --script, so the GameState/AudioManager autoloads exist)

const PACKING := preload("res://scenes/packing/PackingScene.tscn")

var failures: int = 0


func _ready() -> void:
	RunState.reset()
	var scene := PACKING.instantiate()
	add_child(scene)
	await get_tree().process_frame

	var bag: BagGrid = scene.get_node("%BagGrid")
	var tray = scene.get_node("%ItemTray")
	var drag_layer: Control = scene.get_node("%DragLayer")
	# item_views(), not get_children(): the container also holds the sort divider.
	var views: Array = tray.item_views()

	var stock_size: int = RunState.inventory.size()
	check(views.size() == stock_size, "tray spawned the whole inventory, got %d of %d" % [views.size(), stock_size])
	check(bag.cols == RunState.bag_cols() and bag.rows == RunState.bag_rows(),
		"bag matches the run's backpack size (%dx%d)" % [RunState.bag_cols(), RunState.bag_rows()])
	# Read the starting size off BAG_SIZES rather than writing it out — the ladder
	# went from [4,5,6] to [3,4,5,6], and a hardcoded 4 just encodes the old tuning.
	var start_size: int = RunState.BAG_SIZES[0]
	check(bag.cols == start_size and bag.rows == start_size,
		"a fresh run starts with a %dx%d bag" % [start_size, start_size])

	var sword: DraggableItem = _find(views, "sword")
	check(sword != null, "sword is in the tray")

	# --- bounds ---
	check(bag.can_place(sword.get_shape(), Vector2i(0, 0)), "sword fits at origin")
	check(not bag.can_place(sword.get_shape(), Vector2i(-1, 0)), "sword rejected off the left edge")
	var tall := ItemData.get_shape_size(sword.get_shape())
	check(not bag.can_place(sword.get_shape(), Vector2i(0, bag.rows - tall.y + 1)),
		"sword rejected hanging off the bottom")

	# --- place + collision ---
	scene._on_item_grabbed(sword, Vector2.ZERO)
	check(sword.get_parent() == drag_layer, "grabbed item moves to the drag layer")
	scene._preview_origin = Vector2i(0, 0)
	scene._preview_valid = true
	scene._end_drag(true)
	check(sword.get_parent() == bag.item_layer, "dropped item is parented into the bag")
	check(sword.position == Vector2.ZERO, "dropped item snapped to cell (0,0)")
	check(GameState.packed_items.has(sword.item), "dropping packs the item in GameState")
	check(not bag.is_cell_free(Vector2i(0, 0)), "cell (0,0) is now taken")
	check(not bag.can_place(sword.get_shape(), Vector2i(0, 0)), "collision blocks a second item there")

	# --- stats ---
	var stats_panel = scene.get_node("%StatsPanel")
	check(GameState.stats["combat"] == sword.item.combat,
		"packing the sword sets combat to its contribution (%d)" % sword.item.combat)
	var combat_row: Dictionary = stats_panel._rows["combat"]
	check((combat_row["value"] as Label).text ==
			"%d / %d" % [sword.item.combat, GameState.get_targets()["combat"]],
		"the combat row reads current / target, got '%s'" % (combat_row["value"] as Label).text)

	# --- snapping math (relative to current cell size) ---
	var cell := BagGrid.current_cell_size()
	check(bag.snap_to_cell(Vector2(cell * 2.0 + 8.0, 40.0)) == Vector2i(2, 0),
		"a point past the midpoint of cell 2 still snaps to cell 2")
	check(bag.snap_to_cell(Vector2(-40.0, -40.0)) == Vector2i(0, 0), "near-miss above/left snaps back in")

	# --- rotation (the knife is the 2x1 in the starter pack) ---
	# custom_minimum_size, not size: in the tray the flow container stretches
	# items to the row height, so `size` is not the shape box there.
	# This used to rotate a bread, which is no longer in STARTER_INVENTORY.
	var knife: DraggableItem = _find(views, "knife")
	check(knife != null, "the knife is in the tray for rotation tests")
	# Two boxes, not one. A tray view draws at ItemTray.TRAY_SCALE, and grabbing it
	# snaps display_scale back to 1.0 so what you drag is what you drop. This block
	# used to measure the tray box and then assert board-scale facts against it,
	# which only passed while TRAY_SCALE was 1.0.
	var board_box := Vector2(2, 1) * cell
	var tray_box := board_box * ItemTray.TRAY_SCALE
	var before := knife.custom_minimum_size
	check(before.is_equal_approx(tray_box),
		"the knife is a 2x1 box at tray scale, got %s want %s" % [before, tray_box])
	knife.rotate_once()
	check(knife.custom_minimum_size == Vector2(before.y, before.x),
		"rotating swaps the bounding box: %s -> %s" % [before, knife.custom_minimum_size])
	check(bag.can_place(knife.get_shape(), Vector2i(0, bag.rows - 1)) == false,
		"a rotated 1x2 no longer fits on the bottom row")
	knife.rotate_once()
	knife.rotate_once()
	knife.rotate_once()
	check(knife.custom_minimum_size == before, "four rotations return to the start")

	# A drag must leave the tray at true shape size, not the stretched one.
	scene._on_item_grabbed(knife, Vector2(150, 150))
	check(knife.size.is_equal_approx(board_box),
		"dragged item is its shape box, got %s want %s" % [knife.size, board_box])
	check(scene._grab_offset.x <= board_box.x and scene._grab_offset.y <= board_box.y,
		"grab offset clamped into the item, got %s" % scene._grab_offset)
	scene._end_drag(false)

	# --- remove back to tray ---
	scene._on_item_grabbed(sword, Vector2.ZERO)
	check(bag.is_cell_free(Vector2i(0, 0)), "picking an item back up frees its cells")
	check(not GameState.packed_items.has(sword.item), "picking up un-packs it in GameState")
	scene._preview_valid = false
	scene._preview_origin = Vector2i(99, 99)
	scene._end_drag(true)
	check(sword.get_parent() == tray.item_container, "an invalid drop returns to the tray")
	check(sword.rotation_steps == 0, "returning to the tray resets rotation")
	check(GameState.stats["combat"] == 0, "un-packing takes the stat back off")

	# --- a drag out of the bag must not leave the grid owning the gesture ---
	# BagGrid latches the view a press landed on, but a press that becomes a drag
	# has its release eaten by PackingScene, so the latch is never cleared there.
	# If it survives, the next press on the board is forwarded to an item that is
	# now sitting in the tray, and the smallest nudge drags it back out.
	bag.place(sword, Vector2i(0, 0))
	GameState.add_item(sword.item)
	bag._input_owner = sword
	scene._on_item_grabbed(sword, Vector2.ZERO)
	scene._preview_valid = false
	scene._preview_origin = Vector2i(99, 99)
	scene._end_drag(true)
	check(sword.get_parent() == tray.item_container, "the dragged-out sword is back in the tray")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = bag.global_position + Vector2(cell * 1.5, cell * 1.5)
	press.position = press.global_position - bag.global_position
	bag._gui_input(press)
	check(bag._input_owner == null, "a press on an empty cell claims no gesture owner")
	check(not sword._press_active, "a press on the board is not forwarded to an item in the tray")

	# --- resize board ---
	# Clear any remaining occupancy, then shrink: a 1x3 sword must not fit on a
	# row that doesn't exist on a 4x4... already 4x4. Grow to 6x6 and place at
	# a cell that was out of bounds before.
	bag.resize_board(4, 4)
	check(not bag.can_place(sword.get_shape(), Vector2i(0, 2)),
		"on 4x4 a 1x3 sword cannot start at row 2")
	bag.resize_board(6, 6)
	check(bag.cols == 6 and bag.rows == 6, "resize_board grows to 6x6")
	check(bag.can_place(sword.get_shape(), Vector2i(0, 3)),
		"on 6x6 a 1x3 sword fits starting at row 3")
	bag.resize_board(4, 4)
	check(not bag.can_place(sword.get_shape(), Vector2i(0, 3)),
		"shrinking back to 4x4 rejects the old out-of-bounds cell")

	# --- pack again ---
	GameState.reset_packing()
	check(GameState.packed_items.is_empty(), "reset_packing empties the bag")
	for key in GameState.STAT_KEYS:
		check(GameState.stats[key] == 0, "reset zeroes %s" % key)

	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find(views: Array, id: String) -> DraggableItem:
	for view in views:
		if view.item != null and view.item.id == id:
			return view
	return null


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)
