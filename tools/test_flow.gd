extends Node

## Throwaway harness for the full loop: choose a quest -> packing -> send off ->
## playout -> choose again, plus NarrativeEngine and RunState's progression on
## their own. Run: godot --headless --path . res://tools/TestFlow.tscn

const MAIN := preload("res://scenes/Main.tscn")
const QUEST: QuestData = preload("res://data/quests/whisper_woods.tres")

var failures: int = 0


func _ready() -> void:
	_test_engine()
	_test_progression()
	# Progression tests mutate the shared RunState singleton; hand the flow test a
	# clean slate (difficulty 0, nothing cleared) so its draws are predictable.
	RunState.reset()
	await _test_flow()

	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


# --- RunState progression, with no scene tree involved -------------------------

func _test_progression() -> void:
	RunState.reset()
	check(RunState.current_difficulty() == 0, "a fresh run starts at difficulty 0")

	var first := RunState.draw_choices()
	check(first.size() == mini(RunState.CHOICE_COUNT, RunState.POOL.by_difficulty(0).size()),
		"the first draw offers up to three quests from tier 0, got %d" % first.size())
	for quest in first:
		check(quest.difficulty == 0, "every drawn quest is at the current tier")

	# A failed quest doesn't advance difficulty and stays drawable.
	RunState.register_result(first[0], false)
	check(RunState.current_difficulty() == 0, "a failed quest doesn't raise difficulty")
	check(RunState.completed_count == 0, "a failed quest isn't counted as cleared")

	# One clear = one tier up (until the cap).
	RunState.register_result(first[0], true)
	check(RunState.completed_count == 1, "a cleared quest is counted")
	check(RunState.current_difficulty() == 1, "one clear moves to difficulty 1")

	# Difficulty is capped, and clears past the cap keep counting.
	for i in 10:
		RunState.register_result(QUEST, true)
	check(RunState.current_difficulty() == RunState.MAX_DIFFICULTY,
		"difficulty caps at %d" % RunState.MAX_DIFFICULTY)

	# No-repeat within a tier: a cleared quest is held back until the tier is
	# exhausted, then the tier resets and offers everything again.
	RunState.reset()
	var tier0 := RunState.POOL.by_difficulty(0)
	if tier0.size() >= 2:
		# Clear one, but stay at tier 0 by only counting toward the draw filter,
		# not difficulty — draw at tier 0 directly to inspect the exclusion.
		RunState._cleared_ids.append(tier0[0].id)
		var narrowed := RunState.draw_choices()
		check(not _has_id(narrowed, tier0[0].id),
			"a cleared quest is held back while its tier still has others")
		# Clear the rest too: now the tier is exhausted and must reset.
		for quest in tier0:
			if not RunState._cleared_ids.has(quest.id):
				RunState._cleared_ids.append(quest.id)
		var reset_draw := RunState.draw_choices()
		check(not reset_draw.is_empty(), "an exhausted tier resets rather than going empty")
	RunState.reset()


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

	var select: QuestSelect = main.get_node("%QuestSelect")
	var packing: PackingScene = main.get_node("%PackingScene")
	var playout: PlayoutScene = main.get_node("%PlayoutScene")

	check(select.visible and not packing.visible and not playout.visible,
		"the quest picker is the first screen")
	check(select.card_row.get_child_count() == RunState.draw_choices().size(),
		"the picker laid out one card per drawn quest, got %d" % select.card_row.get_child_count())

	# Choose Whisper Woods specifically, so the rest of the flow runs against
	# known targets and a known pool. It is always one of the three tier-0 cards.
	select.quest_chosen.emit(QUEST)
	await get_tree().process_frame
	check(packing.visible and not select.visible, "choosing a quest opens the packing screen")
	check(GameState.current_quest == QUEST, "the chosen quest became the current one")
	check(packing.item_tray.item_container.get_child_count() == RunState.inventory.size(),
		"the tray filled from the player's inventory, got %d" % packing.item_tray.item_container.get_child_count())

	# The tray repopulated on the quest switch; every item must be draggable, and
	# exactly once (the item_ready wiring is what once broke under Main).
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

	# Pack a couple of things — not enough to clear all four targets — then send.
	var bread := _pack(packing, "bread", Vector2i(0, 0))
	var sword := _pack(packing, "sword", Vector2i(5, 0))
	check(GameState.packed_items.size() == 2, "two items are packed")
	check(GameState.stats["food"] == bread.item.food, "stats followed the packing")

	var before := RunState.completed_count
	var stock_before: int = RunState.inventory.size()
	packing.sent_off.emit()
	check(playout.visible and not packing.visible, "\"Send off\" opens the playout")
	# Persistent, depleting inventory: the two packed items are spent on send-off.
	check(RunState.inventory.size() == stock_before - 2,
		"sending off spent the two packed items, %d left of %d" % [RunState.inventory.size(), stock_before])
	check(not RunState.inventory.has(bread.item), "the packed bread left the inventory for good")
	check(not RunState.inventory.has(sword.item), "the packed sword left the inventory for good")
	check(GameState.count_targets_met() < GameState.STAT_KEYS.size(),
		"the light pack doesn't meet every target")
	check(RunState.completed_count == before, "an unmet quest doesn't count as cleared")
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
	check(playout.pack_again_button.visible, "the continue button appears when the log is done")

	# Finishing the log returns to the picker, not straight to packing.
	playout.pack_again_requested.emit()
	check(select.visible and not playout.visible, "finishing the log reopens the quest picker")
	check(select.card_row.get_child_count() > 0, "the picker offers a fresh set of quests")

	# Choosing again switches quests: the old bag is cleared and the tray rebuilt.
	select.quest_chosen.emit(QUEST)
	await get_tree().process_frame
	check(packing.visible, "choosing again returns to packing")
	check(GameState.packed_items.is_empty(), "the new quest starts with an empty bag")
	check(GameState.stats["food"] == 0, "the new quest zeroes the stats")
	check(packing.bag_grid.is_cell_free(Vector2i(0, 0)), "the new quest frees the board")
	check(not is_instance_valid(bread) or bread.get_parent() != packing.bag_grid.item_layer,
		"the previous quest's placed items don't linger in the bag")
	# The inventory is persistent: the new quest's tray is the depleted stash, not
	# a fresh pool, and the spent items do not reappear.
	check(packing.item_tray.item_container.get_child_count() == RunState.inventory.size(),
		"the tray rebuilt from the depleted inventory, got %d" % packing.item_tray.item_container.get_child_count())
	check(RunState.inventory.size() == stock_before - 2,
		"the inventory stayed depleted across the quest switch")
	check(_find(packing.item_tray.item_container.get_children(), "bread") == null,
		"a spent item does not come back in the new quest's tray (bread)")
	check(_find(packing.item_tray.item_container.get_children(), "sword") == null,
		"a spent item does not come back in the new quest's tray (sword)")

	# And the loop actually loops — and keeps depleting.
	var stock_second: int = RunState.inventory.size()
	_pack(packing, "apple", Vector2i(0, 0))
	packing.sent_off.emit()
	check(playout.visible and playout.lines_box.get_child_count() == 1,
		"a second playout starts clean, got %d lines" % playout.lines_box.get_child_count())
	check(RunState.inventory.size() == stock_second - 1, "the second send-off spent another item")


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


func _has_id(quests: Array, id: String) -> bool:
	for quest in quests:
		if quest != null and quest.id == id:
			return true
	return false


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
