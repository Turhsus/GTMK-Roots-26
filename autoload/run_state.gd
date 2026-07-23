extends Node

## Autoload. The run's meta-progression across quests, sitting a level above
## GameState (which only knows the *current* packing): how many quests have been
## cleared, what difficulty that puts us at, and drawing the next choices.
##
## The loop is: RunState.draw_choices() offers a few quests -> the player packs
## and sends one off -> RunState.register_result() records whether it was cleared
## -> back to draw_choices(), now maybe a tier harder.

## Emitted after a quest is registered, whether or not it was cleared.
signal progress_changed(completed: int, difficulty: int)
## Emitted whenever the owned inventory changes: stocked at the start of a run,
## worn down each time a pack is sent off (see apply_wear), and moved both ways in
## the gather phase as the player buys and sells (see gain / release).
signal inventory_changed(inventory: Array[ItemData])
## Emitted whenever the player's gold changes: the starting purse, a quest reward,
## and every buy or sell in town.
signal gold_changed(gold: int)
## Emitted whenever the earned perks change — i.e. when a perk is picked after a
## failed quest (see add_perk), and cleared on reset.
signal perks_changed(perks: Array[PerkData])
## Emitted whenever the run's global day clock ticks down (one per town day spent)
## or is reset. When it reaches zero the run is winding up: the current gather is
## allowed to finish, then one final quest plays and the game ends (see main.gd).
signal days_changed(days_remaining: int)

const POOL: QuestPool = preload("res://data/quest_pool.tres")
## The forced first quest. It is not in the pool — the loop hands it to the player
## directly before the normal draw-of-three ever runs (see main.gd). A gentle,
## short intro; clearing it kicks off the first gather phase.
const TUTORIAL: QuestData = preload("res://data/quests/tutorial.tres")
## Every perk that can be earned this game — permanent upgrades unlocked by failing
## a quest and picking the lesson that fits (see offer_perks). Authored as .tres;
## list one here to make it earnable. Held in a const like the starter pack; a pool
## resource can replace this if the list grows.
const ALL_PERKS: Array[PerkData] = [
	preload("res://data/perks/forage.tres"),
	preload("res://data/perks/crafty.tres"),
]
## Difficulty is capped here; past this every quest is drawn from the top tier.
const MAX_DIFFICULTY := 4
## How many quests to lay out for the player to choose between.
const CHOICE_COUNT := 3
## Gold in the purse at the very start of a run.
const STARTING_GOLD := 50
## The whole run's length: a global day clock that counts down across town visits.
## When it runs out the game is wrapping up — one last quest, then the end screen.
const TOTAL_DAYS := 10

## The items the player owns at the start of a run. This is the whole tray now —
## quests no longer decide what is available, only the targets and story. Authored here (one obvious place) rather than in a .tres; list an item
## twice to start with two of it. Inventory is depleting: whatever is packed is
## spent on send-off and does not come back this pass.
const STARTER_INVENTORY: Array[ItemData] = [
	preload("res://data/items/apple.tres"),
	preload("res://data/items/sword.tres"),
	preload("res://data/items/cheese_wedge.tres"),
]

## Quests cleared so far. Difficulty is derived from this: one clear per tier.
var completed_count: int = 0
## Ids of quests already cleared. A cleared quest is not offered again until its
## whole tier is exhausted, at which point the tier resets (see draw_choices).
var _cleared_ids: Array[String] = []
## The player's owned items for this run — the source the tray builds from.
## Grows and shrinks via apply_wear() / gain() / release(); stocked from
## STARTER_INVENTORY on a fresh run.
var inventory: Array[ItemData] = []
## Coins on hand. Starts at STARTING_GOLD, earned by clearing quests, spent (and
## partly recouped by selling) in the gather phase.
var gold: int = STARTING_GOLD
## Adventuring perks earned so far this run — permanent upgrades. Each is unique: a
## perk once owned is never offered again (see offer_perks). Their effects are read
## through food_bonus (folded into the food stat) and apply_wear (the wear skip).
var owned_perks: Array[PerkData] = []
## The run's global day clock. Starts at TOTAL_DAYS and drops by one for each day
## spent in town (see spend_day). Once it hits zero the loop plays one final quest
## and ends (see main.gd); it is not what limits an individual gather phase — that
## budget is still the finished quest's `days`.
var days_remaining: int = TOTAL_DAYS
## The inventory copies on loan from the current quest (its `quest_items`), added
## when the quest is selected and taken back when it completes — see
## lend_quest_items / reclaim_quest_items. Tracked by identity so reclaiming
## removes exactly the loaned copies, never a same-id item the player owns.
var _quest_item_loans: Array[ItemData] = []


