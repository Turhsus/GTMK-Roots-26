extends Node

## Autoload. Reads and writes the single autosave file.
##
## The game autosaves at *phase boundaries* — the start of packing, each day in
## town, and the quest picker — rather than continuously. Those are the moments
## where the state is a clean, describable snapshot: no half-finished drag, no bag
## mid-packing. A load drops the player at the start of that phase.
##
## Two halves make up a save:
##   "run"  — the meta-progression, owned and serialized by RunState.
##   "loop" — where in the loop the player was, owned by main.gd (which screen,
##            which quest, which town day, which three quests are coming up).
##
## Nothing here stores Resources; both halves are ids and numbers. See the note
## above RunState.to_dict for why that matters.
##
## Deliberately not saved: anything between send-off and the end of the playout.
## Send-off already wears the inventory and pays the reward, so a crash during the
## adventure log rewinds to the packing checkpoint and that quest is packed again
## — the on-disk snapshot is from before the send-off, so nothing double-counts.

## The save file. `user://` is the per-platform writable folder Godot gives every
## project (on Windows, %APPDATA%\Godot\app_userdata\<project>\). It is the only
## place an exported game may write — `res://` is read-only once packed.
const SAVE_PATH := "user://save.json"
## Bumped whenever the shape of the file changes. A save written by an older
## version is discarded rather than half-read into a broken run.
const SAVE_VERSION := 1

## The loop half of a save the player chose to continue, held between the menu's
## scene change and Main picking it up (see consume_loop).
var _pending_loop: Dictionary = {}

## Turn off to make save_game a no-op. The test harnesses run the real Main scene,
## which checkpoints as it goes; without this a test run would overwrite whatever
## the player was actually playing.
var autosave_enabled: bool = true


## Whether there is a run to continue — what the menu's Continue button reads.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Writes the current run plus the given loop position. `loop` is built by main.gd;
## everything else is pulled from RunState here so callers never assemble a whole
## save by hand.
func save_game(loop: Dictionary) -> void:
	if not autosave_enabled:
		return
	var payload := {
		"version": SAVE_VERSION,
		"run": RunState.to_dict(),
		"loop": loop,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not write %s (%s)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	# Tab-indented so the file stays readable in a text editor while debugging.
	file.store_string(JSON.stringify(payload, "\t"))
	# Closing now rather than waiting for the handle to fall out of scope: on the
	# web export the close is what schedules the flush to IndexedDB, and the tab
	# can be shut at any moment.
	file.close()


## Loads the saved run into RunState and stashes the loop position for Main to
## pick up after the scene change. Returns false (changing nothing) if there is no
## readable save, so the caller can leave the player on the menu.
func request_continue() -> bool:
	var data := _read()
	if data.is_empty():
		return false
	RunState.from_dict(data.get("run", {}))
	_pending_loop = data.get("loop", {})
	return true


## Main calls this once on boot: the loop position to resume at, or an empty
## dictionary for a fresh run. Clears it on the way out so a later return to the
## menu and a new run don't resume the old position.
func consume_loop() -> Dictionary:
	var loop := _pending_loop
	_pending_loop = {}
	return loop


## Throws the run away — a new run, or a run that reached its end.
func delete_save() -> void:
	_pending_loop = {}
	if not has_save():
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(SAVE_PATH)


## Parses the file, or returns {} if it is missing, corrupt, or from an older
## version. A file we can't use is deleted rather than left to fail again — a
## Continue button that errors every time is worse than one that goes away.
func _read() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s is not valid JSON — discarding." % SAVE_PATH)
		delete_save()
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveManager: save version mismatch — discarding.")
		delete_save()
		return {}
	return data
