class_name ProtectAdjacentItemEffect
extends ItemEffect

## "Packed around something delicate, this comes through better." When this item sits
## next to a neighbour carrying any of `trait_names`, it *gains* `penalty` durability
## at send-off. The blanket wrapped around the fragile things survives the trip.
##
## KNOWN GAP — the name and the intent don't match the mechanic. What this wants to do
## is shield its *neighbour* from that neighbour's own penalties; what it can do today
## is only mutate itself, because an effect's outcome applies to the item carrying it
## and nothing in the resolve loop lets one rule suppress another. Making it real needs
## a two-pass resolve (collect every outcome, apply suppressions, then apply the rest)
## and a `suppresses` field on EffectOutcome. Until then the description below states
## the behaviour that actually ships rather than the one intended.
##
## This is a boon, never a violation: the base get_violation_message() filters it out
## of the send-off mistakes modal because its durability_delta is positive.

@export var trait_names: Array[String] = []


func evaluate(item: ItemData, layout: PackLayout) -> EffectOutcome:
	var outcome := EffectOutcome.new()
	# An already-destroyed copy is past saving — don't resurrect it with a bonus.
	if trait_names.is_empty() or item.durability <= 0:
		return outcome
	for adjacent in layout.neighbours_of(item):
		for target_trait in trait_names:
			if adjacent.traits.has(target_trait):
				outcome.active = true
				outcome.durability_delta = penalty
				outcome.line = "%s is padded against %s. (+%d durability)" \
					% [name_of(item), name_of(adjacent), penalty]
				return outcome
	return outcome


func describe() -> String:
	if trait_names.is_empty():
		return ""
	return "Survives the trip better when packed next to %s items. (+%d durability)." \
		% [", ".join(trait_names), penalty]
