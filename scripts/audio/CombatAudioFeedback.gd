extends Node3D

const SAMPLE_PATHS := {
	"rifle": [
		"res://assets/audio/weapons/rifle_fire_01.ogg",
		"res://assets/audio/weapons/rifle_fire_02.ogg",
	],
	"pistol": [
		"res://assets/audio/weapons/pistol_fire_01.ogg",
		"res://assets/audio/weapons/pistol_fire_02.ogg",
	],
	"concrete": [
		"res://assets/audio/footsteps/concrete_01.ogg",
		"res://assets/audio/footsteps/concrete_02.ogg",
	],
	"metal": [
		"res://assets/audio/footsteps/metal_01.ogg",
		"res://assets/audio/footsteps/metal_02.ogg",
	],
	"wood": [
		"res://assets/audio/footsteps/wood_01.ogg",
		"res://assets/audio/footsteps/wood_02.ogg",
	],
	"water": [
		"res://assets/audio/footsteps/water_01.ogg",
		"res://assets/audio/footsteps/water_02.ogg",
	],
	"rifle_reload": ["res://assets/audio/foley/rifle_reload.ogg"],
	"pistol_reload": ["res://assets/audio/foley/pistol_reload.ogg"],
}

var _shot_player: AudioStreamPlayer3D
var _impact_player: AudioStreamPlayer3D
var _mechanical_player: AudioStreamPlayer
var _movement_player: AudioStreamPlayer3D
var _shot_count: int = 0
var _hit_count: int = 0
var _reload_count: int = 0
var _switch_count: int = 0
var _footstep_count: int = 0
var _landing_count: int = 0
var _sampled_event_count: int = 0
var _fallback_event_count: int = 0
var _sample_assets_enabled: bool = true
var _sample_bank: Dictionary = {}

func _ready() -> void:
	_load_sample_bank()
	_shot_player = _make_spatial_player("ShotPlayer", 95.0)
	_impact_player = _make_spatial_player("ImpactPlayer", 32.0)
	_mechanical_player = _make_player("MechanicalPlayer")
	_movement_player = _make_spatial_player("MovementPlayer", 42.0)

func play_shot(result: Dictionary, world_position: Vector3 = Vector3.ZERO) -> void:
	_shot_count += 1
	var pistol := int(result.get("weapon_slot", 0)) == 1
	_shot_player.global_position = world_position
	var sampled_shot := _pick_sample("pistol" if pistol else "rifle", _shot_count)
	_shot_player.stream = sampled_shot if sampled_shot != null else _make_burst(0.18 if pistol else 0.27, 184.0 if pistol else 112.0, 0.72, 17 + _shot_count, pistol)
	_record_branch(sampled_shot)
	var pitch_jitter := sin(float(_shot_count) * 12.9898) * 0.012
	_shot_player.pitch_scale = (1.07 if pistol else 0.96) + pitch_jitter
	_shot_player.play()
	if bool(result.get("hit", false)):
		_hit_count += 1
		_impact_player.global_position = result.get("position", world_position)
		_impact_player.stream = _make_impact(0.075, 850.0, 0.24, 101 + _hit_count)
		_impact_player.pitch_scale = 0.98 + float(_hit_count % 5) * 0.009
		_impact_player.play()

func play_footstep(world_position: Vector3, surface: String, quiet: bool) -> void:
	_footstep_count += 1
	_movement_player.global_position = world_position
	var base_frequency := 118.0
	if surface == "metal":
		base_frequency = 260.0
	elif surface == "wood":
		base_frequency = 170.0
	elif surface == "water":
		base_frequency = 72.0
	var gain := (0.16 if quiet else 0.38) if surface == "water" else (0.11 if quiet else 0.32)
	var sample_key := surface if _sample_bank.has(surface) else "concrete"
	var sampled_step := _pick_sample(sample_key, _footstep_count)
	_movement_player.stream = sampled_step if sampled_step != null else _make_step(0.09, base_frequency, gain, _shot_count + _reload_count + _footstep_count + 31, surface)
	_record_branch(sampled_step)
	_movement_player.volume_db = -8.0 if quiet else -2.0
	_movement_player.pitch_scale = 0.97 + float(_footstep_count % 5) * 0.012
	_movement_player.max_distance = 14.0 if quiet else 42.0
	_movement_player.play()

func play_landing(world_position: Vector3, surface: String, strength: float) -> void:
	_landing_count += 1
	_movement_player.global_position = world_position
	var frequency := 235.0 if surface == "metal" else (155.0 if surface == "wood" else (68.0 if surface == "water" else 92.0))
	var sample_key := surface if _sample_bank.has(surface) else "concrete"
	var sampled_landing := _pick_sample(sample_key, _landing_count + 1)
	_movement_player.stream = sampled_landing if sampled_landing != null else _make_step(0.14, frequency, lerpf(0.18, 0.42, clampf(strength, 0.0, 1.0)), 79 + _shot_count + _landing_count, surface)
	_record_branch(sampled_landing)
	_movement_player.volume_db = lerpf(-8.0, -1.0, clampf(strength, 0.0, 1.0))
	_movement_player.pitch_scale = 0.94
	_movement_player.max_distance = 48.0
	_movement_player.play()

func play_reload_started() -> void:
	_reload_count += 1
	var sample_key := "pistol_reload" if GameState.current_weapon_slot == 1 else "rifle_reload"
	var sampled_reload := _pick_sample(sample_key, _reload_count)
	_mechanical_player.stream = sampled_reload if sampled_reload != null else _make_click_sequence([0.0, 0.09], 0.24)
	_record_branch(sampled_reload)
	_mechanical_player.pitch_scale = 0.99 + float(_reload_count % 3) * 0.008
	_mechanical_player.play()

