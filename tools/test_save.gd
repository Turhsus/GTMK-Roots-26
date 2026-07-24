extends Node

## Throwaway harness for the save system: RunState's serialization round-trip, the
## SaveManager file itself, and how both cope with a damaged or outdated file.
## Run: godot --headless --path . res://tools/TestSave.tscn
##
## This writes to the real user:// save path, so it takes a copy of any existing
## save at the start and puts it back at the end — running the tests must not cost
## you the run you were playing.

var failures: int = 0
var _backup: String = ""
var _had_save: bool = false


func _ready() -> void:
	_stash_existing_save()

	_test_round_trip()
	_test_unknown_ids()
	_test_durability_clamp()
	_test_file_cycle()
	_test_bad_file()
	_test_version_mismatch()
	await _test_resume()

	_restore_existing_save()
	RunState.reset()

	if failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


# --- serialization -------------------------------------------------------------

## A run built up by hand, put through to_dict/from_dict, comes back identical.
func _test_round_trip() -> void:
	RunState.reset()
	RunState.completed_count = 2
	RunState.gold = 137
	RunState.days_remaining = 4
	RunState.add_perk(RunState.all_perks[0])
	# Wear one item down so a non-default durability has to survive the trip.
	var blanket := _owned("blanket")
	check(blanket != null, "the fresh inventory has a blanket to wear down")
	blanket.durability = 2

	var before_count := RunState.inventory.size()
	var data := RunState.to_dict()

	# Scribble over the live state, then restore from the snapshot.
	RunState.reset()
	check(RunState.gold != 137, "reset really cleared the run before restoring")

	RunState.from_dict(data)
	check(RunState.completed_count == 2, "completed_count survived the round trip")
	check(RunState.gold == 137, "gold survived, got %d" % RunState.gold)
	check(RunState.days_remaining == 4, "the day clock survived, got %d" % RunState.days_remaining)
	check(RunState.current_difficulty() == 2, "difficulty is derived back from the clears")
	check(RunState.inventory.size() == before_count,
		"the inventory came back whole, %d of %d" % [RunState.inventory.size(), before_count])
	check(RunState.has_perk(RunState.all_perks[0].id), "the earned perk survived")
	var perk_food: int = int(RunState.owned_perks[0].modify_stats({"food": 0}).get("food", 0))
	check(perk_food == 1, "and its effect is live again, got %d" % perk_food)

	var restored_blanket := _owned("blanket")
	check(restored_blanket != null and restored_blanket.durability == 2,
		"per-copy durability survived, got %s" % _durability_of(restored_blanket))
	# The saved copy must be its own instance, not the shared authored resource —
	# otherwise wearing it would corrupt the template for the whole project.
	check(restored_blanket != null and restored_blanket != RunState.find_item("blanket"),
		"a restored item is an owned copy, not the shared template")
	# Templates never carry wear at all: ItemData.durability stays at its -1
	# sentinel until make_owned_copy stamps a real value on the copy.
	check(RunState.find_item("blanket").durability == -1,
		"the shared template is untouched, got %s" % _durability_of(RunState.find_item("blanket")))


## An id that no longer exists is skipped rather than crashing the load — this is
## what happens to an old save after an item or perk is renamed.
func _test_unknown_ids() -> void:
	RunState.reset()
	RunState.from_dict({
		"gold": 10,
		"inventory": [{"id": "apple", "durability": 1}, {"id": "no_such_item", "durability": 1}],
		"perks": ["no_such_perk"],
	})
	check(RunState.inventory.size() == 1, "the unknown item was skipped, got %d" % RunState.inventory.size())
	check(RunState.owned_perks.is_empty(), "the unknown perk was skipped")
	check(RunState.find_item("no_such_item") == null, "an unknown id resolves to null")
	check(RunState.find_quest("no_such_quest") == null, "an unknown quest id resolves to null")
	check(RunState.find_quest("tutorial") == RunState.TUTORIAL, "the tutorial resolves by id")


## A durability saved above the item's current max is clamped down, so retuning an
## item in the editor can't leave old saves carrying over-durable copies.
func _test_durability_clamp() -> void:
	RunState.reset()
	RunState.from_dict({"inventory": [{"id": "apple", "durability": 999}]})
	var apple := _owned("apple")
	check(apple != null and apple.durability == apple.max_durability,
		"an over-durable save is clamped to max, got %s" % _durability_of(apple))


