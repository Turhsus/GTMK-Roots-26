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
## worn down each time a pack is sent off (see apply_wear_to_inventory /
## discard_worn_out), and moved both ways in
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
## Emitted when the player's backpack size changes (upgrade or reset). Packing
## applies the new size on the next load_quest; town refreshes its upgrade button.
signal bag_changed(cols: int, rows: int)

const POOL: QuestPool = preload("res://data/quest_pool.tres")
## The forced first quest. It is not in the pool — the loop hands it to the player
## directly before the normal draw-of-three ever runs (see main.gd). A gentle,
## short intro; clearing it kicks off the first gather phase.
const TUTORIAL: QuestData = preload("res://data/quests/tutorial.tres")
## Difficulty is capped here; past this every quest is drawn from the top tier.
const MAX_DIFFICULTY := 4
## How many quests to lay out for the player to choose between.
const CHOICE_COUNT := 3
## Gold in the purse at the very start of a run.
const STARTING_GOLD := 25
## The whole run's length: a global day clock that counts down across town visits.
## When it runs out the game is wrapping up — one last quest, then the end screen.
const TOTAL_DAYS := 15
## The shops in town. Held here rather than on the road because a shop's shelves are
## *run* state now: they deplete as the player buys and refill on the run's day clock,
## which has to keep ticking with no shop — and no road — on screen. RoadScene reads
## this list to lay the shops out.
const SHOPS: Array[ShopData] = [
	preload("res://data/shops/grocer.tres"),
	preload("res://data/shops/apothecary.tres"),
	preload("res://data/shops/blacksmith.tres"),
	preload("res://data/shops/leatherworker.tres"),
	preload("res://data/shops/cheese_shop.tres"),
]
## The one shop that sells backpack upgrades — the only place bag_tier can move.
## It carries no ItemData stock at all (see its `sells_bag_upgrade` flag); the
## "shelf" it has is a single upgrade that refills once per quest, not on the
## RESTOCK_INTERVAL_DAYS clock the item shops run on.
const LEATHERWORKER: ShopData = preload("res://data/shops/leatherworker.tres")
## The cheese shop's Buy tab is a pick-2-of-3 work shift (see `offers_cheese_shift`),
## not a shelf — same pattern as the leatherworker.
const CHEESE_SHOP: ShopData = preload("res://data/shops/cheese_shop.tres")
## Town days between restocks. Every this many days spent, every shop puts one more
## of each depleted item back on the shelf, up to that item's max QTY — so a shop
## bought out early in the run comes back slowly rather than all at once. Change this
## to move the whole cadence (see spend_day / _restock_shops).
const RESTOCK_INTERVAL_DAYS := 3
## Backpack size ladder: tier index -> side length (square bags). Starts at 3×3
## and upgrades at the leatherworker up to 6×6 (see upgrade_bag).
const BAG_SIZES: Array[int] = [3, 4, 5, 6]
## Gold cost to upgrade the bag, indexed by the tier being upgraded *from* — so
## 15 buys the 4×4, 25 the 5×5, 40 the 6×6. One entry short of BAG_SIZES on
## purpose: the top tier has nothing to buy.
const BAG_UPGRADE_COSTS: Array[int] = [15, 25, 40]

## The items the player owns at the start of a run. This is the whole tray now —
## quests no longer decide what is available, only the targets and story. Authored here (one obvious place) rather than in a .tres; list an item
## twice to start with two of it. Inventory is depleting: whatever is packed is
## spent on send-off and does not come back this pass.
const STARTER_INVENTORY: Array[ItemData] = [
	preload("res://data/items/apple.tres"),
	preload("res://data/items/cheese_wedge.tres"),
	preload("res://data/items/knife.tres"),
	preload("res://data/items/boots.tres"),
	preload("res://data/items/berries.tres"),
	preload("res://data/items/blanket.tres"),
]

