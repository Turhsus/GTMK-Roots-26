class_name DraggableItem
extends Control

## One item on screen. It is exactly its shape's bounding box in size, so a 2x1
## item is 192x96 and its top-left corner lines up with a grid cell corner.
## The node reports a grab and then does as it is told — PackingScene owns the
## drag itself, since only it can see both the bag and the tray.

signal grabbed(view: DraggableItem, grab_offset: Vector2)
## Emitted on a plain click — a press and release that never turns into a drag.
## Unused by PackingScene today (descriptions are hover-only); kept for callers.
signal clicked(view: DraggableItem)
## Right-click while the item is at rest (tray or bag). PackingScene rotates it
## in place — no drag required.
signal rotate_requested(view: DraggableItem)
## Shift+left-click while at rest. PackingScene returns a bagged item to the tray.
signal return_requested(view: DraggableItem)
## Hover enter/exit while at rest. PackingScene shows the item description tip.
signal hover_started(view: DraggableItem)
signal hover_ended(view: DraggableItem)

const HOVER_LIFT := Vector2(0, -6)
## How far the mouse may travel while the button is held before the press stops
## being a click and becomes a drag.
const DRAG_THRESHOLD := 6.0

## Accents for the info panel. It rides the textbox frame like the rest of the
## UI, so these are picked to read against the tan fill (#F3DAB8) — the older
## brighter set was chosen back when the panel drew its own dark box.
const STAT_COLOR := Color("3f6b23")
const WARN_COLOR := Color("9a4f14")
const MUTED_COLOR := Color("6b5d4c")

## Durability bar in the hover/inspect panel (non-single-use only).
const DURA_BAR_FULL := Color("4e7a2e")
const DURA_BAR_MID := Color("a85a24")
const DURA_BAR_LOW := Color("9a3a2a")
const DURA_BAR_TRACK := Color(0.25, 0.2, 0.16, 0.55)

var item: ItemData
## 90-degree clockwise turns applied to `item.shape`.
var rotation_steps: int = 0
var is_dragging: bool = false
## True while a placed item sits in BagGrid's ItemLayer, where sprites can
## visually overlap (a cross-shaped item's empty corner over another item's
## cell). BagGrid disables normal input dispatch there and hit-tests +
## forwards events itself, topmost opaque pixel wins — see set_dragging().
var _external_hit_testing: bool = false

## How big this view draws relative to a board cell. The bag and the tray used to
## share one cell size, which made a 1x3 sword 336 px tall and let three items fill
## the tray. On the board the size is load-bearing — the box has to line up with the
## grid — but in the tray it only has to be readable, so the tray shrinks its copies
## (see ItemTray.TRAY_SCALE) and grabbing one restores it to 1.0.
var display_scale: float = 1.0:
	set(value):
		if is_equal_approx(display_scale, value):
			return
		display_scale = value
		if is_node_ready():
			_refresh()

## A left button is down but hasn't moved far enough to drag yet: releasing now
## is a click, crossing DRAG_THRESHOLD starts the drag.
var _press_active := false
var _press_position := Vector2.ZERO

## All juice animates the icon, never this Control: the node's position and size
## are grid truth (snapping, tests), so cosmetic motion lives in an offset the
## icon adds on top of its resting spot.
var juice_offset := Vector2.ZERO:
	set(value):
		juice_offset = value
		if icon != null:
			icon.position = _icon_base + juice_offset

## Where the icon sits when nothing is animating, recomputed by _refresh().
var _icon_base := Vector2.ZERO
## CPU-side copy of the icon texture, kept only so clicks/rotates can sample
## alpha at the cursor — a cross-shaped sprite's corner cells are transparent
## and must let the click fall through to whatever sits underneath.
var _icon_image: Image = null
## Continuous target angle. Accumulates 90 per rotate so three quarter-turns
## then a fourth spins forward instead of unwinding 270 degrees back to 0.
var _rot_target := 0.0
var _offset_tween: Tween
var _rot_tween: Tween

@onready var icon: TextureRect = $Icon


func setup(source: ItemData) -> void:
	item = source
	if is_node_ready():
		_refresh()


func _ready() -> void:
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))
	_refresh()


## The shape this item currently occupies, after rotation.
func get_shape() -> Array[Vector2i]:
	if item == null:
		return []
	return ItemData.rotate_shape(item.shape, rotation_steps)


