class_name BriefPanel
extends Control

## The first screen: what the quest is and how long they'll be gone. Reads the
## quest straight off GameState so Main only has to show it and listen for the
## button.

signal start_requested

@onready var title: Label = %Title
@onready var brief: Label = %Brief
@onready var start_button: Button = %StartButton


func _ready() -> void:
	GameState.quest_changed.connect(_on_quest_changed)
	if GameState.current_quest != null:
		_on_quest_changed(GameState.current_quest)
	start_button.pressed.connect(func() -> void: start_requested.emit())


func _on_quest_changed(quest: QuestData) -> void:
	if quest == null:
		return
	title.text = quest.title
	brief.text = quest.brief
