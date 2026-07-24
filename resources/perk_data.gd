class_name PerkData
extends Resource

## Base class for an adventuring perk: a permanent upgrade the child earns by failing
## a quest and learning from it. Authored as a .tres in res://data/perks/, but unlike a
## plain data resource each *kind* of perk is its own subclass that overrides the hooks
## below to say how it changes the run. The systems that run the loop don't know about
## individual perks — they just loop the owned perks and call the hooks at the right
## moment (GameState calls modify_stats while packing, RunState.apply_wear calls
## modify_item at send-off). Adding a genuinely new effect is a new subclass plus,
## if it needs a new moment, a new hook here and the one call site that fires it.
##
## The fields below are shared by every perk (identity + when it's offered); the
## per-perk numbers live on the subclass so they can still be tuned in the .tres.

## Stable unique key, e.g. "forage". Ownership is tracked by this so a perk is never
## offered or granted twice (perks are unique — one of each per run).
@export var id: String = ""
@export var title: String = ""
## Shown on the pick card and meant to read as the mother's line about the lesson.
@export_multiline var description: String = ""

## The stat target whose shortfall makes this perk relevant. When a quest is failed,
## only perks whose trigger_stat is among the missed targets are offered — so a food
## shortfall surfaces the forage perk, a combat shortfall the crafty one. One of
## GameState.STAT_KEYS, or "" to always be eligible regardless of what fell short.
@export var trigger_stat: String = ""


## Hook — adjust the derived pack stats during packing. Called for every owned perk
## each time GameState recomputes, from an empty bag on, so a stat bonus is visible
## and the player packs around it. Mutate and return `stats` (keys are STAT_KEYS).
## The base perk changes nothing.
func modify_stats(stats: Dictionary) -> Dictionary:
	return stats


## Hook — the perk's chance to change one packed item at send-off, after its trip.
## Called per packed item for every owned perk, right after the item takes its default
## point of wear and before a worn-out item is discarded, so a perk can repair it,
## spare its wear, buff its stats, and so on. Mutate and return the *same* item
## instance — the inventory tracks copies by identity, so never swap in a different
## one. The base perk leaves the item untouched.
func modify_item(item: ItemData) -> ItemData:
	return item
