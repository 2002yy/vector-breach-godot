extends Node

var _shot_player: AudioStreamPlayer
var _impact_player: AudioStreamPlayer
var _mechanical_player: AudioStreamPlayer
var _shot_count: int = 0
var _hit_count: int = 0
var _reload_count: int = 0
var _switch_count: int = 0

func _ready() -> void:
	_shot_player = _make_player("ShotPlayer")
	_impact_player = _make_player("ImpactPlayer")
	_mechanical_player = _make_player("MechanicalPlayer")

func play_shot(result: Dictionary) -> void:
	_shot_count += 1
	var pistol := int(result.get("weapon_slot", 0)) == 1
	_shot_player.stream = _make_burst(0.075 if pistol else 0.11, 175.0 if pistol else 118.0, 0.72, 17 + _shot_count)
	_shot_player.pitch_scale = 1.08 if pistol else 0.96
	_shot_player.play()
	if bool(result.get("hit", false)):
		_hit_count += 1
		_impact_player.stream = _make_tone(0.055, 920.0, 0.22)
		_impact_player.play()

func play_reload_started() -> void:
	_reload_count += 1
	_mechanical_player.stream = _make_click_sequence([0.0, 0.09], 0.24)
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
		"players": get_child_count(),
	}

func _make_player(node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.max_polyphony = 4
	add_child(player)
	return player

func _make_burst(duration: float, base_frequency: float, gain: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _make_wave(duration, func(time: float) -> float:
		var envelope := exp(-time * 28.0)
		var body := sin(TAU * base_frequency * time) * 0.62
		var crack := rng.randf_range(-1.0, 1.0) * exp(-time * 70.0)
		return (body + crack) * envelope * gain
	)

func _make_tone(duration: float, frequency: float, gain: float) -> AudioStreamWAV:
	return _make_wave(duration, func(time: float) -> float:
		return sin(TAU * frequency * time) * exp(-time * 38.0) * gain
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
