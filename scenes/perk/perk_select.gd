class_name PerkSelect
extends Control

## The lesson screen. After a failed quest's playout, Main hands it the perks that
## address what fell short; it lays out one card each and, when the player picks one,
## emits perk_chosen. Like QuestSelect it holds no state and no offer logic (RunState
## owns that) — the same screen serves whatever lesson the failure surfaces.

signal perk_chosen(perk: PerkData)

const CARD_WIDTH := 320

@onready var header: Label = %Header
@onready var card_row: HBoxContainer = %CardRow


## Lays out a card per offered perk. Called every time the screen is shown, so it
## clears the previous round first. Main only shows this when there is something to
## offer, so an empty list is a defensive case rather than a normal one.
func present(perks: Array[PerkData]) -> void:
	for child in card_row.get_children():
		# Detach as well as free: queue_free() only lands at frame end, and a
		# re-present within the same frame would otherwise stack old cards.
		card_row.remove_child(child)
		child.queue_free()
	if perks.is_empty():
		header.text = "No lesson this time"
		return
	header.text = "A lesson learned"
	for perk in perks:
		card_row.add_child(_build_card(perk))


func _build_card(perk: PerkData) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	card.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)

	var title := Label.new()
	title.text = perk.title
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(title)

	var body := Label.new()
	body.text = perk.description
	body.add_theme_font_size_override("font_size", 15)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)

	var choose := Button.new()
	choose.text = "  Learn this  "
	choose.custom_minimum_size = Vector2(0, 44)
	choose.add_theme_font_size_override("font_size", 18)
	choose.pressed.connect(func() -> void: perk_chosen.emit(perk))
	layout.add_child(choose)

	return card
