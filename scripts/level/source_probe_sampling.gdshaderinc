// Diagnostic LPV 8.2 atlas sampling. No SH fallback is fabricated.
uniform sampler3D source_probe_texture : filter_linear, repeat_disable;
uniform vec3 source_probe_dimensions;
uniform int source_probe_count = 0;
uniform vec4 source_probe_origin_yaw[128];
uniform vec4 source_probe_min[128];
uniform vec4 source_probe_size[128];
uniform vec4 source_probe_inv_edge[128];
uniform vec4 source_probe_atlas_size[128];
uniform vec4 source_probe_atlas_offset[128];

vec4 sample_source_probes(vec3 position_source, vec3 direction_source) {
	vec3 direction = normalize(direction_source);
	vec3 dimensions = source_probe_dimensions * vec3(1.0,1.0,1.0/6.0);
	vec3 face = mix(vec3(0.0,1.0,2.0),vec3(3.0,4.0,5.0),step(direction,vec3(0.0))) / 6.0;
	vec3 result = vec3(0.0);
	float coverage = 0.0;
	int blended = 0;
	for (int index = 0; index < source_probe_count; index++) {
		vec4 origin_yaw = source_probe_origin_yaw[index];
		vec3 p = position_source-origin_yaw.xyz;
		float c = cos(origin_yaw.w);
		float s = sin(origin_yaw.w);
		p.xy = mat2(vec2(c,-s),vec2(s,c)) * p.xy;
		vec3 local_coord = (p-source_probe_min[index].xyz)/source_probe_size[index].xyz;
		vec3 edge = clamp(min(local_coord,vec3(1.0)-local_coord)*source_probe_inv_edge[index].xyz,vec3(0.0),vec3(1.0));
		float fade = min(edge.x,min(edge.y,edge.z));
		float weight = fade*fade*(3.0-2.0*fade)*(1.0-coverage);
		if (weight <= 0.0) { continue; }
		vec3 coords = clamp(local_coord,vec3(0.5)/dimensions,(dimensions-vec3(0.5))/dimensions);
		coords = (coords*source_probe_atlas_size[index].xyz+source_probe_atlas_offset[index].xyz)/dimensions;
		coords.z /= 6.0;
		vec3 color = textureLod(source_probe_texture,coords+vec3(0,0,face.x),0.0).rgb*direction.x*direction.x;
		color += textureLod(source_probe_texture,coords+vec3(0,0,face.y),0.0).rgb*direction.y*direction.y;
		color += textureLod(source_probe_texture,coords+vec3(0,0,face.z),0.0).rgb*direction.z*direction.z;
		result += color*weight;
		coverage += weight;
		blended++;
		if (coverage > 0.99 || blended == 4) { break; }
	}
	return vec4(result,coverage);
}
