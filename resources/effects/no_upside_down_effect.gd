class_name NoUpsideDownEffect
extends ItemEffect

## "This way up." At send-off, if the item was packed upside down (turned a half
## turn, rotation step 2), it loses `penalty` durability — for anything that spills or
## settles wrong when inverted. Sideways (a quarter turn) is fine; only 180° bites.


func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	if layout.rotation_of(item) == 2:
		item.durability -= penalty


func describe() -> String:
	return "Don't pack it upside down (−%d durability)." % penalty
