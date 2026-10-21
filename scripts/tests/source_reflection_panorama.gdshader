shader_type canvas_item;
render_mode unshaded;
uniform samplerCubeArray native_reflection : filter_linear_mipmap;
uniform float cube_index = 0.0;
uniform float native_lod = 0.0;
void fragment() {
	float longitude = (UV.x - 0.5) * TAU;
	float latitude = (0.5 - UV.y) * PI;
	vec3 direction = vec3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude));
	vec3 hdr = textureLod(native_reflection, vec4(direction, cube_index), native_lod).rgb;
	// Display-only Reinhard view. The compressed input and HDR checks are untouched.
	COLOR = vec4(hdr / (vec3(1.0) + hdr), 1.0);
}
