class_name NeighborStatBoostEffect
extends ItemEffect

## "Packed next to a heat source, this pulls its weight harder." While packing, this
## item grants a stat bonus for as long as it sits next to a neighbour carrying any of
## `trait_names` — live only (see ItemEffect.live_bonus), gone the moment it's moved
## away and never docks durability or fires at send-off. `penalty` is unused here.

## The neighbouring traits that wake this item up, from the canonical vocabulary
## (see the Traits autoload / TraitRegistry) — e.g. ["fire"] for a heat source. A
## neighbour carrying any one of these grants the bonus.
@export var trait_names: Array[String] = []

## Which edge to inspect: "up", "down", "left" or "right". Leave "all" to check
## every side.
@export_enum("all", "up", "down", "left", "right") var direction: String = "all"

## The bonus per stat while triggered, same keys as ItemData's own stat block — e.g.
## food_bonus = 4, health_bonus = 1 for "warmed by the fire: +4 food, +1 health".
@export_group("Bonus")
@export var food_bonus: int = 0
@export var health_bonus: int = 0
@export var combat_bonus: int = 0
@export var utility_bonus: int = 0


func live_bonus(item: ItemData, layout: PackLayout) -> Dictionary:
	if trait_names.is_empty() or not _triggered(item, layout):
		return {}
	var delta: Dictionary = {}
	for entry in [["food", food_bonus], ["health", health_bonus],
			["combat", combat_bonus], ["utility", utility_bonus]]:
		if entry[1] != 0:
			delta[entry[0]] = entry[1]
	return delta


func describe() -> String:
	if trait_names.is_empty():
		return ""
	var parts: Array[String] = []
	for entry in [["food", food_bonus], ["health", health_bonus],
			["combat", combat_bonus], ["utility", utility_bonus]]:
		if entry[1] != 0:
			parts.append("+%d %s" % [entry[1], entry[0]])
	if parts.is_empty():
		return ""
	return "%s while packed next to %s." % [", ".join(parts), ", ".join(trait_names)]


func _triggered(item: ItemData, layout: PackLayout) -> bool:
	for other in layout.neighbours_of(item, _directions()):
		for trait_name in trait_names:
			if other.traits.has(trait_name):
				return true
	return false


func _directions() -> Array[Vector2i]:
	match direction:
		"up":
			return [Vector2i.UP]
		"down":
			return [Vector2i.DOWN]
		"left":
			return [Vector2i.LEFT]
		"right":
			return [Vector2i.RIGHT]
		_:
			return [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
