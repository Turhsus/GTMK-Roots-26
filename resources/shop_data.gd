class_name ShopData
extends Resource

## One town shop the player visits during the gather phase. Authored as a .tres in
## res://data/shops/ so shops can be re-themed or re-stocked without touching code.
##
## A shop only defines what it *sells* — its themed stock, buyable with gold. The
## player can sell any owned item at any shop (see ShopScene), so selling isn't
## tied to a shop's theme and lives on the item's sell_price, not here.
##
## Background art is by convention, not authored here: ShopScene looks for
## res://assets/backgrounds/shop_<id>.png and shows it when it exists.

## Stable unique key, e.g. "grocer".
@export var id: String = ""
@export var display_name: String = ""
## One-line sign flavor shown when the shop is open.
@export_multiline var blurb: String = ""

## The items on the shelves, bought at each item's buy_price.
@export var stock: Array[ItemData] = []

## How many items the shop will sell per gather phase — any mix from the shelves.
## Once the player has bought this many the shop is sold out; every shop restocks
## when the next gather opens. RoadScene tracks the counts (this resource is
## shared and stays stateless).
@export var stock_limit: int = 3