## Quests cleared so far. Difficulty is derived from this: one clear per tier.
var completed_count: int = 0
## Quests sent off so far, cleared or not — the denominator for the end-of-run
## win/loss check (see register_result and ThankYouScreen.show_end).
var attempted_count: int = 0
## Ids of quests already cleared. A cleared quest is not offered again until its
## whole tier is exhausted, at which point the tier resets (see draw_choices).
var _cleared_ids: Array[String] = []
## The player's owned items for this run — the source the tray builds from.
## Grows and shrinks via discard_worn_out() / gain() / release(); stocked from
## STARTER_INVENTORY on a fresh run.
var inventory: Array[ItemData] = []
## Coins on hand. Starts at STARTING_GOLD, earned by clearing quests, spent (and
## partly recouped by selling) in the gather phase.
var gold: int = STARTING_GOLD
## Adventuring perks earned so far this run — permanent upgrades. Each is unique: a
## perk once owned is never offered again (see offer_perks). Their effects run through
## each perk's own hooks — GameState calls modify_stats while packing,
## apply_perks_to_items calls modify_item at send-off — so the systems never
## special-case an individual perk.
var owned_perks: Array[PerkData] = []
## One built instance of every perk kind (one per PERK_TYPES entry), the master list
## offer_perks and find_perk work from. Filled once in _ready; perks are stateless
## behaviour, so a single shared instance per kind is all that's ever needed.
var all_perks: Array[PerkData] = []
## The run's global day clock. Starts at TOTAL_DAYS and drops by one for each day
## spent in town (see spend_day). Once it hits zero the loop plays one final quest
## and ends (see main.gd); it is not what limits an individual gather phase — that
## budget is still the finished quest's `days`.
var days_remaining: int = TOTAL_DAYS
## How big the player's backpack is this run. Index into BAG_SIZES; upgraded at
## the leatherworker with gold (see upgrade_bag). Packing reads bag_cols/bag_rows
## from this.
var bag_tier: int = 0
## Whether the leatherworker has an upgrade on the bench right now. Unlike the item
## shops, this does not refill on the day clock: buying it empties the bench until
## the next quest is registered (see register_result / restock_bag_upgrade), so at
## most one upgrade is bought per quest cycle.
var _bag_upgrade_stocked: bool = true
## The day clock reading when the last upgrade was bought, or -1 for none this run.
## Compared against days_remaining to hold the second upgrade of a single town day —
## the per-day gate that sits on top of the per-quest one above.
var _bag_upgrade_day: int = -1
## What the shops have left: shop id -> { item id -> how many are on the shelf }.
## Only *depleted* entries are held. An item with no entry is fully stocked, which
## keeps the save small, means an untouched shop costs nothing, and lets a retuned
## max QTY take effect on shelves the player never touched (see shop_stock).
var _shop_stock: Dictionary = {}
## Town days spent since the last restock. At RESTOCK_INTERVAL_DAYS the shelves
## refill by one and this returns to zero.
var _days_since_restock: int = 0
## The inventory copies on loan from the current quest (its `quest_items`), added
## when the quest is selected and taken back when it completes — see
## lend_quest_items / reclaim_quest_items. Tracked by identity so reclaiming
## removes exactly the loaned copies, never a same-id item the player owns.
var _quest_item_loans: Array[ItemData] = []


## Every item and perk this run can involve, keyed by id, so a save file can name
## things by id instead of storing resources (see to_dict). Built once at boot.
var _items_by_id: Dictionary = {}


func _ready() -> void:
	_build_perks()
	_build_lookups()
	_stock_starter_inventory()


## Builds the one instance of each perk kind. Called before anything can offer or grant
## a perk. Idempotent-ish: clears first so a re-run (tests) doesn't double up.
func _build_perks() -> void:
	all_perks.clear()
	for perk_type in PerkRegistry.TYPES:
		all_perks.append(perk_type.new())


## The current difficulty tier: one cleared quest per tier, capped at the top.
func current_difficulty() -> int:
	return mini(completed_count, MAX_DIFFICULTY)


