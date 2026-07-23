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

@onready var quest_select: QuestSelect = %QuestSelect
@onready var packing_scene: PackingScene = %PackingScene
@onready var playout_scene: PlayoutScene = %PlayoutScene
@onready var town_screen: TownScreen = %TownScreen

## The three quests drawn for the next selection, previewed in town and then
## offered on QuestSelect — the same set for both, so the preview isn't a lie.
var _upcoming: Array[QuestData] = []
## The gather budget owed to the just-completed quest, captured at send-off (the
## current quest is replaced before the gather actually opens).
var _gather_days: int = 0


func _ready() -> void:
	quest_select.quest_chosen.connect(_on_quest_chosen)
	packing_scene.sent_off.connect(_on_sent_off)
	playout_scene.pack_again_requested.connect(_on_playout_done)
	town_screen.gather_done.connect(_on_gather_done)
	_start_tutorial()


## The forced opener: the tutorial quest, packed directly with no selection.
func _start_tutorial() -> void:
	packing_scene.load_quest(RunState.TUTORIAL)
	_show(packing_scene)


func _on_quest_chosen(quest: QuestData) -> void:
	packing_scene.load_quest(quest)
	_show(packing_scene)


func _on_sent_off() -> void:
	var quest := GameState.current_quest
	var cleared := GameState.count_targets_met() == GameState.STAT_KEYS.size()
	# register_result pays the reward on a clear, so the gold is on hand for the
	# gather phase that follows.
	RunState.register_result(quest, cleared)
	var lines := NarrativeEngine.build_log(quest, GameState.packed_items, GameState.stats)
	# Whatever went into the bag went off with the child: it's spent and leaves the
	# inventory for good. (Read the log off packed_items first — consume only
	# touches RunState.) Remember this quest's length; it's the gather budget owed.
	RunState.consume(GameState.packed_items)
	_gather_days = quest.days
	_show(playout_scene)
	playout_scene.play(lines)


## Playout finished (the "continue" button): head into town to gather for the next
## quest. Draw the next three now so they can be previewed there and offered on
## select afterward.
func _on_playout_done() -> void:
	_upcoming = RunState.draw_choices()
	town_screen.begin(_gather_days, _upcoming)
	_show(town_screen)


## The gather days are spent: choose the next quest from the previewed set.
func _on_gather_done() -> void:
	quest_select.present(_upcoming)
	_show(quest_select)


func _show(screen: Control) -> void:
	for candidate in [quest_select, packing_scene, playout_scene, town_screen]:
		(candidate as Control).visible = candidate == screen
