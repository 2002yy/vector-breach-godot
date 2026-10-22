shader_type canvas_item;
#include "res://scripts/characters/source_environment_math.gdshaderinc"
#include "res://scripts/characters/source_indirect_math.gdshaderinc"
uniform sampler2D cases : filter_nearest;
vec3 probe(int x,vec3 n,float coverage) {
	vec3 value=vec3(0.0);
	for(int a=0;a<3;a++) {
		int face=n[a]>=0.0 ? a : a+3;
		value+=texelFetch(cases,ivec2(x,5+face),0).rgb*n[a]*n[a];
	}
	return value+source_probe_remainder(n,coverage);
}
void fragment() {
	int x=int(FRAGCOORD.x);
	vec4 mapped=texelFetch(cases,ivec2(x,0),0);
	vec4 geom=texelFetch(cases,ivec2(x,1),0);
	vec4 albedo=texelFetch(cases,ivec2(x,2),0);
	vec4 reflection=texelFetch(cases,ivec2(x,3),0);
	vec2 parameters=texelFetch(cases,ivec2(x,4),0).xy;
	vec3 softened=vec3(0.0);
	vec3 softness=vec3(1.0,0.302,0.0);
	for(int c=0;c<3;c++) {
		vec3 n=source_soft_normal(mapped.xyz,geom.xyz,softness[c],geom.w);
		softened[c]=probe(x,n,mapped.w)[c];
	}
	SourceEnvBRDF brdf=source_environment_brdf(vec3(0.046,0.035,0.02),parameters.x,parameters.y);
	SourceIndirectEnergy energy=source_indirect_energy(softened,reflection.rgb,brdf.single_scatter,brdf.multi_scatter,albedo.rgb,albedo.a,reflection.a);
	int row=int(FRAGCOORD.y);
	COLOR=vec4(row==0 ? probe(x,mapped.xyz,mapped.w) : (row==1 ? softened : (row==2 ? energy.diffuse : energy.specular)),1.0);
}
