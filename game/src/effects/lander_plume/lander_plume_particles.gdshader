shader_type particles;
// Regolith blown out by the lander's descent engine (LanderPlume sets the uniforms every frame).
// No air: grains leave the ground under the bell in a flat, fast radial sheet and fly exact
// parabolas under the level's gravity (no drag, no billowing, no fading in the air), then settle
// where they land, on the dust collision field (wheel_dust.gd add_ground_collider) or, past it,
// on ground_point / ground_normal (the plane fitted under the lander). Drawn by wheel_dust_grain.
render_mode disable_velocity, disable_force;

uniform vec3 gravity = vec3(0.0, -1.62, 0.0);
uniform vec3 centre;                         // the ground under the bell
uniform vec3 ground_point;
uniform vec3 ground_normal = vec3(0.0, 1.0, 0.0);
uniform float ring_min = 0.6;                // m from the centre, where grains are swept up
uniform float ring_max = 3.0;
uniform float speed_min = 8.0;               // m/s
uniform float speed_max = 26.0;
uniform float angle_min = 1.0;               // degrees above the ground
uniform float angle_max = 6.0;
uniform float emit_ratio = 0.0;
uniform float size_min = 0.015;
uniform float size_max = 0.05;
uniform float alpha = 1.0;
uniform float settle_time = 0.3;

uint hash_uint(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	return (x >> uint(16)) ^ x;
}

float rand(inout uint seed) {
	seed = hash_uint(seed);
	return float(seed % uint(65536)) / 65535.0;
}

void start() {
	uint seed = hash_uint(NUMBER + hash_uint(RANDOM_SEED));
	if (rand(seed) >= emit_ratio) {
		ACTIVE = false;
		CUSTOM = vec4(0.0);
	} else {
		vec3 n = normalize(ground_normal);
		vec3 a = normalize(cross(n, abs(n.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0)));
		vec3 b = cross(n, a);
		float phi = rand(seed) * TAU;
		vec3 out_dir = a * cos(phi) + b * sin(phi);
		float r = mix(ring_min, ring_max, sqrt(rand(seed)));
		float elevation = radians(mix(angle_min, angle_max, rand(seed)));
		// Fast grains far outnumber the slow near the bell; the sheet is thin
		float speed = mix(speed_min, speed_max, sqrt(rand(seed)));
		vec3 velocity = (out_dir * cos(elevation) + n * sin(elevation)) * speed;
		vec3 position = centre + out_dir * r + n * 0.02;
		position += velocity * rand(seed) * DELTA;
		VELOCITY = velocity;
		float s = rand(seed);
		CUSTOM = vec4(0.0, 0.0, mix(size_min, size_max, s * s), 1.0);
		COLOR = vec4(vec3(0.85 + 0.3 * rand(seed)), alpha);
		TRANSFORM = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(velocity, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(position, 1.0));
	}
}

void process() {
	CUSTOM.x += DELTA;
	if (CUSTOM.y <= 0.0) {
		bool falling = dot(VELOCITY, gravity) > 0.0;
		float below = dot(TRANSFORM[3].xyz - ground_point, ground_normal);
		if (falling && COLLIDED) {
			TRANSFORM[3].xyz += COLLISION_NORMAL * COLLISION_DEPTH;
			VELOCITY = vec3(0.0);
			CUSTOM.y = CUSTOM.x;
		} else if (falling && below <= 0.0) {
			TRANSFORM[3].xyz -= ground_normal * below;
			VELOCITY = vec3(0.0);
			CUSTOM.y = CUSTOM.x;
		} else {
			TRANSFORM[3].xyz += VELOCITY * DELTA + 0.5 * gravity * DELTA * DELTA;
			VELOCITY += gravity * DELTA;
		}
	} else {
		float settled = clamp((CUSTOM.x - CUSTOM.y) / settle_time, 0.0, 1.0);
		COLOR.a = alpha * (1.0 - settled);
		if (settled >= 1.0) {
			ACTIVE = false;
			CUSTOM.w = 0.0;
		}
	}
	TRANSFORM[1] = vec4(VELOCITY, 0.0);
}
