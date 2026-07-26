class_name ItemTray
extends PanelContainer

## The tray beside the bag. Spawns one DraggableItem per item in the player's
## inventory (RunState.inventory — the run's owned items, not the quest's pool),
## at true 96 px-per-cell size, and flows them into rows. Items are never
## re-instantiated: the same node moves tray -> drag layer -> bag and back, so
## "refill on removal" is just adopt().

signal item_ready(view: DraggableItem)

const DRAGGABLE_ITEM := preload("res://scenes/packing/DraggableItem.tscn")

## How big tray items draw next to a board cell (see DraggableItem.display_scale).
## At 1.0 a single 1x3 item was a third of the tray, so most of the inventory sat
## below the scroll line; the art is authored far above cell resolution, so drawing
## it smaller costs nothing and roughly triples what fits. Grabbing an item snaps it
## back to full board scale, so what you drag is always what you drop.
const TRAY_SCALE := 0.55

## How the tray orders its items. Stat modes sort descending on that stat (the
## four requirement values quests set targets on); TRAIT groups items that share
## a trait vocabulary together; DEFAULT is the inventory's own order.
enum SortMode { DEFAULT, FOOD, HEALTH, COMBAT, UTILITY, TRAIT }

## Where a shut drawer parks its *rect's* right edge — which is not where the
## drawer looks like it ends. The art's last 63px are the handle arc, and that
## arc only occupies the vertical middle, so at any other height the visible edge
## is 63px further left. The coiled rope in finalpacking_bg.png spans x407 to
## x620 and sits well below the handle, so covering its left quarter means
## putting the *body* edge at x460 — hence 460 + 63 here. Measuring to the rect
## instead leaves the drawer short of the rope entirely.
## Open, that edge is at x800, making the slide ~277px.
@export var closed_right_edge := 523.0

## How close the pointer has to come to the drawer's leading edge to pull it out.
@export var hover_margin := 50.0

## Seconds for a full open or shut.
const SLIDE_TIME := 0.45

## The authored x, captured at _ready — the drawer's open position.
var _open_x := 0.0
var _open := true
var _slide: Tween = null

## Pins the drawer open. The auto-retract is good for seeing the board, and bad
## when you are working out of the tray and the pointer keeps straying right.
var _locked := false

## Dropdown label per mode, in SortMode order (the option index IS the mode).
const SORT_LABELS: Array[String] = [
	"Default", "Food", "Health", "Combat", "Utility", "Trait",
]

var _sort_mode: SortMode = SortMode.DEFAULT

@onready var item_container: HFlowContainer = %ItemContainer
@onready var sort_button: OptionButton = %SortButton
@onready var lock_button: Button = %LockButton
@onready var divider: Label = %Divider


func _ready() -> void:
	_open_x = position.x
	for label in SORT_LABELS:
		sort_button.add_item("Sort: %s" % label)
	sort_button.item_selected.connect(_on_sort_selected)
	lock_button.toggled.connect(_on_lock_toggled)
	# The container has no width until the first layout pass, and the drawer
	# changes it again on every slide, so the divider re-fits rather than being
	# sized once at sort time.
	item_container.resized.connect(_fit_divider)
	GameState.quest_changed.connect(_on_quest_changed)
	if GameState.current_quest != null:
		_on_quest_changed(GameState.current_quest)


## Slides the drawer to match where the pointer is. Each threshold is measured
## against the edge the drawer would have in its *current* state, which gives it
## hysteresis for free: shut, it opens once the pointer is inside x573; open, it
## does not shut again until the pointer passes x850. Measuring against the live
## position instead would let a single mid-slide frame flip the state back and
## forth and leave the drawer juddering in place.
##
## An item being dragged out lives on the packing scene's drag layer, not in the
## tray, so the drawer is free to shut behind it — and a cancelled drag lands
## back in the flow container, which re-lays it out wherever the drawer is.
func _process(_delta: float) -> void:
	# Before the first layout pass size.x is 0, which would put the leading edge
	# at the drawer's left and shut it for one frame on scene entry.
	if size.x <= 0.0:
		return
	var wants_open := _locked or get_global_mouse_position().x <= _leading_edge() + hover_margin
	if wants_open == _open:
		return
	_open = wants_open
	if _slide != null and _slide.is_valid():
		_slide.kill()
	# Sine in-out rather than cubic out: cubic out leaves at full speed and slams
	# into the stop, which is what reads as "poppy". Sine eases both ends, so a
	# heavy drawer starts and settles instead of snapping.
	_slide = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_slide.tween_property(self, "position:x", _open_x if _open else _shut_x(), SLIDE_TIME)


## The drawer's right edge in its current state — the thing the pointer has to
## get near. Deliberately the state's edge, not the live one; see _process.
func _leading_edge() -> float:
	return (_open_x if _open else _shut_x()) + size.x


func _shut_x() -> float:
	return closed_right_edge - size.x


