shader_type spatial;
render_mode specular_disabled;

// Lunar regolith, procedural (no photo textures: they have shadows baked in). Everything is in
// world space, so terrain chunks and rocks match. MoonTerrain sets the uniforms per tier.
// - Albedo: grey regolith mottled at about 120 m, 15 m and 2 m, brighter on steep slopes and
//   around fresh craters (freshness map from the terrain pipeline, play tier only).
// - Detail relief below the mesh's 1 m: the terrain pipeline's roughness spectrum (Hurst 0.9, 3
//   degrees RMS slope from 10 m to 1 m) carried on down to 3 cm, as four value-noise octaves fitted
//   to its bands (5.5 mm RMS height, 5.3 degrees RMS slope in all). Drawn through its normals and
//   its own shadows (a short march of the height field towards the sun), each octave filtered out
//   where it is finer than the pixel, all of it faded out with distance.
// - Light: Lommel-Seeliger with a mild opposition surge instead of Lambert (regolith doesn't darken
//   towards grazing light, and brightens with the sun behind you), no specular. The sun (the
//   directional light) is dimmed where the baked horizon map says terrain beyond the shadow
//   cascades' 500 m hides it: horizon elevation per texel at 16 azimuths, the first one the sun's.
//   Local lights (the helmet light, headlights) lit from nearly where you look from use the smooth
//   surface normal instead of the detail normals (shadow hiding: regolith shows no relief lit from
//   behind you); the detail normals that face away from both the light and the eye otherwise
//   speckled the far edge of a helmet light's pool black.

uniform vec3 albedo_color : source_color = vec3(0.47, 0.46, 0.44);
uniform float albedo_variation = 0.18;
uniform float slope_brightening = 0.25;
uniform float detail_strength = 1.0;
uniform float detail_fade_distance = 60.0;
uniform float opposition_strength = 0.5;
uniform float opposition_width = 0.08;

// Horizon map: 4 RGBA textures (azimuths 4k..4k+3), each covering [-half, half] in X and Z
uniform sampler2D horizon_0 : filter_linear, repeat_disable;
uniform sampler2D horizon_1 : filter_linear, repeat_disable;
uniform sampler2D horizon_2 : filter_linear, repeat_disable;
uniform sampler2D horizon_3 : filter_linear, repeat_disable;
uniform float horizon_half = 512.0;
uniform float horizon_size = 513.0;
uniform float horizon_first_azimuth = 0.0;     // degrees
uniform float horizon_min = -10.0;             // byte 0
uniform float horizon_range = 60.0;            // byte 255
uniform bool use_horizon = true;
// The sun's direction (towards it, world space) and angular radius (radians)
uniform vec3 sun_direction = vec3(0.0, 0.156, -0.988);
uniform float sun_radius = 0.0046;

uniform sampler2D freshness : filter_linear, repeat_disable, hint_default_black;
uniform bool use_freshness = false;
uniform float freshness_half = 512.0;
uniform float freshness_brightening = 0.35;

// Detail relief: the noise period (m) and amplitude (m) of each octave, each fitted to the RMS height
// and RMS slope of one octave band of the pipeline's spectrum (1-0.5, 0.5-0.25, 0.25-0.125 and
// 0.125-0.03 m: 4.7, 2.5, 1.3 and 0.8 mm; 2.3-2.6 degrees each). A single octave of 2 cm bumps every
// 0.4 m, as before, was 2.4 times the spectrum's height at that size and carried all the slope: with
// a low sun every shadow came out the same 0.4 m blob
const vec4 DETAIL_PERIODS = vec4(0.3, 0.15, 0.075, 0.0375);
const vec4 DETAIL_AMPLITUDES = vec4(0.011, 0.0058, 0.003, 0.0019);
// Each octave's turn (cos, sin of 0, 37, 74 and 111 degrees), so their lattices don't line up
const vec4 DETAIL_COS = vec4(1.0, 0.79864, 0.27564, -0.35837);
const vec4 DETAIL_SIN = vec4(0.0, 0.60182, 0.96126, 0.93358);
// The march towards the sun for the relief's own shadows: 10 steps from 6 mm growing to 0.7 m (its
// tallest rises shade about that far at 2 degrees), stopped once the sun is fully hidden, skipped
// where the sun is above any slope the relief has or the terrain's horizon already hides it.
// Against an exact trace (sun 2.1 degrees up) it finds 47% of the ground in shadow against 51%,
// and agrees on 96% of it; 5 degrees: 13.6 / 15%; 9 degrees: 1 / 1%. 16 steps (49%) cost 3-4 ms
// a frame more than the old normals-only relief
const int DETAIL_SHADOW_STEPS = 10;
const float DETAIL_SHADOW_FIRST = 0.006;
const float DETAIL_SHADOW_GROWTH = 1.7;
const float DETAIL_MAX_SLOPE = 0.35;

