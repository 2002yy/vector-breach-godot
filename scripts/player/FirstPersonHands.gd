extends Node3D

const EquipmentVisuals = preload("res://scripts/player/EquipmentVisuals.gd")

# Original articulated gloves: wrist, palm, thumb and three joints per finger.
# Presentation only. Animation never determines collision or damage authority.
var right: Node3D
var left: Node3D
var animator: AnimationPlayer
var magazine: MeshInstance3D
var grip: float = 0.85:
	set(value):
		grip = value
		for finger in _fingers:
			var flex := value
			if finger.get_meta("hand") == "Left" and _kind == "knife" and action == "idle":
				flex *= 0.32
			elif finger.get_meta("hand") == "Right" and action in ["reload", "plant", "defuse"]:
				flex = 0.85
			finger.rotation.x = -flex * float(finger.get_meta("bend", 1.0))
var action := "idle"
var _fingers: Array[Node3D] = []
var _forearms: Dictionary = {}
var _kind := "rifle"
var _idle_time := 0.0
var _base_right := Vector3(0.24, -0.19, -0.48)
var _base_left := Vector3(-0.12, -0.19, -0.58)


func _ready() -> void:
	right = _hand("Right", 1.0)
	left = _hand("Left", -1.0)
	magazine = MeshInstance3D.new()
	magazine.name = "Magazine"
	var magazine_mesh := BoxMesh.new()
	magazine_mesh.size = Vector3(0.035, 0.085, 0.027)
	magazine.mesh = magazine_mesh
	magazine.material_override = _material(Color(0.08, 0.09, 0.095))
	magazine.position = Vector3(0, 0.05, -0.025)
	magazine.visible = false
	left.add_child(magazine)
	animator = AnimationPlayer.new()
	animator.name = "Actions"
	add_child(animator)
	animator.animation_finished.connect(func(_clip): action = "idle")
	grip = 0.85
	set_equipment("rifle", false)


func _process(delta: float) -> void:
	if action == "idle":
		_idle_time += delta
		var breathing := Vector3(0, sin(_idle_time * 1.8) * 0.002, 0)
		right.position = _base_right + breathing
		left.position = _base_left + breathing
	for label in _forearms:
		var wrist: Node3D = right if label == "Right" else left
		var elbow := Vector3(0.36 if label == "Right" else -0.36, -0.36, 0.06)
		var end := wrist.position + wrist.basis * Vector3(0, 0, 0.055)
		var forearm: Node3D = _forearms[label]
		var length := elbow.distance_to(end)
		forearm.scale = Vector3(1, length / 0.5, 1)
		forearm.position = elbow
		forearm.quaternion = Quaternion(Vector3.UP, (end - elbow).normalized())


func _hand(label: String, side: float) -> Node3D:
	var wrist := Node3D.new()
	wrist.name = label
	add_child(wrist)
	var forearm := EquipmentVisuals.part("TailoredSleeve")
	forearm.name = label + "Forearm"
	add_child(forearm)
	_forearms[label] = forearm
	wrist.add_child(EquipmentVisuals.part("GlovePalm"))
	wrist.add_child(EquipmentVisuals.part("GloveCuff"))
	for digit in range(5):
		var parent: Node3D = wrist
		for joint in range(3):
			var pivot := Node3D.new()
			pivot.name = "Digit%dJoint%d" % [digit, joint]
			pivot.position = (
				Vector3((digit - 1.5) * 0.021, 0, -0.035) if joint == 0 else Vector3(0, 0, -0.025)
			)
			if digit == 4 and joint == 0:
				pivot.position = Vector3(-side * 0.055, -0.009, 0)
				pivot.rotation.y = side * -0.95
			pivot.set_meta("bend", 0.9 if digit == 4 else 1.1)
			pivot.set_meta("hand", label)
			parent.add_child(pivot)
			var phalange := EquipmentVisuals.part("GloveFinger")
			phalange.position = Vector3(0, 0, -0.013)
			pivot.add_child(phalange)
			_fingers.append(pivot)
			parent = pivot
	return wrist


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func set_equipment(kind: String, animate: bool = true) -> void:
	_kind = kind
	_base_right = Vector3(0.24, -0.19, -0.48)
	_base_left = Vector3(0.23, -0.19, -0.70)
	if kind == "pistol":
		_base_left = Vector3(0.17, -0.22, -0.50)
	elif kind == "knife":
		_base_left = Vector3(-0.23, -0.18, -0.53)
	elif kind.ends_with("grenade"):
		_base_left = Vector3(-0.16, -0.19, -0.52)
	elif kind == "c4":
		_base_left = Vector3(-0.015, -0.20, -0.63)
	reset_pose()
	if animate:
		play_action("equip", 0.32)


func reset_pose() -> void:
	animator.stop()
	action = "idle"
	right.position = _base_right
	left.position = _base_left
	right.rotation = Vector3.ZERO
	left.rotation = Vector3.ZERO
	magazine.visible = false
	grip = 0.85


