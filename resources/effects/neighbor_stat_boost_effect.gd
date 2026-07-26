class_name NeighborStatBoostEffect
extends ItemEffect

## "Packed next to a heat source, this pulls its weight harder." This item grants a
## stat bonus for as long as it sits next to a neighbour carrying any of `trait_names`.
##
## Live only: it fills the outcome's stat_delta and leaves durability_delta at zero, so
## ItemEffect.live_bonus reads it every time the board changes while resolve_send_off
## has nothing to apply. Move the item away and the bonus is gone next recompute; it
## never survives send-off. `penalty` is unused here — this rule costs nothing.
##
## It is a boon, so it shows green in the info panel and never reaches the send-off
## mistakes modal (the base get_violation_message filters on a *negative* delta).

## The neighbouring traits that wake this item up, from the canonical vocabulary
## (see the Traits autoload / TraitRegistry) — e.g. ["fire"] for a heat source. A
## neighbour carrying any one of these grants the bonus.
@export var trait_names: Array[String] = []

## Which edge to inspect: "up", "down", "left" or "right". Leave "all" to check
## every side.
@export_enum("all", "up", "down", "left", "right") var direction: String = "all"

## The bonus per stat while triggered, same keys as ItemData's own stat block — e.g.
## food_bonus = 4, health_bonus = 1 for "warmed by the fire: +4 food, +1 health".
@export_group("Bonus")
@export var food_bonus: int = 0
@export var health_bonus: int = 0
@export var combat_bonus: int = 0
@export var utility_bonus: int = 0


func evaluate(item: ItemData, layout: PackLayout) -> EffectOutcome:
	var outcome := EffectOutcome.new()
	if trait_names.is_empty():
		return outcome
	var source := _trigger(item, layout)
	if source == null:
		return outcome
	var delta: Dictionary = {}
	for entry in _bonus_entries():
		if entry[1] != 0:
			delta[entry[0]] = entry[1]
	# A rule configured with every bonus at zero has nothing to grant, so it stays
	# dormant rather than reporting itself as a firing boon that does nothing.
	if delta.is_empty():
		return outcome
	outcome.active = true
	outcome.stat_delta = delta
	outcome.line = "%s while packed next to %s." % [_bonus_text(), name_of(source)]
	return outcome


func describe() -> String:
	if trait_names.is_empty():
		return ""
	var text := _bonus_text()
	if text == "":
		return ""
	return "%s while packed next to %s." % [text, ", ".join(trait_names)]


## "+4 food, +1 health", or "" when nothing is configured.
func _bonus_text() -> String:
	var parts: Array[String] = []
	for entry in _bonus_entries():
		if entry[1] != 0:
			parts.append("+%d %s" % [entry[1], entry[0]])
	return ", ".join(parts)


func _bonus_entries() -> Array:
	return [["food", food_bonus], ["health", health_bonus],
		["combat", combat_bonus], ["utility", utility_bonus]]


## The neighbour granting the bonus, or null when none does — returned rather than a
## bool so the warning line can name what is helping.
func _trigger(item: ItemData, layout: PackLayout) -> ItemData:
	for other in layout.neighbours_of(item, _directions()):
		for trait_name in trait_names:
			if other.traits.has(trait_name):
				return other
	return null


func _directions() -> Array[Vector2i]:
	match direction:
		"up":
			return [Vector2i.UP]
		"down":
			return [Vector2i.DOWN]
		"left":
			return [Vector2i.LEFT]
		"right":
			return [Vector2i.RIGHT]
		_:
			return [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
