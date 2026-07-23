extends Node

## Autoload. Global access point for the game's trait vocabulary — the two
## hand-authored master lists in data/trait_registry.tres (see TraitRegistry).
##
## Items and quests each carry their own `traits` array; those should only ever use
## names that appear in the matching master list here, so there is a single
## spell-checked source of truth. Future quest-requirement logic reads these lists
## to know which traits exist and (later) what number each one carries.
##
## Usage: `Traits.item_traits`, `Traits.quest_traits`, or the membership helpers.

const REGISTRY: TraitRegistry = preload("res://data/trait_registry.tres")


## The item-trait master list, {name: int}. Value is 1 for now.
var item_traits: Dictionary[String, int]:
	get:
		return REGISTRY.item_traits


## The quest-trait master list, {name: int}.
var quest_traits: Dictionary[String, int]:
	get:
		return REGISTRY.quest_traits


func has_item_trait(name: String) -> bool:
	return REGISTRY.has_item_trait(name)


func has_quest_trait(name: String) -> bool:
	return REGISTRY.has_quest_trait(name)
