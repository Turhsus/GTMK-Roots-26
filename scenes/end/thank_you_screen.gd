class_name ThankYouScreen
extends Control

## The end of a run. Shown once the global day clock has run out and the one final
## quest has played (see main.gd) — there is no gather or picker after it. A quiet
## sign-off with a short tally of how the run went, and a way back to the menu.
##
## Like the other loop screens the copy is filled in code: `show_end()` sets the
## summary line off RunState just before the screen is revealed.

const MAIN_MENU := "res://scenes/menu/MainMenu.tscn"

@onready var summary_label: Label = %SummaryLabel


func _ready() -> void:
	%MenuButton.pressed.connect(_on_menu_pressed)


## Fills the run summary and is called right before the screen is shown, so the
## final quest's result is already banked in RunState.
func show_end() -> void:
	# The run is over, so the autosave goes with it: there is nothing left to
	# continue into, and leaving it would offer a Continue that lands right back
	# on this screen.
	SaveManager.delete_save()
	var cleared := RunState.completed_count
	var quests_word := "quest" if cleared == 1 else "quests"
	summary_label.text = "You cleared %d %s and made it home.\nSafe travels." % [cleared, quests_word]


func _on_menu_pressed() -> void:
	# A fresh run starts from a clean slate, so wipe the meta-progression on the way
	# out rather than trusting the next boot to do it.
	RunState.reset()
	get_tree().change_scene_to_file(MAIN_MENU)
