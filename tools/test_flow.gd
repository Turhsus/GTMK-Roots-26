extends Node

## Throwaway harness for the full loop: choose a quest -> packing -> send off ->
## playout -> choose again, plus NarrativeEngine and RunState's progression on
## their own. Run: godot --headless --path . res://tools/TestFlow.tscn

const MAIN := preload("res://scenes/Main.tscn")
## The quest this harness drives the loop with. It has to be one the pool holds,
## because _test_flow hands it to the picker. (This used to point at a deleted
## whisper_woods.tres, which meant the whole harness failed to load.)
const QUEST: QuestData = preload("res://data/quests/rescue.tres")

var failures: int = 0


func _ready() -> void:
	# This harness runs the real Main scene, which autosaves at every phase
	# boundary. Left on, a test run would overwrite the player's actual save.
	SaveManager.autosave_enabled = false
	# Both send-off debug switches have to be off here. "skip_playout" would route
	# past the playout this harness asserts on, and "durability_report" pops a modal
	# that waits for a dismissal no headless run will ever give it.
	DebugFlags.set_flag("skip_playout", false)
	DebugFlags.set_flag("durability_report", false)
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

	# The draw pulls from the current tier, or the nearest non-empty one when that
	# tier is bare (see RunState._nearest_tier). The pool has no tier-0 quests today,
	# so a fresh run legitimately draws from tier 1 — asserting "tier 0" here would
	# be testing the content, not the code.
	var first := RunState.draw_choices()
	var drawn_tier := RunState.POOL.by_difficulty(0)
	if drawn_tier.is_empty():
		drawn_tier = RunState._nearest_tier(0)
	check(first.size() == mini(RunState.CHOICE_COUNT, drawn_tier.size()),
		"the first draw offers up to three quests, got %d of %d available" % [first.size(), drawn_tier.size()])
	check(not first.is_empty(), "a fresh run has something to draw (the pool is not empty)")
	if first.is_empty():
		return
	var first_tier: int = first[0].difficulty
	for quest in first:
		check(quest.difficulty == first_tier, "every drawn quest sits at one tier")

	# A failed quest doesn't advance difficulty and stays drawable.
	RunState.register_result(first[0], false)
	check(RunState.current_difficulty() == 0, "a failed quest doesn't raise difficulty")
	check(RunState.completed_count == 0, "a failed quest isn't counted as cleared")
	check(RunState.attempted_count == 1, "a failed quest still counts as attempted")

	# One clear = one tier up (until the cap).
	RunState.register_result(first[0], true)
	check(RunState.completed_count == 1, "a cleared quest is counted")
	check(RunState.attempted_count == 2, "a cleared quest also counts as attempted")
	check(RunState.current_difficulty() == 1, "one clear moves to difficulty 1")

	# Difficulty is capped, and clears past the cap keep counting.
	for i in 10:
		RunState.register_result(QUEST, true)
	check(RunState.current_difficulty() == RunState.MAX_DIFFICULTY,
		"difficulty caps at %d" % RunState.MAX_DIFFICULTY)

	# A clear pays the quest's gold reward; a failure pays nothing.
	RunState.reset()
	check(RunState.gold == RunState.STARTING_GOLD, "a fresh run starts with the starting purse")
	# Whatever a fresh run would actually be offered, rather than assuming tier 0
	# has anything in it.
	var reward_quest: QuestData = RunState.draw_choices()[0]
	var gold0 := RunState.gold
	RunState.register_result(reward_quest, false)
	check(RunState.gold == gold0, "a failed quest pays no gold")
	RunState.register_result(reward_quest, true)
	check(RunState.gold == gold0 + reward_quest.gold_reward, "a cleared quest pays its reward")

	# Backpack upgrades: spend gold to grow, refuse when broke or maxed. Sizes come
	# from BAG_SIZES rather than being written out, so retuning the ladder (it went
	# from [4,5,6] to [3,4,5,6]) doesn't silently invalidate this. The leatherworker's
	# own gates — one per day, one per quest — are exercised in test_shop.
	RunState.reset()
	var sizes := RunState.BAG_SIZES
	check(RunState.bag_tier == 0 and RunState.bag_cols() == sizes[0],
		"a fresh run starts at bag tier 0 (%dx%d)" % [sizes[0], sizes[0]])
	check(RunState.can_upgrade_bag(), "a fresh run can upgrade the backpack")
	check(RunState.bag_upgrade_available(), "and the leatherworker has one on the bench")
	var cost1 := RunState.bag_upgrade_cost()
	check(cost1 == RunState.BAG_UPGRADE_COSTS[0], "first upgrade costs the authored amount")
	var gold_before := RunState.gold
	check(RunState.upgrade_bag(), "first upgrade succeeds when the purse can cover it")
	check(RunState.bag_tier == 1 and RunState.bag_cols() == sizes[1],
		"first upgrade reaches %dx%d" % [sizes[1], sizes[1]])
	check(RunState.gold == gold_before - cost1, "upgrade spends its cost")

	# Climb to the top of the ladder — with the purse topped up, so this tests the
	# tier cap and not affordability (that gets its own check below). Each rung needs
	# a fresh day *and* a finished quest, which is what the two calls in the loop are.
	RunState.add_gold(1000)
	var guard_upgrades := 0
	while RunState.can_upgrade_bag() and guard_upgrades < sizes.size() + 1:
		RunState.spend_day()
		RunState.restock_bag_upgrade()
		check(RunState.upgrade_bag(), "an affordable upgrade below the cap succeeds")
		guard_upgrades += 1
	check(RunState.bag_tier == sizes.size() - 1 and RunState.bag_cols() == sizes[-1],
		"upgrading to the cap reaches %dx%d" % [sizes[-1], sizes[-1]])
	RunState.spend_day()
	RunState.restock_bag_upgrade()
	check(not RunState.can_upgrade_bag() and not RunState.upgrade_bag(),
		"a maxed bag refuses further upgrades")
	RunState.reset()
	RunState.gold = 0
	RunState.gold_changed.emit(0)
	check(not RunState.upgrade_bag() and RunState.bag_tier == 0,
		"an upgrade is refused when the purse is empty")

	# No-repeat within a tier: a cleared quest is held back until the tier is
	# exhausted, then the tier resets and offers everything again.
	RunState.reset()
	# Whichever tier a fresh run actually draws from — tier 0 if the pool has one,
	# otherwise the nearest that isn't empty.
	var tier := RunState.POOL.by_difficulty(0)
	if tier.is_empty():
		tier = RunState._nearest_tier(0)
	if tier.size() >= 2:
		# Clear one, but stay at this tier by only counting toward the draw filter,
		# not difficulty — draw directly to inspect the exclusion.
		RunState._cleared_ids.append(tier[0].id)
		var narrowed := RunState.draw_choices()
		check(not _has_id(narrowed, tier[0].id),
			"a cleared quest is held back while its tier still has others")
		# Clear the rest too: now the tier is exhausted and must reset.
		for quest in tier:
			if not RunState._cleared_ids.has(quest.id):
				RunState._cleared_ids.append(quest.id)
		var reset_draw := RunState.draw_choices()
		check(not reset_draw.is_empty(), "an exhausted tier resets rather than going empty")
	else:
		print("  SKIP  no-repeat needs 2+ quests in the drawn tier, pool has %d" % tier.size())
	RunState.reset()


