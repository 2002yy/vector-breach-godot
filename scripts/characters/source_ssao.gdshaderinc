// Material AO is already applied inside native energy math.
// Apply only to candidate indirect light, never original emission or direct light.
uniform sampler2D source_ssao_texture : filter_linear, repeat_disable;
uniform bool source_ssao_enabled = false;
float source_screen_occlusion(vec2 screen_uv) {
	return source_ssao_enabled ? clamp(textureLod(source_ssao_texture,screen_uv,0.0).r,0.0,1.0) : 1.0;
}
