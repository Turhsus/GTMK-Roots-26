class_name ThankYouScreen
extends Control

## The end of a run. Shown once the global day clock has run out and the one final
## quest has played (see main.gd) — there is no gather or picker after it. A quiet
## sign-off with a short tally of how the run went, and a way back to the menu.
##
## Like the other loop screens the copy is filled in code: `show_end()` sets the
## summary line off RunState just before the screen is revealed.

const MAIN_MENU := "res://scenes/menu/MainMenu.tscn"
const MIN_QUESTS_ATTEMPTED := 4

@onready var title_label: Label = %Title
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
	var cleared: int = RunState.completed_count
	var attempted: int = RunState.attempted_count
	var quests_word := "quest" if cleared == 1 else "quests"
	# A win needs a majority of attempted quests cleared. With no quests attempted
	# at all (e.g. the tutorial itself ran out the clock) there is nothing to judge
	# a win on, so that counts as a loss rather than a vacuous win. A run also needs
	# at least MIN_QUESTS_ATTEMPTED attempts so a short run can't win on a lucky
	# handful of quests.
	var won: bool = attempted >= MIN_QUESTS_ATTEMPTED and cleared * 2 > attempted
	var verdict := "He learned how to be happy and successful." if won else "Maybe you'll raise the next one better."
	title_label.text = "Your Child is a Success!" if won else "Your Child Failed to Thrive!"
	summary_label.text = "You cleared %d %s and made it home.\n%s" % [cleared, quests_word, verdict]


func _on_menu_pressed() -> void:
	# A fresh run starts from a clean slate, so wipe the meta-progression on the way
	# out rather than trusting the next boot to do it.
	RunState.reset()
	get_tree().change_scene_to_file(MAIN_MENU)