varying vec3 world_position;
varying float sun_visible;
// The share of the sun the detail relief leaves on this pixel (its own shadows)
varying float detail_sun;
// The surface normal before the detail normals (view space), for local lights
varying vec3 smooth_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

// Value noise and its gradient (d/dp.x, d/dp.y)
vec3 value_noise_gradient(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float value = a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
	vec2 gradient = du * vec2(b - a + (a - b - c + d) * u.y, c - a + (a - b - c + d) * u.x);
	return vec3(value * 2.0 - 1.0, gradient * 2.0);
}

// Two rotated octaves per scale, so no grid shows
float noise2(vec2 p) {
	return 0.6 * value_noise(p) + 0.4 * value_noise(mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + 17.0);
}

// Octave k's lattice coordinates at q (turned and offset)
vec2 detail_lattice(vec2 q, int k) {
	vec2 r = vec2(DETAIL_COS[k] * q.x - DETAIL_SIN[k] * q.y, DETAIL_SIN[k] * q.x + DETAIL_COS[k] * q.y);
	return r / DETAIL_PERIODS[k] + float(k) * 17.0;
}

// Detail height (m) at q, each octave weighted by w (0 leaves it out)
float detail_height(vec2 q, vec4 w) {
	float h = 0.0;
	for (int k = 0; k < 4; k++) {
		if (w[k] > 0.0) {
			h += value_noise(detail_lattice(q, k)) * DETAIL_AMPLITUDES[k] * w[k];
		}
	}
	return h;
}

// Detail height (m) and its gradient (per m of x, z) at q, in one pass
vec3 detail_height_gradient(vec2 q, vec4 w) {
	vec3 h = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		if (w[k] > 0.0) {
			vec3 n = value_noise_gradient(detail_lattice(q, k)) * DETAIL_AMPLITUDES[k] * w[k];
			// Back from the turned lattice to x, z
			vec2 g = n.yz / DETAIL_PERIODS[k];
			h += vec3(n.x, DETAIL_COS[k] * g.x + DETAIL_SIN[k] * g.y, -DETAIL_SIN[k] * g.x + DETAIL_COS[k] * g.y);
		}
	}
	return h;
}

// How much of the sun's disc clears the detail relief towards it (horizon mapping of the height
// field): with the sun below the relief's slopes its normals alone only darken the slopes facing
// away, and leave lit the ground in their shadow; marched, each rise shades the ground downsun of
// it as a real shadow does. On average the relief's lit slopes make up for its shadows (rough
// ground catches the sun's light like the flat ground under it), so once it is filtered out with
// distance nothing needs darkening in its place
float detail_sun_visible(vec2 q, float h0, vec4 w, vec3 n) {
	float sin_elevation = dot(sun_direction, n);
	if (sin_elevation <= 0.0) {
		return 1.0;   // the smooth surface faces away: its own light term is already zero
	}
	vec3 along = sun_direction - n * sin_elevation;   // towards the sun, in the surface
	float cos_elevation = length(along);
	if (cos_elevation < 1e-4 || sin_elevation / cos_elevation > DETAIL_MAX_SLOPE) {
		return 1.0;
	}
	float tan_elevation = sin_elevation / cos_elevation;
	vec2 direction = along.xz / cos_elevation;
	float hidden = tan_elevation + sun_radius;   // a rise this steep hides the whole disc
	float steepest = -1.0;
	float d = DETAIL_SHADOW_FIRST;
	for (int i = 0; i < DETAIL_SHADOW_STEPS && steepest < hidden; i++) {
		steepest = max(steepest, (detail_height(q + direction * d, w) - h0) / d);
		d *= DETAIL_SHADOW_GROWTH;
	}
	return clamp((tan_elevation - steepest) / (2.0 * sun_radius) + 0.5, 0.0, 1.0);
}

