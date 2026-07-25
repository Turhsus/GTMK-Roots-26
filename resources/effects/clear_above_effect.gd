class_name ClearAboveEffect
extends ItemEffect

## "Don't crush me." At send-off, if any of the `rows` cells directly above this
## item's footprint are filled, it loses `penalty` durability — the "needs air" rule
## for something delicate packed under a heavier load.

## How many rows directly above the item must stay clear.
@export var rows: int = 1


func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	for cell in layout.cells_above(item, rows):
		if layout.is_filled(cell):
			item.durability -= penalty
			return


func describe() -> String:
	var plural := "" if rows == 1 else "s"
	return "Keep %d square%s above it clear, otherwise the item will be crushed! (−%d durability)." % [rows, plural, penalty]
