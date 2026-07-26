class_name RoadScene
extends Control

## The gather phase. Between one quest's playout and the next quest's selection,
## the child's parent spends a run of days in town — one shop visit per day —
## buying supplies with gold and selling off whatever won't be needed. The day
## budget is set by the quest just completed (main.gd passes it in); the three
## quests the player will choose from next are drawn up front and previewed here,
## so the shopping has a plan behind it.
##
## This scene is the *road*: its own background art, the day/quest preview, and
## the "where to today?" shop prompt. A shop itself is a separate full-screen
## child scene (ShopScene) with its own art — this scene opens it for the day's
## visit, applies the trades it signals back, and closes it when the day ends.
## When a fresh gather begins (day one, not a resume) one travel event may fire
## before anything else — a short road vignette — then the shop prompt shows.
##
## Rules (all chosen by the user): one shop visit per day; every day must be spent
## before the loop moves on (no early exit); buying is limited to a shop's own
## themed stock; each item on a shelf has its own QTY and the player may buy as many
## as they can afford until it runs out; a bare shelf stays bare across gathers and
## only refills on the run's restock clock (RunState.RESTOCK_INTERVAL_DAYS); selling
## is allowed at any shop for the item's sell_price (half). The backpack upgrade is
## sold at the leatherworker and nowhere else — at most one per town day and one per
## quest, since his bench refills when a quest is registered rather than on the day
## clock (see RunState.bag_upgrade_available).
##
## Like QuestSelect, the layout is built in code — the .tscn is just the frame
## (header + a scrolling Body the views are rebuilt into).

signal gather_done
## Emitted each time a new town day opens *after* the first (the first is announced
## by begin() returning). Main autosaves on it, so quitting partway through a long
## gather comes back to the right day with the shopping already done.
signal day_started(day: int)

## DEBUG: shows a "Skip gather" button on the road that ends the whole phase at
## once, no matter how many days are left. Flip to false to remove it.
const DEBUG_SKIP_GATHER: bool = true

## Travel vignettes that can fire when the road loads at the start of a gather —
## at most one per gather, rolled in begin(). A resumed save (start_day > 1) is
## re-opening an old gather, not starting one, so it never re-rolls.
const TRAVEL_EVENTS: Array[TravelEvent] = [
	preload("res://data/travel_events/found_coin_pouch.tres"),
	preload("res://data/travel_events/found_coin.tres"),
]

const TRAVEL_FADE_IN := 0.45
const TRAVEL_FADE_HOLD := 0.9
const TRAVEL_FADE_OUT := 0.45

## The road's background art. Drop the real painting at this path (1280x720) and
## it appears — until then the flat backdrop color stands in.
const BACKGROUND_PATH := "res://assets/backgrounds/road.png"

@onready var background_art: TextureRect = %BackgroundArt
@onready var day_label: Label = %DayLabel
@onready var gold_label: Label = %GoldLabel
@onready var days_left_label: Label = %DaysLeftLabel
@onready var body: VBoxContainer = %Body
@onready var travel_fade: ColorRect = %TravelFade
@onready var shop_scene: ShopScene = %ShopScene

var _total_days: int = 0
var _current_day: int = 0
var _upcoming: Array[QuestData] = []
## The shop currently open (ShopScene showing), or null while the road is showing.
## Held so a buy or sell can rebuild the open shop in place with refreshed prices.
var _open_shop: ShopData = null
## Copies sold during the current shop visit — shown on ShopScene's Buy back tab
## and cleared when leaving or opening a different shop.
var _sold_this_visit: Array[ItemData] = []
## Copies bought during the current shop visit — shown on the Return tab.
var _bought_this_visit: Array[ItemData] = []
## True while the road fade is playing, so nothing can stack another roll / fade.
var _travel_transitioning: bool = false


