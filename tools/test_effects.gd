extends Node

## Throwaway harness for the item placement-effect system: PackLayout's board
## queries and each ItemEffect subclass docking durability on a bad pack. Builds
## items and a board snapshot directly — no scene tree, autoloads, or authored .tres
## — so it stays fast and immune to the tray/inventory drift the flow test suffers.
## Run: godot --headless --path . res://tools/TestEffects.tscn

var failures: int = 0


func _ready() -> void:
	_test_layout_queries()
	_test_clear_above()
	_test_no_adjacent_trait()
	_test_no_trait_in_bag()
	_test_requires_adjacent_trait()
	_test_neighbor_stat_boost()
	_test_contains_item()
	_test_describe()
	_test_evaluate_is_pure()
	_test_appliers_agree_with_evaluate()
	_test_board_evaluation()

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


# --- NoTraitInBagEffect ----------------------------------------------------------

## The whole-bag rule a quest requirement hangs on: "deliver this, and take nothing
## sharp". Distance must not matter — that is the whole difference from the adjacency
## rule above.
func _test_no_trait_in_bag() -> void:
	var effect := NoTraitInBagEffect.new()
	effect.trait_names = ["sharp"] as Array[String]
	effect.penalty = 1

	var parcel := _item("parcel", ["fragile"])
	var sword := _item("sword", ["weapon", "sharp"])

	# Opposite corners of the board — nowhere near each other, still a violation.
	var far := PackLayout.new()
	far.add(parcel, Vector2i(0, 0), 0, [Vector2i(0, 0)] as Array[Vector2i])
	far.add(sword, Vector2i(5, 5), 0, [Vector2i(5, 5)] as Array[Vector2i])
	parcel.durability = 3
	effect.resolve_send_off(parcel, far)
	check(parcel.durability == 2, "anything sharp anywhere in the bag docks the parcel")
	check(effect.get_violation_message(parcel, far).contains("sword"),
		"the violation names what shouldn't have been packed")

	# A blunt bag is fine, however full.
	var blunt := PackLayout.new()
	blunt.add(parcel, Vector2i(0, 0), 0, [Vector2i(0, 0)] as Array[Vector2i])
	blunt.add(_item("bread", ["food"]), Vector2i(1, 0), 0, [Vector2i(1, 0)] as Array[Vector2i])
	blunt.add(_item("rope", ["tying"]), Vector2i(5, 5), 0, [Vector2i(5, 5)] as Array[Vector2i])
	parcel.durability = 3
	effect.resolve_send_off(parcel, blunt)
	check(parcel.durability == 3, "a bag with nothing sharp in it costs nothing")

	# Docks once however many offenders came along.
	var armoury := PackLayout.new()
	armoury.add(parcel, Vector2i(0, 0), 0, [Vector2i(0, 0)] as Array[Vector2i])
	armoury.add(_item("axe", ["sharp"]), Vector2i(2, 0), 0, [Vector2i(2, 0)] as Array[Vector2i])
	armoury.add(_item("knife", ["sharp"]), Vector2i(4, 4), 0, [Vector2i(4, 4)] as Array[Vector2i])
	parcel.durability = 3
	effect.resolve_send_off(parcel, armoury)
	check(parcel.durability == 2, "two offenders still dock only once")

	# The rule never fires on the item's own traits — a sharp thing may carry it.
	var self_sharp := _item("blade", ["sharp"])
	var alone := PackLayout.new()
	alone.add(self_sharp, Vector2i(0, 0), 0, [Vector2i(0, 0)] as Array[Vector2i])
	check(not effect.evaluate(self_sharp, alone).active, "an item never violates itself")

	# Left in the tray, it met nothing: the offender is aboard but the carrier isn't.
	var unpacked := PackLayout.new()
	unpacked.add(sword, Vector2i(5, 5), 0, [Vector2i(5, 5)] as Array[Vector2i])
	check(not effect.evaluate(parcel, unpacked).active, "an unpacked item breaks no rule")


# --- RequiresAdjacentTraitEffect --------------------------------------------------

