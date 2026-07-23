class_name ItemTray
extends PanelContainer

## The tray beside the bag. Spawns one DraggableItem per item in the player's
## inventory (RunState.inventory — the run's owned items, not the quest's pool),
## at true 96 px-per-cell size, and flows them into rows. Items are never
## re-instantiated: the same node moves tray -> drag layer -> bag and back, so
## "refill on removal" is just adopt().

signal item_ready(view: DraggableItem)

const DRAGGABLE_ITEM := preload("res://scenes/packing/DraggableItem.tscn")

## How the tray orders its items. Stat modes sort descending on that stat (the
## four requirement values quests set targets on); TRAIT groups items that share
## a trait vocabulary together; DEFAULT is the inventory's own order.
enum SortMode { DEFAULT, FOOD, HEALTH, COMBAT, UTILITY, TRAIT }

## Dropdown label per mode, in SortMode order (the option index IS the mode).
const SORT_LABELS: Array[String] = [
	"Default", "Food", "Health", "Combat", "Utility", "Trait",
]

var _sort_mode: SortMode = SortMode.DEFAULT

@onready var item_container: HFlowContainer = %ItemContainer
@onready var sort_button: OptionButton = %SortButton


func _ready() -> void:
	for label in SORT_LABELS:
		sort_button.add_item("Sort: %s" % label)
	sort_button.item_selected.connect(_on_sort_selected)
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
	_apply_sort()


## Takes an item back from the bag or a cancelled drag. The flow container
## re-lays it out, so any drag-time position is discarded on purpose. Re-sorting
## puts the returned item where the current sort says it belongs, not at the end.
func adopt(view: DraggableItem) -> void:
	view.reset_rotation()
	if view.get_parent() == item_container:
		return
	view.reparent(item_container, false)
	_apply_sort()


func _on_sort_selected(index: int) -> void:
	_sort_mode = index as SortMode
	_apply_sort()


## Reorders the tray's existing item nodes in place (move_child, never rebuild —
## the same nodes travel tray <-> bag, so re-instantiating here would orphan
## views the packing scene is tracking). Views mid-queue_free from a repopulate
## are skipped; they drift to the back and vanish at frame end.
func _apply_sort() -> void:
	var views: Array[DraggableItem] = []
	for child in item_container.get_children():
		if child is DraggableItem and not child.is_queued_for_deletion():
			views.append(child)
	views.sort_custom(_sort_before)
	for i in views.size():
		item_container.move_child(views[i], i)


## Comparator for the current mode. Ties (and DEFAULT) fall through to the
## inventory's own order so the sort is stable and every copy has a fixed slot.
func _sort_before(a: DraggableItem, b: DraggableItem) -> bool:
	match _sort_mode:
		SortMode.FOOD, SortMode.HEALTH, SortMode.COMBAT, SortMode.UTILITY:
			var key: String = SORT_LABELS[_sort_mode].to_lower()
			var stat_a: int = a.item.get(key)
			var stat_b: int = b.item.get(key)
			if stat_a != stat_b:
				return stat_a > stat_b
		SortMode.TRAIT:
			var key_a := _trait_key(a.item)
			var key_b := _trait_key(b.item)
			if key_a != key_b:
				return key_a < key_b
	return RunState.inventory.find(a.item) < RunState.inventory.find(b.item)


## Grouping key for the trait sort: the item's traits, sorted and joined, so
## items sharing a vocabulary sit next to each other. Trait-less items go last.
func _trait_key(item: ItemData) -> String:
	if item.traits.is_empty():
		return "~"
	var sorted_traits := item.traits.duplicate()
	sorted_traits.sort()
	return ",".join(sorted_traits)


## A quest switch is the moment to rebuild the tray. The content is the player's
## inventory, not the quest — the quest only changes the bag, targets, and story
## — but inventory itself only changes at send-off (between packing sessions), so
## a quest boundary is exactly when a rebuild is both needed and safe. We
## deliberately do NOT rebuild on inventory_changed: that fires during send-off,
## and repopulating then would wipe the bag the log is about to be built from.
func _on_quest_changed(_quest: QuestData) -> void:
	populate(RunState.inventory)
