extends Node

## Throwaway harness for the full loop: brief -> packing -> send off -> playout
## -> pack again, plus NarrativeEngine's conditioning on its own.
## Run: godot --headless --path . res://tools/TestFlow.tscn

const MAIN := preload("res://scenes/Main.tscn")
const QUEST: QuestData = preload("res://data/quests/whisper_woods.tres")

var failures: int = 0


func _ready() -> void:
	_test_engine()
	await _test_flow()

	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


# --- NarrativeEngine, with no scene tree involved at all -----------------------

func _test_engine() -> void:
	check(not QUEST.narrative.is_empty(), "the quest has authored beats, got %d" % QUEST.narrative.size())

	var empty: Array[ItemData] = []
	var lines := NarrativeEngine.build_log(QUEST, empty, _stats(0, 0, 0, 0))
	# Departure + every beat + homecoming: with a fallback variant on each beat,
	# nothing may be silently dropped.
	check(lines.size() == QUEST.narrative.size() + 2,
		"an empty bag still gets every beat, got %d lines" % lines.size())
	check(lines[0].contains("empty"), "the empty bag gets its own departure line")
	for i in lines.size():
		check(not lines[i].strip_edges().is_empty(), "line %d is not blank" % i)

	# Two packings that differ only in tags must read differently.
	var with_map := _log_for([_item("map")])
	var with_lantern := _log_for([_item("lantern")])
	check(with_map[1] != with_lantern[1], "a map and a lantern give different day-one beats")
	check(with_map[1].contains("map"), "packing the map picks the map variant")

	# Priority is authoring order: map beats lantern when both are packed.
	var with_both := _log_for([_item("map"), _item("lantern")])
	check(with_both[1] == with_map[1], "the first matching variant wins over a later one")

	# Stat thresholds.
	var fed := NarrativeEngine.build_log(QUEST, empty, _stats(8, 0, 0, 0))
	var peckish := NarrativeEngine.build_log(QUEST, empty, _stats(4, 0, 0, 0))
	var starving := NarrativeEngine.build_log(QUEST, empty, _stats(0, 0, 0, 0))
	check(fed[2] != peckish[2] and peckish[2] != starving[2],
		"food 8 / 4 / 0 give three different day-two beats")

	# The homecoming line is keyed to targets met, and only to that.
	check(NarrativeEngine.count_targets_met(_stats(8, 6, 6, 6), QUEST.get_targets()) == 4,
		"hitting every target counts as 4")
	check(NarrativeEngine.count_targets_met(_stats(8, 0, 6, 0), QUEST.get_targets()) == 2,
		"hitting two targets counts as 2")
	var best := NarrativeEngine.build_log(QUEST, empty, _stats(8, 6, 6, 6))
	check(best[-1] != starving[-1], "a full pack and an empty one end differently")

	check(NarrativeEngine.collect_tags([_item("sword"), _item("shield")]).has("metal"),
		"collect_tags gathers tags across items")
	check(NarrativeEngine.collect_tags([_item("sword"), _item("shield")]).count("metal") == 1,
		"collect_tags deduplicates")
	check(NarrativeEngine.build_log(null, empty, {}).is_empty(), "no quest, no log")


# --- The wired scene ----------------------------------------------------------

