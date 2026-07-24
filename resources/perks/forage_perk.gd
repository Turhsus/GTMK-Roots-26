class_name ForagePerk
extends PerkData

## Forager: the child has learned from a hungry quest and now forages along the way,
## so every quest starts with extra food already in hand. The bonus folds into the
## food stat from an empty bag on (see PerkData.modify_stats), so the player sees it
## and packs around it rather than it being applied silently at send-off.
##
## Perks are 1:1 with their subclass now, so this perk's identity and its one tunable
## number live here rather than in a separate .tres — RunState builds one instance of
## this class at boot (see PERK_TYPES).

## Flat food this perk adds each quest.
const FOOD_BONUS := 1


func _init() -> void:
	id = "forage"
	title = "Forager"
	description = "Your little one has learned from his past mistakes and learned to forage on his quests! +1 Food for each quest."
	trigger_stat = "food"


func modify_stats(stats: Dictionary) -> Dictionary:
	stats["food"] = int(stats.get("food", 0)) + FOOD_BONUS
	return stats
