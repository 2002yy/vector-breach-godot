extends RefCounted

const PREFIX := '#include "res://scripts/characters/source_hair_environment.gdshaderinc"\n'
const ANCHOR := "\tcurvature = clamp((inverse_radius_m * curvature_scale - 1.0) / 99.0, 0.0, 1.0);"
const INJECT := """
	vec3 env_micro = use_normal ? NORMAL_MAP*2.0-1.0 : vec3(0.0,0.0,1.0);
	env_micro.xy *= NORMAL_MAP_DEPTH;
	env_micro.z = sqrt(max(1.0-dot(env_micro.xy,env_micro.xy),0.0));
	vec3 env_view_normal = safe_normalize(basis_t*env_micro.x+basis_b*env_micro.y
		+geom_normal*env_micro.z,geom_normal);
	vec3 env_world_normal = normalize(mat3(INV_VIEW_MATRIX)*env_view_normal);
	vec3 env_tangent = safe_normalize(cross(basis_b,env_view_normal),basis_t);
	if (spherical_aniso) {
		env_tangent = safe_normalize(cross(spherical_axis,env_view_normal),env_tangent);
	}
	vec3 env_world_tangent = normalize(mat3(INV_VIEW_MATRIX)*env_tangent);
	vec3 env_world_bitangent = normalize(cross(env_world_normal,env_world_tangent));
	vec3 env_geometric = normalize(mat3(INV_VIEW_MATRIX)*geom_normal);
	SourceHairEnvironment env_hair = source_hair_environment(world_position,env_world_normal,
		env_geometric,env_world_tangent,env_world_bitangent,
		normalize(CAMERA_POSITION_WORLD-world_position),rough_xy,ALBEDO,METALLIC,AO,
		normal_softness,skin_mask,hair_mask,hair_shift,hair_roughness_scale,hair_transmission,
		cloth_mask,sheen_tint,sheen_scale);
	if (env_hair.weight > 0.0) {
		RADIANCE = vec4(0.0,0.0,0.0,env_hair.weight);
		EMISSION += env_hair.specular*env_hair.weight;
		if (source_indirect_enabled) {
			IRRADIANCE = vec4(0.0,0.0,0.0,env_hair.weight);
			EMISSION += env_hair.diffuse*env_hair.weight;
		}
	}
"""
var materials: Array[ShaderMaterial] = []
var _bindings: Array = []
var _followers: Array[Node] = []


func attach(
	root: Node,
	reflection: RefCounted,
	probes: RefCounted,
	inputs: RefCounted,
	diagnostic := false,
	body_diagnostic := false
) -> int:
	if not diagnostic:
		return 0
	var binding_start := _bindings.size()
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.material_override != null or mesh.material_overlay != null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var already := false
			for entry in _bindings:
				if entry.mesh == mesh and entry.surface == surface:
					already = true
			if already:
				continue
			var original := mesh.get_active_material(surface) as ShaderMaterial
			if (
				original == null
				or original.next_pass != null
				or (not body_diagnostic and original.get_shader_parameter("enable_hair") != true)
			):
				continue
			if original.shader == null or original.shader.code.count(ANCHOR) != 1:
				continue
			var material := original.duplicate() as ShaderMaterial
			var shader := Shader.new()
			shader.code = (
				original
				. shader
				. code
				. replace(
					"// Source character channel contracts",
					PREFIX + "// Source character channel contracts"
				)
				. replace(ANCHOR, ANCHOR + INJECT)
			)
			material.shader = shader
			material.set_shader_parameter("source_body_enabled", body_diagnostic)
			if (
				not reflection.bind(material)
				or not probes.bind(material)
				or not inputs.bind(material)
			):
				continue
			_bindings.append(
				{
					"mesh": mesh,
					"surface": surface,
					"original": original,
					"previous": mesh.get_surface_override_material(surface),
					"copy": material
				}
			)
			materials.append(material)
			mesh.set_surface_override_material(surface, material)
			count += 1
	if count > 0:
		var follower := (
			preload("res://scripts/characters/SourceEnvironmentMaterialFollower.gd").new()
		)
		follower.bindings = _bindings.slice(binding_start)
		root.add_child(follower)
		_followers.append(follower)
	return count


func detach() -> void:
	for entry in _bindings:
		if (
			is_instance_valid(entry.mesh)
			and entry.mesh.get_surface_override_material(entry.surface) == entry.copy
		):
			entry.mesh.set_surface_override_material(entry.surface, entry.previous)
	_bindings.clear()
	materials.clear()
	for follower in _followers:
		if is_instance_valid(follower):
			follower.queue_free()
	_followers.clear()
