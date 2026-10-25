extends RefCounted

const SOURCE_META := "_source_packed_scene"


static func instantiate(path: String) -> Node3D:
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	# Godot's resource cache is weak. Keep the source alive with its instance,
	# without an application-wide cache that outlives the world using it.
	instance.set_meta(SOURCE_META, scene)
	return instance as Node3D


static func source(instance: Node) -> PackedScene:
	if not is_instance_valid(instance) or not instance.has_meta(SOURCE_META):
		return null
	return instance.get_meta(SOURCE_META) as PackedScene
