class_name QuestSelect
extends Control

## The quest picker. Main hands it the few quests RunState drew for the current
## difficulty; it lays out one card each and, when the player picks one, emits
## quest_chosen. That is the whole job — it holds no state and no draw logic, so
## the same screen serves the first quest and every one after.

signal quest_chosen(quest: QuestData)

const CARD_WIDTH := 300

@onready var header: Label = %Header
@onready var card_row: HBoxContainer = %CardRow


## Lays out a card per quest. Called every time the picker is shown, so it clears
## the previous round first.
func present(quests: Array[QuestData]) -> void:
	header.text = "Quest %d  •  Difficulty %d" % [RunState.completed_count + 1, RunState.current_difficulty()]
	for child in card_row.get_children():
		# Detach as well as free: queue_free() only lands at frame end, and a
		# re-present within the same frame would otherwise stack old cards.
		card_row.remove_child(child)
		child.queue_free()
	if quests.is_empty():
		header.text = "No quests available"
		return
	for quest in quests:
		card_row.add_child(_build_card(quest))


func _build_card(quest: QuestData) -> Control:
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
	title.text = quest.title
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(title)

	var brief := Label.new()
	brief.text = quest.brief
	brief.add_theme_font_size_override("font_size", 15)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(brief)

	var choose := Button.new()
	choose.text = "  Choose  "
	choose.custom_minimum_size = Vector2(0, 44)
	choose.add_theme_font_size_override("font_size", 18)
	choose.pressed.connect(func() -> void: quest_chosen.emit(quest))
	layout.add_child(choose)

	return card
