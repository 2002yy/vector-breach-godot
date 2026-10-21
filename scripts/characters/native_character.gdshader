shader_type spatial;
render_mode diffuse_lambert, cull_back;
#include "res://scripts/characters/source_eye_distance.gdshaderinc"

// Source character channel contracts / BRDF reference: ValveResourceFormat
// 54279ec226cc3e1c561b10f11f0f5e879b981e6e, complex.frag / common/pbr.
// Direct lighting is ported here; environment lighting remains Godot PBR.
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D metal_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D ao_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D cloth_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D retro_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D aniso_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D skin_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D skin_falloff : source_color, filter_linear, repeat_disable;
uniform vec4 base_color = vec4(1.0);
uniform bool use_base = false;
uniform bool use_normal = false;
uniform bool use_roughness = false;
uniform bool use_metal = false;
uniform bool use_ao = false;
uniform int roughness_channel = 1;
uniform int metal_channel = 2;
uniform int ao_channel = 0;
uniform float base_roughness = 1.0;
uniform float base_metallic = 1.0;
uniform float normal_strength = 1.0;
uniform float ao_light_affect = 0.0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform bool enable_cloth = false;
uniform bool enable_skin = false;
uniform bool enable_aniso = false;
uniform bool enable_retro = false;
uniform bool enable_hair = false;
uniform float hair_roughness_scale = 1.25;
uniform float hair_shift = 0.3;
uniform float hair_transmission = 0.3;
uniform float sheen_scale = 1.0;
uniform vec3 sheen_tint = vec3(1.0);
uniform vec3 normal_softness = vec3(1.0, 0.302, 0.0);
uniform float curvature_scale = 1.0;
uniform bool spherical_aniso = false;
uniform vec3 aniso_pole = vec3(0.0, 1.0, 0.0);
uniform float aniso_angle = 0.0;
uniform float feature_weight = 1.0;
uniform bool enable_eyes = false;
uniform bool enable_eye_distance_filter = true;
uniform float eye_weight = 1.0;
uniform sampler2D eye_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D eye_mask_texture : filter_linear_mipmap_anisotropic;
uniform vec3 eye_left_center;
uniform vec3 eye_right_center;
uniform vec3 eye_left_forward = vec3(0.0, 0.0, -1.0);
uniform vec3 eye_right_forward = vec3(0.0, 0.0, -1.0);
uniform vec3 eye_left_up = vec3(0.0, 1.0, 0.0);
uniform vec3 eye_right_up = vec3(0.0, 1.0, 0.0);
uniform float eye_radius = 0.0;
uniform float eye_hue = 0.0;
uniform float eye_iris = 1.0;
uniform float eye_pupil = 0.15;
uniform float eye_saturation = 1.0;

varying vec3 spherical_axis;
varying vec3 geom_normal;
varying vec3 basis_t;
varying vec3 basis_b;
varying vec2 rough_xy;
varying float cloth_mask;
varying float skin_mask;
varying float curvature;
varying float retro_mask;
varying float hair_mask;

vec3 safe_normalize(vec3 value, vec3 fallback) {
	return dot(value, value) > 0.000001 ? normalize(value) : fallback;
}

float read_channel(vec4 value, int channel) {
	if (channel == 0) { return value.r; }
	if (channel == 1) { return value.g; }
	if (channel == 2) { return value.b; }
	if (channel == 3) { return value.a; }
	return dot(value.rgb, vec3(1.0 / 3.0));
}

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
	vec3 axis = safe_normalize(cross(aniso_pole, NORMAL), TANGENT);
	float angle = radians(aniso_angle);
	axis = axis * cos(angle) + cross(NORMAL, axis) * sin(angle);
	spherical_axis = safe_normalize(MODELVIEW_NORMAL_MATRIX * axis, vec3(1.0, 0.0, 0.0));
}

