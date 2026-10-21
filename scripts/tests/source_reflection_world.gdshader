shader_type canvas_item;
#include "res://scripts/level/source_reflection_sampling.gdshaderinc"
uniform sampler2D cases : filter_nearest;
uniform bool signature = true;
uniform float native_lod = 0.0;
void fragment() {
	int x = int(FRAGCOORD.x);
	vec3 point = texelFetch(cases, ivec2(x,0),0).xyz;
	vec3 ray = texelFetch(cases, ivec2(x,1),0).xyz;
	vec4 result = sample_source_reflection(point, ray, native_lod, signature);
	COLOR = vec4(int(FRAGCOORD.y) == 0 ? result.rgb : vec3(result.a),1.0);
}
