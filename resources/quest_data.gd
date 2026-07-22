class_name QuestData
extends Resource

## One quest: the brief, the bag it has to fit in, the items on offer, the stat
## targets the bars fill toward, and the story beats the playout walks.

@export var title: String = ""
@export_multiline var brief: String = ""

@export_group("Bag")
@export var bag_cols: int = 6
@export var bag_rows: int = 5

@export_group("Content")
## Items the tray offers for this quest.
@export var item_pool: Array[ItemData] = []
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
