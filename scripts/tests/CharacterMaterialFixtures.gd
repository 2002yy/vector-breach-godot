extends RefCounted


static func test_native_character_channels_preserve_pbr_and_geometry(host: Node) -> void:
	var Materials = preload("res://scripts/characters/SourceCharacterMaterials.gd")
	var holder := Node3D.new()
	host.add_child(holder)
	var original := StandardMaterial3D.new()
	original.resource_name = "native_character_fixture"
	original.albedo_color = Color(0.2, 0.3, 0.4).linear_to_srgb()
	original.uv1_scale = Vector3(2, 3, 1)
	original.uv1_offset = Vector3(0.1, 0.2, 0)
	original.cull_mode = BaseMaterial3D.CULL_DISABLED
	original.render_priority = 2
	var texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	original.albedo_texture = texture
	original.roughness_texture = texture
	original.metallic_texture = texture
	var native := {
		"ShaderName": "csgo_character.vfx",
		"IntParams":
		{
			"F_CLOTH_SHADING": 1,
			"F_SUBSURFACE_SCATTERING": 1,
			"F_ANISOTROPIC_GLOSS": 1,
			"F_SPHERICAL_PROJECTED_ANISOTROPIC_TANGENTS": 1
		},
		"FloatParams":
		{"g_flSheenScale": 0.8, "g_flCurvatureScale": 2.0, "g_vSphericalAnisotropyAngle": 90.0},
		"VectorParams": {"g_vSphericalAnisotropyPole": [1, 0, 1, 0]}
	}
	var entry := {
		"native_material": native,
		"pending_features": ["F_EYEBALLS"],
		"loaded_textures":
		{
			"g_tMetalness": texture,
			"g_tSssMask": texture,
			"g_tDiffuseFalloff": texture,
			"g_tAnisoGloss": texture
		}
	}
	var mesh := QuadMesh.new()
	mesh.material = original
	for index in range(2):
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		holder.add_child(instance)
	var entries := {original.resource_name: entry}
	host.call(
		"_assert_equal",
		Materials._apply_recursive(holder, entries, {}),
		2,
		"native shading is bound to both shared mesh instances"
	)
	var repaired := (holder.get_child(0) as MeshInstance3D).get_active_material(0) as ShaderMaterial
	host.call(
		"_assert_true",
		(
			repaired != null
			and repaired.get_shader_parameter("enable_cloth")
			and repaired.get_shader_parameter("enable_skin")
			and repaired.get_shader_parameter("enable_aniso")
		),
		"all source feature flags are consumed"
	)
	host.call(
		"_assert_true",
		(
			repaired.get_shader_parameter("cloth_texture") == texture
			and repaired.get_shader_parameter("skin_texture") == texture
			and repaired.get_shader_parameter("aniso_texture") == texture
		),
		"native packed masks are actually bound, rather than inferred from albedo"
	)
	host.call(
		"_assert_true",
		(
			repaired.get_shader_parameter("roughness_texture") == original.roughness_texture
			and repaired.get_shader_parameter("uv_scale") == original.uv1_scale
			and repaired.get_shader_parameter("uv_offset") == original.uv1_offset
			and repaired.render_priority == 2
			and repaired.shader.code.contains("cull_disabled")
		),
		"PBR textures, UV, order and double-sided rendering survive"
	)
	host.call(
		"_assert_true",
		(
			is_equal_approx(repaired.get_shader_parameter("sheen_scale"), 0.8)
			and is_equal_approx(repaired.get_shader_parameter("curvature_scale"), 2.0)
			and repaired.get_shader_parameter("aniso_pole") == Vector3(-1, 1, 0)
		),
		"native scale and Source Z-up pole are mapped into the exported body frame"
	)
	host.call(
		"_assert_true",
		(
			repaired.get_meta("source_material_parameters") == native
			and repaired.get_meta("source_features_pending") == ["F_EYEBALLS"]
			and original.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and (holder.get_child(0) as MeshInstance3D).mesh == mesh
		),
		"source parameters, remaining limitations and original geometry remain intact"
	)
	host.call(
		"_assert_equal",
		Materials._apply_recursive(holder, entries, {}),
		2,
		"repeat application preserves the same native shader"
	)
	for child in holder.get_children():
		(child as MeshInstance3D).mesh = null
	holder.free()
