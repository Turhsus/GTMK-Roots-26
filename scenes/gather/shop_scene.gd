class_name ShopScene
extends Control

## One town shop, opened from the road (RoadScene) for the day's visit. This
## scene is presentation only: its own background art per shop, four trade tabs
## (Buy / Sell / Buy back / Return), and the leave button. All the state — gold,
## inventory, shelf stock, and what was bought or sold this visit — lives with the
## road / RunState; the road listens to the signals below, applies the trade, and
## calls open() again to refresh the rows.
##
## Buy back lists items sold during *this* shop visit only. Return lists items
## bought during this visit — refunds the buy price and puts one back on the shelf.
##
## The leatherworker (any shop with `sells_bag_upgrade`) swaps its Buy tab for the
## bench: one row offering the next backpack size, or the reason it isn't on offer.
## That shop also omits Return — a fitted pack can't be undone, and he has no
## ItemData purchases to refund. The cheese shop (`offers_cheese_shift`) skips the
## trade tabs entirely and shows only the pick-2-of-3 work shift. Elsewhere the
## four tabs are unchanged.
##
## Background art is by convention: res://assets/shops/shop_<shop id>.png
## (1280x720). Drop real art at that path and it shows — until then the flat
## backdrop color stands in.
##
## Like the road, the trade list is built in code — the .tscn is just the frame
## (background + header + a scrolling Body). Leave sits under the scroll so it
## stays pinned to the bottom of the screen.

enum Tab { BUY, SELL, BUYBACK, RETURN }

## A buy button was pressed. The road does the actual spend/gain and reopens the
## shop to refresh prices and stock.
signal buy_pressed(item: ItemData)
## A sell button was pressed; same contract as buy_pressed.
signal sell_pressed(item: ItemData)
## Buy back a copy sold earlier in this visit (road restores it for the sell price).
signal buyback_pressed(item: ItemData)
## Return a copy bought earlier in this visit (road refunds buy price + restocks).
signal return_pressed(item: ItemData)
## The leatherworker's one trade: buy the next backpack size. Carries no ItemData —
## the road calls RunState.upgrade_bag() and reopens the shop.
signal bag_upgrade_pressed
## The cheese shop's work shift: the player picked exactly two jobs. `selected` maps
## option id ("sell" / "make" / "repair") -> bool. The road applies the rewards and
## ends the day — same as leaving after a normal shop visit.
signal cheese_shift_pressed(selected: Dictionary)
## "Leave — that's the day": the road ends the day and closes this scene.
signal leave_pressed

## Gold from the cheese shop's "Sell some cheese" job.
const CHEESE_SELL_GOLD: int = 5
const CHEESE_OPTION_SELL := "sell"
const CHEESE_OPTION_MAKE := "make"
const CHEESE_OPTION_REPAIR := "repair"

const BACKGROUND_PATTERN := "res://assets/shops/shop_%s.png"
const TAB_LABELS := ["Buy", "Sell", "Buy back", "Return"]
## Pixels per shape cell for shop thumbnails — same idea as the packing tray
## (art sized to the item's footprint), kept smaller so rows stay readable.
const SHOP_CELL := 48.0
## Fixed icon column so every row's art lines up on the left (fits up to 3×3 cells).
const ICON_SLOT := Vector2(SHOP_CELL * 3.0, SHOP_CELL * 3.0)
## Fixed text column so Buy / Sell / Buy back buttons share one vertical edge.
const TEXT_COLUMN_WIDTH := 200.0
## Shared size for Buy / Sell / Buy back so every row's action button lines up.
const TRADE_BUTTON_SIZE := Vector2(140, 40)

@onready var background_art: TextureRect = %BackgroundArt
@onready var title_label: Label = %TitleLabel
@onready var day_label: Label = %DayLabel
@onready var gold_label: Label = %GoldLabel
@onready var body: VBoxContainer = %Body
@onready var leave_button: Button = %LeaveButton


