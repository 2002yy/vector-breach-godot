shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color;
uniform float opacity = 1.0;
uniform float age = 0.0;
uniform float seed = 0.0;
uniform bool fire = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 5.0 + vec2(seed * 7.3, -age * 0.7);
	float cloud = noise(p) * 0.57 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.15;
	float radius = length((UV - 0.5) * 2.0);
	float edge = 1.0 - smoothstep(0.28, 0.95, radius + (cloud - 0.5) * 0.28);
	ALPHA = edge * smoothstep(0.18, 0.72, cloud) * opacity;
	vec3 color = fire ? mix(vec3(1.0, 0.17, 0.015), tint.rgb, cloud) : tint.rgb * (0.55 + cloud * 0.9);
	ALBEDO = color;
	EMISSION = fire ? color * (1.0 + cloud * 2.0) : vec3(0.0);
}
