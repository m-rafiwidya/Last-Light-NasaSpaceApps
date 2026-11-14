shader_type spatial;
// One clump of dust grains (WheelDust's draw pass, a 1 x 1 quad): a crisp dot facing the camera,
// stretched along the grain's velocity by how far it moves in streak_time (the particle shader
// puts the velocity in the transform's second column, the size in CUSTOM.z, and 1 in CUSTOM.w
// while the grain lives). Opaque with hashed alpha. A grain smaller than min_pixels on screen is
// drawn at min_pixels with its opacity lowered to keep its coverage, so distant spray thins out
// instead of flickering.
// Lit like a clump of regolith grains: the sun's light (its shadows included, so a grain in a
// crater's or the rover's shadow is dark) times its phase function, half the lit fraction a rough
// grain shows from where you look (a Lambert sphere: full with the sun behind you), half the
// forward scattering of fine dust (Henyey-Greenstein, forward_scatter; capped), so dust with the
// sun behind it glows against the sky as in the Apollo films; plus the level's faint fill. It
// casts no shadows.
render_mode cull_disabled, specular_disabled, skip_vertex_transform;

uniform vec3 albedo_color : source_color = vec3(0.47, 0.46, 0.44);
uniform float streak_time = 0.008;   // s
uniform float min_pixels = 1.2;
// Scales the grain's light to the regolith's (regolith.gdshader's Lommel-Seeliger law): a clump
// lit from behind you is then about 0.7 as bright as the flat ground under the Moon's 16.7 degree
// sun seen at a low angle (by that law, the clump's disc 0.5, that ground 0.74)
uniform float brightness = 2.2;
uniform float forward_scatter = 0.5;   // Henyey-Greenstein g
uniform float forward_cap = 6.0;
// The 3D view's height in pixels (WheelDust sets it every frame from its viewport)
uniform float viewport_height = 1080.0;

const float MAX_QUAD = 0.3;   // m

varying float coverage;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 velocity = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;
	float size = INSTANCE_CUSTOM.z;
	float depth = max(-centre.z, 0.001);
	// (the projection's y scale is negative here: the renderer flips y)
	float pixels_per_metre = abs(PROJECTION_MATRIX[1][1]) * viewport_height * 0.5 / depth;
	float grow = max(1.0, min_pixels / max(size * pixels_per_metre, 1e-4));
	float width = size * grow;
	vec2 along = velocity.xy;
	float streak = length(along) * streak_time;
	along = streak > 1e-5 ? along / length(along) : vec2(0.0, 1.0);
	float len = max(width, streak + width);
	// Never more than a hand's width, whatever the inputs
	width = min(width, MAX_QUAD);
	len = min(len, MAX_QUAD);
	vec2 across = vec2(-along.y, along.x);
	vec3 offset = vec3(across * VERTEX.x * width + along * VERTEX.y * len, 0.0);
	VERTEX = centre + offset;
	// Nothing for a slot without a living grain (CUSTOM.w: what's left in it isn't a grain and
	// could fill the screen), nor for a grain at or behind the near plane
	if (INSTANCE_CUSTOM.w < 0.5 || -centre.z < 0.05) {
		VERTEX = vec3(0.0);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
	// A grain drawn larger than it is keeps its light, so it is fainter (the streak is only for
	// reading the motion: it keeps the grain's opacity)
	coverage = min(1.0, (size * size) / (width * width));
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	// A hard-edged grain (smoke would be soft)
	float dot_shape = 1.0 - smoothstep(0.75, 1.0, length(d));
	ALBEDO = albedo_color * COLOR.rgb;
	ALPHA = COLOR.a * dot_shape * coverage;
	ALPHA_HASH_SCALE = 1.0;
}

void light() {
	float a = acos(clamp(dot(LIGHT, VIEW), -1.0, 1.0));
	float sphere = ((PI - a) * cos(a) + sin(a)) / PI;
	// Scattering angle from the sun's direction of travel: forward when the sun is behind the dust
	float mu = -dot(LIGHT, VIEW);
	float g = forward_scatter;
	float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);   // 4 pi times HG: 1 on average
	// Forward scattering for the sun only: local lights (the workshop's lamps cast no shadows) would
	// otherwise light grains behind a wall six times over
	float phase = LIGHT_IS_DIRECTIONAL ? 0.5 * sphere + 0.5 * min(hg, forward_cap) : 0.5 * sphere;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * phase * brightness / PI;
}