# --- item durability, at the RunState level ------------------------------------

func _test_durability() -> void:
	RunState.reset()
	# The apple is the single-use case; the rope is the sturdy one (3 trips). Both
	# are in STARTER_INVENTORY — the blanket this used to test with no longer is.
	var apple := _owned(_id("apple"))
	var rope := _owned(_id("rope"))
	check(apple != null and rope != null, "the fresh inventory holds an apple and a rope")
	check(apple.max_durability == 1, "a plain item lasts one trip")
	check(rope.max_durability == 3, "the rope lasts three trips")
	check(apple.durability == apple.max_durability and rope.durability == rope.max_durability,
		"a fresh owned copy starts at full durability")

	# A single-use item is worn out and gone after one send-off.
	RunState.apply_wear_to_inventory([apple])
	RunState.discard_worn_out([apple])
	check(not RunState.inventory.has(apple), "a 1-durability item is worn out in one quest")

	# A sturdy item survives, losing one trip each send-off, until it too runs out.
	RunState.apply_wear_to_inventory([rope])
	RunState.discard_worn_out([rope])
	check(RunState.inventory.has(rope) and rope.durability == 2, "the rope has 2 trips left after one")
	RunState.apply_wear_to_inventory([rope])
	RunState.discard_worn_out([rope])
	check(RunState.inventory.has(rope) and rope.durability == 1, "and 1 trip left after two")
	RunState.apply_wear_to_inventory([rope])
	RunState.discard_worn_out([rope])
	check(not RunState.inventory.has(rope), "the rope is worn out after three trips")

	# Wear is per-copy: a freshly bought rope doesn't inherit a worn one's damage,
	# and the shared template is never mutated.
	RunState.reset()
	RunState.apply_wear_to_inventory([_owned(_id("rope"))])  # the starter rope drops to 2
	RunState.gain(load("res://data/items/rope.tres"))  # a bought one enters at 3
	var durs: Array[int] = []
	for item in RunState.inventory:
		if item.id == _id("rope"):
			durs.append(item.durability)
	durs.sort()
	check(durs.size() == 2 and durs[0] == 2 and durs[1] == 3,
		"each rope copy wears independently, got %s" % [durs])
	check((load("res://data/items/rope.tres") as ItemData).durability == -1,
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
	# Perks are built instances of their subclasses now (no .tres), one of each in
	# RunState.all_perks; grab them by id to drive the checks below.
	var forage: PerkData = RunState.find_perk("forage")
	var crafty: PerkData = RunState.find_perk("crafty")
	check(forage != null and crafty != null, "the forage and crafty perks are built")
	check(RunState.owned_perks.is_empty(), "a fresh run owns no perks")

	# The perks are their own subclasses now, each owning its behaviour through the
	# PerkData hooks rather than a typed field a central system reads.
	check(forage.modify_stats({"food": 0})["food"] == 1,
		"the forage perk's modify_stats hook adds +1 food")
	var apple: ItemData = preload("res://data/items/apple.tres")  # food item, no combat
	var apple_copy := apple.make_owned_copy()
	var apple_before := apple_copy.durability
	crafty.modify_item(apple_copy)
	check(apple_copy.durability == apple_before, "crafty never touches a non-combat item")

	# Offering is contextual: a missed target surfaces the perk that addresses it.
	var on_food := RunState.offer_perks(["food"])
	check(_has_id(on_food, "forage") and not _has_id(on_food, "crafty"),
		"a food shortfall offers the forage perk, not the crafty one")
	var on_combat := RunState.offer_perks(["combat"])
	check(_has_id(on_combat, "crafty") and not _has_id(on_combat, "forage"),
		"a combat shortfall offers the crafty perk, not the forage one")
	# Self-sufficiency has no trigger_stat, so it rides along with every shortfall —
	# a bad pack costs durability rather than any one stat.
	var on_health := RunState.offer_perks(["health"])
	check(on_health.size() == 1 and _has_id(on_health, "self_sufficiency"),
		"a shortfall no perk targets still offers the always-eligible one")
	check(RunState.offer_perks(["food", "combat"]).size() == 3,
		"failing both surfaces both targeted perks plus the always-eligible one")

	# Earning the forage perk: its food folds into the current packing, and it's no
	# longer offered (perks are unique).
	RunState.add_perk(forage)
	check(RunState.has_perk("forage"), "the forage perk is owned")
	GameState.set_quest(QUEST)
	check(GameState.stats["food"] == 1, "the food bonus shows on an empty bag, got %d" % GameState.stats["food"])
	check(not _has_id(RunState.offer_perks(["food"]), "forage"),
		"an owned perk is not offered again")
	RunState.add_perk(forage)
	check(RunState.owned_perks.size() == 1, "a perk can't be earned twice")

	# Earning crafty repairs a combat item's trip wear now and then. The roll is random,
	# so check the rate over many trials: modify_item (run after the item's default wear)
	# should undo that point of wear on ~10% of combat items.
	RunState.add_perk(crafty)
	var sword: ItemData = preload("res://data/items/sword.tres")  # a combat item
	var repaired := 0
	var trials := 20000
	for _i in trials:
		var copy := sword.make_owned_copy()
		copy.durability -= 1  # the trip's wear, as apply_wear_to_inventory applies it
		crafty.modify_item(copy)
		if copy.durability == sword.max_durability:  # the wear was undone
			repaired += 1
	var rate := float(repaired) / float(trials)
	check(abs(rate - 0.1) < 0.02,
		"crafty repairs a combat item's wear ~10%% of the time, got %.3f" % rate)

	# Self-sufficiency forgives a *packing mistake*: the item's effect docks it at
	# send-off, then the perk hands that durability back ~10% of the time and returns
	# the line the activation modal shows. Built from a bare item and a two-cell board
	# so this doesn't ride on which authored item happens to carry which effect.
	var self_suff: PerkData = RunState.find_perk("self_sufficiency")
	check(self_suff != null, "the self-sufficiency perk is built")
	var crush := ClearAboveEffect.new()
	crush.penalty = 2
	crush.rows = 1
	var forgiven := 0
	var lines := 0
	for _i in trials:
		var fragile := ItemData.new()
		fragile.id = "egg"
		fragile.display_name = "Egg"
		fragile.effects = [crush] as Array[ItemEffect]
		fragile.durability = 5
		var board := PackLayout.new()
		board.add(fragile, Vector2i(1, 3), 0, [Vector2i(1, 3)] as Array[Vector2i])
		board.add(ItemData.new(), Vector2i(1, 2), 0, [Vector2i(1, 2)] as Array[Vector2i])
		crush.resolve_send_off(fragile, board)  # the mistake lands first, as send-off runs it
		if self_suff.modify_item(fragile, board) != "":
			lines += 1
		if fragile.durability == 5:  # the dock was handed back
			forgiven += 1
	var forgive_rate := float(forgiven) / float(trials)
	check(abs(forgive_rate - 0.1) < 0.02,
		"self-sufficiency forgives a mistake ~10%% of the time, got %.3f" % forgive_rate)
	check(lines == forgiven, "every forgiven mistake reports an activation line, and only those")

	# A clean pack has no mistake to forgive, and neither does a call with no board —
	# the perk must stay silent rather than refunding wear it didn't cause.
	var tidy := PackLayout.new()
	var lone := ItemData.new()
	lone.effects = [crush] as Array[ItemEffect]
	lone.durability = 5
	tidy.add(lone, Vector2i(1, 3), 0, [Vector2i(1, 3)] as Array[Vector2i])
	var quiet := true
	for _i in 200:
		if self_suff.modify_item(lone, tidy) != "" or self_suff.modify_item(lone, null) != "":
			quiet = false
	check(quiet and lone.durability == 5,
		"with nothing packed above it there is no mistake to forgive")

	# A fresh run drops every earned perk.
	RunState.reset()
	check(RunState.owned_perks.is_empty(), "reset clears earned perks")
	GameState.set_quest(QUEST)
	check(GameState.stats["food"] == 0, "with perks cleared the food bonus is gone")


# --- NarrativeEngine, with no scene tree involved at all -----------------------

func _test_engine() -> void:
	var quest := _make_narrative_test_quest()
	var empty: Array[ItemData] = []
	var packed: Array[ItemData] = [_item("sword"), _item("bread")]
	var empty_lines := NarrativeEngine.build_log(quest, empty, _stats(0, 0, 0, 0))
	var packed_lines := NarrativeEngine.build_log(quest, packed, quest.get_targets())

	# Departure + every beat + homecoming + the closing verdict line: with a
	# fallback variant on each beat, and the verdict always appended, nothing
	# may be silently dropped.
	check(empty_lines.size() == quest.narrative.size() + 3,
		"an empty bag still gets every beat plus the verdict, got %d lines" % empty_lines.size())
	for line in empty_lines:
		check(not line.strip_edges().is_empty(), "no line is blank")

	# Departure and homecoming are authored per quest now (see QuestData.departure /
	# .homecoming) and resolved the same conditional-variant way as the beats —
	# there's no generic "read the bag back" or "N of 4 targets" text left in the
	# engine itself. The verdict line (see NarrativeEngine._build_summary_line) is
	# the one place that still reads targets vs. stats directly.
	check(empty_lines[0].contains("empty"), "the empty bag matches the departure's fallback variant")
	check(packed_lines[0].contains("heavy"), "a heavy-tagged pack matches the departure's tagged variant")
	check(packed_lines[-2] != empty_lines[-2], "meeting the quest's targets changes the homecoming line")
	check(packed_lines[-1] != empty_lines[-1], "meeting the quest's targets changes the verdict line")
	check(packed_lines[-1].begins_with("Quest Succeeded"), "packed_lines meets every target, so the verdict succeeds")
	check(empty_lines[-1].begins_with("Quest Failed"), "an empty bag misses every target, so the verdict fails")

	# "heavy" is the trait the sword and the shield share, so it exercises both the
	# gathering and the dedup in one pair.
	check(NarrativeEngine.collect_tags([_item("sword"), _item("shield")]).has("heavy"),
		"collect_tags gathers tags across items")
	check(NarrativeEngine.collect_tags([_item("sword"), _item("shield")]).count("heavy") == 1,
		"collect_tags deduplicates")
	check(NarrativeEngine.build_log(null, empty, {}).is_empty(), "no quest, no log")

	_test_authored_beats(quest)


## The conditional-variant machinery: tag matching, forbid rules, and authoring
## order as priority. Run against a quest built in code (see
## _make_narrative_test_quest) rather than any authored .tres, so this stays
## meaningful no matter what the real quests currently have authored.
func _test_authored_beats(quest: QuestData) -> void:
	# A beat must never resolve to nothing: that drops the line silently, so every
	# beat needs an unconditional variant authored last.
	var no_stats := _stats(0, 0, 0, 0)
	var no_tags: Array[String] = []
	for event in quest.narrative:
		check(not event.resolve(no_stats, no_tags).strip_edges().is_empty(),
			"beat '%s' still resolves with nothing packed (needs a fallback variant last)" % event.beat_id)

	# Two packings that differ only in tags must be able to read differently, or the
	# conditions aren't doing anything.
	var bare := NarrativeEngine.build_log(quest, [], no_stats)
	var loaded := NarrativeEngine.build_log(quest, [], quest.get_targets())
	check(bare != loaded, "meeting the targets changes at least one beat")


## A throwaway quest with departure/narrative/homecoming authored right here,
## so the engine's conditional resolution can be tested without depending on
## whichever real quest happens to have content authored.
func _make_narrative_test_quest() -> QuestData:
	var quest := QuestData.new()
	quest.id = "test_narrative_quest"
	quest.target_food = 2
	quest.target_health = 0
	quest.target_combat = 0
	quest.target_utility = 0

	var departure_tagged := NarrativeLine.new()
	departure_tagged.require_tags = ["heavy"]
	departure_tagged.text = "They heave something heavy onto their back and go."
	var departure_fallback := NarrativeLine.new()
	departure_fallback.text = "They shoulder the empty bag and go."
	var departure := NarrativeEvent.new()
	departure.beat_id = "test_departure"
	departure.variants = [departure_tagged, departure_fallback]
	quest.departure = departure

	var beat_pass := NarrativeLine.new()
	beat_pass.require_stat = {"food": 2}
	beat_pass.text = "The road was easy with a full belly."
	var beat_fallback := NarrativeLine.new()
	beat_fallback.text = "The road was hard on an empty stomach."
	var beat := NarrativeEvent.new()
	beat.beat_id = "test_beat"
	beat.variants = [beat_pass, beat_fallback]
	quest.narrative = [beat]

	var home_pass := NarrativeLine.new()
	home_pass.require_stat = {"food": 2}
	home_pass.text = "They came home well fed."
	var home_fallback := NarrativeLine.new()
	home_fallback.text = "They came home hungry."
	var homecoming := NarrativeEvent.new()
	homecoming.beat_id = "test_homecoming"
	homecoming.variants = [home_pass, home_fallback]
	quest.homecoming = homecoming

	return quest


# --- The wired scene ----------------------------------------------------------

func _test_flow() -> void:
	var main: Control = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame

	var select: QuestSelect = main.get_node("%QuestSelect")
	var packing: PackingScene = main.get_node("%PackingScene")
	var playout: PlayoutScene = main.get_node("%PlayoutScene")
	var town: RoadScene = main.get_node("%RoadScene")
	var lesson: PerkSelect = main.get_node("%PerkSelect")
	var tutorial := RunState.TUTORIAL

	# The forced tutorial is packed first — no picker, no gather before it.
	check(packing.visible and not select.visible and not playout.visible and not town.visible,
		"the tutorial quest is packed first, with no picker")
	check(GameState.current_quest == tutorial, "the first quest is the fixed tutorial")
	check(packing.item_tray.item_views().size() == RunState.inventory.size(),
		"the tray filled from the player's inventory, got %d" % packing.item_tray.item_views().size())

	# The tray populated under Main; every item must be draggable, and exactly once
	# (the item_ready wiring is what once broke under Main).
	var unwired := 0
	var doubled := 0
	for view in packing.item_tray.item_views():
		var count: int = view.grabbed.get_connections().size()
		if count == 0:
			unwired += 1
		elif count > 1:
			doubled += 1
	check(unwired == 0, "every tray item is wired for dragging, %d are not" % unwired)
	check(doubled == 0, "no tray item is wired twice, %d are" % doubled)

	# Pack food only — meets the tutorial's food target but not its utility one, so
	# it isn't cleared. Both are spent and must not reappear later. (This packed a
	# bread until the starter inventory dropped it; the cheese wedge is the food
	# item that's actually in the tray.)
	var cheese := _pack(packing, _id("cheese_wedge"), Vector2i(0, 0))
	# Top-right of whatever the starting bag is, so a retuned BAG_SIZES doesn't put
	# this off the board.
	var apple := _pack(packing, _id("apple"), Vector2i(RunState.bag_cols() - 1, 0))
	check(GameState.packed_items.size() == 2, "two items are packed")
	check(GameState.stats["food"] == cheese.item.food + apple.item.food, "stats followed the packing")

	var before := RunState.completed_count
	var gold_before: int = RunState.gold
	var stock_before: int = RunState.inventory.size()
	packing.sent_off.emit()
	check(playout.visible and not packing.visible, "\"Send off\" opens the playout")
	# Persistent, depleting inventory: the two packed items are spent on send-off.
	# The quest also takes back whatever it lent for the trip — the tutorial loans a
	# package that wasn't packed, so it leaves the tray too and has to be counted.
	var expected_stock := stock_before - 2 - tutorial.quest_items.size()
	check(RunState.inventory.size() == expected_stock,
		"send-off spent the two packed items and reclaimed %d loan(s), %d left of %d" % [
			tutorial.quest_items.size(), RunState.inventory.size(), stock_before])
	check(not RunState.inventory.has(cheese.item), "the packed cheese left the inventory for good")
	check(GameState.count_targets_met() < GameState.STAT_KEYS.size(),
		"the food-only pack doesn't meet every target")
	check(RunState.completed_count == before, "an unmet quest doesn't count as cleared")
	check(RunState.gold == gold_before, "an unmet quest pays no reward")
	check(playout.is_playing(), "the playout starts partway through, not all at once")
	check(playout.lines_box.get_child_count() == 1, "the first line lands immediately")
	var first: Label = playout.lines_box.get_child(0)
	# The tutorial has no `departure` authored yet, so the log opens on its first
	# beat instead — the cheese + apple pack clears the food target (2 < 2+1).
	check(first.text.contains("well fed"),
		"the first line is the tutorial's food beat (no departure authored), got '%s'" % first.text)

	playout.skip()
	# No departure/homecoming authored on the tutorial yet, so the log is exactly
	# its beats — see NarrativeEngine.build_log / QuestData.departure/homecoming.
	var expected := tutorial.narrative.size()
	check(playout.lines_box.get_child_count() == expected,
		"skipping reveals every authored beat, got %d of %d" % [playout.lines_box.get_child_count(), expected])
	check(not playout.is_playing(), "skipping ends the playout")
	check(playout.pack_again_button.visible, "the continue button appears when the log is done")

	# The tutorial wasn't cleared, so finishing the log offers a lesson before town.
	# Self-sufficiency has no trigger_stat, so *any* failure now surfaces at least one
	# perk — the lesson screen is no longer skippable on a shortfall no perk targets.
	playout.pack_again_requested.emit()
	check(lesson.visible and not playout.visible, "a failed quest offers a lesson before town")
	# The very offers the loop just made: main captured the shortfall at send-off.
	var offered := RunState.offer_perks(main._last_missed_stats)
	check(_has_id(offered, "self_sufficiency"),
		"the always-eligible perk is among the lesson's offers")

	# Taking the lesson banks it and carries on into the gather phase.
	lesson.perk_chosen.emit(offered[0])
	check(RunState.has_perk(offered[0].id), "the chosen lesson is banked")
	check(town.visible and not lesson.visible, "choosing a lesson opens the gather phase")
	check(town._total_days == tutorial.days, "the gather budget is the finished quest's length")
	check(town._current_day == 1, "the gather phase starts on day one")

	var grocer: ShopData = load("res://data/shops/grocer.tres")
	var apple_item: ItemData = load("res://data/items/apple.tres")

	# Travel event on the road: forced show grants gold, then "Head to the shops"
	# leads on. Events fire when the road loads now, before any shop is chosen.
	var found_coin: TravelEvent = load("res://data/travel_events/found_coin.tres")
	var pre_event_gold: int = RunState.gold
	town._show_travel_event(found_coin)
	check(RunState.gold == pre_event_gold + found_coin.gold_reward,
		"Found coin! grants its gold_reward")
	check(town._open_shop == null, "the travel event shows before any shop opens")
	town._enter_shop(grocer)
	check(town._open_shop == grocer, "entering the grocer opens its shop scene")
	check(town.shop_scene.visible, "the shop scene covers the road while shopping")

	# Buying spends gold and adds a copy; selling gives half back and removes it.
	# Both baselines are taken *here*, after the travel event — it hands out gold,
	# so a snapshot from before it would make every sum below wrong.
	var pre_buy_gold: int = RunState.gold
	var pre_buy_stock: int = RunState.inventory.size()

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
	# cheese + apple must not reappear.
	select.quest_chosen.emit(QUEST)
	await get_tree().process_frame
	check(packing.visible and not select.visible, "choosing a quest opens the packing screen")
	check(GameState.current_quest == QUEST, "the chosen quest became the current one")
	check(GameState.packed_items.is_empty(), "the new quest starts with an empty bag")
	check(GameState.stats["food"] == 0, "the new quest zeroes the stats")
	check(packing.bag_grid.is_cell_free(Vector2i(0, 0)), "the new quest frees the board")
	check(not is_instance_valid(cheese) or cheese.get_parent() != packing.bag_grid.item_layer,
		"the previous quest's placed items don't linger in the bag")
	check(packing.item_tray.item_views().size() == RunState.inventory.size(),
		"the tray rebuilt from the depleted inventory, got %d" % packing.item_tray.item_views().size())
	check(_find(packing.item_tray.item_views(),_id("cheese_wedge")) == null,
		"a spent item does not come back in the new quest's tray (cheese)")
	check(_find(packing.item_tray.item_views(),_id("apple")) == null,
		"a spent item does not come back in the new quest's tray (apple)")

	# And the loop actually loops — and keeps wearing the pack down. The sword is a
	# 5-trip item, so a send-off wears it rather than spending it: assert the wear,
	# not a shrinking inventory (this used to expect the sword to vanish, back when
	# it lasted a single trip).
	var sword_view := _pack(packing, _id("sword"), Vector2i(0, 0))
	var sword_item: ItemData = sword_view.item
	var sword_before: int = sword_item.durability
	packing.sent_off.emit()
	# QUEST (rescue) has no departure, narrative, or homecoming authored at all,
	# so its log is legitimately empty — the playout still has to handle that
	# without hanging (see PlayoutScene.play()'s empty-log branch).
	check(playout.visible and playout.lines_box.get_child_count() == 0 and not playout.is_playing(),
		"a second playout for a quest with nothing authored ends with no lines, got %d lines" % playout.lines_box.get_child_count())
	check(sword_item.durability == sword_before - 1,
		"the second send-off wore the sword, %d -> %d" % [sword_before, sword_item.durability])
	check(RunState.inventory.has(sword_item),
		"a multi-trip item survives its send-off rather than being spent")


# --- helpers ------------------------------------------------------------------

## Drives one item from the tray into the bag through the real drag path. It
## goes through the `grabbed` signal rather than calling the handler, because
## the wiring of that signal is exactly what once broke under Main.
func _pack(packing: PackingScene, id: String, origin: Vector2i) -> DraggableItem:
	var view := _find(packing.item_tray.item_views(),id)
	view.grabbed.emit(view, Vector2.ZERO)
	check(packing._dragging == view, "grabbing %s starts a drag" % id)
	packing._preview_origin = origin
	packing._preview_valid = packing.bag_grid.can_place(view.get_shape(), origin)
	check(packing._preview_valid, "%s fits at %s" % [id, origin])
	packing._end_drag(true)
	return view


func _item(id: String) -> ItemData:
	return load("res://data/items/%s.tres" % id)


## The id a item file actually declares. Worth going through rather than writing
## the literal: apple.tres is authored as "Apple" while every other item is
## lowercase, so these tests keep working whichever way that gets settled.
func _id(file: String) -> String:
	return (_item(file) as ItemData).id


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
