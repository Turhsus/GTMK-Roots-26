class_name PerkRegistry

## The master list of every perk kind in the game — nothing but the list, on purpose.
##
## THIS IS THE ONE PLACE TO ADD OR REMOVE A PERK:
##   1. write the perk's PerkData subclass in resources/perks/
##   2. add (or delete) its class name in the TYPES array below
## That's the whole process. Run._build_perks() builds one instance of each at boot
## (see RunState.all_perks); no .tres, no other file to touch.
##
## A static var, not a const: Godot rejects a bare class name inside a const array
## ("not a constant expression"). Treat TYPES as read-only.
static var TYPES: Array = [
	ForagePerk,
	CraftyPerk,
]
