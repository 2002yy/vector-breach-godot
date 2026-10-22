uniform bool source_indirect_enabled = false;
uniform vec4 source_ambient_sh_r;
uniform vec4 source_ambient_sh_g;
uniform vec4 source_ambient_sh_b;

vec3 source_probe_remainder(vec3 normal,float coverage) {
	float remainder = coverage < 0.99 ? 1.0-coverage : 0.0;
	vec4 axis_normal = vec4(normal*abs(normal),1.0);
	return remainder*vec3(dot(axis_normal,source_ambient_sh_r),dot(axis_normal,source_ambient_sh_g),dot(axis_normal,source_ambient_sh_b));
}

vec3 source_soft_normal(vec3 mapped,vec3 geometric,float softness,float skin) {
	vec3 value = mix(mapped,geometric,softness*skin);
	return dot(value,value)>1e-12 ? normalize(value) : geometric;
}

struct SourceIndirectEnergy { vec3 diffuse; vec3 specular; };
SourceIndirectEnergy source_indirect_energy(vec3 irradiance,vec3 reflection,vec3 single,vec3 multi,
	vec3 albedo,float metallic,float ao) {
	vec3 claimed = single+multi;
	SourceIndirectEnergy result;
	result.diffuse = irradiance*(vec3(1.0)-claimed)*albedo*(1.0-metallic)*ao;
	result.specular = reflection*claimed*ao;
	return result;
}
