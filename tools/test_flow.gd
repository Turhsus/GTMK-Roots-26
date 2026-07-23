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
	_test_durability()
	_test_perks()
	_test_day_clock()
	# The tests above mutate the shared RunState singleton; hand the flow test a
	# clean slate (difficulty 0, nothing cleared, a full pack) so its draws and
	# inventory are predictable.
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

	# A clear pays the quest's gold reward; a failure pays nothing.
	RunState.reset()
	check(RunState.gold == RunState.STARTING_GOLD, "a fresh run starts with the starting purse")
	var reward_quest := RunState.POOL.by_difficulty(0)[0]
	var gold0 := RunState.gold
	RunState.register_result(reward_quest, false)
	check(RunState.gold == gold0, "a failed quest pays no gold")
	RunState.register_result(reward_quest, true)
	check(RunState.gold == gold0 + reward_quest.gold_reward, "a cleared quest pays its reward")

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


# --- item durability, at the RunState level ------------------------------------

func _test_durability() -> void:
	RunState.reset()
	var apple := _owned("apple")
	var blanket := _owned("blanket")
	check(apple != null and blanket != null, "the fresh inventory holds an apple and a blanket")
	check(apple.max_durability == 1, "a plain item lasts one trip")
	check(blanket.max_durability == 3, "the blanket lasts three trips")
	check(apple.durability == apple.max_durability and blanket.durability == blanket.max_durability,
		"a fresh owned copy starts at full durability")

	# A single-use item is worn out and gone after one send-off.
	RunState.apply_wear([apple])
	check(not RunState.inventory.has(apple), "a 1-durability item is worn out in one quest")

	# A sturdy item survives, losing one trip each send-off, until it too runs out.
	RunState.apply_wear([blanket])
	check(RunState.inventory.has(blanket) and blanket.durability == 2, "the blanket has 2 trips left after one")
	RunState.apply_wear([blanket])
	check(RunState.inventory.has(blanket) and blanket.durability == 1, "and 1 trip left after two")
	RunState.apply_wear([blanket])
	check(not RunState.inventory.has(blanket), "the blanket is worn out after three trips")

	# Wear is per-copy: a freshly bought blanket doesn't inherit a worn one's damage,
	# and the shared template is never mutated.
	RunState.reset()
	RunState.apply_wear([_owned("blanket")])  # the starter blanket drops to 2
	RunState.gain(load("res://data/items/blanket.tres"))  # a bought one enters at 3
	var durs: Array[int] = []
	for item in RunState.inventory:
		if item.id == "blanket":
			durs.append(item.durability)
	durs.sort()
	check(durs.size() == 2 and durs[0] == 2 and durs[1] == 3,
		"each blanket copy wears independently, got %s" % [durs])
	check((load("res://data/items/blanket.tres") as ItemData).durability == -1,
		"the shared item template is never worn")
	RunState.reset()


# --- the global day clock, at the RunState level -------------------------------

func _test_day_clock() -> void:
	RunState.reset()
	check(RunState.days_remaining == RunState.TOTAL_DAYS,
		"a fresh run starts with the full day clock, got %d" % RunState.days_remaining)
	check(not RunState.days_are_up(), "a fresh run's clock hasn't run out")

	# Each day spent ticks the clock down by one and reports it.
	var seen: Array[int] = []
	var sub := func(days: int) -> void: seen.append(days)
	RunState.days_changed.connect(sub)
	RunState.spend_day()
	check(RunState.days_remaining == RunState.TOTAL_DAYS - 1, "spending a day drops the clock by one")
	check(seen.size() == 1 and seen[0] == RunState.days_remaining, "spending a day reports the new count")
	RunState.days_changed.disconnect(sub)

	# The clock runs out at zero (and stays "up" if it somehow overshoots).
	while RunState.days_remaining > 0:
		RunState.spend_day()
	check(RunState.days_are_up(), "the clock is up once it reaches zero")
	RunState.spend_day()
	check(RunState.days_are_up(), "the clock stays up past zero")

	# A fresh run winds it back to full.
	RunState.reset()
	check(RunState.days_remaining == RunState.TOTAL_DAYS and not RunState.days_are_up(),
		"reset restores the full day clock")


# --- adventuring perks, at the RunState level ----------------------------------

