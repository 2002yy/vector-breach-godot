shader_type canvas_item;
#include "res://scripts/level/source_probe_sampling.gdshaderinc"
uniform mat4 game_to_source;
uniform vec3 sample_world;
uniform vec3 direction_world;
uniform bool show_coverage = false;
void fragment() {
	vec3 point = (game_to_source*vec4(sample_world,1.0)).xyz;
	vec3 direction = mat3(game_to_source)*direction_world;
	vec4 result = sample_source_probes(point,direction);
	COLOR = vec4(show_coverage ? vec3(result.a) : result.rgb,1.0);
}