func _ready() -> void:
	RunState.gold_changed.connect(_on_gold_changed)
	shop_scene.buy_pressed.connect(_on_buy)
	shop_scene.sell_pressed.connect(_on_sell)
	shop_scene.buyback_pressed.connect(_on_buyback)
	shop_scene.return_pressed.connect(_on_return)
	shop_scene.bag_upgrade_pressed.connect(_on_upgrade_bag)
	shop_scene.leave_pressed.connect(_end_day)
	if ResourceLoader.exists(BACKGROUND_PATH):
		background_art.texture = load(BACKGROUND_PATH)


## Opens a gather phase of `days` days. `upcoming` is previewed as the quests the
## player will pick from the moment the last day is spent.
##
## `start_day` is for resuming a saved gather: a load reopens the phase partway
## through, on the day the save was written. The days already spent are not
## re-billed to the global clock — they were billed when they were first spent.
## What the shops have left needs no restoring here: it lives in RunState, which the
## save has already brought back by the time this runs.
func begin(days: int, upcoming: Array[QuestData], start_day: int = 1) -> void:
	_total_days = maxi(days, 1)
	_current_day = clampi(start_day, 1, _total_days)
	_upcoming = upcoming
	_refresh_header()
	# The once-per-gather travel event, rolled the moment the road loads. Only on
	# day one: a mid-gather resume already had its chance. (A save written *on*
	# day one re-rolls when reloaded — accepted, the stakes are a coin.)
	if start_day <= 1:
		var event := _roll_travel_event()
		if event != null:
			_run_travel_event(event)
			return
	_show_road()


# --- days ---------------------------------------------------------------------

## Ends the current day. Every day passed here also ticks the run's global clock
## down (see RunState.spend_day). When this gather's budget runs out the phase is
## over and the loop moves on; otherwise it's back to the road for the next day.
func _end_day() -> void:
	shop_scene.visible = false
	_open_shop = null
	_sold_this_visit.clear()
	_bought_this_visit.clear()
	RunState.spend_day()
	_current_day += 1
	if _current_day > _total_days:
		gather_done.emit()
		return
	_refresh_header()
	_show_road()
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


# --- the road (shop pick) -------------------------------------------------------

func _show_road() -> void:
	_open_shop = null
	shop_scene.visible = false
	_clear_body()

	body.add_child(_heading("The road out takes them %d days. Stock up." % _total_days))
	body.add_child(_subheading("Where to today?"))
	var shops_row := HBoxContainer.new()
	shops_row.add_theme_constant_override("separation", 16)
	for shop in RunState.SHOPS:
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


# --- travel events (when the road loads) ----------------------------------------

## First event whose `chance` roll succeeds, or null. Rolled once per gather, in
## begin() — before any shop is chosen, so events are no longer tied to a shop.
func _roll_travel_event() -> TravelEvent:
	for event in TRAVEL_EVENTS:
		if event != null and randf() < event.chance:
			return event
	return null


## The fade, then the vignette. Split off from begin() so begin stays synchronous
## for its callers; this runs on as a coroutine.
func _run_travel_event(event: TravelEvent) -> void:
	await _play_travel_fade()
	_show_travel_event(event)


## Full-screen fade with the road line before the event card.
func _play_travel_fade() -> void:
	_travel_transitioning = true
	travel_fade.visible = true
	travel_fade.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(travel_fade, "modulate:a", 1.0, TRAVEL_FADE_IN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(TRAVEL_FADE_HOLD)
	tween.tween_property(travel_fade, "modulate:a", 0.0, TRAVEL_FADE_OUT) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished
	travel_fade.visible = false
	_travel_transitioning = false


## Shows the vignette, applies rewards, then Continue opens the day's shop prompt.
func _show_travel_event(event: TravelEvent) -> void:
	_open_shop = null
	shop_scene.visible = false
	_clear_body()

	body.add_child(_heading(event.title))
	var blurb := Label.new()
	blurb.text = event.text
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)

	if event.gold_reward > 0:
		RunState.add_gold(event.gold_reward)
		body.add_child(_subheading("+%d gold" % event.gold_reward))

	body.add_child(_spacer(16))
	var cont := Button.new()
	cont.text = "Head to the shops"
	cont.custom_minimum_size = Vector2(0, 48)
	cont.add_theme_font_size_override("font_size", 18)
	cont.pressed.connect(_show_road)
	body.add_child(cont)


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
	var card := Ui.card()
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


