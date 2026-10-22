// Six directions share selection, coordinates and coverage. Atlas order: +XYZ,-XYZ.
struct SourceProbeCube {
	vec3 px; vec3 py; vec3 pz; vec3 nx; vec3 ny; vec3 nz;
	float coverage;
};

SourceProbeCube source_probe_cube(vec3 position_source) {
	SourceProbeCube result;
	result.px=vec3(0.0); result.py=vec3(0.0); result.pz=vec3(0.0);
	result.nx=vec3(0.0); result.ny=vec3(0.0); result.nz=vec3(0.0);
	result.coverage=0.0;
	vec3 dimensions=source_probe_dimensions*vec3(1.0,1.0,1.0/6.0);
	int blended=0;
	for(int index=0;index<source_probe_count;index++) {
		vec4 origin_yaw=source_probe_origin_yaw[index];
		vec3 p=position_source-origin_yaw.xyz;
		float c=cos(origin_yaw.w),s=sin(origin_yaw.w);
		p.xy=mat2(vec2(c,-s),vec2(s,c))*p.xy;
		vec3 local_coord=(p-source_probe_min[index].xyz)/source_probe_size[index].xyz;
		vec3 edge=clamp(min(local_coord,vec3(1.0)-local_coord)*source_probe_inv_edge[index].xyz,vec3(0.0),vec3(1.0));
		float fade=min(edge.x,min(edge.y,edge.z));
		float weight=fade*fade*(3.0-2.0*fade)*(1.0-result.coverage);
		if(weight<=0.0) { continue; }
		vec3 coords=clamp(local_coord,vec3(0.5)/dimensions,(dimensions-vec3(0.5))/dimensions);
		coords=(coords*source_probe_atlas_size[index].xyz+source_probe_atlas_offset[index].xyz)/dimensions;
		coords.z/=6.0;
		result.px+=textureLod(source_probe_texture,coords,0.0).rgb*weight;
		result.py+=textureLod(source_probe_texture,coords+vec3(0,0,1.0/6.0),0.0).rgb*weight;
		result.pz+=textureLod(source_probe_texture,coords+vec3(0,0,2.0/6.0),0.0).rgb*weight;
		result.nx+=textureLod(source_probe_texture,coords+vec3(0,0,3.0/6.0),0.0).rgb*weight;
		result.ny+=textureLod(source_probe_texture,coords+vec3(0,0,4.0/6.0),0.0).rgb*weight;
		result.nz+=textureLod(source_probe_texture,coords+vec3(0,0,5.0/6.0),0.0).rgb*weight;
		result.coverage+=weight;
		blended++;
		if(result.coverage>0.99 || blended==4) { break; }
	}
	return result;
}

vec3 source_probe_cube_raw(SourceProbeCube cube,vec3 normal) {
	vec3 n=normalize(normal);
	return mix(cube.nx,cube.px,step(0.0,n.x))*n.x*n.x
		+mix(cube.ny,cube.py,step(0.0,n.y))*n.y*n.y
		+mix(cube.nz,cube.pz,step(0.0,n.z))*n.z*n.z;
}

vec3 source_probe_cube_complete(SourceProbeCube cube,vec3 normal) {
	return source_probe_cube_raw(cube,normal)+source_probe_remainder(normal,cube.coverage);
}
