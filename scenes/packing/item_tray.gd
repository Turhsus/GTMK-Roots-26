class_name ItemTray
extends PanelContainer

## The tray beside the bag. Spawns one DraggableItem per item in the quest's
## pool, at true 96 px-per-cell size, and flows them into rows. Items are never
## re-instantiated: the same node moves tray -> drag layer -> bag and back, so
## "refill on removal" is just adopt().

signal item_ready(view: DraggableItem)

const DRAGGABLE_ITEM := preload("res://scenes/packing/DraggableItem.tscn")

@onready var item_container: HFlowContainer = %ItemContainer


func _ready() -> void:
	GameState.quest_changed.connect(_on_quest_changed)
	if GameState.current_quest != null:
		_on_quest_changed(GameState.current_quest)


## Rebuilds the tray from the pool.
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


func _on_quest_changed(quest: QuestData) -> void:
	if quest == null:
		return
	populate(quest.item_pool)
