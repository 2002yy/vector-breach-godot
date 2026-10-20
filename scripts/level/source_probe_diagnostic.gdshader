shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, fog_disabled;
#include "res://scripts/level/source_probe_sampling.gdshaderinc"
uniform mat4 game_to_source;
uniform int diagnostic_direction = 0;

void fragment() {
	vec3 world = (INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec3 point = (game_to_source*vec4(world,1.0)).xyz;
	vec3 direction = mat3(game_to_source)*(world-CAMERA_POSITION_WORLD);
	if (diagnostic_direction == 1) { direction = -direction; }
	vec4 probe = sample_source_probes(point,direction);
	// Magenta means uncovered input, never an invented ambient light value.
	ALBEDO = probe.a < 0.99 ? vec3(1.0,0.0,1.0) : probe.rgb;
	ALPHA = 1.0;
}
