// Native-origin parallax box direction (VRF environment.slang). Source axes.
vec4 source_reflection_box(vec3 position, vec3 ray, vec4 origin_yaw, vec3 minimum, vec3 size) {
	float c = cos(origin_yaw.w), s = sin(origin_yaw.w);
	vec3 delta = position - origin_yaw.xyz;
	vec3 local = vec3(c * delta.x + s * delta.y, -s * delta.x + c * delta.y, delta.z);
	vec3 direction = vec3(c * ray.x + s * ray.y, -s * ray.x + c * ray.y, ray.z);
	vec3 maximum = minimum + size;
	if (any(lessThan(local, minimum - vec3(0.02))) || any(greaterThan(local, maximum + vec3(0.02)))) {
		return vec4(0.0);
	}
	float distance_to_box = 1e30;
	bool nonzero = false;
	for (int axis = 0; axis < 3; axis++) {
		if (abs(direction[axis]) > 1e-12) {
			nonzero = true;
			distance_to_box = min(distance_to_box, max((minimum[axis] - local[axis]) / direction[axis],
				(maximum[axis] - local[axis]) / direction[axis]));
		}
	}
	vec3 projected = local + direction * abs(distance_to_box);
	if (!nonzero || dot(projected, projected) <= 1e-24) { return vec4(0.0); }
	return vec4(normalize(projected), 1.0);
}
