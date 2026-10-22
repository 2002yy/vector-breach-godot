#include "res://scripts/level/source_reflection_box.gdshaderinc"
uniform samplerCubeArray native_reflection : filter_linear_mipmap;
uniform mat4 game_to_source;
uniform int reflection_count = 0;
uniform vec4 reflection_origin_yaw[128];
uniform vec4 reflection_minimum[128];
uniform vec4 reflection_size[128];
uniform vec4 reflection_inverse_edge[128];
uniform vec4 reflection_sh[128];

// Explicit diagnostic consumer; no BRDF, radiance normalization or ambient fallback.
// VRF environment.slang: total starts at .01, residual fade, stop above .99.
vec4 source_reflection_internal(vec3 world, vec3 world_ray, float lod, bool signature, out vec4 harmonic) {
	vec3 position = (game_to_source * vec4(world, 1.0)).xyz;
	vec3 ray = mat3(game_to_source) * world_ray;
	vec3 result = vec3(0.0);
	float total = 0.01;
	float coverage = 0.0;
	harmonic = vec4(0.0);
	for (int i = 0; i < reflection_count; i++) {
		vec4 placement = reflection_origin_yaw[i];
		vec3 delta = position - placement.xyz;
		float c = cos(placement.w), s = sin(placement.w);
		vec3 local = vec3(c * delta.x + s * delta.y, -s * delta.x + c * delta.y, delta.z);
		vec3 minimum = reflection_minimum[i].xyz;
		vec3 size = reflection_size[i].xyz;
		vec3 maximum = minimum + size;
		if (any(lessThan(local, minimum)) || any(greaterThan(local, maximum))) { continue; }
		vec3 edge = min(clamp((local-minimum)*reflection_inverse_edge[i].xyz, vec3(0.0), vec3(1.0)),
			clamp((maximum-local)*reflection_inverse_edge[i].xyz, vec3(0.0), vec3(1.0)));
		float distance_to_edge = min(edge.x, min(edge.y, edge.z));
		if (distance_to_edge == 0.0) { continue; }
		float weight = distance_to_edge * distance_to_edge * (3.0-2.0*distance_to_edge) * (1.0-total);
		vec4 projected = source_reflection_box(position, ray, placement, minimum, size);
		if (projected.a == 0.0) { continue; }
		float cube = reflection_minimum[i].w;
		vec3 value = signature ? vec3(cube / 128.0, projected.x * 0.5+0.5, projected.y * 0.5+0.5)
			: textureLod(native_reflection, vec4(projected.xyz,cube), lod).rgb;
		result += value * weight;
		harmonic += reflection_sh[int(cube)] * weight;
		total += weight;
		coverage += weight;
		if (total > 0.99) { break; }
	}
	harmonic /= total;
	return vec4(result, coverage);
}

vec4 sample_source_reflection(vec3 world, vec3 world_ray, float lod, bool signature) {
	vec4 unused;
	return source_reflection_internal(world,world_ray,lod,signature,unused);
}

// Native character PS divides accumulated radiance and SH by total, including
// the .01 initial reserve. Keep the earlier raw-radiance diagnostic unchanged.
vec4 source_character_reflection(vec3 world, vec3 ray, float lod, out vec4 harmonic) {
	vec4 value = source_reflection_internal(world,ray,lod,false,harmonic);
	value.rgb /= (0.01+value.a);
	return value;
}
