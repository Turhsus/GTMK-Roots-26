class_name ShopData
extends Resource

## One town shop the player visits during the gather phase. Authored as a .tres in
## res://data/shops/ so shops can be re-themed or re-stocked without touching code.
##
## A shop only defines what it *sells* — its themed stock, buyable with gold. The
## player can sell any owned item at any shop (see TownScreen), so selling isn't
## tied to a shop's theme and lives on the item's sell_price, not here.

## Stable unique key, e.g. "grocer".
@export var id: String = ""
@export var display_name: String = ""
## One-line sign flavor shown when the shop is open.
@export_multiline var blurb: String = ""

## The items on the shelves, bought at each item's buy_price. Stock is unlimited:
## the player can buy any number of copies, gold permitting.
@export var stock: Array[ItemData] = []
