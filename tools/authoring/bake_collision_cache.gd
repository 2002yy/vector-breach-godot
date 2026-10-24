extends SceneTree

const Cache = preload("res://scripts/level/SourceCollisionCache.gd")
const Levels = preload("res://scripts/level/LevelDataLoader.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: --script tools/authoring/bake_collision_cache.gd -- level-id [...]")
		quit(1)
		return
	for id in args:
		var data: Dictionary = Levels.load_level(id)
		var source := String(data.get("runtime_collision_scene", ""))
		if source.is_empty() or bool(data.get("retain_collision_meshes", false)):
			quit(1)
			return
		var scene := load(source) as PackedScene
		if scene == null:
			quit(1)
			return
		var root := scene.instantiate()
		var began := Time.get_ticks_usec()
		var ok := Cache.bake(root, source)
		root.free()
		if not ok:
			quit(1)
			return
		print("COLLISION_CACHE_BAKED ", id, " ", (Time.get_ticks_usec() - began) / 1000.0)
	quit()
