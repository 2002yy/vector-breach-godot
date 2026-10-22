shader_type canvas_item;
#include "res://scripts/characters/source_environment_math.gdshaderinc"
#include "res://scripts/characters/source_indirect_math.gdshaderinc"
#include "res://scripts/characters/source_body_environment.gdshaderinc"
uniform sampler2D cases : filter_nearest;
void fragment() {
	int x=int(FRAGCOORD.x);
	vec4 albedo=texelFetch(cases,ivec2(x,0),0);
	vec4 irradiance=texelFetch(cases,ivec2(x,1),0);
	vec4 reflection=texelFetch(cases,ivec2(x,2),0);
	vec4 view=texelFetch(cases,ivec2(x,3),0);
	vec4 tint=texelFetch(cases,ivec2(x,4),0);
	float hair=texelFetch(cases,ivec2(x,5),0).r;
	vec3 f0=source_character_f0(albedo.rgb,albedo.a,hair,reflection.a,tint.rgb,tint.a);
	SourceEnvBRDF brdf=source_body_brdf(f0,view.a,vec3(0,0,1),view.rgb,reflection.a);
	SourceIndirectEnergy energy=source_body_energy(irradiance.rgb,reflection.rgb,brdf,albedo.rgb,albedo.a,irradiance.a,reflection.a);
	vec3 primary=source_body_primary(vec3(0.8,0,0.6),vec3(0,0,1),reflection.a);
	vec3 ray=source_environment_dominant(primary,view.rgb,view.a)*0.5+0.5;
	int row=int(FRAGCOORD.y);
	COLOR=vec4(row==0 ? f0 : (row==1 ? brdf.single_scatter : (row==2 ? brdf.multi_scatter : (row==3 ? energy.diffuse : (row==4 ? energy.specular : (row==5 ? ray : primary))))),1.0);
}