func play_reload_finished() -> void:
	_mechanical_player.stream = _make_click_sequence([0.0, 0.045, 0.1], 0.3)
	_mechanical_player.play()

func play_weapon_switched() -> void:
	_switch_count += 1
	_mechanical_player.stream = _make_click_sequence([0.0, 0.055], 0.18)
	_mechanical_player.play()

func get_debug_snapshot() -> Dictionary:
	return {
		"shots": _shot_count,
		"hits": _hit_count,
		"reloads": _reload_count,
		"switches": _switch_count,
		"footsteps": _footstep_count,
		"landings": _landing_count,
		"players": get_child_count(),
		"spatial_players": 3,
		"sample_assets": _loaded_sample_count(),
		"sampled_events": _sampled_event_count,
		"fallback_events": _fallback_event_count,
	}

func get_asset_manifest() -> Dictionary:
	return SAMPLE_PATHS.duplicate(true)

func set_sample_assets_enabled(enabled: bool) -> void:
	_sample_assets_enabled = enabled

func _load_sample_bank() -> void:
	_sample_bank.clear()
	for key_variant in SAMPLE_PATHS:
		var key := String(key_variant)
		var loaded: Array[AudioStream] = []
		for path_variant in SAMPLE_PATHS[key]:
			var path := String(path_variant)
			if ResourceLoader.exists(path):
				var stream := ResourceLoader.load(path) as AudioStream
				if stream != null:
					loaded.append(stream)
		_sample_bank[key] = loaded

func _pick_sample(key: String, event_index: int) -> AudioStream:
	if not _sample_assets_enabled:
		return null
	var samples := _sample_bank.get(key, []) as Array
	if samples.is_empty():
		return null
	return samples[posmod(event_index - 1, samples.size())] as AudioStream

func _record_branch(stream: AudioStream) -> void:
	if stream == null:
		_fallback_event_count += 1
	else:
		_sampled_event_count += 1

func _loaded_sample_count() -> int:
	var count := 0
	for samples_variant in _sample_bank.values():
		count += (samples_variant as Array).size()
	return count

func _make_player(node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.max_polyphony = 4
	add_child(player)
	return player

func _make_spatial_player(node_name: String, max_distance: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.max_polyphony = 6
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = 4.0
	player.max_distance = max_distance
	add_child(player)
	return player

func _make_burst(duration: float, base_frequency: float, gain: float, seed_value: int, pistol: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _make_wave(duration, func(time: float) -> float:
		var transient := rng.randf_range(-1.0, 1.0) * exp(-time * (115.0 if pistol else 92.0))
		var body_envelope := exp(-time * (22.0 if pistol else 15.0))
		var body := (sin(TAU * base_frequency * time) * 0.56 + sin(TAU * base_frequency * 0.52 * time) * 0.34) * body_envelope
		var mechanical := sin(TAU * (620.0 if pistol else 470.0) * time) * exp(-time * 58.0) * 0.16
		var tail_time := maxf(time - 0.035, 0.0)
		var tail := rng.randf_range(-1.0, 1.0) * exp(-tail_time * (19.0 if pistol else 12.0)) * (0.11 if time >= 0.035 else 0.0)
		return (transient * 0.72 + body + mechanical + tail) * gain
	)

func _make_tone(duration: float, frequency: float, gain: float) -> AudioStreamWAV:
	return _make_wave(duration, func(time: float) -> float:
		return sin(TAU * frequency * time) * exp(-time * 38.0) * gain
	)

func _make_impact(duration: float, frequency: float, gain: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _make_wave(duration, func(time: float) -> float:
		var tick := sin(TAU * frequency * time) * exp(-time * 52.0)
		var debris := rng.randf_range(-1.0, 1.0) * exp(-time * 34.0) * 0.46
		return (tick + debris) * gain
	)

func _make_step(duration: float, base_frequency: float, gain: float, seed_value: int, surface: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _make_wave(duration, func(time: float) -> float:
		var envelope := exp(-time * (31.0 if surface == "water" else 42.0))
		var body := sin(TAU * base_frequency * time) * 0.5
		var texture_gain := 0.68 if surface == "metal" else (0.3 if surface == "wood" else 0.48)
		var texture := rng.randf_range(-1.0, 1.0) * texture_gain
		var secondary := sin(TAU * base_frequency * (2.3 if surface == "metal" else 0.55) * time) * (0.24 if surface != "water" else 0.12)
		return (body + texture + secondary) * envelope * gain
	)

func _make_click_sequence(times: Array, gain: float) -> AudioStreamWAV:
	var duration := float(times.back()) + 0.05
	return _make_wave(duration, func(time: float) -> float:
		var value := 0.0
		for click_variant in times:
			var elapsed := time - float(click_variant)
			if elapsed >= 0.0 and elapsed < 0.025:
				value += sin(TAU * 760.0 * elapsed) * exp(-elapsed * 135.0)
		return value * gain
	)

func _make_wave(duration: float, sample_function: Callable) -> AudioStreamWAV:
	const MIX_RATE := 22050
	var sample_count := maxi(1, int(duration * MIX_RATE))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var sample := clampf(float(sample_function.call(float(index) / MIX_RATE)), -1.0, 1.0)
		bytes.encode_s16(index * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