## Every item and perk this run can involve, keyed by id, so a save file can name
## things by id instead of storing resources (see to_dict). Built once at boot.
var _items_by_id: Dictionary = {}


func _ready() -> void:
	_build_lookups()
	_stock_starter_inventory()


## The current difficulty tier: one cleared quest per tier, capped at the top.
func current_difficulty() -> int:
	return mini(completed_count, MAX_DIFFICULTY)


## Wears down every packed item by one trip — this is send-off, where the pack
## goes out on the quest. Each copy loses a point of durability; one that hits zero
## is worn out and thrown away for good, while sturdier items (a blanket lasts
## three) come home with less left and can be packed again. This replaces the old
## rule of spending the whole pack outright. The packed items are the very
## inventory copies (the tray builds off `inventory`), so erasing by identity here
## removes exactly the slot that was packed.
## (Restock hook unchanged: to regain items, append to `inventory` and emit.)
func apply_wear(items: Array[ItemData]) -> void:
	if items.is_empty():
		return
	var skip_chance := combat_wear_skip_chance()
	for item in items:
		# Crafty perk: a combat item sometimes comes home untouched — it isn't spent
		# this trip, so it skips the wear entirely. Rolled per combat item packed.
		if skip_chance > 0.0 and item.combat > 0 and randf() < skip_chance:
			continue
		item.durability -= 1
		if item.durability <= 0:
			inventory.erase(item)
	inventory_changed.emit(inventory)


## Records the outcome of a sent-off quest. Only a clear advances difficulty and
## pays the reward; a failed quest can be drawn again straight away and pays
## nothing. The reward lands here so the gold is on hand for the gather phase that
## follows the playout.
func register_result(quest: QuestData, success: bool) -> void:
	if success and quest != null:
		if not _cleared_ids.has(quest.id):
			_cleared_ids.append(quest.id)
		completed_count += 1
		add_gold(quest.gold_reward)
	progress_changed.emit(completed_count, current_difficulty())


## Spends one day off the run's global clock — called once per day passed in town.
## Kept separate from the per-gather day budget: a gather still runs its full length
## even if this crosses zero partway through (main.gd waits until the gather ends).
func spend_day() -> void:
	days_remaining -= 1
	days_changed.emit(days_remaining)


## Whether the global day clock has run out — the cue to play the final quest and
## wrap the run up (checked once a gather phase finishes; see main.gd).
func days_are_up() -> bool:
	return days_remaining <= 0


## Adds coins to the purse (a quest reward, or a sale). Ignores non-positive
## amounts so a zero-reward quest doesn't churn the signal.
func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


## Tries to spend `amount`. Returns false and leaves the purse untouched if it
## can't be afforded, so callers can gate a purchase on the return value.
func spend_gold(amount: int) -> bool:
	if amount < 0 or amount > gold:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


## Adds one owned copy of an item — a purchase in town. A bought item is fresh, so
## it enters at full durability via make_owned_copy (which also gives it its own
## instance, independent of the shop's stock and any copy already owned). The tray
## doesn't rebuild on inventory_changed (that fires mid-send-off), so a buy shows up
## when the next quest's packing loads.
func gain(item: ItemData) -> void:
	if item == null:
		return
	inventory.append(item.make_owned_copy())
	inventory_changed.emit(inventory)


## Drops one owned copy of an item and reports whether it had one to drop — a sale
## in town. Owned copies are distinct instances now (each tracks its own wear), so
## this matches on `id` and drops the first such copy, leaving any others (and their
## separate durability) in place.
func release(item: ItemData) -> bool:
	if item == null:
		return false
	for owned in inventory:
		if owned.id == item.id:
			inventory.erase(owned)
			inventory_changed.emit(inventory)
			return true
	return false


## Lends the quest's `quest_items` to the player for the quest's duration: each
## enters the inventory as its own owned copy (full durability, independent of the
## authored resource) so the tray offers it alongside everything owned. Called when
## a quest is selected (see main.gd); the copies are remembered so
## reclaim_quest_items can take back exactly these when the quest completes.
func lend_quest_items(quest: QuestData) -> void:
	if quest == null or quest.quest_items.is_empty():
		return
	for item in quest.quest_items:
		var copy: ItemData = item.make_owned_copy()
		inventory.append(copy)
		_quest_item_loans.append(copy)
	inventory_changed.emit(inventory)