## The mirror rule: it fires on a neighbour being *missing*, so it is live from the
## moment the item is placed and goes quiet only once the player solves it.
func _test_requires_adjacent_trait() -> void:
	var effect := RequiresAdjacentTraitEffect.new()
	effect.trait_names = ["armor"] as Array[String]
	effect.penalty = 2

	var bottle := _item("tonic", ["fragile", "liquid"])

	# Packed alone — nothing to brace against.
	var loose := PackLayout.new()
	loose.add(bottle, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	bottle.durability = 5
	effect.resolve_send_off(bottle, loose)
	check(bottle.durability == 3, "an unbraced item is docked")
	check(effect.get_violation_message(bottle, loose) != "", "the requirement explains itself")

	# Neighbour without the trait doesn't count.
	var soft := PackLayout.new()
	soft.add(bottle, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	soft.add(_item("bread", ["food"]), Vector2i(3, 2), 0, [Vector2i(3, 2)] as Array[Vector2i])
	bottle.durability = 5
	effect.resolve_send_off(bottle, soft)
	check(bottle.durability == 3, "the wrong neighbour doesn't satisfy the requirement")

	# The right neighbour, on any side, satisfies it.
	var braced := PackLayout.new()
	braced.add(bottle, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	braced.add(_item("helmet", ["armor", "defence"]), Vector2i(2, 1), 0,
		[Vector2i(2, 1)] as Array[Vector2i])
	bottle.durability = 5
	effect.resolve_send_off(bottle, braced)
	check(bottle.durability == 5, "a neighbour carrying the trait costs nothing")
	check(not effect.evaluate(bottle, braced).active, "a satisfied requirement goes dormant")

	# Diagonals are not neighbours here either.
	var corner := PackLayout.new()
	corner.add(bottle, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	corner.add(_item("shield", ["armor"]), Vector2i(3, 3), 0, [Vector2i(3, 3)] as Array[Vector2i])
	check(effect.evaluate(bottle, corner).active, "a diagonal neighbour doesn't brace anything")

	# Still in the tray: a requirement isn't a standing violation on an empty board.
	check(not effect.evaluate(bottle, PackLayout.new()).active,
		"an unpacked item isn't in violation of its own requirement")


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


# --- ContainsItemEffect -----------------------------------------------------------

## The nesting rule: a hollow item (helmet, boots) acting on whatever is packed inside
## its opening. The one rule whose durability lands on a *different* item, so the
## target of the delta is as much under test as the trigger.
func _test_contains_item() -> void:
	# A helmet: 3x2 with a one-cell hollow at its middle-bottom, placed at (1,1).
	var helmet := _item("helmet", ["armor"])
	helmet.display_name = "Helmet"
	var helmet_cells := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(1, 2), Vector2i(3, 2)] as Array[Vector2i]
	var apple := _item("apple", ["food", "fragile"])
	apple.display_name = "Apple"
	apple.max_durability = 5

	# PackLayout's hollow queries first — the geometry the rule stands on.
	var nested := PackLayout.new()
	nested.add(helmet, Vector2i(1, 1), 0, helmet_cells)
	nested.add(apple, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	var hollow := nested.hollow_cells(helmet)
	check(hollow.size() == 1 and hollow[0] == Vector2i(2, 2),
		"hollow_cells finds the gap inside the shape's bounding box")
	check(nested.hollow_cells(apple).is_empty(), "a solid item has no hollow")
	check(nested.hollow_cells(_item("ghost", [])).is_empty(), "an unplaced item has no hollow")
	var inside := nested.items_within(helmet)
	check(inside.size() == 1 and inside[0] == apple,
		"items_within finds the item sitting in the hollow")
	check(nested.items_within(apple).is_empty(), "a solid item contains nothing")

	# The cushioning helmet: +1 durability to whatever is inside it.
	var cradle := ContainsItemEffect.new()
	cradle.durability_delta = 1
	helmet.durability = 5
	apple.durability = 1
	cradle.resolve_send_off(helmet, nested)
	check(apple.durability == 2, "the nested item gets the durability, not the container")
	check(helmet.durability == 5, "the container's own durability is untouched")

	# Cushioning gives back the trip's wear, never more than new.
	apple.durability = apple.max_durability
	cradle.resolve_send_off(helmet, nested)
	check(apple.durability == apple.max_durability, "a cushioned item is never pushed past new")
	# A destroyed copy is past saving.
	apple.durability = 0
	cradle.resolve_send_off(helmet, nested)
	check(apple.durability == 0, "a worn-out nested item isn't resurrected")

	var outcome := cradle.evaluate(helmet, nested)
	check(outcome.active, "a filled hollow fires")
	check(outcome.is_boon() and not outcome.is_warning(), "a cushioning hollow is a boon")
	check(outcome.line.contains("Apple") and outcome.line.contains("Helmet"),
		"the line names both the nested item and its container")

	# Empty hollow — dormant, and nothing is applied.
	var empty := PackLayout.new()
	empty.add(helmet, Vector2i(1, 1), 0, helmet_cells)
	check(not cradle.evaluate(helmet, empty).active, "an empty hollow stays dormant")
	apple.durability = 1
	cradle.resolve_send_off(helmet, empty)
	check(apple.durability == 1, "an empty hollow hands out nothing")

	# Adjacent is not inside: an item beside the helmet doesn't count.
	var beside := PackLayout.new()
	beside.add(helmet, Vector2i(1, 1), 0, helmet_cells)
	beside.add(apple, Vector2i(4, 1), 0, [Vector2i(4, 1)] as Array[Vector2i])
	check(not cradle.evaluate(helmet, beside).active, "a neighbour is not 'within'")

	# Poking in: a 2x1 item half in the hollow and half out is not contained.
	var poking := PackLayout.new()
	poking.add(helmet, Vector2i(1, 1), 0, helmet_cells)
	poking.add(apple, Vector2i(2, 2), 0, [Vector2i(2, 2), Vector2i(2, 3)] as Array[Vector2i])
	check(not cradle.evaluate(helmet, poking).active,
		"an item only partly in the hollow isn't contained")

	# Trait filter: only listed traits are affected.
	var picky := ContainsItemEffect.new()
	picky.trait_names = ["liquid"] as Array[String]
	picky.durability_delta = 1
	check(not picky.evaluate(helmet, nested).active, "the wrong nested trait doesn't fire")
	picky.trait_names = ["fragile"] as Array[String]
	check(picky.evaluate(helmet, nested).active, "a listed nested trait fires")

	# A squashing hollow docks the nested item and reads as a mistake.
	var squash := ContainsItemEffect.new()
	squash.durability_delta = -1
	apple.durability = 3
	squash.resolve_send_off(helmet, nested)
	check(apple.durability == 2, "a squashing hollow docks the nested item")
	check(squash.get_violation_message(helmet, nested).contains("Apple"),
		"a squashing hollow reaches the mistakes modal")

	# The live half: a stat bonus while the hollow is filled, no durability moved.
	var stowed := ContainsItemEffect.new()
	stowed.utility_bonus = 1
	apple.durability = 3
	helmet.durability = 5
	check(stowed.live_bonus(helmet, nested).get("utility", 0) == 1,
		"a filled hollow grants its live stat bonus")
	check(stowed.live_bonus(helmet, empty).is_empty(), "an empty hollow grants nothing")
	stowed.resolve_send_off(helmet, nested)
	check(apple.durability == 3 and helmet.durability == 5,
		"a live-only hollow moves no durability at send-off")
	check(stowed.get_violation_message(helmet, nested) == "", "a live bonus is not a mistake")

	# Rotation is already baked into the placed cells: a boot turned on its side still
	# has its hollow, and the rule doesn't care which way round it is.
	var boot := _item("boots", ["armor"])
	boot.display_name = "Boots"
	var turned := PackLayout.new()
	turned.add(boot, Vector2i(0, 0), 1, [Vector2i(0, 0), Vector2i(0, 1),
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)] as Array[Vector2i])
	turned.add(apple, Vector2i(1, 1), 0, [Vector2i(1, 1)] as Array[Vector2i])
	var in_boot := turned.items_within(boot)
	check(in_boot.size() == 1 and in_boot[0] == apple,
		"a rotated hollow still contains what's inside it")

	# Purity: asking never moves anything.
	apple.durability = 4
	for _i in range(5):
		cradle.evaluate(helmet, nested)
	check(apple.durability == 4, "evaluate never mutates the nested item either")


# --- describe() -----------------------------------------------------------------

func _test_describe() -> void:
	var above := ClearAboveEffect.new()
	check(above.describe() != "", "ClearAboveEffect describes itself")
	var adj := NoAdjacentTraitEffect.new()
	adj.trait_names = ["fire"] as Array[String]
	check(adj.describe() != "", "a configured NoAdjacentTraitEffect describes itself")
	# An unconfigured adjacency rule stays silent rather than printing a broken line.
	check(NoAdjacentTraitEffect.new().describe() == "", "an unset adjacency rule says nothing")
	var in_bag := NoTraitInBagEffect.new()
	in_bag.trait_names = ["sharp"] as Array[String]
	check(in_bag.describe().contains("sharp"), "a whole-bag rule names the trait it forbids")
	check(NoTraitInBagEffect.new().describe() == "", "an unset whole-bag rule says nothing")
	var needs := RequiresAdjacentTraitEffect.new()
	needs.trait_names = ["armor"] as Array[String]
	check(needs.describe().contains("armor"), "a requirement names the trait it wants")
	check(RequiresAdjacentTraitEffect.new().describe() == "", "an unset requirement says nothing")
	var hollow_rule := ContainsItemEffect.new()
	hollow_rule.durability_delta = 1
	check(hollow_rule.describe().contains("inside"), "a hollow describes what it does for what's in it")
	check(ContainsItemEffect.new().describe() == "", "a hollow that gives nothing says nothing")


# --- evaluate(): the pure hook ---------------------------------------------------

## The property the whole live-warning system rests on: asking a rule what it would do
## must never actually do it. If evaluate() mutated, the packing screen would wear the
## bag out just by redrawing after every drag.
func _test_evaluate_is_pure() -> void:
	var effect := ClearAboveEffect.new()
	effect.penalty = 2

	var fragile := _item("egg", ["fragile"])
	fragile.durability = 5
	var crushed := PackLayout.new()
	crushed.add(fragile, Vector2i(1, 3), 0, [Vector2i(1, 3)] as Array[Vector2i])
	crushed.add(_item("rock", []), Vector2i(1, 2), 0, [Vector2i(1, 2)] as Array[Vector2i])

	# Evaluate repeatedly — a mutating implementation would drain it.
	for _i in range(5):
		effect.evaluate(fragile, crushed)
	check(fragile.durability == 5, "evaluate never mutates the item, however often it's asked")

	var outcome := effect.evaluate(fragile, crushed)
	check(outcome.active, "a crushed item's rule reports itself as firing")
	check(outcome.durability_delta == -2, "the outcome carries the penalty as a negative delta")
	check(outcome.is_warning(), "a firing rule that costs durability is a warning")
	check(not outcome.is_boon(), "a penalty is not a boon")
	check(outcome.line != "", "a firing rule explains itself")
	check(outcome.line.contains("rock"), "the explanation names the item doing the crushing")

	# Clear board — dormant, and silent.
	var open := PackLayout.new()
	open.add(fragile, Vector2i(1, 3), 0, [Vector2i(1, 3)] as Array[Vector2i])
	var quiet := effect.evaluate(fragile, open)
	check(not quiet.active, "a rule nothing triggers stays dormant")
	check(not quiet.is_warning(), "a dormant rule is not a warning")
	check(quiet.line == "", "a dormant rule says nothing")


## The three appliers are thin readers of evaluate(), so each must agree with it. This
## is what stops the amber warning from ever disagreeing with the send-off penalty.
func _test_appliers_agree_with_evaluate() -> void:
	var effect := NoAdjacentTraitEffect.new()
	effect.trait_names = ["fire"] as Array[String]
	effect.penalty = 2

	var victim := _item("cloth", ["fragile"])
	var layout := PackLayout.new()
	layout.add(victim, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	layout.add(_item("torch", ["fire"]), Vector2i(3, 2), 0, [Vector2i(3, 2)] as Array[Vector2i])

	var predicted := effect.evaluate(victim, layout)
	victim.durability = 5
	effect.resolve_send_off(victim, layout)
	check(victim.durability == 5 + predicted.durability_delta,
		"resolve_send_off applies exactly the durability evaluate predicted")
	check(effect.get_violation_message(victim, layout) == predicted.line,
		"the send-off mistakes modal shows the same line the live warning does")

	# A boon must never be reported as a mistake, however loudly it fires.
	var blanket_rule := ProtectAdjacentItemEffect.new()
	blanket_rule.trait_names = ["fragile"] as Array[String]
	blanket_rule.penalty = 1
	var blanket := _item("blanket", ["warmth"])
	blanket.durability = 3
	var padded := PackLayout.new()
	padded.add(blanket, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	padded.add(_item("egg", ["fragile"]), Vector2i(3, 2), 0, [Vector2i(3, 2)] as Array[Vector2i])
	var boon := blanket_rule.evaluate(blanket, padded)
	check(boon.is_boon() and not boon.is_warning(), "a durability gain is a boon, not a warning")
	check(blanket_rule.get_violation_message(blanket, padded) == "",
		"a boon never reaches the mistakes modal")

	# A live stat bonus reaches live_bonus and leaves durability alone.
	var warm := NeighborStatBoostEffect.new()
	warm.trait_names = ["fire"] as Array[String]
	warm.food_bonus = 4
	var bread := _item("bread", ["food"])
	bread.durability = 3
	var fireside := PackLayout.new()
	fireside.add(bread, Vector2i(2, 2), 0, [Vector2i(2, 2)] as Array[Vector2i])
	fireside.add(_item("torch", ["fire"]), Vector2i(3, 2), 0, [Vector2i(3, 2)] as Array[Vector2i])
	warm.resolve_send_off(bread, fireside)
	check(bread.durability == 3, "a live-only rule docks nothing at send-off")
	check(warm.get_violation_message(bread, fireside) == "",
		"a live stat bonus is never a mistake")

	# NoRotationEffect fires on the configured turn and names it in words.
	var upright_only := NoRotationEffect.new()
	upright_only.rotate = 2
	upright_only.penalty = 1
	check(_wear_one("wine", ["liquid"], upright_only, 2) == 1, "the forbidden turn docks")
	check(_wear_one("wine", ["liquid"], upright_only, 0) == 0, "any other turn is free")
	check(upright_only.describe().contains("upside down"),
		"the rotation rule describes the forbidden turn in words, not a step number")


# --- BagGrid.evaluate_board: the live sweep ---------------------------------------

## The one entry point PackingScene calls after every placement change. It must hand
## back both halves — the stat bonus and the firing rules — off a single snapshot.
func _test_board_evaluation() -> void:
	var bag := (preload("res://scenes/packing/BagGrid.tscn") as PackedScene).instantiate() as BagGrid
	add_child(bag)
	bag.resize_board(6, 6)

	var crush := ClearAboveEffect.new()
	crush.penalty = 1
	crush.rows = 1

	var cheese := ItemData.new()
	cheese.id = "cheese"
	cheese.display_name = "Cheese Wedge"
	cheese.shape = [Vector2i.ZERO] as Array[Vector2i]
	cheese.effects = [crush] as Array[ItemEffect]
	var cheese_view := (preload("res://scenes/packing/DraggableItem.tscn") as PackedScene).instantiate() as DraggableItem
	add_child(cheese_view)
	var cheese_copy := cheese.make_owned_copy()
	cheese_view.setup(cheese_copy)
	bag.place(cheese_view, Vector2i(2, 2))

	# Nothing on top yet: no firing rules anywhere on the board.
	check(bag.evaluate_board()["outcomes"].is_empty(),
		"an untroubled board reports no firing rules")

	var axe := ItemData.new()
	axe.id = "axe"
	axe.display_name = "Axe"
	axe.shape = [Vector2i.ZERO] as Array[Vector2i]
	var axe_view := (preload("res://scenes/packing/DraggableItem.tscn") as PackedScene).instantiate() as DraggableItem
	add_child(axe_view)
	axe_view.setup(axe.make_owned_copy())
	bag.place(axe_view, Vector2i(2, 1))

	var outcomes: Dictionary = bag.evaluate_board()["outcomes"]
	check(outcomes.has(cheese_copy), "placing something on top makes the rule fire")
	var firing: Dictionary = outcomes.get(cheese_copy, {})
	check(firing.has(crush), "outcomes are keyed by the effect that produced them")
	check((firing[crush] as EffectOutcome).is_warning(), "the firing rule is a warning")
	check((firing[crush] as EffectOutcome).line.contains("Axe"),
		"the live explanation names the offending item")

	# The board sweep must not wear the bag out just by looking at it.
	check(cheese_copy.durability == cheese_copy.max_durability,
		"evaluating the board never docks durability")

	# Move the crusher away and the warning clears.
	bag.remove(axe_view)
	check(bag.evaluate_board()["outcomes"].is_empty(),
		"moving the offending item away clears the warning")

	bag.queue_free()


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
