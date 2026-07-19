extends Node

signal settings_changed(snapshot: Dictionary)

const SETTINGS_PATH := "user://settings.cfg"

var mouse_sensitivity_multiplier: float = 1.0
var master_volume: float = 0.8
var crosshair_gap: float = 7.0
var crosshair_size: float = 6.0
var dynamic_crosshair: bool = true
var radar_range: float = 24.0
var radar_rotates: bool = true

func _ready() -> void:
	load_settings()
	apply_audio_volume()

func get_snapshot() -> Dictionary:
	return {
		"mouse_sensitivity_multiplier": mouse_sensitivity_multiplier,
		"master_volume": master_volume,
		"crosshair_gap": crosshair_gap,
		"crosshair_size": crosshair_size,
		"dynamic_crosshair": dynamic_crosshair,
		"radar_range": radar_range,
		"radar_rotates": radar_rotates,
	}

func apply_snapshot(snapshot: Dictionary, persist: bool = true) -> void:
	mouse_sensitivity_multiplier = clampf(float(snapshot.get("mouse_sensitivity_multiplier", mouse_sensitivity_multiplier)), 0.35, 3.0)
	master_volume = clampf(float(snapshot.get("master_volume", master_volume)), 0.0, 1.0)
	crosshair_gap = clampf(float(snapshot.get("crosshair_gap", crosshair_gap)), 2.0, 16.0)
	crosshair_size = clampf(float(snapshot.get("crosshair_size", crosshair_size)), 2.0, 14.0)
	dynamic_crosshair = bool(snapshot.get("dynamic_crosshair", dynamic_crosshair))
	radar_range = clampf(float(snapshot.get("radar_range", radar_range)), 16.0, 40.0)
	radar_rotates = bool(snapshot.get("radar_rotates", radar_rotates))
	apply_audio_volume()
	if persist:
		save_settings()
	settings_changed.emit(get_snapshot())

func apply_audio_volume() -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus_index, master_volume <= 0.001)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	apply_snapshot({
		"mouse_sensitivity_multiplier": config.get_value("controls", "mouse_sensitivity_multiplier", mouse_sensitivity_multiplier),
		"master_volume": config.get_value("audio", "master_volume", master_volume),
		"crosshair_gap": config.get_value("crosshair", "gap", crosshair_gap),
		"crosshair_size": config.get_value("crosshair", "size", crosshair_size),
		"dynamic_crosshair": config.get_value("crosshair", "dynamic", dynamic_crosshair),
		"radar_range": config.get_value("radar", "range", radar_range),
		"radar_rotates": config.get_value("radar", "rotates", radar_rotates),
	}, false)

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity_multiplier", mouse_sensitivity_multiplier)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("crosshair", "gap", crosshair_gap)
	config.set_value("crosshair", "size", crosshair_size)
	config.set_value("crosshair", "dynamic", dynamic_crosshair)
	config.set_value("radar", "range", radar_range)
	config.set_value("radar", "rotates", radar_rotates)
	config.save(SETTINGS_PATH)
