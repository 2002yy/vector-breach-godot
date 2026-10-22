// Godot a13da4feb Forward+ normal-map stage: preserve interpolated Mikk TBN
// lengths and apply depth as a vector blend, not an XY-strength rescale.
vec3 source_mapped_normal(vec3 encoded,float depth,vec3 tangent,vec3 bitangent,vec3 normal) {
	vec2 xy=encoded.xy*2.0-1.0;
	float z=sqrt(max(1.0-dot(xy,xy),0.0));
	vec3 mapped=tangent*xy.x+bitangent*xy.y+normal*z;
	vec3 value=mix(normal,mapped,depth);
	vec3 fallback=dot(normal,normal)>1e-12 ? normalize(normal) : vec3(0,0,1);
	return dot(value,value)>1e-12 ? normalize(value) : fallback;
}
