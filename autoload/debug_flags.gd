extends Node

## Runtime debug switches.
##
## These were consts on the screens that read them, which meant flipping one cost
## an edit and a restart — and the two things we iterate on want opposite settings
## (packing work wants the adventure log skipped, story work needs it shown). Here
## they are plain values a pause-menu toggle or a launch flag can change mid-run.
##
## Every flag reads off in an exported build regardless of its default, so the jam
## build can't ship with the playout skipped because a const was left true. Set
## them from the command line for a repeatable launch or a headless harness:
##
##   godot --path . res://scenes/Main.tscn -- --skip-playout=false
##
## Nothing here persists. The flags are launch-scoped on purpose: the alternative
## is a second settings file or leaning on SaveManager, and the player's save has
## no business carrying dev switches.

## Fired when a flag changes, so anything mirroring one can follow it.
signal changed(key: String, value: bool)

## The one place a switch is added: key -> the pause-menu label and the value it
## takes in a debug build. The key doubles as its command-line flag, with
## underscores written as dashes (`skip_playout` -> `--skip-playout`).
const FLAGS := {
	"skip_playout": {
		"label": "Skip adventure log",
		"default": false,
	},
	"durability_report": {
		"label": "Send-off report",
		"default": true,
	},
	"debug_menu": {
		"label": "Debug menu",
		"default": true,
	},
	"quest_picker": {
		"label": "Quest picker shortcut",
		"default": true,
	},
}

## False in an exported build, where every flag reads off no matter what it was
## set to. Also what hides the pause menu's debug entry.
var available: bool = false

var _values: Dictionary = {}


func _ready() -> void:
	available = OS.is_debug_build()
	for key in FLAGS:
		_values[key] = bool(FLAGS[key]["default"])
	_parse_cmdline()


## Whether a switch is on *and* usable — the only way anything should read a flag.
func is_on(key: String) -> bool:
	return available and bool(_values.get(key, false))


func set_flag(key: String, value: bool) -> void:
	if not FLAGS.has(key) or bool(_values.get(key)) == value:
		return
	_values[key] = value
	changed.emit(key, value)


## Command-line overrides, in `--skip-playout=false` form (everything after `--`).
## Accepts false/off/0 as false; any other value is true.
func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var key := arg.get_slice("=", 0).trim_prefix("--").replace("-", "_")
		if not FLAGS.has(key):
			continue
		var raw := arg.get_slice("=", 1).strip_edges().to_lower()
		_values[key] = not (raw in ["false", "off", "0"])
