extends RefCounted

const Adapter = preload("res://scripts/characters/SourceCharacterMaterials.gd")


static func run(host: Node) -> void:
	_plain_material(host)
	var hands := preload("res://scripts/player/FirstPersonHands.gd").new()
	host.add_child(hands)
	host.call("_assert_true", hands.is_in_group("first_person_hands"), "hands are discoverable")
	var changes: Array = []
	var retiring: Array = []
	hands.native_changed.connect(func(): changes.append(hands.get_native_hands()))
	hands.native_changing.connect(
		func(visual: Node3D):
			host.call("_assert_true", visual.is_inside_tree(), "retire before visual leaves tree")
			host.call("_assert_equal", visual, hands.get_native_hands(), "retire current rig")
			retiring.append(visual.get_instance_id())
	)
	for profile in ["ct-st6", "t-elite", "missing-hands-fixture"]:
		var had_previous := is_instance_valid(hands.get_native_hands())
		var count := retiring.size()
		hands.set_appearance_profile(profile)
		if had_previous:
			host.call("_assert_equal", retiring.size(), count + 1, "replacement retires old rig")
		var changed := changes.size()
		hands.set_appearance_profile(profile)
		host.call("_assert_equal", changes.size(), changed, "unchanged profile does not rebind")
	host.call("_assert_equal", changes.size(), 3, "one publication per profile transition")
	host.call("_assert_equal", hands.get_native_hands(), null, "missing assets keep fallback")
	hands.free()


static func _plain_material(host: Node) -> void:
	var material := StandardMaterial3D.new()
	host.call(
		"_assert_equal", Adapter.plain_environment_source(material), null, "no generic conversion"
	)
	material.set_meta("source_material_parameters", {"ShaderName": "csgo_character.vfx"})
	material.roughness = 0.37
	material.metallic = 0.24
	material.uv1_scale = Vector3(2, 3, 1)
	var source := Adapter.plain_environment_source(material)
	host.call("_assert_true", source != null, "plain native character PBR can enter candidate")
	host.call(
		"_assert_true",
		is_equal_approx(source.get_shader_parameter("base_roughness"), 0.37),
		"roughness preserved"
	)
	host.call(
		"_assert_equal", source.get_shader_parameter("uv_scale"), material.uv1_scale, "UV preserved"
	)
	host.call("_assert_equal", material.next_pass, null, "original material not modified")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	host.call(
		"_assert_equal",
		Adapter.plain_environment_source(material),
		null,
		"transparent remains original"
	)
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.emission_enabled = true
	host.call(
		"_assert_equal",
		Adapter.plain_environment_source(material),
		null,
		"unmapped emission rejected"
	)
	material.emission_enabled = false
	material.set_meta(
		"source_material_parameters",
		{"ShaderName": "csgo_character.vfx", "IntParams": {"F_UNSUPPORTED_FIXTURE": 1}}
	)
	host.call(
		"_assert_equal",
		Adapter.plain_environment_source(material),
		null,
		"unsupported flags rejected"
	)
