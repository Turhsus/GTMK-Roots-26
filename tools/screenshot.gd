extends Node

## Throwaway harness that photographs the game. Boots the real Main scene, jumps
## it to each requested loop phase, and writes one PNG per phase — so a layout,
## theme or art change can be looked at without playing to that screen.
##
## Run (NOT headless — the dummy renderer captures blank frames):
##   godot --path . res://tools/Screenshot.tscn -- --phases packing,gather --out shots
##
##   --phases  comma-separated: packing, playout, gather, select, perk, thank_you.
##             Defaults to all of them.
##   --out     directory for the PNGs; res:// and user:// paths work, as does an
##             absolute one. Defaults to res://build/screenshots (gitignored).
##   --width   longest edge of the saved image, height follows the window's aspect.
##             Defaults to 1280; pass 0 to save at full window resolution.
##   --size    window size to shoot at, as WxH (e.g. 1024x768). The game's design
##             canvas stays 1920x1080 and is scaled to fit, so this is the knob for
##             checking that a screen still reads at a different resolution/aspect.
##
## The phase jump reuses main.gd's own debug jumper, so this harness knows nothing
## about how a screen is built — it only asks for the phase and takes the picture.

const MAIN := preload("res://scenes/Main.tscn")

const ALL_PHASES: Array[String] = ["packing", "playout", "gather", "select", "perk", "thank_you"]
const DEFAULT_OUT := "res://build/screenshots"
const DEFAULT_WIDTH := 1280
## Frames to let a screen settle before the shutter: enough for the layout pass,
## the tray to spawn its items, and any entry tween to land.
const SETTLE_FRAMES := 8

var _main: Control


func _ready() -> void:
	# This runs the real Main scene, which autosaves at every phase boundary — and
	# the jumper below crosses several. Left on, taking screenshots would overwrite
	# whatever run the player was actually playing.
	SaveManager.autosave_enabled = false
	RunState.reset()

	var args := _parse_args()
	var out_dir: String = args["out"]
	var size: Vector2i = args["size"]
	if size != Vector2i.ZERO:
		# The stretch settings do the rest: the 1920x1080 canvas is scaled to fit
		# whatever the window is, so this changes presentation, never layout.
		DisplayServer.window_set_size(size)
		await get_tree().process_frame
	if not _ensure_dir(out_dir):
		push_error("screenshot: could not create %s" % out_dir)
		get_tree().quit(1)
		return

	_main = MAIN.instantiate()
	add_child(_main)
	await get_tree().process_frame

	var written := 0
	for phase in args["phases"]:
		if not ALL_PHASES.has(phase):
			print("  skip  unknown phase '%s'" % phase)
			continue
		_main._on_debug_phase(phase)
		for _i in SETTLE_FRAMES:
			await get_tree().process_frame
		var path := "%s/%s.png" % [out_dir, phase]
		if await _capture(path, int(args["width"])):
			print("  shot  %s" % ProjectSettings.globalize_path(path))
			written += 1
		else:
			print("  FAIL  could not write %s" % path)

	print("%d screenshot(s)" % written)
	get_tree().quit(0 if written > 0 else 1)


## Grabs what is currently on screen and writes it out, downscaled to `width`
## (0 keeps the window's own resolution). Returns whether the file was written.
func _capture(path: String, width: int) -> bool:
	# The texture is only complete once the frame has actually been drawn.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return false
	if width > 0 and image.get_width() > width:
		var height := int(round(width * float(image.get_height()) / float(image.get_width())))
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return image.save_png(path) == OK


## Everything after `--` on the command line, as {phases, out, width}.
func _parse_args() -> Dictionary:
	var parsed := {
		"phases": ALL_PHASES.duplicate(),
		"out": DEFAULT_OUT,
		"width": DEFAULT_WIDTH,
		"size": Vector2i.ZERO,
	}
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var arg: String = args[i]
		# Both "--flag value" and "--flag=value" are accepted; nothing here needs
		# the difference to matter.
		var value := ""
		if arg.contains("="):
			value = arg.get_slice("=", 1)
			arg = arg.get_slice("=", 0)
		elif i + 1 < args.size():
			value = args[i + 1]
		match arg:
			"--phases":
				var phases: Array[String] = []
				for name in value.split(",", false):
					phases.append(name.strip_edges())
				if not phases.is_empty():
					parsed["phases"] = phases
			"--out":
				if value != "":
					parsed["out"] = value.trim_suffix("/")
			"--width":
				if value.is_valid_int():
					parsed["width"] = maxi(int(value), 0)
			"--size":
				var parts := value.to_lower().split("x", false)
				if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
					parsed["size"] = Vector2i(int(parts[0]), int(parts[1]))
	return parsed


func _ensure_dir(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK
