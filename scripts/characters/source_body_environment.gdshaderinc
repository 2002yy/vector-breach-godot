// Native character probe combo: cloth keeps diffuse energy and suppresses
// mirror multi-scatter by (1-cloth). Viewer formula differs at partial masks.
vec3 source_body_primary(vec3 warped,vec3 mapped,float cloth) {
	// Native probe combo does not renormalize this blend before dominant-ray
	// reflection or radiance-SH normalization.
	return mix(warped,mapped,cloth);
}

vec3 source_character_f0(vec3 albedo,float metal,float hair,float cloth,vec3 tint,float scale) {
	vec3 dielectric=vec3(mix(0.04,0.046,hair));
	dielectric=mix(dielectric,clamp(tint*sqrt(max(albedo,vec3(0.0)))*scale,vec3(0.0),vec3(1.0)),cloth);
	return mix(dielectric,albedo,metal);
}

SourceEnvBRDF source_body_brdf(vec3 f0,float roughness,vec3 normal,vec3 view,float cloth) {
	float nov=max(dot(normal,view),0.0);
	SourceEnvBRDF result=source_environment_brdf(f0,roughness,nov);
	if(cloth>0.0) {
		float inv_rough=1.0/max(roughness*roughness,0.00001);
		vec3 half_vector=source_environment_safe(normal+view,normal);
		float noh=dot(half_vector,normal);
		float charlie=(2.0+inv_rough)*pow(max(1.0-noh*noh,0.0),inv_rough*0.5)*0.125;
		result.single_scatter=mix(result.single_scatter,f0*charlie,cloth);
		vec2 uv=vec2(clamp(roughness,0.0,1.0),sqrt(1.0-clamp(nov,0.0,1.0)))*(63.0/64.0)+vec2(1.0/128.0);
		float missing=1.0-textureLod(source_brdf_lut,vec3(uv,1.0),0.0).g;
		vec3 average=f0+(vec3(1.0)-f0)/21.0;
		result.multi_scatter=result.single_scatter*average/(vec3(1.0)-average*missing)*missing;
	}
	return result;
}

SourceIndirectEnergy source_body_energy(vec3 irradiance,vec3 reflection,SourceEnvBRDF brdf,
	vec3 albedo,float metallic,float ao,float cloth) {
	SourceIndirectEnergy result;
	result.diffuse=irradiance*(vec3(1.0)-(brdf.single_scatter+brdf.multi_scatter)*(1.0-cloth))*albedo*(1.0-metallic)*ao;
	result.specular=reflection*(brdf.single_scatter+brdf.multi_scatter*(1.0-cloth))*ao;
	return result;
}
