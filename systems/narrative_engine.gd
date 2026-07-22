class_name NarrativeEngine
extends RefCounted

## Turns a packed bag into an adventure log.
##
## Deliberately a pure function of (quest, packed_items, stats) -> Array[String]:
## it never reads GameState, so the playout can be regenerated, tested headless,
## or previewed for a hypothetical packing without touching the live game.
##
## The log is three parts:
##   1. a departure line naming what actually went in the bag,
##   2. the quest's authored beats, each resolved to its first matching variant,
##   3. a homecoming line keyed to how many stat targets the packing met.
## Parts 1 and 3 are generated here so a quest with no beats yet still plays out;
## everything in between is authored data.

## How many item names the departure line spells out before it gives up counting.
const NAMES_SHOWN := 3


## The whole log, in reading order. `stats` is a GameState-shaped stat dictionary.
static func build_log(quest: QuestData, packed_items: Array[ItemData], stats: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if quest == null:
		return lines
	var tags := collect_tags(packed_items)
	lines.append(departure_line(packed_items))
	for event in quest.narrative:
		if event == null:
			continue
		var text := event.resolve(stats, tags).strip_edges()
		# A beat whose variants all failed has nothing to say — skipping it beats
		# printing a blank line. Authoring an unconditional variant last avoids it.
		if text.is_empty():
			continue
		lines.append(text)
	lines.append(homecoming_line(count_targets_met(stats, quest.get_targets())))
	return lines


## Every tag across every packed item, deduplicated. The engine derives this
## itself rather than taking GameState's copy — that is what keeps it pure.
static func collect_tags(packed_items: Array[ItemData]) -> Array[String]:
	var tags: Array[String] = []
	for item in packed_items:
		if item == null:
			continue
		for tag in item.tags:
			if not tags.has(tag):
				tags.append(tag)
	return tags


## How many of `targets` the packing meets. Drives the homecoming line, and is
## the same rule GameState.count_targets_met() applies to the live bag.
static func count_targets_met(stats: Dictionary, targets: Dictionary) -> int:
	var met := 0
	for key in targets:
		if int(stats.get(key, 0)) >= int(targets[key]):
			met += 1
	return met


## Opens the log by reading the bag back to the player, so the first line is
## already about their choices.
static func departure_line(packed_items: Array[ItemData]) -> String:
	if packed_items.is_empty():
		return "They shoulder the bag. It is empty, and it swings light on their back. \"I'll be fine,\" they say. Off they go."
	var names: Array[String] = []
	for item in packed_items:
		if item != null:
			names.append(item.display_name)
	return "You buckle the bag shut — %s — and watch them go until the trees take them." % _join_names(names)


## Closes the log. Four targets met is a clean rescue; none is a rough trip home.
## The kitten always comes back: this is a cozy game, not a pass/fail gate.
static func homecoming_line(targets_met: int) -> String:
	match targets_met:
		4:
			return "They came home on the fourth evening, kitten asleep in the crook of one arm, bag light, boots muddy. \"I had everything I needed,\" they said, and meant it."
		3:
			return "They came home on the fourth evening with the kitten purring against their collar. One thing they'd wished for, packed next time. Mostly: they were ready."
		2:
			return "They came home a day late, kitten held tight, and ate three helpings without a word. Half of what they carried was right. The other half they had to make up as they went."
		1:
			return "They came home scratched and quiet, kitten safe in their jacket. \"It was harder than I thought,\" they said. You look at the bag and see what you left out."
		_:
			return "They came home. Kitten too — somehow. They fell asleep at the table before the soup came, and you sat there a while with the empty bag in your lap."


## "bread", "bread and rope", "bread, rope and a sword", then "+ N more".
static func _join_names(names: Array[String]) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	var shown := names.slice(0, mini(NAMES_SHOWN, names.size()))
	var extra := names.size() - shown.size()
	if extra > 0:
		return "%s and %d more" % [", ".join(shown), extra]
	return "%s and %s" % [", ".join(shown.slice(0, shown.size() - 1)), shown[-1]]
