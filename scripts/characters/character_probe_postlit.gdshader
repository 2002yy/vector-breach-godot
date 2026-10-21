shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, fog_disabled;
#include "res://scripts/level/source_probe_sampling.gdshaderinc"
#include "res://scripts/characters/source_distance_contrast.gdshaderinc"

uniform sampler2D lit_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool inputs_ready = false;
uniform bool use_surface_texture = false;
uniform vec3 surface_albedo = vec3(1.0);
uniform vec3 surface_uv_scale = vec3(1.0);
uniform vec3 surface_uv_offset = vec3(0.0);
uniform vec3 average_albedo = vec3(0.5);
uniform mat4 game_to_source;
uniform float source_exposure = 0.5;
uniform float contrast_strength = 0.0;
uniform float fog_modification = 0.0;
uniform bool material_adjustment = false;

void vertex() {
	UV = UV * surface_uv_scale.xy + surface_uv_offset.xy;
}

void fragment() {
	if (!inputs_ready || source_probe_count <= 0 || contrast_strength <= 0.0 || fog_modification <= 0.0) { discard; }
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX,1.0)).xyz;
	float distance_m = distance(world,CAMERA_POSITION_WORLD);
	if (distance_m <= 400.0*0.0254) { discard; }
	vec3 position_source = (game_to_source*vec4(world,1.0)).xyz;
	vec3 direction_source = mat3(game_to_source)*(world-CAMERA_POSITION_WORLD);
	vec4 away = sample_source_probes(position_source,direction_source);
	vec4 toward = sample_source_probes(position_source,-direction_source);
	// Preserve the existing frame when the native SH fallback is unavailable.
	if (away.a < 0.99 || toward.a < 0.99) { discard; }
	vec3 albedo = surface_albedo;
	if (use_surface_texture) { albedo *= texture(surface_texture,UV).rgb; }
	vec3 lit = textureLod(lit_screen,SCREEN_UV,0.0).rgb;
	ALBEDO = source_distance_contrast(lit,albedo,average_albedo,away.rgb,toward.rgb,
		distance_m,0.0254,source_exposure,contrast_strength,fog_modification,material_adjustment);
	ALPHA = 1.0;
}
