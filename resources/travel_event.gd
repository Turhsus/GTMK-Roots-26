class_name TravelEvent
extends Resource

## A short vignette that can fire when the road into town loads at the start of
## a gather — at most one per gather, before any shop is chosen (see
## RoadScene._roll_travel_event). Authored as .tres under res://data/travel_events/.

## Stable unique key, e.g. "found_coin".
@export var id: String = ""
@export var title: String = ""
@export_multiline var text: String = ""

## Probability this event fires when the road loads (0.0–1.0).
@export_range(0.0, 1.0, 0.01) var chance: float = 1

## Gold granted when the event resolves (before the day's shopping).
@export var gold_reward: int = 0
