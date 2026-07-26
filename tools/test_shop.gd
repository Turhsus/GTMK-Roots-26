extends Node

## Throwaway harness for the shops: per-item QTY on the shelves, buying until a
## shelf is bare, the restock clock, and how all of it survives a save.
## Run: godot --headless --path . res://tools/TestShop.tscn
##
## The road scene is instanced for real here (it owns the buy/sell wiring), so this
## needs the autoloads — hence a scene rather than --script.

const ROAD := preload("res://scenes/gather/RoadScene.tscn")

var failures: int = 0


func _ready() -> void:
	_test_authored_quantities()
	_test_buying_depletes_one_shelf()
	_test_restock_clock()
	_test_restock_caps_at_max()
	_test_persists_across_gathers()
	_test_save_round_trip()
	_test_leatherworker()
	await _test_road_buys()
	await _test_buyback()
	await _test_road_bag_upgrade()

	RunState.reset()

	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


# --- the authored shelves -------------------------------------------------------

## Every shop starts full, at the QTY authored per item — DEFAULT_MAX_QTY where the
## .tres leaves it at zero. The base is 1 today; the point of the check is that the
## number comes from the data, not from a constant buried in the shop screen.
func _test_authored_quantities() -> void:
	RunState.reset()
	for shop in RunState.SHOPS:
		var items: Array[ItemData] = shop.items()
		# The leatherworker sells no items at all — his one trade is the bag upgrade,
		# which isn't an ItemData and has its own tests below.
		if shop.sells_bag_upgrade:
			check(items.is_empty(), "%s sells the bag upgrade and no items" % shop.id)
			continue
		check(not items.is_empty(), "%s has stock authored" % shop.id)
		for item in items:
			check(shop.max_qty(item) >= 1, "%s stocks %s with a positive max QTY" % [shop.id, item.id])
			check(RunState.shop_stock(shop, item) == shop.max_qty(item),
				"%s starts %s at its max QTY" % [shop.id, item.id])

	# The programmer knob: raise one item's QTY and a fresh shelf follows it.
	var grocer := RunState.find_shop("grocer")
	var apple := grocer.find("Apple")
	var authored := grocer.stock[apple]
	grocer.stock[apple] = 4
	check(RunState.shop_stock(grocer, apple) == 4, "a retuned max QTY shows on an untouched shelf")
	grocer.stock[apple] = authored


func _test_buying_depletes_one_shelf() -> void:
	RunState.reset()
	var grocer := RunState.find_shop("grocer")
	var apple := grocer.find("Apple")
	var bread := grocer.find("bread")
	# Two deep, so "buy as many as you can afford" has something to spend on.
	var authored := grocer.stock[apple]
	grocer.stock[apple] = 2

	check(RunState.take_shop_stock(grocer, apple), "the first apple comes off the shelf")
	check(RunState.shop_stock(grocer, apple) == 1, "one apple left, got %d"
		% RunState.shop_stock(grocer, apple))
	check(RunState.take_shop_stock(grocer, apple), "the second apple comes off too")
	check(RunState.shop_stock(grocer, apple) == 0, "the apple shelf is bare")
	check(not RunState.take_shop_stock(grocer, apple), "a bare shelf refuses the next buy")

	# A bare shelf is that item's alone — nothing like the old whole-shop cap.
	check(RunState.shop_stock(grocer, bread) == grocer.max_qty(bread),
		"selling out of apples leaves the bread untouched")

	# Selling an item back is not a delivery: the shop's own supply stays bare.
	RunState.gain(apple)
	# release() hands back the copy it removed (or null), not a bool.
	check(RunState.release(apple) != null, "the bought apple can be sold back")
	check(RunState.shop_stock(grocer, apple) == 0, "selling back does not restock the shelf")

	grocer.stock[apple] = authored


# --- the restock clock ----------------------------------------------------------

