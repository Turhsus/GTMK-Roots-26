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

## DEBUG: after send-off, pop a modal listing each packed item's durability before
## and after the trip's wear — the quickest way to see placement effects bite (pack
## the wine upside down and watch it drop an extra point). Flip to false to disable.
const DEBUG_SHOW_DURABILITY: bool = true

## The phases a save can drop the player back into — the three points where the
## run is a clean snapshot. Written into the save's "loop" half (see SaveManager).
const PHASE_PACKING := "packing"
const PHASE_GATHER := "gather"
const PHASE_SELECT := "select"

const MAIN_MENU := "res://scenes/menu/MainMenu.tscn"

@onready var quest_select: QuestSelect = %QuestSelect
@onready var packing_scene: PackingScene = %PackingScene
@onready var playout_scene: PlayoutScene = %PlayoutScene
@onready var road_scene: RoadScene = %RoadScene
@onready var perk_select: PerkSelect = %PerkSelect
@onready var thank_you_screen: ThankYouScreen = %ThankYouScreen
@onready var pause_menu: PauseMenu = %PauseMenu

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
	road_scene.gather_done.connect(_on_gather_done)
	road_scene.day_started.connect(_on_town_day_started)
	perk_select.perk_chosen.connect(_on_perk_chosen)
	pause_menu.resume_requested.connect(_close_pause)
	pause_menu.home_requested.connect(_on_pause_home)
	pause_menu.quit_requested.connect(_on_pause_quit)
	pause_menu.debug_phase_requested.connect(_on_debug_phase)

	# A run continued from the menu resumes at its saved phase; anything else is a
	# fresh run and starts on the tutorial.
	var resume := SaveManager.consume_loop()
	if resume.is_empty():
		_start_tutorial()
	else:
		_resume(resume)


## Escape opens the pause menu when nothing else claimed the key (e.g. packing
## cancel-drag). While paused, PauseMenu itself handles Escape to resume.
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_open_pause()
		get_viewport().set_input_as_handled()


func _open_pause() -> void:
	pause_menu.open()
	get_tree().paused = true


func _close_pause() -> void:
	pause_menu.close()
	get_tree().paused = false


## Leaves the run for the title screen. Autosaves already cover Continue; we don't
## wipe RunState here so a mid-run Home still has a save to pick back up.
func _on_pause_home() -> void:
	_close_pause()
	get_tree().change_scene_to_file(MAIN_MENU)


func _on_pause_quit() -> void:
	_close_pause()
	get_tree().quit()


## Debug-only: jump straight to a loop screen with whatever state we can salvage.
func _on_debug_phase(phase: String) -> void:
	_close_pause()
	match phase:
		"packing":
			var quest := GameState.current_quest
			if quest == null:
				quest = RunState.TUTORIAL
				RunState.lend_quest_items(quest)
			packing_scene.load_quest(quest)
			_show(packing_scene)
		"playout":
			var quest := GameState.current_quest
			if quest == null:
				quest = RunState.TUTORIAL
			var lines := NarrativeEngine.build_log(quest, GameState.packed_items, GameState.stats)
			if lines.is_empty():
				lines = ["(debug) Nothing packed yet — placeholder log."]
			_show(playout_scene)
			playout_scene.play(lines)
		"gather":
			if _gather_days < 1:
				_gather_days = 2
			if _upcoming.is_empty():
				_upcoming = RunState.draw_choices()
			road_scene.begin(_gather_days, _upcoming)
			_show(road_scene)
		"select":
			if _upcoming.is_empty():
				_upcoming = RunState.draw_choices()
			quest_select.present(_upcoming)
			_show(quest_select)
		"perk":
			var offers := RunState.offer_perks(["food", "health", "combat", "utility"])
			perk_select.present(offers)
			_show(perk_select)
		"thank_you":
			thank_you_screen.show_end()
			_show(thank_you_screen)


## The forced opener: the tutorial quest, packed directly with no selection.
func _start_tutorial() -> void:
	# Lend before load_quest: the tray rebuilds off the inventory on quest_changed,
	# so the loaned items must already be in it to show up.
	RunState.lend_quest_items(RunState.TUTORIAL)
	packing_scene.load_quest(RunState.TUTORIAL)
	_show(packing_scene)
	_save_checkpoint(PHASE_PACKING)


func _on_quest_chosen(quest: QuestData) -> void:
	RunState.lend_quest_items(quest)
	packing_scene.load_quest(quest)
	_show(packing_scene)
	_save_checkpoint(PHASE_PACKING)


