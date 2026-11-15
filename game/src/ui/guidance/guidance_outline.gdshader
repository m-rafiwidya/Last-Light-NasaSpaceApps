shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

// UI_SPEC "text" (#ECE9E3): a neutral light, not amber
uniform vec4 color : source_color = vec4(0.925, 0.914, 0.890, 1.0);
uniform float width = 0.012;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb * (0.7 + 0.3 * sin(TIME * 4.0));
}
