class_name TownScreen
extends Control

## The gather phase. Between one quest's playout and the next quest's selection,
## the child's parent spends a run of days in town — one shop visit per day —
## buying supplies with gold and selling off whatever won't be needed. The day
## budget is set by the quest just completed (main.gd passes it in); the three
## quests the player will choose from next are drawn up front and previewed here,
## so the shopping has a plan behind it.
##
## Rules (all chosen by the user): one shop visit per day; every day must be spent
## before the loop moves on (no early exit); buying is limited to a shop's own
## themed stock; selling is allowed at any shop for the item's sell_price (half).
##
## Like QuestSelect, the layout is built in code — the .tscn is just the frame
## (header + a scrolling Body the views are rebuilt into).

signal gather_done
## Emitted each time a new town day opens *after* the first (the first is announced
## by begin() returning). Main autosaves on it, so quitting partway through a long
## gather comes back to the right day with the shopping already done.
signal day_started(day: int)

## DEBUG: shows a "Skip gather" button on the town square that ends the whole
## phase at once, no matter how many days are left. Flip to false to remove it.
const DEBUG_SKIP_GATHER: bool = true

const SHOPS: Array[ShopData] = [
	preload("res://data/shops/grocer.tres"),
	preload("res://data/shops/apothecary.tres"),
	preload("res://data/shops/blacksmith.tres"),
]

@onready var day_label: Label = %DayLabel
@onready var gold_label: Label = %GoldLabel
@onready var days_left_label: Label = %DaysLeftLabel
@onready var body: VBoxContainer = %Body

var _total_days: int = 0
var _current_day: int = 0
var _upcoming: Array[QuestData] = []
## The shop currently open, or null while the town square is showing. Held so a
## buy or sell can rebuild the open shop in place with refreshed prices.
var _open_shop: ShopData = null


func _ready() -> void:
	RunState.gold_changed.connect(_on_gold_changed)


## Opens a gather phase of `days` days. `upcoming` is previewed as the quests the
## player will pick from the moment the last day is spent.
##
## `start_day` is for resuming a saved gather: a load reopens the phase partway
## through, on the day the save was written. The days already spent are not
## re-billed to the global clock — they were billed when they were first spent.
func begin(days: int, upcoming: Array[QuestData], start_day: int = 1) -> void:
	_total_days = maxi(days, 1)
	_current_day = clampi(start_day, 1, _total_days)
	_upcoming = upcoming
	_refresh_header()
	_show_square()


# --- days ---------------------------------------------------------------------

## Ends the current day. Every day passed here also ticks the run's global clock
## down (see RunState.spend_day). When this gather's budget runs out the phase is
## over and the loop moves on; otherwise it's back to the square for the next day.
func _end_day() -> void:
	RunState.spend_day()
	_current_day += 1
	if _current_day > _total_days:
		gather_done.emit()
		return
	_refresh_header()
	_show_square()
	day_started.emit(_current_day)


func _refresh_header() -> void:
	day_label.text = "Day %d of %d in town" % [_current_day, _total_days]
	gold_label.text = "%d gold" % RunState.gold
	_refresh_days_left()


## The run's global day clock, shown top-right. Reads straight off RunState so it
## stays right whether a day was spent normally or the gather was skipped.
func _refresh_days_left() -> void:
	var left := maxi(RunState.days_remaining, 0)
	if left <= 1:
		days_left_label.text = "Final days!" if left == 1 else "Time's up"
	else:
		days_left_label.text = "%d days left" % left


func _on_gold_changed(_gold: int) -> void:
	gold_label.text = "%d gold" % RunState.gold


# --- the town square (shop pick) ----------------------------------------------