void fragment() {
	vec4 color = base_color;
	if (use_base) { color *= texture(base_texture, UV); }
	ALBEDO = color.rgb;
	retro_mask = enable_retro ? texture(retro_texture, UV).r * feature_weight : 0.0;
	ROUGHNESS = base_roughness;
	METALLIC = base_metallic;
	if (use_roughness) { ROUGHNESS *= read_channel(texture(roughness_texture, UV), roughness_channel); }
	if (use_metal) { METALLIC *= read_channel(texture(metal_texture, UV), metal_channel); }
	AO = use_ao ? read_channel(texture(ao_texture, UV), ao_channel) : 1.0;
	AO_LIGHT_AFFECT = ao_light_affect;
	geom_normal = normalize(NORMAL);
	basis_t = safe_normalize(TANGENT, vec3(1.0, 0.0, 0.0));
	basis_b = safe_normalize(BINORMAL, vec3(0.0, 1.0, 0.0));
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	cloth_mask = 0.0;
	if (enable_cloth) {
		vec3 packed = texture(cloth_texture, UV).rgb;
		cloth_mask = packed.b * (1.0 - packed.g) * feature_weight;
	}
	rough_xy = vec2(ROUGHNESS);
	if (enable_aniso) {
		rough_xy = mix(rough_xy, texture(aniso_texture, UV).rg, feature_weight);
	}
	float geometric_roughness = sqrt(clamp(max(dot(dFdx(geom_normal), dFdx(geom_normal)), dot(dFdy(geom_normal), dFdy(geom_normal))), 0.0, 1.0));
	rough_xy = clamp(max(rough_xy, vec2(geometric_roughness)), vec2(0.045), vec2(1.0));
	// The geometric mean retains lobe area for Godot's environment reflection.
	ROUGHNESS = sqrt(rough_xy.x * rough_xy.y);
	skin_mask = enable_skin ? texture(skin_texture, UV).g * feature_weight : 0.0;
	// Native csgo_character PS: SSS red is hair; green remains skin diffusion.
	hair_mask = enable_hair ? texture(skin_texture, UV).r * feature_weight : 0.0;
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// VRF csgo_character_eyes_ps / native S_EYEBALLS: ray/sphere iris projection.
	// Calibrated bone positions are world metres; textures retain native RGB/alpha.
	if (enable_eyes && eye_radius > 0.0) {
		float mask = texture(eye_mask_texture, UV, -0.5).r * feature_weight * eye_weight;
		bool left_eye = distance(world_position, eye_left_center) <= distance(world_position, eye_right_center);
		vec3 center = left_eye ? eye_left_center : eye_right_center;
		vec3 forward = safe_normalize(left_eye ? eye_left_forward : eye_right_forward, vec3(0.0, 0.0, -1.0));
		vec3 up = safe_normalize(left_eye ? eye_left_up : eye_right_up, vec3(0.0, 1.0, 0.0));
		vec3 right = safe_normalize(cross(up, forward), vec3(-1.0, 0.0, 0.0));
		up = safe_normalize(cross(forward, right), up);
		vec3 offset = CAMERA_POSITION_WORLD - center;
		vec3 ray = safe_normalize(world_position - CAMERA_POSITION_WORLD, -forward);
		float projection = dot(offset, ray);
		float discriminant = projection * projection - dot(offset, offset) + eye_radius * eye_radius;
		float hit_distance = -projection - sqrt(max(discriminant, 0.0));
		if (mask > 0.0 && discriminant > 0.0 && hit_distance > 0.0) {
			vec3 sphere_normal = normalize(CAMERA_POSITION_WORLD + ray * hit_distance - center);
			vec2 projected = vec2(dot(sphere_normal, right), dot(sphere_normal, -up));
			float radial = length(projected);
			vec2 iris_uv = mix(projected * (2.0 - eye_iris), projected, vec2(radial));
			vec4 texel = texture(eye_albedo, iris_uv * 0.5 + 0.5, -0.5);
			vec3 grey_axis = vec3(0.57735);
			vec3 rotated = texel.rgb * cos(eye_hue) + cross(grey_axis, texel.rgb) * sin(eye_hue) + grey_axis * dot(grey_axis, texel.rgb) * (1.0 - cos(eye_hue));
			vec3 eye_color = mix(texel.rgb, rotated, texel.a);
			eye_color = mix(eye_color, mix(vec3(dot(eye_color, vec3(0.2125, 0.7154, 0.0721))), eye_color, eye_saturation), texel.a);
			eye_color *= smoothstep(eye_pupil, eye_pupil + 0.03, radial);
			float front = clamp(dot(forward, sphere_normal), 0.0, 1.0);
			eye_color *= front;
			if (enable_eye_distance_filter) {
				eye_color = source_eye_distance_color(eye_color, iris_uv, eye_pupil,
					dFdx(iris_uv.x), distance(CAMERA_POSITION_WORLD, world_position));
			}
			float weight = mask * smoothstep(0.1, 0.3, front);
			ALBEDO = mix(ALBEDO, eye_color, weight);
			rough_xy = mix(rough_xy, vec2(0.1), weight);
			ROUGHNESS = sqrt(rough_xy.x * rough_xy.y);
			vec3 cornea = normalize(mix(sphere_normal, normalize(sphere_normal - forward * 0.5), texel.a));
			vec3 view_cornea = normalize((VIEW_MATRIX * vec4(cornea, 0.0)).xyz);
			vec3 tangent_cornea = vec3(dot(view_cornea, basis_t), dot(view_cornea, basis_b), dot(view_cornea, geom_normal));
			vec3 micro_normal = use_normal ? texture(normal_texture, UV).rgb * 2.0 - 1.0 : vec3(0.0, 0.0, 1.0);
			micro_normal.xy *= normal_strength;
			NORMAL_MAP = normalize(mix(normalize(micro_normal), tangent_cornea, sqrt(weight))) * 0.5 + 0.5;
			NORMAL_MAP_DEPTH = 1.0;
		}
	}
	float inverse_radius_m = length(fwidth(geom_normal)) / max(length(fwidth(world_position)), 0.000001);
	curvature = clamp((inverse_radius_m * curvature_scale - 1.0) / 99.0, 0.0, 1.0);
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Character retroreflection uses native metalness RED, not metalness GREEN.
	// VRF pbr::GetRetroReflectiveNormal; retain the original diffuse NoL.
	vec3 retro_vector = LIGHT - reflect(-VIEW, NORMAL);
	vec3 spec_normal = safe_normalize(mix(NORMAL, retro_vector, retro_mask), NORMAL);
	float nv = clamp(dot(spec_normal, VIEW), 0.0001, 1.0);
	vec3 h = safe_normalize(LIGHT + VIEW, NORMAL);
	float nh = clamp(dot(spec_normal, h), 0.0, 1.0);
	float vh = clamp(dot(VIEW, h), 0.0, 1.0);
	vec3 tangent = safe_normalize(cross(basis_b, NORMAL), basis_t);
	if (spherical_aniso) { tangent = safe_normalize(cross(spherical_axis, NORMAL), tangent); }
	vec3 bitangent = safe_normalize(cross(NORMAL, tangent), basis_b);
	vec2 alpha = rough_xy * rough_xy;
	vec3 dots = vec3(dot(h, tangent) / alpha.x, dot(h, bitangent) / alpha.y, nh);
	float ndf = 1.0 / max(pow(dot(dots, dots), 2.0) * alpha.x * alpha.y, 0.0001);
	float k = pow(max(rough_xy.x, rough_xy.y) + 1.0, 2.0) / 8.0;
	float vis = 1.0 / max(4.0 * (nl * (1.0-k) + k) * (nv * (1.0-k) + k), 0.0001);
	float inv_alpha = 1.0 / max(ROUGHNESS * ROUGHNESS, 0.0001);
	float charlie = (inv_alpha + 2.0) * pow(max(1.0 - nh*nh, 0.0078125), inv_alpha * 0.5) / (2.0 * PI);
	float neubelt = clamp(1.0 / max(4.0 * (nl + nv - nl*nv), 0.00001532), 0.0, 1.0);
	float spec_lobe = mix(ndf * vis, charlie * neubelt * PI * nl, cloth_mask);
	vec3 reflectance = vec3(mix(0.04, 0.046, hair_mask));
	vec3 dielectric = mix(reflectance, clamp(ALBEDO * sheen_tint * sheen_scale, vec3(0.0), vec3(1.0)), cloth_mask);
	vec3 f0 = mix(dielectric, ALBEDO, METALLIC);
	vec3 fresnel = f0 + (vec3(1.0) - f0) * pow(1.0-vh, 5.0);
	vec3 specular = spec_lobe * fresnel;
	if (enable_hair && hair_mask > 0.0) {
		// Native PS secondary lobe shifts the wider roughness axis toward N.
		vec2 shifted_dots = vec2(dot(h, tangent), dot(h, bitangent));
		if (rough_xy.x >= rough_xy.y) {
			shifted_dots.y = dot(h, safe_normalize(bitangent + NORMAL * hair_shift + vec3(0.00001), bitangent));
		} else {
			shifted_dots.x = dot(h, safe_normalize(tangent + NORMAL * hair_shift + vec3(0.00001), tangent));
		}
		vec2 hair_rough = clamp(rough_xy * hair_roughness_scale, vec2(0.045), vec2(1.0));
		vec2 hair_alpha = hair_rough * hair_rough;
		vec3 hair_dots = vec3(shifted_dots / hair_alpha, nh);
		float hair_ndf = 1.0 / max(pow(dot(hair_dots, hair_dots), 2.0) * hair_alpha.x * hair_alpha.y, 0.0001);
		float hair_k = pow(max(hair_rough.x, hair_rough.y) + 1.0, 2.0) / 8.0;
		float hair_vis = 1.0 / max(4.0 * (nl * (1.0-hair_k) + hair_k) * (nv * (1.0-hair_k) + hair_k), 0.0001);
		vec3 hair_f0 = safe_normalize(ALBEDO + vec3(0.001), vec3(0.57735)) * reflectance;
		vec3 hair_fresnel = hair_f0 + (vec3(1.0) - hair_f0) * pow(1.0-vh, 5.0);
		specular = mix(specular, hair_ndf * hair_vis * hair_fresnel, clamp(hair_transmission * hair_mask, 0.0, 1.0));
	}
	SPECULAR_LIGHT += specular * nl * ATTENUATION * LIGHT_COLOR * SPECULAR_AMOUNT / PI;
	vec3 diffuse = vec3(nl);
	if (enable_skin) {
		// Diffuse micro-normal softening is per-channel; the specular normal stays sharp.
		float soft_nl = dot(geom_normal, LIGHT);
		vec3 scatter = vec3(pow(clamp(1.0-soft_nl, 0.0, 1.0), 2.0));
		vec3 softness = mix(normal_softness, vec3(1.0), scatter);
		vec3 nr = safe_normalize(mix(NORMAL, geom_normal, softness.r), geom_normal);
		vec3 ng = safe_normalize(mix(NORMAL, geom_normal, softness.g), geom_normal);
		vec3 nb = safe_normalize(mix(NORMAL, geom_normal, softness.b), geom_normal);
		vec3 channel_nl = clamp(vec3(dot(nr, LIGHT), dot(ng, LIGHT), dot(nb, LIGHT)), vec3(0.0), vec3(1.0));
		vec3 falloff = texture(skin_falloff, vec2(soft_nl*0.5+0.5, curvature)).rgb * 0.5 - 0.25;
		diffuse = mix(diffuse, clamp(channel_nl + falloff, vec3(0.0), vec3(1.0)), skin_mask);
	}
	DIFFUSE_LIGHT += diffuse * (1.0-METALLIC) * ATTENUATION * LIGHT_COLOR / PI;
}
