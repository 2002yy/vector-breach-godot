shader_type canvas_item;
render_mode unshaded;
uniform samplerCubeArray native_reflection : filter_nearest_mipmap;
uniform sampler2D cases : filter_nearest;
void fragment() {
	int column = int(FRAGCOORD.x);
	vec4 ray = texelFetch(cases, ivec2(column, 0), 0);
	float lod = texelFetch(cases, ivec2(column, 1), 0).r;
	COLOR = vec4(textureLod(native_reflection, ray, lod).rgb, 1.0);
}
