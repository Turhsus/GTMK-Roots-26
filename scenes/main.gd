extends Control

## Root of the game. Owns the loop and nothing else:
##
##   tutorial quest -> packing -> send off -> playout -> gather (town) ->
##   choose next quest -> packing -> send off -> playout -> gather -> ...
##
## The very first quest is a fixed tutorial (RunState.TUTORIAL), packed straight
## away with no choosing and no gather phase before it. Every quest after that is
## picked on QuestSelect from the three RunState draws.
##
## The gather phase sits *after* a quest's playout: its day budget is that quest's
## `days`, and during it the player shops for the next quest while previewing the
## three they'll choose from. So a quest earns both gold (on a clear) and the prep
## time that follow it. RunState draws those three when the gather opens and this
## scene holds them, so the same set is previewed in town and offered on select.
##
## All screens live in the tree the whole time and are shown one at a time —
## keeping the packing screen alive means the log can be built from a bag that is
## still packed, and switching quests is a reset rather than a rebuild.
##
## Clearing a quest means meeting all four stat targets; that is what advances the
## difficulty and pays the reward. Cleared or not, the log plays, then town.
##
## The whole run is on a clock: RunState.days_remaining counts down one per day
## spent in town. When it runs out, the gather in progress still finishes, then one
## final quest is packed and played, and the run ends on the thank-you screen —
## no perk, no further gather (see _on_gather_done / _on_playout_done).

## DEBUG: skip the adventure-log playout entirely — send-off jumps straight to
## what follows it (perk offer / gather). Flip back to false to restore the log.
const DEBUG_SKIP_PLAYOUT: bool = true

## The phases a save can drop the player back into — the three points where the
## run is a clean snapshot. Written into the save's "loop" half (see SaveManager).
const PHASE_PACKING := "packing"
const PHASE_GATHER := "gather"
const PHASE_SELECT := "select"

@onready var quest_select: QuestSelect = %QuestSelect
@onready var packing_scene: PackingScene = %PackingScene
@onready var playout_scene: PlayoutScene = %PlayoutScene
@onready var town_screen: TownScreen = %TownScreen
@onready var perk_select: PerkSelect = %PerkSelect
@onready var thank_you_screen: ThankYouScreen = %ThankYouScreen

## The three quests drawn for the next selection, previewed in town and then
## offered on QuestSelect — the same set for both, so the preview isn't a lie.
var _upcoming: Array[QuestData] = []
## The gather budget owed to the just-completed quest, captured at send-off (the
## current quest is replaced before the gather actually opens).
var _gather_days: int = 0
## Whether the just-sent quest was cleared, and which stat targets it fell short of.
## Captured at send-off (GameState is still on that quest then) so that after the
## playout a failure can offer a perk that addresses what went wrong.
var _last_cleared: bool = false
var _last_missed_stats: Array[String] = []
## Set once the global day clock has run out: the quest now being packed is the
## run's last. After its playout the loop ends on the thank-you screen rather than
## offering a perk or another gather (see _on_playout_done).
var _is_final_quest: bool = false


func _ready() -> void:
	quest_select.quest_chosen.connect(_on_quest_chosen)
	packing_scene.sent_off.connect(_on_sent_off)
	playout_scene.pack_again_requested.connect(_on_playout_done)
	town_screen.gather_done.connect(_on_gather_done)
	town_screen.day_started.connect(_on_town_day_started)
	perk_select.perk_chosen.connect(_on_perk_chosen)

	# A run continued from the menu resumes at its saved phase; anything else is a
	# fresh run and starts on the tutorial.
	var resume := SaveManager.consume_loop()
	if resume.is_empty():
		_start_tutorial()
	else:
		_resume(resume)


## The forced opener: the tutorial quest, packed directly with no selection.
func _start_tutorial() -> void:
	packing_scene.load_quest(RunState.TUTORIAL)
	_show(packing_scene)
	_save_checkpoint(PHASE_PACKING)


func _on_quest_chosen(quest: QuestData) -> void:
	packing_scene.load_quest(quest)
	_show(packing_scene)
	_save_checkpoint(PHASE_PACKING)


func _on_sent_off() -> void:
	var quest := GameState.current_quest
	var cleared := GameState.count_targets_met() == GameState.STAT_KEYS.size()
	# register_result pays the reward on a clear, so the gold is on hand for the
	# gather phase that follows.
	RunState.register_result(quest, cleared)
	# Remember the outcome for the post-playout perk offer. GameState is still on this
	# quest here, so read the shortfall now — by the time the playout ends the picker
	# may have moved on.
	_last_cleared = cleared
	_last_missed_stats = _missed_stats()
	var lines := NarrativeEngine.build_log(quest, GameState.packed_items, GameState.stats)
	# Everything in the bag takes the trip and wears by one: single-use items are
	# spent, sturdier ones (the blanket) come home with less durability left. (Read
	# the log off packed_items first — apply_wear only touches RunState.) Remember
	# this quest's length; it's the gather budget owed.
	RunState.apply_wear(GameState.packed_items)
	_gather_days = quest.days
	if DEBUG_SKIP_PLAYOUT:
		# Skip showing the log; go straight to what the "continue" button would do.
		_on_playout_done()
		return
	_show(playout_scene)
	playout_scene.play(lines)


