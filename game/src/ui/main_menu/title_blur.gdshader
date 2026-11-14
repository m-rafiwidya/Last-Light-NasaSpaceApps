// Blurs a CanvasGroup's contents (the opening sequence's "LAST LIGHT" resolving from blur).
// Needs CanvasGroup.use_mipmaps; blur_lod 0 is a plain copy.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod = 0.0;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, blur_lod);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	COLOR *= c;
}
