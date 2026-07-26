class_name StatsPanel
extends PanelContainer

## Four live readouts — Food, Health, Combat, Utility — against the quest's
## targets. It reads GameState and nothing else: the bag never talks to it, so a
## stat change from any source (drop, pick-up, "Pack again") lands here for free.
##
## One row per GameState.STAT_KEYS entry, authored in the scene and named after
## the stat. A row is just Name + Value; with no bar to fill, the number's colour
## is the whole "target met" signal, so it is the one thing built in code.

## Seconds for a value to fade to its new colour.
const FILL_TIME := 0.25

## Both read against the tan panel fill (#F3DAB8), so they are the deeper end of
## the amber/green pair rather than the bright one a dark panel wanted.
@export var under_color := Color("a85a24")
@export var met_color := Color("4e7a2e")

@onready var rows: VBoxContainer = %Rows

## Stat key -> { value: Label, tween: Tween }.
var _rows: Dictionary = {}


func _ready() -> void:
	for key in GameState.STAT_KEYS:
		var row := rows.get_node_or_null(NodePath(key.capitalize()))
		if row == null:
			push_warning("StatsPanel: no row for stat '%s'" % key)
			continue
		_rows[key] = {
			"value": row.get_node("Value") as Label,
			"tween": null,
		}
	GameState.stats_changed.connect(_on_stats_changed)
	_apply(GameState.stats, GameState.get_targets(), false)


func _on_stats_changed(stats: Dictionary, targets: Dictionary) -> void:
	_apply(stats, targets, true)


func _apply(stats: Dictionary, targets: Dictionary, animate: bool) -> void:
	for key in _rows:
		var row: Dictionary = _rows[key]
		var label: Label = row["value"]
		var value := int(stats.get(key, 0))
		var target := int(targets.get(key, 0))
		# The number tells the whole truth, including over target or negative.
		label.text = "%d / %d" % [value, target]
		var color: Color = met_color if value >= target else under_color

		if row["tween"] != null and (row["tween"] as Tween).is_valid():
			(row["tween"] as Tween).kill()
			row["tween"] = null
		if not animate:
			_set_value_color(label, color)
			continue
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# A lambda rather than a bound Callable: the tween supplies the Color and
		# the label has to ride along, and GDScript checks a `bind` argument
		# against the *leading* parameter, so `_set_value_color.bind(label)` is a
		# parse error however the two are ordered. The capture is by value, which
		# is what we want — each row binds its own label.
		tween.tween_method(
			func(c: Color) -> void: _set_value_color(label, c),
			label.get_theme_color("font_color"),
			color,
			FILL_TIME)
		row["tween"] = tween


## Recolors one value label. An override rather than `modulate`, because modulate
## multiplies the theme's own font colour instead of replacing it — against the
## tan panel that would darken the amber rather than swap it for green.
func _set_value_color(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
