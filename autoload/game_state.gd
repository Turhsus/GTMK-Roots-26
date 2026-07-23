extends Node

## Autoload. Single source of truth for the current quest, what is packed, and
## the stats that follow from it. BagGrid owns *where* things sit; GameState
## only cares about *what* is in the bag.

signal quest_changed(quest: QuestData)
signal packed_items_changed(items: Array[ItemData])
signal stats_changed(stats: Dictionary, targets: Dictionary)

const STAT_KEYS: Array[String] = ["food", "health", "attack", "defense"]

var current_quest: QuestData
var packed_items: Array[ItemData] = []
var stats: Dictionary = _zero_stats()


func set_quest(quest: QuestData) -> void:
	current_quest = quest
	packed_items.clear()
	_recompute()
	quest_changed.emit(current_quest)


func add_item(item: ItemData) -> void:
	if item == null:
		return
	packed_items.append(item)
	_recompute()


func remove_item(item: ItemData) -> void:
	var index := packed_items.find(item)
	if index == -1:
		return
	packed_items.remove_at(index)
	_recompute()


## Empties the bag without dropping the quest — this is "Pack again".
func reset_packing() -> void:
	packed_items.clear()
	_recompute()


func get_targets() -> Dictionary:
	if current_quest == null:
		return _zero_stats()
	return current_quest.get_targets()


## Every tag across every packed item, deduplicated. Narrative conditions read
## this rather than walking the item list themselves.
func get_packed_tags() -> Array[String]:
	var tags: Array[String] = []
	for item in packed_items:
		for tag in item.tags:
			if not tags.has(tag):
				tags.append(tag)
	return tags


## How many of the quest's stat targets the current packing meets.
func count_targets_met() -> int:
	var targets := get_targets()
	var met := 0
	for key in STAT_KEYS:
		if stats.get(key, 0) >= int(targets.get(key, 0)):
			met += 1
	return met


func _recompute() -> void:
	stats = _zero_stats()
	for item in packed_items:
		var contribution := item.get_stats()
		for key in STAT_KEYS:
			stats[key] += int(contribution.get(key, 0))
	# Adventuring perks add flat stats on top of what's packed. The forage perk's food
	# shows from an empty bag on, so the player packs around it. RunState owns the
	# run's earned perks; this current-packing singleton reads that meta level.
	stats["food"] += RunState.food_bonus()
	packed_items_changed.emit(packed_items)
	stats_changed.emit(stats, get_targets())


func _zero_stats() -> Dictionary:
	var zeroed := {}
	for key in STAT_KEYS:
		zeroed[key] = 0
	return zeroed