## Rebuilds the tray from a list of items.
func populate(pool: Array[ItemData]) -> void:
	# Only the item views: the divider is authored in the scene and lives in the
	# same container, so a blanket free would take it out on the first repopulate.
	for child in item_container.get_children():
		if child is DraggableItem:
			child.queue_free()
	for item in pool:
		if item == null:
			continue
		var view: DraggableItem = DRAGGABLE_ITEM.instantiate()
		view.setup(item)
		# Set before it enters the tree, so its first layout is already tray-sized.
		view.display_scale = TRAY_SCALE
		item_container.add_child(view)
		item_ready.emit(view)
	_apply_sort()


## Takes an item back from the bag or a cancelled drag. The flow container
## re-lays it out, so any drag-time position is discarded on purpose. Re-sorting
## puts the returned item where the current sort says it belongs, not at the end.
func adopt(view: DraggableItem) -> void:
	view.reset_rotation()
	# Only BagGrid needs to own hit-testing (items overlap there); back in the
	# tray, plain engine dispatch is correct again.
	view.set_external_hit_testing(false)
	# Coming back from the board (or a cancelled drag) it is still at full board
	# scale — shrink it to tray scale on the way in.
	view.display_scale = TRAY_SCALE
	if view.get_parent() == item_container:
		return
	view.reparent(item_container, false)
	_apply_sort()


## The item views, without the sort divider the flow container also holds.
## Anything walking the tray's children wants this rather than get_children():
## the container stopped being "nothing but items" when the divider moved in.
## Views mid-queue_free from a repopulate are skipped; they drift to the back and
## vanish at frame end.
func item_views() -> Array[DraggableItem]:
	var views: Array[DraggableItem] = []
	for child in item_container.get_children():
		if child is DraggableItem and not child.is_queued_for_deletion():
			views.append(child)
	return views


## Locking only forces the drawer open; unlocking hands it straight back to the
## pointer, so it shuts on the next frame if the pointer is already away rather
## than waiting for the pointer to leave and come back.
func _on_lock_toggled(pressed: bool) -> void:
	_locked = pressed
	lock_button.text = "Lock: On" if pressed else "Lock: Off"


func _on_sort_selected(index: int) -> void:
	_sort_mode = index as SortMode
	_apply_sort()


## Reorders the tray's existing item nodes in place (move_child, never rebuild —
## the same nodes travel tray <-> bag, so re-instantiating here would orphan
## views the packing scene is tracking).
func _apply_sort() -> void:
	var views := item_views()
	views.sort_custom(_sort_before)
	for i in views.size():
		item_container.move_child(views[i], i)
	# After the loop the divider has been pushed to the end; put it back on the
	# boundary. Done here rather than in the comparator because it is not an item
	# and has no place in the ordering.
	_place_divider(views)


## Splits the sorted run into "gives this" and "does not", for the sort modes
## that have such a notion. The comparator already puts the giving items first —
## stat modes sort descending, and the trait key "~" sorts trait-less items last
## — so the boundary is just the first item that does not give.
##
## Hidden when the split would be degenerate: DEFAULT has nothing to divide by,
## and a run that is all-giving or all-not has no boundary to draw.
func _place_divider(views: Array[DraggableItem]) -> void:
	if _sort_mode == SortMode.DEFAULT:
		divider.visible = false
		return
	var split := views.size()
	for i in views.size():
		if not _gives(views[i].item):
			split = i
			break
	if split == 0 or split == views.size():
		divider.visible = false
		return
	divider.text = ("No trait" if _sort_mode == SortMode.TRAIT
		else "No %s" % SORT_LABELS[_sort_mode].to_lower())
	divider.visible = true
	_fit_divider()
	item_container.move_child(divider, split)


## A flow container gives a child its own line only when the child is as wide as
## the container, so the divider's width has to track that rather than its text.
## Kept a hair under the full width: matching it exactly makes the divider drive
## the container's own minimum width, which fights the scroll container for it.
func _fit_divider() -> void:
	divider.custom_minimum_size.x = maxf(item_container.size.x - 4.0, 0.0)


## Whether an item contributes to whatever the tray is currently sorted by.
func _gives(item: ItemData) -> bool:
	match _sort_mode:
		SortMode.DEFAULT:
			return true
		SortMode.TRAIT:
			return not item.traits.is_empty()
	return int(item.get(SORT_LABELS[_sort_mode].to_lower())) > 0


## Comparator for the current mode. Ties (and DEFAULT) fall through to height and
## then to the inventory's own order, so the sort is stable and every copy has a
## fixed slot.
##
## Height matters because the flow container makes every row as tall as its tallest
## item: one 1x3 sword sharing a row with two apples wastes two thirds of that row.
## Grouping equal heights together packs the rows tight. It is the primary key only
## in DEFAULT — under a stat sort the stat has to lead, or the dropdown would look
## broken — so the stat modes get the tighter rows only among equal values.
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
	# Tallest first. Items in the tray are always unrotated (adopt resets them), so
	# the authored shape is what will be laid out.
	var height_a: int = a.item.get_size().y
	var height_b: int = b.item.get_size().y
	if height_a != height_b:
		return height_a > height_b
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
