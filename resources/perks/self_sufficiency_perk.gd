class_name SelfSufficiencyPerk
extends PerkData

## Self-Sufficiency: the child has learned to correct minor mistakes in the pack, so a
## bad placement sometimes costs nothing at all — he notices the crushed cheese or the
## upside-down flask on the road and sets it right before it matters.
##
## Runs through the ordinary PerkData.modify_item hook at send-off, which is *after*
## RunState.resolve_item_effects has already docked the item (see the send-off order in
## main._on_sent_off) — so forgiving a mistake is simply handing that durability back,
## the same shape as CraftyPerk undoing a point of trip wear. Nothing in the effect
## pipeline knows this perk exists: it re-asks the item's own effects what they did by
## calling the pure ItemEffect.evaluate against the same board snapshot, which is
## exactly what that purity is for.
##
## Perks are 1:1 with their subclass now, so this perk's identity and its one tunable
## number live here rather than in a separate .tres — RunState builds one instance of
## this class at boot (see PERK_TYPES).

## Chance in [0, 1] that a single mistake is ignored.
const FORGIVE_CHANCE := 0.1


func _init() -> void:
	id = "self_sufficiency"
	title = "Self-Sufficiency"
	description = "Your little one has learned to correct minor mistakes in the pack. There is a 10% chance a packing mistake is ignored."
	# No trigger_stat: a bad pack costs durability rather than any one stat, so this
	# lesson is worth offering whatever fell short.
	trigger_stat = ""


## Each firing mistake on this item is rolled in turn until one is forgiven — at most
## one per item per send-off, so a single item can't shrug off a whole bad pack.
func modify_item(item: ItemData, layout: PackLayout = null) -> String:
	if item == null or layout == null:
		return ""
	for effect in item.effects:
		var outcome := effect.evaluate(item, layout)
		if not outcome.is_warning() or randf() >= FORGIVE_CHANCE:
			continue
		# durability_delta is the negative the effect already applied; give it back.
		item.durability -= outcome.durability_delta
		return "%s: %s — but your little one caught it and repacked before setting off." % [title, outcome.line]
	return ""