func _test_perks() -> void:
	RunState.reset()
	var forage: PerkData = load("res://data/perks/forage.tres")
	var crafty: PerkData = load("res://data/perks/crafty.tres")
	check(RunState.owned_perks.is_empty(), "a fresh run owns no perks")
	check(RunState.food_bonus() == 0, "no perks means no food bonus")
	check(RunState.combat_wear_skip_chance() == 0.0, "no perks means no wear skip")

	# Offering is contextual: a missed target surfaces the perk that addresses it.
	var on_food := RunState.offer_perks(["food"])
	check(_has_id(on_food, "forage") and not _has_id(on_food, "crafty"),
		"a food shortfall offers the forage perk, not the crafty one")
	var on_combat := RunState.offer_perks(["combat"])
	check(_has_id(on_combat, "crafty") and not _has_id(on_combat, "forage"),
		"a combat shortfall offers the crafty perk, not the forage one")
	check(RunState.offer_perks(["health"]).is_empty(),
		"a shortfall with no matching perk offers nothing")
	check(RunState.offer_perks(["food", "combat"]).size() == 2,
		"failing both surfaces both perks")

	# Earning the forage perk: its food folds into the current packing, and it's no
	# longer offered (perks are unique).
	RunState.add_perk(forage)
	check(RunState.has_perk("forage") and RunState.food_bonus() == 1,
		"the forage perk is owned and adds +1 food")
	GameState.set_quest(QUEST)
	check(GameState.stats["food"] == 1, "the food bonus shows on an empty bag, got %d" % GameState.stats["food"])
	check(not _has_id(RunState.offer_perks(["food"]), "forage"),
		"an owned perk is not offered again")
	RunState.add_perk(forage)
	check(RunState.owned_perks.size() == 1, "a perk can't be earned twice")

	# Earning crafty gives the combat wear skip its chance.
	RunState.add_perk(crafty)
	check(abs(RunState.combat_wear_skip_chance() - 0.1) < 0.0001,
		"the crafty perk gives a 10%% chance to skip combat wear")

	# A fresh run drops every earned perk.
	RunState.reset()
	check(RunState.owned_perks.is_empty() and RunState.food_bonus() == 0,
		"reset clears earned perks")
	GameState.set_quest(QUEST)
	check(GameState.stats["food"] == 0, "with perks cleared the food bonus is gone")


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
	check(NarrativeEngine.count_targets_met(_stats(8, 6, 12, 0), QUEST.get_targets()) == 4,
		"hitting every target counts as 4")
	check(NarrativeEngine.count_targets_met(_stats(8, 0, 0, 0), QUEST.get_targets()) == 2,
		"hitting two targets counts as 2")
	var best := NarrativeEngine.build_log(QUEST, empty, _stats(8, 6, 12, 0))
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
	var town: TownScreen = main.get_node("%TownScreen")
	var tutorial := RunState.TUTORIAL

	# The forced tutorial is packed first — no picker, no gather before it.
	check(packing.visible and not select.visible and not playout.visible and not town.visible,
		"the tutorial quest is packed first, with no picker")
	check(GameState.current_quest == tutorial, "the first quest is the fixed tutorial")
	check(packing.item_tray.item_container.get_child_count() == RunState.inventory.size(),
		"the tray filled from the player's inventory, got %d" % packing.item_tray.item_container.get_child_count())

	# The tray populated under Main; every item must be draggable, and exactly once
	# (the item_ready wiring is what once broke under Main).
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

	# Pack food only — meets the tutorial's food target but not its health one, so
	# it isn't cleared. bread + apple are spent and must not reappear later.
	var bread := _pack(packing, "bread", Vector2i(0, 0))
	var apple := _pack(packing, "apple", Vector2i(3, 0))
	check(GameState.packed_items.size() == 2, "two items are packed")
	check(GameState.stats["food"] == bread.item.food + apple.item.food, "stats followed the packing")

	var before := RunState.completed_count
	var gold_before: int = RunState.gold
	var stock_before: int = RunState.inventory.size()
	packing.sent_off.emit()
	check(playout.visible and not packing.visible, "\"Send off\" opens the playout")
	# Persistent, depleting inventory: the two packed items are spent on send-off.
	check(RunState.inventory.size() == stock_before - 2,
		"sending off spent the two packed items, %d left of %d" % [RunState.inventory.size(), stock_before])
	check(not RunState.inventory.has(bread.item), "the packed bread left the inventory for good")
	check(GameState.count_targets_met() < GameState.STAT_KEYS.size(),
		"the food-only pack doesn't meet every target")
	check(RunState.completed_count == before, "an unmet quest doesn't count as cleared")
	check(RunState.gold == gold_before, "an unmet quest pays no reward")
	check(playout.is_playing(), "the playout starts partway through, not all at once")
	check(playout.lines_box.get_child_count() == 1, "the first line lands immediately")
	var first: Label = playout.lines_box.get_child(0)
	check(first.text.contains(bread.item.display_name) and first.text.contains(apple.item.display_name),
		"the departure line names what was packed, got '%s'" % first.text)

	playout.skip()
	var expected := tutorial.narrative.size() + 2
	check(playout.lines_box.get_child_count() == expected,
		"skipping reveals every line, got %d of %d" % [playout.lines_box.get_child_count(), expected])
	check(not playout.is_playing(), "skipping ends the playout")
	check(playout.pack_again_button.visible, "the continue button appears when the log is done")

	# Finishing the log now opens the gather phase (town), not the picker.
	playout.pack_again_requested.emit()
	check(town.visible and not playout.visible, "finishing the log opens the gather phase")
	check(town._total_days == tutorial.days, "the gather budget is the finished quest's length")
	check(town._current_day == 1, "the gather phase starts on day one")

	# Buying spends gold and adds a copy; selling gives half back and removes it.
	var grocer: ShopData = load("res://data/shops/grocer.tres")
	var apple_item: ItemData = load("res://data/items/apple.tres")
	var pre_buy_gold: int = RunState.gold
	var pre_buy_stock: int = RunState.inventory.size()
	town._enter_shop(grocer)
	town._on_buy(apple_item)
	check(RunState.gold == pre_buy_gold - apple_item.buy_price, "buying spends the item's price")
	check(RunState.inventory.size() == pre_buy_stock + 1, "buying adds a copy to the inventory")
	check(_owned(apple_item.id) != null, "the bought item is owned")
	town._on_sell(apple_item)
	check(RunState.gold == pre_buy_gold - apple_item.buy_price + apple_item.sell_price(),
		"selling returns half the buy price")
	check(RunState.inventory.size() == pre_buy_stock, "selling removes the copy again")

	# An unaffordable spend is refused and leaves the purse untouched.
	var settled_gold: int = RunState.gold
	check(not RunState.spend_gold(RunState.gold + 1) and RunState.gold == settled_gold,
		"a spend beyond the purse is refused")

	# No early exit: every day must be spent before the picker opens.
	var guard := 0
	while town.visible and guard < town._total_days + 2:
		town._end_day()
		guard += 1
	check(select.visible and not town.visible, "spending every gather day opens the quest picker")
	check(select.card_row.get_child_count() > 0, "the picker offers a fresh set of quests")

	# Round two: choose a real quest from the pool. It switches quests — old bag
	# cleared, tray rebuilt from the depleted stash — and the tutorial's spent
	# bread + apple must not reappear.
	select.quest_chosen.emit(QUEST)
	await get_tree().process_frame
	check(packing.visible and not select.visible, "choosing a quest opens the packing screen")
	check(GameState.current_quest == QUEST, "the chosen quest became the current one")
	check(GameState.packed_items.is_empty(), "the new quest starts with an empty bag")
	check(GameState.stats["food"] == 0, "the new quest zeroes the stats")
	check(packing.bag_grid.is_cell_free(Vector2i(0, 0)), "the new quest frees the board")
	check(not is_instance_valid(bread) or bread.get_parent() != packing.bag_grid.item_layer,
		"the previous quest's placed items don't linger in the bag")
	check(packing.item_tray.item_container.get_child_count() == RunState.inventory.size(),
		"the tray rebuilt from the depleted inventory, got %d" % packing.item_tray.item_container.get_child_count())
	check(_find(packing.item_tray.item_container.get_children(), "bread") == null,
		"a spent item does not come back in the new quest's tray (bread)")
	check(_find(packing.item_tray.item_container.get_children(), "apple") == null,
		"a spent item does not come back in the new quest's tray (apple)")

	# And the loop actually loops — and keeps depleting.
	var stock_second: int = RunState.inventory.size()
	_pack(packing, "sword", Vector2i(0, 0))
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


## The first owned inventory copy with this id, or null. Owned copies are distinct
## instances now, so lookups go by id rather than matching a shared resource.
func _owned(id: String) -> ItemData:
	for item in RunState.inventory:
		if item.id == id:
			return item
	return null


func _stats(food: int, health: int, combat: int, utility: int) -> Dictionary:
	return {"food": food, "health": health, "combat": combat, "utility": utility}


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
