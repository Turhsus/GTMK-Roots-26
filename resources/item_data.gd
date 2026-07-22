class_name ItemData
extends Resource

## One packable item. Authored as a .tres in res://data/items/ so items can be
## added or tuned without touching code.

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
@export var attack: int = 0
@export var defense: int = 0

@export_group("Narrative")
## Hooks for narrative conditions, e.g. ["light", "food", "fragile"].
@export var tags: Array[String] = []
## One-line tooltip text.
@export var flavor: String = ""


## Stat contributions keyed the same way as GameState.STAT_KEYS.
func get_stats() -> Dictionary:
	return {
		"food": food,
		"health": health,
		"attack": attack,
		"defense": defense,
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
