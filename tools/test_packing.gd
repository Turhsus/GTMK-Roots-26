extends Node

## Throwaway harness: exercises the packing drag end-to-end without a mouse.
## Run: godot --headless --path . res://tools/TestPacking.tscn
## (a scene, not --script, so the GameState/AudioManager autoloads exist)

const PACKING := preload("res://scenes/packing/PackingScene.tscn")

var failures: int = 0


func _ready() -> void:
	var scene := PACKING.instantiate()
	add_child(scene)
	await get_tree().process_frame

	var bag: BagGrid = scene.get_node("%BagGrid")
	var tray = scene.get_node("%ItemTray")
	var drag_layer: Control = scene.get_node("%DragLayer")
	var views: Array = tray.item_container.get_children()

	var stock_size: int = RunState.inventory.size()
	check(views.size() == stock_size, "tray spawned the whole inventory, got %d of %d" % [views.size(), stock_size])
	check(bag.cols == 6 and bag.rows == 6, "bag is 6x6")

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
	check(GameState.stats["attack"] == sword.item.attack,
		"packing the sword sets attack to its contribution (%d)" % sword.item.attack)
	var attack_row: Dictionary = stats_panel._rows["attack"]
	check((attack_row["value"] as Label).text ==
			"%d / %d" % [sword.item.attack, GameState.get_targets()["attack"]],
		"the attack row reads current / target, got '%s'" % (attack_row["value"] as Label).text)
	check((attack_row["bar"] as ProgressBar).max_value == GameState.get_targets()["attack"],
		"a bar's full mark is the quest target")

	# --- snapping math ---
	check(bag.snap_to_cell(Vector2(200.0, 40.0)) == Vector2i(2, 0),
		"a point 8 px past cell 2 still snaps to cell 2")
	check(bag.snap_to_cell(Vector2(-40.0, -40.0)) == Vector2i(0, 0), "near-miss above/left snaps back in")

	# --- rotation ---
	# custom_minimum_size, not size: in the tray the flow container stretches
	# items to the row height, so `size` is not the shape box there.
	var rope: DraggableItem = _find(views, "rope")
	var cell := BagGrid.current_cell_size()
	var before := rope.custom_minimum_size
	check(before == Vector2(2, 1) * cell, "rope is a 2x1 box, got %s" % before)
	rope.rotate_once()
	check(rope.custom_minimum_size == Vector2(before.y, before.x),
		"rotating swaps the bounding box: %s -> %s" % [before, rope.custom_minimum_size])
	check(bag.can_place(rope.get_shape(), Vector2i(0, bag.rows - 1)) == false,
		"a rotated 1x2 no longer fits on the bottom row")
	rope.rotate_once()
	rope.rotate_once()
	rope.rotate_once()
	check(rope.custom_minimum_size == before, "four rotations return to the start")

	# A drag must leave the tray at true shape size, not the stretched one.
	scene._on_item_grabbed(rope, Vector2(150, 150))
	check(rope.size == before, "dragged item is its shape box, got %s" % rope.size)
	check(scene._grab_offset.x <= before.x and scene._grab_offset.y <= before.y,
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
	check(GameState.stats["attack"] == 0, "un-packing takes the stat back off")

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