func rotate_once() -> void:
	rotation_steps = posmod(rotation_steps + 1, 4)
	_rot_target += 90.0
	_kill(_rot_tween)
	_rot_tween = create_tween()
	_rot_tween.tween_property(icon, "rotation_degrees", _rot_target, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh()


func reset_rotation() -> void:
	if rotation_steps == 0 and _rot_target == 0.0:
		return
	rotation_steps = 0
	_kill(_rot_tween)
	_rot_target = 0.0
	_refresh()


## Called by BagGrid.place()/ItemTray.adopt() as a view crosses between the
## two: only the bag can have items visually overlap, so only there does
## BagGrid need to own dispatch instead of the engine's normal top-control
## search (which can only ever pick one node, not fall through to a sibling).
func set_external_hit_testing(value: bool) -> void:
	_external_hit_testing = value
	_apply_mouse_filter()


func _apply_mouse_filter() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if (is_dragging or _external_hit_testing) \
		else Control.MOUSE_FILTER_STOP


## While dragging the node lives on the drag layer and must not swallow the
## mouse, or the release that ends the drag never reaches PackingScene.
func set_dragging(value: bool) -> void:
	is_dragging = value
	_apply_mouse_filter()
	modulate.a = 0.85 if value else 1.0
	if value:
		# A lifted or mid-shake icon must not carry its offset into the drag.
		_kill(_offset_tween)
		juice_offset = Vector2.ZERO
		# Back to board scale the moment it is picked up: from here the item has to
		# match the grid it is being dropped onto, not the tray it came from. The
		# flow container also stretches rows to their tallest item, so an item can
		# leave it wider or taller than its shape — either way, size must be the
		# shape box again or the snap lands a cell off.
		display_scale = 1.0
		_refresh()


## Slides the icon in from where the item visually was when the player let go,
## so a placement reads as a snap instead of a teleport. The node itself is
## already sitting on its cell — only the icon travels.
func play_snap_from(from_global: Vector2) -> void:
	_kill(_offset_tween)
	juice_offset = from_global - global_position
	_offset_tween = create_tween()
	_offset_tween.tween_property(self, "juice_offset", Vector2.ZERO, 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A quick left-right wobble for a drop that didn't fit.
func play_shake() -> void:
	_kill(_offset_tween)
	juice_offset = Vector2.ZERO
	_offset_tween = create_tween()
	for shove in [8.0, -7.0, 5.0, -3.0, 0.0]:
		_offset_tween.tween_property(self, "juice_offset:x", shove, 0.045)


func _gui_input(event: InputEvent) -> void:
	if is_dragging:
		return
	# Only gate the initial press: once a press has started on an opaque
	# pixel, the motion/release that follows it must keep tracking even if
	# it drifts over a transparent one.
	#
	# And only gate it where items can actually overlap, which is the bag — there
	# BagGrid owns dispatch and has already hit-tested this view before forwarding
	# (see _topmost_opaque_view), so this is a second opinion on the same question.
	# In the tray the flow container lays items side by side and nothing can ever
	# occlude anything, so gating there just makes items hard to pick up: every
	# press that lands on a transparent part of the box is silently dropped, which
	# bites hardest on thin art (crowbar, torch) and on small tray scales.
	if _external_hit_testing and event is InputEventMouseButton and event.pressed \
			and not _press_active and not is_pixel_opaque(event.global_position):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		_press_active = false
		rotate_requested.emit(self)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			accept_event()
			# Shift+click returns a bagged item to the tray — don't start a drag.
			if event.shift_pressed:
				_press_active = false
				return_requested.emit(self)
				return
			_press_active = true
			_press_position = event.position
		elif _press_active:
			# Let go without ever crossing the drag threshold: treat it as a
			# click rather than a drag.
			accept_event()
			_press_active = false
			clicked.emit(self)
	elif event is InputEventMouseMotion and _press_active:
		if event.position.distance_to(_press_position) > DRAG_THRESHOLD:
			_press_active = false
			grabbed.emit(self, _press_position)


func _refresh() -> void:
	if item == null:
		return
	var cell := BagGrid.current_cell_size() * display_scale
	custom_minimum_size = Vector2(ItemData.get_shape_size(get_shape())) * cell
	size = custom_minimum_size
	if icon.texture != item.icon:
		icon.texture = item.icon
		_icon_image = item.icon.get_image() if item.icon != null else null
		if _icon_image != null and _icon_image.is_compressed():
			_icon_image.decompress()
	# The art is drawn for the unrotated shape, so the icon keeps its original
	# box and spins inside ours — a 2x1 sprite turned 90 degrees fills our 1x2.
	var art_size := Vector2(item.get_size()) * cell
	icon.size = art_size
	icon.pivot_offset = art_size * 0.5
	# The rotate tween owns the angle while it runs; everyone else lands it.
	if _rot_tween == null or not _rot_tween.is_running():
		icon.rotation_degrees = _rot_target
	_icon_base = (size - art_size) * 0.5
	icon.position = _icon_base + juice_offset


## The "what would this add" panel: the item's name, every stat it contributes,
## and its flavor line. Static so PackingScene can raise the very same panel on
## hover without redoing the layout.
static func build_info_panel(source: ItemData) -> Control:
	var panel := Ui.card()

	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_%s" % side, INFO_PANEL_PADDING)
	panel.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	pad.add_child(box)

	var name_label := Label.new()
	name_label.text = source.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	box.add_child(name_label)

	var stat_added := false
	var stats := source.get_stats()
	for key in GameState.STAT_KEYS:
		var value := int(stats.get(key, 0))
		if value == 0:
			continue
		stat_added = true
		var row := Label.new()
		row.text = "%s %+d" % [key.capitalize(), value]
		row.add_theme_color_override("font_color", STAT_COLOR)
		box.add_child(row)
	if not stat_added:
		var none_label := Label.new()
		none_label.text = "No stat bonus"
		none_label.add_theme_color_override("font_color", MUTED_COLOR)
		box.add_child(none_label)

	# Durability — single-use is text only; multi-use gets a health bar + trips left.
	if source.max_durability > 1:
		var remaining := source.durability if source.durability >= 0 else source.max_durability
		var dura := Label.new()
		if source.durability >= 0 and source.durability < source.max_durability:
			dura.text = "Durability: %d of %d trips left" % [remaining, source.max_durability]
		else:
			dura.text = "Durability: lasts %d trips" % source.max_durability
		dura.add_theme_color_override("font_color", MUTED_COLOR)
		box.add_child(dura)
		box.add_child(_build_durability_bar(remaining, source.max_durability))
	else:
		var dura := Label.new()
		dura.text = "Single use"
		dura.add_theme_color_override("font_color", MUTED_COLOR)
		box.add_child(dura)

	# Placement rules the item carries (see ItemEffect) — warned here so the durability
	# hit at send-off isn't a surprise. Skipped entirely for a plain item.
	for rule_text in source.effect_descriptions():
		var rule := Label.new()
		rule.text = "⚠ " + rule_text
		rule.add_theme_color_override("font_color", WARN_COLOR)
		rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rule.custom_minimum_size.x = 220
		box.add_child(rule)

	if source.flavor != "":
		var flavor := Label.new()
		flavor.text = source.flavor
		flavor.add_theme_color_override("font_color", MUTED_COLOR)
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor.custom_minimum_size.x = 220
		box.add_child(flavor)

	return panel


## Thin fill bar for the inspect panel. Ratio drives color (green → amber → red).
static func _build_durability_bar(remaining: int, maximum: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxi(maximum, 1)
	bar.value = clampi(remaining, 0, int(bar.max_value))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var track := StyleBoxFlat.new()
	track.bg_color = DURA_BAR_TRACK
	track.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	var ratio := clampf(float(remaining) / float(maxi(maximum, 1)), 0.0, 1.0)
	if ratio > 0.5:
		fill.bg_color = DURA_BAR_FULL
	elif ratio > 0.25:
		fill.bg_color = DURA_BAR_MID
	else:
		fill.bg_color = DURA_BAR_LOW
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## True unless the given point (viewport space) lands on a transparent icon
## pixel. Used to let a press fall through a cross-shaped sprite's empty
## corner cells to whatever is stacked underneath. Errs opaque (true) when
## there's nothing to sample, so a missing/uncached image never blocks input.
## Public: BagGrid hit-tests overlapping placed items against this directly.
func is_pixel_opaque(global_pos: Vector2) -> bool:
	if icon == null or icon.texture == null or _icon_image == null:
		return true
	if icon.size.x <= 0.0 or icon.size.y <= 0.0:
		return true
	var tex_size := Vector2(icon.texture.get_size())
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return true
	# Icon uses STRETCH_KEEP_ASPECT_CENTERED: the art is scaled to fit inside
	# icon.size preserving aspect, then centered — so the drawn rect is
	# usually smaller than icon.size and letterboxed on one axis.
	var local: Vector2 = icon.get_global_transform().affine_inverse() * global_pos
	var fit_scale: float = minf(icon.size.x / tex_size.x, icon.size.y / tex_size.y)
	var disp_size := tex_size * fit_scale
	var disp_offset := (icon.size - disp_size) * 0.5
	var px := (local - disp_offset) / fit_scale
	if px.x < 0.0 or px.y < 0.0 or px.x >= tex_size.x or px.y >= tex_size.y:
		return false
	return _icon_image.get_pixel(int(px.x), int(px.y)).a > 0.05


func _on_hover_changed(hovered: bool) -> void:
	set_hovered(hovered)


## Used by PackingScene (tray, normal mouse_entered) and BagGrid (synthetic
## hover while placed items ignore the mouse for overlap hit-testing).
func set_hovered(hovered: bool) -> void:
	if is_dragging or icon == null:
		return
	if hovered:
		hover_started.emit(self)
	else:
		hover_ended.emit(self)
	_kill(_offset_tween)
	_offset_tween = create_tween()
	_offset_tween.tween_property(self, "juice_offset", HOVER_LIFT if hovered else Vector2.ZERO, 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
