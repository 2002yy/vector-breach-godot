extends Node3D

signal beep_emitted(world_position: Vector3, urgency: float)

@export var explosion_radius: float = 22.0
@export var lethal_radius: float = 5.5

@onready var mesh_root: Node3D = $MeshRoot
@onready var status_light: OmniLight3D = $MeshRoot/StatusLight
@onready var beep_player: AudioStreamPlayer3D = $BeepPlayer

var device_state: String = "carried"
var carrier_team: String = "T"
var site_label: String = ""
var _beep_timer: float = 0.0

func _ready() -> void:
	beep_player.stream = _make_beep_stream()
	set_carried(carrier_team)

func _process(delta: float) -> void:
	if device_state != "planted" or RoundManager.state != RoundManager.RoundState.BOMB_PLANTED:
		return
	var urgency := 1.0 - clampf(RoundManager.time_remaining / maxf(RoundManager.bomb_duration, 0.001), 0.0, 1.0)
	var interval := lerpf(1.05, 0.16, urgency)
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_beep_timer = interval
		status_light.light_energy = 2.4
		beep_player.pitch_scale = lerpf(0.9, 1.35, urgency)
		beep_player.play()
		beep_emitted.emit(global_position, urgency)
	else:
		status_light.light_energy = move_toward(status_light.light_energy, 0.45, delta * 8.0)

func set_carried(team: String = "T") -> void:
	device_state = "carried"
	carrier_team = team
	site_label = ""
	mesh_root.visible = false
	_beep_timer = 0.0

func drop_at(world_position: Vector3) -> void:
	device_state = "dropped"
	global_position = world_position
	mesh_root.visible = true
	_beep_timer = 0.0

func plant_at(world_position: Vector3, next_site_label: String) -> void:
	device_state = "planted"
	global_position = world_position
	site_label = next_site_label
	mesh_root.visible = true
	_beep_timer = 0.0

func can_pick_up(player_position: Vector3, player_team: String) -> bool:
	return device_state == "dropped" and player_team == "T" and global_position.distance_to(player_position) <= 1.8

func pick_up(player_team: String) -> bool:
	if device_state != "dropped" or player_team != "T":
		return false
	set_carried(player_team)
	return true

func is_player_in_interaction_range(player_position: Vector3) -> bool:
	return device_state == "planted" and global_position.distance_to(player_position) <= 2.0

func calculate_explosion_damage(target_position: Vector3, space_state: PhysicsDirectSpaceState3D, exclude: Array = []) -> int:
	var distance := global_position.distance_to(target_position)
	if distance > explosion_radius:
		return 0
	var sigma := maxf(lethal_radius, 0.1)
	var damage := 500.0 * exp(-(distance * distance) / (2.0 * sigma * sigma))
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.25, target_position + Vector3.UP * 0.6)
	query.exclude = exclude
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var obstruction := space_state.intersect_ray(query)
	if not obstruction.is_empty():
		damage *= 0.35
	return maxi(0, int(round(damage)))

func get_radar_record() -> Dictionary:
	return {
		"kind": "c4",
		"state": device_state,
		"x": global_position.x,
		"z": global_position.z,
		"site": site_label,
	}

func _make_beep_stream() -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := int(0.075 * mix_rate)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in range(sample_count):
		var envelope := 1.0 - float(index) / float(sample_count)
		var sample := sin(TAU * 980.0 * float(index) / float(mix_rate)) * envelope * 0.32
		var encoded := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(index * 2, encoded)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream
