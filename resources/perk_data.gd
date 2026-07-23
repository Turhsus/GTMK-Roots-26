class_name PerkData
extends Resource

## One adventuring perk: a permanent upgrade the child earns by failing a quest and
## learning from it. Authored as a .tres in res://data/perks/ so perks can be added
## or tuned without touching code — the effect fields below are read by the systems
## that apply them (GameState folds in the food bonus, RunState.apply_wear rolls the
## wear skip). A genuinely new *kind* of effect still needs a new field here plus the
## code that reads it; the two shipped perks fit the two fields below.

## Stable unique key, e.g. "forage". Ownership is tracked by this so a perk is never
## offered or granted twice (perks are unique — one of each per run).
@export var id: String = ""
@export var title: String = ""
## Shown on the pick card and meant to read as the mother's line about the lesson.
@export_multiline var description: String = ""

## The stat target whose shortfall makes this perk relevant. When a quest is failed,
## only perks whose trigger_stat is among the missed targets are offered — so a food
## shortfall surfaces the forage perk, a defense shortfall the crafty one. One of
## GameState.STAT_KEYS, or "" to always be eligible regardless of what fell short.
@export var trigger_stat: String = ""

@export_group("Effects")
## Flat food added to every quest from the start of packing (Forage sets this to 1).
## Summed across owned perks in RunState.food_bonus and folded into the food stat, so
## it shows on the bars from an empty bag on and the player packs around it.
@export var food_bonus: int = 0
## Per-item chance in [0, 1] that a defense item escapes wear on send-off (Crafty
## sets this to 0.1). Read per defense item in RunState.apply_wear.
@export var defense_wear_skip_chance: float = 0.0
