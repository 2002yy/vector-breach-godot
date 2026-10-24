extends RefCounted

const Scene = preload("res://scripts/SceneInstance.gd")


static func run(host: Node) -> void:
	var unowned := Node3D.new()
	host.call("_assert_true", Scene.source(unowned) == null, "fallback nodes have no source lease")
	unowned.free()
	var path := "user://scene-instance-lifetime-%d.tscn" % Time.get_ticks_usec()
	var root := Node3D.new()
	var packed := PackedScene.new()
	host.call("_assert_equal", packed.pack(root), OK, "fixture packs")
	host.call("_assert_equal", ResourceSaver.save(packed, path), OK, "fixture saves")
	root.free()
	packed = null
	var first := Scene.instantiate(path)
	var second := Scene.instantiate(path)
	host.call("_assert_true", first != second, "nodes remain per instance")
	host.call(
		"_assert_true",
		Scene.source(first) == Scene.source(second),
		"live instances share source scene"
	)
	host.call(
		"_assert_true",
		ResourceLoader.has_cached(path),
		"live instance keeps weak loader cache populated"
	)
	var source: WeakRef = weakref(Scene.source(first))
	first.free()
	host.call("_assert_true", source.get_ref() != null, "remaining instance still owns source")
	var retirement: Array[PackedScene] = [Scene.source(second)]
	second.free()
	host.call(
		"_assert_true",
		source.get_ref() != null,
		"retirement bridge spans deferred roster replacement"
	)
	var replacement := Scene.instantiate(path)
	host.call(
		"_assert_true",
		Scene.source(replacement) == source.get_ref(),
		"replacement reuses retained source"
	)
	retirement.clear()
	host.call(
		"_assert_true", source.get_ref() != null, "new instance owns source after bridge release"
	)
	replacement.free()
	host.call(
		"_assert_true", source.get_ref() == null, "last owner releases scene without a global cache"
	)
	host.call(
		"_assert_true", not ResourceLoader.has_cached(path), "no scene remains in loader cache"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.call("_assert_true", Scene.instantiate(path) == null, "missing source falls back safely")
	var flat := Node.new()
	packed = PackedScene.new()
	packed.pack(flat)
	ResourceSaver.save(packed, path)
	flat.free()
	packed = null
	host.call("_assert_true", Scene.instantiate(path) == null, "non-3D scene is rejected and freed")
	host.call("_assert_true", not ResourceLoader.has_cached(path), "rejected scene is not retained")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
