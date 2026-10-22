#include "res://scripts/level/source_reflection_sampling.gdshaderinc"
#include "res://scripts/level/source_probe_sampling.gdshaderinc"
#include "res://scripts/characters/source_environment_math.gdshaderinc"
#include "res://scripts/characters/source_indirect_math.gdshaderinc"
#include "res://scripts/level/source_probe_cube.gdshaderinc"
#include "res://scripts/characters/source_body_environment.gdshaderinc"
uniform float source_env_second_weight = 1.0;
uniform bool source_env_enabled = true;
uniform bool source_indirect_softening = true;
uniform bool source_body_enabled = false;

vec3 source_env_safe(vec3 value, vec3 fallback) {
	return dot(value,value) > 1e-12 ? normalize(value) : fallback;
}

vec4 source_indirect_probe(vec3 point,vec3 normal) {
	vec4 value = sample_source_probes(point,normal);
	if (source_indirect_enabled) {
		value.rgb += source_probe_remainder(normal,value.a);
		value.a = 1.0;
	}
	return value;
}

struct SourceHairEnvironment { vec3 specular; vec3 diffuse; float weight; };
SourceHairEnvironment source_hair_environment(vec3 world, vec3 normal, vec3 geometric,
	vec3 tangent, vec3 bitangent, vec3 view,vec2 rough_xy, vec3 albedo, float metallic,float ao,
	vec3 softness,float skin,float mask, float shift, float roughness_scale, float transmission,
	float cloth,vec3 sheen_tint,float sheen_scale) {
	SourceHairEnvironment result;
	result.specular = vec3(0.0); result.diffuse = vec3(0.0); result.weight = 0.0;
	bool body=source_body_enabled && source_indirect_enabled;
	if (!source_env_enabled || (!body && mask <= 0.0)) { return result; }
	vec3 primary_normal,secondary_normal;
	source_hair_frame(normal,view,tangent,bitangent,rough_xy,shift,primary_normal,secondary_normal);
	if(body) { primary_normal=source_body_primary(primary_normal,normal,cloth); }
	float roughness = clamp(dot(rough_xy,vec2(0.5)),0.0,1.0);
	float secondary_roughness = clamp(roughness*roughness_scale,0.0,1.0);
	vec4 primary_sh, secondary_sh;
	vec4 primary = source_character_reflection(world,source_environment_dominant(primary_normal,view,roughness),6.0*sqrt(roughness),primary_sh);
	vec4 secondary=primary;
	secondary_sh=primary_sh;
	if(mask>0.0) {
		secondary=source_character_reflection(world,source_environment_dominant(secondary_normal,view,secondary_roughness),6.0*sqrt(secondary_roughness),secondary_sh);
	}
	vec3 source_primary = normalize(mat3(game_to_source)*primary_normal);
	if(body) { source_primary*=length(primary_normal); }
	vec3 source_secondary = normalize(mat3(game_to_source)*secondary_normal);
	vec3 source_normal = normalize(mat3(game_to_source)*normal);
	vec3 point = (game_to_source*vec4(world,1.0)).xyz;
	SourceProbeCube cube;
	vec4 irradiance;
	if (source_indirect_enabled) {
		cube=source_probe_cube(point);
		irradiance=vec4(source_probe_cube_complete(cube,source_normal),1.0);
	} else {
		irradiance=sample_source_probes(point,source_normal);
	}
	if (primary.a <= 0.0 || secondary.a <= 0.0 || irradiance.a <= 0.0) { return result; }
	float primary_factor = source_environment_normalization(roughness,source_primary,irradiance.rgb,primary_sh);
	float secondary_factor = source_environment_normalization(secondary_roughness,source_secondary,irradiance.rgb,secondary_sh);
	float weight = clamp(transmission*mask*source_env_second_weight,0.0,1.0);
	vec3 f0 = vec3(mix(0.04,0.046,mask))*mix(vec3(1.0),normalize(albedo+vec3(0.001)),weight);
	if(body) { f0=source_character_f0(albedo,metallic,mask,cloth,sheen_tint,sheen_scale)*mix(vec3(1.0),normalize(albedo+vec3(0.001)),weight); }
	SourceEnvBRDF brdf = source_environment_brdf(f0,roughness,max(dot(normal,view),0.0));
	if(body) { brdf=source_body_brdf(f0,roughness,normal,view,cloth); }
	vec3 reflected = mix(primary.rgb*primary_factor,secondary.rgb*secondary_factor,weight);
	result.specular = reflected*(brdf.single_scatter+brdf.multi_scatter);
	result.weight = body ? 1.0 : clamp(mask,0.0,1.0);
	if (source_indirect_enabled) {
		if (!source_indirect_softening) { softness = vec3(0.0); }
		vec3 n_r = normalize(mat3(game_to_source)*source_soft_normal(normal,geometric,softness.r,skin));
		vec3 n_g = normalize(mat3(game_to_source)*source_soft_normal(normal,geometric,softness.g,skin));
		vec3 n_b = normalize(mat3(game_to_source)*source_soft_normal(normal,geometric,softness.b,skin));
		vec3 softened = vec3(source_probe_cube_complete(cube,n_r).r,source_probe_cube_complete(cube,n_g).g,source_probe_cube_complete(cube,n_b).b);
		SourceIndirectEnergy terms = source_indirect_energy(softened,reflected,brdf.single_scatter,brdf.multi_scatter,albedo,metallic,ao);
		if(body) { terms=source_body_energy(softened,reflected,brdf,albedo,metallic,ao,cloth); }
		result.diffuse = terms.diffuse;
		result.specular = terms.specular;
	}
	return result;
}
