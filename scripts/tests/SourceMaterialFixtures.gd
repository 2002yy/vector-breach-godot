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
		cutout.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"static-overlay shader implies no shadow without an explicit source flag"
	)
	host.call(
		"_assert_equal",
		Decals.apply(holder, "user://absent-native-decal.json"),
		0,
		"private alpha manifest optional"
	)
	var Modulate = preload("res://scripts/level/SourceModulateMaterials.gd")
	var modulate_node := MeshInstance3D.new()
	modulate_node.mesh = mesh
	var modulate_source := material.duplicate() as StandardMaterial3D
	modulate_source.resource_name = "native_mod2x"
	modulate_source.uv1_scale = Vector3(2, 3, 1)
	modulate_source.uv1_offset = Vector3(0.1, 0.2, 0)
	modulate_source.albedo_color = Color(0.5, 0.6, 0.7).linear_to_srgb()
	modulate_source.cull_mode = BaseMaterial3D.CULL_DISABLED
	modulate_source.render_priority = 2
	modulate_node.material_override = modulate_source
	holder.add_child(modulate_node)
	var modulate_entries := {
		"native_mod2x":
		{
			"loaded_texture": decoded,
			"opacity_multiplier": 0.7,
			"native_material": {"IntParams": {"F_BLEND_MODE": 3}},
			"render_contract": "source-static-overlay-mod2x-v1"
		}
	}
	Modulate._apply_recursive(holder, modulate_entries, {})
	var modulated := modulate_node.get_active_material(0) as ShaderMaterial
	host.call(
		"_assert_true",
		modulated != null and modulated.shader.code.contains("blend_mul"),
		"Mod2x is multiplicative, not ordinary alpha"
	)
	host.call(
		"_assert_true",
		(
			modulated.get_shader_parameter("uv_scale") == modulate_source.uv1_scale
			and modulated.get_shader_parameter("uv_offset") == modulate_source.uv1_offset
			and is_equal_approx(
				modulated.get_shader_parameter("surface_offset"), material.grow_amount
			)
			and modulated.render_priority == 2
			and modulated.shader.code.contains("cull_disabled")
		),
		"Mod2x preserves UV, repaired offset, culling and order"
	)
	host.call(
		"_assert_true",
		(
			modulated.get_shader_parameter("source_tint").is_equal_approx(Vector3(0.5, 0.6, 0.7))
			and modulated.get_meta("source_material_parameters").IntParams.F_BLEND_MODE == 3
			and modulate_source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and modulate_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		),
		"source tint, full parameters and overlay shadow rule preserved without input mutation"
	)
	host.call(
		"_assert_equal",
		Modulate._apply_recursive(holder, modulate_entries, {}),
		1,
		"Mod2x repeat application is idempotent"
	)
	var fog := Environment.new()
	fog.fog_enabled = true
	fog.fog_density = 0.02
	Modulate.update_environment(holder, fog)
	host.call(
		"_assert_true",
		(
			modulated.get_shader_parameter("fog_enabled")
			and is_equal_approx(modulated.get_shader_parameter("fog_density"), 0.02)
		),
		"Mod2x follows the current map fog rather than baking one environment"
	)
	var Assets = preload("res://scripts/level/SourceAssetMaterials.gd")
	var flame := MeshInstance3D.new()
	flame.mesh = mesh
	var flame_source := material.duplicate() as StandardMaterial3D
	flame_source.resource_name = "native_flame"
	flame_source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	flame_source.roughness = 0.31
	flame.material_override = flame_source
	holder.add_child(flame)
	var flame_entries := {
		"native_flame":
		{
			"native_material": {"IntParams": {"F_ADDITIVE_BLEND": 1}},
			"render_contract": "source-additive-v1",
			"pending_features": ["F_CLOTH_SHADING"]
		}
	}
	Assets._apply_recursive(holder, flame_entries, {})
	var flame_result := flame.get_active_material(0) as StandardMaterial3D
	(
		host
		. call(
			"_assert_true",
			(
				flame_result.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
				and flame_result.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
				and is_equal_approx(flame_result.roughness, 0.31)
				and flame_source.blend_mode == BaseMaterial3D.BLEND_MODE_MIX
				and flame_result.get_meta("source_features_pending") == ["F_CLOTH_SHADING"]
			),
			"additive source rule removes depth prewrite, preserves PBR and declares unsupported features"
		)
	)
	host.call(
		"_assert_equal",
		Assets._apply_recursive(holder, flame_entries, {}),
		1,
		"source parameter binding never reapplies a material conversion"
	)
	flame.mesh = null
	modulate_node.mesh = null
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
