// Blurs a CanvasGroup's contents (the opening sequence's "LAST LIGHT" resolving from blur).
// Needs CanvasGroup.use_mipmaps; blur_lod 0 is a plain copy.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// In mip levels at the 1920 x 1080 base; the screen is drawn at the window's real size, so as
// many more levels as that is larger (ui_scale) keep the blur the same width on screen
uniform float blur_lod = 0.0;

varying float ui_scale;

void vertex() {
	ui_scale = length(CANVAS_MATRIX[0].xy);
}

void fragment() {
	// (the extra levels fade in over the first level, so the blur resolves to a sharp copy smoothly)
	float lod = blur_lod + log2(max(ui_scale, 1.0)) * clamp(blur_lod, 0.0, 1.0);
	vec4 c = textureLod(screen_texture, SCREEN_UV, lod);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	COLOR *= c;
}
