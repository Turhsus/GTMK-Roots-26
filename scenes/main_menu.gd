class_name MainMenu
extends Control

## The title screen and the project's entry scene. It sits outside the game
## loop on purpose: Main owns brief -> packing -> playout, and this just starts
## it with a scene change, so the loop never has to know a menu exists.

const MAIN_SCENE := "res://scenes/Main.tscn"

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	# Browsers ignore quit() and itch runs in an iframe — the button is a lie there.
	quit_button.visible = not OS.has_feature("web")
	play_button.grab_focus()


func _on_play_pressed() -> void:
	AudioManager.play("send")
	get_tree().change_scene_to_file(MAIN_SCENE)
