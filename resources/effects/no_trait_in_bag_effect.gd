class_name NoTraitInBagEffect
extends ItemEffect

## "Don't pack me *with* X." If anything else on the board carries any of
## `trait_names`, this item loses `penalty` durability at send-off — however far away
## it sits. The sealed parcel that mustn't travel with anything sharp; the tonic that
## mustn't travel with anything that sparks.
##
## The whole-bag counterpart to NoAdjacentTraitEffect: that one is a *placement*
## problem the player solves by moving things apart, this one is a *packing* problem
## they solve by leaving something behind. That makes it the natural shape for a quest
## requirement — "deliver this, and take nothing sharp" is a rule about the bag, not
## about a corner of it — so the errand is authored as an item the quest lends (see
## QuestData.quest_items) rather than as a new kind of quest.
##
## Docks once, no matter how many offenders are aboard: the player is being told off
## for a mistake, not for a quantity of it (same reasoning as NoAdjacentTraitEffect).

## The traits that spoil this item from anywhere in the bag, from the canonical
## vocabulary (see the Traits autoload / TraitRegistry) — e.g. ["sharp"]. Anything
## else packed carrying any one of these triggers the penalty.
@export var trait_names: Array[String] = []


func evaluate(item: ItemData, layout: PackLayout) -> EffectOutcome:
	var outcome := EffectOutcome.new()
	# An unpacked item breaks no rule: left in the tray it never met the offender.
	if trait_names.is_empty() or not layout.contains(item):
		return outcome
	for other in layout.packed_items():
		if other == item:
			continue
		for trait_name in trait_names:
			if other.traits.has(trait_name):
				outcome.active = true
				outcome.durability_delta = -penalty
				outcome.line = "%s is packed with %s, which is %s! (−%d durability)" \
					% [name_of(item), name_of(other), trait_name, penalty]
				return outcome
	return outcome


func describe() -> String:
	if trait_names.is_empty():
		return ""
	return "Pack nothing %s anywhere in the bag with this! (−%d durability)." \
		% [", ".join(trait_names), penalty]
