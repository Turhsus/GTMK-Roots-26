class_name NoAdjacentTraitEffect
extends ItemEffect

## "Don't pack me next to X." At send-off, if any item sharing a cell wall with this
## one carries any of `trait_names`, the item loses `penalty` durability — once, however
## many bad neighbours it ended up against. The classic fragile-next-to-fire rule.

## The neighbouring traits that spoil this item, from the canonical vocabulary (see
## the Traits autoload / TraitRegistry) — e.g. ["fire", "water"]. A neighbour carrying
## any one of these triggers the penalty.
@export var trait_names: Array[String] = []

## Which edge to inspect: "up", "down", "left" or "right". Only the neighbour across
## that edge is considered. Leave blank to check all four sides (the default).
@export_enum("all", "up", "down", "left", "right") var direction: String = "all"


func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	if trait_names.is_empty():
		return
	for other in layout.neighbours_of(item, _directions()):
		for trait_name in trait_names:
			if other.traits.has(trait_name):
				item.durability -= penalty
				return


func describe() -> String:
	if trait_names.is_empty():
		return ""
	var where := "above this item!" if direction == "up" \
		else "below this item! " if direction == "down" \
		else "to its left!" if direction == "left" \
		else "to its right!" if direction == "right" \
		else "next to it"
	return "Don't pack %s items %s (−%d durability)." % [", ".join(trait_names), where, penalty]


## The edge offset(s) matching `direction`, for PackLayout.neighbours_of. Board y grows
## downward, so "up" is -y (matching cells_above).
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