func _show_square() -> void:
	_open_shop = null
	_clear_body()

	body.add_child(_heading("The road out takes them %d days. Stock up." % _total_days))
	body.add_child(_subheading("Where to today?"))
	var shops_row := HBoxContainer.new()
	shops_row.add_theme_constant_override("separation", 16)
	for shop in SHOPS:
		shops_row.add_child(_build_shop_button(shop))
	body.add_child(shops_row)

	body.add_child(_spacer(16))
	body.add_child(_subheading("Coming up — you'll choose one when you set out:"))
	body.add_child(_build_quest_preview())

	if DEBUG_SKIP_GATHER:
		body.add_child(_spacer(16))
		var skip := Button.new()
		skip.text = "DEBUG: Skip gather"
		skip.custom_minimum_size = Vector2(0, 40)
		skip.pressed.connect(_skip_gather)
		body.add_child(skip)


## DEBUG: ends the gather phase immediately, whatever day it is. Still bills the
## global clock for the days it skips, so the endgame is reachable while testing.
func _skip_gather() -> void:
	for _day in range(_current_day, _total_days + 1):
		RunState.spend_day()
	gather_done.emit()


func _build_shop_button(shop: ShopData) -> Button:
	var button := Button.new()
	button.text = shop.display_name
	button.custom_minimum_size = Vector2(200, 56)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_enter_shop.bind(shop))
	return button


func _build_quest_preview() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	if _upcoming.is_empty():
		row.add_child(_muted("(no quests waiting)"))
		return row
	for quest in _upcoming:
		row.add_child(_build_preview_card(quest))
	return row


func _build_preview_card(quest: QuestData) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(260, 0)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var title := Label.new()
	title.text = quest.title
	title.add_theme_font_size_override("font_size", 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(title)

	var meta := Label.new()
	meta.text = "%d days   •   reward %dg" % [quest.days, quest.gold_reward]
	meta.add_theme_font_size_override("font_size", 13)
	layout.add_child(meta)

	var needs := Label.new()
	needs.text = "Needs: " + _target_summary(quest)
	needs.add_theme_font_size_override("font_size", 13)
	needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(needs)

	return card


# --- a shop (buy / sell) ------------------------------------------------------

func _enter_shop(shop: ShopData) -> void:
	_open_shop = shop
	_clear_body()

	body.add_child(_heading(shop.display_name))
	var blurb := Label.new()
	blurb.text = shop.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)

	body.add_child(_subheading("On the shelves"))
	for item in shop.stock:
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
	leave.pressed.connect(_end_day)
	body.add_child(leave)


func _build_buy_row(item: ItemData) -> Control:
	var row := _trade_row(item.display_name, _stat_summary(item))
	var buy := Button.new()
	buy.text = "Buy   %dg" % item.buy_price
	buy.disabled = RunState.gold < item.buy_price
	buy.pressed.connect(_on_buy.bind(item))
	row.add_child(buy)
	return row


func _build_sell_row(item: ItemData, count: int) -> Control:
	var name_text := item.display_name
	if count > 1:
		name_text += "  x%d" % count
	var row := _trade_row(name_text, _stat_summary(item))
	var sell := Button.new()
	sell.text = "Sell   %dg" % item.sell_price()
	sell.pressed.connect(_on_sell.bind(item))
	row.add_child(sell)
	return row


func _on_buy(item: ItemData) -> void:
	if RunState.spend_gold(item.buy_price):
		RunState.gain(item)
		AudioManager.play("place")
	# Rebuild in place: affordability of every row and the sell list have moved.
	_enter_shop(_open_shop)


func _on_sell(item: ItemData) -> void:
	if RunState.release(item):
		RunState.add_gold(item.sell_price())
		AudioManager.play("send")
	_enter_shop(_open_shop)


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


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


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


## "Food 4, Health 2" for a quest's non-zero targets.
func _target_summary(quest: QuestData) -> String:
	var parts: Array[String] = []
	var targets := quest.get_targets()
	for key in GameState.STAT_KEYS:
		var value := int(targets.get(key, 0))
		if value > 0:
			parts.append("%s %d" % [key.capitalize(), value])
	if parts.is_empty():
		return "just a safe trip"
	return ", ".join(parts)


## The owned inventory folded into {item, count} entries, in first-seen order, so
## the sell list shows one row per distinct item. Owned copies are now distinct
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
