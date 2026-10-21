shader_type canvas_item;
uniform sampler3D probe_texture : filter_linear, repeat_disable;
uniform vec3 texture_dimensions;
uniform vec3 probe_origin;
uniform vec3 bounds_min;
uniform vec3 bounds_size;
uniform vec3 atlas_size;
uniform vec3 atlas_offset;
uniform float yaw_degrees;
uniform vec3 source_position;
uniform vec3 source_direction;

void fragment() {
	vec3 p = source_position - probe_origin;
	float angle = radians(yaw_degrees);
	float c = cos(angle);
	float s = sin(angle);
	p.xy = mat2(vec2(c,-s),vec2(s,c)) * p.xy;
	vec3 local_coord = (p - bounds_min) / bounds_size;
	vec3 dims = texture_dimensions * vec3(1.0,1.0,1.0/6.0);
	vec3 coords = clamp(local_coord, vec3(0.5) / dims, (dims-vec3(0.5)) / dims);
	coords = (coords * atlas_size + atlas_offset) / dims;
	coords.z /= 6.0;
	vec3 direction = normalize(source_direction);
	vec3 face = mix(vec3(0.0,1.0,2.0),vec3(3.0,4.0,5.0),step(direction,vec3(0.0))) / 6.0;
	vec3 color = textureLod(probe_texture,coords+vec3(0,0,face.x),0.0).rgb * direction.x*direction.x;
	color += textureLod(probe_texture,coords+vec3(0,0,face.y),0.0).rgb * direction.y*direction.y;
	color += textureLod(probe_texture,coords+vec3(0,0,face.z),0.0).rgb * direction.z*direction.z;
	COLOR = vec4(color,1.0);
}
