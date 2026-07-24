class_name NoAdjacentTraitEffect
extends ItemEffect

## "Don't pack me next to X." At send-off, if any item sharing a cell wall with this
## one carries any of `trait_names`, the item loses `penalty` durability — once, however
## many bad neighbours it ended up against. The classic fragile-next-to-fire rule.

## The neighbouring traits that spoil this item, from the canonical vocabulary (see
## the Traits autoload / TraitRegistry) — e.g. ["fire", "water"]. A neighbour carrying
## any one of these triggers the penalty.
@export var trait_names: Array[String] = []


func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	if trait_names.is_empty():
		return
	for other in layout.neighbours_of(item):
		for trait_name in trait_names:
			if other.traits.has(trait_name):
				item.durability -= penalty
				return


func describe() -> String:
	if trait_names.is_empty():
		return ""
	return "Don't pack it next to %s items (−%d durability)." % [", ".join(trait_names), penalty]
