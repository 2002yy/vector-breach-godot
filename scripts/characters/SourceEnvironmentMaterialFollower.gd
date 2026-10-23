extends Node

var bindings: Array = []


func _ready() -> void:
	# The original eye controller updates calibrated bones at priority 100.
	process_priority = 200


func _process(_delta: float) -> void:
	for entry in bindings:
		if not is_instance_valid(entry.mesh) or not entry.original is ShaderMaterial:
			continue
		for parameter in ["enable_eyes", "eye_radius"]:
			entry.copy.set_shader_parameter(
				parameter, entry.original.get_shader_parameter(parameter)
			)
		for side in ["left", "right"]:
			for field in ["center", "forward", "up"]:
				var parameter: String = "eye_" + side + "_" + field
				entry.copy.set_shader_parameter(
					parameter, entry.original.get_shader_parameter(parameter)
				)