func _test_flow() -> void:
	var main: Control = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame

	var brief: BriefPanel = main.get_node("%BriefPanel")
	var packing: PackingScene = main.get_node("%PackingScene")
	var playout: PlayoutScene = main.get_node("%PlayoutScene")

	check(GameState.current_quest == QUEST, "Main sets the quest before its children build")
	check(brief.title.text == QUEST.title, "the brief shows the quest title")
	check(brief.visible and not packing.visible and not playout.visible,
		"the brief is the first screen")

	brief.start_requested.emit()
	check(packing.visible and not brief.visible, "\"Start packing\" opens the packing screen")
	check(packing.item_tray.item_container.get_child_count() == QUEST.item_pool.size(),
		"the tray filled from the quest pool")

	# The tray is a child, so it populated before PackingScene._ready() could
	# connect to item_ready. Every item must still be draggable, and exactly once.
	var unwired := 0
	var doubled := 0
	for view in packing.item_tray.item_container.get_children():
		var count: int = view.grabbed.get_connections().size()
		if count == 0:
			unwired += 1
		elif count > 1:
			doubled += 1
	check(unwired == 0, "every tray item is wired for dragging, %d are not" % unwired)
	check(doubled == 0, "no tray item is wired twice, %d are" % doubled)

	# Pack a couple of things the way a player would, then send off.
	var bread := _pack(packing, "bread", Vector2i(0, 0))
	var sword := _pack(packing, "sword", Vector2i(5, 0))
	check(GameState.packed_items.size() == 2, "two items are packed")
	check(GameState.stats["food"] == bread.item.food, "stats followed the packing")

	packing.sent_off.emit()
	check(playout.visible and not packing.visible, "\"Send off\" opens the playout")
	check(playout.is_playing(), "the playout starts partway through, not all at once")
	check(playout.lines_box.get_child_count() == 1, "the first line lands immediately")
	var first: Label = playout.lines_box.get_child(0)
	check(first.text.contains(bread.item.display_name) and first.text.contains(sword.item.display_name),
		"the departure line names what was packed, got '%s'" % first.text)

	playout.skip()
	var expected := QUEST.narrative.size() + 2
	check(playout.lines_box.get_child_count() == expected,
		"skipping reveals every line, got %d of %d" % [playout.lines_box.get_child_count(), expected])
	check(not playout.is_playing(), "skipping ends the playout")
	check(playout.pack_again_button.visible, "\"Pack again\" appears when the log is done")

	playout.pack_again_requested.emit()
	check(packing.visible and not playout.visible, "\"Pack again\" returns to the packing screen")
	check(GameState.packed_items.is_empty(), "packing again empties the bag")
	check(GameState.stats["food"] == 0, "packing again zeroes the stats")
	check(packing.bag_grid.is_cell_free(Vector2i(0, 0)), "packing again frees the board")
	check(bread.get_parent() == packing.item_tray.item_container, "packed items went back to the tray")
	check(packing.item_tray.item_container.get_child_count() == QUEST.item_pool.size(),
		"the tray is whole again, got %d" % packing.item_tray.item_container.get_child_count())

	# And the loop actually loops.
	_pack(packing, "apple", Vector2i(0, 0))
	packing.sent_off.emit()
	check(playout.visible and playout.lines_box.get_child_count() == 1,
		"a second playout starts clean, got %d lines" % playout.lines_box.get_child_count())


# --- helpers ------------------------------------------------------------------

## Drives one item from the tray into the bag through the real drag path. It
## goes through the `grabbed` signal rather than calling the handler, because
## the wiring of that signal is exactly what once broke under Main.
func _pack(packing: PackingScene, id: String, origin: Vector2i) -> DraggableItem:
	var view := _find(packing.item_tray.item_container.get_children(), id)
	view.grabbed.emit(view, Vector2.ZERO)
	check(packing._dragging == view, "grabbing %s starts a drag" % id)
	packing._preview_origin = origin
	packing._preview_valid = packing.bag_grid.can_place(view.get_shape(), origin)
	check(packing._preview_valid, "%s fits at %s" % [id, origin])
	packing._end_drag(true)
	return view


func _log_for(items: Array[ItemData]) -> Array[String]:
	var stats := {}
	for key in GameState.STAT_KEYS:
		stats[key] = 0
	for item in items:
		for key in GameState.STAT_KEYS:
			stats[key] += int(item.get_stats().get(key, 0))
	return NarrativeEngine.build_log(QUEST, items, stats)


func _item(id: String) -> ItemData:
	return load("res://data/items/%s.tres" % id)


func _stats(food: int, health: int, attack: int, defense: int) -> Dictionary:
	return {"food": food, "health": health, "attack": attack, "defense": defense}


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
