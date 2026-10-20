// Derived from private csgo_character PS combo 0, Steam manifest
// 2520908610273941189, after lighting/fog and before final output.
// Inputs are linear HDR RGB, never display sRGB or an ALBEDO-only substitute.
// Directional irradiance must be sampled at the surface in both view directions.
vec3 source_distance_contrast(
	vec3 lit_color, vec3 surface_albedo, vec3 average_albedo,
	vec3 irradiance_away, vec3 irradiance_toward,
	float distance_m, float source_unit_m, float exposure,
	float strength, float fog_modification, bool material_adjustment
) {
	if (source_unit_m <= 0.0 || strength <= 0.0 || fog_modification <= 0.0) {
		return lit_color;
	}
	float distance_units = distance_m / source_unit_m;
	if (distance_units <= 400.0) { return lit_color; }
	vec3 luma_weights = vec3(0.2125, 0.7154, 0.0721);
	float threshold = dot(average_albedo, luma_weights);
	if (material_adjustment) { threshold = max(threshold, exposure); }
	threshold = max(threshold, 0.001);
	vec3 tint = average_albedo / threshold;
	float largest = max(max(tint.r, tint.g), tint.b);
	float smallest = min(min(tint.r, tint.g), tint.b);
	// Native data has positive average albedo. Also keep empty/black input finite.
	float saturation = (largest - smallest) / max(largest + smallest, 0.000001);
	tint = mix(tint, vec3(1.0), smoothstep(0.45, 0.55, saturation));
	float material_luma = dot(surface_albedo, luma_weights);
	float curve = 0.5 * smoothstep(0.0, threshold, material_luma)
		+ 0.5 * smoothstep(threshold, threshold + 0.15, material_luma);
	float away_luma = clamp(dot(irradiance_away, luma_weights), 0.0, 1.0);
	float toward_luma = clamp(dot(irradiance_toward, luma_weights), 0.0, 1.0);
	// Rewrite native reverse-edge smoothstep explicitly (defined on every GPU).
	float contrast = 1.0 - smoothstep(0.0, 0.5, abs(toward_luma * threshold - away_luma));
	vec3 target = min(vec3(1.0), lit_color * curve * (2.0 + 2.0 * contrast) * tint);
	target += max(vec3(0.0), lit_color - vec3(1.0)) * (material_adjustment ? exposure : 1.0);
	float weight = min(0.8, strength) * smoothstep(400.0, 1400.0, distance_units)
		* clamp(fog_modification, 0.0, 1.0);
	return mix(lit_color, target, weight);
}
