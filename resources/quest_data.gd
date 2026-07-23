@tool
class_name QuestData
extends Resource

## One quest: the brief, the bag it has to fit in, the items on offer, the stat
## targets the bars fill toward, and the story beats the playout walks.
##
## `@tool` so the inspector can turn the `traits` array into a dropdown of the
## canonical vocabulary (see _validate_property) instead of a free-text field.

## The single trait master list, preloaded so the inspector dropdown can read it.
## Same resource the Traits autoload exposes at runtime, so there's one source.
const _REGISTRY = preload("res://data/trait_registry.tres")

## Stable unique key, e.g. "whisper_woods". Used to track which quests have been
## cleared (so a completed quest isn't redrawn until its whole tier is exhausted).
@export var id: String = ""
@export var title: String = ""
@export_multiline var brief: String = ""

## Which difficulty tier this quest belongs to. The current tier is picked by how
## many quests the player has cleared, and draws only ever pull from one tier.
@export_range(0, 4) var difficulty: int = 0

## How many days this quest takes the child. This is also the gather budget it
## grants: after this quest plays out, the town phase lasts exactly this many days
## (one shop visit each). So a longer quest earns more prep time for the next one.
@export var days: int = 3
## Gold handed over when this quest is cleared (all four targets met). A failed
## quest still plays its log but pays nothing. Spent in the gather phase that
## follows.
@export var gold_reward: int = 0

@export_group("Bag")
@export var bag_cols: int = 6
@export var bag_rows: int = 5

@export_group("Content")
## This quest's traits, e.g. ["cold", "combat", "long"]. The vocabulary future
## quest-requirement logic reads (e.g. "needs items carrying trait X"). Author them
## from the canonical list in TraitRegistry.quest_traits (see the Traits autoload)
## so spellings stay consistent across quests.
@export var traits: Array[String] = []
## Items the tray offers for this quest.
@export var item_pool: Array[ItemData] = []
## Items this quest secretly needs packed. Never shown in the UI as a checklist —
## the brief is meant to hint at them (e.g. "the nights get cold" for a blanket).
## Later gameplay can read this to reward or narrate around them.
@export var required_items: Array[ItemData] = []
## Ordered story beats, walked top to bottom during the playout.
@export var narrative: Array[NarrativeEvent] = []

@export_group("Stat targets")
## Soft thresholds: they color the bars and weight the narrative. They are not a
## pass/fail gate.
@export var target_food: int = 10
@export var target_health: int = 10
@export var target_combat: int = 10
@export var target_utility: int = 10


## Inspector hook: render each element of the `traits` array as a dropdown of the
## registry's quest traits, so authoring picks from the canonical list instead of
## typing (and mistyping) a name. Editing trait_registry.tres updates the choices.
func _validate_property(property: Dictionary) -> void:
	if property.name == "traits":
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:%s" % [TYPE_STRING, PROPERTY_HINT_ENUM,
			",".join(_REGISTRY.quest_traits.keys())]


func get_targets() -> Dictionary:
	return {
		"food": target_food,
		"health": target_health,
		"combat": target_combat,
		"utility": target_utility,
	}


func get_grid_size() -> Vector2i:
	return Vector2i(bag_cols, bag_rows)
