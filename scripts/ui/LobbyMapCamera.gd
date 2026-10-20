extends Camera3D

const Navigation = preload("res://scripts/ai/BotNavigationModel.gd")


func frame_level(data: Dictionary, fallback: Vector3) -> void:
	fov = 65.0
	var at := fallback + Vector3(0, 3, 5)
	var target := fallback + Vector3(0, 0.5, -5)
	var graph: Dictionary = data.get("navigationGraph", {})
	var objectives: Array = data.get("objectives", [])
	if not graph.is_empty() and not objectives.is_empty():
		var starts: Array = (data.get("matchSpawns", {}) as Dictionary).get("T", [])
		if not starts.is_empty():
			fallback = Vector3(float(starts[0][0]), float(starts[0][1]), float(starts[0][2]))
		var navigation := Navigation.new()
		navigation.configure(graph)
		var site: Dictionary = objectives[0]
		var destination := Vector3(
			float(site.get("x", 0)), float(site.get("y", 0)), float(site.get("z", 0))
		)
		var danger: Array[Dictionary] = []
		var path := navigation.find_path(
			navigation.nearest_index(fallback), navigation.nearest_index(destination), danger
		)
		if path.size() >= 3:
			var fraction := 0.8 if String(data.get("id", "")) == "mirage-classic-local" else 0.5
			var index := mini(int(path.size() * fraction), path.size() - 2)
			at = navigation.points[path[index]] + Vector3.UP * 1.1
			var direction: Vector3 = navigation.points[path[mini(index + 2, path.size() - 1)]] - at
			direction.y = 0.0
			if direction.length_squared() < 0.0001:
				direction = Vector3.FORWARD
			target = at + direction.normalized() * 10.0 + Vector3.UP * 0.2
	global_position = at
	if at.distance_squared_to(target) > 0.1:
		look_at(target)
	make_current()