## Takes back the loaned quest items when the quest completes, cleared or not.
## A loaned copy that was packed and worn out on the trip is already gone from the
## inventory — erasing by identity just skips it. Safe to call with nothing on loan.
func reclaim_quest_items() -> void:
	if _quest_item_loans.is_empty():
		return
	for item in _quest_item_loans:
		inventory.erase(item)
	_quest_item_loans.clear()
	inventory_changed.emit(inventory)


## Grants a perk, ignoring one already owned (perks are unique). The permanent
## upgrade takes effect immediately: the food bonus shows the next time the stats
## recompute, the wear skip on the next send-off.
func add_perk(perk: PerkData) -> void:
	if perk == null or has_perk(perk.id):
		return
	owned_perks.append(perk)
	perks_changed.emit(owned_perks)


func has_perk(perk_id: String) -> bool:
	for perk in owned_perks:
		if perk.id == perk_id:
			return true
	return false


## Flat food granted by owned perks, folded into the food stat from the start of
## packing so the player sees it and packs around it (GameState._recompute reads it).
func food_bonus() -> int:
	var bonus := 0
	for perk in owned_perks:
		bonus += perk.food_bonus
	return bonus


## The chance a single combat item escapes wear on send-off, combined across owned
## perks. Perks are unique, so today this is just the crafty perk's 0.1 when owned;
## combining as independent rolls (1 − product of misses) keeps it sane if more
## wear-skip perks are ever added — it approaches 1 rather than overflowing it.
func combat_wear_skip_chance() -> float:
	var keep_worn := 1.0
	for perk in owned_perks:
		keep_worn *= 1.0 - perk.combat_wear_skip_chance
	return 1.0 - keep_worn


## The perks to offer after a failed quest: those not yet owned whose trigger_stat is
## among the missed targets. Contextual — a food shortfall surfaces the forage perk,
## a combat shortfall the crafty one; a perk with no trigger_stat is always eligible.
## Empty means nothing new to offer (a clear, or every relevant perk already earned),
## in which case the loop skips the lesson screen (see main.gd).
func offer_perks(missed_stats: Array[String]) -> Array[PerkData]:
	var offers: Array[PerkData] = []
	for perk in ALL_PERKS:
		if has_perk(perk.id):
			continue
		if perk.trigger_stat == "" or missed_stats.has(perk.trigger_stat):
			offers.append(perk)
	return offers


## Up to CHOICE_COUNT quests from the current tier, cleared ones held back until
## the tier runs dry, then the tier resets and is offered fresh. Fewer than three
## may come back if that is all the tier has; an empty tier falls back to the
## nearest one that has quests, so a sparse pool never dead-ends the loop.
func draw_choices() -> Array[QuestData]:
	var tier := POOL.by_difficulty(current_difficulty())
	if tier.is_empty():
		tier = _nearest_tier(current_difficulty())
	if tier.is_empty():
		return []

	var available: Array[QuestData] = []
	for quest in tier:
		if not _cleared_ids.has(quest.id):
			available.append(quest)
	if available.is_empty():
		# Every quest here is cleared: wipe this tier's clears and offer it anew.
		for quest in tier:
			_cleared_ids.erase(quest.id)
		available = tier.duplicate()

	available.shuffle()
	while available.size() > CHOICE_COUNT:
		available.remove_at(available.size() - 1)
	return available


## Back to a fresh run. Also the clean slate the tests lean on. Re-stocks the
## inventory, so a new run starts with a full pack of starter items.
func reset() -> void:
	completed_count = 0
	_cleared_ids.clear()
	_stock_starter_inventory()
	gold = STARTING_GOLD
	gold_changed.emit(gold)
	owned_perks.clear()
	perks_changed.emit(owned_perks)
	days_remaining = TOTAL_DAYS
	days_changed.emit(days_remaining)
	progress_changed.emit(completed_count, current_difficulty())


# --- saving --------------------------------------------------------------------
#
# A save stores *ids and numbers*, never resources. Writing the ItemData itself
# into the file would freeze a copy of the item's authored stats, so retuning a
# .tres would leave old saves carrying stale numbers (or fail to load at all).
# Naming things by id means the save always re-reads the current authored data.

