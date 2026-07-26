extends Node

## Throwaway harness for the item placement-effect system: PackLayout's board
## queries and each ItemEffect subclass docking durability on a bad pack. Builds
## items and a board snapshot directly — no scene tree, autoloads, or authored .tres
## — so it stays fast and immune to the tray/inventory drift the flow test suffers.
## Run: godot --headless --path . res://tools/TestEffects.tscn

var failures: int = 0


func _ready() -> void:
	_test_layout_queries()
	_test_no_upside_down()
	_test_clear_above()
	_test_no_adjacent_trait()
	_test_neighbor_stat_boost()
	_test_describe()

	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


# --- PackLayout board queries --------------------------------------------------

func _test_layout_queries() -> void:
	# A 1x1 apple at (2,2) with a 1x1 torch right of it at (3,2).
	var apple := _item("apple", ["food"])
	var torch := _item("torch", ["fire"])
	var layout := PackLayout.new()
	layout.add(apple, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	layout.add(torch, Vector2i(3, 2), 1, [Vector2i(3, 2)] as Array[Vector2i])

	check(layout.is_filled(Vector2i(2, 2)), "an occupied cell reads as filled")
	check(not layout.is_filled(Vector2i(0, 0)), "an empty cell reads as free")
	check(not layout.is_filled(Vector2i(-1, -1)), "an off-board cell reads as free")
	check(layout.item_at(Vector2i(3, 2)) == torch, "item_at finds the torch")
	check(layout.rotation_of(torch) == 1, "rotation_of returns the packed turn")
	check(layout.rotation_of(_item("ghost", [])) == -1, "rotation_of an unplaced item is -1")

	var apple_neighbours := layout.neighbours_of(apple)
	check(apple_neighbours.size() == 1 and apple_neighbours[0] == torch,
		"the apple's one neighbour is the torch")
	# A diagonal-only item must not count as a neighbour.
	var far := _item("cheese", [])
	layout.add(far, Vector2i(3, 3), 0, [Vector2i(3, 3)] as Array[Vector2i])
	check(not layout.neighbours_of(apple).has(far), "a diagonal item isn't a neighbour")

	# cells_above the apple: two rows up in its single column.
	var above := layout.cells_above(apple, 2)
	check(above.has(Vector2i(2, 1)) and above.has(Vector2i(2, 0)) and above.size() == 2,
		"cells_above returns the two cells over the footprint")


# --- NoUpsideDownEffect ---------------------------------------------------------

func _test_no_upside_down() -> void:
	var effect := NoUpsideDownEffect.new()
	effect.penalty = 1
	# Upright (step 0) — untouched.
	check(_wear_one("wine", ["water"], effect, 0) == 0, "upright item takes no extra wear")
	# Sideways (step 1) — still fine, only 180 bites.
	check(_wear_one("wine", ["water"], effect, 1) == 0, "sideways item takes no extra wear")
	# Upside down (step 2) — docked.
	check(_wear_one("wine", ["water"], effect, 2) == 1, "upside-down item loses durability")


# --- ClearAboveEffect -----------------------------------------------------------

func _test_clear_above() -> void:
	var effect := ClearAboveEffect.new()
	effect.penalty = 2
	effect.rows = 1

	var fragile := _item("egg", ["fragile"])
	# Clear above — no penalty.
	var open := PackLayout.new()
	open.add(fragile, Vector2i(1, 3), 0, [Vector2i(1, 3)] as Array[Vector2i])
	var d1 := 5
	fragile.durability = d1
	effect.resolve_send_off(fragile, open)
	check(fragile.durability == d1, "clear space above costs nothing")

	# Something one cell above — penalty.
	var crushed := PackLayout.new()
	crushed.add(fragile, Vector2i(1, 3), 0, [Vector2i(1, 3)] as Array[Vector2i])
	crushed.add(_item("rock", []), Vector2i(1, 2), 0, [Vector2i(1, 2)] as Array[Vector2i])
	fragile.durability = d1
	effect.resolve_send_off(fragile, crushed)
	check(fragile.durability == d1 - 2, "a filled cell above docks the penalty")


# --- NoAdjacentTraitEffect ------------------------------------------------------

func _test_no_adjacent_trait() -> void:
	var effect := NoAdjacentTraitEffect.new()
	effect.trait_names = ["fire"] as Array[String]
	effect.penalty = 1

	# Next to a fire item — docked.
	check(_wear_adjacent(effect, ["fire"]) == 1, "packed beside fire loses durability")
	# Next to a non-fire item — safe.
	check(_wear_adjacent(effect, ["food"]) == 0, "packed beside a safe item is fine")

	# Any one of several listed traits triggers it.
	var multi := NoAdjacentTraitEffect.new()
	multi.trait_names = ["fire", "liquid"] as Array[String]
	multi.penalty = 1
	check(_wear_adjacent(multi, ["liquid"]) == 1, "packed beside any listed trait loses durability")
	check(_wear_adjacent(multi, ["food"]) == 0, "packed beside an unlisted trait is fine")
	# Only docks once even against two fire neighbours.
	var victim := _item("cloth", ["clothing"])
	var many := PackLayout.new()
	many.add(victim, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	many.add(_item("torch1", ["fire"]), Vector2i(1, 2), 0, [Vector2i(1, 2)] as Array[Vector2i])
	many.add(_item("torch2", ["fire"]), Vector2i(3, 2), 0, [Vector2i(3, 2)] as Array[Vector2i])
	victim.durability = 5
	effect.resolve_send_off(victim, many)
	check(victim.durability == 4, "two bad neighbours still dock only once")


# --- NeighborStatBoostEffect -----------------------------------------------------

func _test_neighbor_stat_boost() -> void:
	# "Warmed by a heat source": +4 food, +1 health while packed next to fire.
	var effect := NeighborStatBoostEffect.new()
	effect.trait_names = ["fire"] as Array[String]
	effect.food_bonus = 4
	effect.health_bonus = 1

	var bread := _item("bread", ["food"])
	var torch := _item("torch", ["fire", "warmth"])
	var layout := PackLayout.new()
	layout.add(bread, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	layout.add(torch, Vector2i(3, 2), 0, [Vector2i(3, 2)] as Array[Vector2i])

	var warmed := effect.live_bonus(bread, layout)
	check(warmed.get("food", 0) == 4, "next to a heat source grants +4 food")
	check(warmed.get("health", 0) == 1, "next to a heat source grants +1 health")
	check(not warmed.has("combat") and not warmed.has("utility"),
		"stats left at zero aren't included in the bonus")

	# Same item, no heat source neighbour — nothing.
	var cold := PackLayout.new()
	cold.add(bread, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	cold.add(_item("cloth", ["clothing"]), Vector2i(3, 2), 0, [Vector2i(3, 2)] as Array[Vector2i])
	check(effect.live_bonus(bread, cold).is_empty(), "no heat source neighbour means no bonus")

	# Moved away entirely — an unplaced item has no neighbours, so no bonus either.
	var alone := PackLayout.new()
	check(effect.live_bonus(bread, alone).is_empty(), "an unplaced item gets no bonus")

	# Durability is never touched by a live bonus.
	bread.durability = 3
	effect.live_bonus(bread, layout)
	check(bread.durability == 3, "live_bonus never mutates the item")

	# BagGrid.compute_live_bonus sums live_bonus across the whole board the same way
	# resolve_item_effects sums send-off wear — this is the entry point PackingScene
	# calls after every drag. Instantiate the real scenes (not .new()) so the
	# @onready children (ItemLayer/Highlight, Icon) exist.
	var bag := (preload("res://scenes/packing/BagGrid.tscn") as PackedScene).instantiate() as BagGrid
	add_child(bag)
	bag.resize_board(6, 6)

	var bread_item := ItemData.new()
	bread_item.id = "bread"
	bread_item.shape = [Vector2i.ZERO] as Array[Vector2i]
	bread_item.effects = [effect] as Array[ItemEffect]
	var bread_view := (preload("res://scenes/packing/DraggableItem.tscn") as PackedScene).instantiate() as DraggableItem
	add_child(bread_view)
	bread_view.setup(bread_item.make_owned_copy())
	bag.place(bread_view, Vector2i(1, 1))

	var torch_item := ItemData.new()
	torch_item.id = "torch"
	torch_item.shape = [Vector2i.ZERO] as Array[Vector2i]
	torch_item.traits = ["fire"] as Array[String]
	var torch_view := (preload("res://scenes/packing/DraggableItem.tscn") as PackedScene).instantiate() as DraggableItem
	add_child(torch_view)
	torch_view.setup(torch_item.make_owned_copy())
	bag.place(torch_view, Vector2i(2, 1))

	var live := bag.compute_live_bonus()
	check(live.get("food", 0) == 4 and live.get("health", 0) == 1,
		"BagGrid.compute_live_bonus sums the live bonus across the board")

	bag.remove(torch_view)
	var after_removal := bag.compute_live_bonus()
	check(after_removal.is_empty(), "moving the heat source away drops the bonus")
	bag.queue_free()


# --- describe() -----------------------------------------------------------------

func _test_describe() -> void:
	var upside := NoUpsideDownEffect.new()
	check(upside.describe() != "", "NoUpsideDownEffect describes itself")
	var above := ClearAboveEffect.new()
	check(above.describe() != "", "ClearAboveEffect describes itself")
	var adj := NoAdjacentTraitEffect.new()
	adj.trait_names = ["fire"] as Array[String]
	check(adj.describe() != "", "a configured NoAdjacentTraitEffect describes itself")
	# An unconfigured adjacency rule stays silent rather than printing a broken line.
	check(NoAdjacentTraitEffect.new().describe() == "", "an unset adjacency rule says nothing")


# --- helpers -------------------------------------------------------------------

## Durability lost by a lone item packed at rotation `steps` under one effect.
func _wear_one(id: String, traits: Array, effect: ItemEffect, steps: int) -> int:
	var item := _item(id, traits)
	item.durability = 5
	var layout := PackLayout.new()
	layout.add(item, Vector2i(0, 0), steps, [Vector2i(0, 0)] as Array[Vector2i])
	effect.resolve_send_off(item, layout)
	return 5 - item.durability


## Durability lost by an item packed immediately left of one neighbour that carries
## `neighbour_traits`, under the given adjacency effect.
func _wear_adjacent(effect: ItemEffect, neighbour_traits: Array) -> int:
	var item := _item("subject", [])
	item.durability = 5
	var layout := PackLayout.new()
	layout.add(item, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	layout.add(_item("neighbour", neighbour_traits), Vector2i(3, 2), 0,
		[Vector2i(3, 2)] as Array[Vector2i])
	effect.resolve_send_off(item, layout)
	return 5 - item.durability


## A bare in-memory ItemData — no .tres, just enough for the effects to read.
func _item(id: String, traits: Array) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.traits.assign(traits)
	return item


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)
