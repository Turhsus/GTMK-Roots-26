class_name ItemEffect
extends Resource

## Base class for a per-item placement rule, composed onto an ItemData as an entry in
## its `effects` array (authored inline in the item's .tres). This mirrors the perk
## pattern (see PerkData): a small library of subclasses, each overriding the hook
## below, so a genuinely new rule is a new *effect* subclass — never a new ItemData
## subclass. The item itself stays one class with many .tres instances.
##
## Subclasses override exactly one thing: evaluate(). It is *pure* — it reads the item
## and the board and returns an EffectOutcome describing what the rule would do,
## mutating nothing. Everything else here is a thin applier over it:
##
##   evaluate()              -> the verdict; safe to run any time, on any board
##     resolve_send_off()       applies the durability half, once, at send-off
##     live_bonus()             reads the stat half, continuously, while packing
##     get_violation_message()  reads the explanation for the send-off mistakes modal
##     (the warning UI)         reads `active` / `line` to tint and explain, live
##
## That purity is the whole point. A rule that can only be *applied* can only be felt
## after the bag is gone; because this one can also be *asked*, the same rule tints the
## item amber the moment it starts firing and explains itself on hover. The player
## learns the rule at the moment of the mistake instead of after the trip — and no
## consumer can drift out of step with another, because there is one condition, written
## once, and four readers of it.
##
## Placement is still never blocked — a rule is a consequence, not a wall (the agreed
## "send-off penalty" model). A warning is information, not a refusal: the drop stays
## legal and the bag can be sent exactly as packed. Because effects are stateless
## config, the same instance is shared across every owned copy of the item; never store
## per-copy state.

## How much durability a violated rule costs. Authored per item so the same rule can
## bite harder on a fragile item.
@export var penalty: int = 1


## Hook — the one method a subclass overrides. Read `item` and `layout`, return what
## this rule would do; mutate nothing, so the same call is safe to run on every
## placement change as well as at send-off. The base rule has no verdict.
func evaluate(_item: ItemData, _layout: PackLayout) -> EffectOutcome:
	return EffectOutcome.new()


## Applies the send-off half of evaluate(). Called per packed item that carries the
## effect (see RunState.resolve_item_effects), right after its default point of wear
## and before the perks get their say. `layout` is the immutable send-off snapshot.
## Subclasses override evaluate(), not this.
func resolve_send_off(item: ItemData, layout: PackLayout) -> void:
	item.durability += evaluate(item, layout).durability_delta


## Reads the packing-time half of evaluate(): a temporary stat bonus recomputed from
## the live board every time an item moves (see BagGrid.evaluate_board ->
## GameState.set_layout_bonus). Never mutates the item and never survives past packing.
## Subclasses override evaluate(), not this.
func live_bonus(item: ItemData, layout: PackLayout) -> Dictionary:
	return evaluate(item, layout).stat_delta


## The player-friendly explanation of a violation, for the send-off mistakes modal
## (see RunState.resolve_item_effects -> main._show_violations). Empty when the rule
## didn't fire, or fired in the player's favour — a boon is not a mistake.
## Subclasses override evaluate(), not this.
func get_violation_message(item: ItemData, layout: PackLayout) -> String:
	var outcome := evaluate(item, layout)
	return outcome.line if outcome.is_warning() else ""


## Hook — a one-line, player-facing statement of the rule *in general*, shown in the
## item info panel (see DraggableItem.build_info_panel) so the rule isn't invisible
## before it ever fires. Once the rule is actually firing the panel shows the outcome's
## own `line` instead, which names the specific offender. The base rule has nothing to
## say; a blank line is skipped by the panel.
func describe() -> String:
	return ""


## A readable name for an item inside a warning line. Falls back to the id, because
## bare test items and half-authored .tres files have no display name, and "packed
## against " reads worse than "packed against cheese_wedge".
static func name_of(item: ItemData) -> String:
	if item == null:
		return "something"
	return item.display_name if item.display_name != "" else item.id