## The whole run as plain, JSON-safe data. SaveManager wraps this with the loop
## position (which screen the player was on) and writes it out.
func to_dict() -> Dictionary:
	var items: Array = []
	for item in inventory:
		# Durability is per-copy, so it travels with the entry rather than the id.
		var entry := {"id": item.id, "durability": item.durability}
		# A copy on loan from the current quest is flagged so a resumed run can
		# still take it back when the quest completes.
		if _quest_item_loans.has(item):
			entry["on_loan"] = true
		items.append(entry)
	var perk_ids: Array = []
	for perk in owned_perks:
		perk_ids.append(perk.id)
	return {
		"completed_count": completed_count,
		"cleared_ids": _cleared_ids.duplicate(),
		"gold": gold,
		"days_remaining": days_remaining,
		"inventory": items,
		"perks": perk_ids,
	}


## Restores a run from to_dict's output. Anything missing falls back to a fresh
## run's value and an id that no longer exists is skipped, so a save written
## before an item or perk was renamed still loads — just without that entry.
## Emits every signal at the end so screens already in the tree catch up.
func from_dict(data: Dictionary) -> void:
	completed_count = maxi(int(data.get("completed_count", 0)), 0)
	_cleared_ids.clear()
	for id in data.get("cleared_ids", []):
		_cleared_ids.append(String(id))
	gold = maxi(int(data.get("gold", STARTING_GOLD)), 0)
	days_remaining = int(data.get("days_remaining", TOTAL_DAYS))

	inventory.clear()
	_quest_item_loans.clear()
	for entry in data.get("inventory", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item := find_item(String(entry.get("id", "")))
		if item == null:
			continue
		var copy := item.make_owned_copy()
		# Clamped to the item's *current* max: if a blanket was retuned from 3 uses
		# down to 2, a save holding 3 must not come back over-durable.
		copy.durability = clampi(int(entry.get("durability", copy.durability)), 1, copy.max_durability)
		inventory.append(copy)
		if bool(entry.get("on_loan", false)):
			_quest_item_loans.append(copy)

	owned_perks.clear()
	for perk_id in data.get("perks", []):
		var perk := find_perk(String(perk_id))
		if perk != null:
			owned_perks.append(perk)

	inventory_changed.emit(inventory)
	gold_changed.emit(gold)
	perks_changed.emit(owned_perks)
	days_changed.emit(days_remaining)
	progress_changed.emit(completed_count, current_difficulty())


## The authored ItemData for an id, or null if nothing owns that id any more.
func find_item(id: String) -> ItemData:
	if id.is_empty():
		return null
	if _items_by_id.has(id):
		return _items_by_id[id]
	# Not a starter item — fall back to the data/items/<id>.tres naming convention
	# so an item that only ever appears in a shop still round-trips through a save.
	var path := "res://data/items/%s.tres" % id
	if not ResourceLoader.exists(path):
		return null
	var item := load(path) as ItemData
	if item != null:
		_items_by_id[id] = item
	return item


## The authored PerkData for an id, or null. Perks are a short const list, so this
## just walks it.
func find_perk(id: String) -> PerkData:
	for perk in ALL_PERKS:
		if perk.id == id:
			return perk
	return null


## The authored QuestData for an id, or null. Covers the pool plus the tutorial,
## which is the whole set a save can ever point at.
func find_quest(id: String) -> QuestData:
	if id == TUTORIAL.id:
		return TUTORIAL
	# The search itself lives on QuestPool: iterating POOL.quests from here gives the
	# parser the script-path element type, which won't unify with the QuestData
	# return annotation, while inside quest_pool.gd the types resolve natively.
	return POOL.find_by_id(id)


## Indexes every item an id could refer to. The starter list is the master set
## today (it holds all authored items), but a shop could stock something outside
## it, so anything missing is loaded by the data/items/<id>.tres convention.
func _build_lookups() -> void:
	_items_by_id.clear()
	for item in STARTER_INVENTORY:
		_items_by_id[item.id] = item


## Fills the inventory from the authored starter list. Each entry is its own owned
## copy (make_owned_copy) so wearing one down never touches the shared const
## resources, the shop stock, or another copy of the same item.
func _stock_starter_inventory() -> void:
	inventory.clear()
	_quest_item_loans.clear()
	for item in STARTER_INVENTORY:
		inventory.append(item.make_owned_copy())
	inventory_changed.emit(inventory)


## The closest tier to `tier` that actually has quests, searching outward (down
## first, since a lower quest is fairer than a higher one when the exact tier is
## empty). Empty only if the whole pool is.
func _nearest_tier(tier: int) -> Array[QuestData]:
	for delta in range(1, MAX_DIFFICULTY + 1):
		var below := POOL.by_difficulty(tier - delta)
		if not below.is_empty():
			return below
		var above := POOL.by_difficulty(tier + delta)
		if not above.is_empty():
			return above
	return []
