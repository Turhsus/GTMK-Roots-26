class_name ItemEffect
extends Resource

## Base class for a per-item placement rule, composed onto an ItemData as an entry in
## its `effects` array (authored inline in the item's .tres). This mirrors the perk
## pattern (see PerkData): a small library of subclasses, each overriding the hooks
## below, so a genuinely new rule is a new *effect* subclass — never a new ItemData
## subclass. The item itself stays one class with many .tres instances.
##
## Rules resolve at SEND-OFF, once the bag is final. RunState.apply_wear hands each
## packed item's effects the board snapshot (PackLayout) so a rule can read the item's
## neighbours, the space above it, and how it's turned, then dock its durability for a
## bad pack. Placement is never blocked — a rule is a consequence, not a wall (the
## agreed "send-off penalty" model). Because effects are stateless config, the same
## instance is shared across every owned copy of the item; never store per-copy state.

## How much durability a violated rule costs. Authored per item so the same rule can
## bite harder on a fragile item.
@export var penalty: int = 1


## Hook — resolve this rule against the final board. Called per packed item that
## carries the effect, right after its default point of wear and before the perks get
## their say. Mutate `item` on a violation — docking `item.durability` by `penalty` is
## the norm. The base rule does nothing. `layout` is the immutable send-off snapshot.
func resolve_send_off(_item: ItemData, _layout: PackLayout) -> void:
	pass


## Hook — a one-line, player-facing description of the rule, shown as a warning in the
## item info panel (see DraggableItem.build_info_panel) so the rule isn't invisible.
## The base rule has nothing to say; a blank line is skipped by the panel.
func describe() -> String:
	return ""
