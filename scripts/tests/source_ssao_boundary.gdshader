shader_type spatial;
uniform bool emission_mode=false;
void fragment() {
	ALBEDO=vec3(0.5); ROUGHNESS=1.0;
	RADIANCE=vec4(0,0,0,1);
	if(emission_mode) {
		IRRADIANCE=vec4(0,0,0,1);
		EMISSION=vec3(0.3);
	}
}
