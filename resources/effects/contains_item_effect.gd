class_name ContainsItemEffect
extends ItemEffect

## "There's a space in here — put something in it." The rule for a hollow item: the
## helmet's crown, the boot's opening. Anything packed *inside* that hollow (see
## PackLayout.items_within — fully inside, not just poking into it) is affected by the
## thing holding it: cradled in the helmet, warmed in the boot.
##
## Both halves are authored per item, so one class covers both flavours of nesting:
##   durability_delta -> handed to the nested item at send-off (± , it can go either way)
##   *_bonus          -> a live stat bonus while the hollow is filled
## Leave one at zero and the rule is purely the other, exactly as elsewhere.
##
## This is the one rule whose consequence lands on a *different* item than the one
## carrying it, which is why it is also the one place resolve_send_off is overridden
## rather than evaluate() alone. That stays inside the contract: evaluate() is still
## pure, still the single source of the warning line and the number, and the override
## only redirects who the delta is added to. (Contrast ProtectAdjacentItemEffect, which
## wants the same reach for a *neighbour* and can't have it — shielding a neighbour
## means suppressing another rule, which the resolve loop has no way to express.
## Handing another item durability needs no such coordination.)
##
## One consequence worth knowing when authoring: the outcome belongs to the container,
## so the live amber tint throbs on the *helmet* when the thing inside it is being
## docked. The line names both items, so the hover still reads correctly — but keep a
## penalising hollow's wording explicit about who is paying.

## Which nested items this hollow reacts to, from the canonical vocabulary (see the
## Traits autoload / TraitRegistry). Leave empty for "anything that fits inside".
@export var trait_names: Array[String] = []

@export_group("Nested item")
## Durability handed to (positive) or taken from (negative) each nested item at
## send-off. Signed rather than reusing the base `penalty`, because a hollow can be
## either kind of place to be — cradled or crushed — and `penalty` is a magnitude that
## every other rule negates. `penalty` is unused by this rule.
@export var durability_delta: int = 0

@export_group("Bonus")
## Stat bonus while the hollow is filled, same keys as ItemData's own stat block. Live
## only, summed board-wide like any other stat delta; it never survives send-off.
@export var food_bonus: int = 0
@export var health_bonus: int = 0
@export var combat_bonus: int = 0
@export var utility_bonus: int = 0


func evaluate(item: ItemData, layout: PackLayout) -> EffectOutcome:
	var outcome := EffectOutcome.new()
	var delta := _bonus_delta()
	# A hollow authored with nothing to give is dormant rather than a rule that fires
	# and does nothing.
	if durability_delta == 0 and delta.is_empty():
		return outcome
	var nested := _nested(item, layout)
	if nested.is_empty():
		return outcome
	outcome.active = true
	outcome.durability_delta = durability_delta
	outcome.stat_delta = delta
	outcome.line = _line(item, nested)
	return outcome


## Applies the durability half to the *nested* items instead of the container — the
## one deviation from the base applier, and the whole point of this rule. The verdict
## still comes from the pure evaluate() above, so the number applied is exactly the
## one the live warning showed.
func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	if durability_delta == 0 or not evaluate(item, layout).active:
		return
	for nested in _nested(item, layout):
		if durability_delta > 0:
			# An already-destroyed copy is past saving — don't resurrect it with a
			# bonus — and a cushioned item can only ever be given back the trip
			# send-off just took, never pushed past new (same clamp the road's repair
			# uses, and what keeps the info panel's durability bar honest).
			if nested.durability <= 0:
				continue
			nested.durability = mini(nested.durability + durability_delta, nested.max_durability)
		else:
			nested.durability += durability_delta


func describe() -> String:
	var what := "Anything" if trait_names.is_empty() else "%s items" % ", ".join(trait_names)
	var parts: Array[String] = []
	if durability_delta < 0:
		parts.append("takes a beating (−%d durability)" % -durability_delta)
	elif durability_delta > 0:
		parts.append("is cushioned (+%d durability)" % durability_delta)
	var bonus := _bonus_text()
	if bonus != "":
		parts.append("is worth %s" % bonus)
	if parts.is_empty():
		return ""
	return "%s packed inside it %s." % [what, " and ".join(parts)]


## Why the rule is firing on *this* board, naming what is inside and what it costs
## them — the container is named too, since the tint lands on the container.
func _line(item: ItemData, nested: Array[ItemData]) -> String:
	var names: Array[String] = []
	for other in nested:
		names.append(name_of(other))
	var who := ", ".join(names)
	if durability_delta < 0:
		return "%s is squashed inside %s! (−%d durability)" \
			% [who, name_of(item), -durability_delta]
	if durability_delta > 0:
		return "%s is cushioned inside %s. (+%d durability)" \
			% [who, name_of(item), durability_delta]
	return "%s is tucked inside %s. (%s)" % [who, name_of(item), _bonus_text()]


## The items nested in this one that the rule actually applies to.
func _nested(item: ItemData, layout: PackLayout) -> Array[ItemData]:
	var found: Array[ItemData] = []
	for other in layout.items_within(item):
		if trait_names.is_empty():
			found.append(other)
			continue
		for trait_name in trait_names:
			if other.traits.has(trait_name):
				found.append(other)
				break
	return found


## The non-zero bonuses, keyed as GameState.STAT_KEYS.
func _bonus_delta() -> Dictionary:
	var delta: Dictionary = {}
	for entry in _bonus_entries():
		if entry[1] != 0:
			delta[entry[0]] = entry[1]
	return delta


## "+2 food, +1 health", or "" when nothing is configured.
func _bonus_text() -> String:
	var parts: Array[String] = []
	for entry in _bonus_entries():
		if entry[1] != 0:
			parts.append("%+d %s" % [entry[1], entry[0]])
	return ", ".join(parts)


func _bonus_entries() -> Array:
	return [["food", food_bonus], ["health", health_bonus],
		["combat", combat_bonus], ["utility", utility_bonus]]