func play_action(kind: String, duration: float = 0.45) -> void:
	reset_pose()
	action = kind
	var clip := Animation.new()
	clip.length = duration
	var rp := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var rr := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var lp := rp.duplicate()
	var lr := rr.duplicate()
	var curls := [0.85, 0.85, 0.85, 0.85]
	match kind:
		"equip":
			rp[0] = Vector3(0, -0.22, 0.08)
			lp[0] = rp[0]
			rr[0] = Vector3(0.6, 0, 0.15)
		"shot":
			rp[1] = Vector3(0, 0.012, 0.024)
			rr[1] = Vector3(-0.12, 0, 0)
			lp[1] = rp[1] * 0.6
		"reload":
			rr[1] = Vector3(0.08, -0.18, 0.30)
			rr[2] = Vector3(0, -0.12, 0.20)
			lp[1] = Vector3(0.27, -0.17, 0.12)
			lp[2] = Vector3(0.27, 0.08, -0.06)
			lr[1] = Vector3(0.6, 0, -0.6)
			lr[2] = Vector3(-0.4, 0, 0.4)
			curls[1] = 0.35
		"knife":
			rp[1] = Vector3(0.08, 0.04, 0.03)
			rr[1] = Vector3(0.1, 0.1, -0.6)
			rp[2] = Vector3(-0.32, 0.06, -0.08)
			rr[2] = Vector3(-0.2, -0.5, 1.05)
			lp[2] = Vector3(0, -0.04, 0.04)
		"knife_heavy":
			rp[1] = Vector3(0.025, 0.03, 0.08)
			rr[1] = Vector3(-0.15, 0, 0.15)
			rp[2] = Vector3(-0.12, 0.015, -0.27)
			rr[2] = Vector3(-0.4, 0, 0.15)
			lp[2] = Vector3(-0.06, -0.03, 0.04)
		"throw":
			rp[1] = Vector3(0.03, 0.07, 0.11)
			rr[1] = Vector3(-0.5, 0, -0.3)
			lp[1] = Vector3(0.40, 0.10, -0.02)
			lp[2] = Vector3(0.10, 0.04, 0)
			rp[2] = Vector3(-0.09, 0.12, -0.28)
			rr[2] = Vector3(-1.1, 0, 0.25)
			curls[2] = 0.1
		"plant", "defuse":
			rp[1] = Vector3(-0.05, 0.02, -0.06)
			rp[2] = Vector3(-0.08, 0.035, -0.08)
			lp[1] = Vector3(0.1, 0.04, -0.04)
			lp[2] = Vector3(0.13, 0.07, -0.06)
			lr[1] = Vector3(-0.3, 0, -0.25)
			lr[2] = Vector3(0.2, 0, 0.2)
			curls[1] = 0.25
			curls[2] = 0.55
	var times := [0.0, duration * 0.24, duration * 0.46, duration]
	if kind == "knife":
		times = [0.0, 0.06, 0.12, duration]
	elif kind == "knife_heavy":
		times = [0.0, 0.12, 0.22, duration]
	elif kind == "throw":
		times = [0.0, 0.16, 0.30, duration]
	for track in ["Right:position", "Right:rotation", "Left:position", "Left:rotation", ".:grip"]:
		var index := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(index, NodePath(track))
		clip.track_set_interpolation_type(index, Animation.INTERPOLATION_CUBIC)
		for key in range(4):
			var value: Variant = curls[key]
			match track:
				"Right:position":
					value = _base_right + rp[key]
				"Right:rotation":
					value = rr[key]
				"Left:position":
					value = _base_left + lp[key]
				"Left:rotation":
					value = lr[key]
			clip.track_insert_key(index, times[key], value)
	clip.loop_mode = Animation.LOOP_LINEAR if kind in ["plant", "defuse"] else Animation.LOOP_NONE
	if kind == "reload":
		magazine.scale = Vector3.ONE * (0.65 if _kind == "pistol" else 1.0)
		var mag_track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(mag_track, NodePath("Left/Magazine:visible"))
		clip.value_track_set_update_mode(mag_track, Animation.UPDATE_DISCRETE)
		for pair in [
			[0.0, false], [duration * 0.18, true], [duration * 0.68, false], [duration, false]
		]:
			clip.track_insert_key(mag_track, pair[0], pair[1])
	var library := AnimationLibrary.new()
	library.add_animation("action", clip)
	if animator.has_animation_library(""):
		animator.remove_animation_library("")
	animator.add_animation_library("", library)
	animator.play("action")


func snapshot() -> Dictionary:
	return {
		"action": action,
		"joints": _fingers.size() + 2,
		"right": right.position,
		"left": left.position,
		"grip": grip,
		"playing": animator.is_playing(),
		"time": animator.current_animation_position if animator.is_playing() else 0.0
	}
