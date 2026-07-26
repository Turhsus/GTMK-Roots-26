class_name NoRotationEffect
extends ItemEffect

## "This way up." At send-off, if the item was packed upside down (turned a half
## turn, rotation step 2), it loses `penalty` durability — for anything that spills or
## settles wrong when inverted. Sideways (a quarter turn) is fine; only 180° bites.

@export var rotate = 0


func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	if layout.rotation_of(item) == rotate:
		item.durability -= penalty


func describe() -> String:
	return "Don't rotate it %d times! (−%d durability)." % [rotate, penalty]


func get_violation_message(item: ItemData, layout: PackLayout) -> String:
	if layout.rotation_of(item) == rotate:
		var rotation_name := "rotated" if rotate != 2 else "packed upside down"
		return "%s was %s!" % [item.display_name, rotation_name]
	return ""
