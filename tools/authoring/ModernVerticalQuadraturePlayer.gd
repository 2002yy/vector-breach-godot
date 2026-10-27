extends "res://tools/authoring/ModernGroundQuadratureV2Player.gd"
## Author-only constant-gravity kick/drift/kick; no production replacement.

var vertical_enabled := false
var vertical_sample := {}
var _vertical_delta := 0.0
var _vertical_active := false
var _vertical_expected := NAN
var _vertical_start := 0.0
var _vertical_half_kick := 0.0


func _ready() -> void:
	movement_step.connect(_finish_vertical_step)
	super._ready()


func _physics_process(delta: float) -> void:
	_vertical_delta = delta
	_vertical_active = false
	_vertical_expected = NAN
	vertical_sample = {"enabled": false, "phase": "baseline", "delta": delta}
	super._physics_process(delta)
	_vertical_active = false


func _sample_movement_input() -> Dictionary:
	var sampled := super._sample_movement_input()
	_vertical_active = (
		vertical_enabled
		and movement_scheme == "modern_cs"
		and movement_enabled
		and not is_on_ladder
		and not is_in_water
		and _vertical_delta > 0.0
	)
	if _vertical_active:
		_vertical_start = velocity.y
		_vertical_half_kick = _movement_gravity() * _vertical_delta * 0.5
		vertical_sample = {
			"enabled": true,
			"phase": "grounded",
			"delta": _vertical_delta,
			"gravity": _movement_gravity(),
			"start_velocity_y": _vertical_start,
		}
		if not is_on_floor():
			# Production subtracts a full kick after input sampling.
			velocity.y += _vertical_half_kick
			_vertical_expected = _vertical_start - _vertical_half_kick
	return sampled


func _movement_jump_impulse() -> float:
	var impulse := super._movement_jump_impulse()
	if _vertical_active:
		_vertical_expected = impulse - _vertical_half_kick
		vertical_sample["jump_impulse"] = impulse
		return _vertical_expected
	return impulse


func _finish_vertical_step(sample: Dictionary) -> void:
	if not _vertical_active or is_nan(_vertical_expected):
		return
	vertical_sample["motion_velocity_y"] = _vertical_expected
	if not is_on_floor() and absf(velocity.y - _vertical_expected) < 0.00001:
		velocity.y -= _vertical_half_kick
		vertical_sample["phase"] = "postkick"
	else:
		# Floor/snap/ceiling changes win; never restore a hidden vertical endpoint.
		vertical_sample["phase"] = "collision_reset"
	vertical_sample["endpoint_velocity_y"] = velocity.y
	sample["velocity"] = velocity
