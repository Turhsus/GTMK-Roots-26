class_name ClearAboveEffect
extends ItemEffect

## "Don't crush me." If any of the `rows` cells directly above this item's footprint
## are filled, it loses `penalty` durability at send-off — the "needs air" rule for
## something delicate packed under a heavier load.
##
## Fires the moment the crushing item is placed: the amber warning while packing, the
## hover line, and the send-off penalty all come out of the one evaluate() below.
## Note that cells off the top of the board read as empty, so the top row of the bag
## is free crush-immunity — a quirk worth knowing when authoring a bag tier.

## How many rows directly above the item must stay clear.
@export var rows: int = 1


func evaluate(item: ItemData, layout: PackLayout) -> EffectOutcome:
	var outcome := EffectOutcome.new()
	for cell in layout.cells_above(item, rows):
		var crusher := layout.item_at(cell)
		if crusher == null:
			continue
		outcome.active = true
		outcome.durability_delta = -penalty
		outcome.line = "%s is crushed under %s! (−%d durability)" \
			% [name_of(item), name_of(crusher), penalty]
		return outcome
	return outcome


func describe() -> String:
	var plural := "" if rows == 1 else "s"
	return "Keep %d square%s above it clear, otherwise the item will be crushed! (−%d durability)." % [rows, plural, penalty]
