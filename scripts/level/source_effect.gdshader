shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask2 : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask3 : filter_linear_mipmap, repeat_enable;
uniform vec2 mask1_scale = vec2(1.0);
uniform vec2 mask2_scale = vec2(1.0);
uniform vec2 mask3_scale = vec2(1.0);
uniform vec2 mask1_pan = vec2(0.0);
uniform vec2 mask2_pan = vec2(0.0);
uniform vec2 mask3_pan = vec2(0.0);
uniform float opacity = 1.0;

void fragment() {
	vec4 color = texture(color_texture, UV);
	float masks = texture(mask1, UV * mask1_scale + TIME * mask1_pan).r;
	masks *= texture(mask2, UV * mask2_scale + TIME * mask2_pan).r;
	masks *= texture(mask3, UV * mask3_scale + TIME * mask3_pan).r;
	ALBEDO = color.rgb * COLOR.rgb;
	ALPHA = clamp(color.a * masks * COLOR.a * opacity, 0.0, 1.0);
}