# --- the file ------------------------------------------------------------------

## Write, read back, delete — the whole life of a save file.
func _test_file_cycle() -> void:
	SaveManager.delete_save()
	check(not SaveManager.has_save(), "no save file after a delete")
	check(not SaveManager.request_continue(), "continue refuses when there's nothing to continue")

	RunState.reset()
	RunState.gold = 88
	SaveManager.save_game({"phase": "gather", "gather_day": 3, "gather_days": 5})
	check(SaveManager.has_save(), "the save file exists after a save")

	# Wipe the live run so the values can only come from disk.
	RunState.reset()
	check(SaveManager.request_continue(), "continue accepts a good save")
	check(RunState.gold == 88, "the run was restored from disk, gold %d" % RunState.gold)

	var loop := SaveManager.consume_loop()
	check(String(loop.get("phase", "")) == "gather", "the loop phase came back")
	check(int(loop.get("gather_day", 0)) == 3, "the town day came back")
	check(SaveManager.consume_loop().is_empty(), "the loop is consumed only once")

	SaveManager.delete_save()
	check(not SaveManager.has_save(), "the save is gone again")


## A corrupt file is discarded rather than half-loaded, and takes itself out of the
## way so the menu stops offering it.
func _test_bad_file() -> void:
	_write_raw("this is not json {{{")
	check(SaveManager.has_save(), "the corrupt file is on disk to begin with")
	check(not SaveManager.request_continue(), "a corrupt save refuses to load")
	check(not SaveManager.has_save(), "and deletes itself so it can't fail twice")


## A save from a future or past format version is treated the same way.
func _test_version_mismatch() -> void:
	_write_raw(JSON.stringify({"version": SaveManager.SAVE_VERSION + 1, "run": {}, "loop": {}}))
	check(not SaveManager.request_continue(), "a version mismatch refuses to load")
	check(not SaveManager.has_save(), "and is cleaned up")


# --- resuming into the real loop -----------------------------------------------

## The end-to-end path: a saved gather is written, then Main boots against it and
## must come up in town on the saved day rather than on the tutorial.
func _test_resume() -> void:
	SaveManager.autosave_enabled = true
	SaveManager.delete_save()
	RunState.reset()
	RunState.gold = 200
	RunState.completed_count = 1

	var upcoming := RunState.draw_choices()
	check(not upcoming.is_empty(), "there are quests to come back to")
	SaveManager.save_game({
		"phase": "gather",
		"quest_id": "",
		"upcoming_ids": [upcoming[0].id],
		"gather_days": 4,
		"gather_day": 3,
		"is_final_quest": false,
	})

	# From here on, Main is live and would checkpoint over the file as it resumes.
	SaveManager.autosave_enabled = false
	RunState.reset()
	check(SaveManager.request_continue(), "the saved gather loads")

	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var town: Control = main.get_node("%RoadScene")
	var packing: Control = main.get_node("%PackingScene")
	check(town.visible, "a resumed gather comes up on the road (town) screen")
	check(not packing.visible, "and not on the tutorial packing screen")
	check(RunState.gold == 200, "the resumed run kept its gold, got %d" % RunState.gold)
	check(town.get_node("%DayLabel").text.begins_with("Day 3 of 4"),
		"it resumed on the saved day, header reads '%s'" % town.get_node("%DayLabel").text)

	main.queue_free()
	await get_tree().process_frame
	SaveManager.delete_save()


# --- helpers -------------------------------------------------------------------

## Keeps the developer's real save out of the line of fire.
func _stash_existing_save() -> void:
	_had_save = SaveManager.has_save()
	if not _had_save:
		return
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	if file != null:
		_backup = file.get_as_text()
		file.close()


func _restore_existing_save() -> void:
	SaveManager.delete_save()
	if _had_save and not _backup.is_empty():
		_write_raw(_backup)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _owned(id: String) -> ItemData:
	for item in RunState.inventory:
		if item.id == id:
			return item
	return null


## Prints a durability without blowing up on a null, for failure messages.
func _durability_of(item: ItemData) -> String:
	return "none" if item == null else str(item.durability)


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)
