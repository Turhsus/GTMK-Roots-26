@tool
class_name QuestData
extends Resource

## One quest: the brief, the items on offer, the stat targets the bars fill
## toward, and the story beats the playout walks. (The bag is not the quest's
## to define — BagGrid owns its fixed size.)
##
## `@tool` so the inspector can turn the `traits` array into a dropdown of the
## canonical vocabulary (see _validate_property) instead of a free-text field.

## The single trait master list, preloaded so the inspector dropdown can read it.
## Same resource the Traits autoload exposes at runtime, so there's one source.
const _REGISTRY = preload("res://data/trait_registry.tres")

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

@export_group("Content")
## This quest's traits, e.g. ["cold", "combat", "long"]. The vocabulary future
## quest-requirement logic reads (e.g. "needs items carrying trait X"). Author them
## from the canonical list in TraitRegistry.quest_traits (see the Traits-- autoload)
## so spellings stay consistent across quests.
@export var traits: Array[String] = []
## Items this quest lends the player for its duration: added to the tray (the
## run inventory) when the quest is selected, and taken back when the quest is
## completed (see RunState.lend_quest_items / reclaim_quest_items).
@export var quest_items: Array[ItemData] = []
## Items this quest needs packed. Named directly in the gather-step quest
## preview (RoadScene._required_items_summary); the brief also hints at them
## (e.g. "the nights get cold" for a blanket). Later gameplay can read this to
## reward or narrate around them.
@export var required_items: Array[ItemData] = []
## Ordered story beats, walked top to bottom during the playout.
@export var narrative: Array[NarrativeEvent] = []
## Opens the playout log. Resolved the same way as `narrative`'s beats (first
## matching variant wins), so a quest can read the packed bag differently
## depending on what's in it. Null or an all-failing variant list means no
## departure line at all — see NarrativeEngine.build_log.
@export var departure: NarrativeEvent = null
## Closes the playout log, resolved the same way. Author its variants against
## this quest's own targets (get_targets()) to key the ending to how well this
## quest specifically went.
@export var homecoming: NarrativeEvent = null

@export_group("Stat targets")
## Soft thresholds: they color the bars and weight the narrative. They are not a
## pass/fail gate.
@export var target_food: int = 10
@export var target_health: int = 10
@export var target_combat: int = 10
@export var target_utility: int = 10

@export_group("Packing requirements")
## Playable cells the bag must be left *empty* for this quest to clear — room the
## child needs for whatever they are being sent to bring back (the herbs on the
## harvest run). 0, the default, means "pack it however you like" and is what every
## other quest wants.
##
## This one is a hard gate, unlike `required_items`: it is judged alongside the stat
## targets (see empty_space_met, main._on_sent_off and
## NarrativeEngine._build_summary_line). That is exactly why the packing screen shows
## it live against the board — a requirement that can fail the quest has to be visible
## while the bag can still be changed.
##
## Counted against the *current bag tier*, not the 6x6 frame, so asking for more room
## than a small bag can spare is a real difficulty knob — keep it well under 16 if a
## tier-0 (4x4) bag should be able to take the quest at all.
@export_range(0, 36) var required_empty_cells: int = 0


## Inspector hook: render each element of the `traits` array as a dropdown of the
## registry's quest traits, so authoring picks from the canonical list instead of
## typing (and mistyping) a name. Editing trait_registry.tres updates the choices.
func _validate_property(property: Dictionary) -> void:
	if property.name == "traits":
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:%s" % [TYPE_STRING, PROPERTY_HINT_ENUM,
			",".join(_REGISTRY.item_traits.keys())]


## Whether a board with `free_cells` empty cells satisfies this quest's room
## requirement. `free_cells` is a PackLayout.free_cell_count(): -1 means no board was
## measured (a replayed or previewed log), and an unmeasured board must not fail a
## requirement it was never checked against.
func empty_space_met(free_cells: int) -> bool:
	if required_empty_cells <= 0 or free_cells < 0:
		return true
	return free_cells >= required_empty_cells


## "Leave 3 squares empty", or "" when this quest asks for no room. The single phrasing
## of the requirement, so the gather preview and the packing readout can't word the same
## rule two different ways.
func empty_space_label() -> String:
	if required_empty_cells <= 0:
		return ""
	return "Leave %d square%s empty" % [
		required_empty_cells, "" if required_empty_cells == 1 else "s"]


func get_targets() -> Dictionary:
	return {
		"food": target_food,
		"health": target_health,
		"combat": target_combat,
		"utility": target_utility,
	}