## Resolves each packed item's placement effects against the final board (see
## PackLayout). An effect may dock durability for a bad pack — packed upside down,
## crushed from above, next to the wrong thing. This only *changes durability*; it
## never deletes. Pass null (as the tests do) to skip board consequences entirely.
## Runs before perks and before the quest is judged, so a pack that destroys an item
## gets no credit for it (see main._on_sent_off for the send-off order).
## Returns an array of player-friendly violation messages describing which penalties
## were triggered, so the player understands what went wrong with their packing.
func resolve_item_effects(items: Array[ItemData], layout: PackLayout) -> Array[String]:
	var violations: Array[String] = []
	if layout == null:
		return violations
	for item in items:
		for effect in item.effects:
			effect.resolve_send_off(item, layout)
			var violation_msg: String = effect.get_violation_message(item, layout)
			if violation_msg != "":
				violations.append(violation_msg)
	return violations


## Each owned perk gets to change every packed item via its modify_item hook (the
## crafty perk repairs a combat item now and then). Only changes durability/state;
## never deletes. Runs after effects so a perk gets the last, kindest word.
func apply_perks_to_items(items: Array[ItemData]) -> void:
	for item in items:
		for perk in owned_perks:
			perk.modify_item(item)


## The trip's flat cost: every packed item loses one point of durability. Nothing
## else — placement effects, perks, and discarding worn-out copies are each their own
## step now (see resolve_item_effects / apply_perks_to_items / discard_worn_out), so
## the send-off can order them around the quest's success check (main._on_sent_off).
## The packed items are the very inventory copies (the tray builds off `inventory`),
## so this wears exactly the slots that were packed.
func apply_wear_to_inventory(items: Array[ItemData]) -> void:
	for item in items:
		item.durability -= 1


## Throws away every worn-out copy (durability <= 0) among `items`, erasing it from
## the inventory for good, and returns the copies discarded so the caller can drop
## them from anywhere else they're tracked — the current packing, so a destroyed item
## stops counting toward the quest (see main._on_sent_off). Erases by identity: the
## packed copies are the very inventory copies. (Restock hook unchanged: to regain
## items, append to `inventory` and emit.)
func discard_worn_out(items: Array[ItemData]) -> Array[ItemData]:
	var worn: Array[ItemData] = []
	for item in items:
		if item.durability <= 0:
			worn.append(item)
	for item in worn:
		inventory.erase(item)
	if not worn.is_empty():
		inventory_changed.emit(inventory)
	return worn


## Records the outcome of a sent-off quest. Only a clear advances difficulty and
## pays the reward; a failed quest can be drawn again straight away and pays
## nothing. The reward lands here so the gold is on hand for the gather phase that
## follows the playout.
func register_result(quest: QuestData, success: bool) -> void:
	if quest != null:
		attempted_count += 1
	if success and quest != null:
		if not _cleared_ids.has(quest.id):
			_cleared_ids.append(quest.id)
		completed_count += 1
		add_gold(quest.gold_reward)
	# The leatherworker's restock clock is quests, not days: finishing one — cleared
	# or not — puts the next upgrade back on his bench for the gather that follows.
	restock_bag_upgrade()
	progress_changed.emit(completed_count, current_difficulty())


## Spends one day off the run's global clock — called once per day passed in town.
## Kept separate from the per-gather day budget: a gather still runs its full length
## even if this crosses zero partway through (main.gd waits until the gather ends).
func spend_day() -> void:
	days_remaining -= 1
	_days_since_restock += 1
	if _days_since_restock >= RESTOCK_INTERVAL_DAYS:
		_days_since_restock = 0
		_restock_shops()
	days_changed.emit(days_remaining)


## Whether the global day clock has run out — the cue to play the final quest and
## wrap the run up (checked once a gather phase finishes; see main.gd).
func days_are_up() -> bool:
	return days_remaining <= 0


# --- shop shelves ---------------------------------------------------------------
#
# A shop sells each of its items up to that item's max QTY (authored on the ShopData),
# and the player may buy as many as they can afford until the shelf is bare. Nothing
# resets between gathers: the only way stock comes back is the restock tick below,
# one unit per depleted item every RESTOCK_INTERVAL_DAYS town days. Selling an item
# back does *not* return it to the shelves — the shop's supply is its own.

