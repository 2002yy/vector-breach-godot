extends Node3D

const PRESENTATION_SECONDS := 1.25
const LIFETIME := 2.4
const CLOUD := preload("res://scripts/objective/C4Cloud.gdshader")

var age := 0.0
var audio: AudioStreamPlayer3D
var _fire: Array[MeshInstance3D] = []
var _smoke: Array[MeshInstance3D] = []
var _flash: OmniLight3D


func _ready() -> void:
	for index in range(6):
		_fire.append(_puff(Color(1.0, 0.53, 0.12), true))
	for index in range(12):
		_smoke.append(_puff(Color(0.19, 0.18, 0.17, 0.0), false))
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.62, 0.25)
	_flash.omni_range = 14.0
	_flash.shadow_enabled = false
	add_child(_flash)
	audio = AudioStreamPlayer3D.new()
	audio.name = "BlastAudio"
	audio.max_distance = 160.0
	audio.unit_size = 12.0
	audio.volume_db = -4.0
	audio.stream = _rumble()
	add_child(audio)
	audio.play()
	_update_visuals()


func is_presenting() -> bool:
	return age < PRESENTATION_SECONDS


func _exit_tree() -> void:
	if is_instance_valid(audio):
		audio.stop()
		audio.stream = null


func _process(delta: float) -> void:
	if RoundManager.state == RoundManager.RoundState.PAUSED_MENU:
		audio.stream_paused = true
		return
	audio.stream_paused = false
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	_update_visuals()


func _puff(color: Color, fire: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = CLOUD
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("fire", fire)
	material.set_shader_parameter("seed", float(_fire.size() + _smoke.size()))
	material.set_shader_parameter("opacity", 1.0 if fire else 0.0)
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _update_visuals() -> void:
	_flash.light_energy = 10.0 * exp(-age * 15.0)
	for index in range(_fire.size()):
		var node := _fire[index]
		var angle := index * TAU / _fire.size()
		node.position = Vector3(cos(angle), 0.45, sin(angle)) * minf(age * 5.0, 1.6)
		node.scale = Vector3.ONE * (0.25 + minf(age * 10.0, 3.0))
		var material := node.material_override as ShaderMaterial
		material.set_shader_parameter("opacity", clampf(1.0 - age / 0.55, 0.0, 1.0))
		material.set_shader_parameter("age", age)
		node.visible = age < 0.55
	for index in range(_smoke.size()):
		var node := _smoke[index]
		var angle := index * 2.39996
		var radius := (0.3 + index * 0.08) * minf(age * 3.0, 3.5)
		node.position = Vector3(
			cos(angle) * radius, 0.4 + age * (1.0 + index * 0.08), sin(angle) * radius
		)
		node.scale = Vector3.ONE * (0.4 + age * (1.0 + (index % 3) * 0.22))
		var material := node.material_override as ShaderMaterial
		material.set_shader_parameter(
			"opacity", minf(age * 3.0, 0.75) * clampf((LIFETIME - age) / 0.8, 0.0, 1.0)
		)
		material.set_shader_parameter("age", age)


func _rumble() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 22050
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var data := PackedByteArray()
	data.resize(int(stream.mix_rate * 1.4) * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 4139
	var low_noise := 0.0
	for index in range(data.size() / 2):
		var time := float(index) / stream.mix_rate
		var noise := random.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.12)
		var body := sin(TAU * 48.0 * time) * 0.36 + low_noise * 1.5
		var sample := body * exp(-time * 3.7) + noise * 0.4 * exp(-time * 30.0)
		data.encode_s16(index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	stream.data = data
	return stream