## Every RESTOCK_INTERVAL_DAYS town days, one unit of each depleted item comes back.
func _test_restock_clock() -> void:
	RunState.reset()
	var grocer := RunState.find_shop("grocer")
	var apple := grocer.find("Apple")
	var authored := grocer.stock[apple]
	grocer.stock[apple] = 3
	RunState.take_shop_stock(grocer, apple)
	RunState.take_shop_stock(grocer, apple)
	RunState.take_shop_stock(grocer, apple)
	check(RunState.shop_stock(grocer, apple) == 0, "the apple shelf starts this test bare")
	check(RunState.days_until_restock() == RunState.RESTOCK_INTERVAL_DAYS,
		"a fresh run is a full interval from its first restock")

	for day in RunState.RESTOCK_INTERVAL_DAYS - 1:
		RunState.spend_day()
		check(RunState.shop_stock(grocer, apple) == 0,
			"day %d of the interval restocks nothing" % (day + 1))
		check(RunState.days_until_restock() == RunState.RESTOCK_INTERVAL_DAYS - (day + 1),
			"the countdown tracks the days spent")

	RunState.spend_day()
	check(RunState.shop_stock(grocer, apple) == 1,
		"day %d — the interval's last — puts one apple back, got %d"
		% [RunState.RESTOCK_INTERVAL_DAYS, RunState.shop_stock(grocer, apple)])
	check(RunState.days_until_restock() == RunState.RESTOCK_INTERVAL_DAYS,
		"the countdown starts over after a restock")

	# And it keeps ticking: another interval, another single unit.
	for _day in RunState.RESTOCK_INTERVAL_DAYS:
		RunState.spend_day()
	check(RunState.shop_stock(grocer, apple) == 2, "the next interval adds one more, got %d"
		% RunState.shop_stock(grocer, apple))

	grocer.stock[apple] = authored


## Restocking stops at the authored max — a shelf never overfills, and every shop
## in town is restocked, not just the one that was shopped at.
func _test_restock_caps_at_max() -> void:
	RunState.reset()
	var grocer := RunState.find_shop("grocer")
	var smith := RunState.find_shop("blacksmith")
	var apple := grocer.find("Apple")
	var sword := smith.find("sword")
	RunState.take_shop_stock(grocer, apple)
	RunState.take_shop_stock(smith, sword)

	for _day in RunState.RESTOCK_INTERVAL_DAYS * 3:
		RunState.spend_day()
	check(RunState.shop_stock(grocer, apple) == grocer.max_qty(apple),
		"the grocer's shelf refills to max and stops")
	check(RunState.shop_stock(smith, sword) == smith.max_qty(sword),
		"a restock reaches every shop, not just the one bought from")


## Nothing about a shelf resets between gathers: only the clock puts stock back.
func _test_persists_across_gathers() -> void:
	RunState.reset()
	var smith := RunState.find_shop("blacksmith")
	var sword := smith.find("sword")
	RunState.take_shop_stock(smith, sword)
	# Two days in town — a whole short gather — is short of an interval.
	RunState.spend_day()
	RunState.spend_day()
	check(RunState.shop_stock(smith, sword) == 0,
		"a sold-out sword is still sold out when the next gather opens")


func _test_save_round_trip() -> void:
	RunState.reset()
	var grocer := RunState.find_shop("grocer")
	var apple := grocer.find("Apple")
	var authored := grocer.stock[apple]
	grocer.stock[apple] = 3
	RunState.take_shop_stock(grocer, apple)
	RunState.spend_day()

	var data := RunState.to_dict()
	RunState.reset()
	check(RunState.shop_stock(grocer, apple) == 3, "reset put the shelves back to full")

	RunState.from_dict(data)
	check(RunState.shop_stock(grocer, apple) == 2, "the depleted shelf survived the save, got %d"
		% RunState.shop_stock(grocer, apple))
	check(RunState.days_until_restock() == RunState.RESTOCK_INTERVAL_DAYS - 1,
		"the restock countdown survived the save")

	# A max QTY tuned down below a saved count clamps rather than over-stocking.
	grocer.stock[apple] = 1
	RunState.from_dict(data)
	check(RunState.shop_stock(grocer, apple) == 1,
		"a saved count above the current max QTY clamps down, got %d"
		% RunState.shop_stock(grocer, apple))

	# A shelf saved for an item the shop no longer sells is dropped, not carried.
	var stale := {"shop_stock": {"grocer": {"not_an_item": 0}, "no_such_shop": {"apple": 0}}}
	RunState.from_dict(stale)
	check(RunState.shop_stock(grocer, apple) == 1, "a save naming gone shops and items still loads")

	grocer.stock[apple] = authored


