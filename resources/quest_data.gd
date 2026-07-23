class_name QuestData
extends Resource

## One quest: the brief, the bag it has to fit in, the items on offer, the stat
## targets the bars fill toward, and the story beats the playout walks.

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
@export var target_attack: int = 10
@export var target_defense: int = 10


func get_targets() -> Dictionary:
	return {
		"food": target_food,
		"health": target_health,
		"attack": target_attack,
		"defense": target_defense,
	}


func get_grid_size() -> Vector2i:
	return Vector2i(bag_cols, bag_rows)