float horizon_channel(int k, vec2 uv) {
	int file = k / 4;
	int channel = k % 4;
	vec4 v = file == 0 ? texture(horizon_0, uv) : file == 1 ? texture(horizon_1, uv) : file == 2 ? texture(horizon_2, uv) : texture(horizon_3, uv);
	return horizon_min + v[channel] * horizon_range;
}

// 1 where the sun clears the horizon, 0 where terrain hides it, soft over the sun's disc
float sun_above_horizon(vec3 p) {
	if (!use_horizon) {
		return 1.0;
	}
	vec2 uv = (p.xz + horizon_half) / (2.0 * horizon_half);
	uv = uv * (horizon_size - 1.0) / horizon_size + 0.5 / horizon_size;
	float azimuth = degrees(atan(sun_direction.x, -sun_direction.z));
	float k = mod(azimuth - horizon_first_azimuth, 360.0) / 22.5;
	int k0 = int(floor(k)) % 16;
	int k1 = (k0 + 1) % 16;
	float horizon = mix(horizon_channel(k0, uv), horizon_channel(k1, uv), fract(k));
	float elevation = degrees(asin(clamp(sun_direction.y, -1.0, 1.0)));
	return clamp((elevation - horizon) / degrees(2.0 * sun_radius) + 0.5, 0.0, 1.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sun_visible = sun_above_horizon(world_position);
}

void fragment() {
	vec3 p = world_position;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	smooth_normal = NORMAL;

	// Albedo
	float mottle = noise2(p.xz / 120.0) * 0.5 + noise2(p.xz / 15.0) * 0.3 + noise2(p.xz / 2.0) * 0.2;
	vec3 albedo = albedo_color * (1.0 + albedo_variation * mottle);
	albedo *= 1.0 + slope_brightening * smoothstep(0.9, 0.6, world_normal.y);
	if (use_freshness) {
		vec2 fuv = (p.xz + freshness_half) / (2.0 * freshness_half);
		float fresh = max(texture(freshness, fuv).r * 2.0 - 1.0, 0.0);
		albedo *= 1.0 + freshness_brightening * fresh;
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;

	// Detail relief: faded with distance and, per octave, where it is finer than the pixel (there
	// it would only alias into flicker). The pixel's size on the ground is the square root of its
	// footprint's area: at grazing angles the footprint's long side, along the line of sight, would
	// drop the relief 15 m away while it is still sharp across it. Faded over a wide range, so the
	// shadows thin out with distance rather than stop
	detail_sun = 1.0;
	float distance_fade = 1.0 - smoothstep(detail_fade_distance * 0.5, detail_fade_distance, length(VERTEX));
	if (distance_fade > 0.0) {
		float footprint = sqrt(abs(determinant(mat2(dFdx(p.xz), dFdy(p.xz)))));
		vec4 w = vec4(1.0) - smoothstep(DETAIL_PERIODS * 0.15, DETAIL_PERIODS * 0.6, vec4(footprint));
		w *= detail_strength * distance_fade;
		vec2 q = p.xz;
		vec3 h = detail_height_gradient(q, w);
		vec3 bumped = normalize(world_normal - vec3(h.y, 0.0, h.z));
		NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
		if (sun_visible > 0.0) {
			detail_sun = mix(1.0, detail_sun_visible(q, h.x, w, world_normal), smoothstep(0.5, 0.8, world_normal.y));
		}
	}
}

void light() {
	vec3 n = NORMAL;
	if (!LIGHT_IS_DIRECTIONAL) {
		// Smooth normal within about 2 degrees of the view direction, detail normals past 20
		n = normalize(mix(NORMAL, smooth_normal, smoothstep(0.94, 0.9994, dot(LIGHT, VIEW))));
	}
	float mu0 = max(dot(n, LIGHT), 0.0);
	float mu = max(dot(n, VIEW), 0.05);
	// Lommel-Seeliger, scaled to match Lambert looking straight down
	float lommel_seeliger = 2.0 * mu0 / (mu0 + mu);
	float phase = acos(clamp(dot(LIGHT, VIEW), -1.0, 1.0));
	float opposition = 1.0 + opposition_strength / (1.0 + tan(phase * 0.5) / opposition_width);
	float horizon = LIGHT_IS_DIRECTIONAL ? sun_visible * detail_sun : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * horizon * lommel_seeliger * opposition / PI;
}
