shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, fog_disabled;

// csgo_static_overlay mode 3 samples encoded RGB, then blends toward neutral
// 0.5 by opacity. Source blend factors DEST_COLOR / SRC_COLOR give 2*S*D.
// Godot blend_mul gives S*D, so supply twice that neutral-adjusted source.
// Reference: ValveResourceFormat complex.frag.slang / RenderMaterial.cs,
// commit 54279ec226cc3e1c561b10f11f0f5e879b981e6e.
// Deliberately no source_color: mode 3 undoes the sRGB texture decode.
uniform sampler2D source_color_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float source_opacity = 1.0;
uniform vec3 source_tint = vec3(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float surface_offset = 0.0;
uniform bool source_fog_enabled = true;
uniform bool fog_enabled = false;
uniform float fog_density = 0.0;
uniform float fog_height = 0.0;
uniform float fog_height_density = 0.0;
uniform bool depth_fog = false;
uniform float fog_depth_begin = 10.0;
uniform float fog_depth_end = 100.0;
uniform float fog_depth_curve = 1.0;

void vertex() {
	VERTEX += NORMAL * surface_offset;
	UV = UV * uv_scale.xy + uv_offset.xy;
}

void fragment() {
	vec4 texel = texture(source_color_texture, UV);
	float coverage = clamp(texel.a * source_opacity, 0.0, 1.0);
	// Multiplicative contributions fade toward the neutral multiplier with fog;
	// adding the scene fog color here would tint the already-fogged destination.
	if (source_fog_enabled && fog_enabled) {
		float amount = 1.0 - exp(-length(VERTEX) * fog_density);
		if (depth_fog) {
			amount = pow(smoothstep(fog_depth_begin, fog_depth_end, length(VERTEX)), fog_depth_curve) * fog_density;
		}
		if (abs(fog_height_density) >= 0.0001) {
			float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
			amount = max(amount, 1.0 - exp(min(0.0, (world_y - fog_height) * fog_height_density)));
		}
		coverage *= 1.0 - clamp(amount, 0.0, 1.0);
	}
	ALBEDO = mix(vec3(1.0), 2.0 * texel.rgb * source_tint, coverage);
	ALPHA = 1.0;
}
