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
## Background art is by convention: res://assets/shops/shop_<shop id>.png
## (1280x720). Drop real art at that path and it shows — until then the flat
## backdrop color stands in.
##
## Like the road, the trade list is built in code — the .tscn is just the frame
## (background + header + a scrolling Body).

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
## "Leave — that's the day": the road ends the day and closes this scene.
signal leave_pressed

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

## The shop on display, handed in by open(); this scene never picks it.
var _shop: ShopData = null
## Copies sold during this visit, newest last — shown on the Buy back tab.
var _sold_this_visit: Array[ItemData] = []
## Copies bought during this visit — shown on the Return tab.
var _bought_this_visit: Array[ItemData] = []
## Which trade tab is open. Kept across open() refreshes so a buy doesn't yank
## the player back to Buy.
var _tab: Tab = Tab.BUY


func _ready() -> void:
	RunState.gold_changed.connect(_on_gold_changed)


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

	body.add_child(_spacer(12))
	var leave := Button.new()
	leave.text = "Leave — that's the day"
	leave.custom_minimum_size = Vector2(0, 48)
	leave.add_theme_font_size_override("font_size", 18)
	leave.pressed.connect(leave_pressed.emit)
	body.add_child(leave)


func _build_tabs() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for i in TAB_LABELS.size():
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	row.add_child(_build_item_icon(item))

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
	var slot := Control.new()
	slot.custom_minimum_size = ICON_SLOT
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
