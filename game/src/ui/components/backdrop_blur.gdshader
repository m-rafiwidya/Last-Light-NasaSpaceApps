// Blurs and dims everything drawn before it (docs/ui/UI_SPEC.md "Motion": popups open with the
// menu behind blurring about 10 px and dimming to ~45 %). Put it on a full-screen ColorRect and
// tween `amount` 0 -> 1.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// Blur radius in screen pixels at amount 1 (10 design px x 1.2)
uniform float radius_px = 12.0;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// What is left of the picture behind at amount 1 (mixed towards bg_color)
uniform float brightness : hint_range(0.0, 1.0) = 0.45;
uniform vec4 bg_color : source_color = vec4(0.0196, 0.0196, 0.0275, 1.0);

const int TAPS = 16;

void fragment() {
	float r = radius_px * amount;
	// Each tap reads a mip about as wide as the gap between taps, so 16 taps look smooth
	float lod = log2(max(r * 0.5, 1.0));
	vec3 sum = vec3(0.0);
	float weights = 0.0;
	for (int i = 0; i < TAPS; i++) {
		float t = (float(i) + 0.5) / float(TAPS);
		float a = float(i) * 2.39996;   // golden angle: an even spiral of taps
		vec2 offset = vec2(cos(a), sin(a)) * sqrt(t) * r;
		float w = exp(-2.0 * t);
		sum += textureLod(screen_texture, SCREEN_UV + offset * SCREEN_PIXEL_SIZE, lod).rgb * w;
		weights += w;
	}
	vec3 c = sum / weights;
	COLOR = vec4(mix(c, mix(bg_color.rgb, c, brightness), amount), 1.0);
}
