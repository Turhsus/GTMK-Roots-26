class_name EffectOutcome
extends RefCounted

## What one ItemEffect says about one item on one board: the whole verdict, worked out
## without touching anything (see ItemEffect.evaluate).
##
## Because that verdict is computed purely, one call answers every question the game
## asks of a rule — what to dock at send-off, what to add to the live stat bars, what
## to name in the send-off mistakes modal, and what to warn about *while the player is
## still packing*. One implementation per rule means the warning can never drift out of
## step with the penalty; they are the same function.
##
## When each part lands is a property of the field, not of the caller:
##   durability_delta -> applied at send-off only (ItemEffect.resolve_send_off)
##   stat_delta       -> live while packing only (ItemEffect.live_bonus)
##   line             -> read at both, by the mistakes modal and the hover panel
## A rule fills whichever it means and leaves the rest alone.

## True when the rule is firing on this board right now — the bad neighbour is there,
## the space above is filled, the item is turned the wrong way. A dormant rule returns
## an otherwise-empty outcome, which is what the UI reads as "nothing to say yet".
var active: bool = false

## Durability this rule costs (negative) or saves (positive) at send-off.
var durability_delta: int = 0

## Partial GameState.STAT_KEYS -> int delta added to the live bars while packing.
var stat_delta: Dictionary = {}

## Why this rule is firing *on this board* — the concrete "Cheese Wedge is crushed
## under the Axe", not the general rule. Written in the present tense because it is
## read in two places: the hover panel while packing (where it is happening) and the
## send-off mistakes modal (where it describes the bag as it was packed).
var line: String = ""

## Note there is deliberately no back-pointer to the ItemEffect that produced this.
## Typing one here would make EffectOutcome and ItemEffect refer to each other, which
## GDScript can't resolve — and it isn't needed: whoever runs the sweep already knows
## which rule it called, so BagGrid.evaluate_board keys the outcomes by effect instead.


## A firing rule that costs something. This is what the amber warning tint and the
## send-off mistakes list are keyed to — and it is only ever a warning: nothing
## anywhere refuses a placement over it.
func is_warning() -> bool:
	return active and durability_delta < 0


## A firing rule that helps — a live stat bonus, or durability saved at send-off.
func is_boon() -> bool:
	return active and (durability_delta > 0 or not stat_delta.is_empty())