## The shop on display, handed in by open(); this scene never picks it.
var _shop: ShopData = null
## Copies sold during this visit, newest last — shown on the Buy back tab.
var _sold_this_visit: Array[ItemData] = []
## Copies bought during this visit — shown on the Return tab.
var _bought_this_visit: Array[ItemData] = []
## Which trade tab is open. Kept across open() refreshes so a buy doesn't yank
## the player back to Buy.
var _tab: Tab = Tab.BUY
## Cheese-shop pick state, kept across tab switches within one visit. Reset when
## open() starts a new visit (reset_tab).
var _cheese_picks: Dictionary = {
	CHEESE_OPTION_SELL: false,
	CHEESE_OPTION_MAKE: false,
	CHEESE_OPTION_REPAIR: false,
}


func _ready() -> void:
	RunState.gold_changed.connect(_on_gold_changed)
	leave_button.pressed.connect(leave_pressed.emit)


## Shows `shop`. `day_text` is the road's day line ("Day 2 of 3 in town"), repeated
## here since this scene covers the road's header. `sold_this_visit` / `bought_this_visit`
## are the road's same-visit trade lists. Calling open() again on the same shop
## refreshes it in place without resetting the active tab — pass `reset_tab` when
## opening a *new* visit so Buy is always first.
func open(shop: ShopData, day_text: String = "", sold_this_visit: Array = [],
		bought_this_visit: Array = [], reset_tab: bool = false) -> void:
	_shop = shop
	if reset_tab:
		_tab = Tab.BUY
		_cheese_picks = {
			CHEESE_OPTION_SELL: false,
			CHEESE_OPTION_MAKE: false,
			CHEESE_OPTION_REPAIR: false,
		}
	_sold_this_visit.clear()
	for entry in sold_this_visit:
		if entry is ItemData:
			_sold_this_visit.append(entry)
	_bought_this_visit.clear()
	for entry in bought_this_visit:
		if entry is ItemData:
			_bought_this_visit.append(entry)
	title_label.text = shop.display_name
	day_label.text = day_text
	gold_label.text = "%d gold" % RunState.gold
	var art_path := BACKGROUND_PATTERN % shop.id
	background_art.texture = load(art_path) if ResourceLoader.exists(art_path) else null
	_rebuild()


func _on_gold_changed(_gold: int) -> void:
	gold_label.text = "%d gold" % RunState.gold


func _rebuild() -> void:
	_clear_body()

	var blurb := Label.new()
	blurb.text = _shop.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)

	# Cheese shop is shift-only — no Buy/Sell tabs and no Leave. Pick two jobs
	# and "Get to work" applies the rewards and ends the day.
	if _shop.offers_cheese_shift:
		leave_button.visible = false
		body.add_child(_spacer(8))
		_rebuild_cheese_shift()
		return

	leave_button.visible = true
	# Bag upgrades aren't inventory purchases — no Return tab at the leatherworker.
	if _shop.sells_bag_upgrade and _tab == Tab.RETURN:
		_tab = Tab.BUY
	body.add_child(_build_tabs())
	body.add_child(_spacer(8))

	match _tab:
		Tab.BUY:
			_rebuild_buy()
		Tab.SELL:
			_rebuild_sell()
		Tab.BUYBACK:
			_rebuild_buyback()
		Tab.RETURN:
			_rebuild_return()


func _build_tabs() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for i in TAB_LABELS.size():
		if i == Tab.RETURN and _shop.sells_bag_upgrade:
			continue
		var button := Button.new()
		button.text = TAB_LABELS[i]
		button.toggle_mode = true
		button.button_pressed = (_tab == i)
		button.custom_minimum_size = Vector2(120, 40)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_on_tab_pressed.bind(i as Tab))
		row.add_child(button)
	return row


