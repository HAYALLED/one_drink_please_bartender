extends Node

const PATH := "user://settings.cfg"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

var language := ""
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 1.0
var fullscreen := false


func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply()


func load_settings() -> void:
	var config := ConfigFile.new()
	var loaded := config.load(PATH) == OK
	language = String(config.get_value("general", "language", "")) if loaded else ""
	if language.is_empty() or not Loc.has_language(language):
		language = Loc.default_language()
	master_volume = clampf(float(config.get_value("audio", "master", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value("audio", "music", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
	fullscreen = bool(config.get_value("video", "fullscreen", false))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("general", "language", language)
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.save(PATH)


func apply() -> void:
	Loc.set_language(language)
	_apply_bus(&"Master", master_volume)
	_apply_bus(BUS_MUSIC, music_volume)
	_apply_bus(BUS_SFX, sfx_volume)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func set_language(code: String) -> void:
	language = code
	Loc.set_language(code)
	save_settings()


# kind: "master", "music" or "sfx"
func set_volume(kind: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	match kind:
		"master":
			master_volume = value
			_apply_bus(&"Master", value)
		"music":
			music_volume = value
			_apply_bus(BUS_MUSIC, value)
		"sfx":
			sfx_volume = value
			_apply_bus(BUS_SFX, value)
	save_settings()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save_settings()


func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, &"Master")


func _apply_bus(bus_name: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))
