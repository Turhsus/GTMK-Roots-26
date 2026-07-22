extends Control

## Root of the game. Owns the loop and nothing else:
##
##   brief -> packing -> send off -> playout -> pack again -> packing
##
## All three screens live in the tree the whole time and are shown one at a
## time. Keeping the packing screen alive across a playout is deliberate: the
## bag, the tray and every item node survive, so "Pack again" is a reset rather
## than a rebuild, and the log can be generated from a bag that is still packed.

const QUEST: QuestData = preload("res://data/quests/whisper_woods.tres")

@onready var brief_panel: BriefPanel = %BriefPanel
@onready var packing_scene: PackingScene = %PackingScene
@onready var playout_scene: PlayoutScene = %PlayoutScene


## Before the children, not in _ready: child _ready() runs first, and BagGrid and
## ItemTray build themselves off the current quest the moment they are ready.
func _enter_tree() -> void:
	GameState.set_quest(QUEST)


func _ready() -> void:
	brief_panel.start_requested.connect(_on_start_requested)
	packing_scene.sent_off.connect(_on_sent_off)
	playout_scene.pack_again_requested.connect(_on_pack_again_requested)
	_show(brief_panel)


func _on_start_requested() -> void:
	_show(packing_scene)


func _on_sent_off() -> void:
	var lines := NarrativeEngine.build_log(
		GameState.current_quest, GameState.packed_items, GameState.stats
	)
	_show(playout_scene)
	playout_scene.play(lines)


func _on_pack_again_requested() -> void:
	packing_scene.reset_packing()
	_show(packing_scene)


func _show(screen: Control) -> void:
	for candidate in [brief_panel, packing_scene, playout_scene]:
		(candidate as Control).visible = candidate == screen