func _on_tab_pressed(tab: Tab) -> void:
	if _tab == tab:
		# Keep the pressed look if they click the already-active tab.
		_rebuild()
		return
	_tab = tab
	_rebuild()


func _rebuild_buy() -> void:
	if _shop.sells_bag_upgrade:
		_rebuild_bag_upgrade()
		return
	body.add_child(_subheading("On the shelves"))
	var items: Array[ItemData] = _shop.items()
	for item in items:
		body.add_child(_build_buy_row(item))
	if items.is_empty():
		body.add_child(_muted("Nothing for sale today."))
	elif _is_sold_out(items):
		body.add_child(_muted("Bare shelves. \"Cart's due in %d %s, love.\""
			% [RunState.days_until_restock(), "day" if RunState.days_until_restock() == 1 else "days"]))


func _rebuild_sell() -> void:
	body.add_child(_subheading("Sell from your pack"))
	var owned := _dedup_inventory()
	if owned.is_empty():
		body.add_child(_muted("Nothing left to sell."))
	else:
		for entry in owned:
			body.add_child(_build_sell_row(entry["item"], entry["count"]))


func _rebuild_buyback() -> void:
	body.add_child(_subheading("Sold this visit"))
	if _sold_this_visit.is_empty():
		body.add_child(_muted("Nothing sold yet — sales from this visit show up here."))
		return
	var grouped := _dedup_list(_sold_this_visit)
	for entry in grouped:
		body.add_child(_build_buyback_row(entry["item"], entry["count"]))


func _rebuild_return() -> void:
	body.add_child(_subheading("Bought this visit"))
	if _bought_this_visit.is_empty():
		body.add_child(_muted("Nothing bought yet — purchases from this visit show up here."))
		return
	var grouped := _dedup_list(_bought_this_visit)
	for entry in grouped:
		body.add_child(_build_return_row(entry["item"], entry["count"]))


## One shelf row: the item, how many are left of it, and the buy button. Buying is
## limited only by that count and the purse — as many as the player can afford.
func _build_buy_row(item: ItemData) -> Control:
	var left := RunState.shop_stock(_shop, item)
	var row := _trade_row(item, "%s  x%d" % [item.display_name, left], _stat_summary(item))
	var buy := _trade_button("Sold out" if left <= 0 else "Buy   %dg" % item.buy_price)
	buy.disabled = left <= 0 or RunState.gold < item.buy_price
	buy.pressed.connect(buy_pressed.emit.bind(item))
	row.add_child(buy)
	return row


