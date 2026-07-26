extends Node

## Autoload. Custom rat-hand cursor. Idle while free; tilts around the fingertip
## for as long as the left mouse button is held, so clicks read as a press.

const CURSOR_PATH := "res://assets/ui/rat_hand.png"
## Source art is 500px; hardware cursors need to stay small.
const CURSOR_SIZE := 64
## Fingertip on the 500px source — scaled with CURSOR_SIZE below.
const CURSOR_HOTSPOT_SOURCE := Vector2(56, 62)
## Clockwise degrees applied while the button is down.
const PRESS_TILT_DEGREES := -16.0

var _idle: Texture2D
var _pressed: Texture2D
var _hotspot := Vector2.ZERO
var _is_pressed := false


func _ready() -> void:
	_install()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_pressed(event.pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_pressed(false)


func _install() -> void:
	if not ResourceLoader.exists(CURSOR_PATH):
		return
	var tex: Texture2D = load(CURSOR_PATH)
	if tex == null:
		return
	var image := tex.get_image()
	if image == null:
		return
	image.resize(CURSOR_SIZE, CURSOR_SIZE, Image.INTERPOLATE_LANCZOS)
	_hotspot = CURSOR_HOTSPOT_SOURCE * (float(CURSOR_SIZE) / 500.0)
	_idle = ImageTexture.create_from_image(image)
	_pressed = ImageTexture.create_from_image(
		_rotate_around(image, PRESS_TILT_DEGREES, _hotspot)
	)
	_apply(_idle)


func _set_pressed(pressed: bool) -> void:
	if _idle == null or pressed == _is_pressed:
		return
	_is_pressed = pressed
	_apply(_pressed if pressed else _idle)


func _apply(tex: Texture2D) -> void:
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, _hotspot)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_POINTING_HAND, _hotspot)


## Rotates `src` around `pivot` so the fingertip hotspot stays put between the
## idle and pressed frames. Inverse-maps each dest pixel with bilinear sampling.
func _rotate_around(src: Image, degrees: float, pivot: Vector2) -> Image:
	var angle := deg_to_rad(degrees)
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	var w := src.get_width()
	var h := src.get_height()
	var dst := Image.create(w, h, false, Image.FORMAT_RGBA8)
	dst.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var dx := float(x) - pivot.x
			var dy := float(y) - pivot.y
			var sx := cos_a * dx + sin_a * dy + pivot.x
			var sy := -sin_a * dx + cos_a * dy + pivot.y
			if sx < -1.0 or sy < -1.0 or sx > w or sy > h:
				continue
			dst.set_pixel(x, y, _sample_bilinear(src, sx, sy))
	return dst


func _sample_bilinear(src: Image, sx: float, sy: float) -> Color:
	var w := src.get_width()
	var h := src.get_height()
	if sx < 0.0 or sy < 0.0 or sx >= w - 1 or sy >= h - 1:
		var ix := clampi(int(floor(sx)), 0, w - 1)
		var iy := clampi(int(floor(sy)), 0, h - 1)
		if sx < 0.0 or sy < 0.0 or sx >= w or sy >= h:
			return Color(0, 0, 0, 0)
		return src.get_pixel(ix, iy)
	var x0 := int(floor(sx))
	var y0 := int(floor(sy))
	var fx := sx - x0
	var fy := sy - y0
	var c00 := src.get_pixel(x0, y0)
	var c10 := src.get_pixel(x0 + 1, y0)
	var c01 := src.get_pixel(x0, y0 + 1)
	var c11 := src.get_pixel(x0 + 1, y0 + 1)
	return c00.lerp(c10, fx).lerp(c01.lerp(c11, fx), fy)
