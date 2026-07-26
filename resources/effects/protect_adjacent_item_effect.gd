class_name  ProtectAdjacentItemEffect
extends ItemEffect

@export var trait_names: Array[String] = []

func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	if trait_names.is_empty() or item.durability <= 0:
		return
	for adjacent in layout.neighbours_of(item):
		for target_trait in trait_names:
			if adjacent.traits.has(target_trait):
				## Ignore the effect of its negative traits
				## For now, I'll just add 1 to the durability, but ideally, this ignores the harmful effects on the item
				item.durability += penalty
				return

func describe() -> String:
	if trait_names.is_empty():
		return ""
	return "Protects its neighboring items with the %s trait! (+%d durability)." % [", ".join(trait_names), penalty]


func get_violation_message(_item: ItemData, _layout: PackLayout) -> String:
	# This is a beneficial effect, never a violation
	return ""