## The cheese shop's Buy tab: pick exactly two jobs. Toggle buttons highlight when
## selected; Confirm emits cheese_shift_pressed for the road to apply and end the day.
## Repair is disabled when no blanket remains in the inventory.
func _rebuild_cheese_shift() -> void:
	body.add_child(_subheading("Behind the counter — pick two:"))

	var options: Array = [
		{
			"id": CHEESE_OPTION_SELL,
			"label": "Sell some cheese, earn %d gold." % CHEESE_SELL_GOLD,
			"enabled": true,
			"hint": "",
		},
		{
			"id": CHEESE_OPTION_MAKE,
			"label": "Make some cheese, +1 cheese.",
			"enabled": true,
			"hint": "",
		},
		{
			"id": CHEESE_OPTION_REPAIR,
			"label": "Repair the blanket, +1 durability to blanket.",
			"enabled": _find_owned("blanket") != null,
			"hint": "",
		},
	]
	if not options[2]["enabled"]:
		options[2]["hint"] = "The blanket is gone — nothing left to mend."

	var confirm := Button.new()
	confirm.text = "Get to work"
	confirm.custom_minimum_size = Vector2(0, 48)
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	confirm.add_theme_font_size_override("font_size", 18)
	confirm.disabled = _cheese_pick_count() != 2
	confirm.pressed.connect(func() -> void:
		cheese_shift_pressed.emit(_cheese_picks.duplicate()))

	var font := ThemeDB.fallback_font
	var font_size := 16
	var option_width := 0
	for option in options:
		var text_w := int(font.get_string_size(String(option["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		option_width = maxi(option_width, text_w + 48)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(col)

	var toggles: Dictionary = {}
	for option in options:
		var toggle := Button.new()
		toggle.toggle_mode = true
		toggle.text = option["label"]
		toggle.disabled = not option["enabled"]
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.custom_minimum_size = Vector2(option_width, 48)
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		toggle.add_theme_font_size_override("font_size", font_size)
		var option_id: String = option["id"]
		# Disabled options can't stay selected (e.g. blanket broke mid-visit).
		if not option["enabled"]:
			_cheese_picks[option_id] = false
		toggle.button_pressed = bool(_cheese_picks.get(option_id, false))
		toggles[option_id] = toggle
		toggle.toggled.connect(func(on: bool) -> void:
			_on_cheese_option_toggled(option_id, on, toggles, confirm))
		col.add_child(toggle)
		var hint: String = option["hint"]
		if not hint.is_empty():
			col.add_child(_muted(hint))

	body.add_child(_spacer(12))
	body.add_child(confirm)


func _cheese_pick_count() -> int:
	var count := 0
	for value in _cheese_picks.values():
		if value:
			count += 1
	return count


## Caps the pick at two: a third press is refused, and Confirm only lights at exactly two.
func _on_cheese_option_toggled(
	option_id: String,
	on: bool,
	toggles: Dictionary,
	confirm: Button,
) -> void:
	_cheese_picks[option_id] = on
	if _cheese_pick_count() > 2:
		_cheese_picks[option_id] = false
		var toggle: Button = toggles[option_id]
		toggle.set_pressed_no_signal(false)
	confirm.disabled = _cheese_pick_count() != 2


## First owned inventory copy matching `id`, or null. Gates the blanket repair.
func _find_owned(id: String) -> ItemData:
	for item in RunState.inventory:
		if item != null and item.id == id:
			return item
	return null


## The leatherworker's Buy tab: one row for the next bag size, or the reason there
## isn't one. RunState owns every gate (maxed / already bought this quest / already
## bought today) — this only prints what it's told (see bag_upgrade_blocked_reason).
func _rebuild_bag_upgrade() -> void:
	body.add_child(_subheading("On the bench"))
	if not RunState.bag_upgrade_available():
		body.add_child(_muted(RunState.bag_upgrade_blocked_reason()))
		return

	var current := RunState.bag_cols()
	var next := RunState.next_bag_size()
	var cost := RunState.bag_upgrade_cost()
	var row := _plain_row("A larger pack  %d×%d → %d×%d" % [current, current, next, next],
		"%d more cells to pack into" % [next * next - current * current])
	var buy := _trade_button("Buy   %dg" % cost)
	buy.disabled = RunState.gold < cost
	buy.pressed.connect(bag_upgrade_pressed.emit)
	row.add_child(buy)
	body.add_child(row)


## True when every item here is at zero — the cue for the restock line.
func _is_sold_out(items: Array[ItemData]) -> bool:
	for item in items:
		if RunState.shop_stock(_shop, item) > 0:
			return false
	return true


func _build_sell_row(item: ItemData, count: int) -> Control:
	var name_text := item.display_name
	if count > 1:
		name_text += "  x%d" % count
	var row := _trade_row(item, name_text, _stat_summary(item))
	var sell := _trade_button("Sell   %dg" % item.sell_price())
	sell.pressed.connect(sell_pressed.emit.bind(item))
	row.add_child(sell)
	return row


func _build_buyback_row(item: ItemData, count: int) -> Control:
	var price := item.sell_price()
	var name_text := item.display_name
	if count > 1:
		name_text += "  x%d" % count
	var row := _trade_row(item, name_text, _stat_summary(item))
	var buyback := _trade_button("Buy back   %dg" % price)
	buyback.disabled = RunState.gold < price
	buyback.pressed.connect(buyback_pressed.emit.bind(item))
	row.add_child(buyback)
	return row


func _build_return_row(item: ItemData, count: int) -> Control:
	var name_text := item.display_name
	if count > 1:
		name_text += "  x%d" % count
	var row := _trade_row(item, name_text, _stat_summary(item))
	var ret := _trade_button("Return   %dg" % item.buy_price)
	ret.pressed.connect(return_pressed.emit.bind(item))
	row.add_child(ret)
	return row


# --- small builders -----------------------------------------------------------

func _trade_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = TRADE_BUTTON_SIZE
	return button

## Left-aligned row: fixed icon slot, fixed text column, then the trade button.
## Fixed widths keep every Buy / Sell / Buy back button on the same vertical line.
func _trade_row(item: ItemData, name_text: String, desc_text: String) -> HBoxContainer:
	return _row(_build_item_icon(item), name_text, desc_text)


## The same row with nothing to picture — an empty icon slot holds the column, so the
## leatherworker's bench line sits on the same grid as every shelf row.
func _plain_row(name_text: String, desc_text: String) -> HBoxContainer:
	return _row(_empty_icon_slot(), name_text, desc_text)


func _row(icon: Control, name_text: String, desc_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.custom_minimum_size = Vector2(TEXT_COLUMN_WIDTH, 0)
	text_col.add_theme_constant_override("separation", 2)
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 16)
	text_col.add_child(name_label)

	if desc_text != "":
		var desc := Label.new()
		desc.text = desc_text
		desc.add_theme_font_size_override("font_size", 14)
		text_col.add_child(desc)

	row.add_child(text_col)
	return row


## Thumbnail centered in a fixed ICON_SLOT so differently shaped items don't
## shove the text/button columns around.
func _build_item_icon(item: ItemData) -> Control:
	var slot := _empty_icon_slot()

	var shape_cells := Vector2(item.get_size())
	var art_size := shape_cells * SHOP_CELL
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = art_size
	icon.position = (ICON_SLOT - art_size) * 0.5
	slot.add_child(icon)
	return slot


## The fixed-size hole an item thumbnail sits in, empty. Shared so a row with no art
## behind it still lines its text and button up with the rows that have one.
func _empty_icon_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = ICON_SLOT
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _subheading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	return label


func _muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(1, 1, 1, 0.6)
	return label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _clear_body() -> void:
	for child in body.get_children():
		# Detach and free (queue_free lands at frame end); a rebuild in the same
		# frame — as buying does — would otherwise stack the old rows.
		body.remove_child(child)
		child.queue_free()


# --- summaries ----------------------------------------------------------------

## "Food +2, Health +1" for the non-zero stats an item adds; "" when it adds none.
func _stat_summary(item: ItemData) -> String:
	var parts: Array[String] = []
	var stats := item.get_stats()
	for key in GameState.STAT_KEYS:
		var value := int(stats.get(key, 0))
		if value != 0:
			parts.append("%s +%d" % [key.capitalize(), value])
	return ", ".join(parts)


## The owned inventory folded into {item, count} entries, in first-seen order, so
## the sell list shows one row per distinct item. Owned copies are distinct
## instances (each with its own durability), so entries group by `id` rather than
## by resource identity.
func _dedup_inventory() -> Array:
	var result: Array = []
	for item in RunState.inventory:
		var found := false
		for entry in result:
			if entry["item"].id == item.id:
				entry["count"] += 1
				found = true
				break
		if not found:
			result.append({"item": item, "count": 1})
	return result


## Fold an item list into {item, count} rows by id (first-seen order).
func _dedup_list(items: Array[ItemData]) -> Array:
	var result: Array = []
	for item in items:
		var found := false
		for entry in result:
			if entry["item"].id == item.id:
				entry["count"] += 1
				found = true
				break
		if not found:
			result.append({"item": item, "count": 1})
	return result
