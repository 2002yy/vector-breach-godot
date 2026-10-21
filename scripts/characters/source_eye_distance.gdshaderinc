// csgo_character Vulkan PS, S_EYEBALLS: 0.15 UV derivative gate and
// saturate((distance_in_source_units - 100) * 0.005). One Source unit = .0254 m.
// Use ascending smoothstep edges: reversed edges have undefined GLSL results.
vec3 source_eye_distance_color(vec3 color, vec2 iris_uv, float pupil,
		float derivative_x, float distance_m) {
	if (abs(derivative_x) <= 0.15) { return color; }
	float weight = clamp((distance_m / 0.0254 - 100.0) * 0.005, 0.0, 1.0);
	float highlight = 1.0 - smoothstep(0.08, 0.1, length(iris_uv - vec2(pupil, -pupil)));
	return mix(color, color * 0.8 + vec3(highlight), weight);
}
