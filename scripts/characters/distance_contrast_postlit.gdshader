shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, fog_disabled;

#include "res://scripts/characters/source_distance_contrast.gdshaderinc"

// Development-only next_pass. Nothing attaches this to gameplay materials yet.
// Keeping inputs_ready false is mandatory until per-surface lighting data exists.
uniform sampler2D lit_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform bool inputs_ready = false;
uniform vec3 surface_albedo = vec3(0.5);
uniform vec3 average_albedo = vec3(0.5);
uniform vec3 irradiance_away = vec3(0.0);
uniform vec3 irradiance_toward = vec3(0.0);
uniform float source_unit_m = 0.0254;
uniform float source_exposure = 0.5;
uniform float contrast_strength = 0.0;
uniform float fog_modification = 0.0;
uniform bool material_adjustment = true;

void fragment() {
	if (!inputs_ready) { discard; }
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 lit_color = textureLod(lit_screen, SCREEN_UV, 0.0).rgb;
	ALBEDO = source_distance_contrast(lit_color, surface_albedo, average_albedo,
		irradiance_away, irradiance_toward,
		distance(CAMERA_POSITION_WORLD, world_position), source_unit_m,
		source_exposure, contrast_strength, fog_modification, material_adjustment);
	// Remain in the transparent stage after the opaque screen copy. The geometry
	// still uses normal depth testing, so opaque walls cannot reveal a hidden actor.
	ALPHA = 1.0;
}
