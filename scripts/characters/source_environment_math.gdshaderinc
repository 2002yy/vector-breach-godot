uniform sampler2DArray source_brdf_lut : filter_linear, repeat_disable;

struct SourceEnvBRDF { vec3 single_scatter; vec3 multi_scatter; };

SourceEnvBRDF source_environment_brdf(vec3 f0, float roughness, float ndotv) {
	vec2 uv = vec2(clamp(roughness,0.0,1.0),sqrt(1.0-clamp(ndotv,0.0,1.0))) * (63.0/64.0) + vec2(1.0/128.0);
	vec2 lut = textureLod(source_brdf_lut,vec3(uv,1.0),0.0).rg;
	SourceEnvBRDF result;
	result.single_scatter = mix(vec3(lut.x),vec3(lut.y),f0);
	float missing = 1.0-lut.y;
	vec3 average_fresnel = f0+(vec3(1.0)-f0)/21.0;
	result.multi_scatter = result.single_scatter*average_fresnel/(vec3(1.0)-average_fresnel*missing)*missing;
	return result;
}

float source_environment_normalization(float roughness, vec3 source_normal, vec3 irradiance, vec4 harmonic) {
	float baked = dot(vec4(source_normal,1.0),harmonic);
	return baked <= 0.0 ? 1.0 : min(dot(irradiance,vec3(0.2125,0.7154,0.0721))/baked,max(roughness*2.0+1.0,1.0));
}

vec3 source_environment_dominant(vec3 normal, vec3 view, float roughness) {
	float squared = roughness*roughness;
	float smoothness = clamp(1.0-squared,0.0,1.0);
	return normalize(mix(normal,reflect(-view,normal),smoothness*(sqrt(smoothness)+squared)));
}

vec3 source_environment_safe(vec3 value, vec3 fallback) {
	return dot(value,value)>1e-12 ? normalize(value) : fallback;
}

void source_hair_frame(vec3 normal,vec3 view,vec3 tangent,vec3 bitangent,vec2 rough_xy,float shift,
	out vec3 primary,out vec3 secondary) {
	bool wider_x = rough_xy.x >= rough_xy.y;
	vec3 shift_axis = wider_x ? tangent : bitangent;
	vec3 warp_axis = wider_x ? bitangent : tangent;
	float warp = (1.0-min(rough_xy.x/rough_xy.y,rough_xy.y/rough_xy.x))*0.5;
	vec3 warped = source_environment_safe(cross(cross(view,warp_axis),warp_axis),normal);
	primary = source_environment_safe(mix(normal,warped,warp),normal);
	vec3 shifted = source_environment_safe(normal-shift_axis*shift,normal);
	secondary = source_environment_safe(mix(shifted,warped,warp),shifted);
}