func _on_sent_off() -> void:
	var quest := GameState.current_quest
	# Snapshot the packed board before touching anything — the placement effects read
	# how each item was packed (neighbours, space above, rotation), and the debug
	# readout wants every item's before -> after, including copies destroyed below.
	var layout := packing_scene.snapshot_board()
	var report := _durability_report(layout)

	# The send-off runs in a deliberate order (see the design note in run_state.gd):
	# 1. Placement effects dock durability for a bad pack (packed upside down, next to
	#    the wrong thing) ...
	RunState.resolve_item_effects(GameState.packed_items, layout)
	# 2. ... then perks get the last, kindest word (crafty can repair a combat item) ...
	RunState.apply_perks_to_items(GameState.packed_items)
	# 3. ... and a copy the pack itself destroyed is gone *before* the quest is judged:
	#    it broke in the bag, so it neither helps the quest nor comes home.
	_discard_worn_out()

	# 4. Judge the quest against what actually survived to be used. register_result pays
	#    the reward on a clear, so the gold is on hand for the gather phase that follows.
	var cleared := GameState.count_targets_met() == GameState.STAT_KEYS.size()
	RunState.register_result(quest, cleared)
	# Remember the outcome for the post-playout perk offer. GameState is still on this
	# quest here, so read the shortfall now — by the time the playout ends the picker
	# may have moved on.
	_last_cleared = cleared
	_last_missed_stats = _missed_stats()
	# The log reflects the survivors too — a food item that broke won't tell its beat.
	var lines := NarrativeEngine.build_log(quest, GameState.packed_items, GameState.stats)

	# 5. The trip itself wears every surviving item by one: single-use items are spent,
	#    sturdier ones (the blanket) come home with less durability left ...
	RunState.apply_wear_to_inventory(GameState.packed_items)
	# 6. ... and whatever the trip wore out is thrown away for good.
	_discard_worn_out()

	for entry in report:
		entry["after"] = (entry["item"] as ItemData).durability
	# The quest is over: whatever it lent for the trip goes back. After wear, so a
	# loaned item that was packed and spent is simply gone rather than double-removed.
	RunState.reclaim_quest_items()
	_gather_days = quest.days
	# Debug: hold the flow on a durability readout until it's dismissed, then carry on
	# exactly as an undebugged send-off would.
	if DEBUG_SHOW_DURABILITY and not report.is_empty():
		_show_durability_debug(report, _proceed_after_send.bind(lines))
		return
	_proceed_after_send(lines)


## What a finished send-off does next: skip straight past the log (debug) or play it.
func _proceed_after_send(lines: Array[String]) -> void:
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
	road_scene.begin(_gather_days, _upcoming)
	_show(road_scene)
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
		"shop_purchases": road_scene.get_purchases(),
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
			road_scene.begin(_gather_days, _upcoming, int(loop.get("gather_day", 1)),
					purchases if purchases is Dictionary else {})
			_show(road_scene)
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


## Drops every worn-out copy (durability <= 0) from the current send-off. RunState
## erases it from the inventory for good; the same copy is then removed from the
## packing so it stops counting toward the quest and its narrative beats (packed
## items and inventory copies are the same instances). Called twice in _on_sent_off:
## once after placement effects/perks (so a destroyed item isn't judged) and once
## after the trip's flat wear.
func _discard_worn_out() -> void:
	for item in RunState.discard_worn_out(GameState.packed_items):
		GameState.remove_item(item)


func _show(screen: Control) -> void:
	for candidate in [quest_select, packing_scene, playout_scene, road_scene, perk_select, thank_you_screen]:
		(candidate as Control).visible = candidate == screen


# --- debug: durability readout -------------------------------------------------

## One record per packed item, capturing its durability and rotation *before* wear.
## `after` is filled in once all send-off wear has run (see _on_sent_off).
func _durability_report(layout: PackLayout) -> Array:
	var report: Array = []
	for item in GameState.packed_items:
		report.append({
			"item": item,
			"before": item.durability,
			"rotation": layout.rotation_of(item),
		})
	return report


## Modal debug overlay: lists each packed item's before -> after durability so a
## placement effect's extra bite is visible (an upside-down wine drops two, not one).
## Sits on its own CanvasLayer above every screen; `on_dismiss` resumes the loop.
func _show_durability_debug(report: Array, on_dismiss: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.08, 0.98)
	style.border_color = Color(0.55, 0.42, 0.26)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "DEBUG — packed durability after send-off"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	for entry in report:
		var item := entry["item"] as ItemData
		var before := int(entry["before"])
		var after := int(entry["after"])
		var row := Label.new()
		var text := "%s:   %d → %d   (%+d)" % [item.display_name, before, after, after - before]
		if int(entry["rotation"]) == 2:
			text += "   [upside down]"
		if after <= 0:
			text += "   SPENT"
		row.text = text
		# Flag anything that lost more than the flat one point of trip wear — that's an
		# effect (or perk) at work, the thing this readout exists to show.
		if before - after > 1:
			row.add_theme_color_override("font_color", Color("d08b52"))
		box.add_child(row)

	var button := Button.new()
	button.text = "Continue"
	box.add_child(button)
	button.pressed.connect(func() -> void:
		layer.queue_free()
		on_dismiss.call())
