shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://scripts/characters/source_indirect_math.gdshaderinc"
uniform float material_ao=1.0;
void fragment() {
	ALBEDO=vec3(0.3,0.5,0.7);
	ROUGHNESS=1.0;
	AO=material_ao;
	if(source_indirect_enabled) {
		SourceIndirectEnergy terms=source_indirect_energy(vec3(0.4,0.6,0.8),vec3(0.2),vec3(0.1),vec3(0.05),ALBEDO,0.0,material_ao);
		IRRADIANCE=vec4(0.0,0.0,0.0,1.0);
		RADIANCE=vec4(0.0,0.0,0.0,1.0);
		EMISSION=terms.diffuse+terms.specular;
	}
}
