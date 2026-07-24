class_name ShopScene
extends Control

## One town shop, opened from the road (RoadScene) for the day's visit. This
## scene is presentation only: its own background art per shop, the buy/sell
## rows, and the leave button. All the state — gold, inventory, the per-gather
## purchase counts that limit stock — lives with RunState and the RoadScene;
## the road listens to the signals below, applies the trade, and calls open()
## again to refresh the rows.
##
## Background art is by convention: res://assets/backgrounds/shop_<shop id>.png
## (1280x720). Drop real art at that path and it shows — until then the flat
## backdrop color stands in.
##
## Like the road, the trade list is built in code — the .tscn is just the frame
## (background + header + a scrolling Body).

## A buy button was pressed. The road does the actual spend/gain (it owns the
## purchase counts) and reopens the shop to refresh prices and stock.
signal buy_pressed(item: ItemData)
## A sell button was pressed; same contract as buy_pressed.
signal sell_pressed(item: ItemData)
## "Leave — that's the day": the road ends the day and closes this scene.
signal leave_pressed

const BACKGROUND_PATTERN := "res://assets/backgrounds/shop_%s.png"

@onready var background_art: TextureRect = %BackgroundArt
@onready var title_label: Label = %TitleLabel
@onready var day_label: Label = %DayLabel
@onready var gold_label: Label = %GoldLabel
@onready var body: VBoxContainer = %Body

## The shop on display and how many more items it can sell this gather — both
## handed in by open(); this scene never computes them.
var _shop: ShopData = null
var _remaining: int = 0


func _ready() -> void:
	RunState.gold_changed.connect(_on_gold_changed)


## Shows `shop` with `remaining` purchases left this gather. `day_text` is the
## road's day line ("Day 2 of 3 in town"), repeated here since this scene covers
## the road's header. Calling open() again on the same shop refreshes it in place.
func open(shop: ShopData, remaining: int, day_text: String = "") -> void:
	_shop = shop
	_remaining = remaining
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

	if _remaining > 0:
		body.add_child(_subheading("On the shelves — %d in stock" % _remaining))
	else:
		body.add_child(_subheading("On the shelves — sold out"))
	for item in _shop.stock:
		body.add_child(_build_buy_row(item))

	body.add_child(_spacer(8))
	body.add_child(_subheading("Sell from your pack"))
	var owned := _dedup_inventory()
	if owned.is_empty():
		body.add_child(_muted("Nothing left to sell."))
	else:
		for entry in owned:
			body.add_child(_build_sell_row(entry["item"], entry["count"]))

	body.add_child(_spacer(12))
	var leave := Button.new()
	leave.text = "Leave — that's the day"
	leave.custom_minimum_size = Vector2(0, 48)
	leave.add_theme_font_size_override("font_size", 18)
	leave.pressed.connect(leave_pressed.emit)
	body.add_child(leave)


func _build_buy_row(item: ItemData) -> Control:
	var row := _trade_row(item.display_name, _stat_summary(item))
	var buy := Button.new()
	buy.text = "Buy   %dg" % item.buy_price
	buy.disabled = RunState.gold < item.buy_price or _remaining <= 0
	buy.pressed.connect(buy_pressed.emit.bind(item))
	row.add_child(buy)
	return row


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
