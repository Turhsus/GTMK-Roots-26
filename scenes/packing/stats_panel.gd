class_name StatsPanel
extends PanelContainer

## Four live bars — Food, Health, Attack, Defense — filling toward the quest's
## targets. It reads GameState and nothing else: the bag never talks to it, so a
## stat change from any source (drop, pick-up, "Pack again") lands here for free.
##
## One row per GameState.STAT_KEYS entry, authored in the scene and named after
## the stat. Bar colors are built in code so a row is just Label + ProgressBar.

## Seconds for a bar to slide to its new fill.
const FILL_TIME := 0.25

@export var under_color := Color("c08040")
@export var met_color := Color("7aa356")
## Light enough to stay visible against the panel — an empty bar still has to
## read as a bar.
@export var track_color := Color("453529")

@onready var rows: VBoxContainer = %Rows

## Stat key -> { bar: ProgressBar, value: Label, fill: StyleBoxFlat, tween: Tween }.
var _rows: Dictionary = {}


func _ready() -> void:
	for key in GameState.STAT_KEYS:
		var row := rows.get_node_or_null(NodePath(key.capitalize()))
		if row == null:
			push_warning("StatsPanel: no row for stat '%s'" % key)
			continue
		var bar: ProgressBar = row.get_node("Bar")
		_rows[key] = {
			"bar": bar,
			"value": row.get_node("Header/Value") as Label,
			"fill": _style_bar(bar),
			"tween": null,
		}
	GameState.stats_changed.connect(_on_stats_changed)
	_apply(GameState.stats, GameState.get_targets(), false)


func _on_stats_changed(stats: Dictionary, targets: Dictionary) -> void:
	_apply(stats, targets, true)


func _apply(stats: Dictionary, targets: Dictionary, animate: bool) -> void:
	for key in _rows:
		var row: Dictionary = _rows[key]
		var bar: ProgressBar = row["bar"]
		var value := int(stats.get(key, 0))
		var target := int(targets.get(key, 0))
		# A target of 0 would make every fill a division by zero; the bar still
		# has to read as full, so treat it as a 1-point goal.
		bar.max_value = maxi(target, 1)
		# The number tells the whole truth (over target, or negative); the bar
		# only ever draws between empty and full.
		(row["value"] as Label).text = "%d / %d" % [value, target]
		var fill := clampf(value, 0.0, bar.max_value)
		var color: Color = met_color if value >= target else under_color
		var stylebox: StyleBoxFlat = row["fill"]

		if row["tween"] != null and (row["tween"] as Tween).is_valid():
			(row["tween"] as Tween).kill()
			row["tween"] = null
		if not animate:
			bar.value = fill
			stylebox.bg_color = color
			continue
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(bar, "value", fill, FILL_TIME)
		tween.tween_property(stylebox, "bg_color", color, FILL_TIME)
		row["tween"] = tween


## Gives the bar its track and fill boxes and hands back the fill, which is the
## one the tween recolors as a stat crosses its target.
func _style_bar(bar: ProgressBar) -> StyleBoxFlat:
	var track := StyleBoxFlat.new()
	track.bg_color = track_color
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = under_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	return fill
