extends Node

## Autoload. The run's meta-progression across quests, sitting a level above
## GameState (which only knows the *current* packing): how many quests have been
## cleared, what difficulty that puts us at, and drawing the next choices.
##
## The loop is: RunState.draw_choices() offers a few quests -> the player packs
## and sends one off -> RunState.register_result() records whether it was cleared
## -> back to draw_choices(), now maybe a tier harder.

## Emitted after a quest is registered, whether or not it was cleared.
signal progress_changed(completed: int, difficulty: int)

const POOL: QuestPool = preload("res://data/quest_pool.tres")
## Difficulty is capped here; past this every quest is drawn from the top tier.
const MAX_DIFFICULTY := 4
## How many quests to lay out for the player to choose between.
const CHOICE_COUNT := 3

## Quests cleared so far. Difficulty is derived from this: one clear per tier.
var completed_count: int = 0
## Ids of quests already cleared. A cleared quest is not offered again until its
## whole tier is exhausted, at which point the tier resets (see draw_choices).
var _cleared_ids: Array[String] = []


## The current difficulty tier: one cleared quest per tier, capped at the top.
func current_difficulty() -> int:
	return mini(completed_count, MAX_DIFFICULTY)


## Records the outcome of a sent-off quest. Only a clear advances difficulty;
## a failed quest can be drawn again straight away.
func register_result(quest: QuestData, success: bool) -> void:
	if success and quest != null:
		if not _cleared_ids.has(quest.id):
			_cleared_ids.append(quest.id)
		completed_count += 1
	progress_changed.emit(completed_count, current_difficulty())


## Up to CHOICE_COUNT quests from the current tier, cleared ones held back until
## the tier runs dry, then the tier resets and is offered fresh. Fewer than three
## may come back if that is all the tier has; an empty tier falls back to the
## nearest one that has quests, so a sparse pool never dead-ends the loop.
func draw_choices() -> Array[QuestData]:
	var tier := POOL.by_difficulty(current_difficulty())
	if tier.is_empty():
		tier = _nearest_tier(current_difficulty())
	if tier.is_empty():
		return []

	var available: Array[QuestData] = []
	for quest in tier:
		if not _cleared_ids.has(quest.id):
			available.append(quest)
	if available.is_empty():
		# Every quest here is cleared: wipe this tier's clears and offer it anew.
		for quest in tier:
			_cleared_ids.erase(quest.id)
		available = tier.duplicate()

	available.shuffle()
	while available.size() > CHOICE_COUNT:
		available.remove_at(available.size() - 1)
	return available


## Back to a fresh run. Also the clean slate the tests lean on.
func reset() -> void:
	completed_count = 0
	_cleared_ids.clear()
	progress_changed.emit(completed_count, current_difficulty())


## The closest tier to `tier` that actually has quests, searching outward (down
## first, since a lower quest is fairer than a higher one when the exact tier is
## empty). Empty only if the whole pool is.
func _nearest_tier(tier: int) -> Array[QuestData]:
	for delta in range(1, MAX_DIFFICULTY + 1):
		var below := POOL.by_difficulty(tier - delta)
		if not below.is_empty():
			return below
		var above := POOL.by_difficulty(tier + delta)
		if not above.is_empty():
			return above
	return []
