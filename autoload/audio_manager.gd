extends Node

## Autoload. Thin one-shot SFX player. Streams stay unassigned until audio
## exists, so calling play() early is a harmless no-op.

const SFX_PATHS := {
	"place": "res://assets/sfx/place.wav",
	"rotate": "res://assets/sfx/rotate.wav",
	"invalid": "res://assets/sfx/invalid.wav",
	"send": "res://assets/sfx/send.wav",
}

var _players: Dictionary = {}


func _ready() -> void:
	for key in SFX_PATHS:
		var player := AudioStreamPlayer.new()
		player.name = "SFX_%s" % key
		if ResourceLoader.exists(SFX_PATHS[key]):
			player.stream = load(SFX_PATHS[key])
		add_child(player)
		_players[key] = player


## Plays a named SFX ("place", "rotate", "invalid", "send").
func play(sfx: String) -> void:
	var player: AudioStreamPlayer = _players.get(sfx)
	if player != null and player.stream != null:
		player.play()