## Playout finished (the "continue" button). A failed quest is a lesson: offer a
## perk that addresses what fell short before heading to town. A clear — or a failure
## with every relevant perk already earned — skips straight to the gather phase.
func _on_playout_done() -> void:
	# The final quest ends the run outright — no lesson, no next gather.
	if _is_final_quest:
		thank_you_screen.show_end()
		_show(thank_you_screen)
		return
	if not _last_cleared:
		var offers := RunState.offer_perks(_last_missed_stats)
		if not offers.is_empty():
			perk_select.present(offers)
			_show(perk_select)
			return
	_begin_gather()


## The lesson is picked: bank the perk, then carry on into the gather phase.
func _on_perk_chosen(perk: PerkData) -> void:
	RunState.add_perk(perk)
	_begin_gather()


## Head into town to gather for the next quest. Draw the next three now so they can
## be previewed there and offered on select afterward.
func _begin_gather() -> void:
	_upcoming = RunState.draw_choices()
	town_screen.begin(_gather_days, _upcoming)
	_show(town_screen)
	# Checkpoint after the draw, so a resume reuses these three rather than drawing
	# a fresh set — draw_choices has side effects (it can reset a tier's clears).
	_save_checkpoint(PHASE_GATHER, 1)


## A new day opened in town: re-checkpoint so the day's shopping isn't replayed.
func _on_town_day_started(day: int) -> void:
	_save_checkpoint(PHASE_GATHER, day)


## The gather days are spent: choose the next quest from the previewed set. If the
## run's global day clock has now run out, that pick is the final quest — flag it so
## its playout ends the game instead of looping back to another gather.
func _on_gather_done() -> void:
	if RunState.days_are_up():
		_is_final_quest = true
	quest_select.present(_upcoming)
	_show(quest_select)
	_save_checkpoint(PHASE_SELECT)


# --- saving --------------------------------------------------------------------

## Autosaves at a phase boundary. Everything about the *run* comes from RunState;
## what this adds is where in the loop the player stands, so a load can rebuild the
## screen they were on. `gather_day` and `shop_purchases` only mean anything for
## PHASE_GATHER.
func _save_checkpoint(phase: String, gather_day: int = 1) -> void:
	var quest_id := ""
	if GameState.current_quest != null:
		quest_id = GameState.current_quest.id
	SaveManager.save_game({
		"phase": phase,
		"quest_id": quest_id,
		"upcoming_ids": _upcoming_ids(),
		"gather_days": _gather_days,
		"gather_day": gather_day,
		"shop_purchases": town_screen.get_purchases(),
		"is_final_quest": _is_final_quest,
	})


## Rebuilds the loop from a save's "loop" half and shows the phase it names.
## RunState has already been restored by the time this runs (SaveManager does that
## before the scene change), so the inventory, gold and clock are all in place.
func _resume(loop: Dictionary) -> void:
	_gather_days = int(loop.get("gather_days", 0))
	_is_final_quest = bool(loop.get("is_final_quest", false))
	_upcoming = _quests_from_ids(loop.get("upcoming_ids", []))

	match String(loop.get("phase", "")):
		PHASE_GATHER:
			var purchases: Variant = loop.get("shop_purchases", {})
			town_screen.begin(_gather_days, _upcoming, int(loop.get("gather_day", 1)),
					purchases if purchases is Dictionary else {})
			_show(town_screen)
		PHASE_SELECT:
			# A save whose quests have since been removed from the pool would leave
			# nothing to pick, which would dead-end the run — draw a fresh set.
			if _upcoming.is_empty():
				_upcoming = RunState.draw_choices()
			quest_select.present(_upcoming)
			_show(quest_select)
		_:
			# PHASE_PACKING, and the fallback for an unrecognised phase: pack the
			# saved quest, or the tutorial if its id no longer resolves.
			var quest := RunState.find_quest(String(loop.get("quest_id", "")))
			if quest == null:
				quest = RunState.TUTORIAL
			packing_scene.load_quest(quest)
			_show(packing_scene)


func _upcoming_ids() -> Array:
	var ids: Array = []
	for quest in _upcoming:
		ids.append(quest.id)
	return ids


## Saved ids back into quests, skipping any the pool no longer holds.
func _quests_from_ids(ids: Variant) -> Array[QuestData]:
	var quests: Array[QuestData] = []
	if ids is Array:
		for id in ids:
			var quest := RunState.find_quest(String(id))
			if quest != null:
				quests.append(quest)
	return quests


## The stat targets the sent-off pack fell short of — what the failure was made of,
## used to offer perks that address it (see RunState.offer_perks).
func _missed_stats() -> Array[String]:
	var missed: Array[String] = []
	var targets := GameState.get_targets()
	for key in GameState.STAT_KEYS:
		if int(GameState.stats.get(key, 0)) < int(targets.get(key, 0)):
			missed.append(key)
	return missed


func _show(screen: Control) -> void:
	for candidate in [quest_select, packing_scene, playout_scene, town_screen, perk_select, thank_you_screen]:
		(candidate as Control).visible = candidate == screen
