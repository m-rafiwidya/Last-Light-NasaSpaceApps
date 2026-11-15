shader_type sky;

// The Moon's sky (LunarSky sets every uniform): black, with NASA's Deep Star Maps 2020 star
// panorama, the sun's disc and Earth as a sphere lit by the same sun (light 0, the level's
// DirectionalLight3D), so Earth's phase follows the sun.

// Star panorama: plate carree in equatorial coordinates, RA 0h at the centre, RA increasing to
// the left, north at the top (checked against Canopus, Avior and Polaris in the map itself)
uniform sampler2D star_map : filter_linear, repeat_enable;
// World direction -> equatorial (x towards RA 0h, z the north celestial pole)
uniform mat3 world_to_equatorial;
uniform float star_energy = 1.0;

// Sun disc radiance per unit of the light's energy; drawn at least this many radians across
uniform float sun_disc_energy = 40.0;
uniform float sun_min_angular_diameter = 0.00925;

// Earth: world direction of its centre, angular radius (radians), its north pole (world
// direction) and the longitude (radians) facing the observer; the map is plate carree with
// longitude 0 at the centre
uniform sampler2D earth_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 earth_direction = vec3(0.0, 0.07, -1.0);
uniform float earth_angular_radius = 0.0166;
uniform vec3 earth_north = vec3(0.0, -1.0, 0.0);
uniform float earth_facing_longitude = 0.35;
// Earth's albedo scale and the blue of the lit limb (its atmosphere seen edge-on)
uniform float earth_brightness = 1.0;
uniform vec3 earth_limb_color : source_color = vec3(0.35, 0.55, 1.0);


// Texture coordinate with no seam: a longitude-like coordinate's derivatives are taken from
// whichever of two branches is continuous here, so mipmapping doesn't draw a line at the wrap
vec4 sample_wrapped(sampler2D map, vec2 uv) {
	vec2 alt = vec2(fract(uv.x + 0.5) - 0.5, uv.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx_alt = dFdx(alt);
	vec2 dy_alt = dFdy(alt);
	if (abs(dx_alt.x) + abs(dy_alt.x) < abs(dx.x) + abs(dy.x)) {
		dx = dx_alt;
		dy = dy_alt;
	}
	return textureGrad(map, uv, dx, dy);
}


vec3 equatorial_of(vec2 uv) {
	float ra = (0.5 - uv.x) * 2.0 * PI;
	float dec = (0.5 - uv.y) * PI;
	return vec3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec));
}


// Under a long lens (several pixels per texel), instead of magnified soft squares: a texel
// brighter than its eight neighbours is a star, drawn as a point about a pixel across at the
// centroid of its 3 x 3 excess over their minimum, carrying all of it; the minimum, bilinear, is
// the background
vec3 point_stars(vec2 uv, vec3 e, float pixel) {
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	const float SIGMA = 0.9;
	const float GAIN = 1.5;
	ivec2 size = textureSize(star_map, 0);
	vec2 tc = uv * vec2(size) - 0.5;
	ivec2 base = ivec2(floor(tc)) - ivec2(1);
	vec2 f = fract(tc);
	vec3 block[16];
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			ivec2 c = ivec2((base.x + i + size.x) % size.x, clamp(base.y + j, 0, size.y - 1));
			block[j * 4 + i] = texelFetch(star_map, c, 0).rgb;
		}
	}
	vec3 floor_of[4];
	vec3 color = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		int ci = 1 + k % 2;
		int cj = 1 + k / 2;
		vec3 centre = block[cj * 4 + ci];
		vec3 low = centre;
		bool peak = true;
		for (int dj = -1; dj <= 1; dj++) {
			for (int di = -1; di <= 1; di++) {
				vec3 v = block[(cj + dj) * 4 + ci + di];
				low = min(low, v);
				peak = peak && dot(v, LUMA) <= dot(centre, LUMA);
			}
		}
		floor_of[k] = low;
		if (!peak) {
			continue;
		}
		vec3 flux = vec3(0.0);
		vec2 centroid = vec2(0.0);
		float weight = 0.0;
		for (int dj = -1; dj <= 1; dj++) {
			for (int di = -1; di <= 1; di++) {
				vec3 excess = block[(cj + dj) * 4 + ci + di] - low;
				flux += excess;
				centroid += vec2(float(di), float(dj)) * dot(excess, LUMA);
				weight += dot(excess, LUMA);
			}
		}
		if (weight <= 0.0) {
			continue;
		}
		vec2 spot = (vec2(base + ivec2(ci, cj)) + 0.5 + centroid / weight) / vec2(size);
		float d = length(e - equatorial_of(spot)) / pixel;
		color += flux * GAIN * exp(-d * d / (2.0 * SIGMA * SIGMA));
	}
	color += mix(mix(floor_of[0], floor_of[1], f.x), mix(floor_of[2], floor_of[3], f.x), f.y);
	return color;
}


