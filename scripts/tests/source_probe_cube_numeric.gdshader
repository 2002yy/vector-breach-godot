shader_type canvas_item;
#include "res://scripts/level/source_probe_sampling.gdshaderinc"
#include "res://scripts/characters/source_indirect_math.gdshaderinc"
#include "res://scripts/level/source_probe_cube.gdshaderinc"
uniform sampler2D cases : filter_nearest;
void fragment() {
	int x=int(FRAGCOORD.x);
	vec3 point=texelFetch(cases,ivec2(x,0),0).rgb;
	vec3 n=texelFetch(cases,ivec2(x,1),0).rgb;
	SourceProbeCube cube=source_probe_cube(point);
	vec4 legacy=sample_source_probes(point,n);
	int row=int(FRAGCOORD.y);
	COLOR=row==0 ? vec4(source_probe_cube_raw(cube,n),cube.coverage) :
		(row==1 ? legacy : (row==2 ? vec4(source_probe_cube_complete(cube,n),1.0) : vec4(legacy.rgb+source_probe_remainder(n,legacy.a),1.0)));
}
