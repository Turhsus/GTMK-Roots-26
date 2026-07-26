class_name PerkData
extends Resource

## Base class for an adventuring perk: a permanent upgrade the child earns by failing
## a quest and learning from it. Authored as a .tres in res://data/perks/, but unlike a
## plain data resource each *kind* of perk is its own subclass that overrides the hooks
## below to say how it changes the run. The systems that run the loop don't know about
## individual perks — they just loop the owned perks and call the hooks at the right
## moment (GameState calls modify_stats while packing, RunState.apply_perks_to_items
## calls modify_item at send-off). Adding a genuinely new effect is a new subclass plus,
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
## spare its wear, buff its stats, and so on. Mutate the *same* item instance — the
## inventory tracks copies by identity, so never swap in a different one.
##
## `layout` is the immutable send-off snapshot of the board (null when there's no board
## to read, as the tests pass), so a perk that cares about *how* the bag was packed can
## re-ask the item's own effects what they did — see SelfSufficiencyPerk. That keeps a
## perk that reacts to placement inside the perk, rather than wiring it into the
## effect pipeline.
##
## Returns a player-facing line naming what the perk just did, or "" when it didn't
## fire. RunState.apply_perks_to_items collects those lines and main.gd shows them in
## the perk-activation modal, so a perk announces itself without any system knowing
## which perk it is. The line is *returned* rather than stashed on the perk because
## all_perks holds one shared instance per kind — a perk must never carry per-item
## state. The base perk leaves the item untouched and says nothing.
func modify_item(_item: ItemData, _layout: PackLayout = null) -> String:
	return ""
