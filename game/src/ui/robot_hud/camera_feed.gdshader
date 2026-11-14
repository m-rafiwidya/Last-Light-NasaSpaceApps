shader_type canvas_item;

// Full-screen camera-feed look for the rover's camera views (RoverFeedOverlay sets the uniforms per
// view). Reads what has been drawn so far (the 3D view: the overlay is the robot HUD's first
// item), so the HUD drawn after it stays untouched.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// 0 = colour, 1 = black and white
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float contrast = 1.0;
uniform vec3 tint = vec3(1.0);
// Barrel distortion; the corners stay in the corners, so the centre is magnified a little
uniform float fisheye = 0.0;
// Darkening towards the corners (0 = none, 1 = black corners)
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
// Blur towards the edges, in mip levels at the corners (shallow depth of field)
uniform float edge_blur = 0.0;
// Animated noise amplitude
uniform float grain = 0.0;

// Screen pixels per design pixel (the stretch scale): edge blur and grain keep their size on
// screen whatever the window's resolution
varying float ui_scale;

void vertex() {
	ui_scale = length(CANVAS_MATRIX[0].xy);
}

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 centred = SCREEN_UV - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// Distance from the centre in screen heights, squared; corner_r2 at the corners
	vec2 p = centred * vec2(aspect, 1.0);
	float r2 = dot(p, p);
	float corner_r2 = 0.25 * (aspect * aspect + 1.0);
	vec2 uv = 0.5 + centred * (1.0 + fisheye * r2) / (1.0 + fisheye * corner_r2);

	float edge = r2 / corner_r2;
	float blur = edge_blur * smoothstep(0.15, 1.0, edge);
	vec3 colour = textureLod(screen_texture, uv, blur + log2(max(ui_scale, 1.0)) * clamp(blur, 0.0, 1.0)).rgb;

	float luma = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(colour, vec3(luma), desaturate);
	colour = (colour - 0.5) * contrast + 0.5;
	colour *= tint;
	colour *= 1.0 - vignette * smoothstep(0.2, 1.0, edge);
	colour += (hash(floor(FRAGCOORD.xy / (2.0 * ui_scale)) + fract(TIME * 7.13) * 97.0) - 0.5) * grain;

	COLOR = vec4(clamp(colour, 0.0, 1.0), 1.0);
}
