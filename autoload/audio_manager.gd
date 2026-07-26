extends Node

## Autoload. Thin one-shot SFX player, plus looping background music and the
## two volume buses ("Music", "SFX") the pause menu's sliders control.
## Streams stay unassigned until audio exists, so calling play() early is a
## harmless no-op.

const SFX_PATHS := {
	"place": "res://assets/sfx/place.wav",
	"rotate": "res://assets/sfx/rotate.wav",
	"invalid": "res://assets/sfx/invalid.wav",
	"send": "res://assets/sfx/send.wav",
}

const MUSIC_PATHS := {
	"packing": "res://assets/music/packing_theme.mp3",
	"gathering": "res://assets/music/gathering_theme.mp3",
}

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
## Where the two slider positions persist between runs. Separate from
## SaveManager's file: volume is a device preference, not part of a run.
const SETTINGS_PATH := "user://audio_settings.cfg"

var _players: Dictionary = {}
var _music_player: AudioStreamPlayer
var _current_music: String = ""


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)

	for key in SFX_PATHS:
		var player := AudioStreamPlayer.new()
		player.name = "SFX_%s" % key
		player.bus = SFX_BUS
		if ResourceLoader.exists(SFX_PATHS[key]):
			player.stream = load(SFX_PATHS[key])
		add_child(player)
		_players[key] = player

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)

	_load_settings()


## Creates `bus_name` routed to Master if it doesn't already exist. A fresh
## project only ships the Master bus, and these two are otherwise unclaimed —
## idempotent so it's safe to call every time the autoload boots.
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


## Plays a named SFX ("place", "rotate", "invalid", "send").
func play(sfx: String) -> void:
	var player: AudioStreamPlayer = _players.get(sfx)
	if player != null and player.stream != null:
		player.play()


## Starts a named music track ("packing"), looping. A no-op if that track is
## already playing, so a screen can call this every time it shows without
## restarting the loop from the top.
func play_music(track: String) -> void:
	if _current_music == track and _music_player.playing:
		return
	_current_music = track
	var path: String = MUSIC_PATHS.get(track, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		_music_player.stop()
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_current_music = ""
	_music_player.stop()


func set_music_volume(linear: float) -> void:
	_set_bus_volume(MUSIC_BUS, linear)
	_save_settings()


func set_sfx_volume(linear: float) -> void:
	_set_bus_volume(SFX_BUS, linear)
	_save_settings()


func get_music_volume() -> float:
	return _get_bus_volume(MUSIC_BUS)


func get_sfx_volume() -> float:
	return _get_bus_volume(SFX_BUS)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	AudioServer.set_bus_mute(idx, linear <= 0.0001)


func _get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		set_music_volume(1.0)
		set_sfx_volume(1.0)
		return
	set_music_volume(config.get_value("audio", "music", 1.0))
	set_sfx_volume(config.get_value("audio", "sfx", 1.0))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music", get_music_volume())
	config.set_value("audio", "sfx", get_sfx_volume())
	config.save(SETTINGS_PATH)
