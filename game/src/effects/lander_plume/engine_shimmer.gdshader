shader_type spatial;
// Hot exhaust just under the descent engine's bell: a faint refraction of what is behind it,
// strongest across the cone's middle, gone at its rim and ends. Lander sets intensity (0: off).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float intensity = 0.0;
uniform float strength = 0.006;

void fragment() {
	float rim = pow(abs(dot(NORMAL, VIEW)), 1.5);
	float ends = sin(clamp(UV.y, 0.0, 1.0) * PI);
	float t = TIME;
	vec2 wobble = vec2(sin(UV.y * 38.0 - t * 31.0 + UV.x * 25.0), cos(UV.y * 29.0 - t * 23.0 - UV.x * 19.0));
	float amount = intensity * rim * ends;
	ALBEDO = texture(screen, SCREEN_UV + wobble * strength * amount).rgb;
	ALPHA = clamp(amount * 0.8, 0.0, 1.0);
}
