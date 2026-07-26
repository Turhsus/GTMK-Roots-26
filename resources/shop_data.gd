class_name ShopData
extends Resource

## One town shop the player visits during the gather phase. Authored as a .tres in
## res://data/shops/ so shops can be re-themed or re-stocked without touching code.
##
## A shop only defines what it *sells* — its themed stock, buyable with gold. The
## player can sell any owned item at any shop (see ShopScene), so selling isn't
## tied to a shop's theme and lives on the item's sell_price, not here.
##
## The shelves are a map: item -> how many of it the shop holds *when full*. What is
## on the shelf right now is deliberately not here — this resource is shared and
## stays stateless, so the live counts (and the restocking that refills them) belong
## to RunState. See RunState.shop_stock / take_shop_stock.
##
## Background art is by convention, not authored here: ShopScene looks for
## res://assets/backgrounds/shop_<id>.png and shows it when it exists.

## Max QTY for an item whose authored quantity is missing or non-positive — the base
## every shelf starts from. Raise a single item above it by giving that item its own
## number in `stock`; change this to move the floor for every shop at once.
const DEFAULT_MAX_QTY := 1

## Stable unique key, e.g. "grocer".
@export var id: String = ""
@export var display_name: String = ""
## One-line sign flavor shown when the shop is open.
@export_multiline var blurb: String = ""

## The shelves: each item on sale mapped to its max QTY — how many the shop stocks
## when full. Items show in authored order (a Dictionary keeps insertion order), and
## each is bought at the item's own buy_price. Leave a quantity at 0 to take
## DEFAULT_MAX_QTY.
@export var stock: Dictionary[ItemData, int] = {}


## The items on the shelves, in authored order. Nulls (an entry cleared in the
## inspector) are skipped so callers never have to guard for them.
func items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in stock:
		if item != null:
			result.append(item)
	return result


## How many of `item` this shop holds when fully stocked, falling back to
## DEFAULT_MAX_QTY. Zero for an item this shop doesn't sell at all.
func max_qty(item: ItemData) -> int:
	if item == null or not stock.has(item):
		return 0
	var authored := stock[item]
	return authored if authored > 0 else DEFAULT_MAX_QTY


## The stocked item with this id, or null if the shop doesn't sell it. Saves name
## items by id (see RunState.to_dict), so restoring a shelf comes back through here.
func find(item_id: String) -> ItemData:
	for item in items():
		if item.id == item_id:
			return item
	return null
