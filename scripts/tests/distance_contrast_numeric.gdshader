shader_type canvas_item;
render_mode unshaded;
#include "res://scripts/characters/source_distance_contrast.gdshaderinc"

uniform vec3 lit_color = vec3(0.2, 0.3, 0.4);
uniform vec3 surface_albedo = vec3(0.5);
uniform vec3 average_albedo = vec3(0.5);
uniform vec3 irradiance_away = vec3(0.0);
uniform vec3 irradiance_toward = vec3(0.0);
uniform float distance_m = 35.56;
uniform float source_unit_m = 0.0254;
uniform float source_exposure = 0.5;
uniform float contrast_strength = 0.8;
uniform float fog_modification = 1.0;
uniform bool material_adjustment = true;

void fragment() {
	COLOR = vec4(source_distance_contrast(lit_color, surface_albedo, average_albedo,
		irradiance_away, irradiance_toward, distance_m, source_unit_m,
		source_exposure, contrast_strength, fog_modification, material_adjustment), 1.0);
}
