class_name NarrativeLine
extends Resource

## One variant of a narrative beat. NarrativeEngine picks the first variant of a
## NarrativeEvent whose conditions all pass, so order authored = priority.
## A variant with no conditions always passes and acts as the fallback.

@export_multiline var text: String = ""

@export_group("Conditions")
## Minimum stat values, e.g. {"food": 8}. All entries must be met.
@export var require_stat: Dictionary = {}
## Tags that must be present on at least one packed item.
@export var require_tags: Array[String] = []
## Tags that must not be present on any packed item.
@export var forbid_tags: Array[String] = []


## `stats` is a stat dictionary (see GameState.STAT_KEYS); `packed_tags` is the
## set of tags across every packed item.
func matches(stats: Dictionary, packed_tags: Array[String]) -> bool:
	for stat_key in require_stat:
		if stats.get(stat_key, 0) < int(require_stat[stat_key]):
			return false
	for tag in require_tags:
		if not packed_tags.has(tag):
			return false
	for tag in forbid_tags:
		if packed_tags.has(tag):
			return false
	return true
