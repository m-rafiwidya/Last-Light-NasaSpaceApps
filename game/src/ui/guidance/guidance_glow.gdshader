shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// UI_SPEC "text" (#ECE9E3): a neutral light, not amber
uniform vec4 color : source_color = vec4(0.925, 0.914, 0.890, 1.0);
uniform float strength = 0.6;

void fragment() {
	float pulse = 0.55 + 0.45 * sin(TIME * 4.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color.rgb * (0.25 + rim) * strength * pulse;
}
