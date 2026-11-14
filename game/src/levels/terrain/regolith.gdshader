shader_type spatial;
render_mode specular_disabled;

// Lunar regolith, procedural (no photo textures: they have shadows baked in). Everything is in
// world space, so terrain chunks and rocks match. MoonTerrain sets the uniforms per tier.
// - Albedo: grey regolith mottled at about 120 m, 15 m and 2 m, brighter on steep slopes and
//   around fresh craters (freshness map from the terrain pipeline, play tier only).
// - Detail normals: noise bumps of 2 cm over 0.4 m and 4 mm over 0.08 m (a few degrees of tilt:
//   with the sun 9 degrees up, more turns half the ground black), fading out with distance.
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

varying vec3 world_position;
varying float sun_visible;
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

// Two rotated octaves per scale, so no grid shows
float noise2(vec2 p) {
	return 0.6 * value_noise(p) + 0.4 * value_noise(mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + 17.0);
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

	// Detail normals: the slope of the noise height field (finite differences), faded with distance
	float distance_fade = 1.0 - smoothstep(detail_fade_distance * 0.5, detail_fade_distance, length(VERTEX));
	if (distance_fade > 0.0) {
		float e = 0.02;
		vec2 q = p.xz;
		float h0 = noise2(q / 0.4) * 0.02 + noise2(q / 0.08) * 0.004;
		float hx = noise2((q + vec2(e, 0.0)) / 0.4) * 0.02 + noise2((q + vec2(e, 0.0)) / 0.08) * 0.004;
		float hz = noise2((q + vec2(0.0, e)) / 0.4) * 0.02 + noise2((q + vec2(0.0, e)) / 0.08) * 0.004;
		vec2 gradient = vec2(hx - h0, hz - h0) / e * detail_strength * distance_fade;
		vec3 bumped = normalize(world_normal - vec3(gradient.x, 0.0, gradient.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
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
	float horizon = LIGHT_IS_DIRECTIONAL ? sun_visible : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * horizon * lommel_seeliger * opposition / PI;
}
