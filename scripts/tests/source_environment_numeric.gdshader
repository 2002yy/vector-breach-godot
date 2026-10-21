shader_type canvas_item;
#include "res://scripts/characters/source_environment_math.gdshaderinc"
uniform sampler2D cases : filter_nearest;
uniform vec4 reflection_sh[128];
void fragment() {
	int x = int(FRAGCOORD.x);
	vec4 parameters = texelFetch(cases,ivec2(x,0),0);
	vec3 normal = texelFetch(cases,ivec2(x,1),0).xyz;
	vec3 irradiance = texelFetch(cases,ivec2(x,2),0).xyz;
	vec3 f0 = texelFetch(cases,ivec2(x,3),0).xyz;
	float factor = source_environment_normalization(parameters.x,normal,irradiance,reflection_sh[int(parameters.z)]);
	SourceEnvBRDF brdf = source_environment_brdf(f0,parameters.x,parameters.y);
	vec2 rough_xy = texelFetch(cases,ivec2(x,4),0).xy;
	vec3 primary,secondary;
	source_hair_frame(normal,vec3(0.0,0.0,1.0),vec3(0.0,1.0,0.0),vec3(-normal.z,0.0,normal.x),rough_xy,0.3,primary,secondary);
	vec3 ray = source_environment_dominant(secondary,vec3(0.0,0.0,1.0),min(dot(rough_xy,vec2(0.5))*1.25,1.0));
	int row = int(FRAGCOORD.y);
	COLOR = vec4(row == 0 ? vec3(factor) : (row == 1 ? brdf.single_scatter : (row == 2 ? brdf.multi_scatter : ray*0.5+0.5)),1.0);
}
