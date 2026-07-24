class_name CraftyPerk
extends PerkData

## Crafty: the child has learned to make gear last, so a combat item sometimes comes
## home from a quest as good as it left — the point of wear it took this trip is
## repaired. Rolled independently per packed combat item at send-off (see
## PerkData.modify_item, which runs right after the item's default wear).
##
## Perks are 1:1 with their subclass now, so this perk's identity and its one tunable
## number live here rather than in a separate .tres — RunState builds one instance of
## this class at boot (see PERK_TYPES).

## Chance in [0, 1] that a single combat item's trip wear is undone.
const SKIP_CHANCE := 0.1


func _init() -> void:
	id = "crafty"
	title = "Crafty"
	description = "Your little one has learned to be crafty. There is a 10% chance a combat item is not used on quests."
	trigger_stat = "combat"


func modify_item(item: ItemData) -> ItemData:
	if item != null and item.combat > 0 and randf() < SKIP_CHANCE:
		item.durability += 1  # undo this trip's wear — it comes home untouched
	return item
