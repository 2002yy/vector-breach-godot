shader_type canvas_item;
#include "res://scripts/characters/source_normal_frame.gdshaderinc"
uniform sampler2D cases : filter_nearest;
void fragment() {
	int x=int(FRAGCOORD.x);
	vec4 encoded=texelFetch(cases,ivec2(x,0),0);
	vec3 tangent=texelFetch(cases,ivec2(x,1),0).rgb;
	vec3 bitangent=texelFetch(cases,ivec2(x,2),0).rgb;
	vec3 normal=texelFetch(cases,ivec2(x,3),0).rgb;
	COLOR=vec4(source_mapped_normal(encoded.rgb,encoded.a,tangent,bitangent,normal)*0.5+0.5,1.0);
}
