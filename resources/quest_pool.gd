class_name QuestPool
extends Resource

## The authored pool of every quest in the game. Adding a quest is two steps:
## write its .tres and drag it into `quests` here — no code changes. RunState
## draws the player's choices from this pool, filtered to the current difficulty.

@export var quests: Array[QuestData] = []


## Every quest sitting at one difficulty tier, in authored order. Nulls and
## quests at other tiers are skipped.
func by_difficulty(tier: int) -> Array[QuestData]:
	var out: Array[QuestData] = []
	for quest in quests:
		if quest != null and quest.difficulty == tier:
			out.append(quest)
	return out
