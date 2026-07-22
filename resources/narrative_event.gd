class_name NarrativeEvent
extends Resource

## One beat of the adventure log (roughly one "day"). Holds variant lines; the
## first one whose conditions pass is the one the player reads.

## Stable key for the beat, e.g. "day_2_food".
@export var beat_id: String = ""
@export var variants: Array[NarrativeLine] = []


## Returns the text of the first matching variant, or "" if none match (an
## unconditional variant authored last prevents that).
func resolve(stats: Dictionary, packed_tags: Array[String]) -> String:
	for variant in variants:
		if variant != null and variant.matches(stats, packed_tags):
			return variant.text
	return ""