## How many of `item` `shop` still has. An item never bought is at its authored max.
func shop_stock(shop: ShopData, item: ItemData) -> int:
	if shop == null or item == null:
		return 0
	var shelf: Dictionary = _shop_stock.get(shop.id, {})
	if not shelf.has(item.id):
		return shop.max_qty(item)
	return clampi(int(shelf[item.id]), 0, shop.max_qty(item))


## Takes one `item` off `shop`'s shelf, reporting whether there was one to take, so a
## caller can gate a purchase on it (see RoadScene._on_buy). Gold is a separate step:
## this only moves stock.
func take_shop_stock(shop: ShopData, item: ItemData) -> bool:
	var left := shop_stock(shop, item)
	if left <= 0:
		return false
	if not _shop_stock.has(shop.id):
		_shop_stock[shop.id] = {}
	_shop_stock[shop.id][item.id] = left - 1
	return true


## Puts one `item` back on `shop`'s shelf, capped at the authored max QTY. Used when
## the player returns a purchase from the same visit (see RoadScene._on_return).
## Resolves by id — the returned copy is an owned instance, not the shop's template.
func return_shop_stock(shop: ShopData, item: ItemData) -> void:
	if shop == null or item == null:
		return
	var shelf_item := shop.find(item.id)
	if shelf_item == null:
		return
	var max_qty := shop.max_qty(shelf_item)
	if max_qty <= 0:
		return
	var left := shop_stock(shop, shelf_item)
	if left >= max_qty:
		return
	if not _shop_stock.has(shop.id):
		_shop_stock[shop.id] = {}
	var next := left + 1
	if next >= max_qty:
		(_shop_stock[shop.id] as Dictionary).erase(shelf_item.id)
		if (_shop_stock[shop.id] as Dictionary).is_empty():
			_shop_stock.erase(shop.id)
	else:
		_shop_stock[shop.id][shelf_item.id] = next


## Town days until the next restock — what the shop screen tells the player.
func days_until_restock() -> int:
	return maxi(RESTOCK_INTERVAL_DAYS - _days_since_restock, 0)


## One restock tick: every shop puts a single unit of each depleted item back, capped
## at that item's max QTY. Only depleted shelves are tracked at all, so this walks
## just those; an item back at full drops its entry entirely, and an entry for an item
## the shop no longer sells is pruned on the way past.
func _restock_shops() -> void:
	for shop in SHOPS:
		if not _shop_stock.has(shop.id):
			continue
		var shelf: Dictionary = _shop_stock[shop.id]
		# keys() is a copy, so entries can be dropped while walking it.
		for item_id in shelf.keys():
			# Annotated, not inferred: a preloaded .tres reaches the parser as its
			# script-path type, so find()'s return needs naming here (same reason
			# find_quest defers its search to QuestPool).
			var item: ItemData = shop.find(String(item_id))
			if item == null:
				shelf.erase(item_id)
				continue
			var restocked := int(shelf[item_id]) + 1
			if restocked >= shop.max_qty(item):
				shelf.erase(item_id)
			else:
				shelf[item_id] = restocked
		if shelf.is_empty():
			_shop_stock.erase(shop.id)


## The authored ShopData for an id, or null. Walks the town list.
func find_shop(id: String) -> ShopData:
	for shop in SHOPS:
		if shop.id == id:
			return shop
	return null


## Current backpack width in cells (from bag_tier).
func bag_cols() -> int:
	return BAG_SIZES[clampi(bag_tier, 0, BAG_SIZES.size() - 1)]


## Current backpack height in cells (square bags — same as bag_cols).
func bag_rows() -> int:
	return bag_cols()


## True when the bag has a tier left to climb — the ladder alone, ignoring whether
## the leatherworker will sell one today (see bag_upgrade_available).
func can_upgrade_bag() -> bool:
	return bag_tier < BAG_SIZES.size() - 1


## True when an upgrade can actually be bought right now: a tier left to climb, an
## upgrade still on the leatherworker's bench this quest, and none already bought
## today. Gold is *not* part of this — an affordable-or-not upgrade still shows on
## the bench, just with the button disabled (see ShopScene).
func bag_upgrade_available() -> bool:
	return can_upgrade_bag() and _bag_upgrade_stocked and days_remaining != _bag_upgrade_day