# --- the leatherworker ----------------------------------------------------------

## The bag upgrade is his alone, and it is gated twice over: at most one a day, and
## at most one per quest. The two gates are independent, so both get their own check
## — a new day with no quest finished is still refused, and vice versa.
func _test_leatherworker() -> void:
	RunState.reset()
	var leather := RunState.find_shop("leatherworker")
	check(leather != null, "the leatherworker is in town")
	check(leather.sells_bag_upgrade, "and he is the shop flagged for bag upgrades")
	for shop in RunState.SHOPS:
		if shop != leather:
			check(not shop.sells_bag_upgrade, "%s does not sell bag upgrades" % shop.id)

	# The ladder's prices, read off the constant rather than written out again.
	check(RunState.BAG_UPGRADE_COSTS.size() == RunState.BAG_SIZES.size() - 1,
		"there is one authored price per rung of the ladder")

	RunState.add_gold(1000)
	check(RunState.bag_upgrade_available(), "a fresh run finds an upgrade on the bench")
	check(RunState.upgrade_bag(), "the first upgrade is bought")
	check(not RunState.bag_upgrade_available(), "the bench is bare straight after a purchase")

	# A finished quest restocks the bench — but not on the same day it was bought.
	RunState.register_result(null, false)
	check(not RunState.bag_upgrade_available(),
		"a restocked bench still refuses a second upgrade on the same day")
	check(not RunState.upgrade_bag(), "and the purchase itself is refused")
	var tier_before := RunState.bag_tier
	RunState.spend_day()
	check(RunState.bag_upgrade_available(), "the next day, with the bench restocked, it's on offer")
	check(RunState.upgrade_bag(), "and can be bought")
	check(RunState.bag_tier == tier_before + 1, "the second upgrade moved the tier")

	# The other way round: days pass, but no quest finishes, so the bench stays bare.
	RunState.spend_day()
	RunState.spend_day()
	check(not RunState.bag_upgrade_available(),
		"days alone don't restock the bench — only a finished quest does")
	check(RunState.bag_upgrade_blocked_reason() != "", "and the shop has a line explaining why")

	# Both gates survive a save.
	var data := RunState.to_dict()
	RunState.reset()
	check(RunState.bag_upgrade_available(), "reset puts an upgrade back on the bench")
	RunState.from_dict(data)
	check(not RunState.bag_upgrade_available(), "the bare bench survived the save")
	RunState.register_result(null, false)
	check(RunState.bag_upgrade_available(), "and a quest after the load restocks it")


# --- the road's buy path --------------------------------------------------------