# --- the shop visit (ShopScene child) -------------------------------------------

## Opens (or refreshes) the day's shop. The ShopScene is presentation only — it
## covers the road full-screen with its own art and signals trades back here,
## where the gold, inventory, and purchase counts actually move. Switching shops
## (or opening one from the road) clears the Buy back / Return lists and starts on Buy.
func _enter_shop(shop: ShopData) -> void:
	var fresh_visit := _open_shop != shop
	if fresh_visit:
		_sold_this_visit.clear()
		_bought_this_visit.clear()
	_open_shop = shop
	shop_scene.open(shop, day_label.text, _sold_this_visit, _bought_this_visit, fresh_visit)
	shop_scene.visible = true


## Buys one of `item`: the shelf must have one and the purse must cover it, and only
## then does either move. How many are left is RunState's to track, so a purchase
## outlives the gather it was made in. The gained copy is remembered for Return.
func _on_buy(item: ItemData) -> void:
	if RunState.shop_stock(_open_shop, item) > 0 and RunState.spend_gold(item.buy_price):
		RunState.take_shop_stock(_open_shop, item)
		var bought := RunState.gain(item)
		if bought != null:
			_bought_this_visit.append(bought)
		AudioManager.play("place")
	# Rebuild in place: affordability, stock and the sell list have all moved.
	_enter_shop(_open_shop)


func _on_sell(item: ItemData) -> void:
	var sold := RunState.release(item)
	if sold != null:
		# A same-visit purchase that gets sold can't also be Returned.
		_bought_this_visit.erase(sold)
		RunState.add_gold(sold.sell_price())
		_sold_this_visit.append(sold)
		AudioManager.play("send")
	_enter_shop(_open_shop)


## Buys back one copy sold earlier in this visit for the sell price that was paid
## out, restoring that same instance (durability included).
func _on_buyback(item: ItemData) -> void:
	var sold: ItemData = null
	for copy in _sold_this_visit:
		if copy.id == item.id:
			sold = copy
			break
	if sold == null:
		return
	if not RunState.spend_gold(sold.sell_price()):
		return
	_sold_this_visit.erase(sold)
	RunState.restore(sold)
	AudioManager.play("place")
	_enter_shop(_open_shop)


## The leatherworker's trade: gold for the next backpack size. Not an inventory move
## at all — RunState owns the tier, the once-per-day and once-per-quest gates, and the
## refusal when the purse is short. It does not spend the day, and there is no undo:
## unlike a purchase, a fitted pack can't be returned on the Return tab.
func _on_upgrade_bag() -> void:
	if RunState.upgrade_bag():
		AudioManager.play("place")
		_refresh_header()
	_enter_shop(_open_shop)


## Returns one copy bought earlier in this visit: refunds the buy price, puts the
## unit back on the shelf, and removes that exact copy from the pack.
func _on_return(item: ItemData) -> void:
	var bought: ItemData = null
	for copy in _bought_this_visit:
		if copy.id == item.id:
			bought = copy
			break
	if bought == null:
		return
	if not RunState.release_exact(bought):
		return
	_bought_this_visit.erase(bought)
	RunState.add_gold(bought.buy_price)
	RunState.return_shop_stock(_open_shop, bought)
	AudioManager.play("send")
	_enter_shop(_open_shop)


# --- small builders -----------------------------------------------------------

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
		# frame would otherwise stack the old rows.
		body.remove_child(child)
		child.queue_free()


# --- summaries ----------------------------------------------------------------

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
