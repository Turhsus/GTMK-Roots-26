extends Control

## Root of the game. Owns the loop and nothing else:
##
##   choose a quest -> packing -> send off -> playout -> choose again
##
## RunState draws the choices (from the current difficulty) and records whether
## each quest was cleared; this scene just moves between screens. All screens
## live in the tree the whole time and are shown one at a time — keeping the
## packing screen alive means the log can be built from a bag that is still
## packed, and switching quests is a reset rather than a rebuild.
##
## Clearing a quest means meeting all four stat targets; that is what advances
## the difficulty. Whether it's cleared or not, the log plays and then the loop
## offers a fresh set of quests to choose from.

@onready var quest_select: QuestSelect = %QuestSelect
@onready var packing_scene: PackingScene = %PackingScene
@onready var playout_scene: PlayoutScene = %PlayoutScene


func _ready() -> void:
	quest_select.quest_chosen.connect(_on_quest_chosen)
	packing_scene.sent_off.connect(_on_sent_off)
	playout_scene.pack_again_requested.connect(_on_next_quest_requested)
	_offer_quests()


func _offer_quests() -> void:
	quest_select.present(RunState.draw_choices())
	_show(quest_select)


func _on_quest_chosen(quest: QuestData) -> void:
	packing_scene.load_quest(quest)
	_show(packing_scene)


func _on_sent_off() -> void:
	var quest := GameState.current_quest
	var cleared := GameState.count_targets_met() == GameState.STAT_KEYS.size()
	RunState.register_result(quest, cleared)
	var lines := NarrativeEngine.build_log(quest, GameState.packed_items, GameState.stats)
	_show(playout_scene)
	playout_scene.play(lines)


func _on_next_quest_requested() -> void:
	_offer_quests()


func _show(screen: Control) -> void:
	for candidate in [quest_select, packing_scene, playout_scene]:
		(candidate as Control).visible = candidate == screen