## Why the bench is empty, for the shop to print — "" when an upgrade is on offer.
func bag_upgrade_blocked_reason() -> String:
	if not can_upgrade_bag():
		return "Nothing bigger to build — that's the largest pack there is."
	if not _bag_upgrade_stocked:
		return "The bench is bare. \"Come back once they're home from the next trip.\""
	if days_remaining == _bag_upgrade_day:
		return "\"One pack a day, love. The glue needs the night to set.\""
	return ""


## Puts an upgrade back on the leatherworker's bench. Called when a quest is
## registered, cleared or not — the restock clock here is quests, not days.
func restock_bag_upgrade() -> void:
	_bag_upgrade_stocked = true


## Gold cost of the next upgrade, or 0 if already maxed.
func bag_upgrade_cost() -> int:
	if not can_upgrade_bag():
		return 0
	return BAG_UPGRADE_COSTS[bag_tier]


## Side length after the next upgrade, or the current size if maxed.
func next_bag_size() -> int:
	if not can_upgrade_bag():
		return bag_cols()
	return BAG_SIZES[bag_tier + 1]


## Spends the upgrade cost and bumps bag_tier. Returns false if maxed, broke, or the
## leatherworker has nothing to sell today (see bag_upgrade_available). Buying clears
## the bench until the next quest and marks the day, so the next upgrade needs both a
## finished quest and a fresh morning.
func upgrade_bag() -> bool:
	if not bag_upgrade_available():
		return false
	var cost := bag_upgrade_cost()
	if not spend_gold(cost):
		return false
	bag_tier += 1
	_bag_upgrade_stocked = false
	_bag_upgrade_day = days_remaining
	bag_changed.emit(bag_cols(), bag_rows())
	return true


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
## instance, independent of the shop's stock and any copy already owned). Returns
## the new copy so the road can track it for same-visit returns. The tray doesn't
## rebuild on inventory_changed (that fires mid-send-off), so a buy shows up when
## the next quest's packing loads.
func gain(item: ItemData) -> ItemData:
	if item == null:
		return null
	var copy := item.make_owned_copy()
	inventory.append(copy)
	inventory_changed.emit(inventory)
	return copy


## Puts an already-owned copy back into the inventory without cloning — used when
## buying back something sold earlier in the same shop visit (durability preserved).
func restore(item: ItemData) -> void:
	if item == null:
		return
	inventory.append(item)
	inventory_changed.emit(inventory)


## Removes this exact owned copy from the inventory (identity match, not id). Used
## when returning a same-visit purchase so a different apple isn't taken by mistake.
func release_exact(item: ItemData) -> bool:
	if item == null or not inventory.has(item):
		return false
	inventory.erase(item)
	inventory_changed.emit(inventory)
	return true


## Drops one owned copy of an item and returns it — a sale in town. Owned copies
## are distinct instances now (each tracks its own wear), so this matches on `id`
## and drops the first such copy, leaving any others (and their separate
## durability) in place. Returns null when nothing matched.
func release(item: ItemData) -> ItemData:
	if item == null:
		return null
	for owned in inventory:
		if owned.id == item.id:
			inventory.erase(owned)
			inventory_changed.emit(inventory)
			return owned
	return null


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


