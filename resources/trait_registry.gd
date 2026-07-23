class_name TraitRegistry
extends Resource

## The canonical, hand-authored master list of every trait in the game, split into
## the ones items carry and the ones quests carry. Authored as a single .tres
## (data/trait_registry.tres) and reached globally through the Traits autoload.
##
## Each dictionary is keyed on the trait name; the value is a plain int, always 1
## for now. It exists so there is ONE place the correct spelling of every trait
## lives — author an item's or quest's `traits` array against this list and you
## can't drift into "warmth" vs "warm". The int is a placeholder for later: a trait
## may eventually carry a weight or magnitude instead of a bare 1.

## Every trait an item may carry, e.g. {"light": 1, "food": 1, "metal": 1}.
@export var item_traits: Dictionary[String, int] = {}
## Every trait a quest may carry, e.g. {"cold": 1, "combat": 1}. Quest requirements
## will be authored and matched against this vocabulary.
@export var quest_traits: Dictionary[String, int] = {}


## Is `name` a known item trait? Cheap membership check for validation/lookups.
func has_item_trait(name: String) -> bool:
	return item_traits.has(name)


## Is `name` a known quest trait?
func has_quest_trait(name: String) -> bool:
	return quest_traits.has(name)
