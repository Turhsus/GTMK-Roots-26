class_name QuestPool
extends Resource

## The authored pool of every quest in the game. Adding a quest is two steps:
## write its .tres and drag it into `quests` here — no code changes. RunState
## draws the player's choices from this pool, filtered to the current difficulty.

@export var quests: Array[QuestData] = []


## The quest with this id, or null if the pool has none. Used to turn the ids in a
## save file back into quests (see RunState.find_quest).
func find_by_id(id: String) -> QuestData:
	for quest in quests:
		if quest != null and quest.id == id:
			return quest
	return null


## Every quest sitting at one difficulty tier, in authored order. Nulls and
## quests at other tiers are skipped.
func by_difficulty(tier: int) -> Array[QuestData]:
	var out: Array[QuestData] = []
	for quest in quests:
		if quest != null and quest.difficulty == tier:
			out.append(quest)
	return out
