class_name NarrativeEngine
extends RefCounted

## Turns a packed bag into an adventure log.
##
## Deliberately a pure function of (quest, packed_items, stats) -> Array[String]:
## it never reads GameState, so the playout can be regenerated, tested headless,
## or previewed for a hypothetical packing without touching the live game.
##
## The log is all authored data, walked top to bottom: the quest's `departure`,
## then its `narrative` beats, then its `homecoming` — each resolved to its
## first matching variant (see NarrativeEvent.resolve). Departure and homecoming
## differ from every other quest, so they live on QuestData instead of being
## generated here; a quest that hasn't authored one yet just has no line there.


## The whole log, in reading order. `stats` is a GameState-shaped stat dictionary.
static func build_log(quest: QuestData, packed_items: Array[ItemData], stats: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if quest == null:
		return lines
	var tags := collect_tags(packed_items)
	_append_resolved(lines, quest.departure, stats, tags)
	for event in quest.narrative:
		_append_resolved(lines, event, stats, tags)
	_append_resolved(lines, quest.homecoming, stats, tags)
	lines.append(_build_summary_line(quest, packed_items, stats))
	return lines


## Closing verdict line. The pass/fail call mirrors GameState.count_targets_met()
## exactly (every stat target met, nothing more) so this line never disagrees
## with the reward the run actually paid out. Missing secretly-required items
## are reported alongside as context, not as a separate failure cause — they
## don't gate the verdict (see QuestData.required_items). Built here rather
## than read off GameState so the engine stays a pure function of its inputs.
static func _build_summary_line(quest: QuestData, packed_items: Array[ItemData], stats: Dictionary) -> String:
	var targets := quest.get_targets()
	var met_stats: Array[String] = []
	var missed_stats: Array[String] = []
	for key in targets:
		var target := int(targets[key])
		var actual := int(stats.get(key, 0))
		var entry := "%s (%d/%d)" % [String(key).capitalize(), actual, target]
		if actual >= target:
			met_stats.append(entry)
		else:
			missed_stats.append(entry)

	var missing_items: Array[String] = []
	for required in quest.required_items:
		if required == null:
			continue
		var packed := false
		for item in packed_items:
			if item != null and item.id == required.id:
				packed = true
				break
		if not packed:
			var label := required.display_name if not required.display_name.is_empty() else required.id
			missing_items.append(label)

	var cleared := missed_stats.is_empty()
	var line := "Quest Succeeded: " if cleared else "Quest Failed: "
	if cleared:
		line += "every supply target was met (" + ", ".join(met_stats) + ")."
	else:
		line += "fell short on " + ", ".join(missed_stats)
		if not met_stats.is_empty():
			line += "; met " + ", ".join(met_stats)
		line += "."

	if not quest.required_items.is_empty():
		if not missing_items.is_empty():
			line += " Never packed the " + ", ".join(missing_items) + " this quest needed."
		else:
			line += " Everything the quest secretly needed made it into the bag."
	return line


## Resolves `event` and appends its text, unless it's null or every variant
## failed to match — that beat has nothing to say, so it's skipped rather than
## printing a blank line. Authoring an unconditional variant last avoids that.
static func _append_resolved(lines: Array[String], event: NarrativeEvent, stats: Dictionary, tags: Array[String]) -> void:
	if event == null:
		return
	var text := event.resolve(stats, tags).strip_edges()
	if text.is_empty():
		return
	lines.append(text)


## Every tag across every packed item, deduplicated. The engine derives this
## itself rather than taking GameState's copy — that is what keeps it pure.
static func collect_tags(packed_items: Array[ItemData]) -> Array[String]:
	var tags: Array[String] = []
	for item in packed_items:
		if item == null:
			continue
		for tag in item.traits:
			if not tags.has(tag):
				tags.append(tag)
	return tags
