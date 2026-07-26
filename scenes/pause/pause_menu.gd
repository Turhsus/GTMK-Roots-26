class_name PauseMenu
extends Control

## Overlay pause menu for the in-run loop (Main). Opened by Escape from Main;
## lives with PROCESS_MODE_WHEN_PAUSED so it keeps working while the tree is paused.
## Emits requests upward — Main owns scene changes and phase jumps.

signal resume_requested
signal home_requested
signal quit_requested
signal debug_phase_requested(phase: String)

@onready var main_panel: VBoxContainer = %MainPanel
@onready var debug_panel: VBoxContainer = %DebugPanel
@onready var debug_toggles: VBoxContainer = %DebugToggles
@onready var resume_button: Button = %ResumeButton
@onready var home_button: Button = %HomeButton
@onready var quit_button: Button = %QuitButton
@onready var debug_button: Button = %DebugButton
@onready var debug_back_button: Button = %DebugBackButton
@onready var add_gold_button: Button = %AddGoldButton
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	home_button.pressed.connect(func() -> void: home_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	debug_button.pressed.connect(_show_debug)
	debug_back_button.pressed.connect(_show_main)
	add_gold_button.pressed.connect(_on_add_gold)

	quit_button.visible = not OS.has_feature("web")
	debug_button.visible = DebugFlags.is_on("debug_menu")

	music_slider.value = AudioManager.get_music_volume()
	sfx_slider.value = AudioManager.get_sfx_volume()
	music_slider.value_changed.connect(AudioManager.set_music_volume)
	sfx_slider.value_changed.connect(AudioManager.set_sfx_volume)

	for child in %DebugPhases.get_children():
		if child is Button:
			var phase := String(child.get_meta("phase", ""))
			if not phase.is_empty():
				child.pressed.connect(_on_debug_phase.bind(phase))

	_build_debug_toggles()
	_show_main()


## One switch per DebugFlags entry, built here rather than authored in the scene so
## adding a flag to that dictionary is the only step. "debug_menu" is skipped: it
## gates this panel, so a toggle for it inside the panel could not be undone.
func _build_debug_toggles() -> void:
	for key in DebugFlags.FLAGS:
		if key == "debug_menu":
			continue
		var toggle := CheckButton.new()
		toggle.text = String(DebugFlags.FLAGS[key]["label"])
		toggle.button_pressed = DebugFlags.is_on(key)
		toggle.toggled.connect(func(on: bool) -> void: DebugFlags.set_flag(key, on))
		debug_toggles.add_child(toggle)


func open() -> void:
	visible = true
	_show_main()
	resume_button.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if debug_panel.visible:
			_show_main()
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	main_panel.visible = true
	debug_panel.visible = false
	resume_button.grab_focus()


func _show_debug() -> void:
	main_panel.visible = false
	debug_panel.visible = true
	debug_back_button.grab_focus()


func _on_debug_phase(phase: String) -> void:
	debug_phase_requested.emit(phase)


func _on_add_gold() -> void:
	RunState.add_gold(100)
