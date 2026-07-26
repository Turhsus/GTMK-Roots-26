class_name RequiresAdjacentTraitEffect
extends ItemEffect

## "Don't pack me on my own." Unless something sharing a cell wall with this item
## carries one of `trait_names`, it loses `penalty` durability at send-off — the
## bottle that needs bracing, the fledgling that needs something warm beside it.
##
## The mirror of NoAdjacentTraitEffect: that rule fires on a neighbour being there,
## this one on a neighbour being *missing*. Which means, unlike every other rule in
## this folder, it is firing the moment the item is placed and goes quiet only once
## the player solves it — so it reads as a requirement rather than as a mistake, and
## the quest that lends the item can state it as one in the brief.
##
## Being packed at all is what puts the item under the rule: still in the tray, it is
## dormant (see PackLayout.contains), never a standing violation on an empty board.

## The neighbouring traits that satisfy this item, from the canonical vocabulary (see
## the Traits autoload / TraitRegistry) — e.g. ["armor"] for something solid to brace
## against. Any one neighbour carrying any one of these is enough.
@export var trait_names: Array[String] = []


func evaluate(item: ItemData, layout: PackLayout) -> EffectOutcome:
	var outcome := EffectOutcome.new()
	if trait_names.is_empty() or not layout.contains(item):
		return outcome
	for other in layout.neighbours_of(item):
		for trait_name in trait_names:
			if other.traits.has(trait_name):
				return outcome
	outcome.active = true
	outcome.durability_delta = -penalty
	outcome.line = "%s has nothing %s packed against it! (−%d durability)" \
		% [name_of(item), _wanted(), penalty]
	return outcome


func describe() -> String:
	if trait_names.is_empty():
		return ""
	return "Pack something %s right next to this! (−%d durability)." % [_wanted(), penalty]


## "warm", or "warm or solid" — the traits read as a list of alternatives, since any
## one of them satisfies the rule.
func _wanted() -> String:
	return " or ".join(trait_names)
