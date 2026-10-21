shader_type canvas_item;
render_mode unshaded;
#include "res://scripts/level/source_reflection_box.gdshaderinc"
uniform sampler2D cases : filter_nearest;
void fragment() {
	int column = int(FRAGCOORD.x);
	vec4 result = source_reflection_box(texelFetch(cases, ivec2(column,0),0).xyz,
		texelFetch(cases, ivec2(column,1),0).xyz, texelFetch(cases, ivec2(column,2),0),
		texelFetch(cases, ivec2(column,3),0).xyz, texelFetch(cases, ivec2(column,4),0).xyz);
	COLOR = vec4(int(FRAGCOORD.y) == 0 ? result.xyz * 0.5 + 0.5 : vec3(result.a), 1.0);
}
