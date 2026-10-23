shader_type spatial;
#include "res://scripts/characters/source_ssao.gdshaderinc"
uniform int mode = 0;
uniform float material_ao = 1.0;
uniform float indirect_energy = 0.3;
uniform float original_emission = 0.0;
void fragment() {
	ALBEDO=vec3(0.5); ROUGHNESS=1.0; AO=material_ao; AO_LIGHT_AFFECT=0.0;
	RADIANCE=vec4(0,0,0,1);
	if(mode!=0) {
		IRRADIANCE=vec4(0,0,0,1);
		EMISSION=vec3(original_emission);
		float factor=mode==1 ? 1.0 : source_screen_occlusion(SCREEN_UV);
		EMISSION+=vec3(indirect_energy*material_ao*factor);
	}
}
