shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, fog_disabled;

#include "res://scripts/characters/source_distance_contrast.gdshaderinc"

// Development-only next_pass. Nothing attaches this to gameplay materials yet.
// Keeping inputs_ready false is mandatory until per-surface lighting data exists.
uniform sampler2D lit_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform bool inputs_ready = false;
uniform vec3 surface_albedo = vec3(0.5);
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_surface_texture = false;
uniform vec3 surface_uv_scale = vec3(1.0);
uniform vec3 surface_uv_offset = vec3(0.0);
uniform vec3 average_albedo = vec3(0.5);
uniform vec3 irradiance_away = vec3(0.0);
uniform vec3 irradiance_toward = vec3(0.0);
uniform float source_unit_m = 0.0254;
uniform float source_exposure = 0.5;
uniform float contrast_strength = 0.0;
uniform float fog_modification = 0.0;
uniform bool material_adjustment = true;
uniform bool use_directional_sh1 = false;
// Native fallback irradiance: dot(R/G/B coefficients, vec4(view direction,1)).
uniform vec4 irradiance_sh_r = vec4(0.0);
uniform vec4 irradiance_sh_g = vec4(0.0);
uniform vec4 irradiance_sh_b = vec4(0.0);

void vertex() {
	UV = UV * surface_uv_scale.xy + surface_uv_offset.xy;
}

void fragment() {
	if (!inputs_ready) { discard; }
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Avoid repainting resolved silhouette coverage when the native rule is identity.
	// Screen-copy colour is already composited at MSAA edges.
	if (source_unit_m <= 0.0 || contrast_strength <= 0.0 || fog_modification <= 0.0
		|| distance(CAMERA_POSITION_WORLD, world_position) <= 400.0 * source_unit_m) { discard; }
	vec3 lit_color = textureLod(lit_screen, SCREEN_UV, 0.0).rgb;
	vec3 local_albedo = surface_albedo;
	if (use_surface_texture) { local_albedo *= texture(surface_texture, UV).rgb; }
	vec3 away = irradiance_away;
	vec3 toward = irradiance_toward;
	if (use_directional_sh1) {
		vec3 direction = normalize(world_position - CAMERA_POSITION_WORLD);
		away = vec3(dot(irradiance_sh_r, vec4(direction, 1.0)), dot(irradiance_sh_g, vec4(direction, 1.0)), dot(irradiance_sh_b, vec4(direction, 1.0)));
		toward = vec3(dot(irradiance_sh_r, vec4(-direction, 1.0)), dot(irradiance_sh_g, vec4(-direction, 1.0)), dot(irradiance_sh_b, vec4(-direction, 1.0)));
	}
	ALBEDO = source_distance_contrast(lit_color, local_albedo, average_albedo,
		away, toward,
		distance(CAMERA_POSITION_WORLD, world_position), source_unit_m,
		source_exposure, contrast_strength, fog_modification, material_adjustment);
	// Remain in the transparent stage after the opaque screen copy. The geometry
	// still uses normal depth testing, so opaque walls cannot reveal a hidden actor.
	ALPHA = 1.0;
}