vec3 stars(vec3 dir) {
	vec3 e = world_to_equatorial * dir;
	float ra = atan(e.y, e.x);
	float dec = asin(clamp(e.z, -1.0, 1.0));
	vec2 uv = vec2(fract(0.5 - ra / (2.0 * PI)), 0.5 - dec / PI);
	// The 4k map is about one texel per pixel at the players' fields of view (60 degrees and up):
	// no mips needed. Narrower views (the mast zoom, the opening's long lens) draw point stars.
	vec3 smooth_stars = textureLod(star_map, uv, 0.0).rgb;
	float pixel = max(max(length(dFdx(dir)), length(dFdy(dir))), 1e-7);
	float pixels_per_texel = PI / float(textureSize(star_map, 0).y) / pixel;
	float sharp = smoothstep(1.65, 2.4, pixels_per_texel);
	if (sharp > 0.0) {
		smooth_stars = mix(smooth_stars, point_stars(uv, e, pixel), sharp);
	}
	return smooth_stars * star_energy;
}


// Earth's colour and coverage (0..1, antialiased edge) along dir
vec4 earth(vec3 dir) {
	vec3 c = normalize(earth_direction);
	float angle = acos(clamp(dot(dir, c), -1.0, 1.0));
	float pixel = max(fwidth(angle), 1e-6);
	float coverage = clamp((earth_angular_radius - angle) / pixel + 0.5, 0.0, 1.0);
	if (coverage <= 0.0) {
		return vec4(0.0);
	}
	// The ray from the eye (unit distance from Earth's centre) hits the sphere of radius
	// sin(angular radius); just past the limb, use the limb
	float r = sin(earth_angular_radius);
	float along = dot(dir, c);
	float off2 = min(1.0 - along * along, r * r);
	vec3 n = normalize(dir * (along - sqrt(r * r - off2)) - c);

	vec3 north = normalize(earth_north - dot(earth_north, c) * c);
	// Towards the observer, in Earth's equatorial plane; east is north x that
	vec3 facing = -c - dot(-c, north) * north;
	facing = length(facing) > 1e-4 ? normalize(facing) : normalize(cross(north, vec3(1.0, 0.0, 0.0)));
	vec3 east = cross(north, facing);
	float longitude = earth_facing_longitude + atan(dot(n, east), dot(n, facing));
	float latitude = asin(clamp(dot(n, north), -1.0, 1.0));
	vec2 uv = vec2(fract(longitude / (2.0 * PI) + 0.5), 0.5 - latitude / PI);
	vec3 albedo = sample_wrapped(earth_map, uv).rgb * earth_brightness;

	vec3 light = vec3(0.0);
	if (LIGHT0_ENABLED) {
		float lit = max(dot(n, LIGHT0_DIRECTION), 0.0);
		// The atmosphere seen edge-on: a thin blue rim on the lit side
		float limb = pow(1.0 - max(dot(n, -dir), 0.0), 3.0);
		light = LIGHT0_COLOR * LIGHT0_ENERGY * (albedo * lit + earth_limb_color * limb * sqrt(lit) * 0.25);
	}
	return vec4(light, coverage);
}


vec3 sun_disc(vec3 dir) {
	if (!LIGHT0_ENABLED) {
		return vec3(0.0);
	}
	float radius = max(LIGHT0_SIZE, sun_min_angular_diameter) * 0.5;
	float angle = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
	float pixel = max(fwidth(angle), 1e-6);
	float coverage = clamp((radius - angle) / pixel + 0.5, 0.0, 1.0);
	// Slight limb darkening
	float mu = sqrt(max(1.0 - pow(min(angle / radius, 1.0), 2.0), 0.0));
	return LIGHT0_COLOR * LIGHT0_ENERGY * sun_disc_energy * (0.6 + 0.4 * mu) * coverage;
}


void sky() {
	vec3 color = stars(EYEDIR);
	vec4 planet = earth(EYEDIR);
	color = mix(color, planet.rgb, planet.a);
	color += sun_disc(EYEDIR);
	COLOR = color;
}
