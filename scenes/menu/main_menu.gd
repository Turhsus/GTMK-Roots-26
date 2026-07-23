class_name MainMenu
extends Control

## The title screen and the project's entry scene. It sits outside the game
## loop on purpose: Main owns brief -> packing -> playout, and this just starts
## it with a scene change, so the loop never has to know a menu exists.

const MAIN_SCENE := "res://scenes/Main.tscn"

@onready var continue_button: Button = %ContinueButton
@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	# Browsers ignore quit() and itch runs in an iframe — the button is a lie there.
	quit_button.visible = not OS.has_feature("web")

	# Continue is disabled rather than hidden, so the menu doesn't change shape
	# between a first launch and a later one.
	continue_button.disabled = not SaveManager.has_save()
	if continue_button.disabled:
		play_button.grab_focus()
	else:
		continue_button.grab_focus()


## Picks the saved run back up. SaveManager restores RunState here and holds the
## loop position for Main to read once the scene change lands.
func _on_continue_pressed() -> void:
	if not SaveManager.request_continue():
		# The file went missing or wouldn't parse; SaveManager has cleaned it up.
		continue_button.disabled = true
		play_button.grab_focus()
		return
	AudioManager.play("send")
	get_tree().change_scene_to_file(MAIN_SCENE)


## Starts over. The old save goes now rather than being left for the first
## checkpoint to overwrite — quitting before that checkpoint must not resurrect it.
func _on_play_pressed() -> void:
	SaveManager.delete_save()
	RunState.reset()
	AudioManager.play("send")
	get_tree().change_scene_to_file(MAIN_SCENE)
