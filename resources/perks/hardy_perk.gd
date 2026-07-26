class_name HardyPerk
extends PerkData

## Hardy: the child has come home hurt once and now travels tougher, so every quest
## starts a little healthier. The bonus folds into the health stat from an empty bag on
## (see PerkData.modify_stats), so the player sees it and packs around it rather than it
## being applied silently at send-off.
##
## Perks are 1:1 with their subclass now, so this perk's identity and its one tunable
## number live here rather than in a separate .tres — RunState builds one instance of
## this class at boot (see PERK_TYPES).

## Flat health this perk adds each quest.
const HEALTH_BONUS := 1


func _init() -> void:
	id = "hardy"
	title = "Hardy"
	description = "Your little one has learned to shrug off the scrapes of the road. +1 Health for each quest."
	trigger_stat = "health"


func modify_stats(stats: Dictionary) -> Dictionary:
	stats["health"] = int(stats.get("health", 0)) + HEALTH_BONUS
	return stats
