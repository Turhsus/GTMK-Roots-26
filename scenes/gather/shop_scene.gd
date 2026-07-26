class_name ShopScene
extends Control

## One town shop, opened from the road (RoadScene) for the day's visit. This
## scene is presentation only: its own background art per shop, three trade tabs
## (Buy / Sell / Buy back), and the leave button. All the state — gold, inventory,
## shelf stock, and what was sold this visit — lives with the road / RunState; the
## road listens to the signals below, applies the trade, and calls open() again to
## refresh the rows.
##
## Buy back lists items sold during *this* shop visit only (handed in by the road).
## Buying one back costs the sell price that was paid out, and restores that same
## copy (durability included).
##
## Background art is by convention: res://assets/shops/shop_<shop id>.png
## (1280x720). Drop real art at that path and it shows — until then the flat
## backdrop color stands in.
##
## Like the road, the trade list is built in code — the .tscn is just the frame
## (background + header + a scrolling Body).

enum Tab { BUY, SELL, BUYBACK }

## A buy button was pressed. The road does the actual spend/gain and reopens the
## shop to refresh prices and stock.
signal buy_pressed(item: ItemData)
## A sell button was pressed; same contract as buy_pressed.
signal sell_pressed(item: ItemData)
## Buy back a copy sold earlier in this visit (road restores it for the sell price).
signal buyback_pressed(item: ItemData)
## "Leave — that's the day": the road ends the day and closes this scene.
signal leave_pressed

const BACKGROUND_PATTERN := "res://assets/shops/shop_%s.png"
const TAB_LABELS := ["Buy", "Sell", "Buy back"]

@onready var background_art: TextureRect = %BackgroundArt
@onready var title_label: Label = %TitleLabel
@onready var day_label: Label = %DayLabel
@onready var gold_label: Label = %GoldLabel
@onready var body: VBoxContainer = %Body

## The shop on display, handed in by open(); this scene never picks it.
var _shop: ShopData = null
## Copies sold during this visit, newest last — shown on the Buy back tab.
var _sold_this_visit: Array[ItemData] = []
## Which trade tab is open. Kept across open() refreshes so a buy doesn't yank
## the player back to Buy.
var _tab: Tab = Tab.BUY


func _ready() -> void:
	RunState.gold_changed.connect(_on_gold_changed)


## Shows `shop`. `day_text` is the road's day line ("Day 2 of 3 in town"), repeated
## here since this scene covers the road's header. `sold_this_visit` is the road's
## list of copies sold so far in this visit (Buy back tab). Calling open() again
## on the same shop refreshes it in place without resetting the active tab.
func open(shop: ShopData, day_text: String = "", sold_this_visit: Array = []) -> void:
	_shop = shop
	_sold_this_visit.clear()
	for entry in sold_this_visit:
		if entry is ItemData:
			_sold_this_visit.append(entry)
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
	var grouped := _dedup_sold()
	for entry in grouped:
		body.add_child(_build_buyback_row(entry["item"], entry["count"]))


## One shelf row: the item, how many are left of it, and the buy button. Buying is
## limited only by that count and the purse — as many as the player can afford.
func _build_buy_row(item: ItemData) -> Control:
	var left := RunState.shop_stock(_shop, item)
	var row := _trade_row("%s  x%d" % [item.display_name, left], _stat_summary(item))
	var buy := Button.new()
	buy.text = "Sold out" if left <= 0 else "Buy   %dg" % item.buy_price
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
	var row := _trade_row(name_text, _stat_summary(item))
	var sell := Button.new()
	sell.text = "Sell   %dg" % item.sell_price()
	sell.pressed.connect(sell_pressed.emit.bind(item))
	row.add_child(sell)
	return row


func _build_buyback_row(item: ItemData, count: int) -> Control:
	var price := item.sell_price()
	var name_text := item.display_name
	if count > 1:
		name_text += "  x%d" % count
	var row := _trade_row(name_text, _stat_summary(item))
	var buyback := Button.new()
	buyback.text = "Buy back   %dg" % price
	buyback.disabled = RunState.gold < price
	buyback.pressed.connect(buyback_pressed.emit.bind(item))
	row.add_child(buyback)
	return row


# --- small builders -----------------------------------------------------------

## A name + description row with room for a trade button on the right. The caller
## adds the button.
func _trade_row(name_text: String, desc_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(name_label)

	var desc := Label.new()
	desc.text = desc_text
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 14)
	row.add_child(desc)

	return row


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


## Sold-this-visit copies folded the same way as inventory, so the Buy back tab
## shows one row per item id with a count.
func _dedup_sold() -> Array:
	var result: Array = []
	for item in _sold_this_visit:
		var found := false
		for entry in result:
			if entry["item"].id == item.id:
				entry["count"] += 1
				found = true
				break
		if not found:
			result.append({"item": item, "count": 1})
	return result