## The perks to offer after a failed quest: those not yet owned whose trigger_stat is
## among the missed targets. Contextual — a food shortfall surfaces the forage perk,
## a combat shortfall the crafty one; a perk with no trigger_stat is always eligible.
## Empty means nothing new to offer (a clear, or every relevant perk already earned),
## in which case the loop skips the lesson screen (see main.gd).
func offer_perks(missed_stats: Array[String]) -> Array[PerkData]:
	var offers: Array[PerkData] = []
	for perk in all_perks:
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
	attempted_count = 0
	_cleared_ids.clear()
	_stock_starter_inventory()
	gold = STARTING_GOLD
	gold_changed.emit(gold)
	owned_perks.clear()
	perks_changed.emit(owned_perks)
	days_remaining = TOTAL_DAYS
	days_changed.emit(days_remaining)
	_shop_stock.clear()
	_days_since_restock = 0
	bag_tier = 0
	_bag_upgrade_stocked = true
	_bag_upgrade_day = -1
	bag_changed.emit(bag_cols(), bag_rows())
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
	# Depleted shelves only, named by shop id and item id like everything else here,
	# so a shop whose stock or max QTY is retuned still loads.
	var shelves: Dictionary = {}
	for shop_id in _shop_stock:
		shelves[shop_id] = (_shop_stock[shop_id] as Dictionary).duplicate()
	return {
		"completed_count": completed_count,
		"attempted_count": attempted_count,
		"cleared_ids": _cleared_ids.duplicate(),
		"gold": gold,
		"days_remaining": days_remaining,
		"bag_tier": bag_tier,
		"bag_upgrade_stocked": _bag_upgrade_stocked,
		"bag_upgrade_day": _bag_upgrade_day,
		"inventory": items,
		"perks": perk_ids,
		"shop_stock": shelves,
		"days_since_restock": _days_since_restock,
	}


## Restores a run from to_dict's output. Anything missing falls back to a fresh
## run's value and an id that no longer exists is skipped, so a save written
## before an item or perk was renamed still loads — just without that entry.
## Emits every signal at the end so screens already in the tree catch up.
func from_dict(data: Dictionary) -> void:
	completed_count = maxi(int(data.get("completed_count", 0)), 0)
	attempted_count = maxi(int(data.get("attempted_count", completed_count)), completed_count)
	_cleared_ids.clear()
	for id in data.get("cleared_ids", []):
		_cleared_ids.append(String(id))
	gold = maxi(int(data.get("gold", STARTING_GOLD)), 0)
	days_remaining = int(data.get("days_remaining", TOTAL_DAYS))
	bag_tier = clampi(int(data.get("bag_tier", 0)), 0, BAG_SIZES.size() - 1)
	# A save written before the leatherworker existed comes back with the bench
	# stocked and no purchase on the books — the generous reading of a missing field.
	_bag_upgrade_stocked = bool(data.get("bag_upgrade_stocked", true))
	_bag_upgrade_day = int(data.get("bag_upgrade_day", -1))

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

	_restore_shop_stock(data.get("shop_stock", {}))
	_days_since_restock = clampi(int(data.get("days_since_restock", 0)), 0, RESTOCK_INTERVAL_DAYS - 1)

	inventory_changed.emit(inventory)
	gold_changed.emit(gold)
	perks_changed.emit(owned_perks)
	days_changed.emit(days_remaining)
	bag_changed.emit(bag_cols(), bag_rows())
	progress_changed.emit(completed_count, current_difficulty())


## Rebuilds the depleted shelves from a save. A shop or item that no longer exists is
## dropped, and a count is clamped to the item's *current* max QTY — a shelf saved at
## 3 must not come back over-stocked after the max was tuned down to 2. A shelf that
## clamps back up to full keeps no entry at all, matching how to_dict writes them.
func _restore_shop_stock(saved: Variant) -> void:
	_shop_stock.clear()
	if not (saved is Dictionary):
		return
	for shop_id in saved as Dictionary:
		var shop := find_shop(String(shop_id))
		var shelf: Variant = (saved as Dictionary)[shop_id]
		if shop == null or not (shelf is Dictionary):
			continue
		var restored: Dictionary = {}
		for item_id in shelf as Dictionary:
			var item: ItemData = shop.find(String(item_id))
			if item == null:
				continue
			# int-cast: a JSON round trip turns the counts into floats.
			var left := clampi(int((shelf as Dictionary)[item_id]), 0, shop.max_qty(item))
			if left < shop.max_qty(item):
				restored[String(item_id)] = left
		if not restored.is_empty():
			_shop_stock[String(shop_id)] = restored


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


## The built PerkData instance for an id, or null. Perks are a short list, so this
## just walks it.
func find_perk(id: String) -> PerkData:
	for perk in all_perks:
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
