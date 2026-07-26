class_name NoRotationEffect
extends ItemEffect

## "This way up." If the item was packed at the turn named by `rotate`, it loses
## `penalty` durability at send-off — for anything that spills, settles wrong, or
## snags when it isn't the way round it wants to be.
##
## `rotate` is a rotation *step*, matching PackLayout.rotation_of: 0 upright, 1 a
## quarter turn, 2 upside down, 3 the other quarter turn. It is the turn that is
## FORBIDDEN, not the one that is required — so the spilling-wine rule is `rotate = 2`
## and leaving it at the default 0 penalises packing the item the right way up.

## The forbidden turn, as a rotation step (0-3). See the note above: this is the turn
## that costs durability.
@export_range(0, 3) var rotate: int = 0


func evaluate(item: ItemData, layout: PackLayout) -> EffectOutcome:
	var outcome := EffectOutcome.new()
	# rotation_of returns -1 for an item that isn't on the board, which can never
	# match a step, so an unplaced item is simply never in violation.
	if layout.rotation_of(item) != _forbidden_step():
		return outcome
	outcome.active = true
	outcome.durability_delta = -penalty
	outcome.line = "%s is packed %s! (−%d durability)" % [name_of(item), _turn_name(), penalty]
	return outcome


func describe() -> String:
	return "Don't pack it %s! (−%d durability)." % [_turn_name(), penalty]


func _forbidden_step() -> int:
	return posmod(rotate, 4)


## The forbidden turn in words. Quarter turns read the same either way round to a
## player — "on its side" — so both 1 and 3 use it.
func _turn_name() -> String:
	match _forbidden_step():
		0:
			return "upright"
		2:
			return "upside down"
		_:
			return "on its side"
