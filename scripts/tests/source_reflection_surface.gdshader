shader_type spatial;
render_mode unshaded;
#include "res://scripts/level/source_reflection_sampling.gdshaderinc"
uniform float native_lod = 0.0;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec3 world_normal = normalize(INV_VIEW_MATRIX * vec4(NORMAL,0.0)).xyz;
	vec3 ray = reflect(-normalize(CAMERA_POSITION_WORLD-world_position),world_normal);
	ALBEDO = sample_source_reflection(world_position,ray,native_lod,false).rgb;
}
