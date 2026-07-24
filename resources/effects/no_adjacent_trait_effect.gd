class_name NoAdjacentTraitEffect
extends ItemEffect

## "Don't pack me next to X." At send-off, if any item sharing a cell wall with this
## one carries `trait_name`, the item loses `penalty` durability — once, however many
## bad neighbours it ended up against. The classic fragile-next-to-fire rule.

## The neighbouring trait that spoils this item, from the canonical vocabulary (see
## the Traits autoload / TraitRegistry) — e.g. "fire", "water".
@export var trait_name: String = ""


func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	if trait_name.is_empty():
		return
	for other in layout.neighbours_of(item):
		if other.traits.has(trait_name):
			item.durability -= penalty
			return


func describe() -> String:
	if trait_name.is_empty():
		return ""
	return "Don't pack it next to %s items (−%d durability)." % [trait_name, penalty]
