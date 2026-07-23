@tool
class_name ItemData
extends Resource

## One packable item. Authored as a .tres in res://data/items/ so items can be
## added or tuned without touching code.
##
## `@tool` so the inspector can turn the `traits` array into a dropdown of the
## canonical vocabulary (see _validate_property) instead of a free-text field.

## The single trait master list, preloaded so the inspector dropdown can read it.
## Same resource the Traits autoload exposes at runtime, so there's one source.
const _REGISTRY = preload("res://data/trait_registry.tres")

## Stable unique key, e.g. "bread". Also the expected art filename (bread.png).
@export var id: String = ""
@export var display_name: String = ""

## Occupied cell offsets from the shape's top-left, e.g. [(0,0),(1,0)] for a 2x1.
@export var shape: Array[Vector2i] = [Vector2i.ZERO]

## Sprite sized to the shape's bounding box (see MVP.md 8.1). Placeholder until
## real art lands; swapping art is a no-code change.
@export var icon: Texture2D

@export_group("Stats")
@export var food: int = 0
@export var health: int = 0
@export var combat: int = 0
@export var utility: int = 0

@export_group("Narrative")
## This item's traits, e.g. ["light", "food", "fragile"]. Doubles as the narrative
## hooks the playout reads and, going forward, the vocabulary quest requirements
## match against. Author them from the canonical list in TraitRegistry.item_traits
## (see the Traits autoload) so spellings stay consistent across items.
@export var traits: Array[String] = []
## One-line tooltip text.
@export var flavor: String = ""

@export_group("Durability")
## How many quests a fresh copy of this item survives. Each send-off wears every
## packed item by one; a copy that reaches 0 is worn out and thrown away. Most
## items are single-use (1); a few sturdy ones (the blanket) last several trips.
@export var max_durability: int = 1

## Trips left in *this* copy. Owned copies are duplicated per inventory slot (see
## make_owned_copy) so each wears independently of every other copy and of the
## shared preloaded template. Stays -1 on the template — only an owned copy sets it.
var durability: int = -1

@export_group("Economy")
## What this item costs to buy in a shop during the gather phase. The sell price
## is derived from it (half, see sell_price) so a bought item never fully refunds.
## 0 means the item isn't priced yet.
@export var buy_price: int = 0


## What a shop pays for this item: half the buy price, rounded down. Selling is
## always a loss against buying, so hoarding to resell never nets gold.
func sell_price() -> int:
	@warning_ignore("integer_division")
	return buy_price / 2


## A fresh owned copy for the player's inventory: its own duplicated resource with
## full durability, so its wear ticks down independently of every other copy (and
## never touches the shared preloaded template or the shop's stock). RunState
## stocks the starter pack and every purchase through this.
func make_owned_copy() -> ItemData:
	var copy := duplicate() as ItemData
	copy.durability = max_durability
	return copy


## Inspector hook: render each element of the `traits` array as a dropdown of the
## registry's item traits, so authoring picks from the canonical list instead of
## typing (and mistyping) a name. Editing trait_registry.tres updates the choices.
func _validate_property(property: Dictionary) -> void:
	if property.name == "traits":
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:%s" % [TYPE_STRING, PROPERTY_HINT_ENUM,
			",".join(_REGISTRY.item_traits.keys())]


## Stat contributions keyed the same way as GameState.STAT_KEYS.
func get_stats() -> Dictionary:
	return {
		"food": food,
		"health": health,
		"combat": combat,
		"utility": utility,
	}


## Size of the shape's bounding box, in cells.
func get_size() -> Vector2i:
	return get_shape_size(shape)


## Rotates shape offsets by `steps` * 90 degrees clockwise and re-normalizes so
## the minimum offset is (0,0). Grid math lives here so BagGrid and
## DraggableItem agree on what a rotated item occupies.
static func rotate_shape(offsets: Array[Vector2i], steps: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = offsets.duplicate()
	for _i in range(posmod(steps, 4)):
		var turned: Array[Vector2i] = []
		for offset in result:
			turned.append(Vector2i(-offset.y, offset.x))
		result = turned
	return normalize_shape(result)


## Shifts offsets so the top-left of the bounding box sits at (0,0).
static func normalize_shape(offsets: Array[Vector2i]) -> Array[Vector2i]:
	if offsets.is_empty():
		return []
	var min_x: int = offsets[0].x
	var min_y: int = offsets[0].y
	for offset in offsets:
		min_x = mini(min_x, offset.x)
		min_y = mini(min_y, offset.y)
	var shifted: Array[Vector2i] = []
	for offset in offsets:
		shifted.append(offset - Vector2i(min_x, min_y))
	return shifted


static func get_shape_size(offsets: Array[Vector2i]) -> Vector2i:
	if offsets.is_empty():
		return Vector2i.ZERO
	var max_x: int = offsets[0].x
	var max_y: int = offsets[0].y
	for offset in offsets:
		max_x = maxi(max_x, offset.x)
		max_y = maxi(max_y, offset.y)
	return Vector2i(max_x + 1, max_y + 1)
