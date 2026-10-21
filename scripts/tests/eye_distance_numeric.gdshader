shader_type canvas_item;
render_mode unshaded;
#include "res://scripts/characters/source_eye_distance.gdshaderinc"
uniform vec3 input_color = vec3(0.2, 0.3, 0.4);
uniform vec2 iris_uv = vec2(0.0);
uniform float pupil = 0.15;
uniform float derivative_x = 0.2;
uniform float distance_m = 7.62;
void fragment() {
	COLOR = vec4(source_eye_distance_color(input_color, iris_uv, pupil, derivative_x, distance_m), 1.0);
}
