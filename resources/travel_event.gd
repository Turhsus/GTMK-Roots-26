class_name TravelEvent
extends Resource

## A short vignette that can fire on the way to a town shop during gather.
## Authored as .tres under res://data/travel_events/.

## Stable unique key, e.g. "found_coin".
@export var id: String = ""
@export var title: String = ""
@export_multiline var text: String = ""

## Probability this event is offered when its shop filter matches (0.0–1.0).
@export_range(0.0, 1.0, 0.01) var chance: float = 0.1

## Shop ids this event can fire for (e.g. ["grocer"]). Empty = any shop.
@export var shop_ids: Array[String] = []

## Gold granted when the event resolves (before the shop opens).
@export var gold_reward: int = 0


func matches_shop(shop: ShopData) -> bool:
	return shop_ids.is_empty() or shop.id in shop_ids
