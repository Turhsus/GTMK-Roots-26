class_name PlayoutScene
extends Control

## The adventure log. Takes the finished list of lines from NarrativeEngine and
## reveals them one at a time, each fading in under the last, scrolling to
## follow. It does no narrative thinking of its own — by the time play() is
## called every word is already decided.
##
## Clicking (or space/enter) drops the remaining lines in at once, because on a
## second or third replay the player wants the ending, not the pacing.

signal pack_again_requested

## Seconds between lines.
const LINE_DELAY := 1.1
## Seconds for one line to fade up.
const FADE_TIME := 0.35

@onready var lines_box: VBoxContainer = %Lines
@onready var scroll: ScrollContainer = %Scroll
@onready var pack_again_button: Button = %PackAgainButton
@onready var hint: Label = %Hint
@onready var timer: Timer = $LineTimer

var _pending: Array[String] = []


func _ready() -> void:
	timer.wait_time = LINE_DELAY
	timer.timeout.connect(_reveal_next)
	pack_again_button.pressed.connect(func() -> void: pack_again_requested.emit())
	_clear()


## Starts a fresh playout. Safe to call again over a running one.
func play(log_lines: Array[String]) -> void:
	_clear()
	_pending = log_lines.duplicate()
	if _pending.is_empty():
		_finish()
		return
	# The first line lands immediately — a beat of empty panel reads as a hang.
	_reveal_next()


func is_playing() -> bool:
	return not _pending.is_empty()


## Drops every remaining line in at once and ends the playout.
func skip() -> void:
	while not _pending.is_empty():
		_add_line(_pending.pop_front(), false)
	_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not is_playing() or not visible:
		return
	var clicked: bool = event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var keyed: bool = event is InputEventKey and event.pressed and not event.echo \
		and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	if clicked or keyed:
		skip()
		get_viewport().set_input_as_handled()


func _reveal_next() -> void:
	if _pending.is_empty():
		_finish()
		return
	_add_line(_pending.pop_front(), true)
	if _pending.is_empty():
		_finish()
	else:
		timer.start()


func _add_line(text: String, animate: bool) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	lines_box.add_child(label)
	if animate:
		label.modulate.a = 0.0
		create_tween().tween_property(label, "modulate:a", 1.0, FADE_TIME)
	_scroll_to_bottom()


## The new label has no size until the container lays out, so the scroll target
## is only correct a frame later.
func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _finish() -> void:
	timer.stop()
	_pending.clear()
	hint.visible = false
	pack_again_button.visible = true
	pack_again_button.grab_focus()


func _clear() -> void:
	timer.stop()
	_pending.clear()
	for child in lines_box.get_children():
		# Detached as well as freed: queue_free() only lands at the end of the
		# frame, and a replay adds its first line before that.
		lines_box.remove_child(child)
		child.queue_free()
	pack_again_button.visible = false
	hint.visible = true
	scroll.scroll_vertical = 0
