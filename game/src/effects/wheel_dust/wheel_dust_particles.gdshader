shader_type particles;
// Lunar dust thrown by one wheel (WheelDust sets the uniforms every frame). No air: every grain
// flies an exact parabola under the level's gravity (no drag, no turbulence, no growth, no fading
// in the air) and stops where it lands. One material per wheel.
//
// Release: soil sticks to the tread at the contact patch and is carried up the back of the wheel
// (the side the tread leaves the ground on), coming off between release_min and release_max
// degrees up from the bottom. It leaves with a fraction of the tread's own velocity there (the
// hub's velocity plus the spin's), so a rolling wheel throws it up and a little forwards over the
// ground (the cycloid: the rover drives on and leaves it behind, the rooster tail), and a slipping
// wheel throws it back. No grain leaves faster than speed_cap.
//
// Landing: the GPUParticlesCollisionHeightField3D (WheelDust.add_ground_collider) sees only the
// dusty ground's render layer; a falling grain that reaches it is put on it, stops, and fades into
// the ground over settle_time.
render_mode disable_velocity, disable_force;

uniform vec3 gravity = vec3(0.0, -1.62, 0.0);
// The wheel, world space
uniform vec3 hub_position;
uniform vec3 hub_velocity;
uniform vec3 axle = vec3(1.0, 0.0, 0.0);      // unit, along the wheel's axle
uniform vec3 wheel_up = vec3(0.0, 1.0, 0.0);  // unit, from the contact patch to the hub
uniform float radius = 0.15;
uniform float width = 0.24;
// rad/s about the axle, + = the bottom of the tread moving towards -forward
// (forward = cross(wheel_up, axle))
uniform float spin = 0.0;
uniform float release_min = 5.0;    // degrees up the back of the wheel from the bottom
uniform float release_max = 60.0;
uniform float speed_fraction_min = 0.3;
uniform float speed_fraction_max = 0.9;
uniform float spread = 0.12;        // sideways scatter, a fraction of the grain's speed
uniform float speed_cap = 4.0;      // m/s
// Fraction of the particle slots that start a grain as they come round (the spray rate): decided
// per grain, so the grains are spread evenly in time whatever the fraction
uniform float emit_ratio = 0.0;
// A particle is one small clump of grains, this big (m), drawn crisp and opaque; it never grows.
// The spray's density comes from their number, not from soft overlapping puffs (which read as smoke)
uniform float size_min = 0.003;
uniform float size_max = 0.008;
uniform float alpha = 1.0;
uniform float settle_time = 0.3;    // s from landing to gone

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
		vec3 forward = normalize(cross(wheel_up, axle));
		float turning = spin >= 0.0 ? 1.0 : -1.0;
		// The back of the wheel: where the tread climbs away from the ground
		vec3 back = -forward * turning;
		// Most soil drops off low on the wheel, a little rides higher
		float u = rand(seed);
		float theta = radians(mix(release_min, release_max, u * u));
		vec3 rim = radius * (-wheel_up * cos(theta) + back * sin(theta));
		vec3 tangent = back * cos(theta) + wheel_up * sin(theta);
		vec3 velocity = hub_velocity + tangent * abs(spin) * radius;
		velocity *= mix(speed_fraction_min, speed_fraction_max, rand(seed));
		float speed = length(velocity);
		velocity += axle * (rand(seed) * 2.0 - 1.0) * spread * speed;
		velocity += wheel_up * (rand(seed) * 2.0 - 1.0) * spread * 0.5 * speed;
		if (length(velocity) > speed_cap) {
			velocity *= speed_cap / length(velocity);
		}
		vec3 position = hub_position + rim + axle * (rand(seed) - 0.5) * width;
		// Spread over the frame, so a fast wheel doesn't leave clumps a frame apart
		position -= hub_velocity * rand(seed) * DELTA;
		VELOCITY = velocity;
		// Small grains far outnumber the large
		float s = rand(seed);
		float size = mix(size_min, size_max, s * s);
		// x: age (s), y: landed at (s, 0: in the air), z: size (m), w: 1 while it lives (the draw
		// pass draws nothing for any other slot)
		CUSTOM = vec4(0.0, 0.0, size, 1.0);
		COLOR = vec4(vec3(0.85 + 0.3 * rand(seed)), alpha);
		TRANSFORM = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(velocity, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(position, 1.0));
	}
}

void process() {
	CUSTOM.x += DELTA;
	if (CUSTOM.y <= 0.0) {
		// Only a falling grain can land (they start on the tread, millimetres from the ground)
		if (COLLIDED && dot(VELOCITY, gravity) > 0.0) {
			// On the ground: put it on the surface and stop it there
			TRANSFORM[3].xyz += COLLISION_NORMAL * COLLISION_DEPTH;
			VELOCITY = vec3(0.0);
			CUSTOM.y = CUSTOM.x;
		} else {
			// Exact ballistic step (no drag): the same parabola at any frame rate
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
	// The draw pass reads the velocity from the transform's second column (the streak)
	TRANSFORM[1] = vec4(VELOCITY, 0.0);
}
