extends RefCounted


static func _test_native_decal_alpha_keeps_offset_and_original_materials(host: Node) -> void:
	var Decals = preload("res://scripts/level/SourceDecalMaterials.gd")
	var holder := Node3D.new()
	host.add_child(holder)
	var material := StandardMaterial3D.new()
	material.resource_name = "native_sign"
	material.grow = true
	material.grow_amount = -0.3927
	material.albedo_texture = ImageTexture.create_from_image(
		Image.create(2, 2, false, Image.FORMAT_RGB8)
	)
	var decoded := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var mesh := QuadMesh.new()
	mesh.material = material
	var nodes: Array[MeshInstance3D] = []
	for index in range(2):
		var node := MeshInstance3D.new()
		node.mesh = mesh
		holder.add_child(node)
		nodes.append(node)
	var entries := {
		"native_sign":
		{"loaded_texture": decoded, "blend_mode": 1, "opacity_multiplier": 0.9, "no_shadow": true}
	}
	var texture_path := "user://test-native-decal.tres"
	var manifest_path := "user://test-native-decal.json"
	ResourceSaver.save(decoded, texture_path)
	var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	manifest.store_string(
		JSON.stringify(
			{
				"schema": 1,
				"materials":
				[
					{
						"name": "native_sign",
						"source_shader": "csgo_static_overlay.vfx",
						"texture": texture_path,
						"blend_mode": 1,
						"opacity_multiplier": 0.9,
						"no_shadow": true
					}
				]
			}
		)
	)
	manifest.close()
	host.call(
		"_assert_equal",
		Decals.apply(holder, manifest_path),
		2,
		"JSON numeric blend mode installs native alpha on both instances"
	)
	var repaired := nodes[0].get_active_material(0) as StandardMaterial3D
	host.call(
		"_assert_true",
		(
			repaired.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
			and repaired.albedo_texture.get_image().get_format() == Image.FORMAT_RGBA8
		),
		"decoded native alpha actually bound"
	)
	host.call(
		"_assert_true",
		repaired.grow and is_equal_approx(repaired.grow_amount, material.grow_amount),
		"existing along-normal offset correction preserved"
	)
	host.call(
		"_assert_true",
		nodes[1].get_active_material(0) == repaired,
		"shared override cached by source resource"
	)
	host.call(
		"_assert_true",
		(
			material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and material.albedo_texture != decoded
			and nodes[0].mesh == mesh
		),
		"source material texture and geometry immutable"
	)
	host.call(
		"_assert_true",
		nodes[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"source no-shadow flag respected"
	)
	Decals._apply_recursive(holder, entries, {})
	host.call(
		"_assert_true",
		is_equal_approx(repaired.albedo_color.a, 0.9),
		"repeat application never multiplies opacity again"
	)
	var cutout := MeshInstance3D.new()
	cutout.mesh = mesh
	var cutout_source := material.duplicate() as StandardMaterial3D
	cutout_source.resource_name = "native_cutout"
	cutout.material_override = cutout_source
	holder.add_child(cutout)
	entries["native_cutout"] = {"loaded_texture": decoded, "blend_mode": 2, "alpha_test": 0.35}
	Decals._apply_recursive(holder, entries, {})
	var cutout_result := cutout.get_active_material(0) as StandardMaterial3D
	host.call(
		"_assert_true",
		(
			cutout_result.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			and is_equal_approx(cutout_result.alpha_scissor_threshold, 0.35)
		),
		"native alpha-test mode is not treated as additive or solid"
	)
	host.call(
		"_assert_equal",
		Decals.apply(holder, "user://absent-native-decal.json"),
		0,
		"private alpha manifest optional"
	)
	cutout.mesh = null
	for node in nodes:
		node.mesh = null
	holder.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(texture_path))


static func _test_source_helper_faces_preserve_real_surfaces_and_children(host: Node) -> void:
	var Helpers = preload("res://scripts/level/SourceVisualHelpers.gd")
	var holder := Node3D.new()
	host.add_child(holder)
	var helper := StandardMaterial3D.new()
	helper.resource_name = "wrongway_timer"
	var brick := StandardMaterial3D.new()
	brick.resource_name = "brick"
	var helper_mesh := QuadMesh.new()
	helper_mesh.material = helper
	var real_mesh := QuadMesh.new()
	real_mesh.material = brick
	var leaf := MeshInstance3D.new()
	leaf.mesh = helper_mesh
	holder.add_child(leaf)
	var parent := MeshInstance3D.new()
	parent.mesh = helper_mesh
	holder.add_child(parent)
	var child := MeshInstance3D.new()
	child.mesh = real_mesh
	parent.add_child(child)
	var combined := ArrayMesh.new()
	for material in [helper, brick]:
		combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, real_mesh.surface_get_arrays(0))
		combined.surface_set_material(combined.get_surface_count() - 1, material)
	var mixed := MeshInstance3D.new()
	mixed.mesh = combined
	holder.add_child(mixed)
	var prop := MeshInstance3D.new()
	prop.mesh = real_mesh
	var prop_material := StandardMaterial3D.new()
	prop_material.resource_name = "bucket_tools"
	prop.material_override = prop_material
	holder.add_child(prop)
	host.call("_assert_equal", Helpers.apply(holder), 3, "only known helper surfaces excluded")
	host.call(
		"_assert_true",
		not leaf.visible and leaf.mesh == helper_mesh,
		"tool leaf hidden without deleting geometry"
	)
	host.call(
		"_assert_true",
		parent.visible and child.visible and parent.get_active_material(0) is ShaderMaterial,
		"hiding helper faces never hides real child meshes"
	)
	host.call(
		"_assert_true",
		(
			mixed.visible
			and mixed.get_active_material(0) is ShaderMaterial
			and mixed.get_active_material(1) == brick
		),
		"mixed meshes retain their real surface"
	)
	host.call(
		"_assert_true",
		prop.visible and prop.get_active_material(0) == prop_material,
		"ordinary tools props are not helper geometry"
	)
	host.call("_assert_equal", Helpers.apply(holder), 3, "repeated filter returns stable metadata")
	host.call(
		"_assert_true",
		helper_mesh.material == helper and combined.surface_get_material(0) == helper,
		"shared source materials unchanged"
	)
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		node.mesh = null
	holder.free()