## End to end through the real road scene: a buy takes stock *and* gold, an
## unaffordable buy takes neither, and a bare shelf refuses.
func _test_road_buys() -> void:
	RunState.reset()
	var road: RoadScene = ROAD.instantiate()
	add_child(road)
	await get_tree().process_frame

	var grocer := RunState.find_shop("grocer")
	var apple := grocer.find("Apple")
	var authored := grocer.stock[apple]
	grocer.stock[apple] = 2
	road.begin(2, [])
	road._enter_shop(grocer)

	var gold_before := RunState.gold
	var owned_before := RunState.inventory.size()
	road._on_buy(apple)
	check(RunState.gold == gold_before - apple.buy_price, "buying spends the item's price")
	check(RunState.inventory.size() == owned_before + 1, "buying adds a copy to the inventory")
	check(RunState.shop_stock(grocer, apple) == 1, "buying takes one off the shelf")

	# Second copy of the same item in one visit — the old three-per-shop cap is gone.
	road._on_buy(apple)
	check(RunState.inventory.size() == owned_before + 2, "a second copy of the same item is allowed")
	check(RunState.shop_stock(grocer, apple) == 0, "that empties the shelf")

	# Bare shelf: refused, and the purse is untouched.
	var settled := RunState.gold
	road._on_buy(apple)
	check(RunState.gold == settled, "a buy from a bare shelf spends nothing")
	check(RunState.inventory.size() == owned_before + 2, "and adds nothing")

	# Broke: the shelf keeps its stock.
	RunState.spend_gold(RunState.gold)
	var bread := grocer.find("bread")
	var bread_before := RunState.shop_stock(grocer, bread)
	road._on_buy(bread)
	check(RunState.shop_stock(grocer, bread) == bread_before,
		"a buy that can't be afforded leaves the shelf alone")

	grocer.stock[apple] = authored
	# Freed outright rather than queued: the harness quits before the frame end, and
	# a still-queued node is what leaves "resources still in use at exit" behind.
	remove_child(road)
	road.free()


## Sell then Buy back in one visit: gold nets zero and the same copy returns.
func _test_buyback() -> void:
	RunState.reset()
	var road: RoadScene = ROAD.instantiate()
	add_child(road)
	await get_tree().process_frame

	var grocer := RunState.find_shop("grocer")
	road.begin(1, [])
	road._enter_shop(grocer)

	var apple := _owned(_id("apple"))
	check(apple != null, "starter pack has an apple to sell")
	var gold_before := RunState.gold
	var durability_before := apple.durability
	road._on_sell(apple)
	check(not RunState.inventory.has(apple), "selling removes the copy from the pack")
	check(RunState.gold == gold_before + apple.sell_price(), "selling pays the sell price")
	check(road._sold_this_visit.has(apple), "the sale is remembered for buy back")

	road._on_buyback(apple)
	check(RunState.inventory.has(apple), "buy back restores the same copy")
	check(apple.durability == durability_before, "buy back keeps the copy's durability")
	check(RunState.gold == gold_before, "buy back costs exactly what the sale paid")
	check(road._sold_this_visit.is_empty(), "buy back clears that sale from the visit list")

	remove_child(road)
	road.free()


## End to end through the real road scene: the leatherworker's Buy tab moves the bag
## tier and the purse, and refuses once his bench is bare.
func _test_road_bag_upgrade() -> void:
	RunState.reset()
	var road: RoadScene = ROAD.instantiate()
	add_child(road)
	await get_tree().process_frame

	road.begin(3, [])
	road._enter_shop(RunState.find_shop("leatherworker"))

	var gold_before := RunState.gold
	var cost := RunState.bag_upgrade_cost()
	var cols_before := RunState.bag_cols()
	road._on_upgrade_bag()
	check(RunState.gold == gold_before - cost, "the upgrade spends its price")
	check(RunState.bag_cols() == cols_before + 1, "and the bag grows a cell each way")

	# Bare bench: pressing again changes nothing, and the day is not spent either way.
	var settled := RunState.gold
	road._on_upgrade_bag()
	check(RunState.gold == settled, "a second upgrade the same day spends nothing")
	check(RunState.bag_cols() == cols_before + 1, "and leaves the bag alone")

	# Broke: the tier stays put even with the bench restocked and a new day open.
	RunState.register_result(null, false)
	RunState.spend_day()
	RunState.spend_gold(RunState.gold)
	var tier_before := RunState.bag_tier
	road._on_upgrade_bag()
	check(RunState.bag_tier == tier_before, "an upgrade that can't be afforded is refused")

	remove_child(road)
	road.free()


func _owned(id: String) -> ItemData:
	for item in RunState.inventory:
		if item != null and item.id == id:
			return item
	return null


## The id an item file actually declares. Worth going through rather than writing
## the literal: apple.tres is authored as "Apple" while every other item is
## lowercase, so these tests keep working whichever way that gets settled.
func _id(file: String) -> String:
	return (load("res://data/items/%s.tres" % file) as ItemData).id


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)
