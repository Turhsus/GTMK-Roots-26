class_name ItemTray
extends PanelContainer

## The tray beside the bag. Spawns one DraggableItem per item in the player's
## inventory (RunState.inventory — the run's owned items, not the quest's pool),
## at true 96 px-per-cell size, and flows them into rows. Items are never
## re-instantiated: the same node moves tray -> drag layer -> bag and back, so
## "refill on removal" is just adopt().

signal item_ready(view: DraggableItem)

const DRAGGABLE_ITEM := preload("res://scenes/packing/DraggableItem.tscn")

@onready var item_container: HFlowContainer = %ItemContainer


func _ready() -> void:
	GameState.quest_changed.connect(_on_quest_changed)
	if GameState.current_quest != null:
		_on_quest_changed(GameState.current_quest)


## Rebuilds the tray from a list of items.
func populate(pool: Array[ItemData]) -> void:
	for child in item_container.get_children():
		child.queue_free()
	for item in pool:
		if item == null:
			continue
		var view: DraggableItem = DRAGGABLE_ITEM.instantiate()
		view.setup(item)
		item_container.add_child(view)
		item_ready.emit(view)


## Takes an item back from the bag or a cancelled drag. The flow container
## re-lays it out, so any drag-time position is discarded on purpose.
func adopt(view: DraggableItem) -> void:
	view.reset_rotation()
	if view.get_parent() == item_container:
		return
	view.reparent(item_container, false)


## A quest switch is the moment to rebuild the tray. The content is the player's
## inventory, not the quest — the quest only changes the bag, targets, and story
## — but inventory itself only changes at send-off (between packing sessions), so
## a quest boundary is exactly when a rebuild is both needed and safe. We
## deliberately do NOT rebuild on inventory_changed: that fires during send-off,
## and repopulating then would wipe the bag the log is about to be built from.
func _on_quest_changed(_quest: QuestData) -> void:
	populate(RunState.inventory)
